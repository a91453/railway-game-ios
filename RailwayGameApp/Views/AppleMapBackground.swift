import GamePresentation
import MapKit
import SwiftUI

/// The look of Apple's map under a real-world game (Stage E2): the
/// references' choice of a light street map, satellite imagery or both
/// (`Ci/`'s `positron` / `satellite` styles). A view preference, kept with
/// the app's settings rather than the game.
enum AppleMapStyle: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case satellite

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: String(localized: "Map")
        case .hybrid: String(localized: "Satellite with Labels")
        case .satellite: String(localized: "Satellite")
        }
    }

    /// Flat, so the map is the plan the railway is drawn on; the street map
    /// muted, so the railway stands out (as `Ci/`'s light `positron`).
    var configuration: MKMapConfiguration {
        switch self {
        case .standard: MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
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
struct AppleMapBackground: UIViewRepresentable {
    let realWorld: RealWorldFrame
    /// The game's camera. Its view is the top of this one, which is
    /// ``attributionHeight`` taller.
    let camera: PlanCamera
    let style: AppleMapStyle

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
        return map
    }

    func updateUIView(_ map: FollowingMapView, context: Context) {
        if map.appliedStyle != style {
            map.appliedStyle = style
            map.preferredConfiguration = style.configuration
        }
        map.follow(realWorld, camera: camera)
    }
}

/// An `MKMapView` that shows what the game's camera shows: set again
/// whenever the camera or its own size changes, before its first layout
/// too.
final class FollowingMapView: MKMapView {
    /// The style last set, so a redraw of the game does not set it again.
    var appliedStyle: AppleMapStyle?
    private var placement: (realWorld: RealWorldFrame, camera: PlanCamera)?

    func follow(_ realWorld: RealWorldFrame, camera: PlanCamera) {
        placement = (realWorld, camera)
        apply()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    private func apply() {
        guard let placement, bounds.width > 0, bounds.height > 0 else { return }
        let rect = Self.mapRect(placement.realWorld, camera: placement.camera, size: bounds.size)
        guard !Self.isClose(visibleMapRect, to: rect) else { return }
        setVisibleMapRect(rect, animated: false)
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
