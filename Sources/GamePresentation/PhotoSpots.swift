import Foundation
import GameCore

/// Decision 981 (PHOTO-MODE): the 3D map's photo mode. Its controls are
/// put away, three buttons take the camera to a place worth a picture
/// (one of the player's trains, one of their stations, the skyline), and
/// the shutter saves the frame to the Photos app. View state only: it
/// reads the world and never changes it.
///
/// The idea is the photo modes of the references (`commuter_journey`'s
/// `PhotoJournal`, which decision 403 took the capture from; the camera of
/// decision 414's idle mode); the fixed spots are the project's own: the
/// references let the player walk, this camera flies.
public enum PhotoSpot: String, CaseIterable, Hashable, Sendable {
    /// One of the player's trains on the track, followed.
    case train
    /// One of the player's stations, from beyond the end of a platform.
    case station
    /// Low over the ground, looking far, the horizon in the picture.
    case skyline

    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .train: language.text("Train", "列車")
        case .station: language.text("Station", "車站")
        case .skyline: language.text("Skyline", "天際線")
        }
    }

    /// What the button does, for VoiceOver.
    public func hint(in language: DisplayLanguage) -> String {
        switch self {
        case .train: language.text("Follows one of your trains. Tap again for the next one.", "跟著你的一列車。再點一次換下一列。")
        case .station: language.text("Goes to one of your stations. Tap again for the next one.", "到你的一座車站。再點一次換下一座。")
        case .skyline: language.text("Looks far over the town from low down. Tap again to turn a quarter turn.", "從低處往遠方看。再點一次轉四分之一圈。")
        }
    }

    /// What the button says when there is nothing to go to.
    public func none(in language: DisplayLanguage) -> String? {
        switch self {
        case .train: language.text("No train is running yet.", "還沒有列車在路上。")
        case .station: language.text("No station here yet.", "這裡還沒有車站。")
        case .skyline: nil
        }
    }
}

/// Decision 981: which train and which station the photo mode shows next,
/// kept while the mode is open. Each tap of a spot's button goes to the
/// nearest one not shown yet, so tapping walks along the network from
/// where the camera is, and starts over once every one has been shown.
public struct PhotoTour: Equatable, Sendable {
    /// A thing to go to and where it is, seen from above, in world units.
    public struct Place<ID: Hashable & Comparable & Sendable>: Equatable, Sendable {
        public let id: ID
        public let x: Double
        public let y: Double

        public init(id: ID, x: Double, y: Double) {
            self.id = id
            self.x = x
            self.y = y
        }
    }

    /// The trains and stations shown since the mode opened (or since the
    /// round started over), the last one last.
    public private(set) var trains: [TrainID] = []
    public private(set) var stations: [StationID] = []
    /// How many trains have been shown in all, for the view each is
    /// followed from (``trainViews``).
    public private(set) var trainCount = 0
    /// Whether the camera is at the skyline spot, so the next tap turns it.
    public private(set) var atSkyline = false

    public init() {}

    /// From where the trains are followed, one after another: beside it
    /// with the whole train in the picture, above and behind, low behind.
    /// Not the cab, the window (no train in the picture) or the platform
    /// ahead (minutes may pass before the train comes).
    public static let trainViews: [Map3DFollow.View] = [.side, .aboveBack, .back]

    /// The nearest of `places` to (`x`, `y`) not in `shown`, added to it;
    /// with every one shown, the round starts over, never with the one
    /// shown last when there is another. `nil` for no places. Ties go to
    /// the smaller ID, so the order never depends on the array's.
    static func next<ID: Hashable & Comparable & Sendable>(among places: [Place<ID>], nearX x: Double, y: Double, shown: inout [ID]) -> ID? {
        guard !places.isEmpty else { return nil }
        let known = Set(places.map(\.id))
        shown.removeAll { !known.contains($0) }
        var left = places.filter { !shown.contains($0.id) }
        if left.isEmpty {
            let last = shown.last
            shown = places.count > 1 ? last.map { [$0] } ?? [] : []
            left = places.filter { !shown.contains($0.id) }
        }
        func distance(_ place: Place<ID>) -> Double {
            let dx = place.x - x, dy = place.y - y
            return dx * dx + dy * dy
        }
        guard let nearest = left.min(by: { a, b in
            let da = distance(a), db = distance(b)
            return da != db ? da < db : a.id < b.id
        }) else { return nil }
        shown.append(nearest.id)
        return nearest.id
    }

