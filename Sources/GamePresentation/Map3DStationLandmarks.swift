import GameCore

/// Decision 1020: the station landmarks (``Map3DStationLandmark``):
/// Hakata's, Kumamoto's and Duoliang's buildings, which the track runs
/// through rather than round. One rule for all of them (the owner,
/// 2026-11-27: 「車站的規則要統一」):
///
/// 1. It stands whether or not its line is bought, its own rails
///    (``Map3DStationLandmark/railHeight``) on the drawn rails under it,
///    moved across the track a few metres at most where that keeps more
///    of it out of the room the trains and the platforms' people need
///    (``stationRoom(_:within:above:)``). What of it is still in that
///    room is cut away, when that is no more than ``stationCutShare`` of
///    it; when more is, it is not drawn, and `Map3DStationLandmarksTests`
///    turns red, rather than it going quietly.
/// 2. A station of the game whose platforms' middle it stands over draws
///    no building, entrances or canopies of its own; its platforms stay.
/// 3. With no line bought it is scenery, as any landmark.
///
/// Whether it stands and where is asked of the whole network, so every
/// block of chunks built apart (decision 358) agrees, as decision 625's
/// studies are.
extension Map3DScene.Builder {
    /// Either side of a track's middle: a car's half width (the Shinkansen's
    /// 3.38 m, the widest the game runs), and a little more. Narrower than
    /// ``Map3DTrainRoom/trackHalf``, which keeps an overhead line's mast
    /// clear too: a station's building stands clear of the cars; its
    /// platforms keep the masts.
    static let stationCarHalf: Float = 1.9
    /// Over a platform: people under the building's roof (the game's
    /// canopy is left out where a station landmark stands), from the
    /// rails' height.
    static let stationPlatformAbove: Float = 5
    /// How much of a model (its triangles' area) may be cut away where it
    /// is in the room: a column or a strip of wall where the game lays
    /// its platforms a few metres from the real ones (Hakata's 0.2 %,
    /// Kumamoto's 2 %); more is a model built round other track.
    static let stationCutShare: Float = 0.03
    /// How far either way across the track under it a model may be moved
    /// (metres, in steps of ``stationShiftStep``): the drawn line a few
    /// metres from the real one (Duoliang's 3.6 m).
    static let stationShift: Float = 6
    static let stationShiftStep: Float = 0.5

    /// Where a station landmark stands: its middle on its ground, its
    /// ground, its rails and the drawn ones over that, the room it is cut
    /// clear of, how much of its near model is cut away (square metres
    /// and its share) and the ground its far model covers.
    struct StationLandmarkPlace {
        let centre: Map3DPoint
        let ground: Float
        let rails: (model: Float, drawn: Float)?
        let room: Map3DTrainRoom
        let intrusion: Float
        let share: Float
        let plan: LandmarkPlan
        var stands: Bool { share <= Map3DScene.Builder.stationCutShare }

        /// `model` stood here: its rails on the drawn ones, what is in the
        /// room cut away.
        func mesh(_ model: LandmarkMesh) -> Map3DMesh {
            room.carved(stood(model))
        }

        /// `model` stood here, not cut.
        func stood(_ model: LandmarkMesh) -> Map3DMesh {
            let mesh = model.placed(origin: centre, ground: ground, rotation: 0)
            guard let rails, rails.drawn > rails.model else { return mesh }
            let ground = ground
            return Map3DMesh(vertices: mesh.vertices.map { vertex in
                var vertex = vertex
                let up = vertex.y - ground
                vertex.y = ground + (up < rails.model ? up * rails.drawn / rails.model : up + rails.drawn - rails.model)
                return vertex
            }, indices: mesh.indices)
        }
    }

