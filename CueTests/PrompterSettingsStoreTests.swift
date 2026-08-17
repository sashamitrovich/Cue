import XCTest
@testable import Cue

final class PrompterSettingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: PrompterSettingsStore!

    override func setUpWithError() throws {
        let name = "settings-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        store = PrompterSettingsStore(defaults: defaults)
    }

    func testUnsetValuesFallBackToTheSuppliedDefault() {
        XCTAssertEqual(store.double(.fontSize, default: 32), 32)
        XCTAssertEqual(store.int(.driftIndex, default: 2), 2)
        XCTAssertEqual(store.bool(.mirror, default: true), true)
        XCTAssertEqual(store.string(.textAlignment, default: "leading"), "leading")
    }

    func testValuesSurviveANewInstanceOfTheStore() {
        store.set(.fontSize, 48.0)
        store.set(.driftIndex, 3)
        store.set(.mirror, true)
        store.set(.textAlignment, "justified")

        let fresh = PrompterSettingsStore(defaults: defaults)
        XCTAssertEqual(fresh.double(.fontSize, default: 0), 48)
        XCTAssertEqual(fresh.int(.driftIndex, default: 0), 3)
        XCTAssertEqual(fresh.bool(.mirror, default: false), true)
        XCTAssertEqual(fresh.string(.textAlignment, default: ""), "justified")
    }

    func testAFalseOrZeroValueIsNotMistakenForUnset() {
        // The naive `defaults.bool(forKey:) == false` / `.integer(forKey:) == 0`
        // check can't tell "never set" from "set to the falsy value" — this
        // store checks presence explicitly instead.
        store.set(.mirror, false)
        store.set(.countdownSeconds, 0)
        XCTAssertEqual(store.bool(.mirror, default: true), false)
        XCTAssertEqual(store.int(.countdownSeconds, default: 3), 0)
    }
}

final class TeleprompterStateSettingsPersistenceTests: XCTestCase {

    func testPreferencesSurviveANewInstance() {
        let name = "state-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = PrompterSettingsStore(defaults: defaults)

        let first = TeleprompterState(settings: store)
        first.fontSize = 44
        first.textAlignment = .justified
        first.mirror = true

        let second = TeleprompterState(settings: store)
        XCTAssertEqual(second.fontSize, 44)
        XCTAssertEqual(second.textAlignment, .justified)
        XCTAssertEqual(second.mirror, true)
    }

    func testScriptTextAndSessionStateAreNotPersisted() {
        let name = "state-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = PrompterSettingsStore(defaults: defaults)

        let first = TeleprompterState(settings: store)
        first.scriptText = "Something else entirely"
        first.activeIndex = 5

        let second = TeleprompterState(settings: store)
        XCTAssertNotEqual(second.scriptText, "Something else entirely")
        XCTAssertEqual(second.activeIndex, 0)
    }
}
