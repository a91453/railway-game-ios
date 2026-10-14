import GameCore
import GamePresentation
import SwiftUI

/// The network postcard (decision 215): the card itself, laid out by
/// ``PostcardLayout`` at its own size, so the picture shared is the same on
/// every device. The map is the game's own drawing (``MapArt``): the land,
/// the town, the track, the lines in their colours, the stations with their
/// name plates and the trains car by car, fitted to what is built. It is
/// never Apple's or OpenStreetMap's base map, which cannot be drawn into a
/// picture; ``NetworkPostcard/credit`` keeps the railways' credit on a
/// real-world map.
struct PostcardCard: View {
    let postcard: NetworkPostcard
    let world: GameWorld
    let skyline: CitySkyline?
    let language: DisplayLanguage
    @Environment(\.regionStyle) private var region

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius)
                .fill(Theme.panel)
            text(postcard.eyebrow, in: PostcardLayout.eyebrow, size: PostcardLayout.eyebrowSize, weight: .bold, colour: Theme.primary, tracking: 2)
            text(postcard.title, in: PostcardLayout.title, size: PostcardLayout.titleSize, weight: .bold, colour: Theme.textPrimary)
            text(postcard.subtitle, in: PostcardLayout.subtitle, size: PostcardLayout.subtitleSize, weight: .medium, colour: Theme.textSecondary)
            map
                .frame(width: PostcardLayout.map.width, height: PostcardLayout.map.height)
                .clipShape(RoundedRectangle(cornerRadius: PostcardLayout.mapCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: PostcardLayout.mapCornerRadius).strokeBorder(Palette.ink, lineWidth: 1.7))
                .offset(x: PostcardLayout.map.x, y: PostcardLayout.map.y)
            if !postcard.credit.isEmpty {
                text(postcard.credit, in: PostcardLayout.credit, size: PostcardLayout.creditSize, weight: .regular, colour: Theme.textSecondary)
            }
            ForEach(Array(postcard.figures.enumerated()), id: \.offset) { index, figure in
                let frame = PostcardLayout.figure(index)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: figure.value)
                        .font(.system(size: PostcardLayout.figureValueSize, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: figure.label)
                        .font(.system(size: PostcardLayout.figureLabelSize, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .frame(width: frame.width, height: frame.height, alignment: .leading)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 7))
                .offset(x: frame.x, y: frame.y)
            }
            stationMaster
        }
        .frame(width: PostcardLayout.size.width, height: PostcardLayout.size.height)
        .overlay(RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius).strokeBorder(Palette.ink, lineWidth: PostcardLayout.border))
        .clipShape(RoundedRectangle(cornerRadius: PostcardLayout.cornerRadius))
    }

    private func text(
        _ words: String, in frame: PostcardLayout.Frame, size: Double, weight: Font.Weight, colour: Color, tracking: Double = 0
    ) -> some View {
        Text(verbatim: words)
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: frame.width, height: frame.height, alignment: .leading)
            .offset(x: frame.x, y: frame.y)
    }

    /// The map's layers 10–35 and 50 (`docs/MAP_LAYERS.md`), at noon, with
    /// no waits, counts or rings: a picture of the network, not of its
    /// problems.
    private var map: some View {
        Canvas { context, size in
            let projection = PostcardProjection(region: postcard.region, size: ScreenSize(width: size.width, height: size.height))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.land))
            MapArt.drawBase(
                bounds: world.bounds, drawsLand: true, skyline: skyline, growth: nil, growthOnly: false, layer: nil,
                projection: projection, in: context
            )
            MapArt.drawMap(
                world,
                selectedTrainID: nil,
                projection: projection,
                edges: [:],
                layers: MapLayerPreferences(showsStationNames: true, showsWaitingCounts: false, showsCatchmentRings: false),
                lines: LineMap(world: world),
                labels: StationLabels(world: world),
                in: context
            )
            MapArt.drawTrains(
                TrainMotion(world: world, time: 0), progress: 1, selectedTrainID: nil, lights: 0, plain: false,
                traffic: TrafficOverlay(), language: language, projection: projection, in: context
            )
        }
    }

    private var stationMaster: some View {
        let frame = PostcardLayout.stationMaster
        return Image(region.stationMasterArt + StationMasterMood.happy.rawValue)
            .resizable()
            .scaledToFill()
            .frame(width: frame.width, height: frame.height)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
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

/// "Make a Postcard" (decision 215), from the game menu's More: the card as
/// it will be shared, the company's name to write on it, light or dark, and
/// the share button, which hands the picture (1200 by 1500 pixels) to the
/// system's share sheet.
struct PostcardSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var screenScheme
    @Environment(\.regionStyle) private var region
    /// The name the player last wrote, kept on the device.
    @AppStorage("postcard.companyName") private var companyName = ""
    @State private var appearance: PostcardAppearance?
    @State private var skyline: CitySkyline?
    @State private var picture: Image?

    private var language: DisplayLanguage { session.language }
    private var chosen: PostcardAppearance { appearance ?? (screenScheme == .dark ? .dark : .light) }

    var body: some View {
        NavigationStack {
            let postcard = NetworkPostcard(world: session.world, companyName: companyName, in: language)
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
                        ShareLink(item: picture, preview: SharePreview(Text(verbatim: postcard.title), image: picture)) {
                            Label {
                                Text(verbatim: language.text("Share Postcard", "分享明信片"))
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ThemeProminentButtonStyle())
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
                let world = session.world
                if world.geoAnchor == nil, !world.land.isEmpty {
                    skyline = await Task.detached(priority: .userInitiated) { CitySkyline(world: world) }.value
                }
                render()
            }
            .onChange(of: companyName) { render() }
            .onChange(of: chosen) { render() }
        }
    }

    private func card(_ postcard: NetworkPostcard, appearance: PostcardAppearance) -> some View {
        PostcardCard(postcard: postcard, world: session.world, skyline: skyline, language: language)
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.regionStyle, region)
    }

    /// The picture to share, at ``PostcardLayout/scale``.
    private func render() {
        let postcard = NetworkPostcard(world: session.world, companyName: companyName, in: language)
        let renderer = ImageRenderer(content: card(postcard, appearance: chosen))
        renderer.scale = PostcardLayout.scale
        picture = renderer.uiImage.map { Image(uiImage: $0) }
    }
}
