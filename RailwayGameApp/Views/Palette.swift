import SwiftUI
import UIKit

/// Map colours, each with a light and a dark variant so the map stays
/// readable in both appearances.
enum Palette {
    static let land = dynamic(light: (0.86, 0.91, 0.81), dark: (0.16, 0.21, 0.16))
    static let mapEdge = dynamic(light: (0.55, 0.62, 0.52), dark: (0.30, 0.36, 0.30))
    static let ballast = dynamic(light: (0.68, 0.64, 0.58), dark: (0.40, 0.38, 0.35))
    static let rail = dynamic(light: (0.24, 0.21, 0.19), dark: (0.90, 0.88, 0.84))
    static let station = dynamic(light: (0.82, 0.36, 0.08), dark: (0.93, 0.50, 0.18))
    static let stationSymbol = Color.white
    static let train = dynamic(light: (0.10, 0.36, 0.78), dark: (0.45, 0.68, 1.00))

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
