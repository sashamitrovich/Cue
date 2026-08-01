import Foundation
import AVFoundation
import CoreMedia
import Photos
import UIKit

/// What the connected device's front camera supports, detected at runtime.
/// The controls sheet only shows a row when the matching flag/list is non-empty.
struct CameraCapabilities {
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 1
    /// Size tiers (HD / 4K) with the frame rates each one offers.
    var qualityTiers: [QualityTier] = []
    var supportsHDR: Bool = false
    var supportsStabilization: Bool = false
    var supportsLowLightBoost: Bool = false
}

/// Drives the front camera + mic capture session and records takes to a temp
/// file, then saves each finished take into the user's Photos library.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var cameraDevice: AVCaptureDevice?

    @Published var isRunning = false
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var recordingSeconds: Int = 0

    @Published var capabilities = CameraCapabilities()
    @Published var zoomFactor: CGFloat = 1
    @Published var selectedMode: VideoMode?
    @Published var hdrEnabled = false
    @Published var stabilizationEnabled = true
    @Published var lowLightBoostEnabled = true

    /// The widest-field-of-view format backing each offered mode, so switching
    /// quality never quietly narrows the framing (see `setup`).
    private var formatsByMode: [VideoMode: AVCaptureDevice.Format] = [:]

    private var timer: Timer?
    private var orientationObserver: NSObjectProtocol?

    var selectedTier: QualityTier? {
        guard let selectedMode else { return nil }
        return CaptureQualityMenu.tier(for: selectedMode, in: capabilities.qualityTiers)
    }

    func configureAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { videoOK in
            AVCaptureDevice.requestAccess(for: .audio) { audioOK in
                DispatchQueue.main.async {
                    guard videoOK, audioOK else {
                        self.errorMessage = "Camera and microphone access are required to record."
                        return
                    }
                    self.setup()
                }
            }
        }
    }

    private func setup() {
        session.beginConfiguration()
        // .inputPriority (rather than a fixed preset like .high) is required
        // for `device.activeFormat` to actually take effect below, since the
        // resolution/frame-rate picker sets it explicitly per device.
        session.sessionPreset = .inputPriority

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let camInput = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(camInput) {
            session.addInput(camInput)
            cameraDevice = camera
            // AVFoundation's default front-camera format has a noticeably
            // narrower field of view than what Camera.app shows — the wide
            // framing has to be opted into by picking the format with the
            // largest FOV explicitly, otherwise the preview looks zoomed in.
            let wideFormat = camera.formats
                .filter { CMVideoFormatDescriptionGetDimensions($0.formatDescription).height >= 1080 }
                .max { $0.videoFieldOfView < $1.videoFieldOfView }
            do {
                try camera.lockForConfiguration()
                if let wideFormat {
                    camera.activeFormat = wideFormat
                }
                camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
                camera.unlockForConfiguration()
            } catch {
                // Non-fatal — framing stays at whatever the hardware defaulted to.
            }
        }
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        // The preview layer already auto-mirrors the front camera for a
        // selfie-view look; the SwiftUI layer also flips for mirror mode.
        // Keep the *recorded* file unmirrored (reads naturally, like Camera.app)
        // regardless of how the live preview is flipped.
        if let connection = movieOutput.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()

        if let camera = cameraDevice {
            detectCapabilities(for: camera)
        }

        startTrackingOrientation()

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    /// Inspects the connected device's actual formats to build the zoom range
    /// and the HD/4K quality menu — different iPhone models expose very
    /// different sets here (e.g. a 4K60 front camera on newer Pro models vs
    /// 1080p30 on older ones).
    private func detectCapabilities(for device: AVCaptureDevice) {
        var caps = CameraCapabilities()
        caps.minZoom = device.minAvailableVideoZoomFactor
        caps.maxZoom = device.maxAvailableVideoZoomFactor
        caps.supportsLowLightBoost = device.isLowLightBoostSupported

        var formats: [VideoMode: AVCaptureDevice.Format] = [:]
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.height >= 720 else { continue }
            if format.isVideoHDRSupported { caps.supportsHDR = true }

            for rate in CaptureQualityMenu.offeredFrameRates
            where format.videoSupportedFrameRateRanges.contains(
                where: { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }
            ) {
                let mode = VideoMode(height: dims.height, frameRate: rate)
                // Same rule as initial setup: among formats that can serve a
                // mode, keep the widest field of view, so changing quality
                // never crops the framing in.
                if let existing = formats[mode], existing.videoFieldOfView >= format.videoFieldOfView {
                    continue
                }
                formats[mode] = format
            }
        }
        caps.qualityTiers = CaptureQualityMenu.tiers(from: Array(formats.keys))

        if let connection = movieOutput.connection(with: .video) {
            caps.supportsStabilization = connection.isVideoStabilizationSupported
        }

        // Report the mode the session is already running, rather than applying
        // one — `setup` picked the widest-FOV format deliberately and
        // reconfiguring here would undo that before the preview even appears.
        let activeHeight = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription).height
        let activeRate = device.activeVideoMinFrameDuration.seconds > 0
            ? 1 / device.activeVideoMinFrameDuration.seconds
            : 30
        let tiers = caps.qualityTiers
        let current = tiers.first { $0.height == activeHeight }
            .flatMap { CaptureQualityMenu.mode(in: $0, preferringFrameRate: activeRate) }
            ?? tiers.last.flatMap { CaptureQualityMenu.mode(in: $0, preferringFrameRate: 30) }

        DispatchQueue.main.async {
            self.capabilities = caps
            self.formatsByMode = formats
            self.zoomFactor = device.videoZoomFactor
            self.selectedMode = current
            if caps.supportsStabilization { self.setStabilization(true) }
            if caps.supportsLowLightBoost { self.setLowLightBoost(true) }
        }
    }

    /// Digital zoom, clamped to this device's actual reported range (front
    /// cameras rarely go far past 1x — older models may not zoom at all).
    func setZoom(_ factor: CGFloat) {
        guard let device = cameraDevice else { return }
        let clamped = min(max(factor, capabilities.minZoom), capabilities.maxZoom)
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clamped, withRate: 12)
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            errorMessage = "Couldn't set zoom: \(error.localizedDescription)"
        }
    }

    /// Switches size tier (HD ⇄ 4K), keeping the current frame rate where the
    /// new tier supports it.
    func selectTier(_ tier: QualityTier) {
        guard let mode = CaptureQualityMenu.mode(in: tier, preferringFrameRate: selectedMode?.frameRate) else { return }
        apply(mode)
    }

    /// Cycles the frame rate within the current size tier.
    func cycleFrameRate() {
        guard let current = selectedMode, let tier = selectedTier,
              let next = CaptureQualityMenu.nextFrameRate(after: current.frameRate, in: tier) else { return }
        apply(VideoMode(height: tier.height, frameRate: next))
    }

    func apply(_ mode: VideoMode) {
        guard let device = cameraDevice, let format = formatsByMode[mode] else { return }
        // Reconfiguring the device mid-recording would tear down the file
        // being written; Camera.app hides the control while recording for the
        // same reason.
        guard !isRecording else { return }
        do {
            try device.lockForConfiguration()
            session.beginConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(mode.frameRate.rounded()))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            if capabilities.supportsHDR {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = hdrEnabled
            }
            session.commitConfiguration()
            device.unlockForConfiguration()
            selectedMode = mode
            // Zoom is expressed relative to the active format, so re-clamp it
            // rather than leaving a now-out-of-range factor behind.
            zoomFactor = device.videoZoomFactor
        } catch {
            errorMessage = "Couldn't change quality: \(error.localizedDescription)"
        }
    }

    func setHDR(_ enabled: Bool) {
        guard let device = cameraDevice, capabilities.supportsHDR else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = enabled
            device.unlockForConfiguration()
            hdrEnabled = enabled
        } catch {
            errorMessage = "Couldn't change HDR: \(error.localizedDescription)"
        }
    }

    func setStabilization(_ enabled: Bool) {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoStabilizationSupported else { return }
        connection.preferredVideoStabilizationMode = enabled ? .auto : .off
        stabilizationEnabled = enabled
    }

    func setLowLightBoost(_ enabled: Bool) {
        guard let device = cameraDevice, device.isLowLightBoostSupported else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyEnablesLowLightBoostWhenAvailable = enabled
            device.unlockForConfiguration()
            lowLightBoostEnabled = enabled
        } catch {
            errorMessage = "Couldn't change low-light boost: \(error.localizedDescription)"
        }
    }

    /// Keeps the recorded file's orientation matching the device's physical
    /// rotation. `AVCaptureMovieFileOutput`'s connection doesn't follow
    /// SwiftUI's interface rotation automatically — it has to be set explicitly.
    private func startTrackingOrientation() {
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
              let connection = movieOutput.connection(with: .video),
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }

    func stop() {
        if isRecording { stopRecording() }
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
        }
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
        isRunning = false
    }

    func startRecording() {
        guard isRunning, !isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        recordingSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingSeconds += 1
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        timer?.invalidate()
        timer = nil
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isRecording = false
        if let error = error {
            errorMessage = "Recording error: \(error.localizedDescription)"
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.errorMessage = "Enable Photos access to save your take (it's still on disk as \(outputFileURL.lastPathComponent))."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if !success {
                        self.errorMessage = "Couldn't save to Photos: \(error?.localizedDescription ?? "unknown error")"
                    }
                }
            }
        }
    }
}
