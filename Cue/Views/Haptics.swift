import UIKit

/// Touch feedback for the moments you can't be looking at the screen.
///
/// The whole premise of the prompter is that your eyes are on the lens, not
/// the phone — which makes the screen the one channel that can't confirm
/// anything during a take. A countdown you're not watching, a Record tap you
/// made by feel, a take that finished saving: each of those needs to arrive
/// through the hand instead.
///
/// Deliberately sparse. Feedback on everything is feedback on nothing, so
/// this covers starting, stopping, the last seconds of a pre-roll, and a take
/// safely stored — and nothing else.
enum Haptics {
    /// Silent during UI tests, and on any device without a Taptic Engine
    /// (`UIFeedbackGenerator` no-ops there rather than failing).
    private static var enabled: Bool {
        !ProcessInfo.processInfo.arguments.contains("-uiTestingNoCamera")
    }

    /// A take begins.
    static func takeStarted() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A take is paused or stopped — lighter than starting one, so the two
    /// are distinguishable by feel alone.
    static func takeStopped() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Recording has actually begun rolling.
    static func recordingStarted() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// One second of the pre-roll. Soft, because it repeats.
    static func countdownTick() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// The take is in the Photos library.
    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
