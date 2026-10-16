import GameCore
import GamePresentation
import SwiftUI

/// The postcard's map, worked out off the main actor (decision 215, v2):
/// the route map's strokes, dots and names, and on a real-world map the sea.
struct PostcardMap: Sendable {
    let network: PostcardNetwork
    let sea: PostcardSea?

    init(world: GameWorld, water: WaterGrid?) {
        let postcard = NetworkPostcard(world: world, companyName: "", in: .english)
        let frame = PostcardLayout.parts(of: postcard).map
        let size = ScreenSize(width: frame.width, height: frame.height)
        let projection = PostcardProjection(region: postcard.region, size: size)
        network = PostcardNetwork(world: world, lines: LineMap(world: world), projection: projection, size: size)
        if let water, let realWorld = RealWorldFrame(world: world) {
            sea = PostcardSea(water: water, frame: realWorld, projection: projection, size: size)
        } else {
            sea = nil
        }
    }
}

/// The network postcard (decision 215): the card itself, laid out by
/// ``PostcardLayout`` at its own size, so the picture shared is the same on
/// every device. v2 (the planning session's choice C, 2026-10-14): the
/// station master's head beside the title, inside the card; the map framed
/// to the network, drawn as a route map (``PostcardNetwork``: the lines
/// side by side, the stations as dots, the names on plates off the lines),
/// on the game's own ground (the town on its own map, the sea on a
/// real-world one); the legend and at most three figures beside a tall
/// network or under a wide one. It is never Apple's or OpenStreetMap's base
/// map, which cannot be drawn into a picture; ``NetworkPostcard/credit``
/// keeps the railways' credit on a real-world map.
struct PostcardCard: View {
    let postcard: NetworkPostcard
    let world: GameWorld
    let map: PostcardMap?
    let skyline: CitySkyline?
    @Environment(\.regionStyle) private var region

