import QuartzCore
import UIKit
import SwiftUI

/// Drives the prompter's per-frame work.
///
/// A `CADisplayLink` rather than `Timer.publish(every: 1/60)`, for three
/// reasons that all cost battery on a long take:
///
/// 1. It is synchronised to the actual display refresh, so it neither races
///    ahead of nor lags a 120 Hz panel, and it follows Low Power Mode down
///    instead of insisting on 60 wakeups a second.
/// 2. It can be throttled. Most of a take needs no animation at all — the
///    script is parked on the reading line and nothing is moving — so the
///    link drops to `idleFrameRate` and only climbs back to full rate when
///    there is something to animate.
/// 3. It stops itself when the app leaves the screen.
///
/// Deliberately **not** `@Published`: publishing a value every frame is the
/// cost this type exists to avoid. It hands the view a callback, and the view
/// decides for itself whether a given frame is worth a state write. A
/// `Timer.publish` created as a `let` on a `View` struct also allocates a
/// fresh publisher every time the struct is re-initialised, which this avoids
/// by living in a `@StateObject`.
final class PrompterTicker: ObservableObject {
    /// What the link runs at when nothing is animating. Low enough to be
    /// nearly free, often enough that the reading line's self-heal check
    /// still catches a stale layout within a frame or two of it happening.
    static let idleFrameRate: Float = 10
    /// Ceiling while something is animating. Deliberately 60 rather than the
    /// panel's maximum: the offset smoothing is time-based, so 120Hz and
    /// 60Hz produce *identical* motion — the extra frames buy nothing
    /// visible and cost real work. This runs alongside live speech
    /// recognition and (usually) 4K capture, and a warm phone throttles both
    /// the frame rate and the audio buffers that recognition depends on.
    static let trackingFrameRate: Float = 60

    private var link: CADisplayLink?
    private var onTick: ((Date) -> Void)?
    private var active = false

    /// Starts the link. `tick` is called on the main thread, once per frame.
    func start(_ tick: @escaping (Date) -> Void) {
        guard link == nil else { return }
        onTick = tick
        let link = CADisplayLink(target: self, selector: #selector(fire))
        // `.common` so the prompter keeps animating while a finger is dragging
        // the script — in the default run-loop mode the whole prompter would
        // freeze for the duration of the gesture.
        link.add(to: .main, forMode: .common)
        self.link = link
        apply(active: active)
    }

    func stop() {
        link?.invalidate()
        link = nil
        onTick = nil
    }

    /// Whether there is anything to animate. Cheap to call every frame — it
    /// only touches the link when the answer actually changes.
    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        apply(active: value)
    }

    private func apply(active: Bool) {
        guard let link else { return }
        // Never ask for more than the panel can give: on a 60Hz device the
        // ceiling below is already its maximum.
        let ceiling = min(Float(UIScreen.main.maximumFramesPerSecond), Self.trackingFrameRate)
        link.preferredFrameRateRange = active
            ? CAFrameRateRange(minimum: min(30, ceiling), maximum: ceiling, preferred: ceiling)
            : CAFrameRateRange(minimum: Self.idleFrameRate, maximum: Self.idleFrameRate, preferred: Self.idleFrameRate)
    }

    @objc private func fire() {
        onTick?(Date())
    }

    deinit { link?.invalidate() }
}
