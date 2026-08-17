import Foundation
import UIKit

/// Turns a picked document's bytes into script text. Kept free of file-picker
/// and UI concerns so the decoding rules are testable on their own.
enum ScriptImporter {

    /// Extensions offered to the document picker beyond the declared content
    /// types, for providers that report files only by name.
    static let supportedExtensions = ["txt", "md", "markdown", "text", "rtf"]

    static func text(from data: Data, fileExtension: String) -> String? {
        if ["rtf", "rtfd"].contains(fileExtension.lowercased()) {
            return richText(from: data)
        }
        return plainText(from: data)
    }

    private static func richText(from data: Data) -> String? {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return attributed.string
    }

    /// Whether a file of this type can be edited and written back. Formats
    /// with no round trip back to bytes — a PDF, say — are read-only: they
    /// can still be opened and read, just not saved over.
    static func isEditable(fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }

    /// The inverse of `text(from:fileExtension:)`, for autosaving edits back
    /// to the file they came from. RTF loses whatever styling `text(from:)`
    /// already discarded on import — there's nothing left to preserve by the
    /// time the editor sees plain text — but stays valid RTF.
    static func data(from text: String, fileExtension: String) -> Data? {
        if ["rtf", "rtfd"].contains(fileExtension.lowercased()) {
            return richTextData(from: text)
        }
        return text.data(using: .utf8)
    }

    private static func richTextData(from text: String) -> Data? {
        let attributed = NSAttributedString(string: text)
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// Tries the encodings a script is realistically saved in, most likely
    /// first. Latin-1 is last because it accepts almost any byte sequence and
    /// would otherwise mask a correct UTF-8 or UTF-16 reading.
    static func plainText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        return String(data: data, encoding: .isoLatin1)
    }
}
