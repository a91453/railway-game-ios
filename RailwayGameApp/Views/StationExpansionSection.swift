import GameCore
import GamePresentation
import SwiftUI

/// A station's room to wait (decision 506): how many can wait and do, and
/// the next expansion with its price, open once the station is busy
/// enough. Everything comes from ``StationExpansionCard`` and the button
/// calls a `GameSession` method.
struct StationExpansionSection: View {
    let session: GameSession
    let station: StationID

    var body: some View {
        let language = session.language
        if session.world.accounts.mode == .management,
           let card = session.stationExpansionCard(of: station) {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: card.expansion?.title(in: language) ?? language.text("Standard station", "一般車站"))
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: card.capacityText(in: language))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("station.expansion.current")
                if let title = card.offerTitle(in: language) {
                    Button {
                        session.expandStation(at: station)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: title)
                                .font(.subheadline.weight(.semibold))
                            if let price = card.offerPriceText {
                                Text(verbatim: price)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            if let text = card.offerText(in: language) {
                                Text(verbatim: text)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .disabled(!card.canExpand)
                    .accessibilityIdentifier("station.expansion.build")
                } else if let text = card.offerText(in: language) {
                    Text(verbatim: text)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text(verbatim: language.text("Station Size", "車站規模"))
            } footer: {
                if card.expansion == nil {
                    Text(verbatim: StationExpansionCard.explanation(in: language))
                }
            }
        }
    }
}
