import Foundation
import GameCore

/// Decision 632: the collection's ferries and cable cars up close, in the
/// train garage's stage (decision 434, ``Map3DShowcase``): the same models
/// the 3D map draws (decision 585 PR-3's boats, decisions 575 and 615's
/// cabins), laid on open water or ground to turn round, come close to,
/// light at three times of day and photograph.
///
/// Ferries: the two boats side by side on water, bows toward +x level
/// with x 0, the Tamsui–Bali boat at z 0 and the double-ended ferry
/// ``boatSpacing`` further toward +z. Cable cars: a span of rope between
/// two towers for each line, its cabins hanging on the rope nearer +z,
/// one ``cabinSpacing`` apart from x 0 toward −x; the Maokong Gondola's
/// at z 0, the Sun Moon Lake Ropeway's ``lineSpacing`` further.
public enum Map3DCollectionShowcase {
    /// What a page shows.
    public enum Exhibit: String, CaseIterable, Identifiable, Sendable {
        case ferries, cableways
        /// Decision 701: the four aircraft, and the two airports as scenes.
        case aircraft, cityAirport, islandAirport

        public var id: String { rawValue }

        /// Review L19, P3-14: a stage to open: the page and, on the
        /// aircraft page, which aircraft it opens on. One value, so the
        /// cover that opens it cannot read an aircraft tapped before.
        public struct Shown: Identifiable, Hashable, Sendable {
            public let exhibit: Exhibit
            public let focus: Int

            public init(_ exhibit: Exhibit, focus: Int = 0) {
                self.exhibit = exhibit
                self.focus = focus
            }

            public var id: String { "\(exhibit.rawValue).\(focus)" }
        }

