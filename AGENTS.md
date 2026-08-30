# Working on Cue

Guidance for AI agents (and humans) making changes here. Read this before touching the code.

On Cue is a SwiftUI iPhone teleprompter (the repo and product name are `Cue`; the App Store listing is "On Cue Teleprompter" and the home-screen name is "On Cue"): the script scrolls as you speak, with front-camera recording. iOS 16.0 deployment target.

## Build and test

```sh
xcodegen generate                      # after ANY change to project.yml
xcodebuild -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 14' test
```

Run the full suite before claiming a change works. `build` alone misses layout regressions the UI tests catch.

## The project file is generated

`project.yml` is the source of truth. `Cue.xcodeproj` is **gitignored and regenerated** — never edit it, and never commit it. Targets, build settings, Info.plist keys and permission strings all live in `project.yml`.

New source files under `Cue/`, `CueTests/` or `CueUITests/` are picked up automatically by directory; re-run `xcodegen generate` so Xcode sees them.

**Signing set in Xcode's UI does not survive.** Regeneration rebuilds the project file, so a team picked in Signing & Capabilities is wiped and the "requires a development team" error returns. `DEVELOPMENT_TEAM` comes from `Signing.xcconfig`, which is gitignored (copy `Signing.xcconfig.example`) so the team ID stays out of the public repo. Never add `DEVELOPMENT_TEAM` back to `project.yml`'s target settings — even an empty value there overrides the xcconfig and resets Team to None, which is exactly the bug this replaced.

**Xcode Cloud is the only path to TestFlight.** Push to `main`: the suite runs and must pass, the archive is delivered to internal testers automatically (`buildDistributionAudience: INTERNAL_ONLY`, and the internal group has access to all builds). `Tools/release.sh` archives and exports locally for checking signing, and deliberately does **not** upload.

That is a numbering decision as much as a workflow one. Two upload paths meant two counters issuing numbers for one sequence — `project.yml` locally (1, 2, 3) and `CI_BUILD_NUMBER` in the cloud (18) — which is how a build "3" landed after a build "18". App Store Connect requires the number to increase for a submission, so that could have blocked shipping. With one path there is one counter. The `CFBundleVersion` in `project.yml` is only a local default and is not what ships.

Historic note: it used to be necessary to bump `CFBundleVersion` in `project.yml` after every accepted upload, not before the next one — App Store Connect permanently rejects a build number it has already accepted, and bumping after means the repo always holds an unused number.

`Tools/release.sh [--upload]` runs archive → export → validate → upload, reading the team from `Signing.xcconfig` and the API key id/issuer from `ASC_KEY_ID`/`ASC_ISSUER_ID` (with `AuthKey_<KEYID>.p8` in `~/.appstoreconnect/private_keys/`). **`uploadSymbols` must stay `false`**: with it on, Xcode 26's packaging step fails with the useless `error: exportArchive Copy failed` while copying the dSYM. That message says nothing about symbols — it also appears when there is no local Apple Distribution identity, so check `security find-identity -v -p codesigning` before assuming it's the symbols.

## The share extension

`CueShare` is a separate process and cannot touch the app's storage, so the two meet in the App Group `group.app.cueprompter`: the extension writes a script into the container, the app collects it on `scenePhase == .active` and offers it rather than applying it — silently replacing the editor's contents would eventually destroy someone's work.

`SharedScriptInbox` is the contract, and its file is compiled into **both** targets (as is `ScriptImporter`); they must stay in step or a share lands somewhere the app never looks. Its directory is injectable so it can be tested without an App Group, which only exists in a signed, entitled build. `SharedScriptInbox()` returns nil rather than crashing when the container is unavailable.

Both targets carry the App Group entitlement (`Cue/Cue.entitlements`, `CueShare/CueShare.entitlements`). An app extension with an explicit `INFOPLIST_FILE` needs the standard bundle keys spelled out — without `CFBundleIdentifier` = `$(PRODUCT_BUNDLE_IDENTIFIER)` the build fails with the misleading *"Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier"*, even when the identifiers are correct.

## Xcode Cloud

`Cue.xcodeproj` is not in the repository, so Xcode Cloud fails with *"Project Cue.xcodeproj does not exist at the root of the repository"* unless it generates one first. `ci_scripts/ci_post_clone.sh` installs XcodeGen and runs `xcodegen generate`; Xcode Cloud executes it after cloning and before it looks for the project. The scripts must stay at `ci_scripts/` in the repo root and stay executable (`chmod +x`) — Xcode Cloud silently ignores them otherwise.

