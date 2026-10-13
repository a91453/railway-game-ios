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
/// map style menu's OpenStreetMap, the default since decision 151; Apple's
/// maps (``AppleMapBackground``) stay in the menu.
///
/// Like Apple's map it follows the game's camera, top-down and north up
/// (``OpenStreetMapBase/camera(of:in:width:height:)``), takes no gestures of
/// its own, and keeps the band at its bottom (``AppleMapBackground/attributionHeight``)
/// for the map's credit (decision 191) and MapLibre's attribution button,
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
    /// Tapping the credit opens the data sources page (decision 191).
    let onCredit: @MainActor () -> Void
    /// Whether the map may be tilted or turned
    /// (``AppleMapBackground/allowsTilt``): not while the game is played.
    var allowsTilt = false

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
                DataSourceCredits.mapCorner(baseMap: true, railways: false, in: language),
                DataSourceCredits.mapCorner(baseMap: true, railways: true, in: language)
            )
        )
        map.credit.onTap = onCredit
        map.stations = stations
        map.screenSafeArea = safeArea
        map.onAttributionFrames = onAttributionFrames
        map.allowsTilt = allowsTilt
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
    /// Whether the map may be tilted or turned (``OSMMapBackground/allowsTilt``).
    var allowsTilt = false
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
    /// The credit without and with the railways.
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

    /// The credit in the map's corner (decision 191), which opens the data
    /// sources page.
    private(set) lazy var credit: MapCreditButton = {
        let credit = MapCreditButton(alignment: .left)
        addSubview(credit)
        return credit
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
        if !credit.text.isEmpty {
            frames.append(credit.frame)
        }
        guard frames != reportedAttribution, let report = onAttributionFrames else { return }
        reportedAttribution = frames
        Task { @MainActor in report(frames) }
    }

    // MARK: - Accessibility

    // MLNMapView is an accessibility container of its own (its annotations,
    // compass and attribution button), so VoiceOver and the UI tests see
    // only what it lists; the credit (decision 191) is added after them.

    // UIKit asks on the main thread; the SDK may not say so.

    override func accessibilityElementCount() -> Int {
        MainActor.assumeIsolated { super.accessibilityElementCount() + (credit.text.isEmpty ? 0 : 1) }
    }

    override func accessibilityElement(at index: Int) -> Any? {
        let credit: MapCreditButton? = MainActor.assumeIsolated {
            index == super.accessibilityElementCount() && !self.credit.text.isEmpty ? self.credit : nil
        }
        if let credit { return credit }
        return super.accessibilityElement(at: index)
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        MainActor.assumeIsolated {
            (element as AnyObject) === credit ? super.accessibilityElementCount() : super.index(ofAccessibilityElement: element)
        }
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
        // Straight down and north up (decision 50), as Apple's map
        // (``FollowingMapView``): the game's plan is drawn over it.
        if !allowsTilt, camera.pitch != 0 || direction != 0 {
            let level = camera
            level.pitch = 0
            level.heading = 0
            setCamera(level, animated: false)
        }
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

    /// The image of the room the railways keep for themselves among the
    /// map's labels (decision 189), and its size: a little wider than a
    /// line's casing, one every as many points along the line, so the
    /// icons touch.
    private static let railwayRoom = "railways.room"
    private static let railwayRoomSize = RealRailways.Widths.casing + 2.4
    private static let railwayRoomImage: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let side = FollowingMapLibreView.railwayRoomSize
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in }
    }()

    /// The railways near the anchor as `railwayLook` says, in the site's
    /// drawing order (`glTracksInstall`): for each `sortKey` from the lowest,
    /// the casing of every line, then the lines in their colours; then the
    /// stations. All under the style's first label layer, as the site puts
    /// them under its map's labels.
    ///
    /// Decision 189: the map's labels keep off the lines, as they keep off
    /// the game's station names (``makeWay(for:in:)``). A name lying on a
    /// line erased it under its halo: the road names along the Kaohsiung
    /// Metro's Red Line (Zhongshan and Bo'ai Roads over it) cut it every
    /// few hundred points, and village names cut the Alishan line at its
    /// stations. An invisible icon every ``railwayRoomSize`` points along
    /// each line, above every other label layer, is placed first; the
    /// map's labels go around it: a road's name further along its road, a
    /// place's name beside its place (``BaseMapStyle``'s variable anchors),
    /// or, with no room anywhere, not at all. Railways drawn as hidden make
    /// no room.
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
        func stroke(_ identifier: String, _ lines: MLNSource, _ color: RealRailways.RGB, _ width: Double) -> MLNLineStyleLayer {
            let layer = MLNLineStyleLayer(identifier: identifier, source: lines)
            layer.lineColor = NSExpression(forConstantValue: UIColor(color))
            layer.lineWidth = NSExpression(forConstantValue: width)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            return layer
        }
        let makesRoom = look.style != .hidden
        if makesRoom {
            style.setImage(Self.railwayRoomImage, forName: Self.railwayRoom)
        }
        // The invisible icons along `lines`, above every label.
        func room(_ identifier: String, _ lines: MLNSource) {
            let layer = MLNSymbolStyleLayer(identifier: identifier, source: lines)
            layer.symbolPlacement = NSExpression(forConstantValue: "line")
            layer.symbolSpacing = NSExpression(forConstantValue: Self.railwayRoomSize)
            layer.iconImageName = NSExpression(forConstantValue: Self.railwayRoom)
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconOpacity = NSExpression(forConstantValue: 0)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: false)
            style.addLayer(layer)
            railwayLayers.append(layer.identifier)
        }

        let lines = railways.lines(near: look.anchor, within: look.reach)
        for sortKey in Set(lines.map(\.sortKey)).sorted() {
            let rank = lines.filter { $0.sortKey == sortKey }
            let polylines = rank.map { line in
                let coordinates = line.points.map { CLLocationCoordinate2D($0) }
                return MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
            }
            let casing = source("railways.\(sortKey).casing", MLNMultiPolyline(polylines: polylines))
            add(stroke("railways.\(sortKey).casing", casing, look.theme.casing, RealRailways.Widths.casing))
            if makesRoom {
                room("railways.\(sortKey).room", casing)
            }
            var colors: [RealRailways.RGB] = []
            var byColor: [RealRailways.RGB: [MLNPolyline]] = [:]
            for (line, polyline) in zip(rank, polylines) {
                let color = line.palette.color(look.style, on: look.theme)
                if byColor[color] == nil { colors.append(color) }
                byColor[color, default: []].append(polyline)
            }
            for (index, color) in colors.enumerated() {
                let identifier = "railways.\(sortKey).\(index)"
                add(stroke(identifier, source(identifier, MLNMultiPolyline(polylines: byColor[color] ?? [])), color, RealRailways.Widths.line))
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

    /// The base map's credit, with the railways' while they are drawn
    /// (decision 191), in the bottom left corner, clear of the attribution
    /// button on the right; it can be tapped anywhere up the band.
    private func placeCredit() {
        credit.text = railwayLayers.isEmpty ? creditTexts.map : creditTexts.railways
        let safe = screenSafeArea
        let size = credit.textSize
        let width = min(size.width + 8, bounds.width - 60 - safe.leading - safe.trailing)
        let height = size.height + 2
        let bottom = bounds.height - 6 - safe.bottom
        credit.place(
            text: CGRect(x: 10 + safe.leading, y: bottom - height, width: max(0, width), height: height),
            bandTop: bottom - AppleMapBackground.attributionHeight + 6,
            bandBottom: bottom + 6
        )
        bringSubviewToFront(credit)
    }
}

/// The files of the game's base map style (decision 151): the bundled
/// tiles, terrain and glyphs (`Resources/BaseMap/`, a folder in the app), and the
/// style JSON written for MapLibre to load, once a launch for each look.
@MainActor
enum BaseMapFiles {
    /// The app's base map folder, `nil` if it has none.
    static let folder = Bundle.main.url(forResource: "BaseMap", withExtension: nil)

    /// Taiwan's tiles, `nil` if the app has none.
    static let tiles = file("taiwan.pmtiles")

    /// Taiwan's ground heights for the hill shading, `nil` if the app has
    /// none.
    static let terrain = file("taiwan_terrain.pmtiles")

    private static func file(_ name: String) -> URL? {
        folder.map { $0.appendingPathComponent(name) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

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
              let data = try? BaseMapStyle.json(tiles: source, dark: dark, glyphs: glyphs, terrain: taiwan ? terrain?.absoluteString : nil)
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
