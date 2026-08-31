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
    private var interruptionObserver: NSObjectProtocol?
    /// Set when iOS takes the microphone away mid-take (a call, Siri, an
    /// alarm). Listening stops, but the take is not abandoned — the engine
    /// restarts by itself once the interruption ends.
    private var interrupted = false
    // Tried first for privacy (audio stays on-device), but a device can
    // report `supportsOnDeviceRecognition == true` without actually having
    // the language model downloaded (Settings > General > Keyboard >
    // Dictation, or Siri setup) — in that case every on-device attempt
    // fails instantly. Fall back to server-based recognition rather than
    // looping silently.
    private var preferOnDevice = true
    /// `AVAudioSession`'s `setCategory`/`setActive` block, and Apple warns
    /// that calling them on the main thread while the session is active can
    /// stall the UI. A long take calls them repeatedly — iOS ends a
    /// recognition task roughly every minute and the engine restarts — so
    /// they run here, and only the parts that touch `@Published` state or
    /// `AVAudioEngine` hop back to main.
    private let sessionQueue = DispatchQueue(label: "app.oncue.audio-session")
    /// Bumped by every start and by `end()`, so a session configured on
    /// `sessionQueue` can tell it has been superseded before it resumes on
    /// main — a take ended, or restarted, while it was still configuring.
    private var startGeneration = 0

    /// Requests speech-recognition and microphone permission before starting
    /// the engine. Without an explicit SFSpeechRecognizer authorization
    /// request the status stays `.notDetermined` and every recognition task
    /// fails immediately and silently — iOS never prompts on its own.
    /// - Parameter localeIdentifier: the language to listen in. Rebuilding
    ///   the recogniser is cheap and only happens when it actually changes,
    ///   so this is safe to pass on every start.
    func begin(localeIdentifier: String = SpeechLocales.fallback) {
        if localeIdentifier != self.localeIdentifier || recognizer == nil {
            self.localeIdentifier = localeIdentifier
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        }
        shouldRun = true
        preferOnDevice = true
        observeInterruptions()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.shouldRun else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition permission was denied. Enable it in Settings → Privacy & Security → Speech Recognition → On Cue."
                    self.isListening = false
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard self.shouldRun else { return }
                        if granted {
                            self.startEngine()
                        } else {
                            self.errorMessage = "Microphone access was denied. Enable it in Settings → Privacy & Security → Microphone → On Cue."
                            self.isListening = false
                        }
                    }
                }
            }
        }
    }

    func end() {
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
        // Hand the audio session back. Without this the category stays active
        // after a take and everyone else's audio — music, a podcast — stays
        // ducked or stopped until the app is killed.
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
                    self.errorMessage = "Listening stopped when another app took the microphone. Tap play to carry on."
                }
            @unknown default:
                break
            }
        }
    }

    private func startEngine() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            // Naming the language matters: the most likely cause is that this
            // device has no model for the one that was picked, and
            // "isn't available right now" sends the reader looking for a
            // network problem instead.
            let name = SpeechLocales.label(for: Locale(identifier: localeIdentifier))
            errorMessage = "Speech recognition isn't available for \(name) on this device. Pick another language in the prompter settings."
            return
        }
        stopEngine()

        startGeneration &+= 1
        let generation = startGeneration
        sessionQueue.async { [weak self] in
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.startGeneration == generation, self.shouldRun else { return }
                    self.errorMessage = "Couldn't configure the audio session: \(error.localizedDescription)"
                    self.isListening = false
                }
                return
            }
            DispatchQueue.main.async {
                guard let self, self.startGeneration == generation, self.shouldRun else { return }
                self.startRecognition(recognizer: recognizer)
            }
        }
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
        req.contextualStrings = ["scroll up", "scroll down", "scroll back", "go back", "go on"]
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        #if DEBUG
        // Which path a take actually runs on is invisible otherwise, and the
        // two differ by an order of magnitude in latency (roughly 30-50ms
        // on-device against 300-800ms server-based). A take that silently
        // fell back reads as "the scrolling got laggy" with nothing in the
        // UI to say why.
        #if targetEnvironment(simulator)
        let host = "SIMULATOR — on-device recognition is not available here, so a server fallback says nothing about a phone"
        #else
        let host = "device"
        #endif
        print("[speech] host=\(host) locale=\(localeIdentifier) " +
              "path=\(req.requiresOnDeviceRecognition ? "on-device" : "server") " +
              "supportsOnDevice=\(recognizer.supportsOnDeviceRecognition) preferOnDevice=\(preferOnDevice)")
        #endif
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

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
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
        if preferOnDevice && !receivedAnyResult {
            // Never got a single result on-device — most likely the
            // on-device model isn't installed. Retry once via server-based
            // recognition instead of retrying on-device forever.
            preferOnDevice = false
            #if DEBUG
            print("[speech] on-device produced no result, falling back to server: \((error as NSError).localizedDescription)")
            #endif
            stopEngine()
            startEngine()
            return
        }
        errorMessage = "Speech recognition stopped: \((error as NSError).localizedDescription)"
        stopEngine()
        isListening = false
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