It also writes a stub `Signing.xcconfig` when absent: the generated project references it as a base configuration, and xcodebuild fails with *"Unable to open base configuration reference file"* if it is missing. `disabledValidations: [missingConfigFiles]` only silences XcodeGen's own check, not xcodebuild's. The same error hits a fresh local clone that skips the `cp Signing.xcconfig.example` step.

`ci_scripts/ci_pre_xcodebuild.sh` stamps **every** bundle's `CFBundleVersion`, app and extension alike: an embedded extension whose version differs from its parent is rejected at submission. It runs before **every** action, tests included, so it must never exit non-zero — an early version failed the Test action outright while the Archive action running the identical script succeeded. It now stamps only for archives (`CI_XCODEBUILD_ACTION`), tolerates a missing plist or repository path, and always exits 0. It stamps `CFBundleVersion` from `CI_BUILD_NUMBER`, because the static value in `project.yml` would collide on the second upload.

If Apple ever refuses to resolve the workflow at all without a project in the repo, the fallback is to commit `Cue.xcodeproj` — but that gives up the generated-project setup, so try the post-clone script first.

## What you cannot verify here

The simulator has **no microphone and no camera**. Speech recognition and camera capture cannot be exercised locally — do not claim they work based on a green build. Say plainly that they need testing on a physical device, and ask.

Hardware-coupled types (`SpeechTracker`, `CameraController`) are deliberately not unit tested for this reason. Don't add tests that pretend to cover them; put logic worth testing into pure types instead (as `TranscriptDeltaTracker` and `ScriptImporter` do).

## Design principles

The prompter behaves like a first-party capture app: the content is the script and the speaker's face, and the chrome defers to it. Translucent materials rather than opaque slabs; one accent colour, used only where it carries meaning (current word, primary action, live pace); controls that recede during a take and brighten on a tap, with the status readout and the recording badge the things that never hide.

Settings are placed by whether you can judge them without looking at the script. Anything whose effect is only visible on the script — text size, reading line, alignment, mirroring — belongs on the prompter, not the setup screen, where a value like "32" means nothing. The setup screen carries only pre-start decisions, and the pace control lives inside the estimate sentence it governs, as a named speed rather than a bare wpm number.

## Verifying visual changes

Layout and legibility changes need real evidence, because code that looks right often doesn't render. The loop:

**Assert the effect, not the rule you intended.** A control's test must show that using it changes what the reader sees, in **both orientations** — not that the formula behaves as designed. The side-margin setting shipped as a floor over the safe-area inset with unit tests passing, while in landscape (~47pt inset a side) most of its range did nothing: the tests encoded the intent, so they could not catch a wrong intent. And exercise the *weak* end of a range — a first version of `testSideMarginMovesTheScriptInBothOrientations` dragged the slider to 90% and passed against the broken build, because only the bottom of the range was dead. When adding such a test, confirm it fails against the old behaviour before trusting it.

**Measurable geometry belongs in assertions, not in this loop.** Screenshots are for judging taste. Anything with a number — is the reading line on the word, is a control inside the window — goes into a UI test, because eyeballing exported screenshots passed both of those defects repeatedly. See `testReadingLineSitsOnTheWordBeingRead` and `testAllControlsFitInTheLandscapeRail`.

**Run verification on a throwaway simulator.** Parallel runs against the shared `iPhone 14` device kill each other and leave DerivedData in states that fail with an unsigned `Cue.debug.dylib` — failures that have nothing to do with the code:

```sh
DEVICE=$(xcrun simctl create CueVerify com.apple.CoreSimulator.SimDeviceType.iPhone-14 com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcodebuild -project Cue.xcodeproj -scheme Cue -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath /tmp/dd-verify test
xcrun simctl delete $DEVICE
```

`timeout` does not exist on macOS — a command that pipes through it silently never runs xcodebuild at all, which reads as an inconclusive result rather than an error.

1. `xcodebuild ... -only-testing:CueUITests/CaptureScreens test` — attaches a screenshot.
2. `xcrun xcresulttool export attachments --path <the .xcresult> --output-path <dir>`
3. Compare before/after with pixel statistics, not by eye:

```python
from PIL import Image, ImageStat
im = Image.open(path).convert('L'); w, h = im.size
print(ImageStat.Stat(im.crop((0, int(h*0.84), w, int(h*0.96)))).mean[0])
```

This is how a scrim that appeared correct in code but rendered at ~30% of intended opacity was caught. Eyeballing two downscaled screenshots missed it.

## Invariants that are easy to break

