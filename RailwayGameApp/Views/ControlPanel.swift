import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// The way into building, selection inspector, tool options and the
/// action button: the Build entry, always shown in the dock, and the
/// details, in a card the screen shows only when there is something to
/// show (``ContentView``), with the inspector at its head, the options in
/// its middle and the action button at its foot. The tools themselves are in a
/// column at the map's edge while building (``BuildToolRail``, decision
/// 114).
struct ControlPanel: View {
    enum Arrangement {
        /// The Build entry, the lines and the figures, and Undo, in a row.
        case tools
        /// Decision 226: Data, Lines and Build in a column down the leading
        /// edge of a phone held sideways, Build at the bottom, under the
        /// thumb.
        case toolsColumn
        /// Decision 226: Build alone, at the foot of that column while the
        /// building tools are out over it, where a second tap closes them.
        case buildEntry
        /// Decision 226: Undo and Redo in a row beside the column's foot,
        /// when there is an edit to take back or make again.
        case editsRow
        /// The selection inspector, or what the network tool's taps
        /// picked: the details card's head, which stays put.
        case inspector
        /// The tool's options: the details card's middle, which scrolls.
        case options
        /// The action button: the details card's foot, which stays put.
        case action
    }

    let session: GameSession
    let arrangement: Arrangement

    /// Whether the details card has an inspector to show: the building
    /// tool's taps pick a site, not a station, so the selection row only
    /// took the room its kinds need.
    static func showsInspector(_ session: GameSession) -> Bool {
        session.tool != .building
    }

    /// Whether the details card has an action button to show.
    static func showsAction(_ session: GameSession) -> Bool {
        ActionButton(session: session).title != nil
    }

    /// Decision 226: whether Undo and Redo show. Only while there is an
    /// edit to take back or make again (in practice just after one, while
    /// paused), so most of the time the screen has two buttons fewer; and
    /// never in the tutorial, as the details toggle is not, so its steps'
    /// spotlights stay where they were (the session refuses Undo then too,
    /// ``GameSession/canUndo``).
    static func showsEdits(_ session: GameSession) -> Bool {
        session.tutorial == nil && (session.canUndo || session.canRedo)
    }

    var body: some View {
        switch arrangement {
        case .tools:
            // In the dock's one glass (``ContentView``), as before decision
            // 226; Undo and Redo only while they can be used.
            HStack(spacing: 8) {
                BuildEntry(session: session)
                    .dockEntryFrame()
                // Decision 104: the lines and the company's figures, named,
                // beside the tools.
                QuickEntries(session: session, vertical: false)
                if Self.showsEdits(session) {
                    UndoButton(session: session)
                    RedoButton(session: session)
                }
            }
        case .toolsColumn:
            VStack(spacing: ToolColumnStyle.buttonSpacing) {
                QuickEntries(session: session, vertical: true)
                BuildEntry(session: session)
            }
            .controlTile()
        case .buildEntry:
            BuildEntry(session: session)
                .controlTile()
        case .editsRow:
            if Self.showsEdits(session) {
                HStack(spacing: 4) {
                    UndoButton(session: session)
                    RedoButton(session: session)
                }
                .controlTile()
            }
        case .inspector:
            if Self.showsInspector(session) {
                InspectorView(session: session)
            }
        case .options:
            ToolOptions(session: session)
                .frame(minHeight: ToolOptions.minimumHeight, alignment: .topLeading)
        case .action:
            ActionButton(session: session)
        }
    }

    /// The space between tiles (decision 226): the map shows through it.
    static let tileGap = CGFloat(ToolColumn.tileGap)
}

extension View {
    /// Decision 226: a group of the screen's controls in its own glass
    /// (since 2026-10-15; at first a solid tile with an outline).
    func controlTile() -> some View {
        padding(ToolColumnStyle.tilePadding)
            .glassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The thin frame round Build, and round the lines and the figures, in
    /// the dock along the bottom (61.1's look).
    func dockEntryFrame() -> some View {
        padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.panelBorder, lineWidth: 1)
            )
    }
}

/// An icon over a short name, for the tools and the entries beside them
/// (decision 104), and the tools at the map's edge (decision 114).
struct TabLabel: View {
    let systemImage: String
    let title: String
    var isActive = false
    @Environment(\.toolColumnStyle) private var column

