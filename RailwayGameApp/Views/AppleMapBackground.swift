import GameCore
import GamePresentation
import MapKit
import SwiftUI

/// The look of the map under a real-world game (Stage E2): the references'
/// choice of a light street map, satellite imagery or both (`Ci/`'s
/// `positron` / `satellite` styles), from Apple, or OpenStreetMap's own
/// (decision 97, ``OSMMapBackground``). A view preference, kept with the
/// app's settings rather than the game.
enum AppleMapStyle: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite
    case openStreetMap

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: String(localized: "Map")
        case .hybrid: String(localized: "Satellite with Labels")
        case .satellite: String(localized: "Satellite")
        case .openStreetMap: String(localized: "OpenStreetMap")
        }
    }

    /// Flat, so the map is the plan the railway is drawn on; the street map
    /// muted, so the railway stands out (as `Ci/`'s light `positron`).
    var configuration: MKMapConfiguration {
        switch self {
        case .standard, .openStreetMap: MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        case .hybrid: MKHybridMapConfiguration(elevationStyle: .flat)
        case .satellite: MKImageryMapConfiguration(elevationStyle: .flat)
        }
    }
}

/// Apple's map under a real-world game's railway (Stage E2, ARCHITECTURE
/// decision 50). It follows the game's camera: the player pans and zooms
/// the game's map as on a blank one, and this map shows the same piece of
/// the Earth, top-down and north up, so the railway drawn over it lines up.
///
/// The world lies over the Earth as ``RealWorldFrame`` says: a world metre
/// is a metre at the anchor's latitude, in MapKit's own map points
/// (`MKMapPointsPerMeterAtLatitude`), so the drawing and the map agree all
/// over the 16 km map.
///
/// The map takes no gestures of its own, but its view stays interactive:
/// Apple's logo and legal link sit in a strip at its bottom
/// (``attributionHeight``) that nothing of the game covers, and the link
/// can be tapped (Attachment 6 §2.1 of the Apple Developer Program License
/// Agreement: no Apple logo or legal notice may be obscured).
///
/// Taiwan's real railways (the `Railway/` site's lines and stations) are
/// drawn on it as the site draws them on its map: over the roads, under the
/// labels, in the colours of the player's track display. The site's credit
/// for them sits in the middle of the strip, between Apple's logo and link.
struct AppleMapBackground: UIViewRepresentable {
    let realWorld: RealWorldFrame
    /// The game's camera. Its view is the top of this one, which is
    /// ``attributionHeight`` taller.
    let camera: PlanCamera
    let style: AppleMapStyle
    /// Taiwan's railways, `nil` if the app's copy cannot be read.
    let railways: RealRailways?
    let trackStyle: RealRailways.TrackStyle
    let language: DisplayLanguage

    /// The strip at the bottom of the map view kept clear for Apple's logo
    /// and legal link.
    static let attributionHeight: CGFloat = 30

    func makeUIView(context: Context) -> FollowingMapView {
        let map = FollowingMapView()
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        // The logo and legal link go in the strip at the bottom, and only
        // there: the strip is part of the view, not of the safe area.
        map.insetsLayoutMarginsFromSafeArea = false
        map.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 6, right: 10)
        map.preferredConfiguration = style.configuration
        map.appliedStyle = style
        map.delegate = map
        return map
    }

    func updateUIView(_ map: FollowingMapView, context: Context) {
        if map.appliedStyle != style {
            map.appliedStyle = style
            map.preferredConfiguration = style.configuration
        }
        let theme: RealRailways.MapTheme = switch style {
        case .standard, .openStreetMap: context.environment.colorScheme == .dark ? .dark : .light
        case .hybrid, .satellite: .satellite
        }
        map.showRailways(
            railways,
            near: realWorld.anchor,
            look: FollowingMapView.RailwayLook(
                anchor: realWorld.anchor, reach: FollowingMapView.railwayReach(of: camera.mapRegion), style: trackStyle, theme: theme
            ),
            credit: DataSourceCredits.railwaysOnMap(in: language)
        )
        map.follow(realWorld, camera: camera)
    }
}

/// An `MKMapView` that shows what the game's camera shows: set again
/// whenever the camera or its own size changes, before its first layout
/// too.
final class FollowingMapView: MKMapView, MKMapViewDelegate {
    /// The style last set, so a redraw of the game does not set it again.
    var appliedStyle: AppleMapStyle?
    private var placement: (realWorld: RealWorldFrame, camera: PlanCamera)?

    /// How the real railways are drawn: set again only when it changes.
    struct RailwayLook: Equatable {
        let anchor: GeoAnchor
        /// How far from the anchor real railways are drawn, in metres.
        let reach: Double
        let style: RealRailways.TrackStyle
        let theme: RealRailways.MapTheme
    }

