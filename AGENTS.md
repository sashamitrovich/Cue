# Working on Cue

Guidance for AI agents (and humans) making changes here. Read this before touching the code.

Cue is a SwiftUI iPhone teleprompter: the script scrolls as you speak, with front-camera recording. iOS 16.0 deployment target.

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

**`sessionPreset` is `.inputPriority`** so `device.activeFormat` takes effect. Changing it to a fixed preset silently breaks the resolution picker.

## Permissions

`SpeechTracker.begin()` must request **both** speech-recognition and microphone permission before starting the engine. iOS never prompts for speech recognition on its own; without the explicit request the status stays `.notDetermined` and every recognition task fails silently. Surface permission failures — don't retry them in a loop.

## Conventions

- Comments explain constraints and non-obvious *why*, not what the next line does. Several existing comments record hard-won platform behaviour — keep them.
- Match the surrounding style: SwiftUI view builders, `@Published` state on `TeleprompterState`, small pure types for testable logic.
- Keep the icon reproducible: edit `Tools/make_icon.py` and re-run it, don't hand-edit the PNG.

## Keep the docs current

Any change to behaviour, knobs, or invariants must update this file and `README.md` **in the same change**. A stale AGENTS.md is worse than none.
