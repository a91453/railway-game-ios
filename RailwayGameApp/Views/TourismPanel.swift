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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var marked: AttractionID?
    /// Whether the sights off the company's map are shown (decision 663):
    /// folded away at first, unless the map's tap is on one of them.
    @State private var showsOffMap = false

    var body: some View {
        let language = session.language
        let world = session.world
        // CRASH-SIGHTS: kept by the session for the day, not worked out
        // at every tick.
        let rows = session.sightsPanelRows
        // Decision 663: the sights on the company's map, then those off it,
        // nearest first, folded away.
        let onMap = rows.filter { $0.offMapMetres == nil }
        let offMap = rows.filter { $0.offMapMetres != nil }
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(verbatim: language.text(
                            "\(world.touristsThisYear.groupedText) tourists this year",
                            "今年觀光客 \(world.touristsThisYear.groupedText) 人次"
                        ))
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("tourism.year")
                    } footer: {
                        Text(verbatim: world.tourismHelp(in: language))
                    }
                    ForEach(onMap) { row in
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
                            if let exhibits = row.exhibitsText {
                                // Decision 684: the company's railway museum
                                // has its exhibits, not a souvenir shop.
                                Text(verbatim: language.text(
                                    "Today \(row.today) · yesterday \(row.yesterday)",
                                    "今天 \(row.today)・昨天 \(row.yesterday)"
                                ))
                                .font(.footnote)
                                .monospacedDigit()
                                Text(verbatim: exhibits)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("tourism.exhibits")
                            } else {
                                Text(verbatim: language.text(
                                    "Today \(row.today) · yesterday \(row.yesterday) · this year \(row.thisYear.groupedText) · last year \(row.lastYear.groupedText)",
                                    "今天 \(row.today)・昨天 \(row.yesterday)・今年 \(row.thisYear.groupedText)・去年 \(row.lastYear.groupedText)"
                                ))
                                .font(.footnote)
                                .monospacedDigit()
                                shop(row)
                            }
                        }
                        .listRowBackground(marked == row.id ? Theme.accent.opacity(0.18) : nil)
                    }
                    if !offMap.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showsOffMap) {
                                ForEach(offMap) { row in
                                    offMapRow(row)
                                        .listRowBackground(marked == row.id ? Theme.accent.opacity(0.18) : nil)
                                }
                            } label: {
                                Text(verbatim: language.text("Off your map (\(offMap.count))", "地圖外的景點（\(offMap.count)）"))
                            }
                            .accessibilityIdentifier("tourism.offMap")
                        }
                    }
                }
                .task {
                    guard let target = SightFocus.row(for: focus, in: rows) else { return }
                    if offMap.contains(where: { $0.id == target }) { showsOffMap = true }
                    marked = target
                    // Once the sheet has laid its rows out.
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(target, anchor: .top) }
                    try? await Task.sleep(for: .seconds(SightFocus.highlightSeconds))
                    withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { marked = nil }
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

    /// A sight off the company's map (decision 663): its name, stars and
    /// how far off; nothing to build there yet.
    private func offMapRow(_ row: AttractionRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(row)
            if let text = row.offMapText(in: session.language) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
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
