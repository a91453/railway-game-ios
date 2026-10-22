import GamePresentation
import SwiftUI

/// Decision 351, its sequel: in the demo mode, on a real-world map, one
/// tap lays the real lines whose stations are in view, with their trains
/// running (``GameSession/layDemoRealLines(in:)``). While it works, it
/// shows how many stations it has done. Glass, beside the map's other
/// bottom-leading buttons.
struct DemoRealLinesButton: View {
    let session: GameSession
    /// What the map shows, in world units, when the button is tapped.
    let view: () -> WorldRegion

    var body: some View {
        Button {
            let region = view()
            Task { await session.layDemoRealLines(in: region) }
        } label: {
            HStack(spacing: 8) {
                if let progress = session.demoRealLinesProgress {
                    ProgressView()
                    Text(verbatim: progress.total == 0
                        ? session.language.text("Laying…", "鋪設中…")
                        : session.language.text("Laying… \(progress.done)/\(progress.total)", "鋪設中… \(progress.done)/\(progress.total)"))
                        .monospacedDigit()
                } else {
                    Image(systemName: "tram.fill")
                    Text(verbatim: session.language.text("Lay the real lines here", "鋪好這一帶的真實路線"))
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassBackground(in: Capsule(), interactive: true)
        }
        .disabled(session.demoRealLinesProgress != nil)
        .accessibilityHint(Text(verbatim: session.language.text(
            "Lays the real railway lines with stations in view and starts their trains.",
            "把畫面裡的真實鐵路鋪好，並讓列車開始行駛。"
        )))
        .accessibilityIdentifier("map.demoRealLines")
    }
}
