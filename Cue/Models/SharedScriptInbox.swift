import Foundation

/// Hand-off between the share extension and the app.
///
/// A share extension runs in its own process and cannot touch the app's
/// storage, so the two meet in an App Group container: the extension writes a
/// script there and exits, and the app collects it the next time it opens.
///
/// The directory is injectable so this can be tested without an App Group,
/// which is only available to a signed, entitled build.
struct SharedScriptInbox {
    static let appGroup = "group.app.cueprompter"
    /// Written by the extension, read and cleared by the app.
    private static let folder = "SharedScripts"
    private static let fileExtension = "txt"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The real inbox, or nil when the App Group isn't available — which
    /// happens in an unsigned build or if the entitlement is missing, and
    /// should degrade to "sharing doesn't work" rather than a crash.
    init?() {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else { return nil }
        self.init(directory: container.appendingPathComponent(Self.folder, isDirectory: true))
    }

    /// Stores a shared script. Each one gets its own file, so two shares in
    /// quick succession can't overwrite each other.
    @discardableResult
    func store(_ script: String, named name: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = String(format: "%.0f", Date().timeIntervalSince1970 * 1000)
        let safeName = (name ?? "script")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let file = directory
            .appendingPathComponent("\(stamp)-\(safeName.isEmpty ? "script" : safeName)")
            .appendingPathExtension(Self.fileExtension)
        try script.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// The most recently shared script, if one is waiting.
    func pending() -> (name: String, text: String)? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let newest = files
            .filter { $0.pathExtension == Self.fileExtension }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
        guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Strip the timestamp prefix that keeps filenames unique.
        let stem = newest.deletingPathExtension().lastPathComponent
        let name = stem.split(separator: "-").dropFirst().joined(separator: " ")
        return (name.isEmpty ? "Shared script" : name, text)
    }

    /// Called once the app has taken the script, so it isn't offered twice.
    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == Self.fileExtension {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
