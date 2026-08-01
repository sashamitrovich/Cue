import SwiftUI
import Combine

struct PrompterView: View {
    @ObservedObject var state: TeleprompterState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpeechTracker()
    @StateObject private var camera = CameraController()

    @State private var wordFrames: [Int: CGRect] = [:]
    @State private var offset: CGFloat = 0
    @State private var targetOffset: CGFloat = 0
    @State private var lastVoiceTime = Date.distantPast
    @State private var dragStartOffset: CGFloat = 0
    @State private var errorMessage: String?
    @State private var errorWorkItem: DispatchWorkItem?
    @State private var showCameraControls = false
    @State private var pinchStartZoom: CGFloat = 1
    @State private var isPinching = false
    /// Speaking time only — paused stretches are excluded so the measured pace
    /// reflects time actually spent talking.
    @State private var clock = SpeakingClock()
    /// Re-read once a second to refresh the timing readout. The 60 fps ticker
    /// already redraws this view, so this only exists to change at 1 Hz.
    @State private var displayNow = Date()
    /// When the pre-roll countdown ends, or nil when none is running.
    @State private var countdownDeadline: Date?

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let cueY = geo.size.height * state.cueLineFraction

            ZStack {
                Color.black.ignoresSafeArea()

                if state.cameraEnabled {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea()
                        .scaleEffect(x: -1, y: 1)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    if !isPinching {
                                        pinchStartZoom = camera.zoomFactor
                                        isPinching = true
                                    }
                                    camera.setZoom(pinchStartZoom * scale)
                                }
                                .onEnded { _ in
                                    isPinching = false
                                }
                        )
                    Color.black.opacity(state.cameraDimming).ignoresSafeArea()
                }

                // The flow reports a height far taller than the screen (42vh
                // lead-in + script + 60vh tail), and a ZStack sizes itself to
                // its largest child — without pinning this to the screen's
                // frame the whole prompter lays out oversized and pushes the
                // bottom control bar off-screen.
                ScrollFlow(state: state, wordFrames: $wordFrames, topInset: cueY, bottomInset: geo.size.height * 0.6)
                    .coordinateSpace(name: "flow")
                    .opacity(state.cameraEnabled ? state.textOpacity : 1.0)
                    .offset(y: offset)
                    .scaleEffect(x: state.mirror ? -1 : 1, y: 1)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .clipped()

                // The top fade has to finish above the reading line, otherwise
                // it washes out the very words being read.
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: max(0, cueY * 0.55))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.25)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, cueY)
                    .allowsHitTesting(false)

                // Nudge the reading line up or down mid-take without opening
                // the settings sheet.
                VStack(spacing: 10) {
                    nudgeButton(icon: "chevron.up", delta: -0.02)
                    nudgeButton(icon: "chevron.down", delta: 0.02)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)

                if let remaining = countdownRemaining {
                    countdownOverlay(remaining)
                }

                VStack {
                    topBar
                    qualityPills
                    Spacer()
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.footnote)
                            .padding(12)
                            .background(Color(red: 0.16, green: 0.08, blue: 0.07))
                            .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.66))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 18)
                    }
                    footBar
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard state.manualMode else { return }
                        targetOffset = dragStartOffset + value.translation.height
                    }
                    .onEnded { _ in
                        guard state.manualMode else { return }
                        dragStartOffset = targetOffset
                    }
            )
            .onAppear {
                // A take is minutes of talking to the lens without touching
                // the screen, so iOS would dim and lock mid-recording. Held
                // for the whole prompter, not just while recording — the
                // screen going dark mid-read is just as bad.
                UIApplication.shared.isIdleTimerDisabled = true
                dragStartOffset = targetOffset
                recomputeTarget(cueY: cueY)
                speech.onTranscript = { words in
                    lastVoiceTime = Date()
                    state.ingest(transcriptWords: words)
                }
                if state.cameraEnabled {
                    camera.configureAndStart()
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                countdownDeadline = nil
                clock.pause(at: Date())
                speech.end()
                camera.stop()
            }
            .onChange(of: state.activeIndex) { _ in
                recomputeTarget(cueY: cueY)
            }
            .onChange(of: wordFrames.count) { _ in
                recomputeTarget(cueY: cueY)
            }
            .onChange(of: state.cueLineFraction) { fraction in
                recomputeTarget(cueY: geo.size.height * fraction)
            }
            .onChange(of: state.fontSize) { _ in
                // Word frames are re-measured after the relayout, so let that
                // land before repositioning against the reading line.
                DispatchQueue.main.async {
                    recomputeTarget(cueY: geo.size.height * state.cueLineFraction)
                }
            }
            .onReceive(ticker) { _ in
                let now = Date()
                if state.isListening && !state.manualMode && state.driftSpeed > 0 {
                    if now.timeIntervalSince(lastVoiceTime) > 1.2 {
                        targetOffset -= state.driftSpeed / 60
                    }
                }
                offset += (targetOffset - offset) * 0.12

                if let deadline = countdownDeadline, now >= deadline {
                    startListeningNow()
                }
                // Only publish a new date when the displayed second changes,
                // rather than 60 times a second for a readout that can't show it.
                if Int(now.timeIntervalSince1970) != Int(displayNow.timeIntervalSince1970) {
                    displayNow = now
                }
            }
            .onReceive(speech.$errorMessage.compactMap { $0 }) { showError($0) }
            .onReceive(camera.$errorMessage.compactMap { $0 }) { showError($0) }
            .onReceive(speech.$isListening) { listening in
                // If the tracker stops itself (e.g. a fatal recognition
                // error), reflect that in the play/pause button instead of
                // leaving it stuck showing "Listening".
                if !listening && state.isListening {
                    state.isListening = false
                    clock.pause(at: Date())
                }
            }
            .sheet(isPresented: $showCameraControls) {
                PrompterControlsSheet(camera: camera, state: state)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    // MARK: - Take control

    /// Whole seconds still to run on the pre-roll, or nil when none is running.
    private var countdownRemaining: Int? {
        guard let deadline = countdownDeadline else { return nil }
        return max(1, Int(deadline.timeIntervalSince(displayNow).rounded(.up)))
    }

    /// Starts a take, after the pre-roll if one is configured.
    private func beginTake() {
        guard !state.manualMode else { return }
        if state.countdownSeconds > 0 {
            displayNow = Date()
            countdownDeadline = Date().addingTimeInterval(Double(state.countdownSeconds))
        } else {
            startListeningNow()
        }
    }

    private func startListeningNow() {
        countdownDeadline = nil
        state.isListening = true
        lastVoiceTime = Date()
        clock.start(at: Date())
        speech.begin()
    }

    private func pauseTake() {
        countdownDeadline = nil
        state.isListening = false
        clock.pause(at: Date())
        speech.end()
    }

    // MARK: - Timing

    private var elapsed: TimeInterval { clock.elapsed(at: displayNow) }

    /// The pace estimates are built from: the speaker's own once enough of the
    /// take has been read to measure it, otherwise their configured target.
    private var effectiveWPM: Double {
        ReadingPace.effectiveWPM(
            baseline: state.targetWPM,
            wordsRead: state.wordsRead,
            elapsed: elapsed
        )
    }

    private var remainingSeconds: Double {
        ReadingPace.seconds(forWords: state.wordsRemaining, wpm: effectiveWPM)
    }

    private var isMeasuringPace: Bool {
        ReadingPace.measuredWPM(wordsRead: state.wordsRead, elapsed: elapsed) != nil
    }

    private func recomputeTarget(cueY: CGFloat) {
        guard let frame = wordFrames[state.activeIndex] else { return }
        targetOffset = cueY - frame.midY
        dragStartOffset = targetOffset
    }

    private func showError(_ msg: String) {
        errorMessage = msg
        errorWorkItem?.cancel()
        let item = DispatchWorkItem { errorMessage = nil }
        errorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isListening ? Color.orange : Color(.systemGray4))
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if camera.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(timeString(camera.recordingSeconds)).font(.caption).monospacedDigit()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red.opacity(0.16))
                    .clipShape(Capsule())
                }
                Button {
                    showCameraControls = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote)
                        .padding(8)
                        .background(.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Button("Exit") {
                    pauseTake()
                    camera.stop()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(Color(red: 1, green: 0.54, blue: 0.48))
            }

            if state.showTiming {
                timingRow
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        // With a high reading line the script can reach up behind the status
        // row, so give it its own backing rather than relying on the fade.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var statusText: String {
        if countdownRemaining != nil { return "Get ready…" }
        if state.manualMode { return "Manual — drag to scroll" }
        return state.isListening ? "Listening — speak your script" : "Tap play to begin"
    }

    /// Elapsed speaking time, time left at the current pace, and how far
    /// through the script the cursor is.
    private var timingRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Label(ReadingPace.timeString(elapsed), systemImage: "timer")
                    .labelStyle(.titleAndIcon)
                Text("·")
                // Marked "~" until there's enough of the take to measure the
                // speaker's real pace — before that it's only the target wpm.
                Text("\(isMeasuringPace ? "" : "~")\(ReadingPace.timeString(remainingSeconds)) left")
                Spacer()
                Text("\(Int(effectiveWPM.rounded())) wpm")
                    .foregroundStyle(isMeasuringPace ? Color.orange.opacity(0.9) : .secondary)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: max(0, bar.size.width * state.progress))
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Elapsed \(ReadingPace.timeString(elapsed)), about \(ReadingPace.timeString(remainingSeconds)) remaining")
    }

    /// Camera.app-style quality toggles: tap to switch size, tap to switch
    /// frame rate. Hidden while recording, because the capture format can't be
    /// changed without tearing down the file being written.
    @ViewBuilder
    private var qualityPills: some View {
        if state.cameraEnabled, !camera.isRecording, let mode = camera.selectedMode, let tier = camera.selectedTier {
            HStack(spacing: 8) {
                Spacer()
                if camera.capabilities.qualityTiers.count > 1 {
                    pill(mode.tierLabel) {
                        if let next = CaptureQualityMenu.nextTier(after: tier, in: camera.capabilities.qualityTiers) {
                            camera.selectTier(next)
                        }
                    }
                }
                if tier.frameRates.count > 1 {
                    pill(mode.frameRateLabel) { camera.cycleFrameRate() }
                }
            }
            .padding(.trailing, 18)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.23))
                .frame(minWidth: 34)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video quality \(text)")
    }

    private var footBar: some View {
        HStack(spacing: 28) {
            footButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.activeIndex = 0
                // A restart is a fresh take, so the timing starts over too.
                clock.reset()
                if state.isListening { clock.start(at: Date()) }
                displayNow = Date()
            }
            footButton(
                icon: countdownRemaining != nil ? "xmark" : (state.isListening ? "pause.fill" : "play.fill"),
                label: countdownRemaining != nil ? "Cancel" : (state.isListening ? "Pause" : "Listen"),
                primary: true
            ) {
                guard !state.manualMode else { return }
                if countdownRemaining != nil {
                    countdownDeadline = nil
                } else if state.isListening {
                    pauseTake()
                } else {
                    beginTake()
                }
            }
            if state.cameraEnabled {
                footButton(icon: camera.isRecording ? "stop.fill" : "circle.fill", label: camera.isRecording ? "Stop" : "Record") {
                    if camera.isRecording { camera.stopRecording() } else { camera.startRecording() }
                }
            }
            footButton(icon: "hand.raised.fill", label: "Manual", on: state.manualMode) {
                state.manualMode.toggle()
                if state.manualMode {
                    pauseTake()
                    dragStartOffset = targetOffset
                }
            }
        }
        .padding(.top, 34)
        .padding(.bottom, 12)
        // The script scrolls behind these controls, so they need their own
        // backing or the words render straight through the buttons. The stops
        // reach near-opaque well before the buttons begin — an evenly spaced
        // gradient is only ~30% dark by the time it reaches them.
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.92), location: 0.22),
                    .init(color: .black, location: 0.5),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    /// Pre-roll before a take. Deliberately sits above everything and takes the
    /// whole screen: tapping anywhere cancels, so a mistimed start doesn't
    /// force you to hunt for a small button.
    @ViewBuilder
    private func countdownOverlay(_ remaining: Int) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("\(remaining)")
                    .font(.system(size: 96, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.23))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.8), radius: 10)
                Text("Tap anywhere to cancel")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { countdownDeadline = nil }
        .accessibilityLabel("Starting in \(remaining) seconds")
        .zIndex(10)
    }

    @ViewBuilder
    private func nudgeButton(icon: String, delta: Double) -> some View {
        Button {
            state.cueLineFraction = min(0.6, max(0.05, state.cueLineFraction + delta))
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Move text up" : "Move text down")
    }

    @ViewBuilder
    private func footButton(icon: String, label: String, primary: Bool = false, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: primary ? 22 : 18))
                    .frame(width: primary ? 62 : 48, height: primary ? 62 : 48)
                    .background(primary ? Color.orange : Color(.secondarySystemBackground))
                    .foregroundStyle(primary ? .black : (on ? Color.orange : .primary))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(on ? Color.orange : .clear, lineWidth: 1.5)
                    )
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ScrollFlow: View {
    @ObservedObject var state: TeleprompterState
    @Binding var wordFrames: [Int: CGRect]
    /// Lead-in space so the first word can sit on the reading line, and tail
    /// space so the last word can scroll up to it. Driven by the live geometry
    /// rather than `UIScreen`, which reports the wrong height in landscape.
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        VStack(alignment: state.centerAlign ? .center : .leading, spacing: state.fontSize * 0.35) {
            ForEach(state.lines) { line in
                if line.isBlank {
                    // A blank line in the editor becomes real space here, so
                    // pauses and ad-lib room survive into the prompter.
                    Color.clear.frame(height: state.fontSize * 0.9)
                } else {
                    FlowLayout(spacing: 8, lineSpacing: 6) {
                        ForEach(line.words) { word in
                            wordView(word)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: state.centerAlign ? .center : .leading)
        .padding(.horizontal, 26)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .onPreferenceChange(WordFramePreferenceKey.self) { wordFrames = $0 }
    }

    @ViewBuilder
    private func wordView(_ word: ScriptWord) -> some View {
        let wordState = state.state(for: word.id)
        Text(word.raw)
            .font(.system(size: state.fontSize, weight: wordState == .spoken ? .medium : .semibold, design: .serif))
            .foregroundStyle(color(for: wordState))
            // Words sit over live video, so they need their own dark halo — a
            // flat colour alone disappears against faces, windows, and
            // anything else bright behind them.
            .shadow(color: .black.opacity(0.92), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.65), radius: 7)
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: WordFramePreferenceKey.self,
                        value: [word.id: g.frame(in: .named("flow"))]
                    )
                }
            )
    }

    private func color(for wordState: WordState) -> Color {
        switch wordState {
        // Already-read text drops well back so progress is obvious at a glance,
        // the current word is picked out in the accent colour, and what's still
        // to read stays at full brightness because that's what's being read.
        case .spoken: return Color(white: 0.34)
        case .active: return Color(red: 1.0, green: 0.72, blue: 0.23)
        case .upcoming: return Color(white: 0.96)
        }
    }
}
