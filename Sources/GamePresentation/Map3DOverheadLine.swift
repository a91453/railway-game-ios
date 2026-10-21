import GameCore

// ARCHITECTURE decision 326: the overhead line over the track in the open,
// close up only. A steel mast beside the track every 40 m or less (the
// Web city view's `rails.js` `MAST_SPACING`), closer on a curve so the
// wire stays over the track, on the side away from other track and clear
// of a platform where it can; a cantilever arm across to the wire; the
// contact wire, zigzagging a little either side of the middle, and the
// messenger wire sagging above it. None in a tunnel; a track with other
// track either side hangs its wires from its neighbours' masts. On a
// real-world map, none on track laid along a real line run without one:
// the four diesel branch lines (`main-reference.js` `DIESEL_BRANCH_IDS`),
// the forest railway, and the metros, on a third rail or none. None
// either where the ground is drawn over the track.

extension Map3DPalette {
    /// Decision 326: the masts' steel and the wires (the rail-3d viaduct
    /// scene's `mastSteel` #b9bcb6 and `wire` #4c4a46).
    static let mastSteel = Map3DColor.rgb(0xB9BCB6)
    static let overheadWire = Map3DColor.rgb(0x4C4A46)
}

extension Map3DScene {
    /// Decision 326: the systems whose lines run under an overhead line
    /// (``RealRailways/System/id``): TRA's, the high-speed line's and the
    /// two light rails' in New Taipei.
    static let wiredSystems: Set<String> = ["tra_sched", "thsr_sched", "ntdlrt", "ntalrt"]
    /// TRA's lines run by diesel railcars (`DIESEL_BRANCH_IDS`: pingxi,
    /// shenao, jiji, neiwan), by the start of their names; the Neiwan Line
    /// only past Zhuzhong, where the Liujia Line's wires end.
    static let dieselBranches = ["平溪線", "深澳線", "集集線", "內灣線"]
    static let neiwanWiresEnd = "竹中"
}

extension Map3DScene.Builder {
    /// Decision 326: `railways`' lines round the scene, in scene metres,
    /// each piece with whether it runs under an overhead line.
    mutating func addRealLines(_ railways: RealRailways, frame: RealWorldFrame) {
        let reach = 1_000 * Self.metre
        func scene(_ c: RealRailways.Coordinate) -> Map3DPoint {
            let at = frame.worldPosition(latitude: c.latitude, longitude: c.longitude)
            return point(x: at.x, y: at.y, height: 0)
        }
        func station(_ name: String) -> Map3DPoint? {
            railways.stations(named: name, near: nil).first { $0.system.id == "tra_sched" }.map { scene($0.coordinate) }
        }
        let zhuzhong = station(Map3DScene.neiwanWiresEnd), hsinchu = station("新竹")
        for line in railways.lines {
            let worlds = line.points.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
            guard worlds.contains(where: { $0.x >= region.minX - reach && $0.x <= region.maxX + reach && $0.y >= region.minY - reach && $0.y <= region.maxY + reach })
            else { continue }
            let points = line.points.map(scene)
            let wired = Map3DScene.wiredSystems.contains(line.system.id)
            guard wired, let branch = Map3DScene.dieselBranches.first(where: { line.name.hasPrefix($0) }) else {
                realLines.append((points, wired))
                continue
            }
            // The Neiwan Line is wired from Hsinchu as far as Zhuzhong.
            if branch == "內灣線", let zhuzhong, let hsinchu, let first = points.first, let last = points.last {
                let cut = points.indices.min { (points[$0] - zhuzhong).length < (points[$1] - zhuzhong).length } ?? 0
                let fromHsinchu = (first - hsinchu).length < (last - hsinchu).length
                realLines.append((Array(points[...cut]), fromHsinchu))
                realLines.append((Array(points[cut...]), !fromHsinchu))
            } else {
                realLines.append((points, false))
            }
        }
    }

    /// Decision 326 (`rails.js`, metres): masts at most this far apart,
    /// this far to the side of the track's middle and this tall above the
    /// rails; the arm, the contact wire and the messenger wire this high
    /// above the rails.
    static let mastSpacing: Float = 40
    static let mastOffset: Float = 2.45
    static let mastTop: Float = 6.4
    static let armHeight: Float = 5.95
    static let contactHeight: Float = 5.2
    static let messengerHeight: Float = 5.9
    /// How far the contact wire swings either side of the track's middle
    /// from one mast to the next, so it wears the pantograph evenly, and
    /// the most the track may stray from the straight wire between two
    /// masts.
    static let wireStagger: Float = 0.2
    static let wireStray: Float = 0.3
    /// How thick a wire is drawn: more than a real one, so it shows.
    static let wireThickness: Float = 0.07

