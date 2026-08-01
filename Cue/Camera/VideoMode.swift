import Foundation

/// A recording quality in the terms Camera.app uses: a size tier and a frame
/// rate, e.g. "4K 60". Deliberately free of AVFoundation types so the menu
/// logic below can be unit tested without a camera.
struct VideoMode: Hashable, Identifiable {
    let height: Int32
    let frameRate: Double

    var id: String { "\(height)p\(Int(frameRate.rounded()))" }

    /// Camera.app's vocabulary: anything at or above ~2160 lines is "4K",
    /// everything else on offer is "HD".
    var tierLabel: String { height >= 2000 ? "4K" : "HD" }
    var frameRateLabel: String { "\(Int(frameRate.rounded()))" }
    var label: String { "\(tierLabel) • \(frameRateLabel)" }
}

/// One size tier and the frame rates available within it.
struct QualityTier: Identifiable, Hashable {
    let label: String
    let height: Int32
    let frameRates: [Double]

    var id: String { "\(label)-\(height)" }
}

/// Turns the long list of raw camera formats into the two-toggle menu the
/// prompter shows — a size (HD / 4K) and a frame rate within it.
enum CaptureQualityMenu {
    /// The rates worth offering. Camera.app exposes 24/25/30/60 depending on
    /// region and format; for a teleprompter 30 and 60 are the meaningful
    /// choices, and anything else is noise on a control you glance at mid-take.
    static let offeredFrameRates: [Double] = [30, 60]

    /// Groups modes into at most two tiers: the largest sub-4K size the device
    /// offers, and 4K. Intermediate sizes are dropped — the point of this
    /// control is a glanceable toggle, not an exhaustive format list.
    static func tiers(from modes: [VideoMode]) -> [QualityTier] {
        let byHeight = Dictionary(grouping: modes, by: \.height)
        let fourKHeights = byHeight.keys.filter { $0 >= 2000 }
        let hdHeights = byHeight.keys.filter { $0 < 2000 }

        var tiers: [QualityTier] = []
        // Only the best size in each tier: several 4K variants would give the
        // toggle two indistinguishable "4K" positions.
        if let hd = hdHeights.max(), let modes = byHeight[hd] {
            tiers.append(tier(label: "HD", height: hd, modes: modes))
        }
        if let uhd = fourKHeights.max(), let modes = byHeight[uhd] {
            tiers.append(tier(label: "4K", height: uhd, modes: modes))
        }
        return tiers
    }

    private static func tier(label: String, height: Int32, modes: [VideoMode]) -> QualityTier {
        let rates = Set(modes.map(\.frameRate))
        return QualityTier(
            label: label,
            height: height,
            frameRates: rates.sorted()
        )
    }

    /// The mode to land on when switching tier: keep the frame rate the
    /// speaker had if the new tier can do it, otherwise the closest one it
    /// can. Switching HD 60 → 4K on a device that only does 4K 30 should give
    /// 4K 30, not fail.
    static func mode(in tier: QualityTier, preferringFrameRate preferred: Double?) -> VideoMode? {
        guard !tier.frameRates.isEmpty else { return nil }
        guard let preferred else {
            return VideoMode(height: tier.height, frameRate: tier.frameRates.max() ?? 30)
        }
        if tier.frameRates.contains(preferred) {
            return VideoMode(height: tier.height, frameRate: preferred)
        }
        let closest = tier.frameRates.min { abs($0 - preferred) < abs($1 - preferred) }
        return closest.map { VideoMode(height: tier.height, frameRate: $0) }
    }

    /// The tier a mode belongs to.
    static func tier(for mode: VideoMode, in tiers: [QualityTier]) -> QualityTier? {
        tiers.first { $0.height == mode.height }
    }

    /// The next tier when the toggle is tapped, wrapping around.
    static func nextTier(after current: QualityTier?, in tiers: [QualityTier]) -> QualityTier? {
        guard !tiers.isEmpty else { return nil }
        guard let current, let index = tiers.firstIndex(of: current) else { return tiers.first }
        return tiers[(index + 1) % tiers.count]
    }

    /// The next frame rate within a tier when the rate toggle is tapped.
    static func nextFrameRate(after current: Double, in tier: QualityTier) -> Double? {
        guard !tier.frameRates.isEmpty else { return nil }
        guard let index = tier.frameRates.firstIndex(of: current) else { return tier.frameRates.first }
        return tier.frameRates[(index + 1) % tier.frameRates.count]
    }
}
