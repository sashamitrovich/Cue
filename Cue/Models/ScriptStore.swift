import Foundation

/// Keeps a copy of the script in the app's own storage so it survives a
/// relaunch. It is a copy of the text, not a link to wherever the script came
/// from: the source file may be moved, deleted or sit in a place the app can
/// no longer open, and a pasted script has no source at all.
///
/// Failures never throw: a failed read means "nothing saved" and a failed
/// write leaves the in-memory text untouched.
struct ScriptStore {
    let fileURL: URL

    init(fileURL: URL = ScriptStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        // Unit tests build many states on the default store. Give each its own
        // empty file in the temp folder so one test's script is never restored
        // into another's, and nothing lands in the real Application Support.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("cue-test-script-\(UUID().uuidString).txt")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("script.txt")
    }

    /// The saved text, verbatim (an empty string is a real answer: the reader
    /// cleared the editor). `nil` when the file is missing or not valid UTF-8.
    func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ text: String) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: fileURL, options: .atomic)
        } catch {
            // Keep going: the text stays in memory and the next edit retries.
        }
    }
}
