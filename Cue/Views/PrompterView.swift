import SwiftUI
import Combine

/// The prompter.
///
/// Design brief: behave like a first-party capture app. The content is the
/// script and the speaker's face, so the chrome defers to it — translucent
/// materials rather than opaque slabs, one accent colour used only where it
/// carries meaning, and controls that recede once a take is running and
/// brighten again on a tap — without ever leaving the screen.
struct PrompterView: View {
    @ObservedObject var state: TeleprompterState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// A leader that sweeps is exactly what this setting exists to suppress.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the leader's sweeping hand. Set once on appear; the animation
    /// runs on the render server, deliberately not from `tick()` — driving it
    /// there would pin the display link at full rate and undo the work that
    /// stopped the prompter animating when nothing moves.
    @State private var leaderSweeping = false

    @StateObject private var speech = SpeechTracker()
    @StateObject private var camera = CameraController()

    @State private var wordFrames: [Int: CGRect] = [:]
    @State private var offset: CGFloat = 0
    @State private var targetOffset: CGFloat = 0
    #if DEBUG
    @State private var pursuitDiagnostics = PursuitDiagnostics()
    #endif
    /// The live reading-line position, for the ticker — see the `onChange`
    /// that maintains it.
    @State private var tickCueY: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var errorMessage: String?
    @State private var errorWorkItem: DispatchWorkItem?
    /// A neutral confirmation — currently only "take saved" — kept separate
    /// from `errorMessage` so success never renders in the failure colour.
    @State private var noticeMessage: String?
    @State private var noticeWorkItem: DispatchWorkItem?
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
    /// Set when Record is tapped while listening hasn't started yet, so
    /// recording begins the moment listening actually does (after any
    /// pre-roll) instead of needing a second tap.
    @State private var pendingRecordOnListen = false
    /// Drives where the take controls live. Sizes still come from the
    /// `GeometryReader`; this is only used to decide *which* edge, which
    /// geometry can't tell us — both landscapes are the same shape.
    @State private var interfaceOrientation: UIInterfaceOrientation = .portrait
    /// Landscape vs portrait, read from the layout itself. The scene's
    /// `interfaceOrientation` is authoritative for *which* landscape but not
    /// for *when*: `UIDevice.orientationDidChangeNotification` fires before
    /// the scene has rotated, so reading it there could latch a stale value
    /// with nothing scheduled to correct it — the chrome then kept its
    /// landscape rail after a rotation back to portrait, leaving the take
    /// controls off the screen entirely.
    @State private var isLandscapeLayout = false
    /// Chrome hides itself during a take and returns on a tap.
    @State private var chromeVisible = true
    @State private var chromeHideAt: Date?
    /// Grows the handle while it's being dragged, so it's obvious what moved.
    @State private var isDraggingLine = false
    /// True only while a finger is actively dragging the script. Scrolling
    /// works at any time — listening or not — rather than needing a mode, so
    /// this just suppresses the auto-follow logic for the moment of the drag
    /// itself instead of gating the gesture.
    @State private var isDraggingScript = false
    /// Intercepts spoken commands before the matcher sees the words.
    @State private var commandDetector = VoiceCommandDetector()
    /// Shown once, the first time a take starts: voice commands are otherwise
    /// invisible — nothing on screen suggests the prompter takes instructions.
    @State private var showVoiceTip = false
    @State private var voiceTipWorkItem: DispatchWorkItem?
    private let tips = FirstRunTips()

    /// The take controls' circles in portrait, and the width each one claims
    /// in the shared control row — wide enough for the caption beneath it.
    static let takeButtonSize: CGFloat = 52
    static let takeButtonSlot: CGFloat = 64
    /// The same circles in the landscape rail, which has less room.
    static let railButtonSize: CGFloat = 42
    /// Camera / settings / exit.
    static let glassButtonSize: CGFloat = 34