**`FlowLayout` caches its measurements, and the cache key includes `fontSize`.** The `Layout` protocol's cache was declared `inout ()` and unused, so the script was measured three times per pass — in `sizeThatFits`, again in `placeSubviews`, and once more per row inside `place` — for every word, every pass. Word widths are pinned at their bold rendering (`ScrollFlow.boldWidth`) so they don't change when a word changes state; the only thing that invalidates them is the reader changing text size, hence `fontSize` on the layout. If you make a word's width depend on anything else, that thing has to invalidate the cache too.

**Voice commands step *drawn* rows, not typed lines.** `lines` groups words as typed, so a paragraph is one line — stepping by it jumped a whole paragraph. `VisualLines` works from the measured word frames instead, which is the only thing that knows where the rows fall on screen; it falls back to typed lines only when nothing has been measured.

**The matcher's search widens when the reader goes off-script.** Ad-libbing is the normal case for this product, not an edge case — the README promises "skip ahead, paraphrase, double back", and a speaker working from notes deviates constantly. A fixed look-ahead cannot honour that: skipping a sentence, paraphrasing a clause and being misheard all look identical from `ingest`'s side (words arrive, none are in the window), and the cursor then stops and waits forever for words that will never be said while the reader keeps talking. `unmatchedWords` counts heard words that found nothing since the cursor last moved, and `searchReach` widens from `window` (12) to `wideWindow` (60) and finally to the whole script as that count passes `missesBeforeWidening` and `missesBeforeGlobal`. Any match resets it, as does `resyncMatcher()` — called wherever the cursor is placed deliberately (restart, a drag, a voice command), since the reader has just said where they are.

Two guards keep the widening from becoming a runaway, and both matter more the wider the search gets: a jump beyond the ordinary window needs a word of at least `minimumAnchorLength` characters, and filler may still never match beyond `fillerReach`. Anchoring a fifty-word jump on "so" or "cat" is exactly how a prompter loses its reader.

Note what this replaced. Idle drift — a setting that crept the script upward during silence — was the previous, crude answer to the same problem, and the help text said as much ("leave it off unless recognition keeps losing you"). It was deleted because it moved the script when nobody was speaking, which is never right. Do not reintroduce anything like it: the requirement is that the script is *completely still* unless words are being matched, and recovery comes from searching harder, not from moving on a timer.

**Command matching is deliberately looser than script matching.** A short phrase has no surrounding context to disambiguate it, so recognition of "scroll up" is *harder* than of the script around it — markedly so in an accent, which is how this was found. `VoiceCommandDetector.matches` allows prefixes and an edit distance of two, but only for words of five letters or more: "up" must never fuzzy-match "on". The request also carries `contextualStrings` to bias recognition toward the command phrases.

**Stopping a recording always ends the take, and a live take always reads as live.** These are one idea. The status line is the only instruction on screen, so it names the way *out* of the current state — and it keyed off `isListening` alone, which meant a take whose recognition had dropped out (a fatal speech error, iOS taking the mic for a call) kept recording while the status invited you to "tap play to begin" something already running. It now keys off `takeIsLive`. In the same spirit, `onChange(of: camera.isRecording)` ends the take whenever a recording stops: the Stop button and leaving the app already paused explicitly, but a recording can also stop on its own — a capture error, a full disk — which used to leave the microphone open and the script still following a take the reader thought had ended.

**The status readout does not auto-hide, and the buttons dim rather than disappear.** Where you are, how long is left and whether the camera is rolling are needed *while* reading; hiding them meant touching the screen to find out, which defeats a hands-free prompter. The buttons used to go to `opacity(0)` and stop hit-testing, which read as the app having lost them — nothing on screen said they still existed or that a tap would bring them back, and the vacated strip let the script show through the bar. `FadingControls` now dims to `FadingControls.dimmed` and never disables hit-testing, so they can be pressed without a summoning tap first. Rotation also calls `revealChrome()`: the controls change edge when you rotate, and arriving in a new orientation with no buttons visible reads as a malfunction.

**Never feed the cumulative transcript to the matcher.** `SFSpeechRecognitionResult.bestTranscription.formattedString` repeats everything said so far on every partial result. `TranscriptDeltaTracker` reduces it to newly appended words. Passing the whole transcript makes the cursor lurch forward, because each already-consumed word gets another chance to match ahead.

**Filler words must not match far ahead.** `TeleprompterState.filler` words only match within `fillerReach` of the cursor. Common words recur throughout any script, and letting them match anywhere in the look-ahead window is the other cause of jumping. Distinctive words keep full window reach — that is how the matcher recovers from genuinely missed words.

**`words` and `lines` must stay consistent.** `words` is the flat reading-order list the matcher walks; `lines` groups those same words for layout with blank lines preserved as ad-lib space. Word ids are sequential across the whole script and must agree between the two. The flat list's contract is depended on by the original matcher tests.

