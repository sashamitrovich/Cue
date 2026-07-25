import SwiftUI

@main
struct CueApp: App {
    @StateObject private var state = TeleprompterState()

    var body: some Scene {
        WindowGroup {
            SetupView(state: state)
                .preferredColorScheme(.dark)
        }
    }
}