    /// How far from the anchor real railways are drawn on a map reaching
    /// as far as `region`: past its corners, at least 16 km (a 16 km map's
    /// are 8,192 m each way, Stage E1), so the whole of Taiwan (decision
    /// 88) draws all of them.
    static func railwayReach(of region: WorldRegion) -> Double {
        let unitsPerMetre = Double(WorldCoordinate.unitsPerMetre)
        return max(16_000, (region.width * region.width + region.height * region.height).squareRoot() / 2 / unitsPerMetre + 2_000)
    }

    private var railwayLook: RailwayLook?
    private var railwayOverlays: [any MKOverlay] = []
    /// The colour and width of each line overlay, by the overlay.
    private var strokes: [ObjectIdentifier: (color: UIColor, width: CGFloat)] = [:]
    /// The overlay the stations are drawn in, and their circles.
    private var stations: (overlay: MKPolygon, renderer: StationDotsRenderer)?
    private lazy var credit: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        self.addSubview(label)
        return label
    }()

    func follow(_ realWorld: RealWorldFrame, camera: PlanCamera) {
        placement = (realWorld, camera)
        apply()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
        placeCredit()
    }

    private func apply() {
        guard let placement, bounds.width > 0, bounds.height > 0 else { return }
        let rect = Self.mapRect(placement.realWorld, camera: placement.camera, size: bounds.size)
        guard !Self.isClose(visibleMapRect, to: rect) else { return }
        setVisibleMapRect(rect, animated: false)
    }

    // MARK: - Taiwan's real railways

    /// Draws `railways` near `anchor` as `look` says, replacing what was
    /// drawn for another look.
    func showRailways(_ railways: RealRailways?, near anchor: GeoAnchor, look: RailwayLook, credit text: String) {
        credit.text = text
        guard look != railwayLook else { return }
        railwayLook = look
        removeOverlays(railwayOverlays)
        railwayOverlays = []
        strokes = [:]
        stations = nil
        if let railways {
            railwayOverlays = lineStrokes(railways.lines(near: anchor, within: look.reach), look: look)
            let marks = railways.stationMarks(near: anchor, within: look.reach)
            if !marks.isEmpty {
                let stations = stationDots(marks, near: anchor, look: look)
                self.stations = stations
                railwayOverlays.append(stations.overlay)
            }
        }
        // Over the roads and under the labels, as the site puts them
        // under its map's labels.
        addOverlays(railwayOverlays, level: .aboveRoads)
        credit.isHidden = railwayOverlays.isEmpty
        setNeedsLayout()
    }

    /// The site's drawing order (`glTracksInstall`): for each `sortKey`
    /// from the lowest, the casing of every line, then the lines in their
    /// colours.
    private func lineStrokes(_ lines: [RealRailways.Line], look: RailwayLook) -> [any MKOverlay] {
        var overlays: [any MKOverlay] = []
        let casing = UIColor(look.theme.casing)
        for sortKey in Set(lines.map(\.sortKey)).sorted() {
            let rank = lines.filter { $0.sortKey == sortKey }
            let polylines = rank.map { line in
                let coordinates = line.points.map { CLLocationCoordinate2D($0) }
                return MKPolyline(coordinates: coordinates, count: coordinates.count)
            }
            overlays.append(stroke(MKMultiPolyline(polylines), casing, RealRailways.Widths.casing))
            var colors: [RealRailways.RGB] = []
            var byColor: [RealRailways.RGB: [MKPolyline]] = [:]
            for (line, polyline) in zip(rank, polylines) {
                let color = line.palette.color(look.style, on: look.theme)
                if byColor[color] == nil { colors.append(color) }
                byColor[color, default: []].append(polyline)
            }
            for color in colors {
                overlays.append(stroke(MKMultiPolyline(byColor[color] ?? []), UIColor(color), RealRailways.Widths.line))
            }
        }
        return overlays
    }

    private func stroke(_ overlay: MKMultiPolyline, _ color: UIColor, _ width: Double) -> MKMultiPolyline {
        strokes[ObjectIdentifier(overlay)] = (color, CGFloat(width))
        return overlay
    }

    /// The stations near `anchor`, drawn over the square they are in.
    private func stationDots(
        _ marks: [RealRailways.StationMark],
        near anchor: GeoAnchor,
        look: RailwayLook
    ) -> (overlay: MKPolygon, renderer: StationDotsRenderer) {
        let middle = MKMapPoint(CLLocationCoordinate2D(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees))
        let reach = look.reach * MKMapPointsPerMeterAtLatitude(anchor.latitudeDegrees)
        let corners = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { MKMapPoint(x: middle.x + $0.0 * reach, y: middle.y + $0.1 * reach) }
        let square = MKPolygon(points: corners, count: corners.count)
        let dots = marks.map { mark in
            let point = MKMapPoint(CLLocationCoordinate2D(mark.coordinate))
            return StationDotsRenderer.Dot(x: point.x, y: point.y, ring: mark.palette.color(look.style, on: look.theme))
        }
        return (square, StationDotsRenderer(overlay: square, dots: dots, middle: look.theme.casing))
    }

    /// The credit in the middle of the strip at the bottom, clear of
    /// Apple's logo on the left and legal link on the right.
    private func placeCredit() {
        guard !credit.isHidden else { return }
        let width = min(credit.intrinsicContentSize.width + 8, bounds.width * 0.45)
        let height = credit.intrinsicContentSize.height + 2
        credit.frame = CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - layoutMargins.bottom - height,
            width: width,
            height: height
        )
        bringSubviewToFront(credit)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
        if let stations, overlay === stations.overlay {
            return stations.renderer
        }
        guard let lines = overlay as? MKMultiPolyline, let stroke = strokes[ObjectIdentifier(lines)] else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKMultiPolylineRenderer(multiPolyline: lines)
        renderer.strokeColor = stroke.color
        renderer.lineWidth = stroke.width
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }

    /// The part of the Earth a view of `size` shows when its top is the
    /// game's map view under `camera`, in MapKit's map points.
    static func mapRect(_ realWorld: RealWorldFrame, camera: PlanCamera, size: CGSize) -> MKMapRect {
        let topLeft = camera.worldPosition(at: ScreenPoint(x: 0, y: 0))
        let bottomRight = camera.worldPosition(at: ScreenPoint(x: size.width, y: size.height))
        let from = realWorld.metresFromAnchor(worldX: topLeft.x, worldY: topLeft.y)
        let to = realWorld.metresFromAnchor(worldX: bottomRight.x, worldY: bottomRight.y)
        let anchor = CLLocationCoordinate2D(latitude: realWorld.anchor.latitudeDegrees, longitude: realWorld.anchor.longitudeDegrees)
        let origin = MKMapPoint(anchor)
        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(anchor.latitude)
        return MKMapRect(
            x: origin.x + from.east * pointsPerMetre,
            y: origin.y + from.south * pointsPerMetre,
            width: (to.east - from.east) * pointsPerMetre,
            height: (to.south - from.south) * pointsPerMetre
        )
    }

    /// Within a thousandth of the width: setting the same piece again would
    /// only make MapKit redraw.
    private static func isClose(_ a: MKMapRect, to b: MKMapRect) -> Bool {
        let tolerance = b.size.width / 1_000
        return abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.size.width - b.size.width) <= tolerance
            && abs(a.size.height - b.size.height) <= tolerance
    }
}

