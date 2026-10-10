import GameCore
import GamePresentation
import MapLibre
import SwiftUI

/// OpenStreetMap's map under a real-world game's railway (ARCHITECTURE
/// decisions 97 and 151, ROADMAP E3): vector tiles drawn by MapLibre Native,
/// the map engine of the `Ci/` reference, in the game's own style
/// (``BaseMapStyle``, light or dark). In Taiwan the tiles are the ones the
/// app bundles (`Resources/BaseMap/`, from the same OpenStreetMap as the
/// game's water and zones; no network needed), elsewhere OpenFreeMap's. The
/// map style menu's OpenStreetMap; Apple's map (``AppleMapBackground``) stays
/// the default.
///
/// Like Apple's map it follows the game's camera, top-down and north up
/// (``OpenStreetMapBase/camera(of:in:width:height:)``), takes no gestures of
/// its own, and keeps the band at its bottom (``AppleMapBackground/attributionHeight``)
/// for the credit OpenFreeMap asks for and MapLibre's attribution button,
/// which the game draws round (decision 120).
/// Its place labels are in the player's language
/// (``OpenStreetMapBase/labelText(in:)``), and Taiwan's real railways are
/// drawn on it as on Apple's: over the roads, under the labels.
struct OSMMapBackground: UIViewRepresentable {
    let realWorld: RealWorldFrame
    /// The game's camera, whose view is this one.
    let camera: PlanCamera
    /// Taiwan's railways, `nil` if the app's copy cannot be read.
    let railways: RealRailways?
    /// Taiwan's water (``WaterGrid``), which says whether the map is in
    /// Taiwan and draws the bundled tiles (decision 151).
    let water: WaterGrid?
    let trackStyle: RealRailways.TrackStyle
    let language: DisplayLanguage
    /// The game's stations (decision 123), so the map's place names make
    /// way for the names the game draws under them.
    let stations: [StationMark]
    /// The screen's safe area (decision 120): the map reaches the screen's
    /// edges, and the credit and attribution button keep inside this.
    let safeArea: EdgeInsets
    /// Told where the attribution button and the credit are
    /// (``AppleMapBackground/onAttributionFrames``).
    let onAttributionFrames: @MainActor ([CGRect]) -> Void

    func makeUIView(context: Context) -> FollowingMapLibreView {
        FollowingMapLibreView(frame: .zero)
    }

    func updateUIView(_ map: FollowingMapLibreView, context: Context) {
        let dark = context.environment.colorScheme == .dark
        let look = FollowingMapView.RailwayLook(
            anchor: realWorld.anchor,
            reach: FollowingMapView.railwayReach(of: camera.mapRegion),
            style: trackStyle,
            theme: dark ? .dark : .light
        )
        let taiwan = BaseMapStyle.drawsTaiwan(anchor: realWorld.anchor, water: water) && BaseMapFiles.tiles != nil
        map.show(
            style: BaseMapFiles.styleAddress(taiwan: taiwan, dark: dark) ?? OpenStreetMapBase.styleURL(dark: dark),
            language: language,
            railways: railways,
            look: look,
            credits: (
                taiwan ? DataSourceCredits.bundledBaseMap(in: language) : DataSourceCredits.openStreetMapBaseMap(in: language),
                DataSourceCredits.railwaysOnMap(in: language)
            )
        )
        map.stations = stations
        map.screenSafeArea = safeArea
        map.onAttributionFrames = onAttributionFrames
        map.follow(realWorld, camera: camera)
    }

    /// A station of the game, where the map has it, and the name the game
    /// draws there.
    struct StationMark: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// The marks of `world`'s stations in `frame`.
    static func stationMarks(of world: GameWorld, in frame: RealWorldFrame) -> [StationMark] {
        world.stations.map { station in
            let place = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
            return StationMark(name: station.name, latitude: place.latitude, longitude: place.longitude)
        }
    }
}

