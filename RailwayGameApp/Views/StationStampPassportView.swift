import GamePresentation
import SwiftUI

/// The passport of station stamps (decision 348): pages of eight, swiped
/// like a book, each stamp where the reference's layout puts it
/// (``StationStampPassport/layout(_:)``), with the date it was collected.
/// Opened from the achievements; since decision 353 also listed by
/// county or city.
struct StationStampPassportView: View {
    let language: DisplayLanguage
    let records: StationStampRecords
    /// The real railways, for how many stamps there are; `nil` while they
    /// are read.
    var railways: RealRailways?
    /// The counties and cities (decision 353), for the list by county;
    /// `nil` while they are read.
    var placeNames: PlaceNames? = nil
    @State private var total: Int?
    /// Decision 353: pages by date, or the list by county.
    @State private var arrangement = StationStampPassport.Arrangement.date
    /// Each real place's county, worked out once both are read.
    @State private var counties: [String: String]?

    var body: some View {
        let pages = StationStampPassport.pages(records.stamps)
        VStack(spacing: 12) {
            if pages.isEmpty {
                Spacer()
                Text(verbatim: StationStampPassport.empty(in: language))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("stamps.empty")
                Spacer()
            } else {
                Picker(selection: $arrangement) {
                    ForEach(StationStampPassport.Arrangement.allCases, id: \.self) { choice in
                        Text(verbatim: choice.title(in: language)).tag(choice)
                    }
                } label: {
                    Text(verbatim: language.text("Show", "顯示"))
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityIdentifier("stamps.arrangement")
                switch arrangement {
                case .date:
                    TabView {
                        ForEach(pages.indices, id: \.self) { index in
                            StationStampPage(stamps: pages[index], number: index + 1, language: language)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 36)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                case .county:
                    countyList
                }
            }
            Text(verbatim: StationStampPassport.footer(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Theme.background)
        .navigationTitle(Text(verbatim: StationStampPassport.summary(count: records.count, total: total, in: language)))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: railways == nil) {
            guard let railways else { return }
            total = StationStamps.total(in: railways)
        }
        .task(id: arrangement == .county && railways != nil && placeNames != nil) {
            guard arrangement == .county, counties == nil, let railways, let placeNames else { return }
            counties = await Task.detached(priority: .userInitiated) {
                StationStampCounties.counties(of: railways, in: placeNames)
            }.value
        }
    }

    /// Decision 353: each county or city with a real station, how many of
    /// its stamps are collected and which, after the reference's
    /// `cityGroups`.
    @ViewBuilder
    private var countyList: some View {
        if let counties {
            List(StationStampCounties.groups(of: records.stamps, counties: counties)) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: group.name(in: language))
                            .fontWeight(.semibold)
                        Spacer()
                        Text(verbatim: group.total > 0 ? "\(group.collected.count)/\(group.total)" : "\(group.collected.count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(group.collected.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }
                    if group.total > 0 {
                        ProgressView(value: Double(group.collected.count), total: Double(group.total))
                            .tint(Theme.primary)
                    }
                    if !group.collected.isEmpty {
                        Text(verbatim: group.collected.map { $0.name(in: language) }.joined(separator: language.text(", ", "、")))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stamps.county.\(group.county)")
            }
            .scrollContentBackground(.hidden)
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }
    }
}

/// One page of the passport: 0.73 as wide as it is tall (the reference's
/// page), its stamps laid out on it and its number at the foot.
private struct StationStampPage: View {
    let stamps: [StationStamp]
    let number: Int
    let language: DisplayLanguage

    var body: some View {
        let layout = StationStampPassport.layout(stamps.map(\.id))
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(stamps.indices, id: \.self) { index in
                    let place = layout[index]
                    let side = size.width * place.width / 100
                    StationStampMark(stamp: stamps[index], language: language, side: side)
                        .rotationEffect(.degrees(place.angle))
                        .position(x: size.width * place.x / 100, y: size.height * place.y / 100)
                }
                Text(verbatim: String(format: "%02d", number))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .position(x: size.width / 2, y: size.height - 14)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(0.73, contentMode: .fit)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.panelBorder, lineWidth: 1))
    }
}

/// A station's stamp: its name in the game's language, the other
/// language's beneath it, and the date, inside a heavy and a thin border
/// of the railway's ink (``InkStampFrame``, as the trip stamps).
struct StationStampMark: View {
    let stamp: StationStamp
    let language: DisplayLanguage
    let side: CGFloat

    var body: some View {
        let ink = stamp.ink.color
        let other: DisplayLanguage = language == .english ? .traditionalChinese : .english
        let second = stamp.name(in: other)
        VStack(spacing: side * 0.03) {
            Text(verbatim: stamp.name(in: language))
                .font(.system(size: side * 0.2, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if second != stamp.name(in: language) {
                Text(verbatim: second)
                    .font(.system(size: side * 0.1, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Rectangle()
                .frame(height: max(1, side * 0.015))
                .padding(.horizontal, side * 0.08)
            Text(verbatim: StationStampPassport.dateLabel(stamp.earned))
                .font(.system(size: side * 0.09, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(side * 0.1)
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: side * 0.06, style: .continuous)
                .strokeBorder(ink, lineWidth: max(1, side * 0.012))
                .padding(side * 0.06)
        )
        .inkStamp(ink, cornerRadius: side * 0.1, lineWidth: max(2, side * 0.035))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(stamp.name(in: language)), \(StationStampPassport.dateLabel(stamp.earned))"))
        .accessibilityIdentifier("stamp.\(stamp.key)")
    }
}

extension StationStampInk {
    /// The theme colour of the ink (decision 348).
    var color: Color {
        switch self {
        case .navy: Theme.textPrimary
        case .amber: Theme.warning
        case .red: Theme.error
        case .teal: Theme.primary
        }
    }
}
