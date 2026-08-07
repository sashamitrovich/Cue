import SwiftUI
import Combine

/// The prompter.
///
/// Design brief: behave like a first-party capture app. The content is the
/// script and the speaker's face, so the chrome defers to it — translucent
/// materials rather than opaque slabs, one accent colour used only where it
/// carries meaning, and controls that fade away once a take is running and
/// come back on a tap.
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
    @State private var showSettings = false
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
    /// Drives where the take controls live. Sizes still come from the
    /// `GeometryReader`; this is only used to decide *which* edge, which
    /// geometry can't tell us — both landscapes are the same shape.
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait
    /// Chrome hides itself during a take and returns on a tap.
    @State private var chromeVisible = true
    @State private var chromeHideAt: Date?
    /// Grows the handle while it's being dragged, so it's obvious what moved.
    @State private var isDraggingLine = false
    /// Intercepts spoken commands before the matcher sees the words.
    @State private var commandDetector = VoiceCommandDetector()
    /// Shown once, the first time a take starts: voice commands are otherwise
    /// invisible — nothing on screen suggests the prompter takes instructions.
    @State private var showVoiceTip = false
    private let tips = FirstRunTips()

    static let railWidth: CGFloat = 56
    /// Breathing room for the rail on a screen edge with no cutout of its own.
    static let edgeGap: CGFloat = 16
    /// The single accent. Used for the current word, the primary action and
    /// live values — nothing decorative, so it always means something.
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.23)
    /// How long the controls linger after the last touch once a take is live.
    private static let chromeLinger: TimeInterval = 4

    private var isLandscape: Bool { interfaceOrientation.isLandscape }
    /// `landscapeLeft` puts the edge that was the bottom in portrait on the
    /// left of the screen, so the controls follow it there and stay under the
    /// same thumb.
    private var railOnLeading: Bool { interfaceOrientation == .landscapeLeft }
    /// A take is running, so the chrome is allowed to get out of the way.
    private var takeIsLive: Bool { state.isListening || camera.isRecording }

    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            // A pure function of geometry — deliberately not of the measured
            // chrome height. Deriving it from a measurement made the line's
            // position depend on when that measurement landed: the script was
            // scrolled against one value while the line was drawn at another,
            // which is what put them 45pt apart in landscape. The floor is a
            // fraction instead, larger in landscape because the screen is
            // short enough for the bar to swallow a low reading line.
            let cueY = fullHeight(geo: geo, insets: insets)
                * min(0.6, max(isLandscape ? 0.34 : 0.16, state.cueLineFraction))

            ZStack {
                Color.black
                cameraLayer
                scriptLayer(geo: geo, insets: insets, cueY: cueY)

                // The status bar is information — where you are, how long is
                // left, whether it's recording — and stays put through a take.
                // Only the buttons fade, because only the buttons are in the
                // way. Hiding the readout meant touching the screen to find
                // out where you were, which defeats a hands-free prompter.
                chrome(geo: geo, insets: insets)

                if showVoiceTip {
                    voiceCommandTip(insets: insets)
                }

                if let remaining = countdownRemaining {
                    countdownOverlay(remaining)
                }
            }
            // The whole prompter bleeds to the edges — a camera app shows the
            // feed under the Dynamic Island and home indicator, and chrome is
            // padded by the insets instead.
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.28), value: isLandscape)
            .animation(.easeInOut(duration: 0.25), value: chromeVisible)
            .animation(.easeInOut(duration: 0.3), value: showVoiceTip)
            .contentShape(Rectangle())
            .onTapGesture { revealChrome(toggle: true) }
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
                // Screenshot hook: the simulator has no microphone, so the
                // cursor can only be placed for App Store captures by asking.
                if let index = ProcessInfo.processInfo.arguments
                    .drop(while: { $0 != "-uiTestingCursorAt" }).dropFirst().first,
                   let value = Int(index) {
                    state.activeIndex = min(max(0, value), max(0, state.words.count - 1))
                }
                syncInterfaceOrientation()
                dragStartOffset = targetOffset
                recomputeTarget(cueY: cueY)
                speech.onTranscript = { words in
                    lastVoiceTime = Date()
                    guard state.voiceCommandsEnabled else {
                        state.ingest(transcriptWords: words)
                        return
                    }
                    // Commands are pulled out first and their words swallowed:
                    // matching "scroll up" against the script would drag the
                    // cursor forward, fighting the jump the command just made.
                    let heard = commandDetector.process(
                        words, scriptAhead: state.upcomingWords(4)
                    )
                    for command in heard.commands {
                        // Rows as drawn, not lines as typed: a paragraph wraps
                        // into many rows on screen, and stepping by typed line
                        // jumped the whole paragraph.
                        if let target = VisualLines.wordStepping(
                            command.lineOffset, from: state.activeIndex,
                            frames: wordFrames, tolerance: state.fontSize * 0.5
                        ) {
                            state.activeIndex = target
                        } else {
                            state.moveCursor(lines: command.lineOffset)
                        }
                    }
                    if !heard.passthrough.isEmpty {
                        state.ingest(transcriptWords: heard.passthrough)
                    }
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
            // Keyed on the active word's measured position, not on the word
            // *count*: rotating rewraps every line and moves every frame while
            // the count stays identical, which left the script scrolled to
            // where the words used to be.
            //
            // Quantized deliberately. Measured geometry drives state here, and
            // that state moves the layout, which re-publishes the geometry —
            // at full precision the sub-pixel difference on each pass is
            // enough to keep that cycle running forever, pinning the CPU at
            // 100% and preventing layout from ever settling.
            .onChange(of: wordFrames[state.activeIndex].map { ($0.midY / 4).rounded() }) { _ in
                recomputeTarget(cueY: cueY, animated: false)
            }
            .onChange(of: state.cueLineFraction) { _ in
                // Same clamp as the layout above, or the script would scroll
                // to a line the chrome is covering.
                recomputeTarget(cueY: cueY)
            }
            .onChange(of: state.fontSize) { _ in
                // Word frames are re-measured after the relayout, so let that
                // land before repositioning against the reading line.
                DispatchQueue.main.async {
                    recomputeTarget(cueY: cueY)
                }
            }
            .onChange(of: isLandscape) { _ in
                // Rotation changes both the geometry and the chrome height;
                // re-measure after the new layout lands.
                DispatchQueue.main.async { recomputeTarget(cueY: cueY, animated: false) }
            }
            .onChange(of: takeIsLive) { live in
                if live { scheduleChromeHide() } else { revealChrome() }
            }
            .onReceive(ticker) { _ in
                let now = Date()
                if state.isListening && !state.manualMode && state.driftSpeed > 0 {
                    if now.timeIntervalSince(lastVoiceTime) > 1.2 {
                        targetOffset -= state.driftSpeed / 60
                    }
                }
                offset += (targetOffset - offset) * 0.12

                // Self-heal: keep the active word on the reading line no
                // matter what shook the layout. Rotation produces transient
                // layouts whose measurements can leave a stale offset — the
                // script would end up floating with the first line off
                // screen, and no discrete event fired afterwards to fix it.
                // Safe as a continuous check because these frames are in the
                // flow's own space and don't move when `offset` does.
                if !state.manualMode, !isDraggingLine, let frame = wordFrames[state.activeIndex] {
                    let want = cueY - frame.midY
                    if abs(want - targetOffset) > 1 {
                        targetOffset = want
                        dragStartOffset = want
                    }
                }

                if let deadline = countdownDeadline, now >= deadline {
                    startListeningNow()
                }
                if let hideAt = chromeHideAt, now >= hideAt {
                    chromeHideAt = nil
                    if takeIsLive && !showSettings { chromeVisible = false }
                }
                // Only publish a new date when the displayed second changes,
                // rather than 60 times a second for a readout that can't show it.
                if Int(now.timeIntervalSince1970) != Int(displayNow.timeIntervalSince1970) {
                    displayNow = now
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                syncInterfaceOrientation()
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
            .sheet(isPresented: $showSettings) {
                PrompterControlsSheet(camera: camera, state: state)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    // MARK: - Content layers

    @ViewBuilder
    private var cameraLayer: some View {
        if state.cameraEnabled {
            CameraPreviewView(session: camera.session)
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
                        .onEnded { _ in isPinching = false }
                )
            Color.black.opacity(state.cameraDimming)
        }
    }

    /// Where the rail starts, so it never stacks under the status bar. A
    /// stated constant rather than a measurement: the bar's contents are fixed
    /// and measuring it made the layout depend on the order measurements
    /// arrived in.
    private func chromeTopInset(insets: EdgeInsets) -> CGFloat {
        insets.top + (state.showTiming ? 78 : 48)
    }

    private func fullHeight(geo: GeometryProxy, insets: EdgeInsets) -> CGFloat {
        geo.size.height + insets.top + insets.bottom
    }

    private func scriptLayer(geo: GeometryProxy, insets: EdgeInsets, cueY: CGFloat) -> some View {
        // The flow reports a height far taller than the screen, and a ZStack
        // sizes itself to its largest child — without pinning this to the
        // screen's frame the whole prompter lays out oversized.
        ScrollFlow(
            state: state,
            wordFrames: $wordFrames,
            topInset: cueY,
            bottomInset: fullHeight(geo: geo, insets: insets) * 0.6,
            // The frame is full-bleed, so the script clears the safe areas
            // itself. The reader's margin is a floor over the inset, never
            // added to it.
            leadingInset: ScriptMargins.inset(
                safeArea: insets.leading, margin: state.sideMargin,
                rail: isLandscape && railOnLeading ? Self.railWidth : 0),
            trailingInset: ScriptMargins.inset(
                safeArea: insets.trailing, margin: state.sideMargin,
                rail: isLandscape && !railOnLeading ? Self.railWidth : 0)
        )
        .coordinateSpace(name: "flow")
        .opacity(state.cameraEnabled ? state.textOpacity : 1.0)
        .offset(y: offset)
        .scaleEffect(x: state.mirror ? -1 : 1, y: 1)
        // Pinned to an explicit frame — the flow is 2-3x taller than the
        // screen and an unpinned ZStack sizes to it, pushing the controls off
        // screen entirely. The frame is the *full* screen, insets included:
        // the container ignores the safe area, so a child sized to the inset
        // `geo` height gets centred and lands ~(top+bottom)/2 below the origin
        // the reading line measures from — which is why the line sat a line
        // and a half above the words it marks.
        .frame(
            width: geo.size.width + insets.leading + insets.trailing,
            height: fullHeight(geo: geo, insets: insets),
            alignment: .top
        )
        .clipped()
        // Drawn inside the same pinned frame as the script, deliberately: the
        // offset that scrolls the script is measured from this frame's origin,
        // so anchoring the line anywhere else means reconciling two coordinate
        // systems by arithmetic — which is exactly how it ended up 45pt out of
        // register in landscape.
        .overlay(alignment: .top) {
            readingLine(cueY: cueY, insets: insets, height: fullHeight(geo: geo, insets: insets))
        }
        .overlay(alignment: .top) {
            // A short scrim under the top chrome only. The old full-height
            // bottom fade had nothing to protect once the controls moved to a
            // rail, and read as a stray veil across the last line.
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: max(0, cueY * 0.7))
                .allowsHitTesting(false)
        }
    }

    /// A hairline with a grab handle at the leading edge — enough to find with
    /// your eye, not a rule drawn through the sentence, and draggable so the
    /// line can be moved mid-take without opening settings. This replaces the
    /// floating chevrons, which sat on top of the words they were meant to
    /// help you read.
    private func readingLine(cueY: CGFloat, insets: EdgeInsets, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Self.accent)
                .frame(width: 26, height: isDraggingLine ? 6 : 4)
                .overlay {
                    Capsule().stroke(.black.opacity(0.25), lineWidth: 0.5)
                }
                .contentShape(Rectangle().inset(by: -22))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            isDraggingLine = true
                            revealChrome()
                            guard height > 0 else { return }
                            state.cueLineFraction = min(0.6, max(0.08, value.location.y / height))
                        }
                        .onEnded { _ in isDraggingLine = false }
                )
                .opacity(chromeVisible ? 1 : 0.5)
                .accessibilityLabel("Reading line position")
                .accessibilityValue("\(Int(state.cueLineFraction * 100)) percent")
                .accessibilityAdjustableAction { direction in
                    let delta = direction == .increment ? 0.02 : -0.02
                    state.cueLineFraction = min(0.6, max(0.08, state.cueLineFraction + delta))
                }
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, cueY)
        // Same rule as the script, so the line starts and ends with the words.
        .padding(.leading, ScriptMargins.inset(
            safeArea: insets.leading, margin: state.sideMargin,
            rail: isLandscape && railOnLeading ? Self.railWidth : 0))
        .padding(.trailing, ScriptMargins.inset(
            safeArea: insets.trailing, margin: state.sideMargin,
            rail: isLandscape && !railOnLeading ? Self.railWidth : 0))
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("readingLine")
    }

    // MARK: - Chrome

    @ViewBuilder
    private func chrome(geo: GeometryProxy, insets: EdgeInsets) -> some View {
        ZStack {
            VStack(spacing: 0) {
                statusBar(insets: insets)
                Spacer(minLength: 0)
                if let msg = errorMessage {
                    errorBanner(msg)
                        .padding(.bottom, 12)
                }
                if !isLandscape {
                    controlBar(insets: insets)
                        .modifier(FadingControls(visible: chromeVisible))
                }
            }

            if isLandscape {
                HStack(spacing: 0) {
                    if railOnLeading { controlRail(insets: insets) }
                    Spacer(minLength: 0)
                    if !railOnLeading { controlRail(insets: insets) }
                }
                .modifier(FadingControls(visible: chromeVisible))
            }
        }
    }

    /// One bar at the top: state, timing, and the two controls that aren't
    /// part of running a take. Everything is one type size and one weight so
    /// nothing shouts.
    private func statusBar(insets: EdgeInsets) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(state.isListening ? Self.accent : Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 8)

                if camera.isRecording { recordingBadge }

                if state.cameraEnabled, let mode = camera.selectedMode, let tier = camera.selectedTier {
                    qualityControl(mode: mode, tier: tier)
                }

                glassButton(
                    icon: state.cameraEnabled ? "video.fill" : "video.slash.fill",
                    label: state.cameraEnabled ? "Turn camera off" : "Turn camera on",
                    tinted: state.cameraEnabled
                ) { toggleCamera() }
                .disabled(camera.isRecording)

                glassButton(icon: "slider.horizontal.3", label: "Prompter settings") {
                    revealChrome()
                    showSettings = true
                }

                glassButton(icon: "xmark", label: "Exit") {
                    pauseTake()
                    camera.stop()
                    dismiss()
                }
            }

            if state.showTiming { timingRow }
        }
        .padding(.horizontal, 16)
        .padding(.top, insets.top + 8)
        .padding(.bottom, 10)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .background {
            // Material, not black: the feed stays readable through the bar,
            // which is what keeps the chrome feeling like a layer over the
            // picture rather than a lid on it.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
                .allowsHitTesting(false)
        }
    }

    /// Elapsed, remaining and pace, plus progress as a hairline rather than a
    /// bar — it's ambient information, not a control.
    private var timingRow: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(ReadingPace.timeString(elapsed))
                Text("·").foregroundStyle(.white.opacity(0.3))
                // Marked "~" until there's enough of the take to measure the
                // speaker's real pace — before that it's only the target wpm.
                Text("\(isMeasuringPace ? "" : "~")\(ReadingPace.timeString(remainingSeconds)) left")
                Spacer(minLength: 0)
                Text("\(Int(effectiveWPM.rounded())) wpm")
                    .foregroundStyle(isMeasuringPace ? Self.accent.opacity(0.95) : .white.opacity(0.5))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))

            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(Self.accent.opacity(0.9))
                        .frame(width: max(0, bar.size.width * state.progress))
                }
            }
            .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Elapsed \(ReadingPace.timeString(elapsed)), about \(ReadingPace.timeString(remainingSeconds)) remaining")
    }

    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text(timeString(camera.recordingSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// Quality as one compact control in the bar, rather than pills floating
    /// over the script with nothing to anchor them.
    private func qualityControl(mode: VideoMode, tier: QualityTier) -> some View {
        HStack(spacing: 0) {
            Button {
                revealChrome()
                if let next = CaptureQualityMenu.nextTier(after: tier, in: camera.capabilities.qualityTiers) {
                    camera.selectTier(next)
                }
            } label: {
                Text(mode.tierLabel)
                    .frame(minWidth: 30)
                    .padding(.vertical, 5)
            }
            .disabled(camera.capabilities.qualityTiers.count < 2 || camera.isRecording)

            Rectangle().fill(.white.opacity(0.14)).frame(width: 0.5, height: 16)

            Button {
                revealChrome()
                camera.cycleFrameRate()
            } label: {
                Text(mode.frameRateLabel)
                    .frame(minWidth: 28)
                    .padding(.vertical, 5)
            }
            .disabled(tier.frameRates.count < 2 || camera.isRecording)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(camera.isRecording ? .white.opacity(0.35) : .white.opacity(0.9))
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityLabel("Video quality \(mode.label)")
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 18)
    }

    // MARK: - Take controls

    /// The same four controls in both orientations, in the same order, at the
    /// same weight — only the axis changes.
    @ViewBuilder
    private var controlButtons: some View {
        takeButton(icon: "arrow.counterclockwise", label: "Restart") {
            state.activeIndex = 0
            // A restart is a fresh take, so the timing starts over too.
            clock.reset()
            if state.isListening { clock.start(at: Date()) }
            displayNow = Date()
        }
        takeButton(
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
            takeButton(
                icon: camera.isRecording ? "stop.fill" : "circle.fill",
                label: camera.isRecording ? "Stop" : "Record",
                recording: camera.isRecording
            ) {
                if camera.isRecording { camera.stopRecording() } else { camera.startRecording() }
            }
        }
        takeButton(icon: "hand.raised.fill", label: "Manual", on: state.manualMode) {
            state.manualMode.toggle()
            if state.manualMode {
                pauseTake()
                dragStartOffset = targetOffset
            }
        }
    }

    private func controlBar(insets: EdgeInsets) -> some View {
        HStack(spacing: 0) { controlButtons }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, insets.bottom > 0 ? insets.bottom : 14)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                    }
                    .allowsHitTesting(false)
            }
    }

    /// The landscape form: the same controls stacked against the edge they
    /// occupied in portrait, costing horizontal space instead of the vertical
    /// space landscape has none of.
    private func controlRail(insets: EdgeInsets) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            controlButtons
            Spacer(minLength: 0)
        }
        .frame(width: Self.railWidth)
        // The real inset where there is one, a small floor where there
        // isn't: on a phone without a cutout the insets are zero, which put
        // the buttons ~7pt from the screen edge. Never both, or the rail
        // floats in a wide black band on notched devices.
        .padding(.leading, railOnLeading ? max(insets.leading, Self.edgeGap / 2) : 0)
        .padding(.trailing, railOnLeading ? 0 : max(insets.trailing, Self.edgeGap / 2))
        .padding(.vertical, 4)
        .padding(.top, chromeTopInset(insets: insets))
        .padding(.bottom, insets.bottom)
        .frame(maxHeight: .infinity)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: railOnLeading ? .trailing : .leading) {
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5)
                }
                .padding(.top, chromeTopInset(insets: insets))
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// One control: a circular glass button with its label beneath. Uniform
    /// size and weight, so the accent fill on the primary action is the only
    /// thing that stands out.
    @ViewBuilder
    private func takeButton(
        icon: String,
        label: String,
        primary: Bool = false,
        on: Bool = false,
        recording: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            revealChrome()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(primary ? AnyShapeStyle(Self.accent) : AnyShapeStyle(.ultraThinMaterial))
                        .overlay(Circle().stroke(.white.opacity(primary ? 0 : 0.14), lineWidth: 0.5))
                    Image(systemName: icon)
                        .font(.system(size: primary ? 20 : 17, weight: .semibold))
                        .foregroundStyle(
                            primary ? Color.black
                                : (recording ? Color.red : (on ? Self.accent : Color.white))
                        )
                }
                .frame(width: isLandscape ? 42 : 52, height: isLandscape ? 42 : 52)

                if !isLandscape {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(on ? Self.accent : .white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A one-time hint that the prompter takes spoken instructions. Sits
    /// under the status bar rather than over the script, and fades on its own.
    private func voiceCommandTip(insets: EdgeInsets) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
            Text("Say **\"scroll up\"** to go back a line")
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
        .padding(.top, insets.top + chromeTopInset(insets: insets) - insets.top + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityLabel("Tip: say scroll up to go back a line")
    }

    /// Pre-roll before a take. Full screen and tap-anywhere-to-cancel, so a
    /// mistimed start doesn't send you hunting for a small button.
    @ViewBuilder
    private func countdownOverlay(_ remaining: Int) -> some View {
        ZStack {
            // Deliberately not a blur or a scrim: the whole point of a
            // pre-roll is to check your framing, posture and eyeline before
            // you speak, so the picture has to stay legible underneath.
            Color.clear
            VStack(spacing: 8) {
                Text("\(remaining)")
                    .font(.system(size: 108, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.accent)
                    .shadow(color: .black.opacity(0.85), radius: 14)
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .contentTransition(.numericText(countsDown: true))
                Text("Tap anywhere to cancel")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 6)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { countdownDeadline = nil }
        .accessibilityLabel("Starting in \(remaining) seconds")
        .transition(.opacity)
        .zIndex(10)
    }

    // MARK: - Chrome visibility

    /// Brings the controls back and restarts the linger timer. Called from
    /// every control, so using one never makes the others vanish underneath
    /// your thumb.
    private func revealChrome(toggle: Bool = false) {
        if toggle && chromeVisible && takeIsLive {
            chromeVisible = false
            chromeHideAt = nil
            return
        }
        chromeVisible = true
        scheduleChromeHide()
    }

    private func scheduleChromeHide() {
        chromeHideAt = takeIsLive ? Date().addingTimeInterval(Self.chromeLinger) : nil
    }

    /// Read from the window scene rather than `UIDevice.orientation`, which
    /// also reports face-up and face-down — neither of which changes the
    /// layout, and both of which would otherwise throw the rail to a random
    /// side when the phone is set down on a table.
    private func syncInterfaceOrientation() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let orientation = scene?.interfaceOrientation, orientation != .unknown {
            interfaceOrientation = orientation
        }
    }

    // MARK: - Take control

    /// Whole seconds still to run on the pre-roll, or nil when none is running.
    private var countdownRemaining: Int? {
        guard let deadline = countdownDeadline else { return nil }
        return max(1, Int(deadline.timeIntervalSince(displayNow).rounded(.up)))
    }

    private var statusText: String {
        if countdownRemaining != nil { return "Get ready…" }
        if state.manualMode { return "Manual — drag to scroll" }
        return state.isListening ? "Listening" : "Tap play to begin"
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
        if tips.shouldShowVoiceCommandTip(commandsEnabled: state.voiceCommandsEnabled) {
            showVoiceTip = true
            tips.markVoiceCommandTipSeen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { showVoiceTip = false }
        }
        state.isListening = true
        lastVoiceTime = Date()
        clock.start(at: Date())
        speech.begin()
        scheduleChromeHide()
    }

    private func pauseTake() {
        commandDetector.reset()
        countdownDeadline = nil
        state.isListening = false
        clock.pause(at: Date())
        speech.end()
        chromeVisible = true
    }

    /// Starts or tears down the capture session live, so the button's effect
    /// is visible immediately behind the script.
    private func toggleCamera() {
        guard !camera.isRecording else { return }
        state.cameraEnabled.toggle()
        if state.cameraEnabled {
            camera.configureAndStart()
        } else {
            camera.stop()
        }
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

    private func recomputeTarget(cueY: CGFloat, animated: Bool = true) {
        guard let frame = wordFrames[state.activeIndex] else { return }
        let newTarget = cueY - frame.midY
        // A change too small to see is not worth a state write — writing one
        // re-enters layout, which is how the feedback loop starts.
        guard abs(newTarget - targetOffset) > 0.5 || offset == 0 else { return }
        targetOffset = newTarget
        dragStartOffset = newTarget
        // The first layout has nothing to animate from: snap, or the opening
        // line sits below the reading line until the cursor happens to move.
        if !animated || offset == 0 { offset = newTarget }
    }

    private func showError(_ msg: String) {
        errorMessage = msg
        revealChrome()
        errorWorkItem?.cancel()
        let item = DispatchWorkItem { errorMessage = nil }
        errorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }

    /// A small circular control for the things that aren't part of running a
    /// take: camera, settings, exit.
    @ViewBuilder
    private func glassButton(icon: String, label: String, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tinted ? Self.accent : .white.opacity(0.9))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Fades a control out of the way during a take, and takes it out of the
/// hit-testing while hidden so an invisible button can't be tapped.
private struct FadingControls: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
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
    /// Extra side padding so the script clears the landscape control rail.
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

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
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .onPreferenceChange(WordFramePreferenceKey.self) { wordFrames = $0 }
    }

    @ViewBuilder
    private func wordView(_ word: ScriptWord) -> some View {
        let wordState = state.state(for: word.id)
        let wordsBehind = state.activeIndex - word.id
        // System type, not a serif: SF is drawn for screen legibility at a
        // glance, which is the whole job here — you read this in your
        // peripheral vision while looking at a lens.
        Text(word.raw)
            .font(.system(size: state.fontSize, weight: wordState == .spoken ? .semibold : .bold, design: .default))
            .foregroundStyle(color(for: wordState, wordsBehind: wordsBehind))
            // Words sit over live video, so they need their own dark halo — a
            // flat colour alone disappears against faces, windows, and
            // anything else bright behind them.
            .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 8)
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: WordFramePreferenceKey.self,
                        value: [word.id: g.frame(in: .named("flow"))]
                    )
                }
            )
    }

    private func color(for wordState: WordState, wordsBehind: Int) -> Color {
        switch wordState {
        // Read text fades with distance rather than dropping to one flat grey,
        // so the line just spoken can still be read from across a room; the
        // current word is picked out in the accent colour, and what's still to
        // read stays at full brightness because that's what's being read.
        case .spoken:
            return Color(white: ReadTextFade.brightness(
                wordsBehind: wordsBehind, floor: state.readTextFloor))
        case .active: return PrompterView.accent
        case .upcoming: return Color(white: 0.97)
        }
    }
}
