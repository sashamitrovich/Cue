import XCTest
@testable import Cue

final class FirstRunTipsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var tips: FirstRunTips!

    override func setUpWithError() throws {
        let name = "tips-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        tips = FirstRunTips(defaults: defaults)
    }

    func testTheHintIsOfferedOnTheFirstTake() {
        XCTAssertTrue(tips.shouldShowVoiceCommandTip(commandsEnabled: true))
    }

    func testItIsNeverShownTwice() {
        tips.markVoiceCommandTipSeen()
        XCTAssertFalse(tips.shouldShowVoiceCommandTip(commandsEnabled: true),
                       "a one-time hint that reappears is just noise")
    }

    func testNothingIsAdvertisedWhenTheFeatureIsOff() {
        XCTAssertFalse(tips.shouldShowVoiceCommandTip(commandsEnabled: false))
    }

    func testBeingSeenSurvivesANewInstanceOfTheReader() {
        tips.markVoiceCommandTipSeen()
        let fresh = FirstRunTips(defaults: defaults)
        XCTAssertFalse(fresh.shouldShowVoiceCommandTip(commandsEnabled: true),
                       "it must persist across launches, not just within one")
    }
}
