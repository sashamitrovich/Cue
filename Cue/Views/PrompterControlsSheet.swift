import SwiftUI

/// Everything you can tune while the prompter is open.
///
/// Standard grouped sections with real headers and footers: the footer says
/// what the section is *for*, so no control needs an explanation bolted onto
/// it. Camera sections appear only when the camera is on, and each individual
/// row is conditional on what this iPhone's front camera actually supports.
struct PrompterControlsSheet: View {
    @ObservedObject var camera: CameraController
    @ObservedObject var state: TeleprompterState
    @Environment(\.dismiss) private var dismiss

    private var hasAdjustableCapture: Bool {
        camera.capabilities.supportsHDR
            || camera.capabilities.supportsStabilization
            || camera.capabilities.supportsLowLightBoost
    }

    /// Fraction of the screen the sheet is allowed. Deliberately under half:
    /// the reading line sits high on the screen by design, so what stays
    /// uncovered is the part being read.
    static let sheetHeight: CGFloat = 0.45

    /// Landscape is a different problem. 45% of a landscape iPhone is about
    /// 175pt — roughly one row — and iOS does not offer a partial detent in
    /// compact height anyway. The script there is behind the sheet rather
    /// than above it, so there is nothing to preserve by cramping it.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var detents: Set<PresentationDetent> {
        verticalSizeClass == .compact ? [.large] : [.fraction(Self.sheetHeight)]
    }

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                comparisonSection
                #endif
                readingSection
                timingSection
                voiceSection
                if state.cameraEnabled {
                    legibilitySection
                    qualitySection
                    if camera.capabilities.maxZoom > camera.capabilities.minZoom + 0.05 {
                        zoomSection
                    }
                    if hasAdjustableCapture { captureSection }
                }
            }
            .tint(PrompterView.accent)
            .navigationTitle("Prompter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // One detent, not two. These are the settings whose effect you can
        // only judge by looking at the script, so the script has to stay on
        // screen while you change them — and with a `.large` detent in the
        // set, a drag anywhere in the Form expanded the sheet to full screen
        // and covered the very thing being adjusted. A single detent has
        // nothing to expand to, so that same drag scrolls the Form instead.
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        // Leaves the prompter behind undimmed and still interactive, so the
        // script reads normally rather than through the sheet's scrim.
        .modifier(UncoveredPrompter())
        .preferredColorScheme(.dark)
    }

    // MARK: - Reading

    #if DEBUG
    /// A/B for "1.3 felt smoother". Both behaviours in one build so they can
    /// be compared inside a single take rather than against a memory of an
    /// older release. Debug builds only.
    private var comparisonSection: some View {
        Section {
            Toggle("Scroll like 1.3", isOn: $state.legacyScrolling)
        } footer: {
            Text("Debug only. On: the script heads straight for the word you just said, as 1.3 did. Off: it travels there at a bounded speed.")
        }
    }
    #endif

    private var readingSection: some View {
        Section {
            labelledSlider(
                "Reading line",
                value: $state.cueLineFraction,
                range: 0.08...0.6,
                display: "\(Int(state.cueLineFraction * 100))%",
                icons: ("arrow.up.to.line", "arrow.down.to.line")
            )
            labelledSlider(
                "Text size",
                value: $state.fontSize,
                range: 20...64,
                step: 1,
                display: "\(Int(state.fontSize))",
                icons: ("textformat.size.smaller", "textformat.size.larger")
            )
            labelledSlider(
                "Already read text dimming",
                value: $state.readTextFloor,
                range: ReadTextFade.floorRange,
                display: "\(Int(state.readTextFloor * 100))%",
                icons: ("circle.dotted", "circle.fill")
            )
            labelledSlider(
                "Side margins",
                value: $state.sideMargin,
                range: ScriptMargins.range,
                step: 4,
                display: state.sideMargin == 0 ? "None" : "+\(Int(state.sideMargin))",
                icons: ("arrow.right.and.line.vertical.and.arrow.left", "arrow.left.and.line.vertical.and.arrow.right")
            )
            Picker("Text alignment", selection: $state.textAlignment) {
                ForEach(ScriptAlignment.allCases) { option in
                    Image(systemName: option.symbolName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Mirror", isOn: $state.mirror)
        } header: {
            Text("Reading")
        } footer: {
            // Adjusted here rather than before starting, because these are the
            // settings whose effect you can only judge by looking at the
            // script — which is visible behind this sheet.
            Text("Already-read text fades with distance behind you, so the line you just said stays legible if you want it again — Already read text dimming sets how dim the oldest text goes. Side margins add to whatever the screen already needs, so the script never intrudes into a notch. Wider margins give shorter lines, which are easier to catch at a glance. Keep the reading line high on the screen so your eyes stay near the lens. Mirror is for teleprompter rigs that reflect the screen in a sheet of glass; reading from the phone, leave it off.")
        }
    }

    // MARK: - Timing

    private var timingSection: some View {
        Section {
            Toggle("Show timing", isOn: $state.showTiming)
            Picker("Countdown", selection: $state.countdownSeconds) {
                ForEach(TeleprompterState.countdownOptions, id: \.self) { seconds in
                    Text(seconds == 0 ? "Off" : "\(seconds)s").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            labelledSlider(
                "Pace",
                value: $state.targetWPM,
                range: ReadingPace.wpmRange,
                step: 5,
                display: "\(Int(state.targetWPM)) wpm",
                icons: ("tortoise.fill", "hare.fill")
            )
        } header: {
            Text("Timing")
        } footer: {
            Text("Your target pace drives the estimate until you've read enough of a take for On Cue to measure your real one.")
        }
    }

    // MARK: - Voice control

    private var voiceSection: some View {
        Section {
            Picker("Language", selection: $state.recognitionLocale) {
                ForEach(SpeechLocales.available(), id: \.identifier) { locale in
                    Text(SpeechLocales.label(for: locale)).tag(locale.identifier)
                }
            }
            Toggle("Voice commands", isOn: $state.voiceCommandsEnabled)
        } header: {
            Text("Voice control")
        } footer: {
            // The language row comes first because nothing else in this
            // section — or in the app — works until it is right: the
            // prompter simply does not move when it is listening for the
            // wrong one.
            Text("On Cue follows your script in the language set here; a new take uses it. Say \"scroll up\" to step back a line, or \"scroll down\" to step forward — repeat to go further. Command words are not read as script. If your script itself says one of these phrases at that point, it is read rather than obeyed; turn this off if it still gets in the way. Spoken commands are recognised in English only, whatever language the script is in.")
        }
    }

    // MARK: - Legibility

    private var legibilitySection: some View {
        Section {
            labelledSlider(
                "Text",
                value: $state.textOpacity,
                range: 0.3...1.0,
                display: "\(Int(state.textOpacity * 100))%",
                icons: ("circle.lefthalf.filled", "circle.fill")
            )
            labelledSlider(
                "Dim",
                value: $state.cameraDimming,
                range: 0.0...0.85,
                display: "\(Int(state.cameraDimming * 100))%",
                icons: ("sun.max.fill", "moon.fill")
            )
        } header: {
            Text("Over the camera")
        } footer: {
            Text("Raise Dim to darken the picture behind the words. Lower Text to see more of yourself through them.")
        }
    }

    // MARK: - Camera

    @ViewBuilder
    private var qualitySection: some View {
        if let mode = camera.selectedMode, let tier = camera.selectedTier {
            Section {
                if camera.capabilities.qualityTiers.count > 1 {
                    Picker("Size", selection: Binding(
                        get: { tier },
                        set: { camera.selectTier($0) }
                    )) {
                        ForEach(camera.capabilities.qualityTiers) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if tier.frameRates.count > 1 {
                    Picker("Frame rate", selection: Binding(
                        get: { mode.frameRate },
                        set: { camera.apply(VideoMode(height: tier.height, frameRate: $0)) }
                    )) {
                        ForEach(tier.frameRates, id: \.self) { rate in
                            Text("\(Int(rate))").tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Video quality")
            } footer: {
                // What this iPhone actually reports — ground truth behind the
                // controls above.
                Text(camera.isRecording
                     ? "Stop recording to change quality."
                     : "This camera offers " + camera.capabilities.qualityTiers.map { tier in
                        "\(tier.label) at \(tier.frameRates.map { "\(Int($0))" }.joined(separator: "/")) fps"
                     }.joined(separator: ", ") + ".")
            }
            .disabled(camera.isRecording)
        }
    }

    private var zoomSection: some View {
        Section("Zoom") {
            labelledSlider(
                "Zoom",
                value: Binding(get: { camera.zoomFactor }, set: { camera.setZoom($0) }),
                range: camera.capabilities.minZoom...camera.capabilities.maxZoom,
                display: String(format: "%.1f×", camera.zoomFactor),
                icons: ("minus.magnifyingglass", "plus.magnifyingglass")
            )
        }
    }

    private var captureSection: some View {
        Section("Capture") {
            if camera.capabilities.supportsHDR {
                Toggle("HDR video", isOn: Binding(
                    get: { camera.hdrEnabled },
                    set: { camera.setHDR($0) }
                ))
            }
            if camera.capabilities.supportsStabilization {
                Toggle("Stabilisation", isOn: Binding(
                    get: { camera.stabilizationEnabled },
                    set: { camera.setStabilization($0) }
                ))
            }
            if camera.capabilities.supportsLowLightBoost {
                Toggle("Low-light boost", isOn: Binding(
                    get: { camera.lowLightBoostEnabled },
                    set: { camera.setLowLightBoost($0) }
                ))
            }
        }
    }

    // MARK: - Shared row

    /// A slider row in the shape iOS uses for these: title and current value
    /// on one line, the slider beneath it flanked by symbols showing which way
    /// is which.
    private func labelledSlider<V: BinaryFloatingPoint>(
        _ title: String,
        value: Binding<V>,
        range: ClosedRange<V>,
        step: V.Stride? = nil,
        display: String,
        icons: (String, String)
    ) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Image(systemName: icons.0)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    if let step {
                        Slider(value: value, in: range, step: step)
                    } else {
                        Slider(value: value, in: range)
                    }
                }
                .accessibilityIdentifier(title)
                Image(systemName: icons.1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// `presentationBackgroundInteraction` arrived in iOS 16.4 and the app still
/// supports 16.0, where the sheet keeps its dimming scrim — the script behind
/// is visible but dimmed rather than fully live.
private struct UncoveredPrompter: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackgroundInteraction(
                .enabled(upThrough: .fraction(PrompterControlsSheet.sheetHeight))
            )
        } else {
            content
        }
    }
}
