import UIKit
import UniformTypeIdentifiers

/// Receives a script shared from another app and hands it to On Cue.
///
/// Deliberately does its work and gets out of the way: there is nothing to
/// configure about importing a script, so a form would only be in the way.
/// It confirms, then dismisses.
final class ShareViewController: UIViewController {

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let panel = UIView()
        panel.backgroundColor = .secondarySystemBackground
        panel.layer.cornerRadius = 16
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        label.text = "Saving to On Cue…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(label)

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            label.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -22),
            label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedItem() }
    }

    private func handleSharedItem() async {
        guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
              let providers = item.attachments else {
            return finish(message: "Nothing to import.", success: false)
        }

        for provider in providers {
            if let script = await script(from: provider) {
                guard let inbox = SharedScriptInbox() else {
                    return finish(message: "On Cue can't open its shared storage.", success: false)
                }
                do {
                    try inbox.store(script.text, named: script.name)
                    return finish(message: "Saved to On Cue", success: true)
                } catch {
                    return finish(message: "Couldn't save: \(error.localizedDescription)", success: false)
                }
            }
        }
        // Sharing a Google Doc gives a link rather than the document, which is
        // the most likely way to land here.
        finish(message: "That didn't contain any text. Try sharing the file itself, or export it as plain text first.",
               success: false)
    }

    /// Pulls text out of whatever was shared: a plain string, rich text, or a
    /// file. Matches the formats the app's own importer accepts.
    private func script(from provider: NSItemProvider) async -> (name: String, text: String)? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let text = ScriptImporter.text(from: data, fileExtension: url.pathExtension) {
                return (url.deletingPathExtension().lastPathComponent, text)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.rtf.identifier),
           let data = try? await provider.loadItem(forTypeIdentifier: UTType.rtf.identifier) as? Data,
           let text = ScriptImporter.text(from: data, fileExtension: "rtf") {
            return ("Shared script", text)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            return ("Shared script", text)
        }
        return nil
    }

    private func finish(message: String, success: Bool) {
        label.text = message
        // Long enough to read a failure, brief enough not to nag on success.
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.7 : 2.4)) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