    var body: some View {
        if column?.compact == true {
            // 32 points and the style's 4 above and below: the buttons in
            // the room a phone held sideways leaves (decision 123); the
            // names stay the buttons' accessibility labels.
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: column?.buttonWidth)
                .frame(minHeight: 32)
        } else {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                // Decision 106: caption, not caption2, so the name reads on glass.
                Text(verbatim: title)
                    .font(.caption.weight(isActive ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 48, maxWidth: .infinity, minHeight: 40)
            // In the column, one width whether chosen or not: a chosen
            // button's bolder name made it wider (TestFlight, 2026-10-16).
            .frame(width: column?.buttonWidth)
        }
    }
}

/// Decision 226, later (TestFlight, 2026-10-16): the buttons of a tools
/// column (``ToolColumn``) are one size, chosen or not, labelled or, where
/// the column has not the height, icons alone (`compact`), all of them
/// together. `nil` outside a column: the dock's buttons are as wide as
/// their names.
struct ToolColumnStyle: Equatable {
    var compact: Bool
    /// Every button's width: the phone's column, or the wider building
    /// tools beside the map (``ToolColumn/railButtonWidth``).
    var buttonWidth = CGFloat(ToolColumn.buttonWidth)

    static let tilePadding = CGFloat(ToolColumn.tilePadding)
    static let buttonSpacing = CGFloat(ToolColumn.buttonSpacing)
    static let width = CGFloat(ToolColumn.width)
}

extension EnvironmentValues {
    @Entry var toolColumnStyle: ToolColumnStyle?
}

/// The lines and the company's figures, named beside the tools (decision
/// 104). Since decision 106 the lines open only here: the HUD's unnamed
/// icon is gone, and this entry took its name, "Lines", and its place in
/// the tutorial.
private struct QuickEntries: View {
    let session: GameSession
    /// Decision 226: in a column, Data above Lines, so Build, under them,
    /// is nearest the thumb; in a row, Lines first, beside Build.
    let vertical: Bool
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        // In the column (decision 226) no frame of their own, the glass they
        // sit in is it; in the dock a thin frame, as on 61.1.
        if vertical {
            VStack(spacing: ToolColumnStyle.buttonSpacing) {
                data
                lines
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            HStack(spacing: 6) {
                lines
                data
            }
            .dockEntryFrame()
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lines: some View {
        entry(.lines, systemImage: "point.3.connected.trianglepath.dotted",
              title: session.language.text("Lines", "路線"),
              name: Text("Lines"), id: "entry.lines")
            .accessibilityHint("Shows the service lines and their timetables.")
            .tutorialTarget(.linesButton)
    }

    private var data: some View {
        entry(.economy, systemImage: "chart.bar.fill",
              title: session.language.text("Data", "資料"),
              name: Text(verbatim: session.language.text("Open the company's figures", "開啟經營資料")), id: "entry.economy")
    }

    private func entry(_ panel: GameScreenState.Panel, systemImage: String, title: String, name: Text, id: String) -> some View {
        Button {
            screen.panel = panel
        } label: {
            TabLabel(systemImage: systemImage, title: title, isActive: screen.panel == panel)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: screen.panel == panel))
        .frame(minWidth: 44)
        .accessibilityLabel(name)
        .accessibilityIdentifier(id)
    }
}

/// Takes back the last edit (ARCHITECTURE decision 82, MapBuilder's undo
/// button). Disabled while there is nothing to take back: before any edit,
/// and once game time has moved on since, so in practice while paused.
private struct UndoButton: View {
    let session: GameSession

    var body: some View {
        Button {
            session.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .opacity(session.canUndo ? 1 : 0.4)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .disabled(!session.canUndo)
        .accessibilityLabel("Undo")
        .accessibilityHint("Takes back the last edit, refunding what it cost. Only until game time moves on.")
        .accessibilityIdentifier("controls.undo")
    }
}

/// Makes again the edit Undo last took back (decision 184, the
/// simulator's redo). Enabled by the same rule as ``UndoButton``: until a
/// new edit or game time moves on.
private struct RedoButton: View {
    let session: GameSession

