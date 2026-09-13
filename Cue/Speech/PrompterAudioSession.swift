import AVFoundation
import Foundation

/// The one place the shared audio session is configured.
///
/// Two subsystems need the microphone during a take — speech recognition and
/// the camera's capture session — and for most of this app's life neither
/// owned the session. `AVCaptureSession` configured it by default, the
/// recogniser configured it again on every take, and whichever ran last won.
/// Three separate ways of losing a take's sound came out of that:
///
/// - Pausing a take deactivated the session while the camera was still
///   writing a file, and the sound died from the pause onward. Permanently,
///   and invisibly until playback.
/// - Pausing *before* recording deactivated it too, so the next recording
///   started against a dead session and captured no audio at all.
/// - Taking the job away from the capture session, without giving it to
///   anyone, left the camera starting against an unconfigured session: a
///   frozen preview on a cold launch, and a movie writer stalling mid-file.
///
/// So it has an owner now. The prompter activates it when it appears and
/// hands it back when it leaves, and nothing in between reconfigures it.
/// Pausing is not finishing; leaving is.
enum PrompterAudioSession {

    /// `.videoRecording` is what Camera.app uses, and it is what makes a take
    /// sound like something worth publishing — the system's gain and noise
    /// handling stay in the signal path. It was `.measurement`, which exists
    /// to strip exactly that out. Reasonable for a recogniser reading levels,
    /// and the reason takes came out flat and quiet. Recognition works on the
    /// processed signal too, so one mode serves both and there is no reason
    /// to switch when the camera is toggled.
    static let mode: AVAudioSession.Mode = .videoRecording
    static let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]

    /// Serialised, and off the main thread: `setCategory` and `setActive`
    /// block, and Apple warns that calling them on the main thread while the
    /// session is live can stall the UI.
    private static let queue = DispatchQueue(label: "app.oncue.audio-session")

    /// Configures and activates the session, if it is not already how we want
    /// it. Safe to call repeatedly — re-applying a category and mode
    /// renegotiates the audio route, which is not something to do underneath
    /// a capture session that is midway through writing a file.
    static func activate(completion: ((Error?) -> Void)? = nil) {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                if session.category != .playAndRecord
                    || session.mode != mode
                    || session.categoryOptions != options {
                    try session.setCategory(.playAndRecord, mode: mode, options: options)
                }
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                DispatchQueue.main.async { completion?(nil) }
            } catch {
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    /// Hands the session back, so anyone else's music starts again.
    ///
    /// Only ever on leaving the prompter or on the app going to the
    /// background. Never on pausing a take: pausing means you are about to
    /// carry on, and tearing the session down between the two is what lost
    /// the sound.
    static func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
