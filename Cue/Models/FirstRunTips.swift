import Foundation

/// One-time hints, shown where the feature is rather than in a manual.
///
/// Voice commands are invisible: nothing on screen suggests the prompter is
/// listening for instructions as well as for the script. A hint the first
/// time you start a take is the only place it is genuinely useful, and it
/// must never appear twice.
struct FirstRunTips {
    private static let voiceCommandKey = "seenVoiceCommandTip"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether to show the voice-command hint for this take.
    ///
    /// - Parameter commandsEnabled: no point advertising a feature that is
    ///   switched off.
    func shouldShowVoiceCommandTip(commandsEnabled: Bool) -> Bool {
        commandsEnabled && !defaults.bool(forKey: Self.voiceCommandKey)
    }

    func markVoiceCommandTipSeen() {
        defaults.set(true, forKey: Self.voiceCommandKey)
    }
}