    var body: some View {
        Button {
            session.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .opacity(session.canRedo ? 1 : 0.4)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .disabled(!session.canRedo)
        .accessibilityLabel(Text(verbatim: session.language.text("Redo", "重做")))
        .accessibilityHint(Text(verbatim: session.language.text(
            "Makes again the edit Undo took back. Only until another edit or game time moves on.",
            "重新做一次剛才復原的編輯。再做別的編輯或遊戲時間前進後就不能重做。"
        )))
        .accessibilityIdentifier("controls.redo")
    }
}

/// What the active tool needs besides a tap on the map.
private struct ToolOptions: View {
    /// Keeps the panel from jumping in height between tools.
    static let minimumHeight = 116.0

    @Bindable var session: GameSession

    var body: some View {
        switch session.tool {
        case .select:
            Label("Tap Build, then Network, to lay track, platforms and stations. With no tool, a tap on the map only looks.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        case .network:
            NetworkControls(session: session)
        case .train:
            TrainControls(session: session)
        case .building:
            BuildingControls(session: session)
        case .bus:
            BusControls(session: session)
        }
    }
}

/// The bus tool (decision 400, 10i-5): a tap picks the station a route
/// feeds, each next tap a stop on a road; the headway and buses, and what
/// GameCore would make of the route (``BusRoutePreview``). The action
/// button, or the map's ✓, opens it.
private struct BusControls: View {
    let session: GameSession

