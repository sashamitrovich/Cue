import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Shown whole inside its frame (`.resizeAspect`) rather than filling it.
    /// The picture frame uses this: if the preview's aspect ever differs from
    /// the frame's, the mismatch shows as black bars instead of a silent
    /// crop. The legacy full-bleed layout keeps fill.
    var aspectFit = false
    /// `CameraController.inputGeneration`, which changes whenever the session's
    /// video input has been swapped. A swap gives the preview layer a brand
    /// new connection with its settings back at their defaults, so the layer
    /// has to be put back in order; see `PreviewUIView.applyConnectionSettings()`.
    var inputGeneration: Int = 0

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.inputGeneration = inputGeneration
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        // Mirroring is handled explicitly by the SwiftUI `.scaleEffect(x:)`
        // in PrompterView, so the layer's own automatic front-camera mirroring
        // is switched off — here, and again after every input change, since a
        // new input brings a new connection with the defaults back on.
        view.applyConnectionSettings()
        view.startTrackingOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        let gravity: AVLayerVideoGravity = aspectFit ? .resizeAspect : .resizeAspectFill
        if uiView.videoPreviewLayer.videoGravity != gravity {
            uiView.videoPreviewLayer.videoGravity = gravity
        }
        // Always, and cheaply: the connection may have been replaced since the
        // last update (or not have existed yet when `makeUIView` ran), and
        // this is where that is noticed.
        uiView.inputGeneration = inputGeneration
        uiView.applyConnectionSettings()
        #if DEBUG
        RenderCost.previewUpdate()
        #endif
    }
}

final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    /// The `CameraController.inputGeneration` this view has been handed.
    var inputGeneration: Int = 0

    private var orientationObserver: NSObjectProtocol?
    /// The generation `applyConnectionSettings()` last ran against. A change
    /// means the session built a new preview connection, whose settings are
    /// unknown even where they happen to read the same.
    private var appliedInputGeneration: Int?
    /// Whether that run actually found a connection and configured it. Until
    /// one has, `updateUIView` keeps retrying — the connection does not exist
    /// yet when `makeUIView` first asks.
    private var hasConfiguredConnection = false
    /// The last device orientation that actually answered "which way is up",
    /// kept so a camera switch can re-derive the preview orientation even when
    /// the phone is momentarily face-up, face-down or unknown.
    private var lastDeviceOrientation: UIDeviceOrientation?

    #if DEBUG
    /// The expensive one if it fires at the scroll rate: this resets the
    /// capture preview layer's geometry, and doing that sixty times a second
    /// underneath a running session is a far better candidate for dropped
    /// frames than redrawing text is.
    override func layoutSubviews() {
        super.layoutSubviews()
        RenderCost.previewLayout()
    }
    #endif

    func startTrackingOrientation() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyCurrentOrientation()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentOrientation()
        }
    }

    /// Puts the preview connection back into the state the app expects:
    /// automatic mirroring off, mirroring off, and the layer oriented the way
    /// the device is held.
    ///
    /// Idempotent, and it has to be: swapping the video input makes
    /// `AVCaptureSession` create a *new* connection for the layer with both
    /// settings back at their defaults, so doing this once in `makeUIView` is
    /// not enough. But it runs on every `updateUIView`, and every connection
    /// and `UIDevice` read costs, so once the current generation has been
    /// applied to a connection that existed there is nothing left to do: the
    /// early return skips the reads entirely. A generation change always
    /// re-applies, and while no connection has been found yet every call
    /// retries.
    ///
    /// Order matters. Setting `isVideoMirrored` while
    /// `automaticallyAdjustsVideoMirroring` is still true raises an
    /// uncatchable Objective-C exception, and setting it where mirroring is
    /// unsupported raises too — so automatic adjustment goes off first, and
    /// the mirror write is gated on support.
    func applyConnectionSettings() {
        if appliedInputGeneration == inputGeneration, hasConfiguredConnection { return }
        guard let connection = videoPreviewLayer.connection else { return }
        let generationChanged = inputGeneration != appliedInputGeneration
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoMirroringSupported, connection.isVideoMirrored {
            connection.isVideoMirrored = false
        }
        // A new connection is new state, so re-apply the orientation even if
        // the last value we set still matches what the layer reports.
        applyCurrentOrientation(force: generationChanged)
        appliedInputGeneration = inputGeneration
        hasConfiguredConnection = true
    }

    private func applyCurrentOrientation(force: Bool = false) {
        let deviceOrientation = UIDevice.current.orientation
        if AVCaptureVideoOrientation.isDeterminate(deviceOrientation) {
            lastDeviceOrientation = deviceOrientation
        }
        guard let orientation = AVCaptureVideoOrientation.matching(lastDeviceOrientation ?? deviceOrientation),
              let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        if force || connection.videoOrientation != orientation {
            connection.videoOrientation = orientation
        }
    }

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }
}