    static let railWidth: CGFloat = 56
    /// Breathing room for the rail on a screen edge with no cutout of its own.
    static let edgeGap: CGFloat = 16
    /// The single accent. Used for the current word, the primary action and
    /// live values — nothing decorative, so it always means something.
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.23)
    /// The ground the whole app sits on. A barely-cool near-black rather than
    /// pure black, so the amber reads as light being emitted rather than as a
    /// brand colour laid on top of nothing.
    ///
    /// It is a real trade, not a free one. Pure black on OLED is *off pixels*:
    /// deeper contrast for reading in peripheral vision, and less light thrown
    /// onto the speaker's face in a dark room — which matters for an app you
    /// point a camera at yourself with. Judge any change here on a device in
    /// the dark, never on a screenshot.
    static let ground = Color(red: 0x07 / 255, green: 0x09 / 255, blue: 0x0C / 255)
    /// How long the controls linger after the last touch once a take is live.
    private static let chromeLinger: TimeInterval = 4

    private var isLandscape: Bool { isLandscapeLayout }
    /// `landscapeLeft` puts the edge that was the bottom in portrait on the
    /// left of the screen, so the controls follow it there and stay under the
    /// same thumb.
    private var railOnLeading: Bool { interfaceOrientation == .landscapeLeft }
    /// A take is running, so the chrome is allowed to get out of the way.
    private var takeIsLive: Bool { state.isListening || camera.isRecording }

    /// Held in a `@StateObject` rather than built inline: a publisher created
    /// as a `let` on a `View` struct is re-allocated every time SwiftUI
    /// re-initialises that struct.
    @StateObject private var ticker = PrompterTicker()

    /// How close `offset` has to get to its target before it stops being
    /// worth a state write. The smoothing below is exponential and therefore
    /// approaches its target without ever arriving; writing the result every
    /// frame regardless re-evaluated the whole prompter — every word view
    /// included — 60 times a second, forever, long after the movement had
    /// become invisible. Below this the offset snaps once and goes quiet.
    private static let settleThreshold: CGFloat = 0.05
    /// Exponential-smoothing time constant, in seconds: the scroll closes
    /// ~63% of its remaining distance every `smoothingTau`.
    ///
    /// The step used to be a flat `gap * 0.12` per *frame*, which made the
    /// speed a function of the refresh rate — the same scroll ran at one
    /// speed on a 60 Hz panel, twice that on a 120 Hz one, and half of it in
    /// Low Power Mode. It is now frame-rate independent on every device.
    ///
    /// It exists only to animate *jumps* — a restart, a rotation, the end of
    /// a drag. The paced pursuit already produces continuous motion, so
    /// filtering its output again was two lag stages stacked: 0.13 was
    /// inherited from when this was the only smoothing there was, and on top
    /// of the pursuit nearly all it added was delay. 0.05 still takes the
    /// edge off a jump (~95% closed in 0.15s) without putting an eighth of a
    /// second between the reader and the script.
    private static let smoothingTau: CGFloat = 0.05
    /// Seconds the pursuit would take to close the gap if nothing capped it.
    /// This is what keeps the active word *on* the reading line rather than
    /// somewhere below it.
    private static let pursuitResponse: CGFloat = 0.18
    /// Ceiling on the pursuit, as a multiple of the speaking pace — what
    /// stops a burst of recognised words being covered instantly.
    ///
    /// It was 1.3, which was far too low to be a ceiling and acted as a flat
    /// speed instead: the gap closed at only 0.3x pace, so the script never
    /// actually caught up and the reader's eyes drifted down the screen
    /// chasing a word that sat permanently below the line. At 4 the gap
    /// closes at 3x pace when this is the binding constraint, which recovers
    /// a burst in well under a second while still spreading it over enough
    /// frames to read as movement rather than a jump.
    /// Floor for the pursuit speed — the opening words of a take, before
    /// there is a measured pace or a usable per-word spacing estimate.
    private static let pursuitMaxCatchUp: CGFloat = 4
    private static let pursuitMinSpeed: CGFloat = 40
    /// Past this, the cursor didn't advance — it was *moved* (a restart, a
    /// drag, a rotation, a voice command). Travelling that at speaking pace
    /// would take tens of seconds, so the target goes straight there and the
    /// smoothing animates it.
    private static let pursuitSnapDistance: CGFloat = 900
    /// Words ahead of the cursor used to estimate how far the script travels
    /// per spoken word. Local rather than global, so it reflects the current
    /// font size and line wrapping.
    private static let pursuitLookahead = 8
    /// Set when the cursor was moved deliberately rather than by recognition,
    /// so the next tick goes straight there instead of pacing.
    @State private var cursorJumped = false
    /// The cursor position the layout re-target handler last saw, so it can
    /// tell a relayout (same word, new frame) from a cursor move (new word).
    @State private var lastFrameKeyIndex = 0
    /// Timestamp of the previous tick, for the elapsed time the smoothing
    /// above needs. Nil before the first tick of a run.
    @State private var lastTickTime: Date?

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
                Self.ground
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
                        isDraggingScript = true
                        targetOffset = dragStartOffset + value.translation.height
                    }
                    .onEnded { _ in
                        dragStartOffset = targetOffset
                        // Wherever the drag stopped becomes the reading
                        // position, so pausing to record a later scene and
                        // scrolling ahead to it picks tracking back up there
                        // instead of where it was left off — whether or not
                        // listening was running while the drag happened.
                        if let target = VisualLines.nearestRowStart(toFlowY: cueY - targetOffset, frames: wordFrames) {
                            state.activeIndex = target
                            // Placed by hand, not reached by reading it.
                            cursorJumped = true
                            state.resyncMatcher()
                        }
                        isDraggingScript = false
                    }
            )
            .onAppear {
                // A take is minutes of talking to the lens without touching
                // the screen, so iOS would dim and lock mid-recording. Held
                // for the whole prompter, not just while recording — the
                // screen going dark mid-read is just as bad.
                UIApplication.shared.isIdleTimerDisabled = true
                isLandscapeLayout = geo.size.width > geo.size.height
                syncInterfaceOrientation()
                // Screenshot hook: the simulator has no microphone, so the
                // cursor can only be placed for App Store captures by asking.
                if let index = ProcessInfo.processInfo.arguments
                    .drop(while: { $0 != "-uiTestingCursorAt" }).dropFirst().first,
                   let value = Int(index) {
                    state.activeIndex = min(max(0, value), max(0, state.words.count - 1))
                    cursorJumped = true
                }
                // Same idea, for Mirror: driving the Toggle itself through
                // XCUITest is unreliable inside a scrolled Form, and the
                // effect is trivial to set directly.
                if ProcessInfo.processInfo.arguments.contains("-uiTestingMirrorOn") {
                    state.mirror = true
                }
                // Same idea, for the Record badge: the simulator has no
                // camera, so a capture can't actually be running to
                // photograph. Faked only for the capture, never a real state
                // reachable in the shipped app.
                // The pre-roll lasts seconds and cannot be paused, so it
                // cannot be photographed by driving the UI. Faked for capture
                // only, like the recording state above it.
                if ProcessInfo.processInfo.arguments.contains("-uiTestingShowCountdown") {
                    // Deliberately not enabling the camera: the armed state
                    // needs only a queued recording, and turning the camera on
                    // puts a permission dialog over the shot.
                    pendingRecordOnListen = true
                    countdownDeadline = Date().addingTimeInterval(3.4)
                }
                if ProcessInfo.processInfo.arguments.contains("-uiTestingShowRecording") {
                    state.cameraEnabled = true
                    camera.isRecording = true
                    camera.recordingSeconds = 14
                    // Listening too, because recording without it is not a
                    // state a real take reaches — `beginRecordingTake` starts
                    // both. Faking only the recording half produced a
                    // marketing screenshot that contradicted itself: a red
                    // tally counting up, next to a play button inviting you
                    // to start listening.
                    state.isListening = true
                }
                syncInterfaceOrientation()
                tickCueY = cueY
                ticker.start { tick(now: $0) }
                dragStartOffset = targetOffset
                recomputeTarget(cueY: cueY)
                speech.onTranscript = { words in
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
                            cursorJumped = true
                            state.resyncMatcher()
                        } else {
                            state.moveCursor(lines: command.lineOffset)
                            cursorJumped = true
                            state.resyncMatcher()
                        }
                    }
                    if !heard.passthrough.isEmpty {
                        state.ingest(transcriptWords: heard.passthrough)
                    }
                }
                if state.cameraEnabled && !ProcessInfo.processInfo.arguments.contains("-uiTestingShowRecording") {
                    camera.configureAndStart()
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                ticker.stop()
                errorWorkItem?.cancel()
                noticeWorkItem?.cancel()
                voiceTipWorkItem?.cancel()
                countdownDeadline = nil
                clock.pause(at: Date())
                speech.end()
                camera.stop()
            }
            .onChange(of: state.activeIndex) { _ in
                // Deliberately does *not* re-target. Setting the target to
                // the new word here is what produced the stall-then-jump —
                // the paced pursuit in `tick` walks it there at speaking
                // pace instead. All this has to do is make sure there are
                // frames to walk in.
                ticker.setActive(true)
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
                // This key also changes when the *cursor* moves, since it
                // then reads a different word's frame — and that case is the
                // paced pursuit's business, not an immediate re-target.
                // Only act when the same word's frame moved underneath us,
                // which is what a relayout looks like.
                if state.activeIndex == lastFrameKeyIndex {
                    recomputeTarget(cueY: cueY, animated: false)
                }
                lastFrameKeyIndex = state.activeIndex
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
            // The ticker's callback is registered once, so it must not close
            // over `cueY` — that local would freeze at whatever the reading
            // line was when the prompter appeared and never follow a rotation
            // or a drag of the handle. Mirrored into state instead, which the
            // callback reads live. Still a pure function of geometry, so this
            // is not the measurement-drives-layout cycle `cueY` is kept out of.
            .onChange(of: cueY) { tickCueY = $0 }
            .onChange(of: geo.size.width > geo.size.height) { landscape in
                isLandscapeLayout = landscape
                // The scene has rotated by the time the layout has, so this
                // is also the reliable moment to re-read which landscape it
                // is — the rail's edge depends on it.
                syncInterfaceOrientation()
                // Rotating is a deliberate act, and the controls move to a
                // different edge when you do it — coming out of a rotation
                // to a screen with no buttons on it reads as the app having
                // lost them, since nothing on screen says a tap brings them
                // back. Mid-take they still linger away again afterwards.
                revealChrome()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Still needed for landscapeLeft <-> landscapeRight, where
                // the geometry above never changes.
                DispatchQueue.main.async { syncInterfaceOrientation() }
            }
            .onReceive(speech.$errorMessage.compactMap { $0 }) { showError($0) }
            .onReceive(camera.$errorMessage.compactMap { $0 }) { showError($0) }
            .onReceive(camera.$savedMessage.compactMap { $0 }) { msg in
                showNotice(msg)
                Haptics.success()
                camera.savedMessage = nil
            }
            // Leaving the app mid-take: iOS takes the microphone and the
            // capture session away regardless, so end the take deliberately
            // rather than coming back to a prompter that claims to be
            // listening and isn't. A recording is stopped rather than
            // abandoned, which saves what was captured instead of losing it
            // to an interrupted session.
            // A recording that ends by any route ends the take with it. The
            // two deliberate paths (the Stop button, leaving the app) already
            // paused, but a recording can also stop on its own — a capture
            // error, or the disk filling — and that left the microphone open
            // and the script still following a take the reader believed was
            // over.
            .onChange(of: camera.isRecording) { recording in
                if !recording && state.isListening { pauseTake() }
            }
            .onChange(of: scenePhase) { phase in
                guard phase != .active else { return }
                if camera.isRecording { camera.stopRecording() }
                if state.isListening || countdownDeadline != nil { pauseTake() }
            }
            // The tracker is the authority on whether the microphone is
            // actually running, so the prompter follows it in both
            // directions: down when it stops itself (a fatal recognition
            // error, or iOS taking the mic for a call), and back up when it
            // resumes on its own once the interruption ends. Following it
            // down alone left a take that recovered showing "Tap play to
            // begin" while it was in fact listening.
            .onReceive(speech.$isListening) { listening in
                guard listening != state.isListening else { return }
                state.isListening = listening
                // The speaking clock excludes anything that isn't talking, so
                // it tracks this exactly.
                if listening { clock.start(at: Date()) } else { clock.pause(at: Date()) }
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
        // Dimmed while the pre-roll runs, so the leader can be read without a
        // scrim. The distinction matters: this fades the *text*, not the
        // picture — the whole point of a pre-roll is checking your framing and
        // eyeline, so the camera must stay fully legible underneath. At full
        // brightness the script ran straight through the numeral and both read
        // badly.
        .opacity((state.cameraEnabled ? state.textOpacity : 1.0) * (countdownRemaining != nil ? 0.30 : 1.0))
        .animation(.easeInOut(duration: 0.25), value: countdownRemaining != nil)
        .offset(y: offset)
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
        // A full 180° turn, not just a left-right mirror: a rig applies its
        // own 180° flip to whatever the app renders, so the script needs to
        // pre-compensate with the same flip — the chrome stays untouched
        // and reachable wherever it normally sits, since it's read directly
        // rather than through the glass.
        //
        // Deliberately the *default* (center) anchor, applied last, to the
        // already fully-scrolled and clipped screen. Normal (unmirrored)
        // rendering always fills the whole screen already — the small
        // sliver above the cue line is "already read" text, which is why
        // there's never a gap in ordinary use. Transforming that always-full
        // screen around its own true center just repositions it; a
        // reflection about a box's own center maps the box onto itself
        // exactly, so a fully-covered screen stays fully covered, just
        // flipped. Anchoring anywhere off-center (the cue line's position,
        // say) does *not* have that property — it relocates the whole box
        // within its parent instead of just reorienting its content, which
        // is what opened a gap on one edge in an earlier version of this.
        //
        // A vertical flip, not a full 180° rotation: confirmed on the
        // user's actual rig that a 180° turn alone still didn't read
        // correctly and needed a further horizontal flip on top — the two
        // horizontal flips cancel out, netting a top-to-bottom flip only.
        .scaleEffect(x: 1, y: state.mirror ? -1 : 1)
        // Drawn inside the same pinned frame as the script, deliberately: the
        // offset that scrolls the script is measured from this frame's origin,
        // so anchoring the line anywhere else means reconciling two coordinate
        // systems by arithmetic — which is exactly how it ended up 45pt out of
        // register in landscape.
        //
        // Rotated the same way as the script and for the same reason: an
        // `.overlay` is a sibling view aligned to the script's (rotated)
        // bounds, not content carried along by that rotation — without its
        // own matching rotation the line stayed at the raw top of the
        // screen while the active word it's meant to mark moved to the
        // raw bottom, so the two only lined up before mirroring existed.
        .overlay(alignment: .top) {
            readingLine(cueY: cueY, insets: insets, height: fullHeight(geo: geo, insets: insets))
                .scaleEffect(x: 1, y: state.mirror ? -1 : 1)
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
                if isLandscape {
                    statusBar(insets: insets)
                    Spacer(minLength: 0)
                    banners
                } else {
                    // Everything reachable lives on one edge, in one bar:
                    // status, timing and the take controls used to be two
                    // abutting panels with two hairlines, and before that
                    // they were split between the top and bottom of the
                    // screen entirely. One panel is one place to look and
                    // one place to reach — and it leaves no vacated strip
                    // for the script to show through when the take controls
                    // dim. Landscape keeps its rail; it has no vertical
                    // space to spend on a bar this tall.
                    Spacer(minLength: 0)
                    banners
                    unifiedBar(insets: insets)
                }
            }

            recordingTally(insets: insets)

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

    /// State, timing, and the two controls that aren't part of running a
    /// take. Everything is one type size and one weight so nothing shouts.
    /// Docked at the true top in landscape (needs the Dynamic Island
    /// clearance there); in portrait it sits directly above the take
    /// controls instead, so it's no longer touching a screen edge itself.
    private func statusBar(insets: EdgeInsets) -> some View {
        VStack(spacing: 6) {
            statusRow(showsUtilities: true)

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
                // Marks the boundary against the script below it.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
                .allowsHitTesting(false)
        }
    }

    /// Portrait's whole chrome: status, timing and the take controls in a
    /// single material panel with a single hairline, rather than two panels
    /// stacked against each other. The take controls dim during a take (see
    /// `FadingControls`) but never leave, so the panel's height — and the
    /// amount of script above it — does not change mid-take.
    private func unifiedBar(insets: EdgeInsets) -> some View {
        VStack(spacing: 8) {
            statusRow(showsUtilities: false)

            if state.showTiming { timingRow }

            // Every button on one row: running the take on the left, the
            // controls that aren't part of it on the right. They used to be
            // split across two rows — the take controls here and camera,
            // settings and exit up in the status line — which meant the
            // buttons were in two places even after the panels were merged.
            //
            // Aligned on the circles rather than the row, since the take
            // buttons carry a caption underneath and the glass ones don't;
            // centring the row would float the small buttons high.
            HStack(alignment: .top, spacing: 0) {
                controlButtons(compact: true)
                Spacer(minLength: 8)
                utilityButtons
                    .padding(.top, (Self.takeButtonSize - Self.glassButtonSize) / 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .modifier(FadingControls(visible: chromeVisible))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, insets.bottom > 0 ? insets.bottom : 14)
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
                .allowsHitTesting(false)
        }
    }

    /// State and the two controls that aren't part of running a take.
    /// Everything is one type size and one weight so nothing shouts.
    private func statusRow(showsUtilities: Bool) -> some View {
        HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(state.isListening ? Self.accent : Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(ChromeType.body(13))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 8)

                // Landscape only. Its status bar already runs along the top
                // edge, so the badge is where it belongs; portrait floats it
                // at the top-left instead — see `recordingTally`.
                if isLandscape, camera.isRecording { recordingBadge }

                if state.cameraEnabled, let mode = camera.selectedMode, let tier = camera.selectedTier {
                    qualityControl(mode: mode, tier: tier)
                }

                if showsUtilities { utilityButtons }
        }
    }

    /// Camera, settings and exit: the controls that aren't part of running a
    /// take. In landscape they ride in the status bar at the top; in portrait
    /// they sit in the one control row with everything else.
    @ViewBuilder
    private var utilityButtons: some View {
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
            .font(ChromeType.readout(12))
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

    /// Recording, at the top-left of the frame.
    ///
    /// Portrait only: it used to ride in the bottom bar with everything else,
    /// but whether the camera is rolling is the one thing you want to catch
    /// while looking at the lens rather than the screen, and the bottom bar is
    /// where your hands are, not where your eye is. Landscape keeps it in the
    /// status bar, which already runs along the top edge.
    ///
    /// Deliberately outside `FadingControls`: this never dims and never hides.
    /// It is also outside the mirrored layer, so it stays upright on a rig.
    @ViewBuilder
    private func recordingTally(insets: EdgeInsets) -> some View {
        if !isLandscape, camera.isRecording || armedForRecording {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if camera.isRecording { recordingBadge } else { armedBadge }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, insets.top + 10)
            .padding(.leading, max(insets.leading, 16))
            .allowsHitTesting(false)
        }
    }

    /// A recording take is queued behind the pre-roll but has not started.
    private var armedForRecording: Bool {
        countdownRemaining != nil && pendingRecordOnListen
    }

    /// The tally before it is live: a hollow ring, not a filled dot. Broadcast
    /// convention, and it answers the question the pre-roll otherwise leaves
    /// open — whether this take is being recorded or only prompted.
    private var armedBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(Color.red, lineWidth: 1)
                .frame(width: 7, height: 7)
            Text("Armed")
                .font(ChromeType.label(10))
                .tracking(ChromeType.labelTracking(10))
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.38))
        }
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(Color.red.opacity(0.35), lineWidth: 1))
    }

    private var recordingBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text(timeString(camera.recordingSeconds))
                .font(ChromeType.readout(12))
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
        .font(ChromeType.readout(12, weight: .semibold))
        .foregroundStyle(camera.isRecording ? .white.opacity(0.35) : .white.opacity(0.9))
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityLabel("Video quality \(mode.label)")
    }

    /// Transient messages, above whichever chrome is nearest to hand. A
    /// failure and a confirmation can both be pending — a take that saved
    /// while a recognition error was still on screen, say — so neither
    /// displaces the other.
    @ViewBuilder
    private var banners: some View {
        if let msg = errorMessage {
            banner(msg, tint: Color.red.opacity(0.75), icon: "exclamationmark.triangle.fill")
                .padding(.bottom, 12)
        }
        if let msg = noticeMessage {
            banner(msg, tint: Color.black.opacity(0.6), icon: "checkmark.circle.fill")
                .padding(.bottom, 12)
        }
    }

    private func banner(_ msg: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(msg)
        }
        .font(ChromeType.body(13))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 18)
        .transition(.opacity)
    }

    // MARK: - Take controls

    /// The same three controls in both orientations, in the same order, at
    /// the same weight — only the axis changes.
    @ViewBuilder
    private func controlButtons(compact: Bool = false) -> some View {
        Group {
        takeButton(icon: "arrow.counterclockwise", label: "Restart", compact: compact) {
            state.activeIndex = 0
            cursorJumped = true
            state.resyncMatcher()
            // A restart is a fresh take, so the timing starts over too.
            clock.reset()
            if state.isListening { clock.start(at: Date()) }
            displayNow = Date()
        }
        takeButton(
            icon: countdownRemaining != nil ? "xmark" : (state.isListening ? "pause.fill" : "play.fill"),
            label: countdownRemaining != nil ? "Cancel" : (state.isListening ? "Pause" : "Listen"),
            primary: true,
            compact: compact
        ) {
            if countdownRemaining != nil {
                countdownDeadline = nil
                pendingRecordOnListen = false
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
                recording: camera.isRecording,
                compact: compact
            ) {
                if camera.isRecording {
                    camera.stopRecording()
                    pauseTake()
                } else if countdownRemaining != nil {
                    countdownDeadline = nil
                    pendingRecordOnListen = false
                } else {
                    beginRecordingTake()
                }
            }
        }
        }
    }

    /// The landscape form: the same controls stacked against the edge they
    /// occupied in portrait, costing horizontal space instead of the vertical
    /// space landscape has none of.
    private func controlRail(insets: EdgeInsets) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            controlButtons()
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
        /// Sized to its content rather than spreading, so it can share a row
        /// with the utility buttons instead of pushing them off the edge.
        compact: Bool = false,
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
                .frame(
                    width: isLandscape ? Self.railButtonSize : Self.takeButtonSize,
                    height: isLandscape ? Self.railButtonSize : Self.takeButtonSize
                )

                if !isLandscape {
                    Text(label)
                        .font(ChromeType.label(10))
                        .tracking(ChromeType.labelTracking(10))
                        .textCase(.uppercase)
                        .foregroundStyle(on ? Self.accent : .white.opacity(0.65))
                }
            }
            .frame(maxWidth: compact ? Self.takeButtonSlot : .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A one-time hint that the prompter takes spoken instructions. Sits
    /// next to the status bar rather than over the script, and fades on its
    /// own. In landscape that's under the top bar as always; in portrait
    /// the status bar now lives at the bottom with the take controls, so
    /// the hint follows it there instead of floating alone near an empty top.
    private func voiceCommandTip(insets: EdgeInsets) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
            Text("Say **\"scroll up\"** to go back a line")
        }
        .font(ChromeType.body(13))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
        .padding(isLandscape ? .top : .bottom, isLandscape ? chromeTopInset(insets: insets) + 8 : 96 + insets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLandscape ? .top : .bottom)
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

            // Framing marks, to the frame edges. Not decoration: the centre
            // of frame is what you line yourself up against, and a pre-roll
            // is when you do it.
            crosshair

            VStack(spacing: 8) {
                ZStack {
                    leaderRings
                    Text("\(remaining)")
                        .font(ChromeType.leader(132))
                        .foregroundStyle(Self.accent)
                        .shadow(color: .black.opacity(0.9), radius: 20)
                        .shadow(color: Self.accent.opacity(0.25), radius: 30)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 200, height: 200)

                // What the pre-roll is *for*. It exists so you can settle and
                // find the lens, and nothing said so.
                Text("Find the lens")
                    .padding(.top, 6)
                    .font(ChromeType.label(11))
                    .tracking(ChromeType.labelTracking(11))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.55))
                    .shadow(color: .black.opacity(0.8), radius: 6)

                Text("Tap anywhere to cancel")
                    .font(ChromeType.label(10))
                    .tracking(ChromeType.labelTracking(10))
                    .textCase(.uppercase)
                    // The direction sets this at 0.32, which reads on a blank
                    // artboard and vanishes over a real script. Lifted until
                    // it survives the thing it actually sits on.
                    .foregroundStyle(.white.opacity(0.5))
                    .shadow(color: .black.opacity(0.9), radius: 8)
                    .padding(.top, 2)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { countdownDeadline = nil }
        .accessibilityLabel("Starting in \(remaining) seconds")
        .transition(.opacity)
        .zIndex(10)
    }

    /// The Academy leader: two rings and a hand sweeping once a second.
    private var leaderRings: some View {
        ZStack {
            Circle()
                .stroke(Self.accent.opacity(0.28), lineWidth: 1)
                .frame(width: 192, height: 192)
            Circle()
                .stroke(Self.accent.opacity(0.16), lineWidth: 1)
                .frame(width: 160, height: 160)

            LeaderHand()
                .fill(Self.accent.opacity(0.10))
                .frame(width: 192, height: 192)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Self.accent)
                        .frame(width: 1.5, height: 96)
                }
                .rotationEffect(.degrees(leaderSweeping ? 360 : 0))
                .animation(
                    reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                    value: leaderSweeping
                )

            Circle().fill(Self.accent).frame(width: 6, height: 6)
        }
        .onAppear { leaderSweeping = true }
        .onDisappear { leaderSweeping = false }
    }

    /// Faint amber hairlines running to the frame edges, fading out before
    /// they reach them so they read as marks rather than as a grid.
    private var crosshair: some View {
        let fade = Gradient(stops: [
            .init(color: Self.accent.opacity(0), location: 0),
            .init(color: Self.accent.opacity(0.30), location: 0.18),
            .init(color: Self.accent.opacity(0.30), location: 0.82),
            .init(color: Self.accent.opacity(0), location: 1)
        ])
        return ZStack {
            LinearGradient(gradient: fade, startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            LinearGradient(gradient: fade, startPoint: .top, endPoint: .bottom)
                .frame(width: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Per-frame work

    /// One frame of the prompter's own animation, called by `PrompterTicker`.
    ///
    /// The rule throughout is that a frame which changes nothing must write
    /// nothing: every `@State` write here re-evaluates the whole prompter,
    /// which rebuilds every word view in the script. Reading state and
    /// deciding not to write it is nearly free; writing it 60 times a second
    /// for movement too small to see is what made a parked prompter as
    /// expensive as a scrolling one.
    /// How far the script travels per spoken word, measured from the current
    /// layout rather than assumed, so it follows the reader's font size and
    /// the way their text happens to wrap.
    private var pointsPerWord: CGFloat {
        let ahead = min(state.activeIndex + Self.pursuitLookahead, max(0, state.words.count - 1))
        guard ahead > state.activeIndex,
              let here = wordFrames[state.activeIndex],
              let later = wordFrames[ahead] else { return 0 }
        return (later.midY - here.midY) / CGFloat(ahead - state.activeIndex)
    }

    private func tick(now: Date) {
        let cueY = tickCueY

        // Exponential smoothing towards the target, but only while the step
        // is big enough to see. Once it isn't, land exactly on the target one
        // final time and then leave `offset` alone — that last write is what
        // lets the view stop being invalidated.
        // Clamped: a tick delayed by a stall, a backgrounding or a slow
        // frame must not be paid back as one enormous jump.
        let dt = min(max(now.timeIntervalSince(lastTickTime ?? now), 0), 0.1)
        lastTickTime = now

        let gap = targetOffset - offset
        if abs(gap) > Self.settleThreshold {
            offset += gap * (1 - CGFloat(exp(-dt / Double(Self.smoothingTau))))
        } else if offset != targetOffset {
            offset = targetOffset
        }

        // Follow the reading cursor, at the speed the words are being spoken.
        //
        // Recognition does not arrive a word at a time: SFSpeechRecognizer
        // reports partial results every few hundred milliseconds, each of
        // which can match several words at once. Setting the target straight
        // to the newly recognised word therefore asked the script to cover
        // two seconds of speech in a third of a second, and then hold still
        // until the next result — the stall-then-jump. Moving the target at
        // the speaking pace instead turns the same bursts into continuous
        // motion, without the display ever running ahead of what was
        // actually heard.
        //
        // It stops dead when it arrives, so silence is still stillness: with
        // no new words there is no new target, and nothing moves.
        //
        // This also does the old self-heal's job — a rotation or a font
        // change leaves a stale offset that no discrete event corrects, and
        // the pursuit walks it back onto the reading line. Safe as a
        // continuous check because these frames are in the flow's own space
        // and don't move when `offset` does.
        if !isDraggingScript, !isDraggingLine, let frame = wordFrames[state.activeIndex] {
            let want = cueY - frame.midY
            #if DEBUG
            pursuitDiagnostics.record(
                now: now,
                gap: want - targetOffset,
                pointsPerWord: pointsPerWord,
                effectiveWPM: effectiveWPM,
                targetWPM: pursuitWPM,
                response: Self.pursuitResponse,
                maxCatchUp: Self.pursuitMaxCatchUp
            )
            #endif
            let next = ScrollPursuit.step(
                target: targetOffset,
                toward: want,
                speed: ScrollPursuit.speed(
                    gap: want - targetOffset,
                    pointsPerWord: pointsPerWord,
                    wordsPerMinute: pursuitWPM,
                    response: Self.pursuitResponse,
                    maxCatchUp: Self.pursuitMaxCatchUp,
                    minimum: Self.pursuitMinSpeed
                ),
                dt: dt,
                snapDistance: Self.pursuitSnapDistance,
                jumped: cursorJumped
            )
            cursorJumped = false
            if next != targetOffset {
                targetOffset = next
                dragStartOffset = next
            }
        }

        if let deadline = countdownDeadline, now >= deadline {
            startListeningNow()
        }
        if let hideAt = chromeHideAt, now >= hideAt {
            chromeHideAt = nil
            if takeIsLive && !showSettings { chromeVisible = false }
        }
        // Only publish a new date when the displayed second changes, rather
        // than every frame for a readout that can't show it.
        if Int(now.timeIntervalSince1970) != Int(displayNow.timeIntervalSince1970) {
            displayNow = now
            // The pre-roll exists so you can settle and find the lens, which
            // is exactly when you are not looking at the number counting
            // down. Tapped out instead. `startListeningNow` above has already
            // cleared the deadline by the final tick, so this doesn't fire on
            // the beat the take actually starts — that gets its own.
            if countdownDeadline != nil { Haptics.countdownTick() }
        }

        // Full refresh rate only while something is actually moving; the rest
        // of a take runs at the idle rate, which is most of a take.
        ticker.setActive(
            abs(targetOffset - offset) > Self.settleThreshold
            || isDraggingScript
            || isDraggingLine
            || countdownDeadline != nil
        )
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

    /// The status line doubles as the only instruction on screen, so it has to
    /// describe the way *out* of the state you are in — not the way into the
    /// one you have left.
    ///
    /// It keyed off `isListening` alone, which meant a take whose recognition
    /// had dropped out (a fatal speech error, iOS taking the microphone) went
    /// on recording while the status invited you to "tap play to begin"
    /// something that was demonstrably already running. `takeIsLive` covers
    /// recording as well, so a live take always reads as live.
    private var statusText: String {
        if countdownRemaining != nil { return "Get ready…" }
        return takeIsLive ? "Tap pause to stop listening" : "Tap play to begin"
    }

    /// Starts a take, after the pre-roll if one is configured.
    private func beginTake() {
        if state.countdownSeconds > 0 {
            displayNow = Date()
            countdownDeadline = Date().addingTimeInterval(Double(state.countdownSeconds))
        } else {
            startListeningNow()
        }
    }

    /// Record used to need its own separate tap at Listen — recording without
    /// the script tracking along was never actually useful, so Record now
    /// starts the take too. Already listening (rehearsing before deciding to
    /// record) just adds the camera in, without restarting the take.
    private func beginRecordingTake() {
        if state.isListening {
            camera.startRecording()
            Haptics.recordingStarted()
        } else {
            pendingRecordOnListen = true
            beginTake()
        }
    }

    private func startListeningNow() {
        countdownDeadline = nil
        if tips.shouldShowVoiceCommandTip(commandsEnabled: state.voiceCommandsEnabled) {
            showVoiceTip = true
            tips.markVoiceCommandTipSeen()
            // Cancellable, so leaving the prompter inside the six seconds
            // doesn't leave a timer holding the view alive to write state
            // into it afterwards.
            voiceTipWorkItem?.cancel()
            let item = DispatchWorkItem { showVoiceTip = false }
            voiceTipWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
        }
        state.isListening = true
        clock.start(at: Date())
        speech.begin(localeIdentifier: state.recognitionLocale)
        scheduleChromeHide()
        if pendingRecordOnListen {
            pendingRecordOnListen = false
            camera.startRecording()
            Haptics.recordingStarted()
        } else {
            Haptics.takeStarted()
        }
    }

    private func pauseTake() {
        commandDetector.reset()
        countdownDeadline = nil
        pendingRecordOnListen = false
        if state.isListening { Haptics.takeStopped() }
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

    /// The pace the **pursuit ceiling** is measured against.
    ///
    /// Deliberately the configured target, not `effectiveWPM`. `effectiveWPM`
    /// is a whole-take average (`wordsRead / elapsed`), and `wordsRead` is the
    /// cursor — so every pause taken without hitting Pause drags it down, and
    /// ad-libbing tanks it outright: the cursor stalls while the clock runs.
    /// Feeding that to the ceiling made catch-up *slower the longer a take
    /// ran*, and slowest exactly when the matcher had the most ground to make
    /// up. The estimates and the readout still use the measured average —
    /// that is what it is for. The ceiling needs a stable number.
    private var pursuitWPM: Double { state.targetWPM }

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
        // Whether the script was at rest *before* this new target arrived.
        let wasSettled = abs(targetOffset - offset) <= Self.settleThreshold
        targetOffset = newTarget
        dragStartOffset = newTarget
        // Wake the ticker here rather than letting it discover the new target
        // on its own next frame. Parked on the reading line it idles at
        // `PrompterTicker.idleFrameRate`, so that discovery is up to 100ms
        // away — a delay on *every* word, which is what made following a
        // speaker feel laggy even though the cursor itself had already moved.
        ticker.setActive(true)
        // The first layout has nothing to animate from: snap, or the opening
        // line sits below the reading line until the cursor happens to move.
        //
        // Otherwise a re-measurement (`animated: false`) may only snap when
        // the script was already at rest. Doing it mid-scroll writes `offset`
        // out from under an animation in flight, which lands as a teleport —
        // the script stalls, then jumps. A re-measure during a scroll just
        // moves the target and lets the smoothing above absorb it.
        if offset == 0 || (!animated && wasSettled) { offset = newTarget }
    }

    private func showError(_ msg: String) {
        errorMessage = msg
        revealChrome()
        errorWorkItem?.cancel()
        let item = DispatchWorkItem { errorMessage = nil }
        errorWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }

    private func showNotice(_ msg: String) {
        noticeMessage = msg
        revealChrome()
        noticeWorkItem?.cancel()
        let item = DispatchWorkItem { noticeMessage = nil }
        noticeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    /// A small circular control for the things that aren't part of running a
    /// take: camera, settings, exit.
    @ViewBuilder
    private func glassButton(icon: String, label: String, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tinted ? Self.accent : .white.opacity(0.9))
                .frame(width: Self.glassButtonSize, height: Self.glassButtonSize)
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
/// Recedes the take controls during a take without taking them away.
///
/// They used to go to `opacity(0)` and stop hit-testing, which read as the
/// app having lost its buttons: nothing on screen suggested they still
/// existed, or that a tap would bring them back. Dimmed instead — quiet
/// enough to stop competing with the script, present enough to be found and
/// pressed without a preceding tap to reveal them.
private struct FadingControls: ViewModifier {
    let visible: Bool

    /// Low enough to read as inactive chrome rather than as a live control,
    /// high enough to stay legible against the material behind it.
    static let dimmed: Double = 0.28

    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : Self.dimmed)
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

    /// `VStack`/`.frame` only know leading/center/trailing; a justified
    /// block still reads left-to-right at the block level, since it's each
    /// wrapped row inside `FlowLayout` that does the stretching.
    private var horizontalAlignment: HorizontalAlignment {
        switch state.textAlignment {
        case .leading, .justified: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var frameAlignment: Alignment {
        switch state.textAlignment {
        case .leading, .justified: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: state.fontSize * 0.35) {
            ForEach(state.lines) { line in
                if line.isBlank {
                    // A blank line in the editor becomes real space here, so
                    // pauses and ad-lib room survive into the prompter.
                    Color.clear.frame(height: state.fontSize * 0.9)
                } else {
                    FlowLayout(spacing: 8, lineSpacing: 6, alignment: state.textAlignment, fontSize: state.fontSize) {
                        ForEach(line.words) { word in
                            wordView(word)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .onPreferenceChange(WordFramePreferenceKey.self) { wordFrames = $0 }
        // NOTE: each word is deliberately left as its own accessibility
        // element. Grouping the script into one element reads far better
        // under VoiceOver — currently it is one swipe per word — but the
        // reading-line geometry tests locate words through the accessibility
        // tree (`app.staticTexts["Welcome"]`), and those are the tests that
        // caught the line being 45pt out of register. Fixing the VoiceOver
        // experience means giving those assertions another way to find a
        // word first.
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
            // Reserve the word's width at its widest (bold) rendering. Without
            // this, a word narrowing to semibold the moment it's marked spoken
            // frees up row space, and FlowLayout can pull the next — still
            // unread — word up onto the row above, mid-take.
            .frame(width: Self.boldWidth(word.raw, fontSize: state.fontSize), alignment: .leading)
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

    /// Per-type so it survives this struct being recreated every render;
    /// bounded in practice by (unique words) × (font sizes the slider offers).
    ///
    /// Nested by size rather than keyed by an interpolated `"\(size)_\(word)"`
    /// string: this is read once per word per body evaluation, and building a
    /// throwaway String each time to look up a cache made the cache cost about
    /// as much as the measurement it was avoiding.
    private static var boldWidthCache: [CGFloat: [String: CGFloat]] = [:]

    private static func boldWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        if let cached = boldWidthCache[fontSize]?[text] { return cached }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        boldWidthCache[fontSize, default: [:]][text] = width
        return width
    }
}
