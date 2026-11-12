import Foundation
import GameCore

// Decision 699: the airports on the 3D map of a real-world game. Each
// airfield OpenStreetMap maps (``RealAirfields``) is laid on the drawn
// ground: its runways in asphalt with their painted marks, its taxiways
// with their yellow centre lines, its aprons in concrete, its jet bridges
// and its control towers (decision 698's tower), and at night the lights
// along its runways and taxiways and over its stands. The way of it is
// the reference's `tw3d-reference-clean/source/js/airport.js` (Songshan
// from its OpenStreetMap aeroways); the marks are flat strips here rather
// than a shader's, as the roads' paint is. The aircraft are drawn each
// frame (``Map3DAircraft``).

extension Map3DScene.Builder {
    /// What the airfields are painted in: the studies' pavement greys
    /// (decision 698), which stand off the map's pale ground, and the
    /// roads' paint.
    enum Airfield {
        static let asphalt = Map3DStudyColor.asphalt
        static let taxiway = Map3DStudyColor.taxi
        static let apron = Map3DStudyColor.deck
        static let paint = Map3DColor.rgb(0xF2F3EE)
        static let yellow = Map3DStudyColor.warm
        /// Over the ground: the aprons under the taxiways under the
        /// runways, each over the base map's roads (0.28 to 0.36), and the
        /// paint over them all.
        static let apronLift: Float = 0.40
        static let taxiwayLift: Float = 0.44
        static let runwayLift: Float = 0.48
        static let paintLift: Float = 0.54
        /// The paint's widths, metres: twice a real runway's 0.9 m, so
        /// they still show from the game's usual height.
        static let line: Float = 1.8
        static let taxiLine: Float = 1.2
        /// The night lights' colours.
        static let white = Map3DStudyColor.lamp
        static let green = Map3DStudyColor.lampGreen
        static let flood = Map3DColor.rgb(0xFFE9B8)
        /// What the 3D look leaves as it is (``Map3DLook/kept``).
        static let kept: Set<UInt32> = [asphalt, taxiway, apron, paint, yellow, terminalRoof, terminalWall, Map3DStudyColor.roof,
                                        Map3DStudyColor.pane, Map3DStudyColor.base]
        /// A terminal's roof and walls (``RealKind/terminal``): decision
        /// 698's blue-grey roof a step deeper, over white walls.
        static let terminalRoof = Map3DColor.rgb(0x6F86A6)
        static let terminalWall = Map3DColor.rgb(0xF4F5F7)
    }

    /// The scene's region, in the scene's metres.
    var sceneBounds: Map3DBaseMap.Bounds {
        Map3DBaseMap.Bounds(minX: (region.minX - originX) / Self.metre, minZ: (region.minY - originY) / Self.metre,
                            maxX: (region.maxX - originX) / Self.metre, maxZ: (region.maxY - originY) / Self.metre)
    }

