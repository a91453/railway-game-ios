import Foundation
import GameCore

// Parts of this file are translated from Mini Tokyo 3D
// (https://github.com/nagix/mini-tokyo-3d, commit 220adf8, `src/map.js`
// `_jumpTo`, `updateTrackingParams` and `startViewAnimation`), used under
// the MIT License:
//
// The MIT License (MIT)
//
// Copyright (c) 2019-2026 Akihiko Kusanagi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// Decision 333: the 3D map's camera following a train, from behind it.
/// Mini Tokyo 3D's tracking modes `back` and `topback` (`_jumpTo`): the
/// camera looks at the train, faces the way it runs and turns after it a
/// little each frame, tilted 85° from straight down from behind, or 60°
/// from above behind. Only view state: the 3D map keeps one while the
/// session follows a train (``GameSession/followedTrainID``).
public struct Map3DFollow: Hashable, Sendable {
    /// Where the camera stands.
    public enum View: String, CaseIterable, Hashable, Sendable {
        /// Low behind the train (`back`).
        case back
        /// Above and behind it (`topback`).
        case aboveBack
        /// Decision 337: from the cab, looking ahead down the line (the
        /// owner's OpenWorld reference's `railDriverPose`).
        case cab
        /// Decision 403 (續): beside the train, moving along with it, the
        /// whole of it in view (the owner's OpenWorld reference's watch
        /// view, `maglev-view.js` `applyCamera`).
        case side
        /// Decision 403 (續): standing on the platform of the stop ahead,
        /// watching the train come in (``Lookout``).
        case station

