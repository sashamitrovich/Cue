import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // Mirroring is handled explicitly by the SwiftUI `.scaleEffect(x: -1)`
        // in PrompterView, so disable the preview layer's own automatic
        // front-camera mirroring to avoid a double-flip.
        if let connection = view.videoPreviewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        view.startTrackingOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        #if DEBUG
        RenderCost.previewUpdate()
        #endif
    }
}

final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private var orientationObserver: NSObjectProtocol?

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

    private func applyCurrentOrientation() {
        guard let orientation = AVCaptureVideoOrientation.matching(UIDevice.current.orientation),
              let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }
}
