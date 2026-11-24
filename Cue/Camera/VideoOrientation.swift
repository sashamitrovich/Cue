import AVFoundation
import UIKit

extension AVCaptureVideoOrientation {
    /// Maps device rotation to capture orientation.
    ///
    /// Landscape is swapped (not a typo), and the swap is the same for both
    /// cameras: `UIDeviceOrientation.landscapeLeft` means "home button on the
    /// right", while `AVCaptureVideoOrientation.landscapeRight` means "video
    /// oriented horizontally, port on the right" — the same physical state, so
    /// the two enums name it differently. The front/back difference is
    /// mirroring, handled separately, never the rotation mapping.
    static func matching(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil // faceUp/faceDown/unknown: keep the last known orientation
        }
    }

    /// True for orientations that actually say which way up the device is.
    /// Face-up, face-down and unknown are not answers, so callers keep the last
    /// determinate orientation instead of letting a phone laid flat flip the
    /// recording.
    static func isDeterminate(_ orientation: UIDeviceOrientation) -> Bool {
        switch orientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return true
        default:
            return false
        }
    }
}