    var body: some View {
        let parts = PostcardLayout.parts(of: postcard)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius)
                .fill(Theme.panel)
            stationMaster
            text(postcard.title, in: PostcardLayout.title, size: PostcardLayout.titleSize, weight: .heavy, colour: Theme.textPrimary)
            text(postcard.subtitle, in: PostcardLayout.subtitle, size: PostcardLayout.subtitleSize, weight: .medium, colour: Theme.textSecondary)
            mapView
                .frame(width: parts.map.width, height: parts.map.height)
                .clipShape(RoundedRectangle(cornerRadius: PostcardLayout.mapCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: PostcardLayout.mapCornerRadius).strokeBorder(Palette.ink, lineWidth: 1.7))
                .offset(x: parts.map.x, y: parts.map.y)
            ForEach(Array(zip(parts.legend, postcard.legendEntries(slots: parts.legend.count)).enumerated()), id: \.offset) { _, entry in
                legend(entry.1, in: entry.0)
            }
            ForEach(Array(zip(parts.figures, postcard.figures).enumerated()), id: \.offset) { _, entry in
                figure(entry.1, in: entry.0)
            }
            if !postcard.credit.isEmpty {
                text(postcard.credit, in: PostcardLayout.credit, size: PostcardLayout.creditSize, weight: .regular, colour: Theme.textSecondary)
            }
            text(postcard.wordmark, in: PostcardLayout.wordmark, size: PostcardLayout.wordmarkSize, weight: .heavy, colour: Theme.primary, tracking: 1, alignment: .trailing)
        }
        .frame(width: PostcardLayout.size.width, height: PostcardLayout.size.height)
        .overlay(RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius).strokeBorder(Palette.ink, lineWidth: PostcardLayout.border))
        .clipShape(RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius))
    }

    private func text(
        _ words: String, in frame: PostcardLayout.Frame, size: Double, weight: Font.Weight, colour: Color, tracking: Double = 0,
        alignment: Alignment = .leading
    ) -> some View {
        Text(verbatim: words)
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: frame.width, height: frame.height, alignment: alignment)
            .offset(x: frame.x, y: frame.y)
    }

    private func figure(_ figure: NetworkPostcard.Figure, in frame: PostcardLayout.Frame) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: figure.value)
                .font(.system(size: PostcardLayout.figureValueSize, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: figure.label)
                .font(.system(size: PostcardLayout.figureLabelSize, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 10)
        .frame(width: frame.width, height: frame.height, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        .offset(x: frame.x, y: frame.y)
    }

    /// A line's badge (decision 216) and name, or how many more lines.
    private func legend(_ entry: NetworkPostcard.LegendEntry, in frame: PostcardLayout.Frame) -> some View {
        HStack(spacing: 5) {
            switch entry {
            case .line(let line):
                LineCodeBadge(code: line.code, color: Palette.lineColor(line.id, custom: line.color), size: .small)
                Text(verbatim: line.name)
            case .more(let count):
                Text(verbatim: "+\(count)")
            }
        }
        .font(.system(size: PostcardLayout.legendSize, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 4)
        .frame(width: frame.width, height: frame.height, alignment: .leading)
        .offset(x: frame.x, y: frame.y)
    }

    /// The ground (layers 10–15 of `docs/MAP_LAYERS.md`: the land and, on
    /// the game's own map, the town), the sea on a real-world map, then the
    /// route map: at noon, with no trains, waits, counts or rings.
    private var mapView: some View {
        Canvas { context, size in
            let projection = PostcardProjection(region: postcard.region, size: ScreenSize(width: size.width, height: size.height))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.land))
            MapArt.drawBase(
                bounds: world.bounds, drawsLand: true, skyline: skyline, growth: nil, growthOnly: false, layer: nil,
                projection: projection, in: context
            )
            guard let map else { return }
            if let sea = map.sea {
                var water = Path()
                for run in sea.runs {
                    // A hair over a cell, so the cells meet without seams.
                    water.addRect(CGRect(
                        x: Double(run.columns.lowerBound) * sea.cell, y: Double(run.row) * sea.cell,
                        width: Double(run.columns.count) * sea.cell + 0.05, height: sea.cell + 0.05
                    ))
                }
                context.fill(water, with: .color(Palette.water))
            }
            drawNetwork(map.network, in: context)
        }
    }

    private func drawNetwork(_ network: PostcardNetwork, in context: GraphicsContext) {
        func path(_ points: [ScreenPoint]) -> Path {
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.x, y: $0.y) })
            return path
        }
        let round = { (width: Double) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
        for edge in network.track {
            context.stroke(path(edge), with: .color(Palette.track), style: round(PostcardNetwork.trackWidth))
        }
        for stroke in network.strokes {
            context.stroke(path(stroke.points), with: .color(Palette.markerFill), style: round(network.lineWidth + PostcardNetwork.casing))
        }
        for stroke in network.strokes {
            context.stroke(path(stroke.points), with: .color(Palette.lineColor(stroke.line, custom: stroke.color)), style: round(network.lineWidth))
        }
        for dot in network.dots {
            let capsule = path([dot.from, dot.to])
            let radius = PostcardNetwork.dotRadius
            context.stroke(capsule, with: .color(Palette.ink), style: round(2 * (radius + PostcardNetwork.dotEdge)))
            context.stroke(capsule, with: .color(Palette.markerFill), style: round(2 * radius))
        }
        for label in network.labels {
            if let leader = label.leader {
                context.stroke(path(leader), with: .color(Palette.ink), lineWidth: 0.8)
            }
        }
        for label in network.labels {
            let rect = CGRect(x: label.frame.x, y: label.frame.y, width: label.frame.width, height: label.frame.height)
            // Decision 205's name plate: the land at 80 %, corners of 3.
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Palette.land.opacity(0.8)))
            context.draw(
                Text(verbatim: label.name).font(.system(size: PostcardNetwork.labelSize, weight: .semibold)).foregroundStyle(Palette.ink),
                at: CGPoint(x: rect.midX, y: rect.midY)
            )
        }
    }

    /// The station master's head (``StationMasterAvatar``'s zoom), happy,
    /// in a rounded square beside the title: inside the card, over nothing.
    private var stationMaster: some View {
        let frame = PostcardLayout.stationMaster
        let corner = RoundedRectangle(cornerRadius: PostcardLayout.stationMasterCornerRadius)
        return Image(region.stationMasterArt + StationMasterMood.happy.rawValue)
            .resizable()
            .scaledToFill()
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(1.45, anchor: UnitPoint(x: 0.44, y: 0.3))
            .clipShape(corner)
            .overlay(corner.strokeBorder(Palette.ink, lineWidth: 1.5))
            .offset(x: frame.x, y: frame.y)
    }
}

/// The light and dark postcards (decision 215).
enum PostcardAppearance: String, CaseIterable, Identifiable {
    case light, dark

    var id: Self { self }

    var colorScheme: ColorScheme { self == .light ? .light : .dark }

    func title(in language: DisplayLanguage) -> String {
        switch self {
        case .light: language.text("Light", "淺色")
        case .dark: language.text("Dark", "深色")
        }
    }
}

/// What the picture to share was drawn with (``PostcardSheet``): the
/// company's name and light or dark, once the map was worked out.
private struct PostcardPictureKey: Equatable {
    let companyName: String
    let appearance: PostcardAppearance
    let mapReady: Bool
}

/// The picture to share, its title, and what it was drawn with.
private struct PostcardPicture {
    let key: PostcardPictureKey
    let title: String
    let image: Image
}

