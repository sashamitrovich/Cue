import SwiftUI
import UIKit

/// Where the recorded picture sits on the screen, and where the take buttons
/// go around it.
///
/// With the camera on, the speaker should see exactly the frame that is being
/// recorded, centred, so they can tell whether they are in the middle. The
/// picture is 16:9 in landscape and 9:16 in portrait, shown whole (aspect
/// FIT, never fill). What is left of the screen is black, and the take
/// buttons live there.
///
/// This is a **pure function of geometry**: the full size of the screen, the
/// safe-area insets and which edge the thumb is on. Never of a measured
/// height — see AGENTS.md, "Never position layout from a measurement that
/// the position influences".
///
/// Landscape-ness is derived from the size handed in, never from the
/// latched `isLandscapeLayout` in `PrompterView`, which is written one pass
/// late and would compute a 1500pt-tall portrait picture on landscape
/// geometry.
///
/// All rects are in the full-screen coordinate space (origin at the top-left
/// of the screen, safe area included), which is the space the prompter's
/// `ZStack` lays out in.
struct PrompterFrame: Equatable {
    /// Width over height of the recorded frame in landscape.
    static let landscapeAspect: CGFloat = 16.0 / 9.0

    /// The least black space a landscape strip needs on each side of the
    /// picture: 42pt buttons plus margins. A 12/13 mini leaves 72.6.
    static let landscapeMinStrip: CGFloat = 72
    /// The least black space a portrait strip needs under the picture:
    /// 52pt buttons, no captions, and the home-indicator zone below them.
    /// Spec numbers, not tuned to pass a test.
    static let portraitMinStrip: CGFloat = 90

    /// Only iPhone gets the picture frame. iPad and Mac Catalyst (which
    /// reports `.pad`, as the project builds for family 1,2 without
    /// Designed-for-iPad) keep the full-bleed layout.
    static func usesPictureFrame(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone
    }

    let fullSize: CGSize
    let isLandscape: Bool
    /// The recorded frame, whole.
    let picture: CGRect
    /// The black area that holds the take buttons, or nil when there is no
    /// room for one (a 16:9 phone such as the SE, where the picture is the
    /// whole screen and the buttons float over it instead).
    ///
    /// Portrait: the area under the picture, excluding the bottom safe inset.
    /// Landscape: the full spare width on the thumb edge, ignoring the side
    /// safe inset — the thumb edge is the portrait-bottom edge, never the
    /// Dynamic Island side.
    let strip: CGRect?
    /// Landscape only: whether the strip is on the leading edge.
    let stripOnLeading: Bool
    /// How far the picture reaches into each safe area, in points. Zero where
    /// the picture stays clear of it.
    let safeOverlap: EdgeInsets

    /// True when there was no room for a strip.
    var isFallback: Bool { strip == nil }

    static func make(fullSize: CGSize, safeArea: EdgeInsets, railOnLeading: Bool) -> PrompterFrame {
        let w = max(0, fullSize.width)
        let h = max(0, fullSize.height)
        let size = CGSize(width: w, height: h)
        let landscape = w > h
        var picture = CGRect(origin: .zero, size: size)
        var strip: CGRect?

        if w > 0, h > 0 {
            if landscape {
                let pw = min(w, h * landscapeAspect)
                let ph = pw / landscapeAspect
                picture = CGRect(x: (w - pw) / 2, y: (h - ph) / 2, width: pw, height: ph)
                let spare = (w - pw) / 2
                if spare >= landscapeMinStrip {
                    strip = railOnLeading
                        ? CGRect(x: 0, y: 0, width: spare, height: h)
                        : CGRect(x: w - spare, y: 0, width: spare, height: h)
                }
            } else {
                let wanted = w * landscapeAspect  // portrait picture height
                let top = max(0, safeArea.top)
                if wanted <= h, h - top - wanted >= portraitMinStrip {
                    picture = CGRect(x: 0, y: top, width: w, height: wanted)
                    let stripBottom = h - max(0, safeArea.bottom)
                    strip = CGRect(x: 0, y: picture.maxY, width: w,
                                   height: max(0, stripBottom - picture.maxY))
                } else {
                    // No room: the aspect-FIT rect in the whole screen, which
                    // is the screen itself on a true 16:9 phone.
                    let ph = min(h, wanted)
                    let pw = ph / landscapeAspect
                    picture = CGRect(x: (w - pw) / 2, y: (h - ph) / 2, width: pw, height: ph)
                }
            }
        }

        let overlap = EdgeInsets(
            top: max(0, safeArea.top - picture.minY),
            leading: max(0, safeArea.leading - picture.minX),
            bottom: max(0, safeArea.bottom - (h - picture.maxY)),
            trailing: max(0, safeArea.trailing - (w - picture.maxX))
        )
        return PrompterFrame(
            fullSize: size, isLandscape: landscape, picture: picture, strip: strip,
            stripOnLeading: railOnLeading, safeOverlap: overlap)
    }

    /// The layout the non-phone idioms keep: the "picture" is the whole
    /// screen and there is no strip. The script path is the same code either
    /// way; only the chrome differs.
    static func fullScreen(fullSize: CGSize, safeArea: EdgeInsets, railOnLeading: Bool) -> PrompterFrame {
        let size = CGSize(width: max(0, fullSize.width), height: max(0, fullSize.height))
        return PrompterFrame(
            fullSize: size, isLandscape: size.width > size.height,
            picture: CGRect(origin: .zero, size: size), strip: nil,
            stripOnLeading: railOnLeading,
            safeOverlap: EdgeInsets(top: max(0, safeArea.top), leading: max(0, safeArea.leading),
                                    bottom: max(0, safeArea.bottom), trailing: max(0, safeArea.trailing)))
    }
}