/// The site's station circles (`track-stations`): a middle in the casing's
/// colour with a ring in the line's, the same size at every zoom, from the
/// site's zoom level on. Each station is drawn whole, in the site's order,
/// so a later one covers an earlier one where they meet.
///
/// MapKit draws it off the main thread: everything it reads is set when it
/// is made and never changed.
final class StationDotsRenderer: MKOverlayRenderer {
    /// A station: its map point and its line's colour.
    struct Dot: Sendable {
        let x: Double
        let y: Double
        let ring: RealRailways.RGB
    }

    private let dots: [Dot]
    private let middle: RealRailways.RGB

    init(overlay: any MKOverlay, dots: [Dot], middle: RealRailways.RGB) {
        self.dots = dots
        self.middle = middle
        super.init(overlay: overlay)
    }

    /// MapLibre's zoom z draws the Earth 512 · 2^z points wide and MapKit's
    /// world is 2^28 map points, so the site's zoom z is a zoom scale of
    /// 2^(z − 19).
    static let minimumZoomScale = pow(2, RealRailways.Widths.stationsMinimumZoom - 19)

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard Double(zoomScale) >= Self.minimumZoomScale else { return }
        // Sizes are in screen points; the context is in map points.
        let radius = RealRailways.Widths.stationRadius / Double(zoomScale)
        let ring = RealRailways.Widths.stationRing / Double(zoomScale)
        let outer = radius + ring / 2, inner = radius - ring / 2
        let reach = mapRect.insetBy(dx: -outer, dy: -outer)
        for dot in dots {
            let point = MKMapPoint(x: dot.x, y: dot.y)
            guard reach.contains(point) else { continue }
            let centre = self.point(for: point)
            context.setFillColor(Self.color(dot.ring, alpha: RealRailways.Widths.stationRingOpacity))
            context.fillEllipse(in: CGRect(x: centre.x - outer, y: centre.y - outer, width: 2 * outer, height: 2 * outer))
            context.setFillColor(Self.color(middle, alpha: 1))
            context.fillEllipse(in: CGRect(x: centre.x - inner, y: centre.y - inner, width: 2 * inner, height: 2 * inner))
        }
    }

    private static func color(_ rgb: RealRailways.RGB, alpha: Double) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: CGFloat(alpha))
    }
}

extension UIColor {
    convenience init(_ rgb: RealRailways.RGB) {
        self.init(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}

extension CLLocationCoordinate2D {
    init(_ coordinate: RealRailways.Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
