import Foundation
import Speech
import AVFoundation

/// Wraps SFSpeechRecognizer + AVAudioEngine for continuous speech tracking.
/// iOS ends recognition tasks periodically (roughly every minute); this
/// transparently restarts the engine on that benign case so listening feels
/// continuous. Genuine errors are surfaced via `errorMessage` instead of
/// being silently retried forever.
final class SpeechTracker: NSObject, ObservableObject {
    @Published var errorMessage: String?
    @Published var isListening = false

    var onTranscript: (([String]) -> Void)?

    /// Rebuilt whenever the reader changes language, so this is a `var` and
    /// the identifier is supplied at `begin` rather than fixed at init.
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: SpeechLocales.fallback))
    private var localeIdentifier = SpeechLocales.fallback
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var shouldRun = false
    private var receivedAnyResult = false
    private var delta = TranscriptDeltaTracker()
    /// Whether a tap is installed on the engine's input node. Guards
    /// `stopEngine` from touching `audioEngine.inputNode` when no tap was ever
    /// installed — accessing the node lazily initialises it (an AURemoteIO RPC
    /// to the audio server), which times out and aborts on a host whose audio
    /// server does not answer, e.g. the CI virtual Mac.
    private var tapInstalled = false
    private var interruptionObserver: NSObjectProtocol?
    /// Set when iOS takes the microphone away mid-take (a call, Siri, an
    /// alarm). Listening stops, but the take is not abandoned — the engine
    /// restarts by itself once the interruption ends.
    private var interrupted = false
    /// How the next recognition request will be configured.
    ///
    /// On-device is tried first because it keeps the audio on the phone and
    /// is an order of magnitude quicker — roughly 30-50ms against 300-800ms.
    /// But `supportsOnDeviceRecognition` can return `true` on a device that
    /// then refuses every on-device request, so a single flag was not enough:
    /// it latched to server-based for the whole session after one failure,
    /// and a phone whose on-device dictation demonstrably works (Notes, in
    /// Airplane Mode) spent every take on the slow path.
    ///
    /// So the failure path is a ladder rather than a latch. Each rung drops
    /// one thing that might be the obstacle. `contextualStrings` goes first
    /// because it is the request's only unusual ingredient and the likeliest
    /// thing an on-device model refuses.
    ///
    /// The last rung is Apple's server-based speech recognition. It keeps
    /// languages with no on-device model here (Catalan, Czech…) working, and
    /// the reader is told when a take uses it, since it needs a network and
    /// sends the audio to Apple.
    enum Stage: String {
        case onDeviceWithContext
        case onDeviceNoContext
        case server

        var next: Stage? {
            switch self {
            case .onDeviceWithContext: return .onDeviceNoContext
            case .onDeviceNoContext: return .server
            case .server: return nil
            }
        }

        var isOnDevice: Bool { self != .server }
        var usesContextualStrings: Bool { self != .onDeviceNoContext }
    }

    /// The phrases the voice commands listen for, offered to either engine.
    static let commandPhrases = ["scroll up", "scroll down", "scroll back", "go back", "go on"]

    /// Something the reader should know that is not a failure: this take
    /// uses Apple's server-based speech recognition.
    @Published var noticeMessage: String?
    /// Which engine the take is using, for the DEBUG A/B switch and logs.
    @Published private(set) var usingAnalyzer = false
    /// The engine and path the take is running on, e.g. "New (SpeechAnalyzer)"
    /// or "Classic, server". Changes only when that changes, not on the
    /// per-minute task restart, so the DEBUG banner shows once per switch.
    @Published private(set) var engineDescription: String?

    /// DEBUG A/B switch: `true` keeps every take on `SFSpeechRecognizer`.
    static let classicEngineKey = "debugClassicSpeechEngine"
    /// The switch is DEBUG-only; a release build always picks the best engine.
    static var forcesClassicEngine: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: classicEngineKey)
        #else
        return false
        #endif
    }

    /// The iOS 26 engine, as `AnyObject` so this class still builds for iOS 16.
    private var analyzerEngine: AnyObject?
    /// Set when the analyzer failed this take, so the restart uses the classic
    /// engine instead of failing the same way again.
    private var analyzerFailedThisTake = false
    /// Whether this take already said it is using the server. iOS restarts
    /// the recognition task about every minute; the notice should not.
    private var announcedServer = false

    private var stage: Stage = .onDeviceWithContext
    /// Called once the shared audio session has been configured and activated
    /// for this run — or has failed to be. Anything that needs the microphone
    /// must wait for it: `AVCaptureMovieFileOutput` started against an
    /// inactive session records **no audio at all**, silently, for the whole
    /// file, and the take is gone by the time anyone plays it back.
    ///
    /// Fires on failure too. Recognition being unavailable is not a reason to
    /// refuse to record, and the caller would otherwise wait forever.
    private var audioSessionSettled: (() -> Void)?
    /// Bumped by every start and by `end()`, so a session configuration in
    /// flight can tell it has been superseded before it resumes on main — a
    /// take ended, or restarted, while it was still configuring.
    private var startGeneration = 0

    /// Requests speech-recognition and microphone permission before starting
    /// the engine. Without an explicit SFSpeechRecognizer authorization
    /// request the status stays `.notDetermined` and every recognition task
    /// fails immediately and silently — iOS never prompts on its own.
    /// - Parameter localeIdentifier: the language to listen in. Rebuilding
    ///   the recogniser is cheap and only happens when it actually changes,
    ///   so this is safe to pass on every start.
    func begin(
        localeIdentifier: String = SpeechLocales.fallback,
        whenAudioSessionSettled settled: (() -> Void)? = nil
    ) {
        audioSessionSettled = settled
        if localeIdentifier != self.localeIdentifier || recognizer == nil {
            self.localeIdentifier = localeIdentifier
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        shouldRun = true
        stage = .onDeviceWithContext
        analyzerFailedThisTake = false
        announcedServer = false
        engineDescription = nil
        observeInterruptions()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.shouldRun else { return }
                guard status == .authorized else {
                    self.errorMessage = String(localized: "Speech recognition permission was denied. Enable it in Settings → Privacy & Security → Speech Recognition → On Cue.")
                    self.isListening = false
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard self.shouldRun else { return }
                        if granted {
                            self.startEngine()
                        } else {
                            self.errorMessage = String(localized: "Microphone access was denied. Enable it in Settings → Privacy & Security → Microphone → On Cue.")
                            self.isListening = false
                        }
                    }
                }
            }
        }
    }

    /// Stops recognition.
    ///
    /// - Parameter releasingAudioSession: whether to hand the shared audio
    ///   session back. **Pass `false` while a recording is in progress.**
    ///   Deactivating the session pulls the microphone out from under a
    ///   running `AVCaptureSession`, and `AVCaptureMovieFileOutput` does not
    ///   re-attach audio to a file it has already started: the video carries
    ///   on and the sound stops dead at that point, for good. Pausing a take
    ///   does *not* stop the recording, so pausing used to silence the rest
    ///   of the file — discoverable only on playback, by which time the take
    ///   was gone. Call `releaseAudioSessionIfIdle()` once the recording has
    ///   actually finished.
    func end(releasingAudioSession: Bool = true) {
        shouldRun = false
        interrupted = false
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        stopEngine()
        isListening = false
        // Any session configuration still in flight belongs to a take that
        // no longer exists.
        startGeneration &+= 1
        // And so does anything waiting on it. Starting a recording here would
        // be starting one for a take that has already ended.
        audioSessionSettled = nil
        if releasingAudioSession { releaseAudioSessionIfIdle() }
    }

    /// Hands the shared audio session back, if nothing here still needs it.
    ///
    /// Without this the category stays active after a take and everyone
    /// else's audio — music, a podcast — stays ducked or stopped until the
    /// app is killed. It is separate from `end()` so the caller can defer it
    /// past a recording that outlives recognition, and it re-checks
    /// `shouldRun` because by the time it runs the reader may have started
    /// another take.
    /// Runs the waiting callback, once. `startEngine` is re-entered whenever
    /// the recognition task restarts — iOS ends one about every minute — and
    /// whenever the fallback ladder drops a rung, so this must not fire again
    /// on those.
    private func settleAudioSession() {
        guard let settled = audioSessionSettled else { return }
        audioSessionSettled = nil
        settled()
    }

    func releaseAudioSessionIfIdle() {
        guard !shouldRun else { return }
        PrompterAudioSession.deactivate()
    }

    /// A call, Siri, or an alarm takes the microphone away mid-take. Before
    /// this, recognition simply died: `handleError` surfaced a banner and
    /// stopped, while the speaker carried on talking to the lens with a
    /// prompter that had quietly stopped following them. Now the take pauses
    /// and picks itself back up when iOS says the interruption is over.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self, self.shouldRun else { return }
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

            switch type {
            case .began:
                self.interrupted = true
                self.stopEngine()
                // Listening genuinely has stopped, and saying so is what
                // pauses the speaking clock — leaving it running through a
                // phone call would decay the measured pace.
                self.isListening = false
            case .ended:
                guard self.interrupted else { return }
                self.interrupted = false
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                if options.contains(.shouldResume) {
                    self.startEngine()
                } else {
                    // iOS is telling us not to resume on our own — say so
                    // rather than leaving a dead prompter looking live.
                    self.errorMessage = String(localized: "Listening stopped when another app took the microphone. Tap play to carry on.")
                }
            @unknown default:
                break
            }
        }
    }

    private func startEngine() {
        stopEngine()

        startGeneration &+= 1
        let generation = startGeneration
        // The session belongs to `PrompterAudioSession`, which the prompter
        // activated when it appeared. Asking again is cheap and a no-op when
        // it is already right — but this does not own it, and must never hand
        // it back: the camera may be recording. The callback returns on main,
        // which is where everything below it has to run.
        PrompterAudioSession.activate { [weak self] error in
            guard let self, self.startGeneration == generation, self.shouldRun else { return }
            if let error {
                self.errorMessage = String(localized: "Couldn't configure the audio session: \(error.localizedDescription)")
                self.isListening = false
                self.settleAudioSession()
                return
            }
            self.settleAudioSession()
            self.chooseEngineAndStart(generation: generation)
        }
    }

    /// The iOS 26 analyzer when it has this language on the phone; otherwise
    /// the classic engine, on the device only. A language the analyzer could
    /// download starts downloading now, for the next take.
    private func chooseEngineAndStart(generation: Int) {
        let classicOnly = Self.forcesClassicEngine
        guard #available(iOS 26, *), !classicOnly, !analyzerFailedThisTake else {
            startClassic()
            return
        }
        let identifier = localeIdentifier
        Task { @MainActor [weak self] in
            let availability = await OnDeviceSpeechModels.availability(for: identifier)
            guard let self, self.startGeneration == generation, self.shouldRun else { return }
            switch availability {
            case .ready(let locale):
                self.startAnalyzer(locale: locale, generation: generation)
            case .downloadable:
                SpeechModelDownloads.shared.prepare(identifier)
                self.startClassic()
            case .unsupported:
                self.startClassic()
            }
        }
    }

    private func startClassic() {
        usingAnalyzer = false
        guard let recognizer, recognizer.isAvailable else {
            // Naming the language matters: "isn't available right now" alone
            // sends the reader looking for a different problem.
            let name = SpeechLocales.label(for: Locale(identifier: localeIdentifier))
            errorMessage = String(localized: "\(name) isn't available as a local service on the device, and Apple's server-based speech recognition can't be reached. Check your internet connection, or pick another language.")
            isListening = false
            return
        }
        // No on-device model for this language: go straight to the server
        // rather than spending two failed requests finding that out.
        if !recognizer.supportsOnDeviceRecognition { stage = .server }
        if stage == .server && !announcedServer {
            announcedServer = true
            let name = SpeechLocales.label(for: Locale(identifier: localeIdentifier))
            if SpeechModelDownloads.shared.isDownloading(localeIdentifier) {
                noticeMessage = String(localized: "\(name) is still downloading, so this take uses Apple's server-based speech recognition, the same service iOS uses for Dictation. From your next take, On Cue listens on this device.")
            } else {
                noticeMessage = String(localized: "\(name) isn't available as a local service on the device, so On Cue uses Apple's server-based speech recognition, the same service iOS uses for Dictation. It needs an internet connection.")
            }
        }
        startRecognition(recognizer: recognizer)
    }

    @available(iOS 26, *)
    private func startAnalyzer(locale: Locale, generation: Int) {
        let engine = AnalyzerEngine()
        analyzerEngine = engine
        delta.reset()
        receivedAnyResult = false

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        Task { @MainActor [weak self] in
            do {
                try await engine.start(
                    locale: locale,
                    inputFormat: format,
                    contextualStrings: Self.commandPhrases,
                    onTranscript: { [weak self] words in
                        guard let self, self.analyzerEngine === engine else { return }
                        #if DEBUG
                        if !self.receivedAnyResult { print("[speech] first result on engine=analyzer") }
                        #endif
                        self.receivedAnyResult = true
                        let appended = self.delta.newWords(in: words)
                        if !appended.isEmpty { self.onTranscript?(appended) }
                    },
                    onError: { [weak self] error in
                        guard let self, self.analyzerEngine === engine else { return }
                        self.analyzerFailed(error)
                    }
                )
            } catch {
                guard let self, self.analyzerEngine === engine else { return }
                self.analyzerFailed(error)
            }
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            engine.append(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        usingAnalyzer = true
        isListening = true
        if engineDescription != "New (SpeechAnalyzer)" { engineDescription = "New (SpeechAnalyzer)" }
        #if DEBUG
        print("[speech] engine=analyzer locale=\(locale.identifier) — on-device, offline-capable")
        #endif
    }

    /// The analyzer gave up mid-take. Carry on with the classic engine rather
    /// than leaving the reader with a prompter that stopped following.
    private func analyzerFailed(_ error: Error) {
        guard shouldRun, !interrupted else { return }
        #if DEBUG
        let ns = error as NSError
        print("[speech] analyzer failed: domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription) — using classic for this take")
        #endif
        analyzerFailedThisTake = true
        stopEngine()
        startClassic()
    }

    /// The half of starting a take that must be on main: `AVAudioEngine`, the
    /// recognition task, and the `@Published` state both of them drive. Only
    /// ever called from `startEngine` once the session is configured.
    private func startRecognition(recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Tell the recogniser these phrases are expected. Short commands have
        // no surrounding context to disambiguate them, which is why they come
        // back less reliably than the script does — especially in an accent.
        if stage.usesContextualStrings {
            req.contextualStrings = Self.commandPhrases
        }
        req.requiresOnDeviceRecognition = stage.isOnDevice
        #if DEBUG
        // Which engine and rung a take actually runs on is invisible otherwise.
        #if targetEnvironment(simulator)
        let host = "SIMULATOR — on-device recognition is not available here, so nothing here says anything about a phone"
        #else
        let host = "device"
        #endif
        print("[speech] host=\(host) locale=\(localeIdentifier) stage=\(stage.rawValue) " +
              "engine=classic path=\(stage.isOnDevice ? "on-device" : "server") contextualStrings=\(stage.usesContextualStrings) " +
              "supportsOnDevice=\(recognizer.supportsOnDeviceRecognition)")
        #endif
        let description = "Classic, \(stage.isOnDevice ? "on-device" : "server")"
        if engineDescription != description { engineDescription = description }
        request = req
        receivedAnyResult = false
        // A fresh task means a fresh cumulative transcript.
        delta.reset()

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        isListening = true
        // SFSpeechRecognizer does not promise which queue this handler runs
        // on, and everything it touches is main-actor state: `onTranscript`
        // drives the prompter's cursor and several `@State` properties, and
        // `handleError` writes `@Published`. Hop once, here, rather than
        // leaving every downstream caller to wonder.
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let transcript {
                    #if DEBUG
                    if !self.receivedAnyResult {
                        print("[speech] first result on stage=\(self.stage.rawValue) — this is the rung that works")
                    }
                    #endif
                    self.receivedAnyResult = true
                    let words = transcript.split(separator: " ").map(String.init)
                    let appended = self.delta.newWords(in: words)
                    if !appended.isEmpty {
                        self.onTranscript?(appended)
                    }
                }
                if let error = error {
                    self.handleError(error)
                    return
                }
                if isFinal, self.shouldRun {
                    self.stopEngine()
                    self.startEngine()
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        // An interruption tears the task down and reports an error on the way
        // out. That is the interruption handler's business, not a failure to
        // report — surfacing it here would put a red banner over a take that
        // is about to resume by itself.
        guard shouldRun, !interrupted else { return }
        if !receivedAnyResult, let nextStage = stage.next {
            // Not one result at this rung. Drop to the next rather than
            // giving up on on-device for the rest of the session: a phone can
            // refuse one form of request and accept another, and latching to
            // server-based after a single failure is what kept takes on the
            // slow path on hardware that can do it.
            #if DEBUG
            let ns = error as NSError
            print("[speech] \(stage.rawValue) produced no result: " +
                  "domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription) — trying \(nextStage.rawValue)")
            #endif
            stage = nextStage
            stopEngine()
            startEngine()
            return
        }
        #if DEBUG
        let failed = error as NSError
        print("[speech] on-device recognition failed on every rung: domain=\(failed.domain) code=\(failed.code)")
        #endif
        errorMessage = String(localized: "Speech recognition stopped: \((error as NSError).localizedDescription)")
        stopEngine()
        isListening = false
    }

    private func stopEngine() {
        if #available(iOS 26, *), let engine = analyzerEngine as? AnalyzerEngine {
            engine.stop()
        }
        analyzerEngine = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // Only touch the input node if a tap is actually installed. Accessing
        // `audioEngine.inputNode` lazily initialises it, so this used to create
        // the node even for a take that never started recognition — and on the
        // CI virtual Mac that initialisation is an RPC the audio server never
        // answers, which aborts the process. Guarded, a clean exit never
        // touches the node.
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }
}