    /// The supports of `path`'s wire, as distances along it: its start,
    /// then each as far on as ``mastSpacing`` allows with the track no
    /// more than ``wireStray`` from the straight line to it, and its end.
    static func wireSupports(_ path: Map3DStreetLife.Path) -> [Float] {
        var supports: [Float] = [0]
        while let last = supports.last, path.length - last > 0.5 {
            let from = path.at(last).point
            var candidate = min(last + mastSpacing, path.length)
            while candidate - last > 4 {
                let to = path.at(candidate).point
                guard let along = Map3DPoint(to.x - from.x, 0, to.z - from.z).normalized else { break }
                let across = Map3DPoint(-along.z, 0, along.x)
                let stray = stride(from: last + 2, to: candidate, by: Float(2)).map { (distance: Float) -> Float in
                    let p = path.at(distance).point
                    return abs(Map3DPoint(p.x - from.x, 0, p.z - from.z).dot(across))
                }.max() ?? 0
                if stray <= wireStray { break }
                candidate -= 2
            }
            supports.append(candidate)
        }
        return supports
    }

    /// Decision 326: the overhead line over every track laid in the open
    /// (``trackLines``), its masts beside the platforms laid
    /// (``laidPlatforms``); in the closest detail only (decision 267's
    /// ``Map3DScene/Chunk/close``): farther off a mast is under a pixel
    /// wide and a wire less.
    mutating func addOverheadLine() {
        let lines = trackLines.enumerated().filter { $0.element.kind != .tunnel }.compactMap { item in
            Map3DStreetLife.Path(item.element.points).map { (index: item.offset, path: $0, kind: item.element.kind) }
        }
        // Every piece of track in the open by 32 m cell, to find a track's
        // neighbours; and where each line ends.
        struct Cell: Hashable { let x: Int, z: Int }
        func cell(_ p: Map3DPoint) -> Cell { Cell(x: Int((p.x / 32).rounded(.down)), z: Int((p.z / 32).rounded(.down))) }
        var pieces: [Cell: [(line: Int, a: Map3DPoint, b: Map3DPoint)]] = [:]
        var ends: [Cell: [(line: Int, point: Map3DPoint)]] = [:]
        for line in lines {
            for (a, b) in zip(line.path.points, line.path.points.dropFirst()) {
                let low = cell(Map3DPoint(min(a.x, b.x), 0, min(a.z, b.z))), high = cell(Map3DPoint(max(a.x, b.x), 0, max(a.z, b.z)))
                for x in low.x...high.x {
                    for z in low.z...high.z { pieces[Cell(x: x, z: z), default: []].append((line.index, a, b)) }
                }
            }
            if let last = line.path.points.last { ends[cell(last), default: []].append((line.index, last)) }
        }
        func around(_ p: Map3DPoint) -> [Cell] {
            let c = cell(p)
            return (-1...1).flatMap { dx in (-1...1).map { dz in Cell(x: c.x + dx, z: c.z + dz) } }
        }
        func level(_ v: Map3DPoint) -> Map3DPoint { Map3DPoint(v.x, 0, v.z) }
        /// Whether other track runs beside `p` on its right (`side` 1) or
        /// left (-1), its middle 1.8 to 7.5 m away.
        func neighbour(of line: Int, at p: Map3DPoint, along: Map3DPoint, right: Map3DPoint, side: Float) -> Bool {
            around(p).contains { key in
                (pieces[key] ?? []).contains { piece in
                    guard piece.line != line else { return false }
                    let ab = level(piece.b - piece.a), length = ab.dot(ab)
                    let share = length > 0 ? min(max(level(p - piece.a).dot(ab) / length, 0), 1) : 0
                    let v = level(piece.a + (piece.b - piece.a) * share - p)
                    let across = v.dot(right) * side
                    return abs(v.dot(along)) < 4 && across > 1.8 && across < 7.5
                }
            }
        }
        let platforms = laidPlatforms.compactMap { platform in Map3DStreetLife.Path(platform.line).map { (path: $0, platform: platform) } }
        /// The platform beside the track at `p` on `side`, if one is.
        func platform(at p: Map3DPoint, side: Float) -> LaidPlatform? {
            platforms.first { item in
                guard item.platform.offset * side > 0,
                      p.x >= item.path.minimum.x - 1, p.x <= item.path.maximum.x + 1,
                      p.z >= item.path.minimum.z - 1, p.z <= item.path.maximum.z + 1 else { return false }
                return zip(item.path.points, item.path.points.dropFirst()).contains { a, b in
                    let ab = level(b - a), length = ab.dot(ab)
                    guard length > 0 else { return false }
                    let share = level(p - a).dot(ab) / length
                    return share >= 0 && share <= 1 && level(a + (b - a) * share - p).length < 0.5
                }
            }?.platform
        }
        // The real lines' pieces by cell, to tell whether the track at a
        // point is laid along one run without an overhead line: the
        // nearest within 30 m.
        var real: [Cell: [(a: Map3DPoint, b: Map3DPoint, wired: Bool)]] = [:]
        for line in realLines {
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let low = cell(Map3DPoint(min(a.x, b.x), 0, min(a.z, b.z))), high = cell(Map3DPoint(max(a.x, b.x), 0, max(a.z, b.z)))
                guard high.x - low.x < 64, high.z - low.z < 64 else { continue }
                for x in low.x...high.x {
                    for z in low.z...high.z { real[Cell(x: x, z: z), default: []].append((a, b, line.wired)) }
                }
            }
        }
        func isWired(_ p: Map3DPoint) -> Bool {
            var nearest: (distance: Float, wired: Bool) = (30, true)
            for key in around(p) {
                for piece in real[key] ?? [] {
                    let ab = level(piece.b - piece.a), length = ab.dot(ab)
                    let share = length > 0 ? min(max(level(p - piece.a).dot(ab) / length, 0), 1) : 0
                    let distance = level(piece.a + (piece.b - piece.a) * share - p).length
                    if distance < nearest.distance { nearest = (distance, piece.wired) }
                }
            }
            return nearest.wired
        }
        /// Whether `p` lies on a street at one of its level crossings.
        func inStreet(_ p: Map3DPoint) -> Bool {
            crossings.contains { crossing in
                let d = level(p - crossing.point)
                return abs(d.dot(crossing.along)) < Self.mastSpacing
                    && abs(d.x * crossing.along.z - d.z * crossing.along.x) <= crossing.halfWidth + 0.5
            }
        }
        var masts: [Cell: [Map3DPoint]] = [:]
        target = .close
        for line in lines {
            let supports = Self.wireSupports(line.path)
            var wires: [(contact: Map3DPoint, messenger: Map3DPoint)?] = []
            for (order, distance) in supports.enumerated() {
                let (p, along, right) = line.path.at(distance)
                // None where the ground is drawn over the track (the
                // heights file's ground above a track the world laid lower).
                guard realLines.isEmpty || isWired(p), drawnGround(x: p.x, z: p.z) < p.y + 1 else {
                    wires.append(nil)
                    continue
                }
                let stagger: Float = order.isMultiple(of: 2) ? Self.wireStagger : -Self.wireStagger
                let contact = p + right * stagger + Map3DPoint(0, Self.contactHeight, 0)
                wires.append((contact, p + Map3DPoint(0, Self.messengerHeight, 0)))
                // Where another line ends, its mast holds this one's wire.
                if order == 0, around(p).contains(where: { (ends[$0] ?? []).contains { $0.line != line.index && level($0.point - p).length < 1.5 } }) {
                    continue
                }
                if around(p).contains(where: { (masts[$0] ?? []).contains { level($0 - p).length < 2 } }) { continue }
                let open = [Float(1), -1].filter { !neighbour(of: line.index, at: p, along: along, right: right, side: $0) }
                guard let side = open.first(where: { platform(at: p, side: $0) == nil }) ?? open.first else { continue }
                // None in a street crossing the track: the wire spans over
                // it to the masts either side.
                if inStreet(p + right * (side * Self.mastOffset)) { continue }
                masts[cell(p), default: []].append(p)
                var offset = Self.mastOffset, foot: Float
                if let standing = platform(at: p, side: side) {
                    offset = abs(standing.offset)
                    foot = p.y + Self.platformHeight
                } else if line.kind == .viaduct || line.kind == .bridge {
                    foot = p.y - Self.bedDrop
                } else {
                    let at = p + right * (side * offset)
                    foot = min(drawnGround(x: at.x, z: at.z), p.y - Self.bedDrop)
                }
                addMast(at: p, along: along, right: right * side, offset: offset, foot: foot, contact: contact)
            }
            // Each span in the chunk at its middle: a chunk's box holding a
            // whole line's wires would be seen, and drawn close up, from
            // all along it.
            for case let (a?, b?) in zip(wires, wires.dropFirst()) {
                let middle = (a.messenger + b.messenger) * 0.5 - Map3DPoint(0, 0.35, 0)
                mesh(at: middle) { mesh in
                    mesh.addWire(from: a.contact, to: b.contact, thickness: Self.wireThickness, color: Map3DPalette.overheadWire)
                    mesh.addWire(from: a.messenger, to: middle, thickness: Self.wireThickness, color: Map3DPalette.overheadWire)
                    mesh.addWire(from: middle, to: b.messenger, thickness: Self.wireThickness, color: Map3DPalette.overheadWire)
                }
            }
        }
        target = .base
    }

    /// One mast `offset` to `out` of the track's middle `p`, standing at
    /// height `foot` on a concrete footing, its arm reaching back over the
    /// track to the wire's `contact` point.
    mutating func addMast(at p: Map3DPoint, along: Map3DPoint, right out: Map3DPoint, offset: Float, foot: Float, contact: Map3DPoint) {
        let base = Map3DPoint(p.x, foot, p.z) + out * offset
        let top = p.y + Self.mastTop
        mesh(at: base) { mesh in
            // On the ground, not into it: a chunk reaching below its ground
            // would be drawn from farther off.
            mesh.addBox(base: base, forward: along, length: 0.6, width: 0.6, height: 0.25,
                        top: Map3DPalette.concrete, side: Map3DPalette.concrete)
            mesh.addBox(base: base, forward: along, length: 0.22, width: 0.22, height: top - foot, top: Map3DPalette.mastSteel, side: Map3DPalette.mastSteel)
            // The arm, from the mast to a little past the wire.
            let armFrom = Map3DPoint(base.x, p.y + Self.armHeight, base.z), armTo = Map3DPoint(contact.x, p.y + Self.armHeight, contact.z) - out * 0.3
            mesh.addWire(from: armFrom, to: armTo, thickness: 0.11, color: Map3DPalette.mastSteel)
            // Its brace from lower on the mast, and its white insulator by
            // the mast.
            mesh.addWire(from: Map3DPoint(base.x, p.y + Self.contactHeight - 0.4, base.z), to: armFrom + (armTo - armFrom) * 0.45,
                         thickness: 0.07, color: Map3DPalette.mastSteel)
            mesh.addWire(from: armFrom + (armTo - armFrom) * 0.08, to: armFrom + (armTo - armFrom) * 0.2, thickness: 0.16, color: Map3DPalette.tileWhite)
            // The drop arm holding the contact wire.
            mesh.addWire(from: Map3DPoint(contact.x, p.y + Self.armHeight, contact.z), to: contact, thickness: 0.06, color: Map3DPalette.mastSteel)
        }
    }
}

extension Map3DMesh {
    /// Decision 326: a square bar `thickness` thick from `a` to `b`, its
    /// four long sides and no ends: a wire, an arm, a brace.
    mutating func addWire(from a: Map3DPoint, to b: Map3DPoint, thickness: Float, color: UInt32) {
        guard let direction = (b - a).normalized else { return }
        let side = direction.cross(.up).normalized ?? Map3DPoint(1, 0, 0)
        let up = side.cross(direction)
        let h = thickness / 2
        let rim = [side + up, up - side, (side + up) * -1, side - up].map { $0 * h }
        for index in 0..<4 {
            let p = rim[index], q = rim[(index + 1) % 4]
            var corners = [a + p, b + p, b + q, a + q]
            if let normal = Self.normal(of: corners), normal.dot(p + q) < 0 { corners.reverse() }
            addQuad(corners[0], corners[1], corners[2], corners[3], color: color)
        }
    }
}
