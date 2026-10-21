import GameCore
import GamePresentation
import SwiftUI

/// Decision 315 §2: the card that offers a real branch line, opened from a
/// station beside it or the new-line menu. What it brings, its price in
/// three parts and the total, and what is in the way, if anything; Buy
/// only when nothing is and the cash is there. The offer is the
/// session's (``GameSession/shownRealLineOffer``); this view only draws it.
struct RealLineOfferCard: View {
    let session: GameSession
    let offer: RealLineOffer
    /// Called after Buy bought the line.
    var bought: () -> Void = {}

    var body: some View {
        let language = session.language
        let shortfall = offer.shortfallText(balance: session.world.economy.balance, in: language)
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: offer.summaryText(in: language))
                        .font(.subheadline)
                    Text(verbatim: language.text("Yours to run from tomorrow's first train.", "明天首班車起由你經營。"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if offer.price != nil {
                    Section {
                        ForEach(Array(offer.priceRows(in: language).enumerated()), id: \.offset) { index, row in
                            let total = index == 3
                            HStack {
                                Text(verbatim: row.label)
                                    .font(total ? .subheadline.weight(.semibold) : .subheadline)
                                Spacer()
                                Text(verbatim: row.amount.moneyText)
                                    .font((total ? Font.subheadline.weight(.semibold) : .subheadline).monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("acquire.price.\(index)")
                        }
                    } header: {
                        Text(verbatim: language.text("Price", "價格"))
                    }
                }
                if !session.world.realTransfers {
                    Text(verbatim: RealLineOffer.transfersOffText(in: language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let problem = offer.problem {
                    Label {
                        Text(verbatim: problem)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("acquire.problem")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let shortfall, offer.problem == nil {
                        Text(verbatim: shortfall)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .accessibilityIdentifier("acquire.shortfall")
                    }
                    Button {
                        if session.acquireRealLine(offer) { bought() }
                    } label: {
                        Text(verbatim: language.text("Buy \(offer.line.name(in: language))", "收購\(offer.line.name(in: language))"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    // Decision 110: the card's main action, as the theme draws one.
                    .buttonStyle(ThemeProminentButtonStyle())
                    .disabled(offer.acquisition == nil || shortfall != nil)
                    .accessibilityIdentifier("acquire.buy")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.panel)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.panelBorder).frame(height: 1)
                }
            }
            .navigationTitle(Text(verbatim: offer.line.name(in: language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        session.shownRealLineOffer = nil
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                    .accessibilityIdentifier("acquire.cancel")
                }
            }
        }
    }
}

/// Decision 315 §8: the card a purchase ends on, laid out as a lesson's
/// result card. The line's colour band with its name, a navy round seal
/// "Bought" holding the junction's and the terminal's names, and what the
/// company now runs. The seal comes down once (`MotionRule.pop`); with
/// Reduce Motion it is simply there.
struct AcquisitionCompleteCard: View {
    let acquired: RealLineAcquired
    let language: DisplayLanguage
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        VStack(spacing: 16) {
            band
            seal
                .scaleEffect(stamped || reduceMotion ? 1 : 1.25)
                .opacity(stamped || reduceMotion ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: language.text(
                    "Bought: \(acquired.ends.from) to \(acquired.ends.to)", "收購：\(acquired.ends.from)—\(acquired.ends.to)"
                )))
                .accessibilityIdentifier("acquired.seal")
            VStack(spacing: 4) {
                Text(verbatim: acquired.sizeText(in: language))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: acquired.handoverText(in: language))
                Text(verbatim: acquired.timetableText(in: language))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            Button(action: done) {
                Text(verbatim: language.text("OK", "好"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ThemeProminentButtonStyle())
            .accessibilityIdentifier("acquired.done")
        }
        .padding(24)
        .frame(maxWidth: 360)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(MotionRule.pop.animation) { stamped = true }
        }
    }

    /// The line's colour, its name on a panel-coloured capsule so it reads
    /// on any line colour.
    private var band: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(acquired.color.map { Palette.color($0) } ?? Theme.primary)
            .frame(height: 40)
            .overlay {
                Text(verbatim: acquired.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Theme.panel, in: Capsule())
            }
            .accessibilityIdentifier("acquired.title")
    }

    /// Flat, a thick navy ring and a thin one inside it, as the app icon
    /// draws its outlines (art-style skill); no new colour.
    private var seal: some View {
        ZStack {
            Circle().strokeBorder(Theme.textPrimary, lineWidth: 4)
            Circle().strokeBorder(Theme.textPrimary, lineWidth: 1.5).padding(9)
            VStack(spacing: 2) {
                Text(verbatim: language.text("Bought", "收購"))
                    .font(.title2.weight(.heavy))
                Text(verbatim: "\(acquired.ends.from)—\(acquired.ends.to)")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(18)
        }
        .frame(width: 124, height: 124)
        .rotationEffect(.degrees(-8))
    }
}