**Normalize line endings before splitting.** Splitting CRLF text on a newline *character set* invents a blank line between every line. `buildWords` normalizes `\r\n` and `\r` first.

**Never position layout from a measurement that the position influences.** The reading line's `cueY` was once derived from a measured chrome height. Measurement drove state, state moved layout, layout re-published the measurement — at full precision the sub-pixel difference each pass kept that cycle running forever, pinning the CPU at 100% so the prompter never became interactive and every UI test timed out. It also meant the script was scrolled against one value while the line was drawn at another, leaving them 45pt apart in landscape. `cueY` is now a pure function of geometry (fraction of the full height, floored higher in landscape), and the rail's top inset is a stated constant. Where a measurement genuinely must drive state: quantize the key, skip writes below ~0.5pt, and never write synchronously into a value the same layout pass reads.

**The scroll target is *paced* toward the cursor, never set to it.** This is the single most important thing in the prompter and the easiest to undo by accident, because assigning the target directly looks simpler and is wrong. Recognition does not arrive a word at a time: `SFSpeechRecognizer` reports partial results every few hundred milliseconds and each can match several words at once, so the cursor advances in bursts. Setting the target straight to the newly recognised word asked the script to cover two seconds of speech in a third of a second and then hold still until the next result — a stall followed by a jump, which is what a reader notices first. `ScrollPursuit.step` moves the target at the speed the words are actually being spoken (`pointsPerWord × wordsPerSecond × pursuitCatchUp`), turning the same bursts into continuous motion.

Two properties are load-bearing and both are covered by `ScrollPursuitTests`:

- **It only ever moves *toward* the cursor, and stops on arrival.** It never predicts and never runs ahead. No new words means no new target means the script does not move at all — which is the whole of the "nothing moves while you are silent" requirement. Do not add lead or extrapolation here without deciding that requirement has changed.
- **Deliberate cursor moves are not paced.** Restart, a drag, a voice command and the UI-test cursor hook set `cursorJumped`; a gap wider than `pursuitSnapDistance` is treated the same way, since nothing spoken moves the script that far. Walking the length of a script at speaking pace would take as long as reading it.

This also does the old self-heal's job — rotation produces transient layouts whose measurements leave a stale offset that no discrete event corrects — and is safe as a continuous check *only* because word frames are measured in the flow's own coordinate space and therefore do not move when `offset` does. Measuring them in screen space would make it a feedback loop. Guarded by `!isDraggingScript` and `!isDraggingLine` so it never fights a finger.

**The relayout handler must not fire on cursor moves.** `onChange(of: wordFrames[state.activeIndex]…)` exists to catch a *relayout* — a rotation rewraps every line while the word count stays identical — but the key also changes when the cursor moves, because it then reads a different word's frame. Left ungated it re-targeted immediately and defeated the pacing above entirely. It compares against `lastFrameKeyIndex` and acts only when the same word's frame moved underneath it.

**The script's frame is pinned to the *full* screen, top-aligned.** Pinned, because `ScrollFlow` is 2–3× taller than the screen and an unpinned ZStack sizes to it, pushing the controls off screen — removing the pin made Listen untappable and clipped the rail. Full-screen (`geo.size` + insets) rather than the inset `geo` height, because the container ignores the safe area and a smaller child gets centred, dropping the script ~(top+bottom)/2 below the origin the chrome uses.

**Layout must come from live geometry, not `UIScreen`.** `UIScreen.main.bounds` reports the wrong height in landscape. `ScrollFlow` takes its insets from the `GeometryReader`.

**Mirroring is explicit, in one place.** The SwiftUI `.scaleEffect(x: -1)` does it. `AVCaptureVideoPreviewLayer`'s automatic front-camera mirroring is deliberately disabled — re-enabling it double-flips the preview. Recorded files stay unmirrored so takes read naturally.

**Camera controls are capability-gated.** Every row in `PrompterControlsSheet` is conditional on what `CameraController.detectCapabilities` found on the actual device. Never show a control the connected iPhone doesn't support.

**`sessionPreset` is `.inputPriority`** so `device.activeFormat` takes effect. Changing it to a fixed preset silently breaks the quality picker.

**Quality is two toggles, not a format list.** `CaptureQualityMenu` collapses the device's formats into at most two tiers (HD / 4K), each with its available frame rates — the same choice Camera.app offers. Keep only the largest size per tier: 720p and 1080p both label as "HD" and would give the toggle two indistinguishable positions. Every offered mode resolves to the *widest-FOV* format that can serve it, for the same reason `setup` picks a wide format explicitly.

