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
    @State private var sharedScript: (name: String, text: String)?
    /// The file currently backing the editor, if any — set on Open, cleared
    /// when the script comes from somewhere else (typed fresh, or a shared
    /// script). `nil` just means "typed in the app," not an error.
    @State private var openedFileURL: URL?
    @State private var pendingSave: DispatchWorkItem?
    @FocusState private var editorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

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

    /// `nil` (typed fresh, or a shared script) always counts as editable —
    /// there's nowhere to fail to save to.
    private var currentFileIsEditable: Bool {
        guard let openedFileURL else { return true }
        return ScriptImporter.isEditable(fileExtension: openedFileURL.pathExtension)
    }

    var body: some View {
        NavigationStack {
            // No outer ScrollView: the editor takes a `maxHeight: .infinity`
            // slice of whatever's left after the fixed-height controls below
            // it, so it's as big as the screen allows. While the keyboard is
            // up those controls would otherwise eat the little room the
            // keyboard leaves, so they step aside entirely rather than just
            // shrinking the editor further — editing is the only thing to
            // do with the keyboard up anyway.
            VStack(spacing: 22) {
                editorCard()
                if !editorFocused {
                    startButton
                    languageNotice
                    cameraNotice
                    footnote
                }
            }
            .animation(.easeInOut(duration: 0.2), value: editorFocused)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background(Color(.systemBackground))
            .navigationTitle("")
            // Pinned, not a large title. A large title is coupled by iOS to
            // the nearest scroll view — here the script editor — so scrolling
            // the script dragged the app's own name up and bounced it back.
            // The title has nothing to do with where you are in the script.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("On Cue")
                            .font(ChromeType.label(17, weight: .bold))
                            .tracking(17 * 0.08)
                            .textCase(.uppercase)
                            .foregroundStyle(.primary)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(PrompterView.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: PrompterView.accent.opacity(0.8), radius: 4)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("On Cue")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("How On Cue works")
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
        // A script shared from another app is offered rather than applied:
        // silently replacing what is in the editor would eventually eat
        // something the writer cared about.
        .alert("Use the shared script?", isPresented: Binding(
            get: { sharedScript != nil },
            set: { if !$0 { sharedScript = nil } }
        ), presenting: sharedScript) { shared in
            Button("Use It") {
                pendingSave?.cancel()
                openedFileURL = nil
                state.scriptText = shared.text
                SharedScriptInbox()?.clear()
                sharedScript = nil
            }
            Button("Keep Mine", role: .cancel) {
                SharedScriptInbox()?.clear()
                sharedScript = nil
            }
        } message: { shared in
            Text("\"\(shared.name)\" was shared with On Cue. Using it replaces the script you have here.")
        }
        .onAppear { collectSharedScript() }
        .onChange(of: scenePhase) { phase in
            // Sharing happens while the app is in the background, so the
            // hand-off is checked on every return to the foreground.
            if phase == .active { collectSharedScript() }
        }
        .onChange(of: state.scriptText) { _ in
            scheduleAutosave()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importableTypes,
            allowsMultipleSelection: false
        ) { result in
            handleOpen(result)
        }
    }

    // MARK: - Script

    private func editorCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Script")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // One button, two jobs — deliberately not an `if`. While
                // editing this is the way out; otherwise it opens a file.
                //
                // Editing needs an exit that cannot go missing. The keyboard
                // toolbar's Done vanished on the second edit and was never
                // reliable: `ToolbarItemGroup(placement: .keyboard)` depends
                // on the keyboard being re-offered a placement, which does not
                // survive the keyboard going down and coming back. This sits
                // in the card header, above the editor and well clear of the
                // keyboard, and is always on screen.
                Button {
                    if editorFocused {
                        editorFocused = false
                    } else {
                        showImporter = true
                    }
                } label: {
                    Label(
                        editorFocused ? "Done" : "Open",
                        systemImage: editorFocused ? "checkmark" : "folder"
                    )
                    .font(.subheadline.weight(editorFocused ? .semibold : .regular))
                }
                .accessibilityLabel(editorFocused ? "Done editing" : "Open a script file")
            }

            // Fills whatever's left above the start button and the fixed
            // notices below it, rather than a fraction of the screen — this
            // is the thing the screen is for.
            TextEditor(text: $state.scriptText)
                .focused($editorFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxHeight: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!currentFileIsEditable)


            if let openedFileURL {
                Label(
                    currentFileIsEditable
                        ? "Editing \(openedFileURL.lastPathComponent) — changes save automatically"
                        : "\(openedFileURL.lastPathComponent) can't be edited here",
                    systemImage: currentFileIsEditable ? "checkmark.circle" : "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

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

    /// Which language the prompter will listen in, before it matters rather
    /// than after.
    ///
    /// This also lives in the prompter's settings sheet, but it belongs here
    /// too: it's a pre-start decision, and it's the one setting whose failure
    /// mode is silent. Getting it wrong doesn't look like a wrong setting, it
    /// looks like a prompter that doesn't work — and someone who has just
    /// watched their script sit motionless is not going to go hunting through
    /// a settings sheet to find out why.
    private var languageNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
            Text("Listening in")
            Menu {
                Picker("Language", selection: $state.recognitionLocale) {
                    ForEach(SpeechLocales.available(), id: \.identifier) { locale in
                        Text(SpeechLocales.label(for: locale)).tag(locale.identifier)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(SpeechLocales.label(for: Locale(identifier: state.recognitionLocale)))
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .accessibilityLabel("Speech recognition language, \(SpeechLocales.label(for: Locale(identifier: state.recognitionLocale)))")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The thing a first-time user most needs to know before tapping start,
    /// and the only one they can't infer from the screen itself: the front
    /// camera is on, and this will record them.
    /// Whether to record, as a control rather than a bulletin.
    ///
    /// It used to be a passive line: "Camera off — the script will scroll
    /// without recording." `cameraEnabled` persists, and the only toggle is a
    /// button inside the prompter — so anyone who turned the camera off during
    /// a take came back to a setup screen that reported the state and offered
    /// no way to change it. The "on" wording was no better: it explained how to
    /// turn the camera *off* and never how to turn it back on.
    ///
    /// It belongs here. The setup screen carries pre-start decisions, and
    /// whether you are recording is decided before you start, not while
    /// reading. Enabling it here also puts the system permission prompt on a
    /// stationary screen rather than three seconds into a pre-roll.
    ///
    /// Named for what it does — the same words as the prompter's own button —
    /// rather than for the flag behind it.
    private var cameraNotice: some View {
        Toggle(isOn: $state.cameraEnabled) {
            HStack(spacing: 7) {
                Image(systemName: state.cameraEnabled ? "video.fill" : "video.slash.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record with the front camera")
                    Text(state.cameraEnabled
                         ? "Saved to your Photos library when you finish."
                         : "The script still scrolls; nothing is captured.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .tint(PrompterView.accent)
    }

    private var footnote: some View {
        Text("Speech recognition runs on your device. If it hasn't downloaded the offline speech model, iOS falls back to Apple's speech service and sends audio there to transcribe. Recordings are only ever saved to your own Photos library.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Picks up anything the share extension left in the App Group container.
    private func collectSharedScript() {
        guard sharedScript == nil, let pending = SharedScriptInbox()?.pending() else { return }
        sharedScript = pending
    }

    // MARK: - Open

    private func handleOpen(_ result: Result<[URL], Error>) {
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
                pendingSave?.cancel()
                openedFileURL = url
                state.scriptText = text
            } catch {
                importError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Autosave

    /// Debounced rather than a write per keystroke — a fast typist would
    /// otherwise hit the disk (through a security-scoped access grant, not a
    /// free operation) dozens of times a second for no benefit, since only
    /// the latest text ever matters.
    private func scheduleAutosave() {
        pendingSave?.cancel()
        guard let url = openedFileURL, currentFileIsEditable else { return }
        let text = state.scriptText
        let work = DispatchWorkItem { [self] in save(text, to: url) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save(_ text: String, to url: URL) {
        guard let data = ScriptImporter.data(from: text, fileExtension: url.pathExtension) else { return }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            importError = "Couldn't save to \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