    /// The room `snapshot`'s track (the player's, not in a tunnel) and the
    /// real lines' track drawn need within `box` on the ground: a car's
    /// width (``stationCarHalf``) up to ``Map3DTrainRoom/trackAbove`` over
    /// the rails; and over each platform beside its track, people's
    /// (``stationPlatformAbove``). Under the rails only their own 30 cm: a
    /// viaduct's deck may run through a station's floor under its
    /// platforms.
    func stationRoom(_ snapshot: RailwaySnapshot?, within box: (min: Map3DPoint, max: Map3DPoint),
                     above: Float = Map3DTrainRoom.trackAbove) -> Map3DTrainRoom {
        var room = Map3DTrainRoom()
        func reaches(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool {
            max(a.x, b.x) > box.min.x - 20 && min(a.x, b.x) < box.max.x + 20 && max(a.z, b.z) > box.min.z - 20 && min(a.z, b.z) < box.max.z + 20
        }
        func runs(_ line: [Map3DPoint]) -> [[Map3DPoint]] {
            var runs: [[Map3DPoint]] = [], run: [Map3DPoint] = []
            for (a, b) in zip(line, line.dropFirst()) {
                if reaches(a, b) {
                    if run.isEmpty { run.append(a) }
                    run.append(b)
                } else if !run.isEmpty {
                    runs.append(run); run = []
                }
            }
            if run.count > 1 { runs.append(run) }
            return runs
        }
        if let snapshot {
            let past = (Double(20) + 1) * Self.metre
            let near = WorldRegion(minX: originX + Double(box.min.x) * Self.metre, minY: originY + Double(box.min.z) * Self.metre,
                                   maxX: originX + Double(box.max.x) * Self.metre, maxY: originY + Double(box.max.z) * Self.metre)
            for spans in shared.samples(of: snapshot).edges {
                for span in spans where span.end > span.start && span.kind != .tunnel && span.reaches(near, by: past) {
                    for run in runs(span.line.map { point($0) + Self.lifted }) {
                        room.add(line: run, half: Self.stationCarHalf, above: above, ground: 0, below: 0.3)
                    }
                }
            }
            let island = Float(PlatformTrackLayout.island.spacing) / Float(WorldCoordinate.unitsPerMetre) / 2
            let platformHalf = max(Self.highSpeedPlatformEdge + Self.platformWidth, island)
            for platform in snapshot.platforms where platform.structure != .tunnel && platform.points.count > 1 {
                for run in runs(platform.points.map { point($0) + Self.lifted }) {
                    room.add(line: run, half: platformHalf, above: Self.stationPlatformAbove, ground: 0, below: 0.3)
                }
            }
        }
        for line in state.realTrains.realTrackLines {
            for run in runs(line) {
                room.add(line: run, half: Self.stationCarHalf, above: above, ground: 0, below: 0.3)
            }
        }
        return room
    }

    /// Where `landmark` (a station landmark) stands and whether it does:
    /// on the lowest ground under it, its rails
    /// (``Map3DStationLandmark/railHeight``) on those of the track drawn
    /// nearest its middle, moved across that track as far as
    /// ``stationShift`` where that leaves less of it in the room.
    mutating func stationLandmarkPlace(_ landmark: Map3DLandmarkRegistration, snapshot: RailwaySnapshot?,
                                       frame: RealWorldFrame) -> StationLandmarkPlace {
        if let held = state.landmarks.stationPlaces[landmark.id] { return held }
        let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
        let real = point(x: place.x, y: place.y, height: 0)
        let near = landmark.model(full: true), far = landmark.model(full: false)
        let half = Map3DHongKongLandmark.body(of: near)
        let body = LandmarkMesh.corners(half, origin: real, rotation: 0)
        let reach = Self.stationShift
        let box = (min: Map3DPoint(body.map(\.x).min()! - reach, 0, body.map(\.z).min()! - reach),
                   max: Map3DPoint(body.map(\.x).max()! + reach, 0, body.map(\.z).max()! + reach))
        let room = stationRoom(snapshot, within: box)
        func placed(at centre: Map3DPoint) -> StationLandmarkPlace {
            let corners = LandmarkMesh.corners(half, origin: centre, rotation: 0)
            let found = landmark.sink > 0 ? drawnGround(x: centre.x, z: centre.z) : corners.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
            var ground = max(found, landmark.baseHeight) - landmark.sink
            var rails: (model: Float, drawn: Float)?
            if let model = landmark.station?.railHeight, let height = room.railHeight(near: centre, within: max(half.x, half.y)) {
                if height - ground > model {
                    rails = (model, height - ground)
                } else {
                    ground = height - model
                }
            }
            let stood = StationLandmarkPlace(centre: centre, ground: ground, rails: rails, room: room, intrusion: 0, share: 0,
                                             plan: LandmarkPlan(far.placed(origin: centre, ground: ground, rotation: 0)))
            let mesh = stood.stood(near)
            let intrusion = room.intrusion(of: mesh)
            return StationLandmarkPlace(centre: centre, ground: ground, rails: rails, room: room, intrusion: intrusion,
                                        share: intrusion / max(Map3DTrainRoom.area(of: mesh), 1), plan: stood.plan)
        }
        var made = placed(at: real)
        if made.intrusion > 0, let across = room.across(near: real, within: max(half.x, half.y)) {
            let steps = Int((Self.stationShift / Self.stationShiftStep).rounded())
            for step in 1...steps {
                for sign: Float in [1, -1] {
                    let moved = placed(at: real + across * (sign * Float(step) * Self.stationShiftStep))
                    if moved.intrusion < made.intrusion { made = moved }
                }
                if made.intrusion == 0 { break }
            }
        }
        state.landmarks.stationPlaces[landmark.id] = made
        return made
    }

    /// The stations of the game a standing station landmark stands for:
    /// those whose platforms' middle (of the longest, from the whole
    /// network) it stands over.
    mutating func stationsUnderLandmarks(_ snapshot: RailwaySnapshot, frame: RealWorldFrame?,
                                         anchors: [StationID: Map3DPoint]) -> Set<StationID> {
        guard let frame else { return [] }
        // Only those whose ground may reach into the scene.
        let margin = 400 * Self.metre
        let stood = Map3DLandmarkRegistry.landmarks.filter { landmark in
            guard landmark.station != nil else { return false }
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            return place.x > region.minX - margin && place.x < region.maxX + margin && place.y > region.minY - margin && place.y < region.maxY + margin
        }.map { stationLandmarkPlace($0, snapshot: snapshot, frame: frame) }.filter(\.stands)
        guard !stood.isEmpty else { return [] }
        return Set(anchors.filter { _, anchor in stood.contains { $0.plan.covers(anchor) } }.keys)
    }
}

extension Map3DTrainRoom {
    /// The rails' height of the track stretch (``Map3DScene/Builder/stationCarHalf``
    /// wide) whose middle line comes nearest `point` on the ground, within
    /// `reach` metres.
    func railHeight(near point: Map3DPoint, within reach: Float) -> Float? {
        var best: (distance: Float, height: Float)?
        for s in stretches where s.half == Map3DScene.Builder.stationCarHalf {
            let ab = Map3DPoint(s.b.x - s.a.x, 0, s.b.z - s.a.z), ap = Map3DPoint(point.x - s.a.x, 0, point.z - s.a.z)
            let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
            let distance = (ap - ab * share).length
            guard distance <= reach, distance < best?.distance ?? .greatestFiniteMagnitude else { continue }
            best = (distance, s.a.y + (s.b.y - s.a.y) * share)
        }
        return best?.height
    }