**Only 16:9 formats are video sizes.** The front camera publishes 4:3, stills-shaped formats (3088x2320, 1920x1440) next to the video ones. Grouping by height alone let 2320 outrank 2160 and put a stills format behind the "4K" toggle, where it offered a single frame rate — which is how the bug was noticed. `CameraController.isWidescreen` filters at the AVFoundation boundary and `VideoMode.recognizedHeights` (720/1080/2160) guards the pure side.

**Side margins add to the safe area; a *fixed* padding must not.** `ScriptMargins.inset(safeArea:margin:rail:)` is the one place this is decided. The distinction matters and both halves were learned the hard way: a hard-coded 26pt base padding stacked on the inset cost the script ~73pt a side in landscape, but making the reader's margin a floor over the inset instead left the control apparently dead, since ~47pt of landscape inset swallowed most of its range. So: safe area (or an 8pt minimum) plus the reader's margin plus the rail, which is occupied space rather than a margin.

**Landscape moves the controls to a side rail.** A bottom bar costs vertical space, which is exactly what landscape has none of. The rail goes on the edge that was the bottom in portrait — `landscapeLeft` means that edge is now on the left — so the controls stay under the same thumb through a rotation. The *side* comes from the window scene's `interfaceOrientation`, not `UIDevice.orientation` (which also reports face-up/face-down and would throw the rail to a random side when the phone is laid on a table). Whether it is landscape *at all* comes from the layout's own geometry, and must not come from that scene value: it was read on `UIDevice.orientationDidChangeNotification`, which fires *before* the scene has rotated, so it latched a stale value with nothing scheduled to correct it — after rotating back to portrait the view kept rendering the landscape branch and the take controls were simply not on screen. Geometry cannot tell the two landscapes apart, which is the only thing the scene is still consulted for; both are seeded on appear, since launching straight into landscape had the same bug. The rail is opaque, so the script must be inset past it (`leadingInset`/`trailingInset` on `ScrollFlow`) or words vanish mid-line. A UI test rotates the simulator and asserts the controls are hittable, on-screen, stacked vertically and against an edge.

**The bottom bar is a bar.** It spans the full width with an opaque background; backing only the buttons' intrinsic width leaves the script visible around a floating black box over a camera feed, and translucency isn't enough either — at 86% the words were still legible through it.

**The recording tally sits at the top-left, not in the bar.** Whether the camera is rolling is the one thing worth catching while you are looking at the lens rather than the screen, and the bar is where your hands are, not where your eye is. `recordingTally` is deliberately **outside `FadingControls`** (it never dims with the take controls) and **outside the mirrored layer** (it stays upright on a rig). Landscape keeps it in the status bar, which already runs along the top edge — floating it there would put two things in the same corner. During a pre-roll with a recording queued it shows an **armed** state: a hollow ring rather than a filled dot, so you know whether this take is being recorded or only prompted.

**Portrait has exactly one bar, and every button is in one row of it.** This arrived in three steps, each correcting the last: the status row and take controls first sat at opposite edges of the screen (two reach zones, bad on a mounted phone), then were docked together as two abutting panels with two hairlines, and are now a single `unifiedBar` — status, timing and one control row sharing one material and one hairline. Within that row the take controls (`controlButtons(compact:)`) sit leading and the utilities (`utilityButtons` — camera, settings, exit) trailing, aligned on the *circles* rather than the row, since the take buttons carry a caption underneath and the glass ones do not. Landscape keeps its top status bar plus side rail: it has no vertical space for a bar this tall, and the rail already puts everything on one edge.

**Both quality pills stay visible.** They're a readout as much as a control; a pill that vanishes when you switch tier (because that tier offers one frame rate) reads as a bug. A pill with nothing to offer renders dimmed and disabled instead.

**`setup()` runs once.** The camera can be toggled off and back on mid-take, and re-running it would add a second set of inputs and outputs to the session — `isConfigured` gates it, and restarts go through `start()`. Orientation notifications are begin/end nesting-counted, so `startTrackingOrientation` no-ops when already registered.

**Prompter settings is a partial sheet, and must stay one.** Every option in it is judged by looking at the script — text size, margins, dimming, the reading line — so the script has to remain visible while it is open. The detent set was `[.medium, .large]`, and `.large` meant a drag anywhere in the `Form` expanded the sheet to full screen and covered the very thing being adjusted. A *single* `.fraction(PrompterControlsSheet.sheetHeight)` detent has nothing to expand to, so that same drag scrolls the Form instead. `presentationBackgroundInteraction` keeps the prompter behind undimmed and live, guarded by `#available(iOS 16.4, *)` since the deployment target is 16.0.

