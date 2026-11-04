// Decision 566: the new-train card's picture, a port in the app icon's
// style (art-style skill): flat colour, a navy outline, round corners; the
// icon's navy, teal, warm yellow and pale ground, and the model's own
// body, stripe and front colours on the car. A ship at the quay, a gantry
// crane lowering the car onto the quay's rails, bunting and confetti.
// Shapes only, so the app draws it (and animates the car's descent) and a
// test writes it as SVG for the art preview.

/// One shape of the picture, in a 160 × 100 box, y down.
public struct ArrivalArtShape: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A rectangle with corners of radius `r`.
        case rect(x: Double, y: Double, width: Double, height: Double, r: Double)
        case polygon([ArrivalArtPoint])
        case circle(x: Double, y: Double, r: Double)
        /// A line, drawn with its stroke only.
        case line(ArrivalArtPoint, ArrivalArtPoint)
    }

    public let kind: Kind
    /// `0xRRGGBB`, `nil` for none.
    public let fill: Int?
    public let stroke: Int?
    public let strokeWidth: Double
}

public struct ArrivalArtPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// The picture of an arrival.
public enum NewTrainArrivalArt {
    public static let width = 160.0
    public static let height = 100.0

    /// The app icon's colours (docs/UI_THEME.md).
    static let navy = 0x262C57
    static let teal = 0x12A08F
    static let lightTeal = 0x45D3C0
    static let yellow = 0xFFC86B
    static let ground = 0xECEEF6
    static let white = 0xFFFFFF

    /// The picture with the car `drop` of the way down (0 hanging high
    /// over the quay, 1 set on its rails, as a still picture shows it).
    public static func shapes(for arrival: NewTrainArrival, drop: Double = 1) -> [ArrivalArtShape] {
        let drop = min(max(drop, 0), 1)
        var shapes: [ArrivalArtShape] = []
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0, fill: Int?, stroke: Int? = navy, width: Double = 1.5) {
            shapes.append(ArrivalArtShape(kind: .rect(x: x, y: y, width: w, height: h, r: r), fill: fill, stroke: stroke, strokeWidth: stroke == nil ? 0 : width))
        }
        func polygon(_ points: [(Double, Double)], fill: Int, stroke: Int? = navy, width: Double = 1.5) {
            shapes.append(ArrivalArtShape(kind: .polygon(points.map { ArrivalArtPoint($0.0, $0.1) }), fill: fill, stroke: stroke, strokeWidth: stroke == nil ? 0 : width))
        }
        func line(_ a: (Double, Double), _ b: (Double, Double), width: Double = 1) {
            shapes.append(ArrivalArtShape(kind: .line(ArrivalArtPoint(a.0, a.1), ArrivalArtPoint(b.0, b.1)), fill: nil, stroke: navy, strokeWidth: width))
        }

        // Sky, sea and waves.
        rect(0, 0, width, height, fill: ground, stroke: nil)
        rect(0, 76, 84, 24, fill: teal, stroke: nil)
        for (x, y) in [(8.0, 84.0), (30.0, 93.0), (52.0, 86.0), (66.0, 95.0)] {
            rect(x, y, 10, 2, r: 1, fill: lightTeal, stroke: nil)
        }

        // The ship: mast, hull, bridge, containers.
        line((40, 32), (40, 56), width: 2)
        polygon([(4, 66), (78, 66), (72, 84), (10, 84)], fill: navy)
        rect(8, 50, 18, 16, r: 2, fill: white)
        for x in [11.0, 16.0, 21.0] { rect(x, 54, 3, 3, fill: navy, stroke: nil) }
        rect(30, 56, 13, 10, r: 1, fill: yellow)
        rect(45, 56, 13, 10, r: 1, fill: lightTeal)
        rect(60, 56, 12, 10, r: 1, fill: white)

        // The quay: its wall's fenders, the safety line, the rails.
        rect(82, 76, 80, 26, fill: white)
        for y in [82.0, 92.0] {
            shapes.append(ArrivalArtShape(kind: .circle(x: 82, y: y, r: 2.6), fill: navy, stroke: nil, strokeWidth: 0))
        }
        rect(88, 81, 70, 1.6, r: 0.8, fill: yellow, stroke: nil)
        rect(84, 74.4, 76, 1.6, fill: navy, stroke: nil)

        // Bunting from the mast to the crane and down to the stern.
        bunting(from: (40, 32), to: (82, 24), flags: 6, colours: [yellow, teal, arrival.stripe], into: &shapes)
        bunting(from: (40, 32), to: (6, 48), flags: 4, colours: [teal, yellow, arrival.stripe], into: &shapes)

        // The crane's legs, beam, cab and trolley.
        rect(82, 18, 5, 58, r: 1, fill: yellow)
        rect(154, 18, 5, 58, r: 1, fill: yellow)
        rect(14, 13, 145, 6, r: 2, fill: yellow)
        rect(137, 19, 14, 9, r: 2, fill: white)
        rect(141, 21, 6, 3, fill: navy, stroke: nil)
        rect(110, 19, 16, 4, r: 1, fill: navy, stroke: nil)

