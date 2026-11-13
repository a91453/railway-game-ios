import GameCore

// Decision 710: stopping a train driven by hand (decision 686): a bar
// over the last 200 m that shows where the train is against its stopping
// point, a mark beside the track there, and a look at the train from
// beside it once it stands, with the run's marks. The owner's references
// have no driving and no stopping marks (decision 710's table); the
// figures here are this project's.

extension ManualDrive {
    /// The bar shown over the last stretch to the stopping point: short
    /// of it, on it, past it, and where the train's head is now.
    public struct StopBar: Hashable, Sendable {
        public enum State: Hashable, Sendable {
            /// Not there yet.
            case short
            /// Within ``ManualDrive/exactMetres`` of the point: where the
            /// position earns its full marks.
            case onTarget
            /// Past it.
            case past
        }

        /// The bar shows from this many metres short of the point (the
        /// distance decision 704's "stop ahead" always shows within).
        public static let showMetres = ManualDrive.stopAheadMetres
        /// The bar's far end past the point: where the position earns
        /// nothing any more (``ManualDrive/pastMetres``).
        public static let pastMetres = ManualDrive.pastMetres

        /// Where along the bar (0 its start, 1 its end) a head `metres`
        /// short of the point is drawn. The last metres take most of the
        /// bar, so the half metre aimed at can be seen: each pair is
        /// metres short (negative past) and the share of the bar there,
        /// straight between them.
        static let scale: [(metres: Double, share: Double)] = [
            (showMetres, 0), (50, 0.18), (10, 0.38), (exactMetres, 0.62), (-exactMetres, 0.72), (-pastMetres, 1),
        ]
        /// The target's two edges along the bar.
        public static let target: ClosedRange<Double> = share(short: exactMetres)...share(short: -exactMetres)

        /// Where along the bar a head `metres` short of the point is
        /// (negative: past it), held on the bar.
        public static func share(short metres: Double) -> Double {
            guard metres.isFinite else { return 0 }
            guard let last = scale.last, metres > last.metres else { return 1 }
            for (near, far) in zip(scale.dropFirst(), scale) where metres >= near.metres {
                guard metres < far.metres else { return far.share }
                return near.share + (far.share - near.share) * (metres - near.metres) / (far.metres - near.metres)
            }
            return 1
        }

        public let state: State
        /// Where the head is along the bar, 0 to 1.
        public let marker: Double
        /// Tenths of a metre still to the point (negative past it), as
        /// the panel's figure (``Reading/remainingTenths``).
        public let remainingTenths: Int

        /// The bar for a run in `phase` with `remainingTenths` to its
        /// point; `nil` when none shows: before the train has left, more
        /// than ``showMetres`` away, and once the run is over.
        public init?(phase: Reading.Phase, remainingTenths: Int?) {
            guard phase == .driving, let tenths = remainingTenths, Double(tenths) <= Self.showMetres * 10 else { return nil }
            let exact = Int(ManualDrive.exactMetres * 10)
            state = tenths > exact ? .short : tenths < -exact ? .past : .onTarget
            marker = Self.share(short: Double(tenths) / 10)
            self.remainingTenths = tenths
        }

        /// "Short", "Stop here", "Past".
        public static func text(of state: State, in language: DisplayLanguage) -> String {
            switch state {
            case .short: language.text("Short", "未到位")
            case .onTarget: language.text("Stop here", "停車目標")
            case .past: language.text("Past", "越位")
            }
        }

        /// The figure beside the bar, as the strip above writes it: "40 m"
        /// (tens of metres), "4.2 m" within 10 m, "On
        /// the mark", "1.3 m past".
        public func text(in language: DisplayLanguage) -> String {
            switch state {
            case .onTarget:
                return language.text("On the mark", "在目標上")
            case .short:
                return remainingTenths < 100 ? ManualDrive.metresText(tenths: remainingTenths)
                    : Map3DDriverHUD.distanceText(Int64(remainingTenths / 10))
            case .past:
                let past = ManualDrive.metresText(tenths: -remainingTenths)
                return language.text("\(past) past", "超過 \(past)")
            }
        }

        public static func title(in language: DisplayLanguage) -> String {
            language.text("Stopping position", "停車位置")
        }

        /// What VoiceOver reads for the bar: "Short, 38 m to go", "On the
        /// stopping point", "Past, 1.3 m past the stopping point".
        public func value(in language: DisplayLanguage, assisting: Bool = false) -> String {
            let value = value(of: state, in: language)
            return assisting ? value + language.text(", stopping assist braking", "，輔助停車煞車中") : value
        }

        private func value(of state: State, in language: DisplayLanguage) -> String {
            switch state {
            case .short:
                return language.text("Short, \(text(in: language)) to go", "未到位，還差 \(text(in: language))")
            case .onTarget:
                return language.text("On the stopping point", "在停車目標上")
            case .past:
                let past = ManualDrive.metresText(tenths: -remainingTenths)
                return language.text("Past, \(past) past the stopping point", "越位，超過停車目標 \(past)")
            }
        }