        /// The tilt from straight down, in radians: Mini Tokyo 3D's pitch,
        /// 85° and 60°. Beside the train and from the station, the camera
        /// looks at the train from where it stands, and this is only where
        /// it starts: beside, the reference's 10 m up for 36.7 m across
        /// and back; from the station, level.
        public var tilt: Float {
            switch self {
            case .back: 85 * .pi / 180
            case .aboveBack: 60 * .pi / 180
            case .cab: .pi / 2 - Map3DFollow.cabLookDown
            case .side: atan2f(Map3DFollow.sideAway, Map3DFollow.sideUp)
            case .station: .pi / 2
            }
        }

        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .back: language.text("Behind", "後方")
            case .aboveBack: language.text("Above", "上後方")
            case .cab: language.text("Cab", "駕駛室")
            case .side: language.text("Side", "旁邊")
            case .station: language.text("Station", "從車站看")
            }
        }

        /// What the button does, for VoiceOver.
        public func hint(in language: DisplayLanguage) -> String {
            switch self {
            case .back: language.text("Follows the train from behind.", "從列車後方跟著看。")
            case .aboveBack: language.text("Follows the train from above and behind.", "從列車後上方跟著看。")
            case .cab: language.text("Looks ahead from the driver's seat.", "從駕駛座看前方。")
            case .side: language.text("Moves alongside the train, showing all of it.", "在列車旁邊一起移動，看得到整列。")
            case .station: language.text("Watches the train arrive from the platform of its next stop.", "站在下一站的月台，看列車進站。")
            }
        }
    }

    /// Decision 403 (續): where the station view stands: on a platform of
    /// the stop the train runs to (or stands at, or has just left), at a
    /// person's eye over it.
    public struct Lookout: Hashable, Sendable {
        public let station: StationID
        /// The eye, in the scene's space.
        public let eye: Map3DPoint
        /// Whether the train has left this stop (and is still near it).
        public let left: Bool

        public init(station: StationID, eye: Map3DPoint, left: Bool = false) {
            self.station = station
            self.eye = eye
            self.left = left
        }
    }

    public let train: TrainID
    public var view: View
    /// Decision 403 (續): where the station view stands; `nil` follows
    /// from behind instead.
    public var lookout: Lookout?
    /// How far the camera stands, as a share of ``distance(viewportHeight:)``:
    /// a pinch while following moves it in or out.
    public var scale: Float = 1

    public init(train: TrainID, view: View = .back) {
        self.train = train
        self.view = view
    }

    /// The nearest and farthest a pinch takes ``scale``.
    public static let scales: ClosedRange<Float> = 0.4...4

    /// The follow camera `factor` times closer (more than 1 comes in).
    public func zoomed(by factor: Float) -> Map3DFollow {
        guard factor > 0, factor.isFinite else { return self }
        var follow = self
        follow.scale = min(max(scale / factor, Self.scales.lowerBound), Self.scales.upperBound)
        return follow
    }

    /// Mini Tokyo 3D's map in metres on the ground a pixel at both views'
    /// zoom: zoom 18.5 at Tokyo Station (35.6814° N, its default centre),
    /// Mapbox's 512-pixel tiles, 2π × 6,378,137 m × cos(latitude) /
    /// (512 × 2^18.5): about 0.171 m.
    ///
    /// Its trains are drawn bigger the farther out the map is
    /// (`getScale`: 2^(14 − zoom) between zooms 13 and 19), so at the
    /// above-behind view's zoom 15 a train fills the screen as it does at
    /// 18.5. The game's trains are their real size, so both views stand as
    /// far from the train, and the train looks the same size in both, as
    /// there; only the tilt differs.
    public static let metresPerPoint: Float = {
        let latitude = 35.6814 * Double.pi / 180
        return Float(2 * Double.pi * 6_378_137 * cos(latitude) / (512 * pow(2, 18.5)))
    }()

    /// How far the camera stands from the train in a view `height` points
    /// tall: so the ground at the train is ``metresPerPoint`` a point.
    public static func distance(viewportHeight height: Float) -> Float {
        metresPerPoint * max(height, 1) / (2 * tanf(Map3DCamera.fieldOfView / 2))
    }

    /// Mini Tokyo 3D turns the camera 2 % of the way to the train's heading
    /// each frame at 60 frames a second (`bearingFactor: .02`), and on a
    /// slower screen as far as the frames it missed would have
    /// (`1 − (1 − factor)^frameRateFactor`, at most two frames).
    public static let headingShareAFrame: Float = 0.02

    /// The share of the way to the train's heading the camera turns in
    /// `elapsed` seconds.
    public static func headingShare(elapsed seconds: Double) -> Float {
        let frames = min(max(seconds.isFinite ? seconds : 0, 0) * 60, 2)
        return 1 - powf(1 - headingShareAFrame, Float(frames))
    }

    /// The way `forward` (level) faces, in radians clockwise from north,
    /// as ``Map3DCamera/heading`` counts it.
    public static func heading(of forward: Map3DPoint) -> Float {
        atan2f(forward.x, -forward.z)
    }

    /// Decision 337: the cab view, after the owner's OpenWorld reference
    /// (`OpenWorld/reference_snapshot/play/src/game/rail-camera-pose.js`
    /// `railDriverPose`, `world/train-model-specs.js`, `game/maglev-view.js`
    /// `applyCamera`). The eye rides fixed to the front car (turned with it
    /// at once, no easing), looking down the line `driverLook`
    /// [0, −0.04, 2]: 1.15° under level.
    public static let cabLookDown: Float = atanf(0.04 / 2)
    /// The reference's lens seated in a train, 68° top to bottom.
    public static let cabLens: Float = 68 * .pi / 180
    /// The eye over the rail: the reference's `driverEye` stands 0.04 m
    /// under the car body's middle (台鐵 −0.04, 高鐵 +0.05); the game's
    /// body runs from 0.3 m over the rail to ``Map3DTrains/carHeight``.
    public static let cabEyeHeight: Float = 0.3 + (Map3DTrains.carHeight - 0.3) / 2 - 0.04
    /// How far ahead of the train's nose the eye stands. The reference
    /// puts it in the cab (台鐵 2 m behind the nose) and hides that car's
    /// body for a cab inside; the game's cars are closed boxes with no
    /// inside, so the eye stands just in front of the windscreen.
    public static let cabLead: Float = 0.6

    /// Decision 403 (續): the view beside the train, after the owner's
    /// OpenWorld reference's watch view
    /// (`OpenWorld/reference_snapshot/play/src/game/maglev-view.js`
    /// `applyCamera`, a train watched but not ridden): the eye 33 m out to
    /// the train's left, 16 m back and 10 m up from the middle of its cars,
    /// looking at it, through a 58° lens; all of it times the train's
    /// length over the reference's one car (27.75 m, at least 1) and, on a
    /// screen narrower than 0.92 wide to 1 tall, by as much (at most 2.3,
    /// for 0.4). Left: the side clear of the other track where trains keep
    /// left, as Taiwan's railways do.
    public static let sideAcross: Float = 33
    public static let sideBack: Float = 16
    public static let sideUp: Float = 10
    /// The reference's one car, the length the offsets are for.
    public static let sideTrainLength: Float = 27.75
    /// The reference's watch lens, 58° top to bottom, beside the train and
    /// from the station.
    public static let watchLens: Float = 58 * .pi / 180
    /// How far out the eye stands, level, from the middle of the cars.
    static var sideAway: Float { (sideAcross * sideAcross + sideBack * sideBack).squareRoot() }
    /// How far right of the train's heading the camera beside it faces.
    public static let sideBearing: Float = atan2f(sideAcross, sideBack)

    /// The offsets' scale for a train `length` metres long seen in `viewport`.
    public static func sideScale(length: Float, viewport: (width: Float, height: Float)) -> Float {
        let aspect = max(viewport.width, 1) / max(viewport.height, 1)
        let narrow = max(1, 0.92 / max(0.4, aspect))
        return narrow * max(1, length / sideTrainLength)
    }

    /// Decision 403 (續): the eye on the station's platform: a person's
    /// 1.6 m over its top (``Map3DScene/Builder/platformHeight``, 1.15 m
    /// over the rail), and as far beside the rail as the platform's middle
    /// (its edge 1.6 m out and half its 3.2 m).
    public static let stationEyeHeight: Float = 1.15 + 1.6
    public static let stationEyeAcross: Float = 1.6 + 3.2 / 2
    /// How far past the stop it left the station view stays there: the
    /// train's length and as much again, so its last car is seen leaving.
    public static func stationLingerMetres(trainLength: Int64) -> Int64 { 2 * max(trainLength, 0) / WorldCoordinate.unitsPerMetre + 100 }

    /// The camera at `eye` looking at `target`, through `lens`: as close
    /// as ``Map3DCamera/nearest`` lets it, the target farther along the
    /// same look when it is nearer.
    static func camera(at eye: Map3DPoint, looking target: Map3DPoint, lens: Float, from camera: Map3DCamera) -> Map3DCamera {
        var next = camera
        let look = target - eye
        let level = Map3DPoint(look.x, 0, look.z).length
        guard let way = look.normalized, level > 0.001 else { return camera }
        next.heading = heading(of: look)
        next.pitch = atan2f(level, -look.y)
        next.lens = lens
        next.distance = min(max(look.length, Map3DCamera.nearest), Map3DCamera.farthest)
        next.target = eye + way * next.distance
        return next
    }

    /// The camera following the train whose front is at `head`, `elapsed`
    /// seconds after `camera`: looking at the rail under the front, from
    /// the view's tilt and distance, turned after the train from where
    /// `camera` faced (at once when `turnsAtOnce`). Where the ground
    /// covers the train (``Map3DTrains/Head/ground``), at the ground over
    /// it instead, so the camera stays out of the ground (decision 359).
    public func camera(following head: Map3DTrains.Head, from camera: Map3DCamera, elapsed: Double,
                       turnsAtOnce: Bool = false) -> Map3DCamera {
        var next = camera
        if view == .side {
            // Turned after the train as from behind, its heading read back
            // from the way the camera faces.
            let wanted = Self.heading(of: head.forward)
            let was = camera.heading - Self.sideBearing
            let share = turnsAtOnce ? 1 : Self.headingShare(elapsed: elapsed)
            let turned = was + Map3DCamera.turnFromNorth(wanted - was) * share
            let forward = Map3DPoint(sinf(turned), 0, -cosf(turned)), left = Map3DPoint(forward.z, 0, -forward.x)
            var target = (head.middle ?? head.rail) + Map3DPoint(0, Map3DTrains.carHeight / 2, 0)
            if let ground = head.ground { target.y = max(target.y, ground) }
            let k = Self.sideScale(length: head.length, viewport: camera.viewport) * scale
            let eye = target + left * (Self.sideAcross * k) - forward * (Self.sideBack * k) + Map3DPoint(0, Self.sideUp * k, 0)
            return Self.camera(at: eye, looking: target, lens: Self.watchLens, from: camera)
        }
        if view == .station, let lookout {
            // At the front of the train, half way up it; a pinch does
            // nothing, the eye stays on the platform.
            return Self.camera(at: lookout.eye, looking: head.nose + Map3DPoint(0, Map3DTrains.carHeight / 2, 0),
                               lens: Self.watchLens, from: camera)
        }
        if view == .cab {
            // From the eye, the target the nearest distance ahead down the
            // look; the eye stays where it is at any distance, so a pinch
            // does nothing.
            next.heading = Self.heading(of: head.forward)
            next.pitch = view.tilt
            next.lens = Self.cabLens
            next.distance = Map3DCamera.nearest
            var eye = head.nose + head.forward * Self.cabLead + Map3DPoint(0, Self.cabEyeHeight, 0)
            // Decision 359: over the ground where it covers the track (a
            // deep cutting), not in it; decision 359 (續): in a tunnel, in
            // its bore.
            if let ground = head.ground, !head.inTunnel { eye.y = max(eye.y, ground + Self.cabEyeHeight) }
            next.target = eye + next.forward * (next.distance * sinf(view.tilt)) - Map3DPoint(0, next.distance * cosf(view.tilt), 0)
            return next
        }
        next.lens = nil
        next.target = head.rail
        // Decision 359: the ground over the train where it covers it, so
        // the camera does not go under the ground with it.
        if let ground = head.ground { next.target.y = max(next.target.y, ground) }
        next.distance = min(max(Self.distance(viewportHeight: camera.viewport.height) * scale, Map3DCamera.nearest), Map3DCamera.farthest)
        // From the station with no platform to stand on: from behind.
        next.pitch = (view == .station ? View.back : view).tilt
        let wanted = Self.heading(of: head.forward)
        let share = turnsAtOnce ? 1 : Self.headingShare(elapsed: elapsed)
        next.heading = Map3DCamera.turnFromNorth(camera.heading + Map3DCamera.turnFromNorth(wanted - camera.heading) * share)
        return next
    }
}