        // The car on its spreader, the sling to the trolley; set down, its
        // wheels stand on the rails.
        let top = 40 + 14.4 * drop
        line((113, 23), (96, top - 4))
        line((123, 23), (140, top - 4))
        rect(92, top - 5, 52, 2.5, r: 1, fill: navy, stroke: nil)
        rect(88, top, 60, 16, r: 3.5, fill: arrival.body, width: 1.8)
        rect(89, top + 11, 58, 2.4, fill: arrival.stripe, stroke: nil)
        for x in [94.0, 105.0, 116.0, 127.0] { rect(x, top + 3.5, 8, 5, r: 1, fill: navy, stroke: nil) }
        rect(140.5, top + 1, 6.6, 14, r: 2.8, fill: arrival.cab, stroke: nil)
        rect(88, top, 60, 16, r: 3.5, fill: nil, width: 1.8)
        for x in [98.0, 138.0] {
            shapes.append(ArrivalArtShape(kind: .circle(x: x, y: top + 18, r: 2.2), fill: navy, stroke: nil, strokeWidth: 0))
        }

        // Confetti in the sky.
        let confetti: [(Double, Double, Int)] = [
            (26, 6, yellow), (50, 9, arrival.stripe), (64, 4, teal), (96, 7, yellow), (126, 5, teal),
            (150, 8, arrival.stripe), (60, 36, yellow), (72, 44, teal), (100, 30, yellow), (20, 34, arrival.stripe),
        ]
        for (x, y, colour) in confetti {
            polygon([(x, y - 2.2), (x + 1.6, y), (x, y + 2.2), (x - 1.6, y)], fill: colour, width: 0.6)
        }
        return shapes
    }

    /// Triangles along a string from `a` to `b`, hanging down.
    private static func bunting(from a: (Double, Double), to b: (Double, Double), flags: Int, colours: [Int], into shapes: inout [ArrivalArtShape]) {
        shapes.append(ArrivalArtShape(kind: .line(ArrivalArtPoint(a.0, a.1), ArrivalArtPoint(b.0, b.1)), fill: nil, stroke: navy, strokeWidth: 0.8))
        for index in 0..<flags {
            let t0 = (Double(index) + 0.15) / Double(flags), t1 = (Double(index) + 0.85) / Double(flags)
            let p0 = (a.0 + (b.0 - a.0) * t0, a.1 + (b.1 - a.1) * t0)
            let p1 = (a.0 + (b.0 - a.0) * t1, a.1 + (b.1 - a.1) * t1)
            let tip = ((p0.0 + p1.0) / 2, (p0.1 + p1.1) / 2 + 5)
            shapes.append(ArrivalArtShape(
                kind: .polygon([ArrivalArtPoint(p0.0, p0.1), ArrivalArtPoint(p1.0, p1.1), ArrivalArtPoint(tip.0, tip.1)]),
                fill: colours[index % colours.count], stroke: navy, strokeWidth: 0.6
            ))
        }
    }

    /// The picture as an SVG, for the art preview (art-style skill §5):
    /// only the elements and attributes Xcode's catalog takes.
    public static func svg(for arrival: NewTrainArrival, drop: Double = 1) -> String {
        func hex(_ colour: Int?) -> String {
            guard let colour else { return "none" }
            let digits = String(colour, radix: 16, uppercase: true)
            return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
        }
        func n(_ value: Double) -> String {
            let rounded = (value * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(n(width)) \(n(height))\" width=\"\(n(width))\" height=\"\(n(height))\">"]
        for shape in shapes(for: arrival, drop: drop) {
            let paint = "fill=\"\(hex(shape.fill))\" stroke=\"\(hex(shape.stroke))\" stroke-width=\"\(n(shape.strokeWidth))\" stroke-linejoin=\"round\" stroke-linecap=\"round\""
            switch shape.kind {
            case let .rect(x, y, w, h, r):
                lines.append("<rect x=\"\(n(x))\" y=\"\(n(y))\" width=\"\(n(w))\" height=\"\(n(h))\" rx=\"\(n(r))\" \(paint)/>")
            case let .polygon(points):
                let d = points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\(n($0.element.x)) \(n($0.element.y))" }.joined(separator: " ")
                lines.append("<path d=\"\(d) Z\" \(paint)/>")
            case let .circle(x, y, r):
                lines.append("<circle cx=\"\(n(x))\" cy=\"\(n(y))\" r=\"\(n(r))\" \(paint)/>")
            case let .line(a, b):
                lines.append("<path d=\"M\(n(a.x)) \(n(a.y)) L\(n(b.x)) \(n(b.y))\" \(paint)/>")
            }
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }
}
