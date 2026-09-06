import SwiftUI

/// One place that explains the app and every option in it.
///
/// Deliberately a single sheet behind one "?" rather than an info dot on each
/// control: most of these settings are obvious once you've used them, and a
/// row of little "i" buttons adds permanent clutter to solve a first-run
/// problem. The one genuinely opaque option — Mirror — also gets a one-line
/// caption in place on the setup screen.
struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    explain(
                        "The script follows your voice",
                        "Tap Listen and start speaking. On Cue matches what it hears against your script and scrolls to keep the line you're on at the reading line. Stop talking and it waits. Paraphrase, skip a word, or start a sentence again and it stays with you."
                    )
                    explain(
                        "It uses your phone's speech model",
                        "Speech recognition runs on your device. If it hasn't downloaded the offline speech model (Settings → General → Keyboard → Dictation), iOS falls back to Apple's speech service, which means audio is sent to Apple to be transcribed — the same thing dictation does. When using the local model, your script and your recordings never leave the device. Videos are saved straight to your Photos library only."
                    )
                }

                Section("Before you start") {
                    explain("Share a script to On Cue", "From another app — Notes, Mail, Files, Drive — tap Share and choose On Cue. It waits for you here and asks before replacing the script you already have. A Google Doc shares as a link rather than text, so use \"Send a copy\" and pick plain text or rich text.")
                    explain("Import", "Load a script from Files or iCloud Drive — .txt, .md or .rtf. Line breaks and blank lines carry through, so leave a blank line where you want ad-lib room. You can edit the script for finishing touches and the changes save automatically.")
                    explain("Pace", "Your target words per minute. It's what the run-time estimate is based on until you've spoken enough of a take for On Cue to measure your real pace. This gives you the feel of how long the text takes to be spoken.")
                    explain("Countdown", "A pre-roll before listening starts, so you can check your framing and settle before you speak. Tap anywhere to cancel the start if you're not ready.")
                }

                Section("Voice commands") {
                    explain("\"scroll up\" or \"go back\"", "In the listening mode, it steps the script back one line on screen and moves the cursor with it, so that line reads as unread again. Say it again to go back further.")
                    explain("\"scroll down\" or \"go on\"", "Steps forward one line, the same way.")
                }

                Section("In the prompter") {
                    explain("Listen / Pause", "Starts and stops voice tracking. Pausing keeps your place and stops the clock.")
                    explain("Restart", "Jumps back to the first word and starts the timing over.")
                    explain("Record", "Records a take from the camera. The recording is saved to Photos when you stop.")
                    explain("Drag the script with your finger", "Works always, listening or not — drag to scroll by hand, and voice tracking picks up from wherever you let go, the next word to speak is highlighted.")
                    explain("Camera", "Turns the live camera view behind the script on or off.")
                    explain("Turning sideways", "In landscape the controls move to a rail on the edge they were already on, so they stay under the same thumb and stop eating the height you need for the script.")
                    explain("HD / 4K", "Recording size and frame rate, offered only as far as your device's front camera supports. Stop recording to change them.")
                    explain("Mirror", "Flips the script top-to-bottom for teleprompter rigs that bounce the screen off a sheet of glass in front of the lens; the reflection turns it back the right way round. The controls stay exactly where they are and read normally, since you look at them directly rather than through the glass. Reading straight from the phone? Leave it off.")
                    explain("Reading line", "The marked line your eyes read from. Adjust it any time from the settings button, to keep it as near to the lens as possible.")
                    explain("Text and Dim", "Text fades the script so more of the camera shows through; Dim darkens the picture behind it. Between them you can keep the words legible over any background.")
                    explain("Timing", "Elapsed speaking time, an estimate of what's left, and your pace. The estimate is marked with a ~ until On Cue has heard enough of the take to measure how fast you actually talk.")
                }

                Section {
                    Text("The screen stays awake for as long as the prompter is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How On Cue works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func explain(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
