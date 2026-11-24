import XCTest
import AVFoundation
import CoreMedia
@testable import Cue

/// Pure camera-position logic: the preview-mirroring rule, the saved-position
/// fallback, the widest-16:9-format choice, and the orientation mapping. None
/// of these touch a camera, so they run on the simulator and CI.
final class CameraPositionTests: XCTestCase {

    // MARK: - Preview mirroring

    func testFrontCameraPreviewIsMirrored() {
        XCTAssertTrue(CameraPosition.front.previewIsMirrored)
    }

    func testBackCameraPreviewIsNotMirrored() {
        XCTAssertFalse(CameraPosition.back.previewIsMirrored)
    }

    // MARK: - Saved-position fallback

    func testBackPositionFallsBackToFrontWithoutABackCamera() {
        XCTAssertEqual(
            CameraPosition.resolvedPosition(requested: .back, hasBackCamera: false),
            .front
        )
    }

    func testBackPositionIsHonouredWithABackCamera() {
        XCTAssertEqual(
            CameraPosition.resolvedPosition(requested: .back, hasBackCamera: true),
            .back
        )
    }

    func testFrontPositionIsUnchangedEitherWay() {
        XCTAssertEqual(CameraPosition.resolvedPosition(requested: .front, hasBackCamera: false), .front)
        XCTAssertEqual(CameraPosition.resolvedPosition(requested: .front, hasBackCamera: true), .front)
    }

    // MARK: - Flipping

    func testFrontFlipsToBack() {
        XCTAssertEqual(CameraPosition.front.other, .back)
    }

    func testBackFlipsToFront() {
        XCTAssertEqual(CameraPosition.back.other, .front)
    }

    func testFlippingTwiceReturnsToTheSameCamera() {
        for position in CameraPosition.allCases {
            XCTAssertEqual(position.other.other, position)
        }
    }

    // MARK: - Widest 16:9 format choice

    func testPreferredDimensionsPicksWidestWidescreenFormat() {
        let dims = [
            (CMVideoDimensions(width: 1920, height: 1080), Float(60)),
            (CMVideoDimensions(width: 3840, height: 2160), Float(70)),
            // 4:3 stills-shaped, widest FOV of all — must be filtered out.
            (CMVideoDimensions(width: 3088, height: 2320), Float(80)),
        ]
        let chosen = CameraController.preferredDimensions(from: dims)
        XCTAssertEqual(chosen?.width, 3840)
        XCTAssertEqual(chosen?.height, 2160)
    }

    func testPreferredDimensionsRejectsStillsAndSub1080Formats() {
        let dims = [
            (CMVideoDimensions(width: 3088, height: 2320), Float(90)), // 4:3
            (CMVideoDimensions(width: 1920, height: 1440), Float(85)), // 4:3
            (CMVideoDimensions(width: 1280, height: 720), Float(75)),  // below 1080 lines
        ]
        XCTAssertNil(CameraController.preferredDimensions(from: dims))
    }

    /// A 16:9 format at an unrecognised height can carry the widest FOV, but
    /// no quality tier can name it — so choosing it would leave the pills
    /// describing a size the session is not running.
    func testPreferredDimensionsIgnoresWidescreenFormatsAtUnrecognisedHeights() {
        let dims = [
            (CMVideoDimensions(width: 3840, height: 2160), Float(70)),
            (CMVideoDimensions(width: 4032, height: 2268), Float(80)),
        ]
        let chosen = CameraController.preferredDimensions(from: dims)
        XCTAssertEqual(chosen?.width, 3840)
        XCTAssertEqual(chosen?.height, 2160)
    }

    func testPreferredDimensionsNeverPicksA4x3StillsFormat() {
        let dims = [
            (CMVideoDimensions(width: 3088, height: 2320), Float(90)),
            (CMVideoDimensions(width: 1920, height: 1080), Float(60)),
        ]
        let chosen = CameraController.preferredDimensions(from: dims)
        XCTAssertEqual(chosen?.width, 1920)
        XCTAssertEqual(chosen?.height, 1080)
    }

    func testPreferredDimensionsPicks1080WhenItHasTheWidestFieldOfView() {
        let dims = [
            (CMVideoDimensions(width: 3840, height: 2160), Float(60)),
            (CMVideoDimensions(width: 1920, height: 1080), Float(70)),
        ]
        let chosen = CameraController.preferredDimensions(from: dims)
        XCTAssertEqual(chosen?.width, 1920)
        XCTAssertEqual(chosen?.height, 1080)
    }

    func testPreferredDimensionsIsNilWithoutCandidates() {
        let dims: [(CMVideoDimensions, Float)] = []
        XCTAssertNil(CameraController.preferredDimensions(from: dims))
    }

    // MARK: - Orientation mapping

    func testLandscapeOrientationIsSwapped() {
        XCTAssertEqual(AVCaptureVideoOrientation.matching(.landscapeLeft), .landscapeRight)
        XCTAssertEqual(AVCaptureVideoOrientation.matching(.landscapeRight), .landscapeLeft)
    }

    func testPortraitOrientationIsUnchanged() {
        XCTAssertEqual(AVCaptureVideoOrientation.matching(.portrait), .portrait)
        XCTAssertEqual(AVCaptureVideoOrientation.matching(.portraitUpsideDown), .portraitUpsideDown)
    }

    func testFaceUpFaceDownAndUnknownAreNotDeterminate() {
        XCTAssertFalse(AVCaptureVideoOrientation.isDeterminate(.faceUp))
        XCTAssertFalse(AVCaptureVideoOrientation.isDeterminate(.faceDown))
        XCTAssertFalse(AVCaptureVideoOrientation.isDeterminate(.unknown))
        XCTAssertTrue(AVCaptureVideoOrientation.isDeterminate(.portrait))
        XCTAssertTrue(AVCaptureVideoOrientation.isDeterminate(.landscapeLeft))
        XCTAssertTrue(AVCaptureVideoOrientation.isDeterminate(.landscapeRight))
    }
}
