# Cue

A voice-controlled teleprompter for iPhone. The script scrolls as you speak — stop talking and it waits for you — while the front camera records your take.

Built with SwiftUI, Apple's Speech framework and AVFoundation. No subscription, no account, no network: speech recognition runs on-device by default and nothing leaves the phone.

## What it does

- **Follows your voice.** On-device speech recognition matches what you say against the script and moves the reading line to keep your place. Skip a word, paraphrase, or pause and it stays with you.
- **Records while you read.** Front-camera capture with the script overlaid, saved straight to Photos. The camera is on by default and toggles off from the prompter itself, where you can see what it does.
- **Explains itself.** A "?" on the setup screen opens a plain-language guide to every option — including Mirror, which is for teleprompter glass rigs and not for reading off the phone.
- **Times your read.** Word count and estimated run time as you write, then elapsed time, time left and a progress bar while you speak. The estimate starts from your target pace and switches to your *measured* pace once there's enough of the take to judge from.
- **Counts you in.** An optional 3, 5 or 10 second pre-roll before listening starts, so you can settle and find the lens. Tap anywhere to cancel it.
- **Adapts to the device.** Zoom, HDR, stabilisation and low-light boost appear as controls only if the connected iPhone's front camera actually supports them. Recording quality is a Camera.app-style pair of toggles — HD or 4K, and the frame rates that size offers (24/25/30/60, as far as the camera supports) — right on the prompter.
- **Stays readable over video.** Adjustable text opacity and camera dimming, with per-word contrast shadows so words survive against a bright background.
- **Keeps your formatting.** Line breaks and blank lines carry over from the editor, so you can leave deliberate gaps as ad-lib room.
- **Imports scripts** from Files or iCloud Drive (`.txt`, `.md`, `.rtf`).
- **Manual mode** for dragging through the script by hand when you would rather not be tracked.

## Requirements

- iOS 16.0 or later
- Xcode (developed against Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

Speech recognition and camera capture need a **physical device** — the simulator has no microphone or camera, so voice tracking and recording cannot be exercised there.

## Getting started

```sh
brew install xcodegen      # once
xcodegen generate          # writes Cue.xcodeproj from project.yml
open Cue.xcodeproj
```

The Xcode project is generated rather than committed, so `project.yml` is the source of truth for targets, build settings and Info.plist keys. Re-run `xcodegen generate` after changing it.

To run on your own device, give the project your Apple Developer Team ID:

```sh
cp Signing.xcconfig.example Signing.xcconfig   # then edit in your team ID
xcodegen generate
```

Set it there rather than in Xcode's **Signing & Capabilities** pane — the project file is regenerated, so a team picked in the UI is wiped on the next `xcodegen generate`. `Signing.xcconfig` is gitignored.

## Tests

```sh
xcodebuild -project Cue.xcodeproj -scheme Cue \
  -destination 'platform=iOS Simulator,name=iPhone 14' test
```

Unit tests cover the parts with real logic — script tokenisation, line grouping, transcript handling, the word matcher, pace/timing maths and the video-quality menu. UI tests are smoke tests that catch layout regressions such as controls being pushed off-screen. Hardware-coupled code (`CameraController`, `SpeechTracker`) is deliberately not unit tested: it needs a real camera and microphone.

## How the voice tracking works

`SFSpeechRecognizer` delivers a *cumulative* transcript — every partial result repeats everything said so far. `TranscriptDeltaTracker` reduces that to only the newly appended words, so the matcher never re-scans words it already consumed.

`TeleprompterState.ingest(transcriptWords:)` then walks those words against a look-ahead window of the script. Matching is fuzzy in both directions (a heard word may be a prefix of a script word or vice versa) so partial recognition still advances the cursor. Common filler words — "the", "and", "of" — are only allowed to match at or next to the cursor, because letting them match anywhere in the window is what makes a prompter lurch forward mid-sentence.

## Layout

```
Cue/
  Models/        script state, word matching, import decoding
  Speech/        on-device recognition and transcript delta handling
  Camera/        capture session, capability detection, orientation
  Views/         setup screen, prompter, controls
CueTests/        unit tests
CueUITests/      UI smoke tests and screenshot capture
Tools/           icon generation
```

## Icon

The icon is generated, not drawn by hand:

```sh
python3 Tools/make_icon.py
```

## Licence

MIT — see [LICENSE](LICENSE).