    /// The train to follow next and from where; `nil` with none running.
    public mutating func nextTrain(among places: [Place<TrainID>], nearX x: Double, y: Double) -> (train: TrainID, view: Map3DFollow.View)? {
        guard let train = Self.next(among: places, nearX: x, y: y, shown: &trains) else { return nil }
        let view = Self.trainViews[trainCount % Self.trainViews.count]
        trainCount += 1
        atSkyline = false
        return (train, view)
    }

    /// The station to go to next; `nil` with none.
    public mutating func nextStation(among places: [Place<StationID>], nearX x: Double, y: Double) -> StationID? {
        guard let station = Self.next(among: places, nearX: x, y: y, shown: &stations) else { return nil }
        atSkyline = false
        return station
    }

    /// How far the skyline spot turns from where the camera faces: not at
    /// all the first time, a quarter turn each tap after it.
    public mutating func nextSkylineTurn() -> Float {
        defer { atSkyline = true }
        return atSkyline ? .pi / 2 : 0
    }
}

/// Decision 981: where the photo mode's camera stands at a spot, and what
/// there is to go to.
public enum PhotoSpots {
    // MARK: - What there is

    /// The player's trains on the track (the ones a follow can hold,
    /// ``GameSession/followTrain(_:)``) and where each is.
    public static func trains(in world: GameWorld) -> [PhotoTour.Place<TrainID>] {
        world.trains.compactMap { train in
            guard case .onEdge(let traversal, let offset)? = train.position, let geometry = world.trackGeometry(of: traversal.edge),
                  offset >= 0, offset <= geometry.length else { return nil }
            let position = geometry.location(at: offset, going: traversal.direction).position
            return PhotoTour.Place(id: train.id, x: Double(position.x), y: Double(position.y))
        }
    }

    /// The player's stations, apart from depots, within `region` (the part
    /// of the map the 3D scene can show; `nil` for the whole map).
    public static func stations(in world: GameWorld, within region: WorldRegion? = nil) -> [PhotoTour.Place<StationID>] {
        world.stations.compactMap { station in
            guard !station.isDepot else { return nil }
            let x = Double(station.point.x), y = Double(station.point.y)
            if let region, !(region.minX...region.maxX).contains(x) || !(region.minY...region.maxY).contains(y) { return nil }
            return PhotoTour.Place(id: station.id, x: x, y: y)
        }
    }

    // MARK: - The station

    /// The tilt the station spot looks from, in radians from straight
    /// down: 66°, lower than the map leans by itself (42°) or two fingers
    /// lean it (60°), so the platform's roof, the train's side and the
    /// town behind are all in the picture, the horizon just out of it.
    public static let stationTilt: Float = 66 * .pi / 180
    /// How far the camera stands off the way the platform runs: a
    /// railway photographer's three-quarter view.
    public static let stationAngle: Float = 35 * .pi / 180
    /// The nearest and farthest the camera looks at a platform from.
    public static let stationDistances: ClosedRange<Float> = 120...320
    /// The length taken for a station with no platform on the track.
    public static let plainStationLength: Float = 120

