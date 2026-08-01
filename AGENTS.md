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

Bump `CFBundleVersion` in `project.yml` for every TestFlight upload; App Store Connect rejects a build number it has already accepted.

## What you cannot verify here

The simulator has **no microphone and no camera**. Speech recognition and camera capture cannot be exercised locally — do not claim they work based on a green build. Say plainly that they need testing on a physical device, and ask.

Hardware-coupled types (`SpeechTracker`, `CameraController`) are deliberately not unit tested for this reason. Don't add tests that pretend to cover them; put logic worth testing into pure types instead (as `TranscriptDeltaTracker` and `ScriptImporter` do).

## Verifying visual changes

Layout and legibility changes need real evidence, because code that looks right often doesn't render. The loop:

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

**Never feed the cumulative transcript to the matcher.** `SFSpeechRecognitionResult.bestTranscription.formattedString` repeats everything said so far on every partial result. `TranscriptDeltaTracker` reduces it to newly appended words. Passing the whole transcript makes the cursor lurch forward, because each already-consumed word gets another chance to match ahead.

**Filler words must not match far ahead.** `TeleprompterState.filler` words only match within `fillerReach` of the cursor. Common words recur throughout any script, and letting them match anywhere in the look-ahead window is the other cause of jumping. Distinctive words keep full window reach — that is how the matcher recovers from genuinely missed words.

**`words` and `lines` must stay consistent.** `words` is the flat reading-order list the matcher walks; `lines` groups those same words for layout with blank lines preserved as ad-lib space. Word ids are sequential across the whole script and must agree between the two. The flat list's contract is depended on by the original matcher tests.

**Normalize line endings before splitting.** Splitting CRLF text on a newline *character set* invents a blank line between every line. `buildWords` normalizes `\r\n` and `\r` first.

**Layout must come from live geometry, not `UIScreen`.** `UIScreen.main.bounds` reports the wrong height in landscape. `ScrollFlow` takes its insets from the `GeometryReader`.

**Mirroring is explicit, in one place.** The SwiftUI `.scaleEffect(x: -1)` does it. `AVCaptureVideoPreviewLayer`'s automatic front-camera mirroring is deliberately disabled — re-enabling it double-flips the preview. Recorded files stay unmirrored so takes read naturally.

**Camera controls are capability-gated.** Every row in `PrompterControlsSheet` is conditional on what `CameraController.detectCapabilities` found on the actual device. Never show a control the connected iPhone doesn't support.

**`sessionPreset` is `.inputPriority`** so `device.activeFormat` takes effect. Changing it to a fixed preset silently breaks the quality picker.

**Quality is two toggles, not a format list.** `CaptureQualityMenu` collapses the device's formats into at most two tiers (HD / 4K), each with its available frame rates — the same choice Camera.app offers. Keep only the largest size per tier: 720p and 1080p both label as "HD" and would give the toggle two indistinguishable positions. Every offered mode resolves to the *widest-FOV* format that can serve it, for the same reason `setup` picks a wide format explicitly.

**Only 16:9 formats are video sizes.** The front camera publishes 4:3, stills-shaped formats (3088x2320, 1920x1440) next to the video ones. Grouping by height alone let 2320 outrank 2160 and put a stills format behind the "4K" toggle, where it offered a single frame rate — which is how the bug was noticed. `CameraController.isWidescreen` filters at the AVFoundation boundary and `VideoMode.recognizedHeights` (720/1080/2160) guards the pure side.

**The bottom bar is a bar.** It spans the full width with an opaque background; backing only the buttons' intrinsic width leaves the script visible around a floating black box over a camera feed, and translucency isn't enough either — at 86% the words were still legible through it.

**Both quality pills stay visible.** They're a readout as much as a control; a pill that vanishes when you switch tier (because that tier offers one frame rate) reads as a bug. A pill with nothing to offer renders dimmed and disabled instead.

**`setup()` runs once.** The camera can be toggled off and back on mid-take, and re-running it would add a second set of inputs and outputs to the session — `isConfigured` gates it, and restarts go through `start()`. Orientation notifications are begin/end nesting-counted, so `startTrackingOrientation` no-ops when already registered.

**The start button must be reachable without scrolling.** `SetupView` sizes the script editor from live geometry (~30% of screen height, clamped) so the button sits above the fold on every screen; the editor scrolls internally. A UI test asserts the button is hittable and inside the window before any scrolling. Options live *below* the button.

**UI tests pass `-uiTestingNoCamera`.** The camera defaults to on, and the simulator has no camera — without the launch argument the capture-permission prompt blocks the run. `TeleprompterState.cameraEnabled` reads it.

**Format-dependent camera properties raise uncatchable exceptions.** `isVideoHDREnabled`, `activeVideoMin/MaxFrameDuration` and `videoZoomFactor` are validated against the **active format**, and an unsupported value raises an Objective-C exception — which Swift cannot catch, so the app dies. Always gate on the format in force (`device.activeFormat.isVideoHDRSupported`, the format's own `videoSupportedFrameRateRanges`, the device's live zoom range), never on a device-wide or cached capability. `capabilities.supportsHDR` describing "some format supports HDR" is what crashed the app when the frame-rate pill switched to a format without HDR. Re-read zoom range and HDR support after every format change.

**Never reconfigure the capture device while recording.** `apply(_:)` refuses, and the on-screen pills hide, because changing `activeFormat` mid-take tears down the file being written.

**The idle timer stays disabled for the whole prompter screen.** A take is minutes of talking to the lens without touching the screen, so iOS would otherwise dim and lock mid-recording. Set in `PrompterView.onAppear`, cleared in `onDisappear` — don't scope it to `isRecording` only.

**Elapsed time excludes pauses.** `SpeakingClock` accumulates only while listening, so the measured pace reflects time actually spent talking. Anything that stops listening (pause, manual mode, exit, a fatal recognition error) must pause the clock too, or the pace readout decays during a break.

## Permissions

`SpeechTracker.begin()` must request **both** speech-recognition and microphone permission before starting the engine. iOS never prompts for speech recognition on its own; without the explicit request the status stays `.notDetermined` and every recognition task fails silently. Surface permission failures — don't retry them in a loop.

## Conventions

- Comments explain constraints and non-obvious *why*, not what the next line does. Several existing comments record hard-won platform behaviour — keep them.
- Match the surrounding style: SwiftUI view builders, `@Published` state on `TeleprompterState`, small pure types for testable logic.
- Keep the icon reproducible: edit `Tools/make_icon.py` and re-run it, don't hand-edit the PNG.

## Keep the docs current

Any change to behaviour, knobs, or invariants must update this file and `README.md` **in the same change**. A stale AGENTS.md is worse than none.
