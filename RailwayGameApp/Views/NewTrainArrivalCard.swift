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
/// is lowered onto the quay.
private struct ArrivalScene: View, Animatable {
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
