import GamePresentation
import SwiftUI

/// Where each control a tutorial step can be about lies on screen (Stage
/// C5): every control marked with `tutorialTarget(_:)` reports its bounds
/// under its ``TutorialTarget``, and the tutorial's overlay reads them with
/// `overlayPreferenceValue(_:_:)` to outline the step's targets and put its
/// card beside the first (the reference finds them with
/// `document.querySelector`).
///
/// A preference does not leave a sheet: a control in a sheet is found only
/// by an overlay inside that sheet.
struct TutorialTargetBounds: PreferenceKey {
    static var defaultValue: [TutorialTarget: TutorialTargetAnchor] { [:] }

    static func reduce(value: inout [TutorialTarget: TutorialTargetAnchor], nextValue: () -> [TutorialTarget: TutorialTargetAnchor]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// A marked control's bounds, and the bounds of each scroll view it sits in
/// (marked with `tutorialClip()`). A control scrolled out of its scroll view
/// still has bounds, over whatever lies beyond the scroll view; only the
/// part inside every clip is on screen.
struct TutorialTargetAnchor {
    let bounds: Anchor<CGRect>
    var clips: [Anchor<CGRect>] = []

    /// The part of the control on screen, in `proxy`'s coordinates, within
    /// `viewport`; `nil` when none of it is.
    @MainActor
    func visibleFrame(in proxy: GeometryProxy, viewport: CGRect) -> CGRect? {
        var visible = proxy[bounds].intersection(viewport)
        for clip in clips {
            visible = visible.intersection(proxy[clip])
        }
        return visible.isNull || visible.isEmpty ? nil : visible
    }
}

extension View {
    /// Marks this view as `target` for the tutorial; `nil` marks nothing.
    func tutorialTarget(_ target: TutorialTarget?) -> some View {
        anchorPreference(key: TutorialTargetBounds.self, value: .bounds) { (bounds: Anchor<CGRect>) -> [TutorialTarget: TutorialTargetAnchor] in
            guard let target else { return [:] }
            return [target: TutorialTargetAnchor(bounds: bounds)]
        }
    }

    /// Marks a scroll view: the tutorial counts the controls marked inside it
    /// only where it shows them.
    func tutorialClip() -> some View {
        transformAnchorPreference(key: TutorialTargetBounds.self, value: .bounds) { (targets: inout [TutorialTarget: TutorialTargetAnchor], clip: Anchor<CGRect>) in
            for target in targets.keys {
                targets[target]?.clips.append(clip)
            }
        }
    }
}
