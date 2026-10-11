import Foundation
import Speech

/// Whether the chosen language can be listened to on this device, and getting
/// its model here when it can be downloaded (#25).
///
/// Shared rather than owned by `SpeechTracker`, because the place a reader
/// picks a language is the setup screen, long before a prompter exists: the
/// download starts there, and the prompter shows the same one if it is still
/// running when a take starts.
final class SpeechModelDownloads: ObservableObject {
    static let shared = SpeechModelDownloads()

    enum Offline: Equatable {
        case checking
        /// A model is on the device: listening works offline.
        case ready
        case downloading(Double)
        /// No on-device model for this language here: On Cue listens through
        /// Apple's server-based speech recognition, which needs a network.
        case server
        /// The download failed — usually no network. Picking the language
        /// again retries.
        case failed
    }

    /// The offline state of the language last passed to `prepare`.
    @Published private(set) var status: Offline = .checking
    @Published private(set) var statusIdentifier = ""
    /// The download in progress, for the prompter's banner.
    @Published private(set) var current: (language: String, fraction: Double)?
    /// Set to the language's name when a download finishes.
    @Published private(set) var finished: String?

    /// Languages Apple has an on-device model for on this device, whether
    /// downloaded or not: the iOS 26 engine's list plus whatever the classic
    /// engine reports it can run locally. Orders the language picker.
    @Published private(set) var localIdentifiers: Set<String> = []

    private var downloading: Set<String> = []

    init() {
        let classic = SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .map(\.identifier)
        localIdentifiers = Set(classic)
        guard #available(iOS 26, *) else { return }
        Task { @MainActor [weak self] in
            let analyzer = await SpeechTranscriber.supportedLocales.map(\.identifier)
            self?.localIdentifiers.formUnion(analyzer)
        }
    }

    func isDownloading(_ identifier: String) -> Bool {
        downloading.contains(identifier)
    }

    /// Works out whether `identifier` can be listened to on this device and,
    /// if its model only needs downloading, starts that. Safe to call on every
    /// language change: a language already downloading is not started twice.
    func prepare(_ identifier: String) {
        statusIdentifier = identifier
        // Store screenshots are taken on a simulator, which has no on-device
        // speech at all and would label every language as server-only. The
        // capture test passes this for the languages Apple has a local model
        // for, so the editor shows what a real iOS 26 device shows.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingOfflineReady") {
            status = .ready
            return
        }
        status = downloading.contains(identifier) ? status : .checking
        let classicOnly = SpeechTracker.forcesClassicEngine
        guard #available(iOS 26, *), !classicOnly else {
            status = Self.classicOnDevice(identifier) ? .ready : .server
            return
        }
        Task { @MainActor [weak self] in
            let availability = await OnDeviceSpeechModels.availability(for: identifier)
            #if DEBUG
            print("[speech] prepare \(identifier): \(availability)")
            let supported = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
            print("[speech] analyzer supports \(supported.count): \(supported.joined(separator: " "))")
            let installed = await SpeechTranscriber.installedLocales.map(\.identifier).sorted()
            print("[speech] analyzer installed: \(installed.joined(separator: " "))")
            let classic = SFSpeechRecognizer.supportedLocales()
                .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
                .map(\.identifier).sorted()
            print("[speech] classic on-device \(classic.count): \(classic.joined(separator: " "))")
            #endif
            guard let self, self.statusIdentifier == identifier else { return }
            switch availability {
            case .ready:
                self.status = .ready
            case .downloadable(let locale):
                self.download(locale, identifier: identifier)
            case .unsupported:
                self.status = Self.classicOnDevice(identifier) ? .ready : .server
            }
        }
    }

    /// The classic engine on this device. Not a guarantee — see the
    /// recognition-ladder note in AGENTS.md — but the best available answer
    /// before a take has tried.
    private static func classicOnDevice(_ identifier: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: identifier))?.supportsOnDeviceRecognition == true
    }

    @available(iOS 26, *)
    private func download(_ locale: Locale, identifier: String) {
        guard !downloading.contains(identifier) else { return }
        downloading.insert(identifier)
        let name = SpeechLocales.label(for: Locale(identifier: identifier))
        report(identifier, .downloading(0))
        current = (name, 0)
        Task { @MainActor [weak self] in
            var succeeded = false
            do {
                try await OnDeviceSpeechModels.install(locale) { fraction in
                    self?.current = (name, fraction)
                    self?.report(identifier, .downloading(fraction))
                }
                succeeded = true
            } catch {
                #if DEBUG
                print("[speech] model download failed for \(identifier): \(error)")
                #endif
            }
            guard let self else { return }
            self.downloading.remove(identifier)
            self.current = nil
            self.report(identifier, succeeded ? .ready : .failed)
            if succeeded { self.finished = name }
        }
    }

    #if DEBUG
    /// Gives up On Cue's claim on every downloaded language, for retesting the
    /// download flow. iOS decides whether and when the model files actually
    /// go — there is no API to delete them — so this logs what it reports after.
    func releaseAllForTesting() {
        guard #available(iOS 26, *) else { return }
        Task { @MainActor [weak self] in
            for locale in await AssetInventory.reservedLocales {
                let released = await AssetInventory.release(reservedLocale: locale)
                print("[speech] released \(locale.identifier): \(released)")
            }
            let installed = await SpeechTranscriber.installedLocales.map(\.identifier).sorted()
            print("[speech] after release, installed: \(installed.joined(separator: " "))")
            if let self { self.prepare(self.statusIdentifier) }
        }
    }
    #endif

    private func report(_ identifier: String, _ status: Offline) {
        if statusIdentifier == identifier { self.status = status }
    }
}
