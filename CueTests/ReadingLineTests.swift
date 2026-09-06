import XCTest
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
}
