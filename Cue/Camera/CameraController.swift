import Foundation
import AVFoundation
import CoreMedia
import Photos
import UIKit

/// What the connected device's camera supports, detected at runtime.
/// The controls sheet only shows a row when the matching flag/list is non-empty.
struct CameraCapabilities {
    /// Size tiers (HD / 4K) with the frame rates each one offers.
    var qualityTiers: [QualityTier] = []
    var supportsHDR: Bool = false
    var supportsStabilization: Bool = false
    var supportsLowLightBoost: Bool = false
    /// Whether both a front and a back camera exist, so the front/back row can
    /// be shown. Never true under Mac Catalyst — the Mac presents only the
    /// FaceTime camera, so there is nothing to switch to.
    var hasBothCameras: Bool = false
}

/// Drives the camera + mic capture session and records takes to a temp
/// file, then saves each finished take into the user's Photos library.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var cameraDevice: AVCaptureDevice?
    /// The live video input, retained so a switch can remove it before adding
    /// the other camera's. Previously a local in `setup`, which left nothing to
    /// remove and made a swap impossible without re-running `setup`.
    private var cameraInput: AVCaptureDeviceInput?
    #if DEBUG
    /// Why a recorded file stutters, answered rather than guessed at. iOS
    /// throttles capture under thermal pressure without telling the app in
    /// any visible way, interrupts the session for reasons worth naming, and
    /// changes the audio route underneath a running recording — all three
    /// produce "it freezes occasionally" and only one of them is a bug we
    /// could have written.
    private var pressureObservation: NSKeyValueObservation?
    private var captureDiagnostics: [NSObjectProtocol] = []
    #endif

    @Published var isRunning = false
    @Published var isRecording = false
    @Published var errorMessage: String?
    /// Which camera is currently connected to the session. Mirrors the
    /// persisted `TeleprompterState.cameraPosition` once setup/switch resolves
    /// it against the hardware actually present.
    @Published var position: CameraPosition = .front
    /// Bumped once every change to the session's video input has been
    /// committed. Swapping the input makes `AVCaptureSession` build a brand
    /// new connection for the preview layer, with automatic mirroring and the
    /// default orientation back on, so the preview re-applies its connection
    /// settings whenever this changes — see `CameraPreviewView`.
    @Published private(set) var inputGeneration = 0
    /// Set once a finished take is safely in the Photos library, so the
    /// prompter can say so. Cleared by whoever displays it.
    @Published var savedMessage: String?
    @Published var recordingSeconds: Int = 0

    @Published var capabilities = CameraCapabilities()
    @Published var selectedMode: VideoMode?
    @Published var hdrEnabled = false
    @Published var stabilizationEnabled = true
    @Published var lowLightBoostEnabled = true

    /// The widest-field-of-view format backing each offered mode, so switching
    /// quality never quietly narrows the framing (see `setup`).
    private var formatsByMode: [VideoMode: AVCaptureDevice.Format] = [:]

    private var timer: Timer?
    private var orientationObserver: NSObjectProtocol?
    /// The last device orientation that actually answered "which way is up".
    /// A camera switch must re-derive the connection's orientation from this
    /// even when the phone is momentarily face-up, face-down or unknown, where
    /// `UIDevice.current.orientation` is not a determinate answer.
    private var lastDeviceOrientation: UIDeviceOrientation?
    /// Inputs and outputs are added once; stopping only stops the session.
    private var isConfigured = false

    var selectedTier: QualityTier? {
        guard let selectedMode else { return nil }
        return CaptureQualityMenu.tier(for: selectedMode, in: capabilities.qualityTiers)
    }

    func configureAndStart(position desired: CameraPosition = .front) {
        // The camera can be switched off and back on mid-take. Re-running
        // `setup` would add a second set of inputs and outputs to the session,
        // so once configured this only restarts the running session.
        if isConfigured {
            start()
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { videoOK in
            AVCaptureDevice.requestAccess(for: .audio) { audioOK in
                DispatchQueue.main.async {
                    guard videoOK, audioOK else {
                        self.errorMessage = String(localized: "Camera and microphone access are required to record.")
                        return
                    }
                    self.setup(position: desired)
                }
            }
        }
    }

    private func setup(position desired: CameraPosition) {
        // One owner for the audio session, and it is not this one.
        // `AVCaptureSession` reconfigures the app's audio session by default
        // when it starts running, which would fight the category and mode set
        // for the take — two things writing the same setting is how a take
        // lost its sound in the first place.
        session.automaticallyConfiguresApplicationAudioSession = false
        session.beginConfiguration()
        // .inputPriority (rather than a fixed preset like .high) is required
        // for `device.activeFormat` to actually take effect below, since the
        // resolution/frame-rate picker sets it explicitly per device.
        session.sessionPreset = .inputPriority

        // A saved back position is only honoured where a back camera exists.
        // `position` records what the session actually connected to, so the
        // sheet's row can reflect reality rather than the saved preference.
        let resolved = CameraPosition.resolvedPosition(requested: desired, hasBackCamera: Self.hasBackCamera())

        if let camera = Self.defaultCamera(for: resolved),
           let camInput = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(camInput) {
            session.addInput(camInput)
            cameraInput = camInput
            cameraDevice = camera
            // Claimed only now that the input is actually in the session: a
            // failed input must not leave `position` naming a camera the
            // controller does not have.
            position = resolved
            // AVFoundation's default camera format has a noticeably narrower
            // field of view than what Camera.app shows — the wide framing has
            // to be opted into by picking the format with the largest FOV
            // explicitly, otherwise the preview looks zoomed in. Widescreen
            // only, so the running format is one the quality toggles can
            // actually name — a 4:3 stills format would leave the pills
            // describing something the session isn't recording.
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }
                if let wideFormat = Self.widestFormat(in: camera.formats) {
                    camera.activeFormat = wideFormat
                }
                camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
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

        applyRecordedConnectionSettings()

        session.commitConfiguration()
        noteVideoInputChanged()

        if let camera = cameraDevice {
            detectCapabilities(for: camera)
        }

        isConfigured = true
        start()
    }

    private func start() {
        startTrackingOrientation()
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    /// Inspects the connected device's actual formats to build the zoom range
    /// and the HD/4K quality menu — different iPhone models expose very
    /// different sets here (e.g. a 4K60 front camera on newer Pro models vs
    /// 1080p30 on older ones).
    private func detectCapabilities(for device: AVCaptureDevice) {
        var caps = CameraCapabilities()
        caps.hasBothCameras = Self.hasBothCameras()
        caps.supportsLowLightBoost = device.isLowLightBoostSupported

        var formats: [VideoMode: AVCaptureDevice.Format] = [:]
        for format in device.formats {
            guard let dims = Self.dimensions(of: format),
                  dims.height >= 720, Self.isWidescreen(dims) else { continue }

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

        // Reported for the format actually in force — a device-wide "some
        // format supports HDR" would offer a toggle whose setter raises.
        caps.supportsHDR = device.activeFormat.isVideoHDRSupported

        if let connection = movieOutput.connection(with: .video) {
            caps.supportsStabilization = connection.isVideoStabilizationSupported
        }

        // Report the mode the session is already running, rather than applying
        // one — `setup` picked the widest-FOV format deliberately and
        // reconfiguring here would undo that before the preview even appears.
        let activeHeight = Self.dimensions(of: device.activeFormat)?.height ?? 0
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
            self.selectedMode = current
            // Keep the reader's current toggles rather than forcing them back
            // on: a camera switch re-runs this for the new device, and their
            // choice should survive the swap. Setup still lands on the same
            // defaults, since both flags start true.
            if caps.supportsStabilization { self.setStabilization(self.stabilizationEnabled) }
            if caps.supportsLowLightBoost { self.setLowLightBoost(self.lowLightBoostEnabled) }
        }
    }

    /// Dimensions for a format, or nil when it has none worth reading.
    ///
    /// `CMVideoFormatDescriptionGetDimensions` logs
    /// `err=-12710 (kCMFormatDescriptionError_InvalidParameter)` to the console
    /// when handed a description that isn't a valid video one, and returns
    /// zeros. Harmless — the size filters discard those anyway — but it's our
    /// call making the noise, so check the media type first.
    private static func dimensions(of format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        let description = format.formatDescription
        guard CMFormatDescriptionGetMediaType(description) == kCMMediaType_Video else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(description)
        guard dims.width > 0, dims.height > 0 else { return nil }
        return dims
    }

    /// Video is 16:9. The front camera also publishes 4:3 stills-shaped
    /// formats (3088x2320, 1920x1440) whose heights would otherwise be read as
    /// video sizes — 2320 outranking 2160 is what put a photo format behind
    /// the "4K" toggle and left it offering a single frame rate.
    private static func isWidescreen(_ dims: CMVideoDimensions) -> Bool {
        guard dims.height > 0 else { return false }
        return abs(Double(dims.width) / Double(dims.height) - 16.0 / 9.0) < 0.05
    }

    /// Chooses the dimensions of the widest-field-of-view 16:9 format at least
    /// 1080 lines tall, from `(dimensions, horizontal field of view)` pairs.
    /// Restricted to `VideoMode.recognizedHeights`: a 16:9 format at any other
    /// height (a back camera's 4032x2268, say) could win on field of view and
    /// become the active format while `detectCapabilities` finds no tier for
    /// it — leaving the pills describing a size the session is not running.
    /// Pure so the choice can be unit tested without a camera; `widestFormat`
    /// maps the chosen dimensions back to the concrete format.
    static func preferredDimensions(from dims: [(CMVideoDimensions, Float)]) -> CMVideoDimensions? {
        dims
            .filter {
                $0.0.height >= 1080
                    && Self.isWidescreen($0.0)
                    && VideoMode.recognizedHeights.contains($0.0.height)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// The concrete format for the widest-FOV 16:9 choice above. Among formats
    /// that share the chosen dimensions, the widest FOV wins — the dimensions
    /// alone can be ambiguous.
    private static func widestFormat(in formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        let candidates = formats.compactMap { format -> (CMVideoDimensions, Float)? in
            guard let dims = Self.dimensions(of: format) else { return nil }
            return (dims, format.videoFieldOfView)
        }
        guard let preferred = Self.preferredDimensions(from: candidates) else { return nil }
        return formats
            .filter { format in
                guard let dims = Self.dimensions(of: format) else { return false }
                return dims.width == preferred.width && dims.height == preferred.height
            }
            .max { $0.videoFieldOfView < $1.videoFieldOfView }
    }

    private static func defaultCamera(for position: CameraPosition) -> AVCaptureDevice? {
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
    }

    private static func hasBackCamera() -> Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return defaultCamera(for: .back) != nil
        #endif
    }

    private static func hasBothCameras() -> Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return defaultCamera(for: .front) != nil && defaultCamera(for: .back) != nil
        #endif
    }

    /// The frame rate to run the newly active format at: the rate the reader
    /// had where the new camera supports it, otherwise the highest offered rate
    /// (24/25/30/60) it can do. Nil only when none of them fit.
    private static func frameRate(preferred: Double?, in format: AVCaptureDevice.Format) -> Double? {
        if let preferred,
           format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= preferred && preferred <= $0.maxFrameRate }) {
            return preferred
        }
        return CaptureQualityMenu.offeredFrameRates.last { rate in
            format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= rate && rate <= $0.maxFrameRate })
        }
    }

    /// The recorded file's connection must stay unmirrored for both cameras;
    /// the mirror the reader sees is a SwiftUI preview-only flip.
    private func applyRecordedConnectionSettings() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
    }

    /// Pins the camera to its widest field of view.
    ///
    /// There is no zoom control any more. A teleprompter wants as much of the
    /// subject and the room in frame as the lens will give; the widest 16:9
    /// format is the design for both cameras. The one thing a zoom setting
    /// could do was make the picture worse.
    ///
    /// Called again after a format change, because the zoom factor and its
    /// range are properties of the *active format*: switching quality can
    /// leave a factor behind that no longer means what it did.
    private func pinToWidestFieldOfView() {
        guard let device = cameraDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = device.minAvailableVideoZoomFactor
            device.unlockForConfiguration()
        } catch {
            // Not worth a banner: the picture is merely narrower than it
            // could be, and everything else about the take still works.
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

    /// Switches the live video input between the front and back cameras inside
    /// the already-running session, never through `setup()` (which must run
    /// once; a second run would add duplicate inputs and outputs).
    ///
    /// The microphone input, the audio session and the recording output are
    /// untouched — only the video input is swapped — so the script keeps
    /// following while the take is armed but not recording.
    ///
    /// Refuses while recording, for the same reason `apply(_:)` does:
    /// reconfiguring the device mid-take tears down the file being written.
    /// The UI disables the row, and this guard is the backstop.
    ///
    /// Every format-dependent property is gated on the *new* device's active
    /// format: zoom is re-read after the format change, frame durations must
    /// fall inside the new format's ranges, and HDR is set only when the new
    /// format supports it — each of these raises an uncatchable Objective-C
    /// exception against the wrong format.
    @discardableResult
    func switchCamera(to target: CameraPosition) -> Bool {
        guard !isRecording else { return false }
        guard target != position else { return true }
        guard let device = Self.defaultCamera(for: target) else {
            errorMessage = String(localized: "Couldn't change camera: that camera isn't available on this device.")
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            errorMessage = String(localized: "Couldn't change camera: the camera input couldn't be created.")
            return false
        }

        let oldInput = cameraInput
        let oldDevice = cameraDevice
        session.beginConfiguration()
        if let oldInput {
            session.removeInput(oldInput)
        }
        cameraInput = nil

        guard session.canAddInput(input) else {
            // Leave the session whole rather than half-configured: put the old
            // camera back if the new one cannot be added.
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
                cameraInput = oldInput
            }
            session.commitConfiguration()
            noteVideoInputChanged()
            applyRecordedConnectionSettings()
            applyCurrentOrientation()
            setStabilization(stabilizationEnabled)
            errorMessage = String(localized: "Couldn't change camera: the camera input couldn't be added.")
            return false
        }
        session.addInput(input)
        cameraInput = input
        cameraDevice = device
        // Synchronously, so the main thread can never read the previous
        // camera's formats against this device: `detectCapabilities` republishes
        // this dictionary asynchronously, and a quality tap in between would
        // otherwise set `activeFormat` on the new device from the old one's
        // list. `apply(_:)` also refuses formats this device does not have.
        formatsByMode = [:]

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if let wideFormat = Self.widestFormat(in: device.formats) {
                device.activeFormat = wideFormat
            }
            // Zoom factor and its range are properties of the active format;
            // re-read (and re-pin to widest) after the format above takes effect.
            device.videoZoomFactor = device.minAvailableVideoZoomFactor

            // Frame durations only inside the new format's ranges. Prefer the
            // rate the reader had, otherwise the highest offered rate the new
            // camera can do — but never a value the format rejects.
            if let rate = Self.frameRate(preferred: selectedMode?.frameRate, in: device.activeFormat),
               device.activeFormat.videoSupportedFrameRateRanges.contains(
                   where: { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }
               ) {
                let duration = CMTime(value: 1, timescale: CMTimeScale(rate.rounded()))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }

            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = hdrEnabled
            }
        } catch {
            // `lockForConfiguration` failed (a Swift error, unlike the Obj-C
            // exceptions the format setters above would raise). Put the old
            // camera back so the session still matches `position`.
            session.removeInput(input)
            cameraInput = nil
            cameraDevice = oldDevice
            if let oldInput, session.canAddInput(oldInput) {
                session.addInput(oldInput)
                cameraInput = oldInput
            }
            session.commitConfiguration()
            noteVideoInputChanged()
            applyRecordedConnectionSettings()
            applyCurrentOrientation()
            setStabilization(stabilizationEnabled)
            errorMessage = String(localized: "Couldn't change camera: \(error.localizedDescription)")
            return false
        }

        session.commitConfiguration()
        noteVideoInputChanged()

        position = target
        pinToWidestFieldOfView()
        setStabilization(stabilizationEnabled)
        applyCurrentOrientation()
        applyRecordedConnectionSettings()
        setLowLightBoost(lowLightBoostEnabled)
        detectCapabilities(for: device)
        return true
    }

    /// Announces a committed video-input change. The preview cannot observe
    /// the session's connections directly, so it is told instead. Main thread
    /// because `inputGeneration` is `@Published` state the view reads.
    private func noteVideoInputChanged() {
        if Thread.isMainThread {
            inputGeneration += 1
        } else {
            DispatchQueue.main.async { self.inputGeneration += 1 }
        }
    }

    /// Switches the capture format.
    ///
    /// Every property touched here raises an Objective-C exception when given
    /// a value the *active format* doesn't support — and those cannot be
    /// caught in Swift, they terminate the app. So each one is checked against
    /// the format actually in force rather than against device-wide
    /// capabilities. This is what crashed the app when tapping the frame-rate
    /// pill: `capabilities.supportsHDR` is true when *any* format supports
    /// HDR, and setting `isVideoHDREnabled` on a format that doesn't (or on a
    /// 10-bit format, where it isn't settable at all) raises immediately.
    func apply(_ mode: VideoMode) {
        guard let device = cameraDevice, let format = formatsByMode[mode] else { return }
        // The dictionary may still describe the previous camera: `switchCamera`
        // clears it synchronously, but `detectCapabilities` republishes it from
        // the main queue and a format belonging to another device raises an
        // uncatchable Objective-C exception on `activeFormat`.
        guard device.formats.contains(format) else { return }
        // Reconfiguring the device mid-recording would tear down the file
        // being written; Camera.app hides the control while recording for the
        // same reason.
        guard !isRecording else { return }
        do {
            session.beginConfiguration()
            try device.lockForConfiguration()
            device.activeFormat = format

            // Frame duration must fall inside one of the *new* format's
            // ranges; anything else raises "Unsupported frame duration".
            if format.videoSupportedFrameRateRanges.contains(
                where: { $0.minFrameRate <= mode.frameRate && mode.frameRate <= $0.maxFrameRate }
            ) {
                let duration = CMTime(value: 1, timescale: CMTimeScale(mode.frameRate.rounded()))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }

            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = hdrEnabled
            }

            device.unlockForConfiguration()
            session.commitConfiguration()
            selectedMode = mode
            pinToWidestFieldOfView()
            // HDR availability is a property of the active format, so it has
            // to be re-read after a change.
            capabilities.supportsHDR = device.activeFormat.isVideoHDRSupported
        } catch {
            session.commitConfiguration()
            errorMessage = String(localized: "Couldn't change quality: \(error.localizedDescription)")
        }
    }

    func setHDR(_ enabled: Bool) {
        // Gated on the active format, not on the device: setting this for a
        // format that doesn't support HDR raises an uncatchable exception.
        guard let device = cameraDevice, device.activeFormat.isVideoHDRSupported else { return }
        do {
            try device.lockForConfiguration()
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = enabled
            device.unlockForConfiguration()
            hdrEnabled = enabled
        } catch {
            errorMessage = String(localized: "Couldn't change HDR: \(error.localizedDescription)")
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
            errorMessage = String(localized: "Couldn't change low-light boost: \(error.localizedDescription)")
        }
    }

    /// Keeps the recorded file's orientation matching the device's physical
    /// rotation. `AVCaptureMovieFileOutput`'s connection doesn't follow
    /// SwiftUI's interface rotation automatically — it has to be set explicitly.
    private func startTrackingOrientation() {
        // Paired with the removal in `stop()` — the begin/end calls are
        // nesting-counted, so re-registering on every restart would leak.
        guard orientationObserver == nil else { return }
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
        let deviceOrientation = UIDevice.current.orientation
        if AVCaptureVideoOrientation.isDeterminate(deviceOrientation) {
            lastDeviceOrientation = deviceOrientation
        }
        // Re-derive from the last determinate orientation so a camera switch
        // still corrects the landscape mapping when the phone is face-up,
        // face-down or unknown right now.
        guard let orientation = AVCaptureVideoOrientation.matching(lastDeviceOrientation ?? deviceOrientation),
              let connection = movieOutput.connection(with: .video),
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }

    func stop() {
        if isRecording { stopRecording() }
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            self.orientationObserver = nil
        }
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
        isRunning = false
    }

    #if DEBUG
    private func observeCaptureHealth() {
        guard captureDiagnostics.isEmpty, let device = cameraDevice else { return }
        pressureObservation = device.observe(\.systemPressureState, options: [.new]) { _, change in
            guard let state = change.newValue else { return }
            print("[capture] systemPressure=\(state.level.rawValue) factors=\(state.factors)")
        }
        let centre = NotificationCenter.default
        captureDiagnostics.append(centre.addObserver(
            forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { note in
                let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
                print("[capture] INTERRUPTED reason=\(raw)")
            })
        captureDiagnostics.append(centre.addObserver(
            forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { _ in
                print("[capture] interruption ended")
            })
        captureDiagnostics.append(centre.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { note in
                let e = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                print("[capture] RUNTIME ERROR \(e?.domain ?? "?") \(e?.code ?? 0) \(e?.localizedDescription ?? "")")
            })
        captureDiagnostics.append(centre.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 99
                let s = AVAudioSession.sharedInstance()
                print("[capture] audio route change reason=\(raw) sampleRate=\(s.sampleRate) ioBuffer=\(s.ioBufferDuration)")
            })
        let s = AVAudioSession.sharedInstance()
        print("[capture] recording starts: mode=\(s.mode.rawValue) sampleRate=\(s.sampleRate) " +
              "ioBuffer=\(s.ioBufferDuration) pressure=\(device.systemPressureState.level.rawValue) " +
              "format=\(device.activeFormat.formatDescription) " +
              "fpsRange=\(device.activeVideoMinFrameDuration.timescale)/\(device.activeVideoMaxFrameDuration.timescale)")
    }
    #endif

    func startRecording() {
        guard isRunning, !isRecording else { return }
        #if DEBUG
        observeCaptureHealth()
        #endif
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        recordingSeconds = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingSeconds += 1
        }
        // `.common`, not the default mode: on the default run loop this timer
        // is suspended for the whole of any touch tracking, so the recording
        // clock visibly froze the moment a finger touched the script and
        // caught up in a jump when it lifted.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        // The timer is also cleared in the delegate callback, which is what
        // catches a recording that stops without going through here.
        timer?.invalidate()
        timer = nil
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // AVFoundation calls this on its own queue, and everything below is
        // `@Published` state the UI observes.
        DispatchQueue.main.async {
            self.isRecording = false
            self.timer?.invalidate()
            self.timer = nil
        }
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = String(localized: "Recording error: \(error.localizedDescription)")
            }
            Self.discard(outputFileURL)
            return
        }
        let seconds = CMTimeGetSeconds(output.recordedDuration)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "Enable Photos access to save your take (it's still on disk as \(outputFileURL.lastPathComponent)).")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        // A take used to finish in total silence: the one
                        // thing the app is for completed with no
                        // acknowledgement at all, so the only way to find out
                        // whether minutes of talking had been kept was to
                        // leave and open Photos.
                        self.savedMessage = seconds >= 1
                            ? String(localized: "Take saved to Photos · \(Self.durationLabel(seconds))")
                            : String(localized: "Take saved to Photos")
                    } else {
                        self.errorMessage = String(localized: "Couldn't save to Photos: \(error?.localizedDescription ?? String(localized: "unknown error"))")
                    }
                }
                // Photos has its own copy now. Leaving these behind meant
                // every take of every session accumulating in the container
                // — minutes of 4K each, invisible to the user and counted
                // against the app's storage.
                if success { Self.discard(outputFileURL) }
            }
        }
    }

    private static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