In **landscape** it goes back to `.large`, keyed off `verticalSizeClass`. 45% of a landscape iPhone is about 175pt — roughly one row of the Form — iOS does not offer a partial detent in compact height anyway, and the script there sits *behind* the sheet rather than above it, so there is nothing to preserve by cramping it. Note the knock-on for tests: a shorter sheet shows fewer rows, so `PrompterSmokeTests.revealSlider` needs more scroll-drags to reach a row than it did — its budget went 10 → 24 after the 45% detent made it fail one full run in four.

**The sample script is a real speech, and the UI tests are anchored to its words.** It is Mark Twain's "Advice to Youth" (1882) — public domain, written to be *said* rather than read, which is the thing this app is actually for. It replaced a script that explained the app to itself: fine as documentation, but it demonstrated nothing about reading aloud and made every screenshot look like a tutorial. Onboarding lives in the "?" guide and the first-run voice-command tip instead.

If you change it, `PrompterSmokeTests` breaks: the reading-line geometry tests locate the opening word (`app.staticTexts["Being"]`) and three words that must appear *exactly once* (`inquired`, `didactic,`, `beseechingly,`) — a repeated word makes the query ambiguous rather than the layout wrong. Keep the first word unique, and re-point those tests.

**Recording is a control on the setup screen, not a bulletin.** It used to be a line reading "Camera off — the script will scroll without recording". `cameraEnabled` **persists**, and the only toggle lived inside the prompter, so anyone who turned the camera off during a take came back to a screen that reported the state and offered no way to change it; the "on" copy explained how to turn it off and never how to turn it on. It belongs here because the setup screen carries pre-start decisions and whether you are recording is one, and because enabling it here puts the system permission prompt on a stationary screen rather than three seconds into a pre-roll. Named for what it does — "Record with the front camera", the same words as the prompter's own button — rather than after the flag behind it.

**The setup screen's script card is an editor, not a preview.** A preview showing the opening line at reading size with later paragraphs stepping back was built and rejected: `TextEditor` renders one uniform style, so graduated type and inline editing cannot coexist in the same view on this deployment target, and editing behind a tap was worse than plain text. The card is a plain editor set at 19pt rather than `.body` — this is the thing the screen is for, and a script at system body size on a phone is a wall of small grey text.

**The start button must be reachable without scrolling.** `SetupView` sizes the script editor from live geometry (~30% of screen height, clamped) so the button sits above the fold on every screen; the editor scrolls internally. A UI test asserts the button is hittable and inside the window before any scrolling. Options live *below* the button.

**UI tests pass `-uiTestingNoCamera`.** The camera defaults to on, and the simulator has no camera — without the launch argument the capture-permission prompt blocks the run. `TeleprompterState.cameraEnabled` reads it.

**Format-dependent camera properties raise uncatchable exceptions.** `isVideoHDREnabled`, `activeVideoMin/MaxFrameDuration` and `videoZoomFactor` are validated against the **active format**, and an unsupported value raises an Objective-C exception — which Swift cannot catch, so the app dies. Always gate on the format in force (`device.activeFormat.isVideoHDRSupported`, the format's own `videoSupportedFrameRateRanges`, the device's live zoom range), never on a device-wide or cached capability. `capabilities.supportsHDR` describing "some format supports HDR" is what crashed the app when the frame-rate pill switched to a format without HDR. Re-read zoom range and HDR support after every format change.

**Never reconfigure the capture device while recording.** `apply(_:)` refuses, and the on-screen pills hide, because changing `activeFormat` mid-take tears down the file being written.

**A frame that changes nothing must write nothing.** `PrompterTicker` (a `CADisplayLink`, not a `Timer`) calls `PrompterView.tick` once per frame, and every `@State` write in there re-evaluates the whole prompter — which rebuilds *every word view in the script*. The offset smoothing is exponential and so never actually arrives at its target: writing the result unconditionally meant a prompter parked on the reading line, doing nothing, redrawing the entire script sixty times a second forever. It now lands exactly on the target once movement drops below `settleThreshold` and then stops writing. Keep that shape for anything added here — read state, decide, and only write when the result differs.

**The smoothing is time-based, not per-frame.** The step was a flat `gap * 0.12` *per frame*, which made the scroll speed a function of the refresh rate: the same movement ran at one speed on a 60 Hz panel, twice that on a 120 Hz one, and half of it in Low Power Mode. It is now `gap * (1 - exp(-dt / smoothingTau))` with `dt` clamped to 100ms, so a tick delayed by a stall or a backgrounding is not repaid as one enormous jump. `smoothingTau = 0.13` reproduces what the old constant did at 60 Hz.

