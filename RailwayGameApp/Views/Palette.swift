import SwiftUI
import UIKit

/// Map and UI colours, each with a light and a dark variant so the app stays
/// readable and aesthetically pleasing in both appearances.
enum Palette {
    static let land = dynamic(light: (0.86, 0.91, 0.81), dark: (0.16, 0.21, 0.16))
    static let mapEdge = dynamic(light: (0.55, 0.62, 0.52), dark: (0.30, 0.36, 0.30))
    static let ballast = dynamic(light: (0.68, 0.64, 0.58), dark: (0.40, 0.38, 0.35))
    static let rail = dynamic(light: (0.24, 0.21, 0.19), dark: (0.90, 0.88, 0.84))
    static let station = dynamic(light: (0.82, 0.36, 0.08), dark: (0.93, 0.50, 0.18))
    static let stationSymbol = Color.white
    static let train = dynamic(light: (0.10, 0.36, 0.78), dark: (0.45, 0.68, 1.00))

    // Transit Semantic Colors
    static let metroBlue = dynamic(light: (0.07, 0.45, 0.88), dark: (0.24, 0.60, 1.00))
    static let metroGreen = dynamic(light: (0.13, 0.62, 0.36), dark: (0.22, 0.78, 0.48))
    static let metroAmber = dynamic(light: (0.88, 0.52, 0.08), dark: (0.96, 0.65, 0.20))
    static let metroPurple = dynamic(light: (0.48, 0.28, 0.82), dark: (0.65, 0.48, 0.95))
    static let metroCyan = dynamic(light: (0.05, 0.60, 0.72), dark: (0.20, 0.75, 0.88))
    static let metroRed = dynamic(light: (0.85, 0.24, 0.24), dark: (0.95, 0.38, 0.38))

    // Surfaces and Borders
    static let cardBackground = dynamic(light: (1.00, 1.00, 1.00), dark: (0.14, 0.15, 0.18))
    static let cardBorder = dynamicAlpha(light: (0.0, 0.0, 0.0, 0.08), dark: (1.0, 1.0, 1.0, 0.12))
    static let chipBackground = dynamicAlpha(light: (0.0, 0.0, 0.0, 0.05), dark: (1.0, 1.0, 1.0, 0.08))

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    private static func dynamicAlpha(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgba = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
        })
    }
}

/// A clean, tactile card modifier for grouping management options.
struct MetroCardModifier: ViewModifier {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
    }
}

extension View {
    func metroCard(padding: CGFloat = 12, cornerRadius: CGFloat = 14) -> some View {
        modifier(MetroCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