/// Decision 333: the 3D camera flying from where it was to where it is
/// going (the follow view as a train is followed; decision 334, a train at
/// its platform), as the reference's `cameraMotion` animates the map
/// (`Railway/taiwan-rail-reference-clean/source/rail-3d/integration/camera-motion.js`):
/// 1.2 s, smooth at both ends (`t² (3 − 2t)`), the shorter way round; a
/// long way rises over the middle (the zoom's `dip`, sin²(πt)) so the
/// ground does not stream past; with Reduce Motion, there at once. The
/// goal can move as it flies (a running train): each frame blends the
/// start toward the goal of that frame, as Mini Tokyo 3D's
/// `startViewAnimation` does toward the train.
public struct Map3DFlight: Hashable, Sendable {
    public let start: Map3DCamera
    /// When it began, in seconds of the caller's clock.
    public let began: Double
    /// How long it takes; 0 is there at once.
    public let seconds: Double

    /// A flight from `start` beginning at `began`, run as `rule` says
    /// (``MotionRule/cameraFlight``, ``MotionRule/running(reduceMotion:)``):
    /// `nil`, there at once.
    public init(from start: Map3DCamera, began: Double, rule: MotionRule?) {
        self.start = start
        self.began = began
        seconds = rule?.seconds ?? 0
    }

