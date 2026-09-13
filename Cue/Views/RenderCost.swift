import Foundation

/// What actually runs while the script is scrolling. Kept as scaffolding for
/// the next perf investigation, since it is free in Release.
///
/// Historical note (#11, resolved 2026-09-13): these SwiftUI body/layout
/// counters never convicted the real culprit, because the cost was on the GPU,
/// not in body evaluation. The recording stutter was two per-word blurred
/// `.shadow` halos — ~430 offscreen Gaussian-blur layers recomposited every
/// frame over live video, contending with the H.264 encoder. Body count,
/// preview layouts and per-word rebuilds were all ruled out by these very
/// numbers while the stutter persisted; commenting out the blur fixed it.
/// The lesson these counters encode: `print` counters are blind to GPU time,
/// compositing and offscreen rendering — reach for Instruments (Core
/// Animation, Metal System Trace) when the symptom is dropped capture frames.
///
/// DEBUG only, and deliberately just counters and a timestamp.
#if DEBUG
enum RenderCost {
    private static var prompterBodies = 0
    private static var previewUpdates = 0
    private static var previewLayouts = 0
    private static var scriptBodies = 0
    private static var since = Date()

    static func prompterBody() { prompterBodies += 1 }
    static func previewUpdate() { previewUpdates += 1 }
    static func previewLayout() { previewLayouts += 1 }
    static func scriptBody() { scriptBodies += 1 }

    /// Called from the prompter's once-a-second tick.
    static func report() {
        let elapsed = Date().timeIntervalSince(since)
        guard elapsed >= 1 else { return }
        print(String(
            format: "[cost] prompter body %.0f/s | script body %.0f/s | preview update %.0f/s | preview LAYOUT %.0f/s",
            Double(prompterBodies) / elapsed,
            Double(scriptBodies) / elapsed,
            Double(previewUpdates) / elapsed,
            Double(previewLayouts) / elapsed
        ))
        prompterBodies = 0
        previewUpdates = 0
        previewLayouts = 0
        scriptBodies = 0
        since = Date()
    }
}
#endif
