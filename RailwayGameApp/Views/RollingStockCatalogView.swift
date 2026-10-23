import GameCore
import GamePresentation
import SwiftUI

/// The train types as a showroom (ARCHITECTURE decision 224, option 2A,
/// `a91453/railway-reference-private: Railway/game-art-previews/docs/art/railway-ui-redesign-2026-10-14/s2-*.png`): one type at a time,
/// its train standing on a platform under a navy name board, arrows to the
/// next in its family, four figures, the cars stepped on the train itself
/// with the whole train's price on a tag, and a row of the family's other
/// types. Choosing a type sets the type and cars the line's staffing
/// buys; nothing is bought here. ``RollingStockCatalog`` lists the types.
/// Decision 374: in a lesson, a type a later lesson opens is shown with
/// that lesson in place of the choice.
struct RollingStockCatalogView: View {
    let session: GameSession
    @Binding var type: TrainType?
    @Binding var cars: Int
    @Environment(\.dismiss) private var dismiss
    @State private var shown: TrainType?
    @State private var shownCars = 4

    var body: some View {
        let language = session.language
        let catalog = RollingStockCatalog(world: session.world)
        NavigationStack {
            ScrollView {
                if let entry = catalog.entries.first(where: { $0.type == current(catalog) }) {
                    VStack(spacing: 14) {
                        familyPicker(catalog, entry: entry, language: language)
                        showroom(catalog, entry: entry, language: language)
                        figures(entry, language: language)
                        if let note = session.world.sightseeingNote(for: entry.type, in: language) {
                            Text(verbatim: note)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        purchase(entry, language: language)
                        thumbnails(catalog, entry: entry, language: language)
                    }
                    .padding(16)
                } else {
                    Text(verbatim: language.text("No train type to buy here.", "這裡沒有可以買的車種。"))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(24)
                }
            }
            .background(Theme.background)
            .navigationTitle(Text(verbatim: language.text("Train types", "車種型錄")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel", "取消")) { dismiss() }
                        .accessibilityIdentifier("catalog.cancel")
                }
            }
        }
        .onAppear {
            shown = type ?? catalog.firstOpen
            shownCars = cars
        }
        .accessibilityIdentifier("catalog")
    }

    private func current(_ catalog: RollingStockCatalog) -> TrainType? {
        shown ?? catalog.firstOpen
    }

    private func familyPicker(_ catalog: RollingStockCatalog, entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        Picker(selection: Binding(
            get: { entry.family },
            set: { family in shown = catalog.entries(of: family).first?.type }
        )) {
            ForEach(catalog.families, id: \.self) { family in
                Text(verbatim: family.title(in: language)).tag(family)
            }
        } label: {
            Text(verbatim: language.text("Family", "類別"))
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("catalog.family")
    }

    /// The train on its platform: the name board, the arrows either side,
    /// and the train as long as the cars chosen (up to eight drawn).
    private func showroom(_ catalog: RollingStockCatalog, entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: Train.typeText(entry.type, in: language))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Palette.markerFill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                arrow("chevron.left", to: catalog.previous(before: entry.type), label: language.text("Previous", "上一款"))
                CatalogTrain(stripe: stripe(entry.family), cars: min(shownCars, 8))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .animation(.spring(duration: 0.3), value: shownCars)
                arrow("chevron.right", to: catalog.next(after: entry.type), label: language.text("Next", "下一款"))
            }
            // The track and the platform's edge under it.
            ZStack(alignment: .top) {
                Rectangle().fill(Palette.track).frame(height: 7)
                Rectangle().fill(Palette.trackCentre).frame(height: 2).padding(.top, 2)
            }
            Rectangle()
                .fill(Theme.chip)
                .frame(height: 12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.accent).frame(height: 3) }
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.panelBorder, lineWidth: 1))
    }

    private func arrow(_ symbol: String, to type: TrainType?, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { shown = type }
        } label: {
            Image(systemName: symbol)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.panel, in: Circle())
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(type == nil)
        .opacity(type == nil ? 0.3 : 1)
        .accessibilityLabel(Text(verbatim: label))
    }

    private func figures(_ entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        HStack(spacing: 8) {
            figure(language.text("A car", "每節人數"), "\(entry.card.capacityPerCar)", language.text("riders", "人"))
            figure(language.text("Top speed", "最高速度"), "\(entry.card.topSpeed)", "km/h")
            figure(language.text("Doors a car", "每節車門"), "\(entry.doorsPerCar)", "")
            figure(language.text("A day, one car", "每日（一節）"), entry.card.dailyCost.moneyText, "")
        }
    }

    private func figure(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The cars, stepped on the train above; the whole train's price on a
    /// dashed tag; and the choice.
    private func purchase(_ entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        let train = RollingStockCatalog.train(entry.type, cars: shownCars, in: session.world)
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    carsStepper(language: language, riders: train.riders)
                    Spacer(minLength: 4)
                    priceTag(train.price, language: language)
                    chooseButton(entry, language: language)
                }
                VStack(spacing: 10) {
                    carsStepper(language: language, riders: train.riders)
                    HStack(spacing: 12) {
                        priceTag(train.price, language: language)
                        chooseButton(entry, language: language)
                    }
                }
            }
            // Decision 301 (the City Transport Manager study's 4.11): what
            // the train shown costs an hour, to set beside its fares.
            Text(verbatim: language.text(
                "This train costs \(train.hourly.moneyText) an hour on a line, plus its trips.",
                "這列車在路線上每營運小時約 \(train.hourly.moneyText)，另加行駛與發車的費用。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("catalog.hourlyCost")
        }
    }

    private func carsStepper(language: DisplayLanguage, riders: Int64) -> some View {
        Stepper(value: $shownCars, in: Train.minimumCars...Train.maximumCars) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: language.text("\(shownCars) \(shownCars == 1 ? "car" : "cars")", "\(shownCars) 節"))
                    .font(.headline.monospacedDigit())
                Text(verbatim: language.text("\(riders) riders", "共 \(riders) 人"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize()
        .accessibilityIdentifier("catalog.cars")
    }

    private func priceTag(_ price: Money, language: DisplayLanguage) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: language.text("A train", "一列"))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: price.moneyText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(session.world.economy.canAfford(price) ? Theme.textPrimary : Theme.error)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chooseButton(_ entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        if let unlock = session.world.lessonUnlockText(for: entry.type, in: language) {
            Label {
                Text(verbatim: unlock)
                    .font(.headline)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 96, minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("catalog.locked")
        } else {
            choose(entry, language: language)
        }
    }

    private func choose(_ entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        Button {
            type = entry.type
            cars = shownCars
            dismiss()
        } label: {
            Text(verbatim: language.text("Choose this", "選這款"))
                .font(.headline)
                .frame(minWidth: 96, minHeight: 44)
        }
        .buttonStyle(ThemeProminentButtonStyle())
        .accessibilityIdentifier("catalog.choose")
    }

    /// The family's types, small, the one shown outlined.
    private func thumbnails(_ catalog: RollingStockCatalog, entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(catalog.entries(of: entry.family)) { other in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { shown = other.type }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: Train.typeText(other.type, in: language))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            CatalogTrain(stripe: stripe(other.family), cars: 2)
                                .frame(width: 70, height: 20)
                                .opacity(other.isOpen ? 1 : 0.4)
                            if let unlock = session.world.lessonUnlockText(for: other.type, in: language) {
                                Label {
                                    Text(verbatim: unlock)
                                } icon: {
                                    Image(systemName: "lock.fill")
                                }
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(other.type == entry.type ? Palette.ink : Theme.panelBorder, lineWidth: other.type == entry.type ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The stripe along the cars: teal for the metro, warm for the
    /// railway, navy for high speed, the warning colour for the others.
    private func stripe(_ family: RollingStockCatalog.Family) -> Color {
        switch family {
        case .metro: Theme.primary
        case .railway: Theme.accent
        case .highSpeed: Palette.ink
        case .special: Theme.warning
        }
    }
}

/// A train in the showroom, seen from the side: `cars` cars in the panel's
/// colour with a navy outline, navy windows, a door and a stripe, the
/// last car's nose rounded; as wide as it is given.
private struct CatalogTrain: View {
    let stripe: Color
    let cars: Int

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, cars)
            let gap: CGFloat = 2
            let width = (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let height = min(proxy.size.height - 6, width * 0.45)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    car(width: width, height: height, isFront: index == count - 1)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func car(width: CGFloat, height: CGFloat, isFront: Bool) -> some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 3,
                                                               topTrailing: isFront ? height * 0.6 : 3), style: .continuous)
        return shape
            .fill(Palette.markerFill)
            .overlay(alignment: .bottom) {
                Rectangle().fill(stripe).frame(height: height * 0.14).padding(.bottom, height * 0.2)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: height * 0.25) {
                    ForEach(0..<max(1, Int(width / (height * 0.7))), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(Palette.ink).frame(width: height * 0.32, height: height * 0.28)
                    }
                }
                .padding(.top, height * 0.2)
                .padding(.leading, height * 0.25)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1.5))
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                HStack {
                    Circle().fill(Palette.ink).frame(width: height * 0.2)
                    Spacer()
                    Circle().fill(Palette.ink).frame(width: height * 0.2)
                }
                .padding(.horizontal, width * 0.15)
                .offset(y: height * 0.12)
            }
    }
}