/// A MapLibre map view that shows what the game's camera shows, with the
/// labels and railways the game asks for: set again whenever the camera,
/// the style or its own size changes, and once a style has loaded.
final class FollowingMapLibreView: MLNMapView {
    private var placement: (realWorld: RealWorldFrame, camera: PlanCamera)?
    /// The style asked for, and whether it has loaded: layers go only into
    /// a loaded style.
    private var styleAddress: String?
    private var styleLoaded = false
    private var language: DisplayLanguage = .english
    private var railways: RealRailways?
    private var railwayLook: FollowingMapView.RailwayLook?
    /// What the loaded style shows: its labels' language and its railways.
    private var labelled: DisplayLanguage?
    private var drawn: FollowingMapView.RailwayLook?
    private var railwayLayers: [String] = []
    /// The railways' shape sources, kept for the next drawing: a source is
    /// given a new shape rather than removed.
    private var railwaySources: Set<String> = []
    /// The game's stations, and those the loaded style makes way for.
    var stations: [OSMMapBackground.StationMark] = [] {
        didSet {
            if stations != oldValue { decorate() }
        }
    }
    private var clearedFor: [OSMMapBackground.StationMark]?
    private var creditTexts = (map: "", railways: "")
    /// MapLibre's delegate, which the map view holds weakly.
    private var observer: StyleObserver?
    /// Told where the attribution is (``AppleMapBackground/onAttributionFrames``).
    var onAttributionFrames: (@MainActor ([CGRect]) -> Void)?
    private var reportedAttribution: [CGRect]?
    /// The screen's safe area, as SwiftUI gives it (decision 120).
    var screenSafeArea = EdgeInsets() {
        didSet {
            if screenSafeArea != oldValue { setNeedsLayout() }
        }
    }

    private lazy var credit: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        addSubview(label)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isZoomEnabled = false
        isScrollEnabled = false
        isRotateEnabled = false
        isPitchEnabled = false
        compassView.isHidden = true
        showsScale = false
        // MapLibre's licence asks for no logo; the credit says whose the
        // map is, and the attribution button lists its sources.
        logoView.isHidden = true
        attributionButtonPosition = .bottomRight
        attributionButtonMargins = CGPoint(x: 10, y: 6)
        // The game's camera places the map, not the safe area.
        automaticallyAdjustsContentInset = false
        contentInset = .zero
        let observer = StyleObserver { [weak self] in self?.styleDidLoad() }
        self.observer = observer
        delegate = observer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func follow(_ realWorld: RealWorldFrame, camera: PlanCamera) {
        placement = (realWorld, camera)
        apply()
    }

    /// Loads `address` if it is a new style, and shows the labels in
    /// `language` and `railways` as `look` says once it has loaded.
    func show(
        style address: String,
        language: DisplayLanguage,
        railways: RealRailways?,
        look: FollowingMapView.RailwayLook,
        credits: (map: String, railways: String)
    ) {
        self.language = language
        self.railways = railways
        railwayLook = look
        if creditTexts != credits {
            creditTexts = credits
            setNeedsLayout()
        }
        if styleAddress != address, let url = URL(string: address) {
            styleAddress = address
            styleLoaded = false
            styleURL = url
            return
        }
        decorate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
        placeAttributionButton()
        placeCredit()
        reportAttribution()
    }

