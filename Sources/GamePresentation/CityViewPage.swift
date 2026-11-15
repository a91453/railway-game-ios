import Foundation

// The 3D city view (ARCHITECTURE decision 152) is jeantimex/tokyo's web
// renderer, built from `Web/CityView`. Since decision 163 the game's
// website serves it, under `/city/`, and the app's web view opens it
// there: the app no longer bundles the page or serves it itself. This is
// the part of that with no web view in it: the address of each area's
// page, and which pages the web view may open itself.

/// The areas of the city view, in the settings' order: Kaohsiung Station
/// (decision 152), whose railways are all underground, and Taichung
/// Station (decision 161), whose TRA viaduct shows the trains.
public enum CityViewArea: String, CaseIterable, Identifiable, Sendable {
    case kaohsiung
    case taichung

    public var id: String { rawValue }

    /// The page the app opens for the area, as light as the owner tried it
    /// on an iPhone 17 Pro (a 400 m view, no clouds, no birds, no traffic).
    /// `app=1` tells the page it is in the game, which hides its link to the
    /// website: the settings have their own.
    public var pageAddress: String? {
        pageAddress(of: .current)
    }

    /// The page of `brand`'s website, or nil when it has none.
    public func pageAddress(of brand: GameBrand) -> String? {
        CityViewPage.root(of: brand).map { "\($0)?area=\(rawValue)&radius=400&clouds=0&birds=0&traffic=0&app=1" }
    }
}

/// The game's website (decision 163), which the settings open in the app;
/// nil in a build with no website (``GameBrand/website``).
public enum GameWebsite {
    public static var home: String? { GameBrand.current.home }
}

/// Where the city view's page is (decision 163).
public enum CityViewPage {
    /// The page's folder on the game's website.
    public static func root(of brand: GameBrand = .current) -> String? {
        brand.home.map { $0 + "city/" }
    }

    /// Whether the web view opens `url` itself: the city view's own pages,
    /// and pages with no host (`about:blank`). Any other link the page
    /// follows, the website's home page among them, goes to the browser.
    public static func opensInView(_ url: URL, brand: GameBrand = .current) -> Bool {
        guard let host = url.host else { return true }
        return url.scheme == "https" && brand.website != nil && host == brand.website
            && (url.path == "/city" || url.path.hasPrefix("/city/"))
    }
}
