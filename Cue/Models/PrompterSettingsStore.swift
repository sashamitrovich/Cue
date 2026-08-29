import Foundation

/// Persists the prompter's tunable settings — everything in the Prompter
/// settings sheet — across launches. The script itself and session state
/// (the reading cursor, whether a take is running, manual mode) reset with
/// each launch by design; only preferences live here.
struct PrompterSettingsStore {
    enum Key: String {
        case fontSize, driftIndex, mirror, textAlignment, cameraEnabled,
             textOpacity, cueLineFraction, sideMargin, cameraDimming,
             targetWPM, countdownSeconds, showTiming, voiceCommandsEnabled,
             readTextFloor, recognitionLocale
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func double(_ key: Key, default value: Double) -> Double {
        defaults.object(forKey: key.rawValue) != nil ? defaults.double(forKey: key.rawValue) : value
    }

    func set(_ key: Key, _ value: Double) {
        defaults.set(value, forKey: key.rawValue)
    }

    func int(_ key: Key, default value: Int) -> Int {
        defaults.object(forKey: key.rawValue) != nil ? defaults.integer(forKey: key.rawValue) : value
    }

    func set(_ key: Key, _ value: Int) {
        defaults.set(value, forKey: key.rawValue)
    }

    func bool(_ key: Key, default value: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) != nil ? defaults.bool(forKey: key.rawValue) : value
    }

    func set(_ key: Key, _ value: Bool) {
        defaults.set(value, forKey: key.rawValue)
    }

    func string(_ key: Key, default value: String) -> String {
        defaults.string(forKey: key.rawValue) ?? value
    }

    func set(_ key: Key, _ value: String) {
        defaults.set(value, forKey: key.rawValue)
    }
}