    /// The camera at a station whose platform's middle is at `point`,
    /// running `along`, `length` metres long, from `camera`: tilted
    /// ``stationTilt``, as far as shows the platform end to end, standing
    /// ``stationAngle`` off the way it runs, on whichever of the four such
    /// sides turns the view the least.
    public static func camera(stationAt point: Map3DPoint, along: Map3DPoint, length: Float, from camera: Map3DCamera) -> Map3DCamera {
        var goal = camera
        goal.target = point
        goal.pitch = stationTilt
        goal.lens = nil
        goal.lean = 0
        goal.distance = min(max(length * 1.1, stationDistances.lowerBound), stationDistances.upperBound)
        let runs = Map3DFollow.heading(of: Map3DPoint(along.x, 0, along.z).normalized ?? Map3DPoint(0, 0, -1))
        let options = [runs + stationAngle, runs - stationAngle, runs + .pi + stationAngle, runs + .pi - stationAngle]
        func turn(_ heading: Float) -> Float { abs(Map3DCamera.turnFromNorth(heading - camera.heading)) }
        goal.heading = Map3DCamera.turnFromNorth(options.min { turn($0) < turn($1) } ?? camera.heading)
        return goal
    }

    /// The camera at station `station` of `world` in `scene`, from
    /// `camera`: over its first platform on the track (or where the
    /// station stands, with none), never looking at a point under the
    /// ground (a station in a tunnel is looked at from the street). `nil`
    /// for an unknown station.
    public static func camera(station: StationID, in world: GameWorld, scene: Map3DScene, from camera: Map3DCamera) -> Map3DCamera? {
        guard let place = world.station(id: station) else { return nil }
        var point = scene.point(worldX: Double(place.point.x), worldY: Double(place.point.y), height: 0)
        var along = Map3DPoint(0, 0, -1), length = plainStationLength
        if let platform = world.trackPlatforms(of: station).first, let middle = Map3DNextDeparture.middle(of: platform, in: world, scene: scene) {
            (point, along, length) = (middle.point, middle.along, middle.length)
        }
        point.y = max(point.y, scene.drawnGround.height(x: point.x, z: point.z, world: world))
        return Self.camera(stationAt: point, along: along, length: length, from: camera)
    }

    // MARK: - The skyline

    /// How far the skyline spot stands from what it looks at, metres.
    public static let skylineDistance: Float = 800
    /// The tilts the skyline spot tries, in radians from straight down,
    /// lowest first: 80° puts the horizon a fifth of the way down the
    /// picture (the view is 35° tall); the higher ones are for a camera
    /// that would otherwise stand inside a hill.
    public static let skylineTilts: [Float] = [80, 76, 72, 66, 60].map { $0 * .pi / 180 }
    /// How far over the ground under it the eye must be, metres.
    public static let skylineClearance: Float = 30

    /// The skyline spot from `camera`: looking at the same place, turned
    /// `turn` more, from ``skylineDistance`` away and as low as
    /// ``skylineTilts`` allow with the eye ``skylineClearance`` over the
    /// ground under it (`ground`, the height at a scene x and z).
    public static func skylineCamera(from camera: Map3DCamera, turn: Float, ground: (_ x: Float, _ z: Float) -> Float) -> Map3DCamera {
        var goal = camera
        goal.target.y = ground(camera.target.x, camera.target.z)
        goal.heading = Map3DCamera.turnFromNorth(camera.heading + turn)
        goal.distance = skylineDistance
        goal.lens = nil
        goal.lean = 0
        for tilt in skylineTilts {
            goal.pitch = tilt
            let eye = goal.eye
            if eye.y >= ground(eye.x, eye.z) + skylineClearance { break }
        }
        return goal
    }

    /// The skyline spot over `scene`'s ground.
    public static func skylineCamera(from camera: Map3DCamera, turn: Float, in world: GameWorld, scene: Map3DScene) -> Map3DCamera {
        skylineCamera(from: camera, turn: turn) { x, z in scene.drawnGround.height(x: x, z: z, world: world) }
    }

    // MARK: - Leaving

    /// The camera as the photo mode ends: where it looks, tilting by its
    /// distance again as the map's own does (a spot sets the tilt
    /// outright, which two fingers cannot lean).
    public static func cameraLeaving(_ camera: Map3DCamera) -> Map3DCamera? {
        guard camera.pitch != nil || camera.lens != nil else { return nil }
        var goal = camera
        goal.pitch = nil
        goal.lens = nil
        return goal
    }
}
