import GameCore
import GamePresentation
import SwiftUI

/// The train types as a showroom (ARCHITECTURE decision 224, option 2A,
/// `a91453/railway-reference-private: Railway/game-art-previews/docs/art/railway-ui-redesign-2026-10-14/s2-*.png`),
/// over the whole screen (decision 915): a list of the types on the left,
/// with a family, an order and "only those the company can pay for", and
/// the type chosen in the list on the right: its train standing on a
/// platform under a navy name board, arrows to the next in the list, four
/// figures, and what choosing it does. ``RollingStockCatalog`` lists the
/// types. Decision 374: in a lesson, a type a later lesson opens is shown
/// with that lesson in place of the choice.
///
/// One screen for three purposes (decision 915): the type and cars a line's
/// staffing buys (nothing is bought here); the type of a train not yet on
/// the track, or on it and waiting (`GameSession.changeTrainType(_:to:)`,
/// in place of the 23-row menu); and, from the fleet overview, buying one
/// (decision 960).
struct RollingStockCatalogView: View {
    enum Purpose: Equatable {
        case staffing
        case train(TrainID)
        case browse
    }

    let session: GameSession
    var purpose: Purpose = .staffing
    @Binding var type: TrainType?
    @Binding var cars: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var shown: TrainType?
    @State private var shownCars = 4
    /// The family the list shows; `nil`, every family.
    @State private var family: RollingStockCatalog.Family?
    @State private var order: RollingStockCatalog.Order = .family
    @State private var affordableOnly = false

    /// The type and cars a line's staffing buys.
    init(session: GameSession, type: Binding<TrainType?>, cars: Binding<Int>) {
        self.session = session
        _type = type
        _cars = cars
    }

    /// The type of train `train`, not yet on the track.
    init(session: GameSession, train: TrainID) {
        self.session = session
        purpose = .train(train)
        _type = .constant(session.world.train(id: train)?.type)
        _cars = .constant(session.world.train(id: train)?.cars ?? 4)
    }

    /// Only looking.
    init(browsing session: GameSession) {
        self.session = session
        purpose = .browse
        _type = .constant(nil)
        _cars = .constant(4)
    }