        /// How coming into a part of the bar is felt.
        public enum Feel: Hashable, Sendable {
            /// The head has come onto the target.
            case onTarget
            /// It has run past it.
            case past
        }

        /// What going from `old` to `new` is felt as: coming onto the
        /// target, and running past it; nothing for the bar showing,
        /// going, or the head still short.
        public static func feel(from old: State?, to new: State?) -> Feel? {
            guard old != new, old != nil else { return nil }
            switch new {
            case .onTarget: return .onTarget
            case .past: return .past
            case .short, nil: return nil
            }
        }
    }

    /// Decision 710: once the train stands at its stop, the camera looks
    /// at it from beside it for a while, the run's marks over that view,
    /// then goes back to where the player drove from.
    public enum StopLook {
        /// How long the look from beside lasts unless the player ends it.
        public static let seconds = 8.0
        /// How near the look stands, as a share of the view from beside's
        /// own distance (``Map3DFollow/lookScale``): the train some six
        /// tenths of the screen's width, clear of the result card.
        public static let scale: Float = 0.45

        /// Whether a run that ended with `result` is looked at from
        /// beside: one that stopped at its stop, and not with Reduce
        /// Motion, which leaves the camera where it is.
        public static func turns(for result: Result?, reduceMotion: Bool) -> Bool {
            result?.outcome == .stopped && !reduceMotion
        }

        /// Where the train is followed from: `chosen`, the player's view,
        /// but from beside while a run that stopped is looked at
        /// (`looking`: since it stopped, until ``seconds`` have passed).
        public static func view(chosen: Map3DFollow.View, result: Result?, looking: Bool, reduceMotion: Bool) -> Map3DFollow.View {
            looking && turns(for: result, reduceMotion: reduceMotion) ? .side : chosen
        }

        /// The look's own distance while it lasts; `nil` otherwise.
        public static func scale(result: Result?, looking: Bool, reduceMotion: Bool) -> Float? {
            looking && turns(for: result, reduceMotion: reduceMotion) ? scale : nil
        }

        /// The result card's button: "Back to the cab" while a player who
        /// drives from the cab looks at the stopped train from beside
        /// (`looking`), "OK" once the camera is back in the cab (or never
        /// left it), "Back to the train" from any other view.
        public static func backText(chosen: Map3DFollow.View, looking: Bool, in language: DisplayLanguage) -> String {
            guard chosen == .cab else { return ManualDrive.doneText(in: language) }
            return looking ? language.text("Back to the cab", "回駕駛室") : language.text("OK", "好")
        }
    }

    /// Decision 710: the mark that stands at the stopping point: a post
    /// beside the track with a yellow board, and a yellow bar between the
    /// rails, both lit at night. Plain boxes in the platform edge's
    /// yellow and the rails' grey: no model of its own.
    public enum StopMark {
        /// The post stands this far left of the track's middle, clear of
        /// the car's side (``Map3DTrains/carWidth``), in metres.
        public static let postAcross: Float = 2.3
        public static let postHeight: Float = 3.0
        public static let postWidth: Float = 0.12
        /// The board, square, its top at the post's.
        public static let boardSide: Float = 0.6
        public static let boardDepth: Float = 0.06
        /// The bar between the rails: along the track, across it, and how
        /// far its top stands under the rails' (clear of the wheels).
        public static let barLength: Float = 0.4
        public static let barWidth: Float = 0.9
        public static let barHeight: Float = 0.15
        public static let barUnderRail: Float = 0.05

        /// Adds the mark to `mesh` where the head stops: `rail` on the
        /// rails' top at the track's middle, the train coming along
        /// `forward`. Nothing for a `forward` with no length on the plan.
        public static func add(to mesh: inout Map3DMesh, at rail: Map3DPoint, forward: Map3DPoint) {
            guard let along = Map3DPoint(forward.x, 0, forward.z).normalized else { return }
            let left = Map3DPoint(along.z, 0, -along.x)
            let post = rail + left * postAcross
            mesh.addBox(base: post, forward: along, length: postWidth, width: postWidth, height: postHeight - boardSide,
                        top: Map3DPalette.rail, side: Map3DPalette.rail)
            let lit = mesh.vertices.count
            mesh.addBox(base: post + Map3DPoint(0, postHeight - boardSide, 0), forward: along, length: boardDepth, width: boardSide,
                        height: boardSide, top: Map3DPalette.platformEdge, side: Map3DPalette.platformEdge, shaded: false)
            mesh.addBox(base: rail - Map3DPoint(0, barUnderRail + barHeight, 0), forward: along, length: barLength, width: barWidth,
                        height: barHeight, top: Map3DPalette.platformEdge, side: Map3DPalette.platformEdge, shaded: false)
            mesh.makeGlowing(from: lit)
        }
    }
}