    /// Across (on the ground, a unit length) the track stretch whose
    /// middle line comes nearest `point`, within `reach` metres.
    func across(near point: Map3DPoint, within reach: Float) -> Map3DPoint? {
        var best: (distance: Float, across: Map3DPoint)?
        for s in stretches where s.half == Map3DScene.Builder.stationCarHalf {
            let ab = Map3DPoint(s.b.x - s.a.x, 0, s.b.z - s.a.z), ap = Map3DPoint(point.x - s.a.x, 0, point.z - s.a.z)
            guard let along = ab.normalized else { continue }
            let share = min(max(ab.dot(ap) / max(ab.dot(ab), 1e-6), 0), 1)
            let distance = (ap - ab * share).length
            guard distance <= reach, distance < best?.distance ?? .greatestFiniteMagnitude else { continue }
            best = (distance, Map3DPoint(-along.z, 0, along.x))
        }
        return best?.across
    }

    /// The area of `polygon` (square metres).
    static func area(_ polygon: [Map3DVertex]) -> Float {
        guard polygon.count > 2 else { return 0 }
        return (1..<(polygon.count - 1)).reduce(0) { $0 + (polygon[$1].position - polygon[0].position).cross(polygon[$1 + 1].position - polygon[0].position).length / 2 }
    }

    /// The area of `mesh`'s triangles (square metres).
    static func area(of mesh: Map3DMesh) -> Float {
        stride(from: 0, to: mesh.indices.count - 2, by: 3).reduce(0) { sum, at in
            sum + area((0..<3).map { mesh.vertices[Int(mesh.indices[at + $0])] })
        }
    }

    /// `mesh` with what of it is in the room cut away: a triangle the room
    /// does not reach as it is, one it does in the pieces left out of it.
    func carved(_ mesh: Map3DMesh) -> Map3DMesh {
        var vertices: [Map3DVertex] = [], indices: [UInt32] = []
        var kept: [UInt32: UInt32] = [:]
        for at in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let corners = (0..<3).map { mesh.indices[at + $0] }
            let triangle = corners.map { mesh.vertices[Int($0)] }
            let pieces = outside(triangle, marking: false)
            if pieces.count == 1, pieces[0].polygon.count == 3, zip(pieces[0].polygon, triangle).allSatisfy({ $0.position == $1.position }) {
                for corner in corners {
                    if let index = kept[corner] {
                        indices.append(index)
                    } else {
                        kept[corner] = UInt32(vertices.count)
                        indices.append(UInt32(vertices.count))
                        vertices.append(mesh.vertices[Int(corner)])
                    }
                }
                continue
            }
            for piece in pieces where piece.polygon.count > 2 && Self.area(piece.polygon) > 1e-6 {
                let first = UInt32(vertices.count)
                vertices.append(contentsOf: piece.polygon)
                for i in 1..<(piece.polygon.count - 1) {
                    indices.append(contentsOf: [first, first + UInt32(i), first + UInt32(i + 1)])
                }
            }
        }
        return Map3DMesh(vertices: vertices, indices: indices)
    }

    /// How much of `mesh` (square metres of its triangles) is in the room.
    func intrusion(of mesh: Map3DMesh) -> Float {
        var inside: Float = 0
        for at in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[at + $0])] }
            let whole = Self.area(triangle)
            guard whole > 1e-6 else { continue }
            let kept = outside(triangle, marking: false).reduce(0) { $0 + Self.area($1.polygon) }
            inside += max(0, whole - kept)
        }
        return inside
    }
}
