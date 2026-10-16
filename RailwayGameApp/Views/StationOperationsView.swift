import GameCore
import GamePresentation
import SwiftUI

/// The station panel's operations page (ARCHITECTURE decision 224, option
/// A "月台俯視圖", `docs/art/railway-ui-redesign-2026-10-14/s4-*.png`): how
/// many wait, each platform as a track seen from above with the train
/// standing at it now and how busy it has been, then the weather of the
/// next days. ``StationOperations`` works it out from the world; this view
/// only draws it. Other parts of the station's operations (the station's
/// shops, decision 222) join this section.
struct StationOperationsSection: View {
    let session: GameSession
    let station: StationID

    var body: some View {
        let language = session.language
        let page = StationOperations(world: session.world, station: station, use: session.platformUse)
        Section {
            waitingRow(page, language: language)
            if page.platforms.isEmpty {
                Text(verbatim: language.text("No platform yet. Add one with the network tool.", "還沒有月台。請用路網工具加上月台。"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(page.platforms) { row in
                PlatformTrackRow(row: row, lineName: row.line.flatMap { session.world.line(id: $0)?.name },
                                 code: row.line.flatMap { LineBadge.codes(for: session.world.lines)[$0] }, language: language)
            }
            if !page.days.isEmpty {
                WeatherDaysCard(days: page.days, language: language)
            }
        } header: {
            Text(verbatim: language.text("Now at the station", "車站現況"))
        }
        .accessibilityIdentifier("station.operations")
    }

    private func waitingRow(_ page: StationOperations, language: DisplayLanguage) -> some View {
        HStack(spacing: 8) {
            (page.crowding == .full ? MapGlyph.full : page.crowding == .crowded ? MapGlyph.crowd : MapGlyph.person).image
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(page.crowding == .normal ? Theme.textPrimary : page.crowding == .full ? Theme.error : Theme.warning)
                .accessibilityHidden(true)
            Text(verbatim: page.waitingText(in: language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A platform seen from above (decision 224): its number on a warm disc, the
/// track in the map's teal with the train standing there drawn car by car
/// in its line's colour, and under it where the train goes and how busy
/// the platform has been, in words as well as a bar.
///
/// Decision 224, later (TestFlight, the station card on a phone held
/// sideways): the words are under the track, not beside it, so the track
/// and the bar do not squeeze them into a word a line ("空著", "0", "%");
/// where even that line is short, the bar gives way, then the minutes
/// seen, and a number never breaks.
private struct PlatformTrackRow: View {
    let row: StationOperations.Platform
    let lineName: String?
    let code: String?
    let language: DisplayLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(row.number)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track).frame(height: 6)
                    Capsule().fill(Palette.trackCentre).frame(height: 1.5)
                    if row.train != nil {
                        TrainSideView(color: row.line == nil ? Palette.train : Palette.lineColor(row.line!, custom: row.lineColor),
                                      cars: min(max(row.cars, 1), 6))
                            .padding(.leading, 6)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .clipped()
                .accessibilityHidden(true)
                HStack(spacing: 4) {
                    if let code, let line = row.line {
                        LineCodeBadge(code: code, color: Palette.lineColor(line, custom: row.lineColor), size: .small)
                    }
                    Text(verbatim: row.trainText(lineName: lineName, in: language))
                        .font(.caption)
                        .foregroundStyle(row.train == nil ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                }
                if let busy = row.busyness, let text = row.busyText(in: language), let percent = row.busyPercent {
                    ViewThatFits(in: .horizontal) {
                        busyLine(busy, text: text, percent: percent, bar: true)
                        busyLine(busy, text: text, percent: percent, bar: false)
                        busyLine(busy, text: "\(percent)%", percent: percent, bar: false)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityIdentifier("station.operations.platform.\(row.number)")
    }

    /// How busy the platform has been: the bar (where it fits), the share
    /// and its word, each on one line.
    private func busyLine(_ busy: StationOperations.Busyness, text: String, percent: Int, bar: Bool) -> some View {
        HStack(spacing: 4) {
            if bar {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.chip)
                        Capsule().fill(color(busy)).frame(width: proxy.size.width * Double(percent) / 100)
                    }
                }
                .frame(width: 44, height: 6)
            }
            Text(verbatim: text)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
            Text(verbatim: busy.text(in: language))
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 5)
                .background(color(busy), in: Capsule())
                .foregroundStyle(busy == .packed ? Theme.onError : Theme.onPrimary)
                .fixedSize()
        }
    }

    private func color(_ busy: StationOperations.Busyness) -> Color {
        switch busy {
        case .quiet: Theme.primary
        case .busy: Theme.warning
        case .packed: Theme.error
        }
    }

    private var accessibilityText: String {
        var parts = [language.text("Platform \(row.number)", "第 \(row.number) 月台"), row.trainText(lineName: lineName, in: language)]
        if let busy = row.busyness, let text = row.busyText(in: language) {
            parts.append(text + " " + busy.text(in: language))
        }
        return parts.joined(separator: ", ")
    }
}

/// A train seen from the side, car by car (the map's close-up cars,
/// decision 205): the line's colour, a navy outline and a window band.
private struct TrainSideView: View {
    let color: Color
    let cars: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<cars, id: \.self) { index in
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 3,
                                                          topTrailing: index == cars - 1 ? 8 : 3), style: .continuous)
                    .fill(color)
                    .overlay(
                        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 3,
                                                                  topTrailing: index == cars - 1 ? 8 : 3), style: .continuous)
                            .strokeBorder(Palette.ink, lineWidth: 1.2)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.markerFill)
                            .frame(height: 3)
                            .padding(.horizontal, 3)
                            .padding(.top, 3)
                    }
                    .frame(width: 18, height: 12)
            }
        }
    }
}

/// The next days' weather at the station (decision 224): each day's
/// weather, and what it takes off the riders here, in words.
private struct WeatherDaysCard: View {
    let days: [StationOperations.Day]
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: language.text("Forecast", "預報"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            ForEach(days) { day in
                HStack(spacing: 8) {
                    Text(verbatim: day.dayText(in: language))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 64, alignment: .leading)
                    Image(systemName: day.typhoon ? "tropicalstorm" : day.weather.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(verbatim: day.weatherText(in: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    if let effect = day.effectText(in: language) {
                        Text(verbatim: effect)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("station.operations.forecast")
    }
}