    var body: some View {
        let language = session.language
        let catalog = RollingStockCatalog(world: session.world)
        let list = catalog.listed(family: family, order: order, cars: shownCars, affordableOnly: affordableOnly, in: session.world)
        let entry = list.first(where: { $0.type == shown }) ?? list.first
        NavigationStack {
            VStack(spacing: 0) {
                filters(catalog, language: language)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Divider()
                // A phone on its side and an iPad: the list beside the
                // type; a phone upright: the type over the list.
                if isWide {
                    HStack(spacing: 0) {
                        listColumn(list, entry: entry, language: language)
                            .frame(width: 300)
                        Divider()
                        ScrollView { detail(list, entry: entry, language: language).padding(16) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            detail(list, entry: entry, language: language)
                            rows(list, entry: entry, language: language)
                        }
                        .padding(16)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(Text(verbatim: language.text("Train types", "車種型錄")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(purpose == .browse ? language.text("Done", "完成") : language.text("Cancel", "取消")) { dismiss() }
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

    /// A phone on its side or an iPad: the list beside the type.
    private var isWide: Bool {
        horizontalSizeClass == .regular || verticalSizeClass == .compact
    }

    // MARK: The list

    /// The family, the order and "only affordable", in one row where the
    /// list stands beside the type. Chosen by the size classes, not a
    /// `ViewThatFits`, which measures its picker off the main thread
    /// (CRASH101).
    @ViewBuilder
    private func filters(_ catalog: RollingStockCatalog, language: DisplayLanguage) -> some View {
        if isWide {
            HStack(spacing: 12) {
                familyPicker(catalog, language: language)
                orderMenu(language: language)
                affordableToggle(language: language)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                familyPicker(catalog, language: language)
                HStack(spacing: 12) {
                    orderMenu(language: language)
                    Spacer(minLength: 0)
                    affordableToggle(language: language)
                }
            }
        }
    }

    private func familyPicker(_ catalog: RollingStockCatalog, language: DisplayLanguage) -> some View {
        Picker(selection: $family) {
            Text(verbatim: language.text("All", "全部")).tag(RollingStockCatalog.Family?.none)
            ForEach(catalog.families, id: \.self) { family in
                Text(verbatim: family.title(in: language)).tag(Optional(family))
            }
        } label: {
            Text(verbatim: language.text("Family", "類別"))
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("catalog.family")
    }

    private func orderMenu(language: DisplayLanguage) -> some View {
        Menu {
            Picker(selection: $order) {
                ForEach(RollingStockCatalog.Order.allCases, id: \.self) { order in
                    Text(verbatim: order.title(in: language)).tag(order)
                }
            } label: {
                Text(verbatim: language.text("Sort by", "排序"))
            }
        } label: {
            Label {
                Text(verbatim: order.title(in: language))
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
        .fixedSize()
        .accessibilityIdentifier("catalog.sort")
        .accessibilityLabel(Text(verbatim: language.text("Sort by \(order.title(in: language))", "排序：\(order.title(in: language))")))
    }

    private func affordableToggle(language: DisplayLanguage) -> some View {
        Toggle(isOn: $affordableOnly) {
            Text(verbatim: language.text("Only affordable", "只看買得起"))
                .font(.subheadline)
        }
        .toggleStyle(.button)
        .fixedSize()
        .frame(minHeight: 44)
        .accessibilityIdentifier("catalog.affordable")
    }

    private func listColumn(_ list: [RollingStockCatalog.Entry], entry: RollingStockCatalog.Entry?, language: DisplayLanguage) -> some View {
        ScrollViewReader { reader in
            ScrollView {
                rows(list, entry: entry, language: language)
                    .padding(12)
            }
            .onAppear {
                if let entry { reader.scrollTo(entry.type, anchor: .center) }
            }
        }
        .accessibilityIdentifier("catalog.list")
    }

    private func rows(_ list: [RollingStockCatalog.Entry], entry: RollingStockCatalog.Entry?, language: DisplayLanguage) -> some View {
        // Not lazy: some two dozen rows, and a lazy stack builds its
        // cells off the main thread (CRASHSWEEP-2).
        VStack(spacing: 6) {
            if case let .train(id) = purpose, session.world.offersStandardCar {
                standardRow(id, language: language)
            }
            if list.isEmpty {
                Text(verbatim: language.text("No train type the company can pay for now.", "目前沒有買得起的車種。"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            ForEach(list) { other in
                row(other, isShown: other.type == entry?.type, language: language)
                    .id(other.type)
            }
        }
    }

    /// One type: its train's 3D model small, its name, what the order sorts by and the
    /// whole train's price; a lock while a lesson keeps it shut, a tick on
    /// the type chosen.
    private func row(_ other: RollingStockCatalog.Entry, isShown: Bool, language: DisplayLanguage) -> some View {
        let train = RollingStockCatalog.train(other.type, cars: shownCars, in: session.world)
        let affordable = session.world.economy.canAfford(train.price)
        let isChosen = purpose != .browse && other.type == type
        return Button {
            withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { shown = other.type }
        } label: {
            HStack(spacing: 10) {
                // TRAIN-IDENTITY: the 3D map's own model of the type.
                TrainPortraitView(key: TrainPortrait.key(of: other.type), cars: 2, stripe: stripe(other.family), dimmed: !other.isOpen)
                    .frame(width: 84, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: other.type.title(in: language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(verbatim: rowFigure(other, train: train, language: language))
                            .foregroundStyle(Theme.textSecondary)
                        Text(verbatim: train.price.moneyText)
                            .foregroundStyle(affordable ? Theme.textSecondary : Theme.error)
                    }
                    .font(.caption.monospacedDigit())
                }
                Spacer(minLength: 4)
                if !other.isOpen {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.textSecondary)
                } else if isChosen {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(isShown ? Theme.chip : Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isShown ? Palette.ink : Theme.panelBorder, lineWidth: isShown ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The button stays one element with its own label: wrapping it in
        // `.accessibilityElement(children: .ignore)` made a new element
        // without the button trait, which VoiceOver and the UI tests did
        // not find as a button (full lane of a011379, after 143).
        .accessibilityLabel(Text(verbatim: "\(Train.typeText(other.type, in: language)) · \(train.price.moneyText)"))
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityIdentifier("catalog.row")
    }

    /// What the list is sorted by, for one row: what a car carries unless
    /// the order is a speed or an hour's cost.
    private func rowFigure(_ entry: RollingStockCatalog.Entry, train: (riders: Int64, price: Money, daily: Money, hourly: Money), language: DisplayLanguage) -> String {
        switch order {
        case .speed: "\(entry.card.topSpeed) km/h"
        case .hourlyCost: language.text("\(train.hourly.moneyText) an hour", "每小時 \(train.hourly.moneyText)")
        case .family, .price, .capacity: language.text("\(entry.card.capacityPerCar) a car", "每節 \(entry.card.capacityPerCar) 人")
        }
    }

    /// The standard car, for a train being placed where the game offers it.
    private func standardRow(_ id: TrainID, language: DisplayLanguage) -> some View {
        let isChosen = session.world.train(id: id)?.type == nil
        return Button {
            // Decision 959: the train it was opened for; decision 960:
            // on the track too.
            session.changeTrainType(id, to: nil)
            dismiss()
        } label: {
            HStack {
                Text(verbatim: Train.standardCarName(in: language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.panelBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: Train.typeText(nil, in: language)))
        .accessibilityIdentifier("catalog.standard")
    }

    // MARK: The type shown

    @ViewBuilder
    private func detail(_ list: [RollingStockCatalog.Entry], entry: RollingStockCatalog.Entry?, language: DisplayLanguage) -> some View {
        if let entry {
            VStack(spacing: 14) {
                showroom(list, entry: entry, language: language)
                figures(entry, language: language)
                if let note = session.world.sightseeingNote(for: entry.type, in: language) {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                purchase(entry, language: language)
            }
        } else {
            Text(verbatim: language.text("No train type to buy here.", "這裡沒有可以買的車種。"))
                .foregroundStyle(Theme.textSecondary)
                .padding(24)
        }
    }

    /// The train on its platform: the name board, the arrows either side,
    /// and the train's 3D model (TRAIN-IDENTITY), up to three cars of it.
    private func showroom(_ list: [RollingStockCatalog.Entry], entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        VStack(spacing: 0) {
            HStack {
                // TRAIN-IDENTITY: its name alone; what a car carries and
                // its doors are the figures under the train.
                Text(verbatim: entry.type.title(in: language))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Palette.markerFill)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // REVIEW-L32: the name alone is no longer told from
                    // other texts by what follows it, so it is named.
                    .accessibilityIdentifier("catalog.name")
                Spacer()
            }
            .padding(.bottom, 10)
            HStack(spacing: 8) {
                arrow("chevron.left", to: RollingStockCatalog.step(in: list, from: entry.type, by: -1), label: language.text("Previous", "上一款"))
                // TRAIN-IDENTITY: the train the 3D map draws, its head
                // and two cars behind it.
                TrainPortraitView(key: TrainPortrait.key(of: entry.type), cars: min(shownCars, 3), stripe: stripe(entry.family))
                    .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 150)
                    .padding(.bottom, 4)
                arrow("chevron.right", to: RollingStockCatalog.step(in: list, from: entry.type, by: 1), label: language.text("Next", "下一款"))
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
            withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { shown = type }
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
        // Decision 962: how each model runs is part of it, so its rates
        // stand beside its top speed.
        let runs = entry.card.type?.performance
        let rates = runs ?? .standard
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                figure(language.text("A car", "每節人數"), "\(entry.card.capacityPerCar)", language.text("riders", "人"))
                figure(language.text("Top speed", "最高速度"), "\(entry.card.topSpeed)", "km/h")
                figure(language.text("Doors a car", "每節車門"), "\(entry.doorsPerCar)", "")
                figure(language.text("A day, one car", "每日（一節）"), entry.card.dailyCost.moneyText, "")
            }
            HStack(spacing: 8) {
                figure(language.text("Accelerates", "加速"), TrainPerformance.rateText(rates.acceleration), "km/h/s")
                figure(language.text("Brakes", "減速"), TrainPerformance.rateText(rates.braking), "km/h/s")
            }
            if runs == nil {
                Text(verbatim: language.text("Runs as its line is planned.", "照路線的性能跑。"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
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

    /// The cars, stepped on the train above (a train being placed keeps its
    /// own); the whole train's price on a dashed tag, or what changing the
    /// train to it costs; and the choice, unless only looking.
    private func purchase(_ entry: RollingStockCatalog.Entry, language: DisplayLanguage) -> some View {
        let train = RollingStockCatalog.train(entry.type, cars: shownCars, in: session.world)
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    carsControl(language: language, riders: train.riders)
                    Spacer(minLength: 4)
                    priceTag(entry, price: train.price, language: language)
                    chooseButton(entry, language: language)
                }
                VStack(spacing: 10) {
                    carsControl(language: language, riders: train.riders)
                    HStack(spacing: 12) {
                        priceTag(entry, price: train.price, language: language)
                        chooseButton(entry, language: language)
                    }
                }
            }
            // Decision 301: what
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

    @ViewBuilder
    private func carsControl(language: DisplayLanguage, riders: Int64) -> some View {
        let label = VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: language.text("\(shownCars) \(shownCars == 1 ? "car" : "cars")", "\(shownCars) 節"))
                .font(.headline.monospacedDigit())
            Text(verbatim: language.text("\(riders) riders", "共 \(riders) 人"))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        if case .train = purpose {
            // The train's own cars: its stepper is on the train's card.
            label
        } else {
            Stepper(value: $shownCars, in: Train.minimumCars...Train.maximumCars) { label }
                .fixedSize()
                .accessibilityIdentifier("catalog.cars")
        }
    }

    /// The whole train's price, or for a train being placed what changing
    /// it to this type costs (decision 180's refit).
    private func priceTag(_ entry: RollingStockCatalog.Entry, price: Money, language: DisplayLanguage) -> some View {
        var title = language.text("A train", "一列")
        var cost = price
        if case let .train(id) = purpose, session.world.rollingStockEconomics {
            title = language.text("Change", "改裝")
            cost = session.world.train(id: id)?.type == entry.type ? .zero : session.world.refitCost(of: id, to: entry.type)
        }
        return VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: cost.moneyText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(session.world.economy.canAfford(cost) ? Theme.textPrimary : Theme.error)
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
            switch purpose {
            case .staffing:
                type = entry.type
                cars = shownCars
            case .train(let id):
                // Decision 959: the train it was opened for, not the one
                // selected now.
                session.changeTrainType(id, to: entry.type)
            case .browse:
                // Decision 960: from the fleet, a train of it bought.
                session.purchaseTrain(of: entry.type, cars: shownCars)
            }
            dismiss()
        } label: {
            Text(verbatim: purpose == .browse ? language.text("Buy one", "買一列") : language.text("Choose this", "選這款"))
                .font(.headline)
                .frame(minWidth: 96, minHeight: 44)
        }
        .buttonStyle(ThemeProminentButtonStyle())
        .accessibilityIdentifier("catalog.choose")
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
struct CatalogTrain: View {
    let stripe: Color
    let cars: Int
    /// Decision 696: only its outline's shape, in one flat colour: a type
    /// the railway museum does not have yet.
    var silhouette = false

    var body: some View {
        let stripe = stripe
        let cars = cars
        let silhouette = silhouette
        // A sendable closure, not main-actor code (CRASHSWEEP-3): SwiftUI
        // calls a GeometryReader's closure again whenever its size
        // changes, which its asynchronous renderer may do off the main
        // thread (CRASH101).
        GeometryReader { @Sendable proxy in
            CatalogTrainCars(stripe: stripe, cars: cars, size: proxy.size, silhouette: silhouette)
        }
        .accessibilityHidden(true)
    }
}

/// ``CatalogTrain``'s cars at the size its reader gives.
private struct CatalogTrainCars: View {
    let stripe: Color
    let cars: Int
    let size: CGSize
    var silhouette = false

    var body: some View {
        let count = max(1, cars)
        let gap: CGFloat = 2
        let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let height = min(size.height - 6, width * 0.45)
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { index in
                car(width: width, height: height, isFront: index == count - 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func car(width: CGFloat, height: CGFloat, isFront: Bool) -> some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 3,
                                                               topTrailing: isFront ? height * 0.6 : 3), style: .continuous)
        // A silhouette is one flat colour all over.
        let flat: Color? = silhouette ? Theme.textSecondary : nil
        let ink = flat ?? Palette.ink
        return shape
            .fill(flat ?? Palette.markerFill)
            .overlay(alignment: .bottom) {
                Rectangle().fill(flat ?? stripe).frame(height: height * 0.14).padding(.bottom, height * 0.2)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: height * 0.25) {
                    ForEach(0..<RollingStockCatalog.sideWindows(width: width, height: height), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(ink).frame(width: height * 0.32, height: height * 0.28)
                    }
                }
                .padding(.top, height * 0.2)
                .padding(.leading, height * 0.25)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(ink, lineWidth: 1.5))
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                HStack {
                    Circle().fill(ink).frame(width: height * 0.2)
                    Spacer()
                    Circle().fill(ink).frame(width: height * 0.2)
                }
                .padding(.horizontal, width * 0.15)
                .offset(y: height * 0.12)
            }
    }
}