**The pre-roll leader's sweep must never be driven from `tick()`.** The Academy leader's hand is a SwiftUI animation, which Core Animation runs on the render server. Driving it from the ticker would write state every frame and pin the display link at full rate for the whole pre-roll — undoing the work that stopped the prompter animating when nothing moves. Anything else added here that animates continuously has the same obligation. It is also suppressed under `accessibilityReduceMotion`, which is exactly what that setting exists for.

**The leader dims the script, never the picture.** `scriptLayer` drops to 30% opacity while a countdown runs so the numeral can be read. The camera feed stays fully legible underneath, because the entire point of a pre-roll is checking your framing and eyeline. The visual direction shows a radial vignette here; that is an artboard standing in for a camera it does not have, and adding it in the app would be the scrim the direction itself rules out. Note also that values taken from a static artboard need re-judging against a live script — the cancel caption was specified at 0.32 opacity and is invisible over real text.

**`ChromeType` is the one place the chrome's typeface is decided.** The script keeps SF Pro at its natural width — it is drawn for legibility at a glance, which is the peripheral-reading task this app exists for. Everything else is condensed: uppercase and tracked at 0.13em for small labels, sentence case for status lines and banners (a sentence set in caps shouts), monospaced digits for readouts so timings do not jitter. It uses **iOS 16 system condensed widths, not a bundled face** — the visual direction names Saira Condensed, which costs app size and a `UIAppFonts` entry, and the free width was confirmed on device to carry the look. If that is ever revisited, `ChromeType` is the only file that changes.

**`PrompterView.ground` is one definition shared by both screens.** `#07090C`, not pure black. Changing only the prompter would make the app change colour underneath you when you tap Start. It is safe as a fixed value **only because the app forces `.preferredColorScheme(.dark)` at the root** — light mode never applies. The icon on the amber primary button stays true black: that is foreground on amber, not ground. The trade is real and was judged on a device in the dark, not on a screenshot — pure black on OLED is off pixels, giving deeper contrast for peripheral reading and throwing less light on the speaker's face.

**The tracking frame rate is capped at 60, deliberately.** `PrompterTicker.trackingFrameRate` does not follow the panel to 120Hz. Since the offset smoothing became time-based, 60 and 120 produce *identical* motion — the extra frames buy nothing visible and cost real work, in an app that is simultaneously running live speech recognition and often 4K capture. A warm phone throttles the frame rate *and* the audio buffers recognition depends on, so the cheapest frame is the one not drawn.

**The ticker throttles itself, and anything that needs a frame *now* must wake it.** `setActive` drops the link to `PrompterTicker.idleFrameRate` whenever nothing is animating, which is most of a take. It cannot simply *stop*: the paced pursuit has to keep running to walk a mis-settled layout back onto the reading line, which is why the idle rate is low rather than zero. Two rules follow, and the second was learned by shipping the bug. Anything new that animates must be named in the `setActive` condition at the end of `tick`, or it will run at the idle rate and stutter. And anything that needs a frame immediately must call `ticker.setActive(true)` itself: the ticker re-evaluates its own rate only at the end of a tick, so while idling it would not notice for up to a frame at the idle rate — a delay on *every* word, which is exactly how it was found.

**The ticker's callback is registered once, so it must not close over layout values.** `cueY` is a local computed inside the `GeometryReader`; capturing it in the callback froze it at whatever it was when the prompter appeared, surviving neither rotation nor a drag of the reading-line handle. It is mirrored into `tickCueY` by an `onChange` and read live from there.

**Speech callbacks arrive on an arbitrary queue.** `SFSpeechRecognizer`'s task handler and `AVCaptureFileOutputRecordingDelegate` both call back off the main thread, and everything they touch — the cursor, `@Published` state, `@State` in the view — is main-actor. Both hop to main once at the boundary. Don't add a second hop downstream, and don't remove these.

**An interruption is not an error.** A call, Siri or an alarm ends the recognition task *and* reports an error on the way out. `SpeechTracker` observes `AVAudioSession.interruptionNotification`, sets `interrupted`, and `handleError` returns early while it is set — otherwise a take that is about to resume by itself gets a red banner over it. On `.ended` it restarts only when iOS passes `.shouldResume`, and says so plainly when it doesn't. `PrompterView` follows `speech.$isListening` in **both** directions so a recovered take doesn't read as stopped.

**`end()` deactivates the audio session.** Without it the category stays active after a take and the user's music or podcast stays ducked until the app is killed.

