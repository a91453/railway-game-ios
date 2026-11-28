import GamePresentation
import SwiftUI

/// Decision 566: the card a model new to the fleet comes with: the port
/// picture in its paint (``NewTrainArrivalArt``), its name, how the real
/// first ones arrived, a fanfare. ContentView lays it over the game (under
/// any sheet, so it shows once the sheet the train was bought in has
/// closed) on a dimmed ground. "Skip" closes it and any waiting after it;
/// "Welcome" shows the next.
struct NewTrainArrivalCard: View {
    let arrival: NewTrainArrival
    /// How many more wait after it.
    let waiting: Int
    let language: DisplayLanguage
    let next: () -> Void
    let skip: () -> Void
    let playSound: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowered = false

    var body: some View {
        VStack(spacing: 12) {
            ArrivalScene(arrival: arrival, drop: lowered || reduceMotion ? 1 : 0)
                .aspectRatio(NewTrainArrivalArt.width / NewTrainArrivalArt.height, contentMode: .fit)
                // A phone on its side keeps the whole card on the screen.
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.textPrimary, lineWidth: 2))
                .accessibilityHidden(true)
            Text(verbatim: arrival.title(in: language))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("newTrain.title")
            Text(verbatim: arrival.story(in: language))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("newTrain.story")
            HStack(spacing: 12) {
                Button(action: skip) {
                    Text(verbatim: waiting > 0 ? language.text("Skip all", "全部略過") : language.text("Skip", "略過"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityIdentifier("newTrain.skip")
                Button(action: next) {
                    Text(verbatim: language.text("Welcome!", "歡迎！"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .accessibilityIdentifier("newTrain.welcome")
            }
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newTrain.card")
        .task(id: arrival.id) {
            playSound()
            guard !reduceMotion else { return }
            lowered = false
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(MotionRule.cardIn.animation) { lowered = true }
        }
    }
}

/// The picture with the car `drop` of the way down; animatable, so the car
/// is lowered onto the quay. Nonisolated, so the `Animatable` conformance
/// (a nonisolated protocol) does not cross into the main actor; `body` is
/// still on the main actor through `View`.
private nonisolated struct ArrivalScene: View, Animatable {
    let arrival: NewTrainArrival
    var drop: Double

    var animatableData: Double {
        get { drop }
        set { drop = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / NewTrainArrivalArt.width, size.height / NewTrainArrivalArt.height)
            context.scaleBy(x: scale, y: scale)
            for shape in NewTrainArrivalArt.shapes(for: arrival, drop: drop) {
                let path: Path
                switch shape.kind {
                case let .rect(x, y, width, height, r):
                    path = Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: r)
                case let .polygon(points):
                    path = Path { p in
                        p.addLines(points.map { CGPoint(x: $0.x, y: $0.y) })
                        p.closeSubpath()
                    }
                case let .circle(x, y, r):
                    path = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                case let .line(a, b):
                    path = Path { p in
                        p.move(to: CGPoint(x: a.x, y: a.y))
                        p.addLine(to: CGPoint(x: b.x, y: b.y))
                    }
                }
                if let fill = shape.fill { context.fill(path, with: .color(Self.color(fill))) }
                if let stroke = shape.stroke, shape.strokeWidth > 0 {
                    context.stroke(path, with: .color(Self.color(stroke)),
                                   style: StrokeStyle(lineWidth: shape.strokeWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// The picture's colours are the same in light and dark (a picture
    /// with its own ground, as the station master's).
    private static func color(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// Decision 1044: the banner of a bought line's opening, over the top of
/// the map while its first train is out. It does not dim the game or
/// stop it: a tap on it opens the line, the cross closes it, and it goes
/// by itself after ``GameSession/lineOpeningShown``. ContentView plays the
/// bugle call with it (the session does, when the ceremony starts).
struct LineOpeningBanner: View {
    let opening: LineOpening
    let language: DisplayLanguage
    let go: () -> Void
    let close: () -> Void

    var body: some View {
        let ribbon = Palette.lineColor(opening.line, custom: opening.color)
        HStack(spacing: 12) {
            Image(systemName: "flag.2.crossed.fill")
                .font(.title2)
                .foregroundStyle(ribbon)
                .accessibilityHidden(true)
            Button(action: go) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: opening.title(in: language))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("lineOpening.title")
                    Text(verbatim: opening.detail(in: language))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(verbatim: language.text("Opens the line.", "打開這條線。")))
            .accessibilityIdentifier("lineOpening.go")
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
            .accessibilityIdentifier("lineOpening.close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .frame(maxWidth: 440)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            // The line's colour, a ribbon down the banner's side.
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                .fill(ribbon)
                .frame(width: 6)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lineOpening.banner")
        .task(id: opening.id) {
            try? await Task.sleep(for: GameSession.lineOpeningShown)
            guard !Task.isCancelled else { return }
            close()
        }
    }
}
