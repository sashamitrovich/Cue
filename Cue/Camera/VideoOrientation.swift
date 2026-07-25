import AVFoundation
import UIKit

extension AVCaptureVideoOrientation {
    /// Maps device rotation to capture orientation. Landscape is swapped
    /// (not a typo) — the front camera sensor is mounted rotated 90°
    /// relative to the device's home-button-down portrait orientation, so a
    /// physical rotation to `.landscapeLeft` requires `.landscapeRight` to
    /// keep the captured image right-side up.
    static func matching(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil // faceUp/faceDown/unknown: keep the last known orientation
        }
    }
}