**Recording timers need `.common` run-loop mode.** `CameraController`'s per-second recording clock froze for the duration of any touch on the default mode, so the badge stopped counting the moment a finger touched the script and jumped when it lifted.

**A finished take is deleted from `tmp` only after Photos confirms the copy.** Both halves matter: leaving it accumulated minutes of 4K per take invisibly, and deleting it before the callback would lose the recording outright.

**Haptics are deliberately sparse.** `Haptics` covers take start, take stop, recording start, each pre-roll second, and a saved take — nothing else. The premise of the app is that the reader is looking at the lens rather than the screen, which makes touch the only channel that reaches them during a take; feedback on everything would make it meaningless. Suppressed under `-uiTestingNoCamera`.

**Every script word is its own accessibility element, on purpose.** It reads badly under VoiceOver — one swipe per word — but the reading-line geometry tests locate words through the accessibility tree (`app.staticTexts["Welcome"]`), and those are the tests that caught the line sitting 45pt out of register. Grouping the script needs those assertions given another way to find a word first.

**The audio session is configured off the main thread.** `AVAudioSession.setCategory`/`setActive` block, and Apple warns that calling them on the main thread while the session is active can stall the UI (`SessionCore.mm:631`). A long take hits them repeatedly, since iOS ends a recognition task roughly every minute and `SpeechTracker` restarts the engine. Configuration runs on `sessionQueue`; only `AVAudioEngine`, the recognition task and the `@Published` state they drive come back to main, in `startRecognition`. A `startGeneration` counter guards the hop back, so a take that ends or restarts mid-configuration is not resumed by a stale completion.

**The recognition locale is a real setting, not `en-US`.** It was hard-coded, which meant the app silently did nothing for anyone reading in another language — the prompter simply never moved, with no error to explain it. `SpeechLocales.preferred` resolves the default (exact match, then same language in another region, then English), and the picker appears in *both* the settings sheet and on the setup screen: it is a pre-start decision, and it's the one setting whose failure mode looks like a broken app rather than a wrong option. `SFSpeechRecognizer` is rebuilt when it changes. Command `contextualStrings` stay English.

**The idle timer stays disabled for the whole prompter screen.** A take is minutes of talking to the lens without touching the screen, so iOS would otherwise dim and lock mid-recording. Set in `PrompterView.onAppear`, cleared in `onDisappear` — don't scope it to `isRecording` only.

**Elapsed time excludes pauses.** `SpeakingClock` accumulates only while listening, so the measured pace reflects time actually spent talking. Anything that stops listening (pause, manual mode, exit, a fatal recognition error) must pause the clock too, or the pace readout decays during a break.

## Permissions

`SpeechTracker.begin()` must request **both** speech-recognition and microphone permission before starting the engine. iOS never prompts for speech recognition on its own; without the explicit request the status stays `.notDetermined` and every recognition task fails silently. Surface permission failures — don't retry them in a loop.

## Conventions

- Comments explain constraints and non-obvious *why*, not what the next line does. Several existing comments record hard-won platform behaviour — keep them.
- Match the surrounding style: SwiftUI view builders, `@Published` state on `TeleprompterState`, small pure types for testable logic.
- Keep the icon reproducible: edit `Tools/make_icon.py` and re-run it, don't hand-edit the PNG.
- Keep the App Store screenshots reproducible the same way. They are generated, not retouched: run `CueUITests/MarketingCaptures` on a device, export the attachments (`xcrun xcresulttool export attachments`), then `Tools/marketing_screens.py <exports-dir> Marketing/AppStoreScreenshots`. `marketing_screens.py` is the entry point and holds the frame list — which capture, which headline, which crop; `Tools/marketing_compositor.py` holds the layout. The whole pipeline is in the repo because its predecessor was not: it lived in a scratch directory, was lost, and its headline copy had to be recovered by reading pixels out of the old PNGs. Note the name changed meaning at 1.5 — at 1.4 `marketing_screens.py` *was* the layout, for the earlier plum-band design.
- Two things inside it are deliberate and easy to undo by accident. The capture is cropped from **above** the reading line, never bottom-sliced: a bottom slice discards the top ~18% of the screen, which on a teleprompter is exactly where the reading line and the amber active word live — the evidence for whatever the caption claims. And the accent panel is a **fixed** height, not one derived from its headline's line count, because a row of five panels at four different heights reads as an accident. `MarketingCaptures` also places the cursor at three different points (18, 58, 96) so the prompter frames don't show the same paragraph three times.

## Keep the docs current

Any change to behaviour, knobs, or invariants must update this file and `README.md` **in the same change**. A stale AGENTS.md is worse than none.