    /// Tells the game where the attribution button and the credit are,
    /// when that has changed: after this layout, not during SwiftUI's.
    private func reportAttribution() {
        var frames = [attributionButton.frame]
        if !(credit.text ?? "").isEmpty {
            frames.append(credit.frame)
        }
        guard frames != reportedAttribution, let report = onAttributionFrames else { return }
        reportedAttribution = frames
        Task { @MainActor in report(frames) }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// MapLibre puts its attribution button inside UIKit's safe area, which
    /// may not be the screen's; whatever of the screen's it leaves out is
    /// added to the margins, so the button clears the home indicator and
    /// the camera housing either way.
    private func placeAttributionButton() {
        let margins = CGPoint(
            x: 10 + max(0, screenSafeArea.trailing - safeAreaInsets.right),
            y: 6 + max(0, screenSafeArea.bottom - safeAreaInsets.bottom)
        )
        if attributionButtonMargins != margins {
            attributionButtonMargins = margins
        }
    }

    private func apply() {
        guard let placement, bounds.width > 0, bounds.height > 0 else { return }
        let view = OpenStreetMapBase.camera(
            of: placement.camera, in: placement.realWorld, width: Double(bounds.width), height: Double(bounds.height)
        )
        let centre = CLLocationCoordinate2D(latitude: view.latitude, longitude: view.longitude)
        // Setting the same view again would only make MapLibre redraw.
        guard abs(zoomLevel - view.zoom) > 1e-4
            || abs(centerCoordinate.latitude - centre.latitude) > 1e-7
            || abs(centerCoordinate.longitude - centre.longitude) > 1e-7
        else { return }
        setCenter(centre, zoomLevel: view.zoom, animated: false)
    }

    private func styleDidLoad() {
        // A new style has none of the game's layers.
        styleLoaded = true
        labelled = nil
        drawn = nil
        clearedFor = nil
        railwayLayers = []
        railwaySources = []
        decorate()
    }

    private func decorate() {
        guard styleLoaded, let style else { return }
        if labelled != language {
            labelled = language
            label(style)
        }
        if drawn != railwayLook {
            drawn = railwayLook
            drawRailways(in: style)
            setNeedsLayout()
        }
        if clearedFor != stations {
            clearedFor = stations
            makeWay(for: stations, in: style)
        }
    }

    // MARK: - Room for the game's station names

    private static let stationRoom = "game.stations.room"

    /// The game draws each station's name on a plate under it, over this
    /// map; the map's own place names did not know, and a village named as
    /// its station printed its name a second time under the game's
    /// (Sijiaoting, in the owner's screenshots). An invisible label for each
    /// station, as long as its name and above every other label layer, is
    /// placed first and keeps the map's labels out of where the game's name
    /// goes. MapLibre places the symbols of higher layers first; this one
    /// is drawn at no opacity, may overlap anything, and others may not
    /// overlap it.
    private func makeWay(for stations: [OSMMapBackground.StationMark], in style: MLNStyle) {
        let points = stations.map { station in
            let point = MLNPointFeature()
            point.coordinate = CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
            point.attributes = ["name": station.name]
            return point
        }
        let shape = MLNShapeCollectionFeature(shapes: points)
        if let source = style.source(withIdentifier: Self.stationRoom) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: Self.stationRoom, shape: shape, options: nil)
        style.addSource(source)
        let layer = MLNSymbolStyleLayer(identifier: Self.stationRoom, source: source)
        layer.text = NSExpression(forKeyPath: "name")
        // The style's own font, whose glyphs its server has.
        let labels = style.layers.compactMap { $0 as? MLNSymbolStyleLayer }
        if let font = labels.first(where: { $0.textFontNames != nil })?.textFontNames {
            layer.textFontNames = font
        }
        layer.textFontSize = NSExpression(forConstantValue: 13)
        layer.textAnchor = NSExpression(forConstantValue: "top")
        // From just above the station's mark to under its name.
        layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -0.6)))
        layer.textPadding = NSExpression(forConstantValue: 8)
        layer.textOpacity = NSExpression(forConstantValue: 0)
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        layer.textIgnoresPlacement = NSExpression(forConstantValue: false)
        style.addLayer(layer)
    }

    // MARK: - Labels

    /// Every place label in the player's language; road numbers as they are.
    private func label(_ style: MLNStyle) {
        let text = NSExpression(mglJSONObject: OpenStreetMapBase.labelText(in: language))
        for case let layer as MLNSymbolStyleLayer in style.layers {
            guard let current = layer.text, OpenStreetMapBase.showsName(current.mgl_jsonExpressionObject) else { continue }
            layer.text = text
        }
    }

    // MARK: - Taiwan's real railways

    /// The railways near the anchor as `railwayLook` says, in the site's
    /// drawing order (`glTracksInstall`): for each `sortKey` from the lowest,
    /// the casing of every line, then the lines in their colours; then the
    /// stations. All under the style's first label layer, as the site puts
    /// them under its map's labels.
    private func drawRailways(in style: MLNStyle) {
        for identifier in railwayLayers {
            if let layer = style.layer(withIdentifier: identifier) {
                style.removeLayer(layer)
            }
        }
        railwayLayers = []
        var used: Set<String> = []
        defer {
            // Sources this drawing has no use for are emptied, not removed.
            for identifier in railwaySources.subtracting(used) {
                (style.source(withIdentifier: identifier) as? MLNShapeSource)?.shape = MLNShapeCollection(shapes: [])
            }
            railwaySources.formUnion(used)
        }
        guard let railways, let look = railwayLook else { return }
        let firstLabel = style.layers.first { $0 is MLNSymbolStyleLayer }
        func add(_ layer: MLNStyleLayer) {
            if let firstLabel {
                style.insertLayer(layer, below: firstLabel)
            } else {
                style.addLayer(layer)
            }
            railwayLayers.append(layer.identifier)
        }
        func source(_ identifier: String, _ shape: MLNShape) -> MLNShapeSource {
            used.insert(identifier)
            if let source = style.source(withIdentifier: identifier) as? MLNShapeSource {
                source.shape = shape
                return source
            }
            let source = MLNShapeSource(identifier: identifier, shape: shape, options: nil)
            style.addSource(source)
            return source
        }
        func stroke(_ identifier: String, _ shape: MLNShape, _ color: RealRailways.RGB, _ width: Double) -> MLNLineStyleLayer {
            let layer = MLNLineStyleLayer(identifier: identifier, source: source(identifier, shape))
            layer.lineColor = NSExpression(forConstantValue: UIColor(color))
            layer.lineWidth = NSExpression(forConstantValue: width)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            return layer
        }

        let lines = railways.lines(near: look.anchor, within: look.reach)
        for sortKey in Set(lines.map(\.sortKey)).sorted() {
            let rank = lines.filter { $0.sortKey == sortKey }
            let polylines = rank.map { line in
                let coordinates = line.points.map { CLLocationCoordinate2D($0) }
                return MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
            }
            add(stroke("railways.\(sortKey).casing", MLNMultiPolyline(polylines: polylines), look.theme.casing, RealRailways.Widths.casing))
            var colors: [RealRailways.RGB] = []
            var byColor: [RealRailways.RGB: [MLNPolyline]] = [:]
            for (line, polyline) in zip(rank, polylines) {
                let color = line.palette.color(look.style, on: look.theme)
                if byColor[color] == nil { colors.append(color) }
                byColor[color, default: []].append(polyline)
            }
            for (index, color) in colors.enumerated() {
                add(stroke("railways.\(sortKey).\(index)", MLNMultiPolyline(polylines: byColor[color] ?? []), color, RealRailways.Widths.line))
            }
        }

        // The site's station circles (`track-stations`): a middle in the
        // casing's colour with a ring in the line's, the same size at every
        // zoom, from the site's zoom on. MapLibre strokes outside the
        // radius, so the middle is the radius less half the ring.
        var rings: [RealRailways.RGB] = []
        var byRing: [RealRailways.RGB: [MLNPointAnnotation]] = [:]
        for mark in railways.stationMarks(near: look.anchor, within: look.reach) {
            let ring = mark.palette.color(look.style, on: look.theme)
            let point = MLNPointAnnotation()
            point.coordinate = CLLocationCoordinate2D(mark.coordinate)
            if byRing[ring] == nil { rings.append(ring) }
            byRing[ring, default: []].append(point)
        }
        for (index, ring) in rings.enumerated() {
            let identifier = "railways.stations.\(index)"
            let layer = MLNCircleStyleLayer(identifier: identifier, source: source(identifier, MLNShapeCollection(shapes: byRing[ring] ?? [])))
            layer.circleRadius = NSExpression(forConstantValue: RealRailways.Widths.stationRadius - RealRailways.Widths.stationRing / 2)
            layer.circleColor = NSExpression(forConstantValue: UIColor(look.theme.casing))
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor(ring))
            layer.circleStrokeWidth = NSExpression(forConstantValue: RealRailways.Widths.stationRing)
            layer.circleStrokeOpacity = NSExpression(forConstantValue: RealRailways.Widths.stationRingOpacity)
            layer.minimumZoomLevel = Float(RealRailways.Widths.stationsMinimumZoom)
            add(layer)
        }
    }

    // MARK: - Credit

    /// OpenFreeMap's credit, and the railways' while they are drawn, on the
    /// left of the band at the bottom, clear of the attribution button on
    /// the right.
    private func placeCredit() {
        credit.text = railwayLayers.isEmpty ? creditTexts.map : "\(creditTexts.map) · \(creditTexts.railways)"
        let safe = screenSafeArea
        let width = min(credit.intrinsicContentSize.width + 8, bounds.width - 60 - safe.leading - safe.trailing)
        let height = credit.intrinsicContentSize.height + 2
        credit.frame = CGRect(
            x: 10 + safe.leading, y: bounds.height - 6 - safe.bottom - height, width: max(0, width), height: height
        )
        bringSubviewToFront(credit)
    }
}

