import SwiftUI

@main
struct CueApp: App {
    @UIApplicationDelegateAdaptor(CueAppDelegate.self) private var delegate
    @StateObject private var state = TeleprompterState()

    var body: some Scene {
        WindowGroup {
            SetupView(state: state)
                .preferredColorScheme(.dark)
                // The setup screen is portrait only: see `OrientationLock`.
                // The prompter restores `.all` when it appears.
                .orientationLock(.portrait)
        }
    }
}
