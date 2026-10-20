import GamePresentation
import SwiftUI

/// The new line's draft in one line, at the top of its section (City
/// Transport Manager study 4.2, step M0): "3 stops · 4.2 km · about 6 min
/// · $ 1,200,000", or why no track joins the stations picked, in the
/// warning colour. GamePresentation says it (``GameSession/lineDraftSummary``);
/// this only lays it out.
struct LineDraftSummaryRow: View {
    let session: GameSession

    var body: some View {
        if let summary = session.lineDraftSummary {
            Text(verbatim: summary.text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(summary.isProblem ? Theme.warning : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("line.draft.summary")
        }
    }
}
