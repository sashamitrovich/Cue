import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @ObservedObject var state: TeleprompterState
    @State private var showPrompter = false
    @State private var showImporter = false
    @State private var importError: String?

    private var importableTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .rtf]
        // Markdown isn't a declared type on every OS version this runs on.
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Cue").font(.system(size: 36, weight: .bold, design: .serif))
                        Circle().fill(Color.orange).frame(width: 10, height: 10)
                    }
                    Text("The script scrolls when you speak. Stop, and it waits for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("YOUR SCRIPT").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "folder")
                            .font(.caption)
                    }
                }
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextEditor(text: $state.scriptText)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .scrollContentBackground(.hidden)

                estimateLine

                HStack(spacing: 12) {
                    stepper(label: "Text size", value: "\(Int(state.fontSize))") {
                        state.fontSize = max(20, state.fontSize - 2)
                    } up: {
                        state.fontSize = min(64, state.fontSize + 2)
                    }
                    stepper(label: "Idle drift", value: state.driftLabel) {
                        state.driftIndex = max(0, state.driftIndex - 1)
                    } up: {
                        state.driftIndex = min(TeleprompterState.driftSteps.count - 1, state.driftIndex + 1)
                    }
                }

                HStack(spacing: 12) {
                    stepper(label: "Pace", value: "\(Int(state.targetWPM))") {
                        state.targetWPM = max(ReadingPace.wpmRange.lowerBound, state.targetWPM - 5)
                    } up: {
                        state.targetWPM = min(ReadingPace.wpmRange.upperBound, state.targetWPM + 5)
                    }
                    stepper(label: "Countdown", value: countdownLabel) {
                        stepCountdown(-1)
                    } up: {
                        stepCountdown(1)
                    }
                }

                HStack(spacing: 10) {
                    toggleChip(state.mirror ? "Mirror: On" : "Mirror ⇋", on: state.mirror) { state.mirror.toggle() }
                    toggleChip("Align: " + (state.centerAlign ? "Center" : "Left"), on: false) { state.centerAlign.toggle() }
                }
                toggleChip(state.cameraEnabled ? "📹 Front camera: On" : "📹 Front camera: Off", on: state.cameraEnabled) {
                    state.cameraEnabled.toggle()
                }

                Button {
                    state.buildWords()
                    showPrompter = true
                } label: {
                    Text("Start prompting →")
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(state.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Uses on-device speech recognition to track your place. Grant microphone (and camera, if recording) access when asked. Nothing leaves your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(isPresented: $showPrompter) {
            PrompterView(state: state)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importableTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    /// Length of the script as typed, and roughly how long it runs at the
    /// chosen pace — the thing you actually want to know when writing to a
    /// time limit.
    private var estimateLine: some View {
        let count = TeleprompterState.wordCount(in: state.scriptText)
        let seconds = ReadingPace.seconds(forWords: count, wpm: state.targetWPM)
        return HStack(spacing: 6) {
            Image(systemName: "timer").font(.caption2)
            Text("\(count) word\(count == 1 ? "" : "s") · about \(ReadingPace.timeString(seconds)) at \(Int(state.targetWPM)) wpm")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var countdownLabel: String {
        state.countdownSeconds == 0 ? "Off" : "\(state.countdownSeconds)s"
    }

    private func stepCountdown(_ direction: Int) {
        let options = TeleprompterState.countdownOptions
        let current = options.firstIndex(of: state.countdownSeconds) ?? 0
        state.countdownSeconds = options[min(options.count - 1, max(0, current + direction))]
    }

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

    @ViewBuilder
    private func stepper(label: String, value: String, down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(value).font(.system(size: 20, weight: .semibold, design: .serif))
                Spacer()
                Button("−", action: down).buttonStyle(.bordered)
                Button("+", action: up).buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func toggleChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(on ? Color.orange : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(on ? Color.orange : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
