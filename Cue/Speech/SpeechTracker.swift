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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var shouldRun = false
    private var receivedAnyResult = false
    private var delta = TranscriptDeltaTracker()
    // Tried first for privacy (audio stays on-device), but a device can
    // report `supportsOnDeviceRecognition == true` without actually having
    // the language model downloaded (Settings > General > Keyboard >
    // Dictation, or Siri setup) — in that case every on-device attempt
    // fails instantly. Fall back to server-based recognition rather than
    // looping silently.
    private var preferOnDevice = true

    /// Requests speech-recognition and microphone permission before starting
    /// the engine. Without an explicit SFSpeechRecognizer authorization
    /// request the status stays `.notDetermined` and every recognition task
    /// fails immediately and silently — iOS never prompts on its own.
    func begin() {
        shouldRun = true
        preferOnDevice = true
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
        stopEngine()
        isListening = false
    }

    private func startEngine() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        stopEngine()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't configure the audio session: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
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
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.receivedAnyResult = true
                let transcript = result.bestTranscription.formattedString
                    .split(separator: " ")
                    .map(String.init)
                let appended = self.delta.newWords(in: transcript)
                if !appended.isEmpty {
                    self.onTranscript?(appended)
                }
            }
            if let error = error {
                self.handleError(error)
                return
            }
            if result?.isFinal == true, self.shouldRun {
                self.stopEngine()
                self.startEngine()
            }
        }
    }

    private func handleError(_ error: Error) {
        guard shouldRun else { return }
        if preferOnDevice && !receivedAnyResult {
            // Never got a single result on-device — most likely the
            // on-device model isn't installed. Retry once via server-based
            // recognition instead of retrying on-device forever.
            preferOnDevice = false
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
