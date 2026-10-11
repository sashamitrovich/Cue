import Foundation
import Speech
import AVFoundation

/// Listening with iOS 26's `SpeechAnalyzer` (#25).
///
/// Always on the device: there is no server path, so a take that runs here is
/// fast and works offline. Unlike `SFSpeechRecognizer`, the language model can
/// be downloaded by the app itself — see `OnDeviceSpeechModels`.
///
/// It only listens; `SpeechTracker` still owns the audio engine, the audio
/// session and interruptions, and feeds this the microphone's buffers.
@available(iOS 26, *)
final class AnalyzerEngine {
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    /// Touched from the audio thread by `append`, so behind a lock.
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?

    /// Prepares the model and starts listening. `onTranscript` receives the
    /// whole transcript so far, on main, after every result.
    func start(
        locale: Locale,
        inputFormat: AVAudioFormat,
        contextualStrings: [String],
        onTranscript: @escaping ([String]) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        // Volatile results are what make following feel live: without them a
        // stretch is reported only once it is final, which lags speech by
        // well over a second.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber], considering: inputFormat) ?? inputFormat

        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        lock.withLock {
            self.continuation = continuation
            analyzerFormat = format
            converter = format == inputFormat ? nil : AVAudioConverter(from: inputFormat, to: format)
        }
        self.analyzer = analyzer

        resultsTask = Task {
            var assembler = TranscriptAssembler()
            do {
                for try await result in transcriber.results {
                    let words = assembler.apply(String(result.text.characters), isFinal: result.isFinal)
                    await MainActor.run { onTranscript(words) }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run { onError(error) }
            }
        }
        try await analyzer.start(inputSequence: stream)
    }

    /// Hands one microphone buffer to the analyzer. Called on the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        guard let converter, let format = analyzerFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var handedOver = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: out))
        }
    }

    func stop() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
            converter = nil
        }
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }
}

/// The analyzer's language models: whether one is on the phone, and getting
/// it there (#25).
@available(iOS 26, *)
enum OnDeviceSpeechModels {
    enum Availability {
        /// Installed: listen with the analyzer now.
        case ready(Locale)
        /// Supported but not on the phone yet.
        case downloadable(Locale)
        /// The analyzer has no model for this language.
        case unsupported
    }

    static func availability(for identifier: String) async -> Availability {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: identifier)) else { return .unsupported }
        switch await AssetInventory.status(forModules: [transcriber(for: locale)]) {
        case .installed: return .ready(locale)
        case .supported, .downloading: return .downloadable(locale)
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Downloads and installs the model, reporting progress from 0 to 1.
    ///
    /// The app may only hold a few languages at once
    /// (`AssetInventory.maximumReservedLocales`). A reader who has gone past
    /// that gives up the oldest one they are not using now, rather than
    /// being refused the new one.
    static func install(_ locale: Locale, progress: @escaping (Double) -> Void) async throws {
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(locale), reserved.count >= AssetInventory.maximumReservedLocales,
           let oldest = reserved.first(where: { $0 != locale }) {
            await AssetInventory.release(reservedLocale: oldest)
        }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber(for: locale)]) else { return }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
            let fraction = p.fractionCompleted
            DispatchQueue.main.async { progress(fraction) }
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }

    private static func transcriber(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }
}
