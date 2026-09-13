import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// The prompter's per-frame scroll state, deliberately kept out of `@State`.
///
/// Measured on a device: while the script was moving, `PrompterView.body` was
/// being re-evaluated **about a hundred times a second** — roughly twice per
/// display frame — and every one of those rebuilt and diffed the whole
/// prompter: ground, camera layer, script, chrome, tally, banners, overlays.
/// That, and not the per-word views, is what dropped capture frames. The proof
/// was that reducing the script's own rebuilds from ~50/s to ~2/s changed
/// nothing, while dragging the script with no speech at all still stuttered.
///
/// The cause was four `@State` values changing every tick — the offset, its
/// target, the last tick time and the cue position. A `@State` write
/// invalidates the view that owns it, so a prompter whose job is to move
/// something sixty times a second was rebuilding its entire interface at that
/// rate.
///
/// Holding them here fixes that in two ways:
///
/// - `PrompterView` keeps this in `@State`, which **stores** a reference
///   without subscribing to it. Only `@StateObject` and `@ObservedObject`
///   subscribe. So writing to any of this no longer invalidates the prompter.
/// - Only `offset` is `@Published`, because only `offset` changes what is
///   drawn. The rest are ordinary properties: the pursuit needs them every
///   frame but nothing renders from them, and publishing them would put the
///   invalidation straight back.
///
/// `ScrollingScript` is the one view that observes this, so a frame of
/// scrolling re-applies one `.offset` rather than rebuilding a screen.
final class ScrollState: ObservableObject {
    /// Where the script is drawn. The only value here that anything renders
    /// from, and so the only one that publishes.
    @Published var offset: CGFloat = 0

    /// Where the script is travelling to. Written every frame by the pursuit
    /// and read by it on the next one; nothing draws from it.
    var target: CGFloat = 0
    /// Where the offset was when the current drag began.
    var dragStart: CGFloat = 0
    /// Timestamp of the previous tick, for frame-rate-independent smoothing.
    var lastTick: Date?
    /// The reading line's position, captured for the ticker's callback, which
    /// is registered once and so cannot close over a fresh `cueY` each frame.
    var cueY: CGFloat = 0
}

/// Applies the scroll offset, and is the only thing that redraws when it
/// changes.
///
/// A `ViewModifier` rather than a wrapper view, so it drops into the existing
/// modifier chain where `.offset(y:)` used to be. It observes `ScrollState`;
/// the prompter merely stores it. So a frame of scrolling re-evaluates this
/// one modifier instead of rebuilding the whole prompter — which is what was
/// happening a hundred times a second, and what dropped capture frames.
struct ScrollOffset: ViewModifier {
    @ObservedObject var scroll: ScrollState

    func body(content: Content) -> some View {
        content.offset(y: scroll.offset)
    }
}
