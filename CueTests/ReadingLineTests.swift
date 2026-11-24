import XCTest
import SwiftUI
@testable import Cue

/// The reading line's position, which is the setting users complained was
/// lying to them: the slider offered values the line could not take.
final class ReadingLineTests: XCTestCase {

    // A 17 Pro in portrait: 874pt of screen, a 59pt safe area for the
    // Dynamic Island, 34pt for the home indicator.
    private let fullHeight: CGFloat = 967
    private let topInset: CGFloat = 59
    private let fontSize: CGFloat = 32

    /// The home indicator, and nothing else — the reading line is allowed to
    /// run behind the bottom chrome. See `testTheLineMayRunBehindTheBottomChrome`.
    private let bottomInset: CGFloat = 34

    private func y(_ fraction: Double) -> CGFloat {
        PrompterView.cueY(fraction: fraction, fullHeight: fullHeight,
                          topInset: topInset, bottomInset: bottomInset, fontSize: fontSize)
    }

    func testZeroPutsTheLineAsHighAsItCanPhysicallyGo() {
        // Clear of the safe area, plus enough for the word centred on the
        // line not to be clipped by the Dynamic Island.
        XCTAssertEqual(y(0), topInset + fontSize * 0.75, accuracy: 0.001)
    }

    func testEveryStepOfTheSliderMovesTheLine() {
        // The bug this replaced: the setting was a fraction of the *screen*,
        // so everything below the safe area produced the same position and
        // the top of the slider's travel did nothing at all. On a 17 Pro that
        // was the first 8.6% of it.
        var previous = y(0)
        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
            let current = y(step)
            XCTAssertGreaterThan(current, previous, "nothing moved between \(step - 0.05) and \(step)")
            previous = current
        }
    }

    func testTheSameNumberMeansTheSameThingOnEveryDevice() {
        // Halfway down the band is halfway down the band, whether or not the
        // phone has a Dynamic Island — which a fraction of screen height
        // could never promise.
        let island = PrompterView.cueY(fraction: 0.5, fullHeight: fullHeight, topInset: 59, bottomInset: bottomInset, fontSize: fontSize)
        let noIsland = PrompterView.cueY(fraction: 0.5, fullHeight: fullHeight, topInset: 20, bottomInset: bottomInset, fontSize: fontSize)
        let islandBand = island - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 59, bottomInset: bottomInset, fontSize: fontSize)
        let plainBand = noIsland - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 20, bottomInset: bottomInset, fontSize: fontSize)
        let islandFull = PrompterView.cueY(fraction: 1, fullHeight: fullHeight, topInset: 59, bottomInset: bottomInset, fontSize: fontSize)
            - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 59, bottomInset: bottomInset, fontSize: fontSize)
        let plainFull = PrompterView.cueY(fraction: 1, fullHeight: fullHeight, topInset: 20, bottomInset: bottomInset, fontSize: fontSize)
            - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 20, bottomInset: bottomInset, fontSize: fontSize)
        XCTAssertEqual(islandBand / islandFull, 0.5, accuracy: 0.001)
        XCTAssertEqual(plainBand / plainFull, 0.5, accuracy: 0.001)
    }

    func testLargerTypeNeedsMoreClearance() {
        // The word is centred on the line, so a bigger script has to start
        // lower or the Dynamic Island clips it.
        XCTAssertGreaterThan(
            PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: topInset, bottomInset: bottomInset, fontSize: 64),
            PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: topInset, bottomInset: bottomInset, fontSize: 20)
        )
    }

    func testDraggingAndTheSettingAgree() {
        // Dragging the line puts it under the finger, and the setting that
        // results puts it back in the same place.
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let position = y(fraction)
            let round = PrompterView.cueFraction(
                y: position, fullHeight: fullHeight, topInset: topInset,
                bottomInset: bottomInset, fontSize: fontSize)
            XCTAssertEqual(round, fraction, accuracy: 0.001)
        }
    }

    func testDragsBeyondTheBandAreClamped() {
        XCTAssertEqual(PrompterView.cueFraction(y: -400, fullHeight: fullHeight, topInset: topInset, bottomInset: bottomInset, fontSize: fontSize), 0)
        XCTAssertEqual(PrompterView.cueFraction(y: 9999, fullHeight: fullHeight, topInset: topInset, bottomInset: bottomInset, fontSize: fontSize), 1)
    }

    func testADegenerateLayoutCannotProduceANonsensePosition() {
        // Before the first layout pass there is no height to work from.
        let collapsed = PrompterView.cueY(fraction: 0.5, fullHeight: 0, topInset: 0, bottomInset: 0, fontSize: fontSize)
        XCTAssertEqual(collapsed, fontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(PrompterView.cueFraction(y: 10, fullHeight: 0, topInset: 0, bottomInset: 0, fontSize: fontSize), 0)
    }

    func testChromeAboveTheLineRaisesItsHighestPosition() {
        // Landscape docks the status bar at the true top, so the line's
        // highest position has to start below it — not merely below the safe
        // area. This is what the old 0.34 landscape floor was guarding, and
        // dropping that floor without replacing the guard scrolled the script
        // behind the bar at 0%.
        let portrait = PrompterView.cueY(
            fraction: 0, fullHeight: fullHeight, topInset: topInset,
            bottomInset: bottomInset, fontSize: fontSize)
        let landscape = PrompterView.cueY(
            fraction: 0, fullHeight: fullHeight, topInset: topInset + 48,
            bottomInset: bottomInset, fontSize: fontSize)
        XCTAssertEqual(landscape - portrait, 48, accuracy: 0.001)
    }

    func testTheBandNarrowsRatherThanInvertingWhenChromeIsDeep() {
        // A short landscape screen with timing shown: the top chrome can eat
        // most of the height. The band must collapse to a point rather than
        // run backwards, or 0% would sit below 100%.
        let squashed = PrompterView.cueY(fraction: 0, fullHeight: 200, topInset: 190, bottomInset: 0, fontSize: fontSize)
        let squashedEnd = PrompterView.cueY(fraction: 1, fullHeight: 200, topInset: 190, bottomInset: 0, fontSize: fontSize)
        XCTAssertEqual(squashed, squashedEnd, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(squashedEnd, squashed)
    }

    // MARK: - What the line has to clear

    // These are the tests that were missing. `cueY` was covered, but nothing
    // checked what the view *fed* it, and that is where the landscape bug
    // was: at 0% the script scrolled behind the landscape status bar.

    func testPortraitOnlyHasToClearTheSafeArea() {
        XCTAssertEqual(
            PrompterView.readingLineTopInset(safeAreaTop: 59, isLandscape: false, showsTiming: true),
            59
        )
    }

    func testLandscapeAlsoHasToClearTheBarDockedAtTheTop() {
        // Landscape docks the status bar at the true top. Clearing only the
        // safe area there puts the reading line behind it — which is what the
        // old 0.34 landscape floor had been quietly guarding against, and what
        // removing that floor reintroduced.
        XCTAssertEqual(
            PrompterView.readingLineTopInset(safeAreaTop: 0, isLandscape: true, showsTiming: false),
            PrompterView.landscapeBarHeight
        )
    }

    func testShowingTimingMakesTheLandscapeBarTallerAndTheLineLower() {
        let without = PrompterView.readingLineTopInset(safeAreaTop: 0, isLandscape: true, showsTiming: false)
        let with = PrompterView.readingLineTopInset(safeAreaTop: 0, isLandscape: true, showsTiming: true)
        XCTAssertGreaterThan(with, without, "the timing row adds a line to the bar")
        XCTAssertEqual(with, PrompterView.landscapeBarHeightWithTiming)
    }

    func testTheHighestLineInLandscapeSitsBelowTheBarAndItsOwnType() {
        // End to end, the way the view composes it: nothing of the active
        // word may overlap the bar.
        let top = PrompterView.readingLineTopInset(safeAreaTop: 0, isLandscape: true, showsTiming: true)
        let highest = PrompterView.cueY(fraction: 0, fullHeight: 390, topInset: top, bottomInset: bottomInset, fontSize: fontSize)
        XCTAssertGreaterThan(
            highest - fontSize * 0.6, PrompterView.landscapeBarHeightWithTiming,
            "the top of the word must clear the bar, not just its centre"
        )
    }

    // MARK: - How far down the line may go

    func testTheBottomEndIsTheSafeAreaInBothOrientations() {
        // Deliberately not symmetric with the top, and the asymmetry is the
        // point: top chrome covers script not yet read, so a line underneath
        // it is unusable; bottom chrome covers script already spoken, so a
        // line behind it costs nothing.
        XCTAssertEqual(PrompterView.readingLineBottomInset(safeAreaBottom: 34), 34)
        XCTAssertEqual(PrompterView.readingLineBottomInset(safeAreaBottom: 21), 21)
    }

    func testTheLineMayRunBehindTheBottomChrome() {
        // Approved on a device after seeing it: in portrait the line passes
        // behind the control panel at the bottom of its travel. The earlier
        // rule stopped it above the panel, and stopping it there is what this
        // test exists to prevent being reinstated.
        let panelHeight: CGFloat = 134
        let lowest = PrompterView.readingLineBand(
            fullHeight: fullHeight, topInset: topInset,
            bottomInset: bottomInset, fontSize: fontSize
        ).lowest
        XCTAssertGreaterThan(
            lowest, fullHeight - bottomInset - panelHeight,
            "the line must be able to travel into the space the control panel occupies"
        )
    }

    func testTheLineStillStopsShortOfTheHomeIndicator() {
        // Full range is not the same as off the screen: the word is centred
        // on the line, so its underside still has to clear the safe area.
        let lowest = PrompterView.readingLineBand(
            fullHeight: fullHeight, topInset: topInset,
            bottomInset: bottomInset, fontSize: fontSize
        ).lowest
        XCTAssertLessThanOrEqual(lowest + fontSize * 0.6, fullHeight - bottomInset + fontSize * 0.2)
    }

    func testTheBandSpansNearlyTheWholeScreen() {
        let band = PrompterView.readingLineBand(
            fullHeight: fullHeight, topInset: topInset,
            bottomInset: bottomInset, fontSize: fontSize)
        XCTAssertGreaterThan(
            (band.lowest - band.highest) / fullHeight, 0.8,
            "the slider should reach most of the screen, not a fraction of it"
        )
    }

    func testLandscapeUsesTheWholeBandAtBothEnds() {
        // End to end in landscape: highest clears the top bar, lowest clears
        // only the home indicator, and the two are not the same place.
        let top = PrompterView.readingLineTopInset(safeAreaTop: 0, isLandscape: true, showsTiming: true)
        let bottom = PrompterView.readingLineBottomInset(safeAreaBottom: 21)
        let band = PrompterView.readingLineBand(
            fullHeight: 402, topInset: top, bottomInset: bottom, fontSize: fontSize)
        XCTAssertGreaterThan(band.lowest - band.highest, 200, "the band must span most of a landscape screen")
    }

    // MARK: - In the picture frame (phones)

    // The script's space is the recorded picture, not the screen. These feed
    // the same statics the view uses with real frames, and pin the end the
    // slider could drive the line out of the picture from.

    private func frame(_ w: CGFloat, _ h: CGFloat,
                       top: CGFloat = 0, bottom: CGFloat = 0, side: CGFloat = 0) -> PrompterFrame {
        PrompterFrame.make(
            fullSize: CGSize(width: w, height: h),
            safeArea: EdgeInsets(top: top, leading: side, bottom: bottom, trailing: side),
            railOnLeading: false)
    }

    func testTheChipRowClearanceDependsOnTheTimingRow() {
        // Landscape keeps the top row, so the timing row still costs clearance.
        let f = frame(852, 393, bottom: 21, side: 59)
        let without = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: false)
        let with = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: true)
        XCTAssertEqual(without, PrompterView.chipClearance)
        XCTAssertEqual(with, PrompterView.chipClearanceWithTiming)
        XCTAssertGreaterThan(with, without, "the timing row makes the chip taller")
        // Portrait with a strip has nothing in the top row any more.
        let portrait = frame(393, 852, top: 59, bottom: 34)
        XCTAssertEqual(PrompterView.pictureReadingLineTopInset(frame: portrait, showsTiming: false), 0)
        XCTAssertEqual(PrompterView.pictureReadingLineTopInset(frame: portrait, showsTiming: true), 0)
    }

    func testPortraitWithAStripDoesNotChargeTheTopSafeArea() {
        // The picture starts below the island and the status chip has moved to
        // the bottom, so the line may start at the picture's top edge: the
        // 59 pt island must not be charged to it a second time.
        let f = frame(393, 852, top: 59, bottom: 34)
        XCTAssertEqual(PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: false), 0)
        XCTAssertEqual(PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: true), 0)
    }

    func testTheFallbackNeverScrollsUnderTheIsland() {
        // Picture == screen: a deep cutout may exceed the chip clearance, and
        // the line must still start below it.
        let f = frame(375, 667, top: 100)
        let top = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: false)
        XCTAssertGreaterThanOrEqual(top, f.safeOverlap.top)
        XCTAssertGreaterThan(top, PrompterView.chipClearance)
    }

    func testTheBottomInsetClearsTheBottomChipInPortraitAndTheHomeIndicatorInLandscape() {
        // Portrait: the whole bottom row, so the taller chip and its padding.
        XCTAssertEqual(PrompterView.pictureReadingLineBottomInset(
            frame: frame(393, 852, top: 59, bottom: 34), showsTiming: true),
            PrompterView.statusChipHeight(showsTiming: true) + PrompterView.chipBottomPadding,
            accuracy: 1e-9)
        XCTAssertEqual(PrompterView.pictureReadingLineBottomInset(
            frame: frame(393, 852, top: 59, bottom: 34), showsTiming: false),
            PrompterView.statusChipHeight(showsTiming: false) + PrompterView.chipBottomPadding,
            accuracy: 1e-9)
        XCTAssertGreaterThan(PrompterView.statusChipHeight(showsTiming: false),
                             PrompterView.utilityChipHeight,
                             "the status chip is the taller of the two, so it sets the row")
        XCTAssertEqual(PrompterView.pictureReadingLineBottomInset(
            frame: frame(852, 393, bottom: 21, side: 59), showsTiming: true), 21, accuracy: 1e-9)
        // The fallback keeps the chip top-right, so a 16:9 portrait still
        // clears only the home indicator (which it may not even reach).
        XCTAssertEqual(PrompterView.pictureReadingLineBottomInset(
            frame: frame(375, 667, top: 20), showsTiming: true), 0, accuracy: 1e-9)
    }

    func testTheLowestLineStaysInsideThePictureInEveryCase() {
        // The line is drawn `readingLineDrop` under `cueY`. At 100% both it
        // and the row it marks must still be inside the picture, in portrait,
        // landscape, the fallback and at the largest and smallest type.
        let frames = [
            frame(393, 852, top: 59, bottom: 34),
            frame(852, 393, bottom: 21, side: 59),
            frame(375, 667, top: 20),
            frame(667, 375),
        ]
        for f in frames {
            for font: CGFloat in [20, 32, 64] {
                let top = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: true)
                let bottom = PrompterView.pictureReadingLineBottomInset(frame: f, showsTiming: true)
                let y = PrompterView.cueY(fraction: 1, fullHeight: f.picture.height,
                                          topInset: top, bottomInset: bottom, fontSize: font)
                XCTAssertGreaterThanOrEqual(y, 0, "\(f.picture) font \(font)")
                XCTAssertLessThanOrEqual(
                    y + PrompterView.readingLineDrop(fontSize: font), f.picture.height - bottom,
                    "the drawn line leaves the picture: \(f.picture) font \(font)")
            }
        }
    }

    func testTheHighestLineClearsTheChipRowInPictureSpace() {
        let f = frame(852, 393, bottom: 21, side: 59)
        let top = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: true)
        let y = PrompterView.cueY(fraction: 0, fullHeight: f.picture.height,
                                  topInset: top, bottomInset: 21, fontSize: fontSize)
        XCTAssertGreaterThan(y - fontSize * 0.6, PrompterView.chipClearanceWithTiming,
                             "the top of the word must clear the chips, not just its centre")
    }

    func testTheScriptIsCentredOnThePictureAndNotPushedByTheRail() {
        // Margins are the same on both sides, so the column is centred on
        // the picture whichever edge the strip is on. Portrait has no rail;
        // landscape clears the vertical utility chip column on both sides.
        let strip = frame(393, 852, top: 59, bottom: 34)
        XCTAssertEqual(PrompterView.pictureMargins(frame: strip).rail, 0)
        XCTAssertEqual(PrompterView.pictureMargins(frame: strip).safeArea, 0)

        let landscape = frame(852, 393, bottom: 21, side: 59)
        XCTAssertEqual(PrompterView.pictureMargins(frame: landscape).rail,
                       PrompterView.utilityChipColumnWidth,
                       "the vertical utility chip must be cleared on both sides, symmetric")
        XCTAssertEqual(PrompterView.pictureMargins(frame: landscape).safeArea, 0,
                       "59 pt side inset is inside the black, not the picture")

        let fallbackLandscape = PrompterFrame.make(
            fullSize: CGSize(width: 667, height: 375),
            safeArea: EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10), railOnLeading: true)
        XCTAssertEqual(PrompterView.pictureMargins(frame: fallbackLandscape).rail, PrompterView.railWidth)
        XCTAssertGreaterThan(PrompterView.pictureMargins(frame: fallbackLandscape).safeArea, 0)
    }

    // MARK: - Utility chip placement (phones)

    func testUtilityChipSitsAtTheBottomTrailingInPortraitWithAStrip() throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)] {
            let f = PrompterFrame.make(
                fullSize: size,
                safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
                railOnLeading: false)
            let chip = try XCTUnwrap(PrompterView.utilityChipRect(frame: f), "\(size)")
            XCTAssertTrue(chip.minX >= 0 && chip.maxX <= f.picture.width, "inside the picture \(size)")
            XCTAssertTrue(chip.minY >= 0 && chip.maxY <= f.picture.height, "inside the picture \(size)")
            XCTAssertEqual(chip.maxX, f.picture.width - PrompterView.chipEdgePadding, accuracy: 1e-9)
            XCTAssertEqual(chip.maxY, f.picture.height - PrompterView.chipBottomPadding, accuracy: 1e-9)
            if let strip = f.strip {
                let chipOnScreen = chip.offsetBy(dx: f.picture.minX, dy: f.picture.minY)
                XCTAssertFalse(chipOnScreen.intersects(strip), "the chip must stay out of the take-button strip")
            }
        }
    }

    func testUtilityChipStacksVerticallyOnTheEdgeOppositeTheStrip() throws {
        for railOnLeading in [true, false] {
            let f = PrompterFrame.make(
                fullSize: CGSize(width: 852, height: 393),
                safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
                railOnLeading: railOnLeading)
            let chip = try XCTUnwrap(PrompterView.utilityChipRect(frame: f), "railOnLeading \(railOnLeading)")
            XCTAssertEqual(chip.width, PrompterView.utilityChipHeight)
            XCTAssertEqual(chip.height, PrompterView.utilityChipWidth)
            XCTAssertTrue(chip.minX >= 0 && chip.maxX <= f.picture.width, "inside the picture")
            XCTAssertTrue(chip.minY >= 0 && chip.maxY <= f.picture.height, "inside the picture")
            XCTAssertEqual(chip.midY, f.picture.height / 2, accuracy: 1e-9)
            if railOnLeading {
                XCTAssertEqual(chip.maxX, f.picture.width - PrompterView.chipEdgePadding, accuracy: 1e-9)
                XCTAssertGreaterThan(chip.midX, f.picture.width / 2, "chip must be on the trailing half")
            } else {
                XCTAssertEqual(chip.minX, PrompterView.chipEdgePadding, accuracy: 1e-9)
                XCTAssertLessThan(chip.midX, f.picture.width / 2, "chip must be on the leading half")
            }
            if let strip = f.strip {
                let chipOnScreen = chip.offsetBy(dx: f.picture.minX, dy: f.picture.minY)
                XCTAssertFalse(chipOnScreen.intersects(strip), "the chip must not sit in the black strip")
            }
        }
    }

    func testUtilityChipKeepsTheLegacyTopRightInTheFallback() {
        let f = PrompterFrame.make(
            fullSize: CGSize(width: 375, height: 667),
            safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0),
            railOnLeading: false)
        XCTAssertNil(PrompterView.utilityChipRect(frame: f),
                     "the fallback keeps the chip in the top row, so no bottom/side rect is computed")
    }

    // MARK: - Status chip placement (phones)

    // The owner asked for the "timer" to come down when the phone is upright,
    // so in portrait the status chip shares the utility chip's bottom row.
    // These use the real devices' geometry, and pin the pure function the view
    // places the chip with.

    func testStatusChipSharesTheBottomRowInPortraitWithAStrip() throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)] {
            let f = PrompterFrame.make(
                fullSize: size,
                safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
                railOnLeading: false)
            XCTAssertFalse(f.isFallback, "a modern phone has room for the strip: \(size)")
            let utility = try XCTUnwrap(PrompterView.utilityChipRect(frame: f), "\(size)")
            for showsTiming in [false, true] {
                let chip = PrompterView.statusChipRect(frame: f, showsTiming: showsTiming)
                let what = "\(size) showsTiming \(showsTiming)"
                XCTAssertTrue(chip.minX >= 0 && chip.maxX <= f.picture.width, "inside the picture (\(what))")
                XCTAssertTrue(chip.minY >= 0 && chip.maxY <= f.picture.height, "inside the picture (\(what))")
                XCTAssertGreaterThan(chip.midY, f.picture.height / 2, "in the bottom half (\(what))")
                XCTAssertEqual(chip.height, PrompterView.statusChipHeight(showsTiming: showsTiming), accuracy: 1e-9)
                XCTAssertEqual(chip.minX, PrompterView.chipEdgePadding, accuracy: 1e-9,
                               "leading edge (\(what))")
                XCTAssertEqual(chip.maxY, utility.maxY, accuracy: 1e-9,
                               "bottom-aligned with the utility chip (\(what))")
                XCTAssertFalse(chip.intersects(utility), "must not overlap the utility chip (\(what))")
                XCTAssertLessThanOrEqual(chip.maxY, f.picture.height - PrompterView.tickLength,
                                         "the bottom tick must stay visible (\(what))")
                // The old top row's width rule: the cap, or as much room as
                // the utility chip leaves. 205pt on 393, 210 on 430.
                XCTAssertEqual(chip.width,
                               min(PrompterView.statusChipMaxWidth,
                                   f.picture.width - 2 * PrompterView.chipEdgePadding
                                       - PrompterView.utilityChipWidth - 8),
                               accuracy: 1e-9, "width (\(what))")
            }
        }
    }

    func testStatusChipKeepsTheTopLeftInLandscape() {
        for railOnLeading in [true, false] {
            let f = PrompterFrame.make(
                fullSize: CGSize(width: 852, height: 393),
                safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
                railOnLeading: railOnLeading)
            let chip = PrompterView.statusChipRect(frame: f, showsTiming: true)
            let what = "railOnLeading \(railOnLeading)"
            XCTAssertEqual(chip.minX, PrompterView.chipEdgePadding, accuracy: 1e-9, "top-left (\(what))")
            XCTAssertEqual(chip.minY, PrompterView.chipTopPadding, accuracy: 1e-9, "top-left (\(what))")
            XCTAssertLessThan(chip.midY, f.picture.height / 2, "upper part of the picture (\(what))")
            XCTAssertEqual(chip.width, PrompterView.statusChipMaxWidth, accuracy: 1e-9, "width (\(what))")
            XCTAssertLessThanOrEqual(chip.maxY, PrompterView.chipClearanceWithTiming + 1e-9,
                                     "the chip row ends at chipClearance (\(what))")
        }
    }

    func testStatusChipKeepsTheTopLeftInTheFallbackAndLeavesTheUtilityChipItsCorner() {
        let f = frame(375, 667, top: 20)
        let chip = PrompterView.statusChipRect(frame: f, showsTiming: true)
        XCTAssertEqual(chip.minX, PrompterView.chipEdgePadding, accuracy: 1e-9)
        XCTAssertEqual(chip.minY, PrompterView.chipTopPadding + f.safeOverlap.top, accuracy: 1e-9,
                       "below the safe-area top, since the picture is the screen")
        XCTAssertLessThan(chip.midY, f.picture.height / 2, "upper part of the picture")
        XCTAssertLessThanOrEqual(
            chip.maxX,
            f.picture.width - PrompterView.chipEdgePadding - PrompterView.utilityChipWidth - 8 + 1e-9,
            "the utility chip keeps the fallback's top-right corner")
    }

    func testTheLowestLineClearsTheBottomChipInPortrait() {
        let f = frame(393, 852, top: 59, bottom: 34)
        let chip = PrompterView.utilityChipRect(frame: f)!
        let bottom = PrompterView.pictureReadingLineBottomInset(frame: f, showsTiming: true)
        let top = PrompterView.pictureReadingLineTopInset(frame: f, showsTiming: true)
        let lowest = PrompterView.readingLineBand(
            fullHeight: f.picture.height, topInset: top, bottomInset: bottom, fontSize: 32).lowest
        XCTAssertLessThanOrEqual(
            lowest + PrompterView.readingLineDrop(fontSize: 32), chip.minY + 0.5,
            "the reading line at 100% must sit above the bottom chip")
        // The status chip is the taller of the two, so it is what the inset
        // is really sized against.
        let statusChip = PrompterView.statusChipRect(frame: f, showsTiming: true)
        XCTAssertLessThanOrEqual(statusChip.minY, chip.minY,
                                 "the status chip is the taller one, so its top reaches higher in the row")
        XCTAssertLessThanOrEqual(
            lowest + PrompterView.readingLineDrop(fontSize: 32), statusChip.minY + 0.5,
            "the reading line at 100% must sit above the taller status chip too")
    }

    func testTheMarginsClearTheVerticalChipInLandscape() throws {
        for railOnLeading in [true, false] {
            let f = PrompterFrame.make(
                fullSize: CGSize(width: 852, height: 393),
                safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
                railOnLeading: railOnLeading)
            let chip = try XCTUnwrap(PrompterView.utilityChipRect(frame: f))
            let margins = PrompterView.pictureMargins(frame: f)
            XCTAssertEqual(margins.rail, PrompterView.utilityChipColumnWidth)
            XCTAssertEqual(margins.safeArea, 0)
            let inset = ScriptMargins.inset(
                safeArea: margins.safeArea, margin: 0, rail: margins.rail,
                width: f.picture.width, fontSize: 32)
            if railOnLeading {
                // Strip leading -> chip trailing: the column's trailing edge
                // must not reach the chip.
                XCTAssertLessThanOrEqual(f.picture.width - inset, chip.minX + 0.5)
            } else {
                // Strip trailing -> chip leading: the column's leading edge
                // must start past the chip.
                XCTAssertGreaterThanOrEqual(inset, chip.maxX - 0.5)
            }
        }
    }
}
