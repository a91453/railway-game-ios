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
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    /// Marks this view as `target` for the tutorial; `nil` marks nothing.
    func tutorialTarget(_ target: TutorialTarget?) -> some View {
        anchorPreference(key: TutorialTargetBounds.self, value: .bounds) { (bounds: Anchor<CGRect>) -> [TutorialTarget: Anchor<CGRect>] in
            guard let target else { return [:] }
            return [target: bounds]
        }
    }
}
