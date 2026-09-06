import XCTest
@testable import Cue

/// Every setting in the prompter sheet, round-tripped through the store.
///
/// A setting persists only if three separate things line up: a `Key` case, a
/// `didSet` that writes it, and a line in `init` that reads it back. Miss any
/// one and the setting silently forgets itself between launches — nothing
/// crashes, nothing logs, and it is only noticeable if you happen to look for
/// that particular preference after relaunching.
///
/// `testEveryPersistedKeyIsCovered` is the part that matters most: it fails
/// when a new `Key` is added without a test here, so this file cannot quietly
/// fall behind the settings it is supposed to cover.
final class SettingsPersistenceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Writes settings through one state object, then builds a second one on
    /// the same store — which is what a relaunch does.
    private func afterRelaunch(_ change: (TeleprompterState) -> Void) -> TeleprompterState {
        let store = PrompterSettingsStore(defaults: defaults)
        change(TeleprompterState(settings: store))
        return TeleprompterState(settings: store)
    }

    func testFontSizeSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.fontSize = 47 }.fontSize, 47)
    }

    func testMirrorSurvivesARelaunch() {
        XCTAssertTrue(afterRelaunch { $0.mirror = true }.mirror)
    }

    func testTextAlignmentSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.textAlignment = .justified }.textAlignment, .justified)
    }

    func testTextOpacitySurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.textOpacity = 0.42 }.textOpacity, 0.42, accuracy: 0.0001)
    }

    func testReadingLinePositionSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.cueLineFraction = 0.73 }.cueLineFraction, 0.73, accuracy: 0.0001)
    }

    func testSideMarginSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.sideMargin = 31 }.sideMargin, 31)
    }

    func testCameraDimmingSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.cameraDimming = 0.61 }.cameraDimming, 0.61, accuracy: 0.0001)
    }

    func testTargetPaceSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.targetWPM = 175 }.targetWPM, 175, accuracy: 0.0001)
    }

    func testCountdownSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.countdownSeconds = 10 }.countdownSeconds, 10)
    }

    func testShowTimingSurvivesARelaunch() {
        XCTAssertFalse(afterRelaunch { $0.showTiming = false }.showTiming)
    }

    func testVoiceCommandsSurviveARelaunch() {
        XCTAssertFalse(afterRelaunch { $0.voiceCommandsEnabled = false }.voiceCommandsEnabled)
    }

    func testReadTextFloorSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.readTextFloor = 0.29 }.readTextFloor, 0.29, accuracy: 0.0001)
    }

    func testRecognitionLocaleSurvivesARelaunch() {
        XCTAssertEqual(afterRelaunch { $0.recognitionLocale = "hr-HR" }.recognitionLocale, "hr-HR")
    }

    func testCameraEnabledSurvivesARelaunch() {
        // This one persisting is what made the setup screen's camera control
        // necessary: turning it off inside the prompter came back next launch
        // with no way to turn it on from the screen that reported it.
        XCTAssertFalse(afterRelaunch { $0.cameraEnabled = false }.cameraEnabled)
    }

    func testAFreshInstallGetsTheDefaults() {
        // Nothing written: every setting must fall back to its default rather
        // than to a zero read out of an empty store.
        let fresh = TeleprompterState(settings: PrompterSettingsStore(defaults: defaults))
        XCTAssertEqual(fresh.fontSize, 32)
        XCTAssertEqual(fresh.targetWPM, ReadingPace.defaultWPM)
        XCTAssertGreaterThan(fresh.textOpacity, 0, "a default of zero would render the script invisible")
        XCTAssertFalse(fresh.recognitionLocale.isEmpty)
    }

    func testEveryPersistedKeyIsCovered() {
        // The guard on this file. Adding a Key without a round-trip test here
        // fails, rather than leaving a setting that quietly does not persist.
        let tested: Set<PrompterSettingsStore.Key> = [
            .fontSize, .mirror, .textAlignment, .cameraEnabled, .textOpacity,
            .cueLineFraction, .sideMargin, .cameraDimming, .targetWPM,
            .countdownSeconds, .showTiming, .voiceCommandsEnabled,
            .readTextFloor, .recognitionLocale,
        ]
        let all = Set(PrompterSettingsStore.Key.allCases)
        XCTAssertEqual(
            all.subtracting(tested), [],
            "a setting was added without a round-trip test in this file"
        )
    }
}