    /// Decision 699: `fields`' airfields in the scene, laid on the world
    /// by `frame`. Returns the 64 m cells the runways lie on, which keep
    /// no building.
    @discardableResult
    mutating func addAirfields(_ fields: RealAirfields, frame: RealWorldFrame) -> Set<Map3DScene.ChunkKey> {
        let bounds = sceneBounds
        func place(_ point: RealAirfields.Point) -> Map3DBaseMap.Point {
            let at = frame.worldPosition(latitude: point.latitude, longitude: point.longitude)
            return Map3DBaseMap.Point(x: (at.x - originX) / Self.metre, z: (at.y - originY) / Self.metre)
        }
        func inside(_ point: Map3DBaseMap.Point, margin: Double = 0) -> Bool {
            point.x >= bounds.minX - margin && point.x <= bounds.maxX + margin && point.z >= bounds.minZ - margin && point.z <= bounds.maxZ + margin
        }
        var taken = Set<Map3DScene.ChunkKey>(), onRunways = Set<Map3DScene.ChunkKey>()
        // The game's airports stand at their terminals' middles (decision
        // 695): the building there is a terminal.
        for airport in world.airports {
            let at = point(x: Double(airport.point.x), y: Double(airport.point.y), height: 0)
            terminalSpots.append((Map3DPoint(at.x, 0, at.z), 60))
        }
        for field in fields.fields {
            let runways = field.runways.map { (runway: $0, line: $0.line.map(place)) }
            guard runways.contains(where: { $0.line.contains { inside($0, margin: 1_500) } })
                || field.aprons.contains(where: { $0.contains { inside(place($0), margin: 800) } }) else { continue }
            // Decision 707: no house of the game's by the runways, on the
            // taxiways or on the aprons.
            var clear = AirfieldClear.Field()
            for (runway, line) in runways {
                let length = zip(line, line.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.z - $1.0.z) }
                clear.add(line, half: max(runway.width / 2, AirfieldClear.runwayStrip(length: length)))
            }
            for taxiway in field.taxiways { clear.add(taxiway.line.map(place), half: taxiway.width / 2 + AirfieldClear.taxiwayMargin) }
            for apron in field.aprons { clear.add(apron: apron.map(place)) }
            airfieldClear.fields.append(clear)
            for apron in field.aprons {
                addPavement(apron.map(place), bounds: bounds, color: Airfield.apron, lift: Airfield.apronLift)
            }
            for taxiway in field.taxiways {
                let line = taxiway.line.map(place)
                addStrip(line, bounds: bounds, width: taxiway.width, lift: Airfield.taxiwayLift, color: Airfield.taxiway, paint: nil, taking: &taken)
            }
            for (runway, line) in runways {
                addStrip(Self.shortened(line, by: Double(runway.width) / 2), bounds: bounds, width: runway.width, lift: Airfield.runwayLift,
                         color: Airfield.asphalt, paint: nil, taking: &onRunways)
            }
            for taxiway in field.taxiways {
                let line = taxiway.line.map(place)
                addStrip(line, bounds: bounds, width: Airfield.taxiLine, lift: Airfield.paintLift, color: Airfield.yellow, paint: nil, taking: &taken)
                addLights(along: line, every: 45, offsets: [0], colour: Airfield.green, radius: 5, strength: 0.75, bounds: bounds)
            }
            for (runway, line) in runways { addRunwayPaint(runway, line: line, bounds: bounds) }
            for stand in field.stands {
                let nose = place(stand.nose)
                guard inside(nose) else { continue }
                // The floodlights' pool over the aircraft, behind its nose.
                let back = stand.heading.map { Self.direction(degrees: $0) } ?? (x: 0, z: 0)
                addPool(at: Map3DBaseMap.Point(x: nose.x - back.x * 18, z: nose.z - back.z * 18), colour: Airfield.flood, radius: 28, strength: 0.42)
            }
            // Where passengers board, past the scene's edge too: a part
            // of the scene built alone finds the same terminals.
            for bridge in field.bridges {
                let from = place(bridge.from), to = place(bridge.to)
                terminalSpots.append((Map3DPoint(Float(from.x), 0, Float(from.z)), 30))
                guard inside(from), inside(to) else { continue }
                addJetBridge(from: from, to: to)
            }
            // With no jet bridge mapped, the terminal is the big building
            // by the stands.
            if field.bridges.isEmpty {
                for stand in field.stands {
                    let nose = place(stand.nose)
                    terminalSpots.append((Map3DPoint(Float(nose.x), 0, Float(nose.z)), 70))
                }
            }
            for tower in field.towers {
                let at = place(tower.at)
                guard inside(at) else { continue }
                let foot = Map3DPoint(Float(at.x), drawnGround(x: Float(at.x), z: Float(at.z)), Float(at.z))
                let model = Self.controlTower(height: tower.height)
                mesh(at: foot) { $0.append(model, at: foot, forward: Map3DPoint(1, 0, 0)) }
            }
        }
        return onRunways
    }

    /// Decision 699: whether the building of `outline` (scene points) is an
    /// airport's terminal: 1,500 m² or more, a wall within reach of where
    /// passengers board (``terminalSpots``).
    func isTerminal(_ outline: [Map3DPoint]) -> Bool {
        guard !terminalSpots.isEmpty, outline.count >= 3, abs(Self.signedArea(outline)) >= 1_500 else { return false }
        let low = (x: outline.map(\.x).min() ?? 0, z: outline.map(\.z).min() ?? 0), high = (x: outline.map(\.x).max() ?? 0, z: outline.map(\.z).max() ?? 0)
        for spot in terminalSpots {
            let p = spot.at, reach = spot.reach
            guard p.x > low.x - reach, p.x < high.x + reach, p.z > low.z - reach, p.z < high.z + reach else { continue }
            // Standing over the spot (a hall wider than the reach).
            if NoBuild.inside(p.x, p.z, outline.map { ($0.x, $0.z) }) { return true }
            for (index, a) in outline.enumerated() {
                let b = outline[(index + 1) % outline.count]
                let dx = b.x - a.x, dz = b.z - a.z, length2 = dx * dx + dz * dz
                let t = length2 > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.z - a.z) * dz) / length2)) : 0
                let ox = a.x + t * dx - p.x, oz = a.z + t * dz - p.z
                if ox * ox + oz * oz <= reach * reach { return true }
            }
        }
        return false
    }

    /// Decision 699: the buildings of `outlines` (scene points) that stand
    /// against a terminal (within 30 m of one, 1,500 m² or more) are
    /// terminals too: a hall behind its piers. Each one found joins
    /// ``terminalSpots``, so ``isTerminal(_:)`` says so; twice over, for a
    /// hall behind a hall.
    mutating func joinTerminals(_ outlines: [[Map3DPoint]]) {
        guard !terminalSpots.isEmpty else { return }
        // Only those within 600 m of where passengers board.
        let near = outlines.filter { outline in
            outline.count >= 3 && abs(Self.signedArea(outline)) >= 1_500 && terminalSpots.contains { spot in
                abs(spot.at.x - outline[0].x) < 600 && abs(spot.at.z - outline[0].z) < 600
            }
        }
        var found = near.map { isTerminal($0) }
        for _ in 0..<2 {
            var added: [(at: Map3DPoint, reach: Float)] = []
            for (index, outline) in near.enumerated() where found[index] {
                // Its outline, a point every 20 m or so.
                for (at, a) in outline.enumerated() {
                    let b = outline[(at + 1) % outline.count]
                    let steps = max(1, Int(((b - a).length / 20).rounded(.up)))
                    for step in 0..<steps { added.append((a + (b - a) * (Float(step) / Float(steps)), 30)) }
                }
            }
            terminalSpots += added
            var grew = false
            for (index, outline) in near.enumerated() where !found[index] && isTerminal(outline) {
                found[index] = true
                grew = true
            }
            if !grew { break }
        }
    }

    /// Decision 699: on a terminal's flat roof (`outline`, at the roof's
    /// height), a white edge all round; and on a `plain` one that fills
    /// its `box`, a skylight along its middle and white ribs across.
    static func addTerminalRoof(to mesh: inout Map3DMesh, outline: [Map3DPoint], box: (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float),
                                plain: Bool) {
        let white = Airfield.terminalWall, up = Map3DPoint(0, 0.12, 0), turn = signedArea(outline) > 0 ? Float(1) : -1
        for (at, a) in outline.enumerated() {
            let b = outline[(at + 1) % outline.count]
            guard let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized else { continue }
            // Inward: to the left of a counter-clockwise outline's way.
            let inward = Map3DPoint(-along.z, 0, along.x) * (1.8 * turn)
            mesh.addFlat([a + up, b + up, b + inward + up, a + inward + up], triangles: [0, 1, 2, 0, 2, 3], color: white)
        }
        guard plain, box.width > 14, abs(signedArea(outline)) > 0.85 * box.length * box.width else { return }
        let height = outline[0].y, across = Map3DPoint(-box.along.z, 0, box.along.x)
        let centre = Map3DPoint(box.centre.x, height, box.centre.z)
        func strip(_ middle: Map3DPoint, _ way: Map3DPoint, length: Float, width: Float, lift: Float, _ color: UInt32) {
            let side = Map3DPoint(-way.z, 0, way.x) * (width / 2), half = way * (length / 2), rise = Map3DPoint(0, lift, 0)
            mesh.addFlat([middle - half - side + rise, middle + half - side + rise, middle + half + side + rise, middle - half + side + rise],
                         triangles: [0, 1, 2, 0, 2, 3], color: color)
        }
        var at = -box.length / 2 + 12
        while at < box.length / 2 - 6 {
            strip(centre + box.along * at, across, length: box.width - 5, width: 1.4, lift: 0.14, white)
            at += 18
        }
        strip(centre, box.along, length: box.length - 8, width: min(8, box.width * 0.16), lift: 0.18, Map3DStudyColor.pane)
    }

    /// `line` with `metres` taken off each end (``addStrip`` draws a half
    /// width past them, which a runway's ends do not want).
    static func shortened(_ line: [Map3DBaseMap.Point], by metres: Double) -> [Map3DBaseMap.Point] {
        guard line.count >= 2 else { return line }
        var line = line
        func moved(_ a: Map3DBaseMap.Point, toward b: Map3DBaseMap.Point) -> Map3DBaseMap.Point {
            let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
            guard length > 2 * metres else { return a }
            return Map3DBaseMap.Point(x: a.x + (b.x - a.x) * metres / length, z: a.z + (b.z - a.z) * metres / length)
        }
        line[0] = moved(line[0], toward: line[1])
        line[line.count - 1] = moved(line[line.count - 1], toward: line[line.count - 2])
        return line
    }

    /// The level way `degrees` clockwise from north points, in the scene
    /// (x east, z south).
    static func direction(degrees: Double) -> (x: Double, z: Double) {
        let angle = degrees * .pi / 180
        return (sin(angle), -cos(angle))
    }

    /// A paved area inside `ring` (not closed), cut to the ground's
    /// triangles as the base map's cover is (``addArea(_:taking:)``).
    mutating func addPavement(_ ring: [Map3DBaseMap.Point], bounds: Map3DBaseMap.Bounds, color: UInt32, lift: Float) {
        let lowX = max(ring.map(\.x).min() ?? 0, bounds.minX), highX = min(ring.map(\.x).max() ?? 0, bounds.maxX)
        let lowZ = max(ring.map(\.z).min() ?? 0, bounds.minZ), highZ = min(ring.map(\.z).max() ?? 0, bounds.maxZ)
        guard ring.count >= 3, lowX < highX, lowZ < highZ else { return }
        for row in gridCell(lowZ, origin: originY)...gridCell(highZ, origin: originY) {
            let top = max(gridLine(row, origin: originY), bounds.minZ), bottom = min(gridLine(row + 1, origin: originY), bounds.maxZ)
            guard top < bottom else { continue }
            let band = Self.clipRings([ring], by: [{ $0.z - top }, { bottom - $0.z }])
            guard band.first?.isEmpty == false else { continue }
            for column in gridCell(lowX, origin: originX)...gridCell(highX, origin: originX) {
                let left = max(gridLine(column, origin: originX), bounds.minX), right = min(gridLine(column + 1, origin: originX), bounds.maxX)
                guard left < right else { continue }
                let cell = Self.clipRings(band, by: [{ $0.x - left }, { right - $0.x }])
                guard cell.first?.isEmpty == false else { continue }
                let westX = gridLine(column, origin: originX), northZ = gridLine(row, origin: originY)
                for side in [1.0, -1.0] {
                    let piece = Self.clipRings(cell, by: [{ side * (($0.z - northZ) - ($0.x - westX)) }])
                    guard let outline = piece.first, outline.count >= 3, abs(Self.area(outline)) > 0.5 else { continue }
                    var triangles = Earcut.triangulate([outline.map { (x: $0.x, y: $0.z) }])
                    guard !triangles.isEmpty else { continue }
                    var points = outline.map { point -> Map3DPoint in
                        let x = Float(point.x), z = Float(point.z)
                        return Map3DPoint(x, drawnGround(x: x, z: z) + lift, z)
                    }
                    (points, triangles) = outsideTrenches(points, triangles: triangles, lift: lift)
                    guard !triangles.isEmpty else { continue }
                    let middle = Map3DPoint(Float((westX + gridLine(column + 1, origin: originX)) / 2), 0,
                                            Float((northZ + gridLine(row + 1, origin: originY)) / 2))
                    mesh(at: middle) { $0.addFlat(points, triangles: triangles, color: color) }
                }
            }
        }
    }

    /// A pool of night light on the ground round `at`.
    mutating func addPool(at: Map3DBaseMap.Point, colour: UInt32, radius: Float, strength: Float) {
        let centre = Map3DPoint(Float(at.x), 0, Float(at.z))
        let ring = Map3DProp.poolRing.map { centre + $0 * radius }
        shadows[key(of: centre), default: Map3DMesh()].addPool(centre: onGround([centre])[0], ring: onGround(ring), colour: colour, strength: strength)
    }

    /// Night lights along `line`: a pool every `spacing` metres, at each of
    /// `offsets` metres to its left.
    mutating func addLights(along line: [Map3DBaseMap.Point], every spacing: Double, offsets: [Double], colour: UInt32, radius: Float,
                            strength: Float, bounds: Map3DBaseMap.Bounds) {
        var travelled = 0.0, next = spacing / 2
        for (a, b) in zip(line, line.dropFirst()) {
            let length = ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
            guard length > 0.01 else { continue }
            let along = (x: (b.x - a.x) / length, z: (b.z - a.z) / length)
            while next <= travelled + length {
                let t = next - travelled
                for offset in offsets {
                    let at = Map3DBaseMap.Point(x: a.x + along.x * t + along.z * offset, z: a.z + along.z * t - along.x * offset)
                    if at.x > bounds.minX, at.x < bounds.maxX, at.z > bounds.minZ, at.z < bounds.maxZ {
                        addPool(at: at, colour: colour, radius: radius, strength: strength)
                    }
                }
                next += spacing
            }
            travelled += length
        }
    }

    /// A runway's paint and lights: its edge lines, its dashed centre line,
    /// and at each end the threshold's bars, the numbers, the touchdown
    /// zone's bars and the aiming point (the reference's `runwayMaterial`,
    /// to ICAO's pattern; a short runway has only the bars, the numbers and
    /// the aiming point).
    mutating func addRunwayPaint(_ runway: RealAirfields.Runway, line: [Map3DBaseMap.Point], bounds: Map3DBaseMap.Bounds) {
        guard let first = line.first, let last = line.last, line.count >= 2 else { return }
        let length = ((last.x - first.x) * (last.x - first.x) + (last.z - first.z) * (last.z - first.z)).squareRoot()
        guard length > 300 else { return }
        var none = Set<Map3DScene.ChunkKey>()
        let half = Double(runway.width) / 2, lineWidth = Double(Airfield.line)
        let names = runway.ref.split(separator: "/").map(String.init)
        // A strip from `from` to `to` metres along the way `along` from
        // `origin`, its middle `across` metres to the left.
        func bar(_ origin: Map3DBaseMap.Point, _ along: (x: Double, z: Double), from: Double, to: Double, across: Double, width: Double) {
            // ``addStrip`` draws a half width past each end.
            let a = from + width / 2, b = to - width / 2
            guard b > a else { return }
            func point(_ s: Double) -> Map3DBaseMap.Point {
                Map3DBaseMap.Point(x: origin.x + along.x * s + along.z * across, z: origin.z + along.z * s - along.x * across)
            }
            addStrip([point(a), point(b)], bounds: bounds, width: Float(width), lift: Airfield.paintLift, color: Airfield.paint, paint: nil,
                     taking: &none)
        }
        let forward = (x: (last.x - first.x) / length, z: (last.z - first.z) / length)
        for side in [-1.0, 1.0] { bar(first, forward, from: 0, to: length, across: side * (half - 1.5 - lineWidth / 2), width: lineWidth) }
        // The centre line: 30 m of paint, 20 m of gap, between the numbers.
        var s = 90.0
        while s + 30 < length - 90 {
            bar(first, forward, from: s, to: s + 30, across: 0, width: lineWidth)
            s += 50
        }
        for (end, origin) in [(0, first), (1, last)] {
            let along = end == 0 ? forward : (x: -forward.x, z: -forward.z)
            // The threshold's bars, from 6 m to 36 m.
            let bars = max(4, Int((half - 3) / 3.6))
            for index in 0..<bars {
                for side in [-1.0, 1.0] { bar(origin, along, from: 6, to: 36, across: side * (2.7 + 3.6 * Double(index)), width: 1.8) }
            }
            // The numbers, read by the pilot landing over this end; the
            // letter of a parallel runway before them.
            let name = names.indices.contains(end) ? names[end] : ""
            let digits = name.filter(\.isNumber), letter = name.first { "LRC".contains($0) }
            var from = 46.0
            if let letter {
                addRunwayCharacter(letter, origin: origin, along: along, from: from, across: 0, bounds: bounds)
                from += 15
            }
            for (index, digit) in digits.enumerated() {
                let across = digits.count == 1 ? 0 : (index == 0 ? 3.6 : -3.6)
                addRunwayCharacter(digit, origin: origin, along: along, from: from, across: across, bounds: bounds)
            }
            // The aiming point, and on a long runway the touchdown zone.
            let aiming = length > 2_400 ? 400.0 : (length > 1_500 ? 300.0 : 250.0)
            for side in [-1.0, 1.0] { bar(origin, along, from: aiming, to: aiming + 45, across: side * (half * 0.3 + 4), width: 8) }
            if length > 1_800 {
                for (at, count) in [(150.0, 3), (300.0, 3), (600.0, 2), (750.0, 1), (900.0, 1)] where at < length / 2 - 60 {
                    for index in 0..<count {
                        for side in [-1.0, 1.0] {
                            bar(origin, along, from: at, to: at + 22.5, across: side * (half * 0.3 + 0.9 + 3.3 * Double(index)), width: 1.8)
                        }
                    }
                }
            }
            // The threshold's green lights across the end.
            for index in 0..<7 {
                let across = (Double(index) - 3) * half / 3.5
                addPool(at: Map3DBaseMap.Point(x: origin.x + along.x * 3 + along.z * across, z: origin.z + along.z * 3 - along.x * across),
                        colour: Airfield.green, radius: 5, strength: 0.9)
            }
        }
        addLights(along: line, every: 60, offsets: [-(half + 1.5), half + 1.5], colour: Airfield.white, radius: 7, strength: 0.95, bounds: bounds)
        addLights(along: line, every: 30, offsets: [0], colour: Airfield.white, radius: 3.5, strength: 0.8, bounds: bounds)
    }

    /// Each character's strokes on a grid 1 across (x, to the reader's
    /// right) and 1 up (y, away from the reader).
    static let runwayStrokes: [Character: [(Double, Double, Double, Double)]] = {
        // The seven segments: a top, b upper right, c lower right, d
        // bottom, e lower left, f upper left, g middle.
        let a = (0.0, 1.0, 1.0, 1.0), b = (1.0, 1.0, 1.0, 0.5), c = (1.0, 0.5, 1.0, 0.0), d = (0.0, 0.0, 1.0, 0.0)
        let e = (0.0, 0.5, 0.0, 0.0), f = (0.0, 1.0, 0.0, 0.5), g = (0.0, 0.5, 1.0, 0.5)
        return [
            "0": [a, b, c, d, e, f], "1": [(0.5, 1, 0.5, 0)], "2": [a, b, g, e, d], "3": [a, b, g, c, d], "4": [f, g, b, c],
            "5": [a, f, g, c, d], "6": [a, f, g, e, c, d], "7": [a, b, c], "8": [a, b, c, d, e, f, g], "9": [a, b, c, d, f, g],
            "L": [(0, 1, 0, 0), d], "R": [(0, 1, 0, 0), a, b, g, (0.3, 0.5, 1, 0)], "C": [a, f, e, d],
        ]
    }()

    /// One painted character 4.5 m wide and 9 m tall, its foot `from`
    /// metres along `along` from `origin`, its middle `across` metres to
    /// the left.
    mutating func addRunwayCharacter(_ character: Character, origin: Map3DBaseMap.Point, along: (x: Double, z: Double), from: Double,
                                     across: Double, bounds: Map3DBaseMap.Bounds) {
        guard let strokes = Self.runwayStrokes[character] else { return }
        var none = Set<Map3DScene.ChunkKey>()
        let wide = 4.5, tall = 9.0, stroke = 1.0
        // The reader's right is the way's right: (−z, x) in x east, z south.
        func point(_ x: Double, _ y: Double) -> Map3DBaseMap.Point {
            let right = (x - 0.5) * wide - across, up = from + y * tall
            return Map3DBaseMap.Point(x: origin.x + along.x * up - along.z * right, z: origin.z + along.z * up + along.x * right)
        }
        for (x0, y0, x1, y1) in strokes {
            addStrip([point(x0, y0), point(x1, y1)], bounds: bounds, width: Float(stroke), lift: Airfield.paintLift, color: Airfield.paint,
                     paint: nil, taking: &none)
        }
    }

    /// A jet bridge from the terminal at `from` to the aircraft's door at
    /// `to`: its tunnel on a pillar at each end.
    mutating func addJetBridge(from: Map3DBaseMap.Point, to: Map3DBaseMap.Point) {
        let a = Map3DPoint(Float(from.x), 0, Float(from.z)), b = Map3DPoint(Float(to.x), 0, Float(to.z))
        guard let along = (b - a).normalized else { return }
        let length = (b - a).length
        let ground = max(drawnGround(x: a.x, z: a.z), drawnGround(x: b.x, z: b.z)) + Airfield.apronLift
        let middle = Map3DPoint((a.x + b.x) / 2, ground, (a.z + b.z) / 2)
        let c = Map3DStudyColor.self
        mesh(at: middle) { mesh in
            mesh.addBox(base: middle + Map3DPoint(0, 3.6, 0), forward: along, length: length, width: 3, height: 2.7, top: c.roof, side: c.wall)
            mesh.addBox(base: middle + Map3DPoint(0, 4.3, 0), forward: along, length: length - 2, width: 3.1, height: 1.1, top: c.pane, side: c.pane)
            for end in [a + along * 2, b - along * 3.5] {
                mesh.addBox(base: Map3DPoint(end.x, ground, end.z), forward: along, length: 1.6, width: 1.6, height: 3.6, top: c.base, side: c.base)
            }
            mesh.addBox(base: Map3DPoint(b.x, ground + 3.4, b.z) - along * 2, forward: along, length: 4.4, width: 4.4, height: 3.2, top: c.roof,
                        side: c.wall)
        }
    }

    /// Decision 698's control tower `height` metres to its cab's floor, in
    /// the kits' space (+x its front, +y up, +z its right), by height.
    static func controlTower(height: Float) -> Map3DMesh {
        let height = (height / 5).rounded() * 5
        return towerMeshes.withLock { made in
            if let mesh = made[height] { return mesh }
            var study = Map3DStudyMesh()
            study.tower(0, 0, max(12, height - 8), false)
            let mesh = Map3DMesh(study: study)
            made[height] = mesh
            return mesh
        }
    }

    private static let towerMeshes = Map3DLocked<[Float: Map3DMesh]>([:])
}

/// A value behind a lock, for a cache several scene builds share.
final class Map3DLocked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

extension Map3DMesh {
    /// A study's solids (x forward, y left, z up) in the kits' space (+x
    /// the front, +y up, +z the right), each triangle flat.
    init(study: Map3DStudyMesh) {
        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(study.triangles.count * 3)
        for triangle in study.triangles {
            let corners = [triangle.a, triangle.b, triangle.c].map { Map3DPoint($0.x, $0.z, -$0.y) }
            guard let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { continue }
            for corner in corners {
                vertices.append(Map3DVertex(corner, normal: normal, color: triangle.paint.color, u: 0,
                                            layer: triangle.paint.glow ? Map3DVertex.glowing : Map3DVertex.plain))
            }
        }
        self.init(vertices: vertices, indices: (0..<UInt32(vertices.count)).map { $0 })
    }
}