    /// How far through it is at `now`, 0 to 1.
    public func progress(at now: Double) -> Float {
        guard seconds > 0 else { return 1 }
        return Float(min(max((now - began) / seconds, 0), 1))
    }

    public func isOver(at now: Double) -> Bool { progress(at: now) >= 1 }

    /// The camera at `now` on the way to `goal`; `goal` itself once over.
    public func camera(toward goal: Map3DCamera, at now: Double) -> Map3DCamera {
        let t = progress(at: now)
        guard t < 1 else { return goal }
        let e = t * t * (3 - 2 * t)
        var camera = goal
        camera.target = start.target + (goal.target - start.target) * e
        camera.heading = Map3DCamera.turnFromNorth(start.heading + Map3DCamera.turnFromNorth(goal.heading - start.heading) * e)
        camera.pitch = start.tilt + (goal.tilt - start.tilt) * e
        // Decision 337: into or out of the cab view's wider lens.
        if start.lens != nil || goal.lens != nil {
            camera.lens = start.fieldOfViewTall + (goal.fieldOfViewTall - start.fieldOfViewTall) * e
        }
        // The distance by its logarithm, as the reference's zoom, rising by
        // `dip` over the middle when the way is longer than the view.
        let from = log2f(start.distance), to = log2f(goal.distance)
        let rise = sinf(.pi * t)
        let level = from + (to - from) * e + Self.dip(from: start, to: goal) * rise * rise
        camera.distance = min(max(powf(2, level), Map3DCamera.nearest), Map3DCamera.farthest)
        return camera
    }