    var body: some View {
        let language = session.language
        let draft = session.busDraft
        VStack(alignment: .leading, spacing: 8) {
            if let id = draft.route {
                Text(verbatim: language.text("Changing \(BusRouteText.name(id, in: language))", "修改\(BusRouteText.name(id, in: language))"))
                    .font(.footnote.weight(.semibold))
            }
            Label {
                Text(verbatim: hint)
            } icon: {
                Image(systemName: "hand.tap")
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("bus.hint")
            if draft.station != nil {
                Picker(selection: Binding(get: { session.busDraft.headway }, set: { session.setBusDraftHeadway($0) })) {
                    ForEach(headways, id: \.self) { minutes in
                        Text(verbatim: language.text("\(minutes) min", "\(minutes) 分")).tag(minutes)
                    }
                } label: {
                    Text(verbatim: language.text("A bus every", "班距"))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("bus.headway")
                Stepper(value: Binding(get: { session.busDraft.buses }, set: { session.setBusDraftBuses($0) }), in: 1...BusRoute.maximumBuses) {
                    Text(verbatim: language.text("Buses: \(draft.buses)", "公車：\(draft.buses) 輛"))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("bus.count")
            }
            if let preview = session.busPreview {
                ForEach(Array(preview.lines(for: draft, in: language).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.footnote)
                        .monospacedDigit()
                }
                if let problem = preview.problem {
                    Text(verbatim: problem)
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("bus.problem")
                }
            }
            if draft.station != nil {
                Button {
                    session.removeLastBusStop()
                } label: {
                    Label {
                        Text(verbatim: draft.stops.isEmpty
                             ? language.text("Pick another station", "換一座車站")
                             : language.text("Take back the last stop", "收回最後一個站牌"))
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .font(.footnote)
                }
                .disabled(draft.stops.isEmpty && draft.route != nil)
                .accessibilityIdentifier("bus.undoStop")
            }
        }
    }

    /// The headways offered, with the route's own when it is none of them.
    private var headways: [Int64] {
        let own = session.busDraft.headway
        return BusRouteDraft.headwayChoices.contains(own) ? BusRouteDraft.headwayChoices : (BusRouteDraft.headwayChoices + [own]).sorted()
    }

    private var hint: String {
        let language = session.language
        guard let id = session.busDraft.station, let station = session.world.station(id: id) else {
            return language.text(
                "Tap the station the bus route feeds. People beyond walking distance ride it to your trains.",
                "點公車路線要接的車站。走路到不了車站的人會搭它來坐你的車。"
            )
        }
        return language.text(
            "Tap roads for its stops, out from \(station.name). Tap a stop again to take it away.",
            "從\(station.name)往外，點路面放站牌。再點一次站牌就拿掉。"
        )
    }
}

/// The building tool (city building P0-A, decision 92): what a tap on the
/// map puts up, and how many the player has put up. GameCore decides
/// whether a building fits where the player taps. Since P0-C1 (decision 94)
/// it also demolishes, and shows a managed company what building costs and
/// what its buildings earn. Since P0-B (decision 98) it zones cells: tap
/// one, or drag across a rectangle.
private struct BuildingControls: View {
    @Bindable var session: GameSession
    /// A kind's glyph, as large as the subheadline it sits beside.
    @ScaledMetric(relativeTo: .subheadline) private var cardArtSize = 44.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Building mode", selection: $session.buildingMode) {
                ForEach(BuildingToolMode.allCases, id: \.self) { mode in
                    Text(mode.title(in: session.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("building.mode")
            switch session.buildingMode {
            case .build:
                buildOptions
            case .demolish:
                Label("Tap one of your buildings to demolish it. A managed company pays a tenth of what it cost.", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            case .sell:
                sellOptions
            case .zone:
                zoneOptions
            }
            Text(verbatim: session.placedBuildingsText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier("building.count")
            if let economy = session.buildingEconomyText {
                Text(verbatim: economy)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("building.economy")
            }
        }
    }

    @ViewBuilder
    private var buildOptions: some View {
        // Three a row, as the zones: five in one row cut a phone's names to
        // "小…" and "漁…".
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(PlacedBuildingKind.allCases, id: \.self) { kind in
                let isActive = session.buildingKind == kind
                Button {
                    session.buildingKind = kind
                } label: {
                    VStack(spacing: 2) {
                        // Decision 122, later: the kind's picture over its
                        // name, as a building card.
                        Image(kind.cardArt)
                            .resizable()
                            .scaledToFit()
                            .frame(width: cardArtSize, height: cardArtSize)
                            .accessibilityHidden(true)
                        Text(kind.title(in: session.language))
                            .font(.subheadline.weight(isActive ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        // Decision 103: what each costs before its land.
                        if let cost = session.buildingStartingCost(kind) {
                            Text(verbatim: cost.moneyText)
                                .font(.caption2)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                .accessibilityIdentifier("building.kind.\(kind.rawValue)")
                .accessibilityAddTraits(isActive ? .isSelected : [])
                // Decision 376: lesson 9's step points at the hotel.
                .tutorialTarget(kind == .hotel ? .hotelKind : nil)
            }
        }
        // Decision 361: the kind's looks, and what a park or a temple does.
        if session.buildingKind.looks > 1 {
            Picker(selection: $session.buildingLook) {
                ForEach(0..<session.buildingKind.looks, id: \.self) { look in
                    Text(verbatim: session.buildingKind.lookTitle(look, in: session.language) ?? "\(look + 1)").tag(look)
                }
            } label: {
                Text(verbatim: session.language.text("Look", "外觀"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("building.look")
        }
        if let effect = session.buildingKind.effectText(in: session.language) {
            Label {
                Text(verbatim: effect)
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("building.effect")
        }
        // Decision 103: one tap builds, for one building after another.
        Toggle(isOn: $session.buildingBuildsOnTap) {
            Text(verbatim: session.language.text("Build where I tap", "點一下直接蓋"))
                .font(.footnote)
        }
        .accessibilityIdentifier("building.buildsOnTap")
        if let preview = session.buildingPreview {
            // Decision 95: the site's cost and what it pulls down, or why
            // it cannot stand there; the action button builds it.
            if let text = session.buildingPreviewText {
                Text(verbatim: text)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(preview.problem == nil ? Theme.textPrimary : Theme.error)
                    .accessibilityIdentifier("building.preview")
            }
            if preview.problem == nil {
                Label {
                    Text(verbatim: session.language.text(
                        "Tap it again to build, or drag it somewhere else.",
                        "再點一下就蓋，或把它拖到別的地方。"
                    ))
                } icon: {
                    Image(systemName: "hand.tap")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
        } else {
            // Short: where it cannot stand, the preview says when it is so.
            Label("Tap the map to choose a site. A city building in the way is bought out.", systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if let quote = session.buildingQuoteText {
                Text(verbatim: quote)
                    .font(.footnote)
                    .monospacedDigit()
                    .accessibilityIdentifier("building.quote")
            }
        }
    }
}

extension BuildingControls {
    /// Decision 130: what the building tapped would sell for, part by part,
    /// and the gain or loss against its book value; the action button or
    /// the map's pill sells it.
    @ViewBuilder
    private var sellOptions: some View {
        if let sale = session.salePreview {
            let lines = session.salePreviewLines
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let isLoss = index == lines.count - 1 && sale.quote.gain < .zero && session.world.accounts.mode == .management
                    Text(verbatim: line)
                        .font(index == 0 || index == lines.count - 1 ? .footnote.weight(.semibold) : .footnote)
                        .foregroundStyle(isLoss ? Theme.error : Theme.textPrimary)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("building.sale")
            Label {
                Text(verbatim: session.language.text(
                    "The city takes it over: its people stay.", "賣掉的建物留給城市，居民與就業照舊。"
                ))
            } icon: {
                Image(systemName: "building.2")
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        } else {
            Label {
                Text(verbatim: session.language.text(
                    "Tap one of your buildings to see what it would sell for.", "點選自己的建物，先看售價與損益。"
                ))
            } icon: {
                Image(systemName: "hand.tap")
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Decision 98: the zones, and clearing them, three a row; what the
    /// chosen one does, and how many cells are zoned.
    @ViewBuilder
    private var zoneOptions: some View {
        let choices: [Zone?] = Zone.allCases.map { $0 } + [nil]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, zone in
                let isActive = session.zoningZone == zone
                Button {
                    session.zoningZone = zone
                } label: {
                    HStack(spacing: 4) {
                        if let zone {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(CityMap.zoneColor(zone)))
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "eraser")
                                .font(.caption.weight(.semibold))
                        }
                        Text(verbatim: zone?.title(in: session.language) ?? session.language.text("Clear", "清除"))
                            .font(.caption.weight(isActive ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                .accessibilityIdentifier("building.zone.\(zone?.rawValue ?? "clear")")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        Label {
            Text(verbatim: session.zoningHelpText)
        } icon: {
            Image(systemName: "hand.draw")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        Text(verbatim: session.zonedCellsText)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .accessibilityIdentifier("building.zoneCount")
        // Decision 139: what the city is short of.
        if let demand = session.cityDemandText {
            Text(verbatim: demand)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier("building.cityDemand")
        }
    }
}

extension PlacedBuildingKind {
    /// The kind's glyph, the same on its button and on the map
    /// (decision 121).
    var mapGlyph: MapGlyph {
        switch self {
        case .house: .house
        case .shop: .shop
        case .office: .office
        case .wharf: .wharf
        case .marina: .marina
        case .departmentStore: .departmentStore
        case .hotel: .hotel
        case .amusementPark: .amusementPark
        case .park: .park
        case .temple: .temple
        case .school: .school
        case .hospital: .hospital
        case .nightMarket: .nightMarket
        }
    }

    /// The kind's picture on its building card (decision 122, later): a
    /// many-coloured illustration, where the map keeps ``mapGlyph``.
    var cardArt: String {
        switch self {
        case .house: "BuildingHouse"
        case .shop: "BuildingShop"
        case .office: "BuildingOffice"
        case .wharf: "BuildingWharf"
        case .marina: "BuildingMarina"
        case .departmentStore: "BuildingDepartmentStore"
        case .hotel: "BuildingHotel"
        case .amusementPark: "BuildingAmusementPark"
        case .park: "BuildingPark"
        case .temple: "BuildingTemple"
        case .school: "BuildingSchool"
        case .hospital: "BuildingHospital"
        case .nightMarket: "BuildingNightMarket"
        }
    }
}

/// Applies the train tool to the selected station, or, with the network
/// tool, builds, adds or removes what its taps picked. Shows the cost read
/// from the world's economy or GameCore's preview; GameCore decides whether
/// the action is allowed.
private struct ActionButton: View {
    let session: GameSession

    var body: some View {
        if let title {
            Button {
                act()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.tool.systemImage)
                        .font(.body.weight(.bold))
                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ThemeProminentButtonStyle(isDestructive: isRemoval))
            .disabled(!isReady)
            .accessibilityHint(hint)
            .accessibilityIdentifier(TutorialTarget.actionButton.rawValue)
            .tutorialTarget(.actionButton)
        }
    }

    private var isRemoval: Bool {
        session.tool == .network && session.networkMode == .remove
    }

    private var isReady: Bool {
        if session.tool == .bus { return session.busPreview?.canOpen ?? false }
        if session.tool == .building {
            if session.buildingMode == .sell { return session.salePreview != nil }
            return session.buildingPreview.map { $0.problem == nil } ?? false
        }
        guard session.tool == .network else { return session.selectedPoint != nil }
        switch session.networkMode {
        case .build: return session.networkPreview != nil
        case .platform, .remove: return session.networkEdgePoint != nil
        case .passingLoop: return session.networkLoopPreview.map { $0.problem == nil } ?? false
        case .depot: return session.networkDepotPreview.map { $0.problem == nil } ?? false
        }
    }

    private func act() {
        if session.tool == .bus {
            session.confirmBusRoute()
            return
        }
        if session.tool == .building {
            if session.buildingMode == .sell {
                session.confirmSale()
            } else {
                session.confirmBuilding()
            }
            return
        }
        guard session.tool == .network else {
            session.applyTool()
            return
        }
        switch session.networkMode {
        case .build: session.buildNetworkTrack()
        case .platform: session.addNetworkPlatform()
        case .remove: session.removeNetworkEdge()
        case .passingLoop: session.addPassingLoop()
        case .depot: session.addDepotYard()
        }
    }

    private var hint: String {
        guard !isReady else { return "" }
        switch session.tool {
        case .network: return String(localized: "Tap the map first.")
        case .building:
            if session.buildingMode == .sell { return session.language.text("Tap one of your buildings first.", "請先點選自己的建物。") }
            return String(localized: "Tap the map where it goes first.")
        case .bus: return session.language.text("Tap a station, then roads for the stops.", "先點車站，再點路面放站牌。")
        case .select, .train: return String(localized: "Select a station on the map first.")
        }
    }

    fileprivate var title: String? {
        switch session.tool {
        case .select: return nil
        case .building:
            // Decision 95: a tap chooses the site, this builds there;
            // demolishing acts on the tap itself. Decision 130: a tap
            // chooses the building to sell, this sells it.
            switch session.buildingMode {
            case .build:
                guard let cost = session.buildingPreview?.cost, cost > .zero else { return String(localized: "Build") }
                return String(localized: "Build · \(cost.moneyText)")
            case .sell:
                guard let price = session.salePreview?.quote.price, price > .zero else { return session.language.text("Sell", "出售") }
                return session.language.text("Sell · \(price.moneyText)", "出售 · \(price.moneyText)")
            case .demolish, .zone:
                return nil
            }
        case .network:
            switch session.networkMode {
            case .build:
                guard let cost = session.networkPreview?.cost else { return String(localized: "Build Track") }
                return String(localized: "Build Track · \(cost.moneyText)")
            case .platform: return String(localized: "Add Platform")
            case .remove: return String(localized: "Remove Track")
            case .passingLoop:
                // Decision 204: the loop and its signal station, for what.
                guard let cost = session.networkLoopPreview?.cost else { return session.language.text("Add Passing Loop", "加待避線") }
                return session.language.text("Add Passing Loop · \(cost.moneyText)", "加待避線 · \(cost.moneyText)")
            case .depot:
                // Decision 214: the sidings and the depot, for what.
                guard let cost = session.networkDepotPreview?.cost else { return session.language.text("Lay Depot Sidings", "鋪機廠停車線") }
                return session.language.text("Lay Depot Sidings · \(cost.moneyText)", "鋪機廠停車線 · \(cost.moneyText)")
            }
        case .bus:
            // Decision 400, 10i-5: the route drawn, or the edited one's stops.
            let language = session.language
            let what = session.busDraft.route == nil ? language.text("Open Bus Route", "開公車路線") : language.text("Save Bus Route", "儲存公車路線")
            guard let price = session.busPreview?.price, price > .zero else { return what }
            return "\(what) · \(price.moneyText)"
        case .train:
            // Placing and sending both act on the selected train.
            guard let train = session.selectedTrain else { return nil }
            return train.position == nil ? String(localized: "Place \(train.name) Here") : String(localized: "Send \(train.name) Here")
        }
    }
}

/// The result of the last action, shown over the top of the map and
/// announced to VoiceOver, since focus stays on the button that caused it.
struct StatusBanner: View {
    let session: GameSession
    /// Whether this banner tells VoiceOver of a new message. The map's
    /// banner does; a panel's beside it shows the same message and stays
    /// quiet, so VoiceOver reads it once (decision 184, later).
    var announces = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message = session.message {
                banner(for: message)
                    // Decision 253: in from the top, out faster.
                    .transition(.card(from: .top, reduceMotion: reduceMotion))
            }
        }
        // By the serial, not the message: the same text posted again (a
        // second save) is announced again and waits its own while.
        .onChange(of: session.messageSerial) {
            if announces, let message = session.message {
                AccessibilityNotification.Announcement(message.text).post()
            }
        }
        // Every message clears itself (``StatusMessage/autoDismissDelay``),
        // so none stays over the map or a panel's last row; a newer message
        // restarts the wait. While VoiceOver runs a problem stays until
        // dismissed, as before decision 106.
        .task(id: session.messageSerial) {
            let serial = session.messageSerial
            guard let message = session.message else { return }
            if message.kind == .failure, UIAccessibility.isVoiceOverRunning { return }
            try? await Task.sleep(for: message.autoDismissDelay)
            guard !Task.isCancelled else { return }
            session.dismissMessage(posted: serial)
        }
    }

    private func banner(for message: StatusMessage) -> some View {
        let isSuccess = message.kind == .success
        let kindName = isSuccess ? String(localized: "Done") : String(localized: "Problem")
        let tintColor = isSuccess ? Theme.success : Theme.warning
        // Read here: the animators' closures run off the main actor.
        let reduceMotion = self.reduceMotion
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tintColor)
                .accessibilityLabel(kindName)
            Text(message.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // Decision 327: a train standing on no line that is in the way
            // is sold from here (Undo brings it back).
            if let id = message.sellableTrain, let train = session.world.train(id: id) {
                Button {
                    session.sellTrain(id)
                } label: {
                    Text(verbatim: session.language.text(
                        "Sell \(train.name) \(session.world.trainSaleQuote(id).moneyText)",
                        "出售 \(train.name) \(session.world.trainSaleQuote(id).moneyText)"
                    ))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("banner.sellTrain")
            }
            // Decision 336: land not bought yet; this ends building and
            // starts choosing a tile.
            if session.offersMapExpansion(for: message.text) {
                Button {
                    session.startChoosingMapTile()
                } label: {
                    Text(verbatim: session.language.text("Expand Map", "擴建地圖"))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("banner.expandMap")
            }
            Button {
                session.dismissMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(Theme.panelBorder, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tintColor.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        // The same message again, or a newer one, moves the banner rather
        // than stacking another (the reference's `notify()`). Decision 253:
        // good news bumps it a little; a refusal shakes it sideways
        // (``RefusalShake``); with Reduce Motion neither.
        .phaseAnimator([false, true], trigger: session.messageSerial) { banner, isBumped in
            banner.scaleEffect(isBumped && isSuccess && !reduceMotion ? 1.04 : 1)
        } animation: { _ in MotionRule.confirm.animation }
        .keyframeAnimator(initialValue: 0.0, trigger: session.messageSerial) { banner, progress in
            banner.offset(x: isSuccess || reduceMotion ? 0 : RefusalShake.offset(at: progress))
        } keyframes: { _ in
            MoveKeyframe(0.0)
            LinearKeyframe(1.0, duration: MotionRule.refuse.seconds)
        }
        .padding(10)
    }
}

extension ConstructionTool {
    var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .network: "point.topleft.down.curvedto.point.bottomright.up"
        case .train: "train.side.front.car"
        case .building: "building.2"
        case .bus: "bus.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .select: String(localized: "Select tool")
        case .network: String(localized: "Track network tool")
        case .train: String(localized: "Train tool")
        case .building: String(localized: "Building tool")
        case .bus: String(localized: "Bus tool")
        }
    }
}
