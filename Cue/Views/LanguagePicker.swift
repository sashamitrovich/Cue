import SwiftUI

/// The language list, shared by the setup screen and prompter settings (#25):
/// languages with an on-device model first, then those that use Apple's
/// server, each A-Z.
struct LanguagePickerContent: View {
    @Binding var selection: String
    @ObservedObject private var downloads = SpeechModelDownloads.shared

    var body: some View {
        let groups = SpeechLocales.grouped(SpeechLocales.available(), local: downloads.localIdentifiers)
        Picker("Language", selection: $selection) {
            if !groups.onDevice.isEmpty {
                Section("Listens on the device") {
                    ForEach(groups.onDevice, id: \.identifier) { row($0) }
                }
            }
            Section("Uses Apple's server") {
                ForEach(groups.server, id: \.identifier) { row($0) }
            }
        }
    }

    private func row(_ locale: Locale) -> some View {
        Text(SpeechLocales.label(for: locale)).tag(locale.identifier)
    }
}
