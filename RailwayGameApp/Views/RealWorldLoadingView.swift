import GameCore
import GamePresentation
import SwiftUI

/// The loading screen of a real-world map (ARCHITECTURE decision 307): the
/// company's name, the place the map starts at, and three lines in the
/// game's line colours with a train running back and forth on each. Where
/// the lines and trains are is GamePresentation's (``LoadingRoutes``); with
/// Reduce Motion the trains stand still.
struct RealWorldLoadingView: View {
    let loading: RealWorldLoading
    let language: DisplayLanguage
    /// The name the player gave the company on the postcard.
    @AppStorage("postcard.companyName") private var companyName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = Date.now

    var body: some View {
        let company = NetworkPostcard.companyName(companyName, in: language)
        let preparing = language.text("Preparing the map…", "正在準備地圖…")
        VStack(spacing: 20) {
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, elapsed: timeline.date.timeIntervalSince(shown))
                }
            }
            .frame(width: 220, height: 220)
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(verbatim: company)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                if let place = loading.place {
                    Text(verbatim: place)
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                }
                Text(verbatim: preparing)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: [company, loading.place, preparing].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("loading.realWorld")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        func point(_ p: ScreenPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        let routes = LoadingRoutes.routes
        for (index, route) in routes.enumerated() {
            var track = Path()
            track.addLines(route.stations.map(point))
            context.stroke(track, with: .color(Palette.lineColor(LineID(rawValue: index))), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        }
        for station in Set(routes.flatMap(\.stations)) {
            let dot = Path(ellipseIn: CGRect(origin: point(station), size: .zero).insetBy(dx: -6, dy: -6))
            context.fill(dot, with: .color(Theme.panel))
            context.stroke(dot, with: .color(Theme.textPrimary), lineWidth: 2.5)
        }
        var glyph = context.resolve(MapGlyph.train.image)
        glyph.shading = .color(Theme.onAccent)
        for route in routes {
            let at = point(LoadingRoutes.train(of: route, elapsed: elapsed, reduceMotion: reduceMotion))
            let disc = Path(ellipseIn: CGRect(origin: at, size: .zero).insetBy(dx: -14, dy: -14))
            context.fill(disc, with: .color(Theme.accent))
            context.stroke(disc, with: .color(Theme.onAccent), lineWidth: 2)
            context.draw(glyph, in: CGRect(origin: at, size: .zero).insetBy(dx: -9, dy: -9))
        }
    }
}
