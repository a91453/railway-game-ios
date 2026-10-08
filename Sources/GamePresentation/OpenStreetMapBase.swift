import Foundation
import GameCore

// The OpenStreetMap base map of real-world maps (ARCHITECTURE decision 97,
// ROADMAP E3): OpenFreeMap's vector tiles drawn by MapLibre Native, as the
// `Ci/` reference draws its OSM map engine (`initOsmMapEngine`, its
// `positron` default and `dark` style, its labels in the local language).
// The app's map view (`OSMMapBackground`) is MapLibre's; what it asks of
// the game is here, where it can be tested.

/// What the app's OpenStreetMap base map needs from the game: where to look,
/// which style to load and how to label it.
public enum OpenStreetMapBase {
    /// OpenFreeMap's Positron, light and muted so the railway stands out
    /// (`Ci/`'s default `positron`), or its Dark for the dark appearance.
    public static func styleURL(dark: Bool) -> String {
        dark ? "https://tiles.openfreemap.org/styles/dark" : "https://tiles.openfreemap.org/styles/positron"
    }

    /// The text of the base map's place labels, as a MapLibre style
    /// expression: one name in the player's language, not OpenFreeMap's
    /// Latin name over the local one (`Ci/`'s `osmLabelLang`). In Chinese
    /// the Traditional name, else the Chinese, else the local one (Taiwan's
    /// own); in English the English name, else the Latin, else the local.
    public static func labelText(in language: DisplayLanguage) -> [Any] {
        let keys = switch language {
        case .english: ["name:en", "name_en", "name:latin", "name"]
        case .traditionalChinese: ["name:zh-Hant", "name:zh", "name"]
        }
        return ["coalesce"] + keys.map { ["get", $0] as [Any] }
    }

    /// Whether a style layer's text expression (its JSON form) shows a
    /// place's name, so ``labelText(in:)`` stands in for it; a road's number
    /// (`ref`) or a house number keeps its own.
    public static func showsName(_ text: Any) -> Bool {
        if let key = text as? String {
            return key == "name" || key.hasPrefix("name:") || key.hasPrefix("name_")
        }
        guard let parts = text as? [Any], let first = parts.first as? String else { return false }
        if first == "get", parts.count >= 2 {
            return showsName(parts[1])
        }
        return parts.dropFirst().contains { showsName($0) }
    }

    /// MapLibre's camera for a map view of `width` × `height` points whose
    /// top is the game's map view under `camera`: the place at the view's
    /// middle and the zoom (the Earth 512 · 2^z points wide) that draws a
    /// world metre, a metre at the anchor's latitude, as many points as the
    /// game does, so the railway lines up all over the map (as MapKit's map
    /// rect does, ``RealWorldFrame``).
    public static func camera(
        of camera: PlanCamera, in frame: RealWorldFrame, width: Double, height: Double
    ) -> (latitude: Double, longitude: Double, zoom: Double) {
        let middle = camera.worldPosition(at: ScreenPoint(x: width / 2, y: height / 2))
        let place = frame.coordinate(worldX: middle.x, worldY: middle.y)
        return (place.latitude, place.longitude, StationLabels.zoom(pointsPerUnit: camera.pointsPerUnit, latitude: frame.anchor.latitudeDegrees))
    }
}
