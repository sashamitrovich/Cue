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
                        "Tap Listen and start speaking. Cue matches what it hears against your script and scrolls to keep the line you're on at the reading line. Stop talking and it waits. Paraphrase, skip a word, or start a sentence again and it stays with you."
                    )
                    explain(
                        "Nothing leaves your phone",
                        "Speech recognition runs on-device, and takes are saved straight to your Photos library."
                    )
                }

                Section("On the setup screen") {
                    explain("Import", "Load a script from Files or iCloud Drive — .txt, .md or .rtf. Line breaks and blank lines carry through, so leave a blank line where you want ad-lib room.")
                    explain("Text size", "How large the script is drawn in the prompter. Adjustable mid-take too.")
                    explain("Idle drift", "How fast the script creeps upward while you're silent. Useful as a nudge if a word goes unrecognised; set it to Off if you'd rather the script never move on its own.")
                    explain("Pace", "Your target words per minute. It's what the run-time estimate is based on until you've spoken enough of a take for Cue to measure your real pace.")
                    explain("Countdown", "A pre-roll before listening starts, so you can settle and look at the lens. Tap anywhere to cancel it.")
                    explain("Mirror", "Flips the text left-to-right. This is for teleprompter rigs that bounce the screen off a sheet of glass in front of the lens — the reflection flips it back the right way round. Reading straight from the phone? Leave it off.")
                    explain("Align", "Left-aligned reads faster for most people; centred keeps your eyes closer to the lens on a wide screen.")
                }

                Section("In the prompter") {
                    explain("Listen / Pause", "Starts and stops voice tracking. Pausing keeps your place and stops the clock.")
                    explain("Restart", "Jumps back to the first word and starts the timing over.")
                    explain("Record", "Records a take from the front camera. The recording is saved to Photos when you stop.")
                    explain("Manual", "Turns off voice tracking so you can drag the script with your finger.")
                    explain("Camera", "Turns the live camera view behind the script on or off.")
                    explain("HD / 4K", "Recording size and frame rate, offered only as far as your iPhone's front camera supports. Stop recording to change them.")
                    explain("Reading line", "The orange line your eyes read from. Keep it high on the screen so you're looking near the lens rather than down the phone. The chevrons on the right nudge it mid-take.")
                    explain("Text and Dim", "Text fades the script so more of the camera shows through; Dim darkens the camera behind it. Between them you can keep the words legible over any background.")
                    explain("Timing", "Elapsed speaking time, an estimate of what's left, and your pace. The estimate is marked with a ~ until Cue has heard enough of the take to measure how fast you actually talk.")
                }

                Section {
                    Text("The screen stays awake for as long as the prompter is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How Cue works")
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