        /// The photo sheet's title: "Ferries" / "渡輪", "Cable Cars" / "纜車".
        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .ferries: language.text("Ferries", "渡輪")
            case .cableways: language.text("Cable Cars", "纜車")
            case .aircraft: language.text("Aircraft", "飛機")
            case .cityAirport: language.text("City Airport", "城市機場")
            case .islandAirport: language.text("Island Airport", "離島機場")
            }
        }

        /// Decision 701: whether its models are stood in the ground's own
        /// mesh (``Map3DAirShowcase``) rather than drawn from the model pack.
        public var isAir: Bool { self == .aircraft || self == .cityAirport || self == .islandAirport }

        /// The collection's button that opens it.
        public func openTitle(in language: DisplayLanguage) -> String {
            switch self {
            case .ferries: language.text("Ferries up close", "近看渡輪")
            case .cableways: language.text("Cable cars up close", "近看纜車")
            case .aircraft: language.text("Aircraft up close", "近看飛機")
            case .cityAirport: language.text("City airport up close", "近看城市機場")
            case .islandAirport: language.text("Island airport up close", "近看離島機場")
            }
        }

        /// The SF Symbol by the button.
        public var symbol: String {
            switch self {
            case .ferries: "ferry.fill"
            case .cableways: "cablecar.fill"
            case .aircraft: "airplane"
            case .cityAirport: "airplane.departure"
            case .islandAirport: "airplane.arrival"
            }
        }

        /// The camera's ready views' names: the first is the bow or a cabin.
        public func viewName(_ view: Map3DShowcase.View, in language: DisplayLanguage) -> String {
            switch (self, view) {
            case (.ferries, .closeUp): language.text("Bow", "船頭特寫")
            case (.cableways, .closeUp): language.text("Cabin", "吊廂特寫")
            case (.aircraft, .closeUp): language.text("Nose", "機頭特寫")
            case (.cityAirport, .closeUp), (.islandAirport, .closeUp): language.text("Stand", "機位特寫")
            default: view.name(in: language)
            }
        }

        /// VoiceOver's hints for the photo and hide buttons, and the turntable.
        public func photoHint(in language: DisplayLanguage) -> String {
            switch self {
            case .ferries: language.text("Takes a photo of the boats to save or share.", "拍下渡輪的照片，可以存起來或分享。")
            case .cableways: language.text("Takes a photo of the cabins to save or share.", "拍下吊廂的照片，可以存起來或分享。")
            case .aircraft: language.text("Takes a photo of the aircraft to save or share.", "拍下飛機的照片，可以存起來或分享。")
            case .cityAirport, .islandAirport: language.text("Takes a photo of the airport to save or share.", "拍下機場的照片，可以存起來或分享。")
            }
        }

        public func hideHint(in language: DisplayLanguage) -> String {
            switch self {
            case .ferries: language.text("Leaves only the boats on screen. Tap the picture to bring the buttons back.",
                                         "畫面只留下渡輪。點一下畫面，按鈕就回來。")
            case .cableways: language.text("Leaves only the cable cars on screen. Tap the picture to bring the buttons back.",
                                           "畫面只留下纜車。點一下畫面，按鈕就回來。")
            case .aircraft: language.text("Leaves only the aircraft on screen. Tap the picture to bring the buttons back.",
                                          "畫面只留下飛機。點一下畫面，按鈕就回來。")
            case .cityAirport, .islandAirport: language.text("Leaves only the airport on screen. Tap the picture to bring the buttons back.",
                                                             "畫面只留下機場。點一下畫面，按鈕就回來。")
            }
        }

        public func turntableHint(in language: DisplayLanguage) -> String {
            switch self {
            case .ferries: language.text("Turns the camera slowly round the boats.", "鏡頭慢慢繞著渡輪轉。")
            case .cableways: language.text("Turns the camera slowly round the cabins.", "鏡頭慢慢繞著吊廂轉。")
            case .aircraft: language.text("Turns the camera slowly round the aircraft.", "鏡頭慢慢繞著飛機轉。")
            case .cityAirport, .islandAirport: language.text("Turns the camera slowly round the stand.", "鏡頭慢慢繞著機位轉。")
            }
        }
    }

    /// One model stood on the stage: its name in the pack, its foot
    /// (a boat's waterline middle, a cabin's grip on the rope, a tower's
    /// foot) and the way its +x faces.
    public struct Piece: Equatable, Sendable {
        public let model: String
        public let at: Map3DPoint
        public let forward: Map3DPoint
    }

    /// A straight rope from one tower's sheave to the other's.
    public struct Rope: Equatable, Sendable {
        public let from: Map3DPoint
        public let to: Map3DPoint
    }

    /// What a page lays: its pieces, ropes, and where the camera looks.
    public struct Layout: Equatable, Sendable {
        public let exhibit: Exhibit
        public let pieces: [Piece]
        public let ropes: [Rope]
        /// The first exhibit's middle and length along x (the first boat;
        /// the first line's cabins), for the close and side views.
        public let focus: Map3DPoint
        public let focusLength: Float
        /// The close view's distance.
        public let closeDistance: Float
        /// Everything shown, low and high corners (y the ground's 0).
        public let low: Map3DPoint
        public let high: Map3DPoint
        /// Decision 701: whether the far models are shown, and where the
        /// close and side views stand (the camera's heading, radians): ahead
        /// of a boat or cabin's +x and to one side, and beside it.
        public var far = false
        public var closeHeading: Float = -120 * .pi / 180
        public var sideHeading: Float = .pi
        /// The way up the screen in the view from above: +z, or +x for
        /// what is laid across rather than along (the aircraft's row).
        public var overheadHeading: Float = .pi
    }

    /// The boats' distance apart, middle to middle: the two beams' halves
    /// (2.2 and 4.1 m) and some 8 m of water between.
    public static let boatSpacing: Float = 14
    /// The cabins' distance apart along the rope, and the lines' apart.
    public static let cabinSpacing: Float = 7
    public static let lineSpacing: Float = 18
    /// How far the towers stand past the first and last cabin: past the
    /// close view's eye (``Layout/closeDistance``), so no tower stands
    /// between it and the cabin.
    static let towerClearance: Float = 14
    /// The ground or water's reach past what is shown: to the horizon of
    /// the view from above (the edge showed in the first screenshots).
    static let margin: Float = 400
    /// How much of the screen's height the buttons under the picture
    /// cover (on a phone on its side, about the lower half): every view
    /// raises what it shows by this much (decision 632's screenshots).
    static let coveredBelow: Float = 0.45

    /// The cabins of each line, in order: Maokong's two, Sun Moon Lake's four.
    static let cableLines: [[String]] = [
        Map3DCableCar.Cabin.allCases.map { "cablecar-cabin-" + $0.rawValue },
        Map3DCableCar.SunMoonCabin.allCases.map { "cablecar-cabin-sunmoon-" + $0.rawValue }
    ]

    /// `exhibit` laid out, with its far models when `far`. Decision 701:
    /// `focus` picks which of an aircraft page's aircraft the close and
    /// side views look at (the first when out of range).
    public static func layout(_ exhibit: Exhibit, far: Bool = false, focus: Int = 0) -> Layout {
        let suffix = far ? "-far" : ""
        let ahead = Map3DPoint(1, 0, 0)
        switch exhibit {
        case .aircraft, .cityAirport, .islandAirport:
            let parked = Map3DAirShowcase.parked(exhibit)
            let shown = parked.indices.contains(focus) ? parked[focus] : parked[0]
            let extent = Map3DAirShowcase.extent(exhibit) ?? (.zero, .zero)
            // An aircraft is as wide as it is long and only the upper half
            // of the screen is clear of the buttons: the close view stands
            // back by nearly twice its length, an airport's far enough to
            // take in the bridge or the terminal behind.
            let close = shown.length * (exhibit == .aircraft ? 1.8 : 1.6)
            var layout = Layout(exhibit: exhibit, pieces: [], ropes: [], focus: shown.middle + Map3DPoint(0, shown.height * 0.4, 0),
                                focusLength: max(shown.length, shown.wingspan) * (exhibit == .aircraft ? 1 : 1.5),
                                closeDistance: min(max(close, 18), Map3DShowcase.farthest), low: extent.low, high: extent.high)
            layout.far = far
            // An airport is looked at from its apron, the terminal behind
            // the aircraft: the city's from behind the first jet's tail and
            // its open side, the island's from the runway's side.
            switch exhibit {
            case .cityAirport: (layout.closeHeading, layout.sideHeading) = (-60 * .pi / 180, 0)
            case .islandAirport: (layout.sideHeading, layout.overheadHeading) = (-.pi / 2, .pi / 2)
            default: layout.overheadHeading = .pi / 2
            }
            return layout
        case .ferries:
            let boats = Map3DFerry.Boat.allCases
            let pieces = boats.enumerated().map { index, boat in
                Piece(model: Map3DFerry.name(boat, far: far), at: Map3DPoint(-boat.length / 2, Map3DFerries.waterLift, Float(index) * boatSpacing),
                      forward: ahead)
            }
            let longest = boats.map(\.length).max() ?? 0
            let first = boats[0]
            return Layout(exhibit: exhibit, pieces: pieces, ropes: [], focus: Map3DPoint(-first.length / 2, first.height / 2, 0),
                          focusLength: first.length, closeDistance: 26,
                          low: Map3DPoint(-longest, 0, -Map3DFerry.Boat.cijin.beam), high: Map3DPoint(0, Map3DFerry.Boat.cijin.height,
                                                                                                         Float(boats.count - 1) * boatSpacing + Map3DFerry.Boat.cijin.beam))
        case .cableways:
            let ropeHeight = Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight)
            let most = cableLines.map(\.count).max() ?? 0
            let towerFront = towerClearance - cabinSpacing / 2
            let towerBack = -Float(most - 1) * cabinSpacing - cabinSpacing / 2 - towerClearance
            var pieces: [Piece] = [], ropes: [Rope] = []
            let half = Map3DCableCar.ropeSpacing / 2
            for (line, cabins) in cableLines.enumerated() {
                let z = Float(line) * lineSpacing
                for x in [towerFront, towerBack] {
                    pieces.append(Piece(model: "cablecar-tower" + suffix, at: Map3DPoint(x, 0, z), forward: ahead))
                }
                for side: Float in [-1, 1] {
                    ropes.append(Rope(from: Map3DPoint(towerBack, ropeHeight, z + side * half), to: Map3DPoint(towerFront, ropeHeight, z + side * half)))
                }
                // On the rope nearer +z, as the 3D map hangs an outbound cabin.
                for (index, cabin) in cabins.enumerated() {
                    pieces.append(Piece(model: cabin + suffix, at: Map3DPoint(-Float(index) * cabinSpacing, ropeHeight, z + half), forward: ahead))
                }
            }
            let firstCount = Float(cableLines[0].count)
            let cabinMiddle = ropeHeight - Map3DCableCar.cabinDrop + Map3DCableways.cabinHeight / 2
            return Layout(exhibit: exhibit, pieces: pieces, ropes: ropes,
                          focus: Map3DPoint(-(firstCount - 1) * cabinSpacing / 2, cabinMiddle, half),
                          focusLength: towerFront - towerBack, closeDistance: 9,
                          low: Map3DPoint(towerBack, 0, -half), high: Map3DPoint(towerFront, ropeHeight + 1, Float(cableLines.count - 1) * lineSpacing + half))
        }
    }

    // MARK: - The scene

    /// The open water or ground under `layout`, ``margin`` past it.
    public static func ground(_ layout: Layout) -> Map3DScene.Chunk {
        var mesh = Map3DMesh()
        let low = Map3DPoint(layout.low.x - margin, 0, layout.low.z - margin), high = Map3DPoint(layout.high.x + margin, 0, layout.high.z + margin)
        let water = layout.exhibit == .ferries
        let y: Float = water ? Map3DFerries.waterLift : 0
        let colour = water ? Map3DPalette.water : layout.exhibit.isAir ? Map3DAirShowcase.groundColour : Map3DShowcase.groundColour
        mesh.addQuad(Map3DPoint(low.x, y, low.z), Map3DPoint(low.x, y, high.z), Map3DPoint(high.x, y, high.z), Map3DPoint(high.x, y, low.z),
                     color: colour)
        if water { mesh.makeWater(from: 0) }
        // Decision 701: the aircraft and airports stand in the ground's
        // own mesh, all of it drawn at every distance.
        if layout.exhibit.isAir { mesh.append(Map3DAirShowcase.mesh(layout.exhibit, far: layout.far)) }
        let count = mesh.indices.count
        return Map3DScene.Chunk(column: 0, row: 0, mesh: mesh, baseIndexCount: count, far: Map3DMesh(), farBoxes: [], close: Map3DMesh(),
                                standIn: Map3DMesh(), shadows: Map3DMesh(), props: [], minimum: Map3DPoint(low.x, -1, low.z),
                                maximum: Map3DPoint(high.x, layout.high.y + 2, high.z),
                                cityTops: Array(repeating: -.infinity, count: Map3DSeeThrough.cells * Map3DSeeThrough.cells),
                                signs: [], coarse: false)
    }

    /// The pieces and ropes as instances of `pack`'s models; a piece the
    /// pack lacks is left out.
    public static func frame(_ layout: Layout, pack: Map3DModelPack = .standard) -> Map3DTrains.Frame {
        var frame = Map3DTrains.Frame()
        for piece in layout.pieces {
            guard let index = pack.index(of: piece.model) else { continue }
            frame.instances.append(.prop(index, at: piece.at, forward: piece.forward, scale: 1, tint: 0xFFFFFF))
        }
        if let rope = pack.index(of: "cablecar-rope") {
            for line in layout.ropes {
                frame.instances.append(Map3DCableways.rope(rope, from: line.from, to: line.to, left: Map3DPoint(0, 0, -1)))
            }
        }
        return frame
    }

    /// The camera of `view` over `layout` on a screen `viewport` points,
    /// as the garage's (``Map3DShowcase/camera(_:rows:viewport:)``).
    public static func camera(_ view: Map3DShowcase.View, layout: Layout, viewport: (width: Float, height: Float)) -> Map3DCamera {
        var camera = Map3DCamera(viewport: viewport)
        let aspect = max(viewport.width, 1) / max(viewport.height, 1)
        let halfTall = tanf(Map3DCamera.fieldOfView / 2), halfWide = halfTall * aspect
        // Half the screen's height at the target, and the part of it the
        // buttons leave: the target goes that far below what is shown.
        // Decision 701: an aircraft is as wide as it is long, so it is
        // raised to the middle of the part the buttons leave.
        let raise = layout.exhibit.isAir ? Float(0.5) : coveredBelow / 2
        switch view {
        case .closeUp:
            camera.heading = layout.closeHeading
            camera.pitch = .pi / 2 - 0.39
            camera.distance = layout.closeDistance
            camera.target = layout.focus - Map3DPoint(0, raise * camera.distance * halfTall, 0)
        case .side:
            camera.heading = layout.sideHeading
            camera.pitch = 82 * .pi / 180
            // Decision 701: an aircraft's tail stands a third of its length
            // high, more than the clear part of a wide screen shows at the
            // distance its length alone asks for.
            camera.distance = min(max(layout.focusLength / 2 * (layout.exhibit == .aircraft ? 1.7 : 1.15) / halfWide, 12), Map3DShowcase.farthest)
            camera.target = layout.focus - Map3DPoint(0, raise * camera.distance * halfTall, 0)
        case .overhead:
            // Looking nearly straight down with +z up the screen (or +x:
            // decision 701's ``Layout/overheadHeading``).
            let up = Map3DPoint(sinf(layout.overheadHeading), 0, -cosf(layout.overheadHeading))
            let turned = abs(up.x) > 0.5
            let along = turned ? layout.high.z - layout.low.z : layout.high.x - layout.low.x
            let across = turned ? layout.high.x - layout.low.x : layout.high.z - layout.low.z
            camera.heading = layout.overheadHeading
            camera.pitch = 20 * .pi / 180
            // Decision 701: an airport is its own ground, so it needs no
            // margin of stage round it.
            let margin: (Float, Float) = layout.exhibit.isAir ? (2, 1.08) : (6, 1.3)
            let fit = max(along / 2 * 1.15 / halfWide, (across / 2 + margin.0) * margin.1 / ((1 - coveredBelow) * halfTall))
            camera.distance = min(max(fit, 30), Map3DShowcase.farthest)
            camera.target = Map3DPoint((layout.low.x + layout.high.x) / 2, 0, (layout.low.z + layout.high.z) / 2)
                - up * (coveredBelow * camera.distance * halfTall)
        }
        return camera
    }
}

/// Decision 632: what the garage's stage shows: trains (decision 434) or
/// one of the collection's other pages.
public enum Map3DShowcaseContent: Equatable, Sendable {
    case trains([Map3DShowcase.Row])
    case exhibit(Map3DCollectionShowcase.Layout)

    public func ground() -> Map3DScene.Chunk {
        switch self {
        case .trains(let rows): Map3DShowcase.ground(rows)
        case .exhibit(let layout): Map3DCollectionShowcase.ground(layout)
        }
    }

    public func frame(pack: Map3DModelPack = .standard) -> Map3DTrains.Frame {
        switch self {
        case .trains(let rows): Map3DShowcase.frame(rows, pack: pack)
        case .exhibit(let layout): Map3DCollectionShowcase.frame(layout, pack: pack)
        }
    }

    public func camera(_ view: Map3DShowcase.View, viewport: (width: Float, height: Float)) -> Map3DCamera {
        switch self {
        case .trains(let rows): Map3DShowcase.camera(view, rows: rows, viewport: viewport)
        case .exhibit(let layout): Map3DCollectionShowcase.camera(view, layout: layout, viewport: viewport)
        }
    }
}
