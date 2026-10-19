import GameCore
import GamePresentation
import SwiftUI

/// The sights tourists come to (decision 174): each with its stars, the
/// tourists it draws today, yesterday and this year and last, what keeps it
/// from drawing any, and a button for the next level of its souvenir shop
/// with what that does. Opened from the game menu, and by a tap on a
/// sight's stars on the map, which opens it at that sight's row, marked
/// for a moment (decision 250). Everything shown is read from
/// `session.world`; the words come from GamePresentation.
struct TourismPanel: View {
    let session: GameSession
    /// The sight tapped on the map (``SightFocus``), or `nil` from the menu.
    var focus: AttractionID?
    @Environment(\.dismiss) private var dismiss
    @State private var marked: AttractionID?

    var body: some View {
        let language = session.language
        let world = session.world
        let rows = world.attractionRows(in: language)
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(verbatim: language.text(
                            "\(Money(world.touristsThisYear).displayText) tourists this year",
                            "今年觀光客 \(Money(world.touristsThisYear).displayText) 人次"
                        ))
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("tourism.year")
                    } footer: {
                        Text(verbatim: world.tourismHelp(in: language))
                    }
                    ForEach(rows) { row in
                        Section {
                            header(row)
                            Label {
                                Text(verbatim: row.statusText)
                            } icon: {
                                Image(systemName: row.status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(row.status == .ok ? Theme.success : Theme.warning)
                            }
                            .font(.footnote)
                            if row.hotels > 0 {
                                Text(verbatim: language.text(
                                    "\(row.hotels) hotel\(row.hotels == 1 ? "" : "s") within 800 m",
                                    "800 公尺內有 \(row.hotels) 家飯店"
                                ))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                            }
                            if let text = row.sightseeingTrainText {
                                Text(verbatim: text)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let station = row.stationName {
                                Text(verbatim: language.text("Station: \(station)", "車站：\(station)"))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Text(verbatim: language.text(
                                "Today \(row.today) · yesterday \(row.yesterday) · this year \(Money(row.thisYear).displayText) · last year \(Money(row.lastYear).displayText)",
                                "今天 \(row.today)・昨天 \(row.yesterday)・今年 \(Money(row.thisYear).displayText)・去年 \(Money(row.lastYear).displayText)"
                            ))
                            .font(.footnote)
                            .monospacedDigit()
                            shop(row)
                        }
                        .listRowBackground(marked == row.id ? Theme.accent.opacity(0.18) : nil)
                    }
                }
                .task {
                    guard let target = SightFocus.row(for: focus, in: rows) else { return }
                    marked = target
                    // Once the sheet has laid its rows out.
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                    try? await Task.sleep(for: .seconds(SightFocus.highlightSeconds))
                    withAnimation { marked = nil }
                }
            }
            .navigationTitle(Text(verbatim: language.text("Sights", "觀光景點")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("tourism.done")
                }
            }
        }
    }

    private func header(_ row: AttractionRow) -> some View {
        HStack {
            MapGlyph.star.image
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(verbatim: row.name)
                .fontWeight(.semibold)
            Spacer()
            Text(verbatim: "\(row.starsText) · \(row.kind)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        // Where the panel scrolls to for a sight tapped on the map.
        .id(row.id)
        .accessibilityIdentifier("tourism.row.\(row.id.rawValue)")
    }

    @ViewBuilder
    private func shop(_ row: AttractionRow) -> some View {
        let language = session.language
        if let offer = row.nextShop {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: offer.preview)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    session.investInSouvenirShop(of: row.id)
                } label: {
                    Text(verbatim: language.text(
                        "Souvenir shop level \(row.souvenir + 1) · \(offer.cost.moneyText)",
                        "名產店升到 \(row.souvenir + 1) 級・\(offer.cost.moneyText)"
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!offer.canAfford)
                .accessibilityIdentifier("tourism.shop.\(row.id.rawValue)")
            }
        } else {
            Text(verbatim: language.text("Souvenir shop at its top level (2).", "名產店已是最高等級（2 級）。"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