/// The files of the game's base map style (decision 151): the bundled
/// tiles and glyphs (`Resources/BaseMap/`, a folder in the app), and the
/// style JSON written for MapLibre to load, once a launch for each look.
@MainActor
enum BaseMapFiles {
    /// The app's base map folder, `nil` if it has none.
    static let folder = Bundle.main.url(forResource: "BaseMap", withExtension: nil)

    /// Taiwan's tiles, `nil` if the app has none.
    static let tiles: URL? = folder.map { $0.appendingPathComponent("taiwan.pmtiles") }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }

    /// The glyphs' address, MapLibre's `{fontstack}` and `{range}` in it:
    /// the bundled ones, else OpenFreeMap's (the same files).
    static let glyphs: String = {
        if let fonts = folder?.appendingPathComponent("fonts", isDirectory: true),
           FileManager.default.fileExists(atPath: fonts.path) {
            var address = fonts.absoluteString
            while address.hasSuffix("/") { address.removeLast() }
            return address + "/{fontstack}/{range}.pbf"
        }
        return "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
    }()

    private static var written: [String: String] = [:]

    /// The address of the style file for Taiwan's tiles or OpenFreeMap's,
    /// light or dark, writing it the first time; `nil` if it cannot be
    /// written.
    static func styleAddress(taiwan: Bool, dark: Bool) -> String? {
        let name = "BaseMapStyle-\(taiwan ? "taiwan" : "world")-\(dark ? "dark" : "light").json"
        if let address = written[name] { return address }
        let source: BaseMapStyle.Tiles = if taiwan, let tiles { .bundled(pmtiles: tiles.absoluteString) } else { .openFreeMap }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let data = try? BaseMapStyle.json(tiles: source, dark: dark, glyphs: glyphs)
        else { return nil }
        let file = caches.appendingPathComponent(name)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        written[name] = file.absoluteString
        return file.absoluteString
    }
}

/// Tells the map view when a style has loaded. MapLibre calls its delegate
/// on the main thread, in a protocol Swift sees as nonisolated: only the
/// (Sendable) callback crosses to the main actor, not the observer.
private final class StyleObserver: NSObject, MLNMapViewDelegate {
    private let loaded: @MainActor @Sendable () -> Void

    init(loaded: @escaping @MainActor @Sendable () -> Void) {
        self.loaded = loaded
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        let loaded = self.loaded
        MainActor.assumeIsolated { loaded() }
    }
}
