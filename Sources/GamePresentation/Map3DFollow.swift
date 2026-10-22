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

        /// The tilt from straight down, in radians: Mini Tokyo 3D's pitch,
        /// 85° and 60°.
        public var tilt: Float {
            switch self {
            case .back: 85 * .pi / 180
            case .aboveBack: 60 * .pi / 180
            case .cab: .pi / 2 - Map3DFollow.cabLookDown
            }
        }

        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .back: language.text("Behind", "後方")
            case .aboveBack: language.text("Above", "上後方")
            case .cab: language.text("Cab", "駕駛室")
            }
        }
    }

    public let train: TrainID
    public var view: View
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

    /// The camera following the train whose front is at `head`, `elapsed`
    /// seconds after `camera`: looking at the rail under the front, from
    /// the view's tilt and distance, turned after the train from where
    /// `camera` faced (at once when `turnsAtOnce`).
    public func camera(following head: Map3DTrains.Head, from camera: Map3DCamera, elapsed: Double,
                       turnsAtOnce: Bool = false) -> Map3DCamera {
        var next = camera
        if view == .cab {
            // From the eye, the target the nearest distance ahead down the
            // look; the eye stays where it is at any distance, so a pinch
            // does nothing.
            next.heading = Self.heading(of: head.forward)
            next.pitch = view.tilt
            next.lens = Self.cabLens
            next.distance = Map3DCamera.nearest
            let eye = head.nose + head.forward * Self.cabLead + Map3DPoint(0, Self.cabEyeHeight, 0)
            next.target = eye + next.forward * (next.distance * sinf(view.tilt)) - Map3DPoint(0, next.distance * cosf(view.tilt), 0)
            return next
        }
        next.lens = nil
        next.target = head.rail
        next.distance = min(max(Self.distance(viewportHeight: camera.viewport.height) * scale, Map3DCamera.nearest), Map3DCamera.farthest)
        next.pitch = view.tilt
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
