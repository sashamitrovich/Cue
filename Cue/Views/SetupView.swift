import SwiftUI
import UniformTypeIdentifiers

/// The first screen: write or import a script, then start.
///
/// Structured the way iOS structures this kind of screen — one clear primary
/// action above the fold, secondary tuning in a grouped list below it, and
/// nothing competing with the thing you came here to do.
struct SetupView: View {
    @ObservedObject var state: TeleprompterState
    @State private var showPrompter = false
    @State private var showImporter = false
    @State private var showHelp = false
    @State private var importError: String?
    @FocusState private var editorFocused: Bool

    private var importableTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .rtf]
        // Markdown isn't a declared type on every OS version this runs on.
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }

    private var scriptIsEmpty: Bool {
        state.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 22) {
                        editorCard(height: min(max(geo.size.height * 0.28, 130), 300))
                        startButton
                        cameraNotice
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(.systemBackground))
            .navigationTitle("On Cue")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("How On Cue works")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(PrompterView.accent)
        .fullScreenCover(isPresented: $showPrompter) {
            PrompterView(state: state)
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importableTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - Script

    private func editorCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Script")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                }
            }

            // Sized from live geometry so the start button lands above the
            // fold on every phone; the editor scrolls internally.
            TextEditor(text: $state.scriptText)
                .focused($editorFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: height)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            estimateLine
        }
    }

    /// Length and run time, with the speed the estimate assumes built into
    /// the sentence it affects — a "Pace: 140" row elsewhere on the screen
    /// gave a number with nothing to attach it to.
    private var estimateLine: some View {
        let count = TeleprompterState.wordCount(in: state.scriptText)
        let seconds = ReadingPace.seconds(forWords: count, wpm: state.targetWPM)
        return HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("\(count) word\(count == 1 ? "" : "s") · about \(ReadingPace.timeString(seconds)) at a")
            Menu {
                Picker("Pace", selection: $state.targetWPM) {
                    ForEach(ReadingPace.namedPaces, id: \.wpm) { pace in
                        Text("\(pace.label.capitalized) · \(Int(pace.wpm)) wpm").tag(pace.wpm)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("\(ReadingPace.name(forWPM: state.targetWPM)) pace")
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .accessibilityLabel("Reading pace, \(Int(state.targetWPM)) words per minute")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var startButton: some View {
        Button {
            editorFocused = false
            state.buildWords()
            showPrompter = true
        } label: {
            Text("Start prompting →")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(PrompterView.accent)
        .foregroundStyle(.black)
        .disabled(scriptIsEmpty)
    }

    /// The thing a first-time user most needs to know before tapping start,
    /// and the only one they can't infer from the screen itself: the front
    /// camera is on, and this will record them.
    private var cameraNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: state.cameraEnabled ? "video.fill" : "video.slash.fill")
            Text(state.cameraEnabled
                 ? "Records with the front camera. You can turn it off while prompting."
                 : "Camera off — the script will scroll without recording.")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footnote: some View {
        Text("Speech recognition runs on your iPhone. If it hasn't downloaded the offline speech model, iOS falls back to Apple's speech service and sends audio there to transcribe. Recordings are only ever saved to your own Photos library.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure(let error):
            importError = "Couldn't open that file: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            // Documents picked outside the app's container are security-scoped
            // and must be opened explicitly before reading.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = ScriptImporter.text(from: data, fileExtension: url.pathExtension),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    importError = "\(url.lastPathComponent) didn't contain any readable text."
                    return
                }
                state.scriptText = text
            } catch {
                importError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }
}
