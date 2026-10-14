import GameCore
import GamePresentation
import SwiftUI

/// A station's shops (ARCHITECTURE decision 222): the level built with what
/// it made yesterday, the next level's card with about how much more it
/// would make a day and when it pays back, and demolishing them. A section
/// of its own, so the station panel and the station operations page can
/// both show it; everything comes from ``StationCommerceCard`` and every
/// button calls a `GameSession` method.
struct StationCommerceSection: View {
    let session: GameSession
    let station: StationID
    @State private var confirmingDemolition = false
    @ScaledMetric(relativeTo: .subheadline) private var artSize = 44.0

    var body: some View {
        let language = session.language
        if session.world.accounts.mode == .management,
           let card = session.stationCommerceCard(of: station), card.allowed {
            Section {
                if let level = card.level {
                    HStack(spacing: 12) {
                        art(level)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: level.title(in: language))
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: card.yesterdayText(in: language))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("station.commerce.current")
                }
                if let offer = card.offer, let title = card.offerTitle(in: language) {
                    Button {
                        session.buildNextStationCommerce(at: station)
                    } label: {
                        HStack(spacing: 12) {
                            art(offer.level)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: title)
                                    .font(.subheadline.weight(.semibold))
                                if let text = card.offerText(in: language) {
                                    Text(verbatim: text)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(verbatim: offer.price.moneyText)
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    .disabled(!offer.affordable)
                    .accessibilityIdentifier("station.commerce.build")
                }
                if card.level != nil {
                    Button(role: .destructive) {
                        confirmingDemolition = true
                    } label: {
                        Text(verbatim: language.text("Demolish the Shops…", "拆除商店…"))
                    }
                    .accessibilityIdentifier("station.commerce.demolish")
                    .confirmationDialog(
                        Text(verbatim: language.text("Demolish the shops? Nothing comes back.", "拆除商店？花的錢不會退回。")),
                        isPresented: $confirmingDemolition, titleVisibility: .visible
                    ) {
                        Button(role: .destructive) {
                            session.demolishStationCommerce(at: station)
                        } label: {
                            Text(verbatim: language.text("Demolish", "拆除"))
                        }
                    }
                }
            } header: {
                Text(verbatim: language.text("Shops", "車站商業"))
            } footer: {
                if card.level == nil {
                    Text(verbatim: StationCommerceCard.explanation(in: language))
                }
            }
        }
    }

    private func art(_ level: StationCommerceLevel) -> some View {
        Image(level.cardArt)
            .resizable()
            .scaledToFit()
            .frame(width: artSize, height: artSize)
            .accessibilityHidden(true)
    }
}
