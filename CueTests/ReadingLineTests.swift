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

    private func y(_ fraction: Double) -> CGFloat {
        PrompterView.cueY(fraction: fraction, fullHeight: fullHeight, topInset: topInset, fontSize: fontSize)
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
        let island = PrompterView.cueY(fraction: 0.5, fullHeight: fullHeight, topInset: 59, fontSize: fontSize)
        let noIsland = PrompterView.cueY(fraction: 0.5, fullHeight: fullHeight, topInset: 20, fontSize: fontSize)
        let islandBand = island - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 59, fontSize: fontSize)
        let plainBand = noIsland - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 20, fontSize: fontSize)
        let islandFull = PrompterView.cueY(fraction: 1, fullHeight: fullHeight, topInset: 59, fontSize: fontSize)
            - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 59, fontSize: fontSize)
        let plainFull = PrompterView.cueY(fraction: 1, fullHeight: fullHeight, topInset: 20, fontSize: fontSize)
            - PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: 20, fontSize: fontSize)
        XCTAssertEqual(islandBand / islandFull, 0.5, accuracy: 0.001)
        XCTAssertEqual(plainBand / plainFull, 0.5, accuracy: 0.001)
    }

    func testLargerTypeNeedsMoreClearance() {
        // The word is centred on the line, so a bigger script has to start
        // lower or the Dynamic Island clips it.
        XCTAssertGreaterThan(
            PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: topInset, fontSize: 64),
            PrompterView.cueY(fraction: 0, fullHeight: fullHeight, topInset: topInset, fontSize: 20)
        )
    }

    func testDraggingAndTheSettingAgree() {
        // Dragging the line puts it under the finger, and the setting that
        // results puts it back in the same place.
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let position = y(fraction)
            let round = PrompterView.cueFraction(
                y: position, fullHeight: fullHeight, topInset: topInset, fontSize: fontSize)
            XCTAssertEqual(round, fraction, accuracy: 0.001)
        }
    }

    func testDragsBeyondTheBandAreClamped() {
        XCTAssertEqual(PrompterView.cueFraction(y: -400, fullHeight: fullHeight, topInset: topInset, fontSize: fontSize), 0)
        XCTAssertEqual(PrompterView.cueFraction(y: 9999, fullHeight: fullHeight, topInset: topInset, fontSize: fontSize), 1)
    }

    func testADegenerateLayoutCannotProduceANonsensePosition() {
        // Before the first layout pass there is no height to work from.
        let collapsed = PrompterView.cueY(fraction: 0.5, fullHeight: 0, topInset: 0, fontSize: fontSize)
        XCTAssertEqual(collapsed, fontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(PrompterView.cueFraction(y: 10, fullHeight: 0, topInset: 0, fontSize: fontSize), 0)
    }
}
