import SwiftUI
import UIKit

/// Which orientations the app will accept, right now.
///
/// The prompter is used in both — landscape is what a rig wants. The setup
/// screen is not: it is a title, an editor and a button in a single column,
/// and in landscape the keyboard takes most of the screen and the column
/// stretches into something that reads like a mistake. There is nothing to
/// gain by rotating it, so it does not.
///
/// iOS asks the app delegate which orientations a window supports, so the
/// answer has to live somewhere UIKit can reach — a static, set by whichever
/// screen is on top. SwiftUI has no equivalent of its own on this deployment
/// target.
enum OrientationLock {
    static var supported: UIInterfaceOrientationMask = .all {
        didSet {
            guard supported != oldValue else { return }
            apply()
        }
    }

    /// Asks the window scene to rotate back into an allowed orientation.
    ///
    /// Setting the mask alone only governs *future* rotations — a phone
    /// already held in landscape stays there until something asks it to move,
    /// which on iOS 16 is `requestGeometryUpdate`. Its error handler is
    /// deliberately empty: being refused means the device is already somewhere
    /// acceptable, which is the outcome wanted anyway.
    private static func apply() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: supported)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// The delegate exists only to answer the orientation question. SwiftUI has
/// no hook for it on iOS 16.
final class CueAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.supported
    }
}

extension View {
    /// Holds the app to `mask` while this view is on screen, and to
    /// `restoring` once it goes away.
    ///
    /// Both ends are explicit because the two screens are each other's
    /// restore state: leaving the setup screen means entering the prompter,
    /// which wants every orientation, and leaving the prompter means going
    /// back to a screen that wants only one. A single hard-coded restore
    /// value would be wrong at one end or the other.
    func orientationLock(
        _ mask: UIInterfaceOrientationMask,
        restoring restore: UIInterfaceOrientationMask = .all
    ) -> some View {
        onAppear { OrientationLock.supported = mask }
            .onDisappear { OrientationLock.supported = restore }
    }
}
