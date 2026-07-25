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

    /// Tries the encodings a script is realistically saved in, most likely
    /// first. Latin-1 is last because it accepts almost any byte sequence and
    /// would otherwise mask a correct UTF-8 or UTF-16 reading.
    static func plainText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        return String(data: data, encoding: .isoLatin1)
    }
}