    /// How much farther out, in doublings of the distance, the middle of a
    /// flight from `a` to `b` stands: the reference's `dip`, by how far
    /// past the halfway distance the camera must be for 1.4 times the way
    /// (at least 100 m) to fit across the view.
    public static func dip(from a: Map3DCamera, to b: Map3DCamera) -> Float {
        let way = max(100, (Map3DPoint(b.target.x - a.target.x, 0, b.target.z - a.target.z)).length) * 1.4
        let aspect = max(b.viewport.width, 1) / max(b.viewport.height, 1)
        let seesWay = way / (2 * tanf(Map3DCamera.fieldOfView / 2) * aspect)
        return max(0, log2f(seesWay) - (log2f(a.distance) + log2f(b.distance)) / 2)
    }
}

extension GameWorld {
    /// Decision 403 (續): the stop the station view watches train `id`
    /// from: the one it stands at, or runs to; just after leaving one,
    /// that one, until it is ``Map3DFollow/stationLingerMetres(trainLength:)``
    /// past it, or half the way to the next (`left`). `nil` for a train with no service.
    public func map3DLookoutStop(of id: TrainID) -> (station: StationID, left: Bool)? {
        guard let train = train(id: id), let execution = train.execution, train.timetable.indices.contains(execution.stop)
        else { return nil }
        switch execution {
        case .waitingAtStop(let stop, _):
            return (train.timetable[stop].station, false)
        case .travellingToStop(let stop, let cycle):
            // The stop before: the last of the cycle before, for the first.
            let previous = stop > 0 ? stop - 1 : (cycle > 0 ? train.timetable.count - 1 : nil)
            if let previous, let run = train.times?.run, let curve = runCurve(of: run, for: train.performance) {
                let elapsed = max(0, clock.now.seconds - run.start.seconds)
                let done = elapsed >= run.seconds ? run.length : curve.distance(at: elapsed * 1000)
                // Review I: no farther than half the run, so a stop close
                // ahead is watched before the train stands there.
                let linger = min(Map3DFollow.stationLingerMetres(trainLength: train.length) * WorldCoordinate.unitsPerMetre, run.length / 2)
                if done < linger {
                    return (train.timetable[previous].station, true)
                }
            }
            return (train.timetable[stop].station, false)
        }
    }
}

extension Map3DFollow {
    /// Decision 403 (續): where the station view of train `train` stands
    /// in `scene`: on the platform it stops at (as the station's board
    /// reads it, ``Map3DNextDeparture/platform(of:at:in:)``), at its
    /// middle, on the side the scene lays it (towards its island partner
    /// across the next track within 15 m, else the left), a person's eye
    /// over it. `nil` with no stop, no platform, or a platform in a
    /// tunnel (the scene lays none there).
    public static func lookout(of train: TrainID, in world: GameWorld, scene: Map3DScene) -> Lookout? {
        guard let stop = world.map3DLookoutStop(of: train),
              let platform = Map3DNextDeparture.platform(of: train, at: stop.station, in: world),
              let middle = Map3DNextDeparture.middle(of: platform, in: world, scene: scene),
              !scene.trackCover.isInTunnel(middle.point) else { return nil }
        let right = Map3DPoint(-middle.along.z, 0, middle.along.x)
        let partner = world.trackPlatforms(of: stop.station)
            .filter { $0.edge != platform.edge }
            .compactMap { Map3DNextDeparture.middle(of: $0, in: world, scene: scene).map { ($0.point - middle.point).dot(right) } }
            .filter { abs($0) < 15 }
            .min { abs($0) < abs($1) }
        let side: Float = (partner ?? -1) >= 0 ? 1 : -1
        return Lookout(station: stop.station, eye: middle.point + right * (side * stationEyeAcross) + Map3DPoint(0, stationEyeHeight, 0),
                       left: stop.left)
    }
}