// MARK: - The stopping assist

extension ManualDrive {
    /// Decision 710: the stopping assist. On, it takes the brake over the
    /// last stretch and stops the head on the stopping point, once the
    /// player has brought the train down to a speed it can stop from: the
    /// player still does the running and the slowing, the assist the last
    /// metres. A run it helped is told so (``Result/assisted``).
    public enum StopAssist {
        /// Where the player's choice is kept (the app's preferences, not
        /// the save): on unless the player turned it off.
        public static let key = "manualDriveStopAssist"
        public static let isOnByDefault = true

        /// The assist takes the brake within the stopping bar's reach
        /// (``StopBar/showMetres``), once stopping on the point asks for
        /// at least this share of the timetable's braking (brake step 3
        /// of 5: before that the player's own handle is enough, and a
        /// train crawling from far off is left to crawl)...
        public static let takesShare = 0.6
        /// ...and for no more than the timetable's braking itself (step
        /// 5): a train too fast for that is the player's to slow first.
        public static let takesAtMostShare = 1.0
        /// Holding the brake, it goes as hard as the hardest service
        /// brake (step 7) when the point is nearer than it thought, and
        /// lets the train roll while less than this share would do, so it
        /// does not creep to a stand short of the point.
        public static var mostShare: Double { Double(Notch.brakeSteps) / Double(ManualDrive.timetableBrakeStep) }
        public static let rollsShare = 0.3
        /// The brake comes on at ``ManualDrive/jerk``, so the assist aims
        /// this many seconds of running short of the point.
        public static let leadSeconds = 0.25

        public static func title(in language: DisplayLanguage) -> String {
            language.text("Stopping assist", "輔助停車")
        }

        /// Under the switch, and what VoiceOver adds to it.
        public static func hint(in language: DisplayLanguage) -> String {
            language.text("Stops you on the mark. At most half the bonus.",
                          "最後幾公尺幫你停準；用了輔助，獎金最多一半。")
        }

        /// Beside the stopping bar while it holds the brake.
        public static func activeText(in language: DisplayLanguage) -> String {
            language.text("Assist", "輔助中")
        }

        /// On the result card of a run it helped.
        public static func usedText(in language: DisplayLanguage) -> String {
            language.text("Stopping assist helped", "用了輔助停車")
        }
    }

    /// What the stopping assist asks for now, m/s² (negative: braking),
    /// or `nil` while the handle is the player's: off, the power on or the
    /// emergency brake, standing, past the point, farther than the
    /// stopping bar reaches, too fast for the timetable's braking to stop
    /// on the point, or (until it has taken the brake) still slow enough
    /// that less than ``StopAssist/takesShare`` of the timetable's braking
    /// would do.
    func assistAsked() -> Double? {
        guard assists, !isOver, notch.step <= 0, !notch.isEmergency, speed > 0, train.braking > 0 else { return nil }
        let most = train.braking * StopAssist.mostShare
        let room = remaining - speed * StopAssist.leadSeconds
        let needed = room > 0 ? speed * speed / (2 * room) : most
        // Once it has the brake it keeps it to the stand: as hard as the
        // service brake goes if the point is nearer than it thought, and
        // rolling while the train is ahead of what stopping there asks.
        if isAssisting { return needed >= train.braking * StopAssist.rollsShare ? -min(needed, most) : -train.rolling }
        guard remaining > 0, remaining <= StopBar.showMetres, needed >= train.braking * StopAssist.takesShare,
              needed <= train.braking * StopAssist.takesAtMostShare else { return nil }
        return -needed
    }
}

extension ManualDrive.Reading {
    /// Decision 710: the stopping bar, while it shows.
    public var stopBar: ManualDrive.StopBar? {
        ManualDrive.StopBar(phase: phase, remainingTenths: remainingTenths)
    }
}

extension ManualDriveTrack {
    /// Decision 710: where a head `metres` into the run stands on the
    /// track, with its height there, and the way the track goes there on
    /// the plan; `nil` for a track with no direction.
    func place(metres: Double) -> (coordinate: WorldCoordinate, direction: TrainMotion.Point)? {
        let head = along(metres: metres)
        guard let direction = trail.direction(at: head) else { return nil }
        return (coordinate(at: head), direction)
    }

    /// Decision 710: adds the stopping point's mark (``ManualDrive/StopMark``)
    /// to `frame`, where a head `metres` into the run stops, as `scene`
    /// lays the track (on its rails, ``Map3DScene/railLift`` up).
    public func addStopMark(to frame: inout Map3DTrains.Frame, at metres: Double, in scene: Map3DScene) {
        guard let place = place(metres: metres) else { return }
        ManualDrive.StopMark.add(to: &frame.boxes, at: scene.point(place.coordinate) + Map3DPoint(0, Map3DScene.railLift, 0),
                                 forward: Map3DPoint(Float(place.direction.x), 0, Float(place.direction.y)))
    }
}
