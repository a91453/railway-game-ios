import Foundation
import GameCore

// "Use my location" on the real-world picker (ARCHITECTURE decision 335,
// the competitor study's 4.6, after decision 312): one fix of where the
// device is moves the start area there. Only the app asks the system for
// the fix (CoreLocation); what the picker does with it, and what it says
// when there is none, is decided here. The fix moves the frame and is
// dropped: it is not kept, and nothing is sent off the device.
//
// The owner's references have no device location to port (gap): `Ci/`'s
// "any city" and `MapBuilder/` start from a point picked on the map.

/// What one ask for the device's location came to, and where the picker's
/// frame goes for it.
public enum MyLocationStart: Hashable, Sendable {
    /// The player turned location off for the app, or it is not allowed
    /// on this device (parental controls, a managed device).
    case denied
    /// The system could not tell where the device is.
    case failed
    /// The device is at `latitude`°, `longitude`°.
    case located(latitude: Double, longitude: Double)

    /// How finely the fix places the frame, in degrees: about 1 km, finer
    /// than a 16 km square needs, so a game started there keeps no more
    /// than the town the device was in.
    public static let step = 0.01

    /// The start area the frame moves to, or `nil` where it stays: round
    /// the fix to the nearest ``step``, kept on the map.
    public var area: RealWorldStartArea? {
        guard case let .located(latitude, longitude) = self else { return nil }
        return RealWorldStartArea(latitude: Self.rounded(latitude), longitude: Self.rounded(longitude))
    }

    private static func rounded(_ degrees: Double) -> Double {
        (degrees / step).rounded() * step
    }

    /// Whether the frame had to stop short of the location: the map ends
    /// at about 85° north and south (``RealWorldStartArea/maximumLatitude``).
    public var isKeptOnMap: Bool {
        guard case let .located(latitude, _) = self, area != nil else { return false }
        return abs(latitude) > RealWorldStartArea.maximumLatitude
    }

    /// Whether the picker's line for this result goes once the map comes to
    /// rest with its middle at `latitude`°, `longitude`°: a fix's line is
    /// about where the frame went, so it goes once the map is a place away
    /// from there (``RecentStartPlaces/samePlaceMetres``). Why there is no
    /// fix stays until the player closes it or taps the map (TestFlight
    /// 86.1, an iPad: the map settling after the tap took the line away, so
    /// the button seemed to do nothing).
    public func messageGoes(mapMiddleLatitude latitude: Double, longitude: Double) -> Bool {
        guard let middle = area?.middle else { return false }
        guard let now = GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude) else { return true }
        return RecentStartPlaces.metres(from: middle, to: now) >= RecentStartPlaces.samePlaceMetres
    }

    /// How far from the map's top and trailing edges the button reaches, in
    /// points: 44 across inside a padding of 10.
    public static let buttonCorner = 64.0

    /// Whether a tap at `x`, `y` points on a map `mapWidth` wide is on the
    /// button's corner, where it must not also move the frame (TestFlight
    /// 86.1, an iPad: the tap that reached the map behind the button moved
    /// the frame to the top right instead of finding the device).
    public static func isOnButton(x: Double, y: Double, mapWidth: Double) -> Bool {
        x >= mapWidth - buttonCorner && y <= buttonCorner
    }

    /// The line the picker shows, or `nil` when the frame simply moved to a
    /// place of Taiwan. Each says how to go on picking without it.
    public func message(in language: DisplayLanguage) -> String? {
        switch self {
        case .denied:
            return language.text(
                "Location is off for this app. Search for a place or move the map instead, or turn location on in Settings.",
                "這個 App 的定位已關閉。請改用搜尋或移動地圖，或到「設定」開啟定位。"
            )
        case .failed:
            return language.text(
                "Couldn't find your location. Search for a place or move the map instead.",
                "找不到你的位置。請改用搜尋或移動地圖。"
            )
        case .located:
            guard let area else {
                return Self.failed.message(in: language)
            }
            if isKeptOnMap {
                return language.text(
                    "The map doesn't reach that far north or south, so the square is as close to you as it goes. A map here stays this size.",
                    "地圖到不了那麼北或那麼南，方框停在最靠近你的地方。這裡的地圖之後不會再擴大。"
                )
            }
            // Decision 167: only the island and Penghu buy land tile by
            // tile; anywhere else (Kinmen, Matsu, abroad) is one 16 km map.
            if !area.buysMoreLand {
                return language.text(
                    "You're outside Taiwan's main island and Penghu. The square is on your location, but a map here stays this size. Pick a place there to buy more land later.",
                    "你在台灣本島與澎湖以外。方框已移到你的位置，但這裡的地圖之後不會再擴大；選本島或澎湖的地點，之後才能買地擴大。"
                )
            }
            return nil
        }
    }
}