/// "Make a Postcard" (decision 215), from the game menu: the card as
/// it will be shared, the company's name to write on it, light or dark, and
/// the share button, which hands the picture (1200 by 1500 pixels) to the
/// system's share sheet. The card shows the network as it was when the
/// sheet opened, and the picture shared is drawn from that same moment:
/// the game running underneath changes neither.
struct PostcardSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var screenScheme
    @Environment(\.regionStyle) private var region
    /// The name the player last wrote, kept on the device.
    @AppStorage("postcard.companyName") private var companyName = ""
    @State private var appearance: PostcardAppearance?
    /// The world when the sheet opened: the card and the picture are both
    /// drawn from it, not redrawn on every tick of the game.
    @State private var world: GameWorld
    @State private var skyline: CitySkyline?
    @State private var map: PostcardMap?
    @State private var picture: PostcardPicture?

    init(session: GameSession) {
        self.session = session
        _world = State(initialValue: session.world)
    }

    private var language: DisplayLanguage { session.language }
    private var chosen: PostcardAppearance { appearance ?? (screenScheme == .dark ? .dark : .light) }

    var body: some View {
        NavigationStack {
            let postcard = NetworkPostcard(world: world, companyName: companyName, in: language)
            let key = PostcardPictureKey(companyName: companyName, appearance: chosen, mapReady: map != nil)
            ScrollView {
                VStack(spacing: 16) {
                    GeometryReader { proxy in
                        let scale = min(1, proxy.size.width / PostcardLayout.size.width)
                        card(postcard, appearance: chosen)
                            .scaleEffect(scale, anchor: .top)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }
                    .aspectRatio(PostcardLayout.size.width / PostcardLayout.size.height, contentMode: .fit)
                    .frame(maxWidth: PostcardLayout.size.width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: ([postcard.title, postcard.subtitle] + postcard.figures.map { "\($0.value) \($0.label)" }).joined(separator: ", ")))
                    .accessibilityIdentifier("postcard.card")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: language.text("Company name", "公司名稱"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        TextField(NetworkPostcard.defaultCompanyName(in: language), text: $companyName)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .accessibilityIdentifier("postcard.name")
                    }
                    Picker(selection: Binding(get: { chosen }, set: { appearance = $0 })) {
                        ForEach(PostcardAppearance.allCases) { option in
                            Text(verbatim: option.title(in: language)).tag(option)
                        }
                    } label: {
                        Text(verbatim: language.text("Appearance", "外觀"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("postcard.appearance")

                    if let picture {
                        ShareLink(item: picture.image, preview: SharePreview(Text(verbatim: picture.title), image: picture.image)) {
                            Label {
                                Text(verbatim: language.text("Share Postcard", "分享明信片"))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ThemeProminentButtonStyle())
                        // Until the picture is drawn again with the name
                        // and look shown, so what is shared is the card above.
                        .disabled(picture.key != key)
                        .accessibilityIdentifier("postcard.share")
                    } else {
                        ProgressView()
                    }
                }
                .padding()
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle(language.text("Network Postcard", "路網明信片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("postcard.done")
                }
            }
            .task {
                // The town under the network, as the map draws it; not on a
                // real-world map, whose houses are the base map's.
                let world = world
                if world.geoAnchor == nil, !world.land.isEmpty {
                    skyline = await Task.detached(priority: .userInitiated) { CitySkyline(world: world) }.value
                }
                // The route map and the sea (decision 215, v2): the lines'
                // journeys and the names' places take a moment on a large
                // network.
                let water = session.water
                map = await Task.detached(priority: .userInitiated) { PostcardMap(world: world, water: water) }.value
            }
            // The picture to share: once the map is worked out, at once for
            // a new look, and a moment after the name stops changing, not
            // on every keystroke.
            .task(id: key) {
                guard key.mapReady else { return }
                if let picture, picture.key.companyName != key.companyName {
                    do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                }
                render(key)
            }
        }
    }

    private func card(_ postcard: NetworkPostcard, appearance: PostcardAppearance) -> some View {
        PostcardCard(postcard: postcard, world: world, map: map, skyline: skyline)
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.regionStyle, region)
    }

    /// The picture to share, at ``PostcardLayout/scale``, as the card
    /// shows with `key`'s name and look.
    private func render(_ key: PostcardPictureKey) {
        let postcard = NetworkPostcard(world: world, companyName: key.companyName, in: language)
        let renderer = ImageRenderer(content: card(postcard, appearance: key.appearance))
        renderer.scale = PostcardLayout.scale
        picture = renderer.uiImage.map { PostcardPicture(key: key, title: postcard.title, image: Image(uiImage: $0)) }
    }
}
