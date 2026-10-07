import SwiftUI
import UIKit

/// The interface colours, in the app icon's style: flat, rounded, teal track,
/// navy buildings, warm lights and a pale blue-grey ground. Each colour has a
/// light and a dark variant; the dark ones follow the dark icon.
///
/// The icon's own colours (both PNGs and their SVG sources) are teal
/// #12A08F (dark #45D3C0) with a #BDEFE7 (dark #D4FAF4) centre line, navy
/// #262C57 (the dark icon's ground; its buildings are #ECEEF6), warm #FFC86B
/// and ground #ECEEF6. The icon's light teal is too pale for text on the
/// light ground (2.8:1), so ``primary`` darkens it along the same hue.
///
/// Every text colour here is at least 4.5:1 (WCAG AA) on both ``background``
/// and ``panel`` in its appearance, and ``onPrimary`` and ``onAccent`` are
/// at least 4.5:1 on the colour they sit on. ``accent`` and ``panelBorder``
/// are fills and edges, never text.
///
/// Screens move to these colours one at a time; until then they use
/// ``Palette``. The map's colours stay in ``Palette``.
enum Theme {
    /// Teal: the app's tint and its main colour (the `AccentColor` asset,
    /// #0D766A light, #45D3C0 dark), for controls, icons and selection.
    /// 4.75:1 on the light background, 6.03:1 on the dark panel.
    static let primary = Color("AccentColor")
    /// Text and icons on ``primary`` (5.50:1 light, 7.17:1 dark).
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x262C57)
    /// The icon's warm light and station: highlights and badges, with
    /// ``onAccent`` on top. Not for text, nor alone on the light background.
    static let accent = dynamic(light: 0xFFC86B, dark: 0xFFC86B)
    /// Text and icons on ``accent`` (8.69:1).
    static let onAccent = dynamic(light: 0x262C57, dark: 0x262C57)

    /// The screen's ground: the light icon's ground, the dark icon's navy.
    static let background = dynamic(light: 0xECEEF6, dark: 0x262C57)
    /// Cards, chips and panels over the background or the map.
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x30376A)
    /// The edge of a ``panel``.
    static let panelBorder = dynamic(light: 0x262C57, dark: 0xECEEF6, lightAlpha: 0.14, darkAlpha: 0.16)

    /// Body text: the icon's buildings (11.47:1 light, 9.64:1 dark).
    static let textPrimary = dynamic(light: 0x262C57, dark: 0xECEEF6)
    /// Secondary text (5.16:1 light, 5.79:1 dark).
    static let textSecondary = dynamic(light: 0x5B6189, dark: 0xB4B9D9)

    /// Good news: a positive balance, a finished action (5.10:1, 6.10:1).
    static let success = dynamic(light: 0x1E7334, dark: 0x5FD68A)
    /// Needs attention: paused, short of something (5.06:1, 6.33:1).
    static let warning = dynamic(light: 0x8A5B0F, dark: 0xFFB454)
    /// Something is wrong: a negative balance, a failed action (4.85:1,
    /// 5.54:1).
    static let error = dynamic(light: 0xC62828, dark: 0xFF9B9B)
    /// Text and icons on ``error`` (5.62:1 light, 6.59:1 dark).
    static let onError = dynamic(light: 0xFFFFFF, dark: 0x262C57)

    private static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? Theme.uiColor(dark, alpha: darkAlpha)
                : Theme.uiColor(light, alpha: lightAlpha)
        })
    }

    private static func uiColor(_ rgb: UInt32, alpha: Double) -> UIColor {
        UIColor(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// A button that is on or off, in ``Theme`` colours: filled with
/// ``Theme/primary`` while on, and only its label while off, for the glass
/// it sits on (`glassBackground(in:interactive:)`). Flat, like
/// the icon. It replaces ``SelectableButtonStyle`` as screens move to the
/// theme.
struct ThemeSelectableButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Theme.onPrimary : Theme.textPrimary)
            .background(isActive ? Theme.primary : Color.clear, in: shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(shape)
    }
}

/// A screen's main action, flat and filled: ``Theme/primary``, or
/// ``Theme/error`` for one that removes something; a quiet fill while it
/// cannot be used.
struct ThemeProminentButtonStyle: ButtonStyle {
    var isDestructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let fill = isDestructive ? Theme.error : Theme.primary
        let text = isDestructive ? Theme.onError : Theme.onPrimary
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(isEnabled ? text : Theme.textSecondary)
            .background(isEnabled ? fill : Theme.panelBorder, in: shape)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(shape)
    }
}

extension View {
    /// A flat card in ``Theme`` colours: ``Theme/panel`` with a
    /// ``Theme/panelBorder`` edge, so text on it keeps its stated contrast
    /// even over glass. It replaces `metroCard` as screens move to the
    /// theme.
    func themeCard(padding: CGFloat = 12, cornerRadius: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.panelBorder, lineWidth: 1)
            }
    }

    /// Glass behind this view, in `shape`, for the controls that float over
    /// the map: Liquid Glass on iOS 26 and later (reacting to touches when
    /// `interactive`), a material on earlier versions.
    @ViewBuilder
    func glassBackground(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}
