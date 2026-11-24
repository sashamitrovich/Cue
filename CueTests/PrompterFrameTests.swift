import XCTest
import SwiftUI
@testable import Cue

/// Where the recorded picture sits on the screen. With the camera on, the
/// speaker must see exactly the frame being recorded, centred. These use the
/// real sizes of real phones, because the failure modes (a strip that does
/// not fit, a picture off-centre, a frame computed from stale orientation)
/// only show up with real numbers.
final class PrompterFrameTests: XCTestCase {

    private func insets(top: CGFloat = 0, bottom: CGFloat = 0,
                        leading: CGFloat = 0, trailing: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    /// iPhone 15 Pro. Full size = geo.size + insets, as the view computes it.
    private func portrait15Pro(railOnLeading: Bool = false) -> PrompterFrame {
        PrompterFrame.make(fullSize: CGSize(width: 393, height: 852),
                           safeArea: insets(top: 59, bottom: 34), railOnLeading: railOnLeading)
    }

    private func landscape15Pro(railOnLeading: Bool) -> PrompterFrame {
        PrompterFrame.make(fullSize: CGSize(width: 852, height: 393),
                           safeArea: insets(bottom: 21, leading: 59, trailing: 59),
                           railOnLeading: railOnLeading)
    }

    // MARK: - Portrait

    func testPortraitPictureIsExactlyNineBySixteenAndCentred() {
        let f = portrait15Pro()
        XCTAssertEqual(f.picture.width / f.picture.height, 9.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(f.picture.width, 393, accuracy: 1e-9, "portrait fills the width")
        XCTAssertEqual(f.picture.midX, 393.0 / 2, accuracy: 1e-9)
        XCTAssertEqual(f.picture.minY, 59, accuracy: 1e-9, "starts under the Dynamic Island")
        XCTAssertFalse(f.isLandscape)
    }

    func testPortraitStripIsUnderThePictureAndAboveTheHomeIndicator() throws {
        let f = portrait15Pro()
        let strip = try XCTUnwrap(f.strip, "94 pt is spare under the picture, which is enough")
        XCTAssertEqual(strip.minY, f.picture.maxY, accuracy: 1e-9)
        XCTAssertEqual(strip.maxY, 852 - 34, accuracy: 1e-9, "excludes the bottom safe inset")
        XCTAssertEqual(strip.width, 393, accuracy: 1e-9)
        XCTAssertGreaterThan(strip.height, 0)
        XCTAssertEqual(f.safeOverlap.bottom, 0, "the picture stays clear of the home indicator")
        XCTAssertEqual(f.safeOverlap.top, 0)
    }

    func testOtherPortraitPhonesGetAStripAndAnExactPicture() throws {
        // 16e: 390x844, top 47. 17 Pro Max class: 430x932, top 59.
        for (size, top) in [(CGSize(width: 390, height: 844), CGFloat(47)),
                            (CGSize(width: 430, height: 932), CGFloat(59)),
                            (CGSize(width: 375, height: 812), CGFloat(44))] {
            let f = PrompterFrame.make(fullSize: size, safeArea: insets(top: top, bottom: 34),
                                       railOnLeading: false)
            XCTAssertNotNil(f.strip, "\(size) should have room for a strip")
            XCTAssertEqual(f.picture.width / f.picture.height, 9.0 / 16.0, accuracy: 1e-9, "\(size)")
            XCTAssertEqual(f.picture.midX, size.width / 2, accuracy: 1e-9, "\(size)")
            XCTAssertLessThanOrEqual(f.picture.maxY, f.strip!.minY + 1e-9)
        }
    }

    func testPortraitNeedsTheStripsSpecifiedMinimum() {
        // The minimum is the spec (52 pt buttons, no captions, home-indicator
        // zone), not a number to tune: a screen 89 pt short of it must fall
        // back, one 91 pt over it must not.
        let wanted = 393 * 16.0 / 9.0
        let short = PrompterFrame.make(
            fullSize: CGSize(width: 393, height: 59 + wanted + PrompterFrame.portraitMinStrip - 1),
            safeArea: insets(top: 59, bottom: 34), railOnLeading: false)
        let enough = PrompterFrame.make(
            fullSize: CGSize(width: 393, height: 59 + wanted + PrompterFrame.portraitMinStrip + 1),
            safeArea: insets(top: 59, bottom: 34), railOnLeading: false)
        XCTAssertNil(short.strip)
        XCTAssertNotNil(enough.strip)
        XCTAssertEqual(PrompterFrame.portraitMinStrip, 90)
        XCTAssertEqual(PrompterFrame.landscapeMinStrip, 72)
    }

    // MARK: - Landscape

    func testLandscapePictureIsExactlySixteenByNineAndCentred() {
        for left in [true, false] {
            let f = landscape15Pro(railOnLeading: left)
            XCTAssertEqual(f.picture.width / f.picture.height, 16.0 / 9.0, accuracy: 1e-9)
            XCTAssertEqual(f.picture.height, 393, accuracy: 1e-9)
            XCTAssertEqual(f.picture.midX, 852.0 / 2, accuracy: 1e-9)
            XCTAssertEqual(f.picture.midY, 393.0 / 2, accuracy: 1e-9)
            XCTAssertTrue(f.isLandscape)
        }
    }

    func testLandscapeStripIsOnTheRequestedEdgeAndIgnoresTheSideSafeInset() throws {
        let leading = landscape15Pro(railOnLeading: true)
        let stripL = try XCTUnwrap(leading.strip)
        XCTAssertEqual(stripL.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(stripL.maxX, leading.picture.minX, accuracy: 1e-9)
        XCTAssertTrue(leading.stripOnLeading)

        let trailing = landscape15Pro(railOnLeading: false)
        let stripT = try XCTUnwrap(trailing.strip)
        XCTAssertEqual(stripT.maxX, 852, accuracy: 1e-9)
        XCTAssertEqual(stripT.minX, trailing.picture.maxX, accuracy: 1e-9)
        XCTAssertFalse(trailing.stripOnLeading)

        // The full spare width: 76.67, more than the 72 minimum, and not
        // trimmed by the 59 pt side inset.
        XCTAssertEqual(stripL.width, (852 - 393 * 16.0 / 9.0) / 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(stripL.width, PrompterFrame.landscapeMinStrip)
        XCTAssertEqual(stripL.height, 393, accuracy: 1e-9)
        // The picture clears the side insets, so it overlaps nothing there.
        XCTAssertEqual(leading.safeOverlap.leading, 0)
        XCTAssertEqual(leading.safeOverlap.trailing, 0)
        // It reaches the bottom edge, so it does overlap the home indicator.
        XCTAssertEqual(leading.safeOverlap.bottom, 21, accuracy: 1e-9)
    }

    func testAMiniJustFitsALandscapeStrip() throws {
        // 12/13 mini, 812x375: 72.6 pt spare each side, against a minimum of 72.
        let f = PrompterFrame.make(fullSize: CGSize(width: 812, height: 375),
                                   safeArea: insets(bottom: 21, leading: 44, trailing: 44),
                                   railOnLeading: true)
        let strip = try XCTUnwrap(f.strip)
        XCTAssertEqual(strip.width, 72.6, accuracy: 0.1)
    }

    // MARK: - 16:9 phones: no room for a strip

    func testAnSEHasNoStripAndThePictureIsTheScreenWithinAPoint() {
        let portrait = PrompterFrame.make(fullSize: CGSize(width: 375, height: 667),
                                          safeArea: insets(), railOnLeading: false)
        XCTAssertNil(portrait.strip)
        XCTAssertTrue(portrait.isFallback)
        XCTAssertEqual(portrait.picture.width, 375, accuracy: 1)
        XCTAssertEqual(portrait.picture.height, 667, accuracy: 1)
        XCTAssertEqual(portrait.picture.midX, 375.0 / 2, accuracy: 1)
        XCTAssertEqual(portrait.picture.midY, 667.0 / 2, accuracy: 1)

        let landscape = PrompterFrame.make(fullSize: CGSize(width: 667, height: 375),
                                           safeArea: insets(), railOnLeading: true)
        XCTAssertNil(landscape.strip)
        XCTAssertEqual(landscape.picture.width, 667, accuracy: 1)
        XCTAssertEqual(landscape.picture.height, 375, accuracy: 1)
    }

    func testTheFallbackNeverFillsPastTheScreen() {
        // Aspect FIT, never a fill-crop: a screen taller than 9:16 and too
        // short for a strip must still end up with the exact aspect.
        let f = PrompterFrame.make(fullSize: CGSize(width: 375, height: 700),
                                   safeArea: insets(top: 20), railOnLeading: false)
        XCTAssertNil(f.strip)
        XCTAssertEqual(f.picture.width / f.picture.height, 9.0 / 16.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(f.picture.height, 700 + 1e-9)
        XCTAssertGreaterThanOrEqual(f.picture.minX, 0)
    }

    func testTheFallbackKnowsHowFarItReachesIntoTheSafeArea() {
        // The script must clear the Dynamic Island / status bar where the
        // picture is the whole screen.
        let f = PrompterFrame.make(fullSize: CGSize(width: 375, height: 667),
                                   safeArea: insets(top: 20), railOnLeading: false)
        XCTAssertEqual(f.safeOverlap.top, 20 - f.picture.minY, accuracy: 1e-9)
        XCTAssertGreaterThan(f.safeOverlap.top, 19)
    }

    // MARK: - Orientation comes from the size, nothing else

    func testLandscapenessIsDerivedFromTheSizeHandedIn() {
        // The latched `isLandscapeLayout` is written one pass late. If the
        // frame trusted it, landscape geometry would produce a portrait
        // picture 1500 pt tall. The frame has no such input: size alone.
        let landscape = landscape15Pro(railOnLeading: true)
        XCTAssertTrue(landscape.isLandscape)
        XCTAssertLessThanOrEqual(landscape.picture.height, 393 + 1e-9)
        XCTAssertLessThanOrEqual(landscape.picture.width, 852 + 1e-9)

        XCTAssertFalse(portrait15Pro(railOnLeading: true).isLandscape)
        XCTAssertFalse(portrait15Pro(railOnLeading: false).isLandscape)
    }

    func testADegenerateSizeDoesNotProduceNonsense() {
        // Before the first layout pass the geometry can be zero.
        let f = PrompterFrame.make(fullSize: .zero, safeArea: insets(), railOnLeading: false)
        XCTAssertEqual(f.picture, .zero)
        XCTAssertNil(f.strip)
    }

    // MARK: - Which devices get it

    func testOnlyPhonesUseThePictureFrame() {
        XCTAssertTrue(PrompterFrame.usesPictureFrame(idiom: .phone))
        XCTAssertFalse(PrompterFrame.usesPictureFrame(idiom: .pad))
        // Mac Catalyst reports .pad in this project; .mac is covered anyway.
        XCTAssertFalse(PrompterFrame.usesPictureFrame(idiom: .mac))
        XCTAssertFalse(PrompterFrame.usesPictureFrame(idiom: .unspecified))
    }

    func testTheNonPhoneLayoutIsTheWholeScreen() {
        let f = PrompterFrame.fullScreen(fullSize: CGSize(width: 1024, height: 768),
                                         safeArea: insets(top: 24, bottom: 20), railOnLeading: false)
        XCTAssertEqual(f.picture, CGRect(x: 0, y: 0, width: 1024, height: 768))
        XCTAssertNil(f.strip)
    }
}
