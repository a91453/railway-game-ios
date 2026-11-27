import GameCore

/// Decision 1020: the station landmarks (``Map3DStationLandmark``):
/// Hakata's, Kumamoto's and Duoliang's buildings, which the track runs
/// through rather than round. One rule for all of them (the owner,
/// 2026-11-27: 「車站的規則要統一」):
///
/// 1. It stands whether or not its line is bought, when nothing of its
///    near model is in the room the trains and the platforms' people
///    need (``stationRoom(_:within:)``): the room its model leaves for
///    the real platforms. When something is, it is not drawn, and
///    `Map3DStationLandmarksTests` turns red, rather than it going
///    quietly.
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
    /// What of a model may be in the room (square metres, its triangles'
    /// share there): a cut face's few centimetres where a wall meets the
    /// room's edge, no more.
    static let stationLeast: Float = 1

    /// Where a station landmark stands: its middle on its ground, its
    /// ground, how much of its near model is in the room (square metres)
    /// and the ground its far model covers.
    struct StationLandmarkPlace {
        let centre: Map3DPoint
        let ground: Float
        let intrusion: Float
        let plan: LandmarkPlan
        var stands: Bool { intrusion <= Map3DScene.Builder.stationLeast }
    }

    /// The room `snapshot`'s track (the player's, not in a tunnel) and the
    /// real lines' track drawn need within `box` on the ground: a car's
    /// width (``stationCarHalf``) up to ``Map3DTrainRoom/trackAbove`` over
    /// the rails; and over each platform beside its track, people's
    /// (``stationPlatformAbove``). Under the rails only their own 30 cm: a
    /// viaduct's deck may run through a station's floor under its
    /// platforms.
    func stationRoom(_ snapshot: RailwaySnapshot?, within box: (min: Map3DPoint, max: Map3DPoint)) -> Map3DTrainRoom {
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
                        room.add(line: run, half: Self.stationCarHalf, above: Map3DTrainRoom.trackAbove, ground: 0, below: 0.3)
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
                room.add(line: run, half: Self.stationCarHalf, above: Map3DTrainRoom.trackAbove, ground: 0, below: 0.3)
            }
        }
        return room
    }

    /// Where `landmark` (a station landmark) stands and whether it does:
    /// on the lowest ground under it, or (``Map3DStationLandmark/railHeight``)
    /// its rails on those of the track drawn nearest its middle.
    mutating func stationLandmarkPlace(_ landmark: Map3DLandmarkRegistration, snapshot: RailwaySnapshot?,
                                       frame: RealWorldFrame) -> StationLandmarkPlace {
        if let held = state.landmarks.stationPlaces[landmark.id] { return held }
        let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
        let centre = point(x: place.x, y: place.y, height: 0)
        let near = landmark.model(full: true), far = landmark.model(full: false)
        let half = Map3DHongKongLandmark.body(of: near)
        let body = LandmarkMesh.corners(half, origin: centre, rotation: 0)
        let box = (min: Map3DPoint(body.map(\.x).min()!, 0, body.map(\.z).min()!), max: Map3DPoint(body.map(\.x).max()!, 0, body.map(\.z).max()!))
        let room = stationRoom(snapshot, within: box)
        let found = landmark.sink > 0 ? drawnGround(x: centre.x, z: centre.z) : body.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0
        var ground = max(found, landmark.baseHeight) - landmark.sink
        if let rails = landmark.station?.railHeight, let height = room.railHeight(near: centre, within: max(half.x, half.y)) {
            ground = height - rails
        }
        let placed = near.placed(origin: centre, ground: ground, rotation: 0)
        let made = StationLandmarkPlace(centre: centre, ground: ground, intrusion: room.intrusion(of: placed),
                                        plan: LandmarkPlan(far.placed(origin: centre, ground: ground, rotation: 0)))
        state.landmarks.stationPlaces[landmark.id] = made
        return made
    }

    /// The stations of the game a standing station landmark stands for:
    /// those whose platforms' middle (of the longest, from the whole
    /// network) it stands over.
    mutating func stationsUnderLandmarks(_ snapshot: RailwaySnapshot, frame: RealWorldFrame?,
                                         anchors: [StationID: Map3DPoint]) -> Set<StationID> {
        guard let frame else { return [] }
        let stood = Map3DLandmarkRegistry.landmarks.filter { $0.station != nil }.map { stationLandmarkPlace($0, snapshot: snapshot, frame: frame) }
            .filter(\.stands)
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

    /// How much of `mesh` (square metres of its triangles) is in the room.
    func intrusion(of mesh: Map3DMesh) -> Float {
        func area(_ p: [Map3DVertex]) -> Float {
            guard p.count > 2 else { return 0 }
            return (1..<(p.count - 1)).reduce(0) { $0 + (p[$1].position - p[0].position).cross(p[$1 + 1].position - p[0].position).length / 2 }
        }
        var inside: Float = 0
        for at in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[at + $0])] }
            let whole = area(triangle)
            guard whole > 1e-6 else { continue }
            let kept = outside(triangle, marking: false).reduce(0) { $0 + area($1.polygon) }
            inside += max(0, whole - kept)
        }
        return inside
    }
}
