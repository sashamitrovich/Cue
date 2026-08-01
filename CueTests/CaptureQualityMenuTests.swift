import XCTest
@testable import Cue

final class CaptureQualityMenuTests: XCTestCase {

    private let hd30 = VideoMode(height: 1080, frameRate: 30)
    private let hd60 = VideoMode(height: 1080, frameRate: 60)
    private let uhd30 = VideoMode(height: 2160, frameRate: 30)
    private let uhd60 = VideoMode(height: 2160, frameRate: 60)

    // MARK: - Labels

    func testTierLabelsFollowCameraAppVocabulary() {
        XCTAssertEqual(hd30.tierLabel, "HD")
        XCTAssertEqual(VideoMode(height: 720, frameRate: 30).tierLabel, "HD")
        XCTAssertEqual(uhd60.tierLabel, "4K")
        XCTAssertEqual(uhd60.frameRateLabel, "60")
        XCTAssertEqual(uhd60.label, "4K • 60")
    }

    // MARK: - Grouping

    func testTiersCollapseToHDAndFourK() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30, hd60, uhd30, uhd60])
        XCTAssertEqual(tiers.map(\.label), ["HD", "4K"])
        XCTAssertEqual(tiers[0].frameRates, [30, 60])
        XCTAssertEqual(tiers[1].frameRates, [30, 60])
    }

    func testOnlyTheLargestSizeInEachTierIsOffered() {
        // 720p and 1080p would both be labelled "HD" — offering both gives the
        // toggle two indistinguishable positions.
        let tiers = CaptureQualityMenu.tiers(from: [
            VideoMode(height: 720, frameRate: 30), hd30, hd60
        ])
        XCTAssertEqual(tiers.count, 1)
        XCTAssertEqual(tiers[0].height, 1080)
        XCTAssertEqual(tiers[0].frameRates, [30, 60])
    }

    func testDeviceWithOnlyHDGetsOneTier() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30])
        XCTAssertEqual(tiers.map(\.label), ["HD"])
        XCTAssertEqual(tiers[0].frameRates, [30])
    }

    func testNoModesGivesNoTiers() {
        XCTAssertTrue(CaptureQualityMenu.tiers(from: []).isEmpty)
    }

    // MARK: - Switching

    func testSwitchingTierKeepsTheCurrentFrameRate() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30, hd60, uhd30, uhd60])
        let fourK = tiers[1]
        XCTAssertEqual(
            CaptureQualityMenu.mode(in: fourK, preferringFrameRate: 60),
            uhd60
        )
    }

    func testSwitchingTierFallsBackToTheClosestAvailableRate() {
        // Common on older Pro models: 4K tops out at 30 while HD does 60.
        let tiers = CaptureQualityMenu.tiers(from: [hd30, hd60, uhd30])
        let fourK = tiers[1]
        XCTAssertEqual(
            CaptureQualityMenu.mode(in: fourK, preferringFrameRate: 60),
            uhd30
        )
    }

    func testModeWithNoPreferenceTakesTheHighestRate() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30, hd60])
        XCTAssertEqual(
            CaptureQualityMenu.mode(in: tiers[0], preferringFrameRate: nil),
            hd60
        )
    }

    func testTierLookupForAMode() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30, hd60, uhd30])
        XCTAssertEqual(CaptureQualityMenu.tier(for: hd60, in: tiers)?.label, "HD")
        XCTAssertEqual(CaptureQualityMenu.tier(for: uhd30, in: tiers)?.label, "4K")
        XCTAssertNil(CaptureQualityMenu.tier(for: VideoMode(height: 480, frameRate: 30), in: tiers))
    }

    func testTierToggleWrapsAround() {
        let tiers = CaptureQualityMenu.tiers(from: [hd30, uhd30])
        XCTAssertEqual(CaptureQualityMenu.nextTier(after: tiers[0], in: tiers), tiers[1])
        XCTAssertEqual(CaptureQualityMenu.nextTier(after: tiers[1], in: tiers), tiers[0])
        XCTAssertEqual(CaptureQualityMenu.nextTier(after: nil, in: tiers), tiers[0])
        XCTAssertNil(CaptureQualityMenu.nextTier(after: nil, in: []))
    }

    func testFrameRateToggleWrapsAround() {
        let tier = CaptureQualityMenu.tiers(from: [hd30, hd60])[0]
        XCTAssertEqual(CaptureQualityMenu.nextFrameRate(after: 30, in: tier), 60)
        XCTAssertEqual(CaptureQualityMenu.nextFrameRate(after: 60, in: tier), 30)
        // A rate the tier doesn't offer (e.g. carried over from another tier)
        // lands on its first rate rather than returning nothing.
        XCTAssertEqual(CaptureQualityMenu.nextFrameRate(after: 24, in: tier), 30)
    }
}
