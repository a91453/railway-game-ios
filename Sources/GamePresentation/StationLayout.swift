import GameCore

// A station's layout in one step (decision 507, a player's suggestion the
// owner took: 「好 照你的排」): before building a station the player picks
// how its platforms and tracks stand, and ✓ builds all of it as one
// command. Five layouts, the usual ones of Taiwan's stations (decision
// 507 has a real station of each):
//
//   single track, one side platform       ───────  ▭
//   single track, an island, two tracks   ═╗ ▭ ╔═   (a passing loop)
//   double track, two side platforms      ▭ ═══ ▭
//   double track, one island              ═╗ ▭ ╔═   (the mains spread)
//   double track, two islands, four tracks
//
// No new rule and no new part: the platform is the platform tool's
// (`addNetworkPlatform`, with the track beside's, decision 285), each
// island's second track a platform track (`PlatformTrack.swift`, its
// turnouts, S-curves and spacing), and for one island between the mains
// the track beside is swung out round it and its old stretch taken up
// (GameCore's `removeTrackEdge`). Every step is planned on a copy of the
// world, one after another, so each sees the track the one before laid;
// replayed in order on the world itself they build the same.

/// How a station's platforms and tracks stand (decision 507).
public enum StationLayout: String, CaseIterable, Hashable, Sendable {
    /// Single track, one platform beside it.
    case singleSide
    /// Single track with a loop: an island platform between the two.
    case singleIsland
    /// Double track, a platform outside each track.
    case doubleSide
    /// Double track, one island platform between the two, the track
    /// beside swung out round it.
    case doubleIsland
    /// Double track and a loop outside each, an island between each loop
    /// and its main track: four tracks, two islands.
    case doubleTwoIslands

    /// Whether it is laid on double track (the track tapped has another
    /// beside it).
    public var isDouble: Bool {
        switch self {
        case .singleSide, .singleIsland: false
        case .doubleSide, .doubleIsland, .doubleTwoIslands: true
        }
    }

    /// The tracks through the station once built.
    public var tracks: Int {
        switch self {
        case .singleSide: 1
        case .singleIsland, .doubleSide, .doubleIsland: 2
        case .doubleTwoIslands: 4
        }
    }

    /// The platforms passengers stand on: an island is one, serving two
    /// tracks.
    public var platforms: Int {
        switch self {
        case .singleSide, .singleIsland, .doubleIsland: 1
        case .doubleSide, .doubleTwoIslands: 2
        }
    }

    /// Whether ✓ lays track for it beyond the platform tool's own
    /// (``StationLayoutPlan``); the two side layouts are the tool as it was.
    var isLaidByLayout: Bool {
        switch self {
        case .singleSide, .doubleSide: false
        case .singleIsland, .doubleIsland, .doubleTwoIslands: true
        }
    }

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .singleSide: language.text("Single, one side", "單線一岸")
        case .singleIsland: language.text("Single, island", "單線一島兩線")
        case .doubleSide: language.text("Double, two sides", "雙線兩岸")
        case .doubleIsland: language.text("Double, island", "雙線一島")
        case .doubleTwoIslands: language.text("Double, two islands", "雙線兩島四線")
        }
    }

    /// What it builds, in a sentence.
    public func summary(in language: DisplayLanguage) -> String {
        switch self {
        case .singleSide:
            language.text("One platform beside a single track.", "單線鐵路旁一座月台。")
        case .singleIsland:
            language.text(
                "A second track joins the line at each end, with one platform between the two, so trains can pass here.",
                "兩端用轉轍器多接一股軌道，兩股中間一座月台，列車可以在這裡交會。"
            )
        case .doubleSide:
            language.text("A platform outside each of the two tracks.", "雙線兩股軌道外側各一座月台。")
        case .doubleIsland:
            language.text(
                "The two tracks spread apart round one platform between them.",
                "兩股軌道在站內分開，中間一座月台。"
            )
        case .doubleTwoIslands:
            language.text(
                "A loop outside each track and a platform between each loop and its track, so fast trains can pass stopping ones.",
                "兩股軌道外側各加一股待避線，每股待避線與正線中間一座月台，快車可以在這裡超越停站的車。"
            )
        }
    }
}

/// A station's layout as planned (decision 507): the platform, then each
/// platform track in order, then the stretches of track taken up.
public struct StationLayoutPlan: Hashable, Sendable {
    public let layout: StationLayout
    let platform: PlayerCommand.PlatformAddition
    let tracks: [PlatformTrackPlan]
    let removed: [TrackEdgeID]
}

/// Why a layout cannot be laid where the platform was picked.
enum StationLayoutProblem: Error {
    /// A double-track layout on single track.
    case needsDouble
    /// The track beside cannot take its platform (a platform there
    /// already, a train on it).
    case besideRefused
    /// No room for a loop's turnouts, or the track there climbs.
    case track(PlatformTrackProblem)
    /// GameCore refused a step.
    case refused(GameError)

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .needsDouble:
            language.text("This layout needs double track here.", "這種排法要在雙線的軌道上蓋。")
        case .besideRefused:
            language.text("The track beside cannot take a platform here.", "旁邊那股軌道這裡放不了月台。")
        case .track(let problem):
            problem.text(in: language)
        case .refused(let error):
            error.playerMessage(in: language)
        }
    }
}

struct StationLayoutMemo {
    struct Key: Equatable {
        let edge: TrackEdgeID
        let start: Int64
        let end: Int64
        let layout: StationLayout
        let station: StationID?
        let language: DisplayLanguage
        let commandRevision: Int
    }

    let key: Key
    let preview: StationLayoutPreview
}

/// A row of the layout menu (``GameSession/stationLayoutChoices``).
public struct StationLayoutChoice: Hashable, Sendable, Identifiable {
    public let layout: StationLayout
    public let title: String
    public let fits: Bool
    public var id: StationLayout { layout }
}

/// What ✓ would pay for a layout's tracks and platforms, the station's
/// own price and levelling included, or why it cannot be laid.
public struct StationLayoutPreview: Hashable, Sendable {
    public let cost: Money?
    public let problem: String?
}

extension GameSession {
    /// The layout ✓ builds where the platform was picked: the player's
    /// pick (``stationLayout``) where it fits the track, single or
    /// double; else the plain one for that track, one side platform or a
    /// platform each side, as the platform tool always built.
    public var networkStationLayout: StationLayout {
        fits(stationLayout) ? stationLayout : (networkPlatformBeside == nil ? .singleSide : .doubleSide)
    }

    /// Whether `layout` fits the track picked for a platform: single
    /// layouts on single track, double ones where the track beside has
    /// room for a platform (``networkPlatformBeside``). Every layout fits
    /// before a track is picked.
    public func fits(_ layout: StationLayout) -> Bool {
        guard networkPlatformStretch != nil else { return true }
        return layout.isDouble == (networkPlatformBeside != nil)
    }

    /// What the layout menu says of `layout` where it does not fit the
    /// track picked; `nil` where it does.
    public func stationLayoutUnfitText(_ layout: StationLayout) -> String? {
        guard !fits(layout) else { return nil }
        return layout.isDouble
            ? language.text("Needs double track", "要在雙線上")
            : language.text("This track is double", "這裡是雙線")
    }

    /// The platform mode's big button: "Build station" where the pick
    /// starts a new station, "Add platform" where it joins one that
    /// stands (``platformStationID``).
    public var networkPlatformActionTitle: String {
        platformStationID == nil
            ? language.text("Build Station", "蓋車站")
            : language.text("Add Platform", "加月台")
    }

    /// The layout menu of the platform mode: each layout by name, those
    /// that do not fit the track picked with why, and off.
    public var stationLayoutChoices: [StationLayoutChoice] {
        StationLayout.allCases.map { layout in
            let title = layout.title(in: language)
            let unfit = stationLayoutUnfitText(layout)
            return StationLayoutChoice(layout: layout, title: unfit.map { language.text("\(title) (\($0))", "\(title)（\($0)）") } ?? title, fits: unfit == nil)
        }
    }

    /// What ✓ pays for ``networkStationLayout`` with its platform, or why
    /// it cannot be laid; `nil` for the two side layouts, which are the
    /// platform tool's own (``networkPlatformCost``). The map's pill reads
    /// it every frame, so it is kept for the stretch and command it was
    /// worked out for, as ``networkPlatformLevelling`` is.
    public var networkStationLayoutPreview: StationLayoutPreview? {
        let layout = networkStationLayout
        guard layout.isLaidByLayout, let stretch = networkPlatformStretch else { return nil }
        _ = world
        let key = StationLayoutMemo.Key(
            edge: stretch.edge, start: stretch.start, end: stretch.end, layout: layout, station: platformStationID,
            language: language, commandRevision: commandRevision
        )
        if let memo = stationLayoutMemo, memo.key == key { return memo.preview }
        let preview: StationLayoutPreview
        switch networkPlatformDraft(beside: layout != .doubleIsland) {
        case .failure(let refusal):
            preview = StationLayoutPreview(cost: nil, problem: refusal.text)
        case .success(let draft):
            switch stationLayoutPlan(layout, platform: draft.addition) {
            case .failure(let problem):
                preview = StationLayoutPreview(cost: nil, problem: problem.text(in: language))
            case .success(let plan):
                do throws(GameError) {
                    let cost = try priced { world throws(GameError) in try apply(.buildStationLayout(plan), to: &world) }.cost
                    preview = StationLayoutPreview(cost: cost, problem: shortfallText(cost, doing: .buildStationLayout(plan)))
                } catch {
                    preview = StationLayoutPreview(cost: nil, problem: error.playerMessage(in: language))
                }
            }
        }
        stationLayoutMemo = StationLayoutMemo(key: key, preview: preview)
        buildPreviewsWorkedOut += 1
        return preview
    }

    /// What the tool's message adds for a layout it laid.
    func stationLayoutText(_ layout: StationLayout) -> String {
        language.text(" Laid out as \(layout.title(in: language).lowercased()).", "排法：\(layout.title(in: language))。")
    }

    /// Plans `layout` round the platform `addition` (decision 507; see the
    /// file's header): each step on a copy of the world after the one
    /// before. A loop goes on the side clear of the track beside, or for
    /// single track the left first, else the right.
    func stationLayoutPlan(_ layout: StationLayout, platform addition: PlayerCommand.PlatformAddition)
        -> Result<StationLayoutPlan, StationLayoutProblem>
    {
        var probe = world.pricingCopy()
        let outcome: PlayerCommand.Outcome
        do throws(GameError) {
            outcome = try apply(.addPlatform(addition), to: &probe)
        } catch {
            return .failure(.refused(error))
        }
        guard let station = outcome.station?.id, let stretch = outcome.stretch else { return .failure(.refused(.invalidTrackGeometry)) }
        let island = PlatformTrackLayout.island
        var tracks: [PlatformTrackPlan] = []
        var removed: [TrackEdgeID] = []
        /// A loop beside `platform`, `spacing` out on the first of `sides`
        /// it fits, built on the copy.
        func loop(beside platform: TrackPlatform, spacing: Int64, sides: [PlatformTrackSide])
            -> Result<PlatformTrackPlan, StationLayoutProblem>
        {
            var last = StationLayoutProblem.track(.noRoom)
            for side in sides {
                switch sidingPlan(on: platform.edge, from: platform.start, to: platform.end, spacing: spacing, reach: island.reach, side: side, in: probe) {
                case .failure(let problem):
                    last = .track(problem)
                case .success(let siding):
                    let plan = PlatformTrackPlan(
                        platform: platform, near: siding.near, far: siding.far, beside: siding.beside, curves: siding.curves,
                        structure: siding.structure
                    )
                    var draft = probe
                    do throws(GameError) {
                        _ = try build(plan, in: &draft)
                        probe = draft
                        tracks.append(plan)
                        return .success(plan)
                    } catch {
                        last = .refused(error)
                    }
                }
            }
            return .failure(last)
        }
        let main = TrackPlatform(station: station, edge: stretch.edge, start: stretch.start, end: stretch.end)
        switch layout {
        case .singleSide, .doubleSide:
            break
        case .singleIsland:
            if case .failure(let problem) = loop(beside: main, spacing: island.spacing, sides: [.left, .right]) { return .failure(problem) }
        case .doubleTwoIslands:
            guard addition.beside != nil else { return .failure(.besideRefused) }
            // The platform the track beside got: the station's nearest
            // other one to where it was asked for.
            guard let besideStretch = besidePlatformStretch(of: (addition.edge, addition.start, addition.end)),
                  let other = nearestPlatform(of: station, to: middle(of: besideStretch, in: world), except: main, in: probe)
            else { return .failure(.besideRefused) }
            // Both sides found first: the first loop splits the main track.
            guard let mainAway = side(of: main, awayFrom: other, in: probe), let otherAway = side(of: other, awayFrom: main, in: probe) else {
                return .failure(.track(.missing))
            }
            for (platform, away) in [(main, mainAway), (other, otherAway)] {
                if case .failure(let problem) = loop(beside: platform, spacing: island.spacing, sides: [away]) { return .failure(problem) }
            }
        case .doubleIsland:
            // The track beside swings out to stand an island's spacing from
            // the platform's track, then its old stretch is taken up.
            guard let besideStretch = besidePlatformStretch(of: (addition.edge, addition.start, addition.end)) else {
                return .failure(.needsDouble)
            }
            let beside = TrackPlatform(station: station, edge: besideStretch.edge, start: besideStretch.start, end: besideStretch.end)
            guard let away = side(of: beside, awayFrom: main, in: probe) else { return .failure(.track(.missing)) }
            let plan: PlatformTrackPlan
            switch loop(beside: beside, spacing: island.spacing - DoubleTrack.spacing, sides: [away]) {
            case .success(let found): plan = found
            case .failure(let problem): return .failure(problem)
            }
            let old = middle(of: besideStretch, in: world)
            guard let taken = stretchBetween(plan.near.position.plan, plan.far.position.plan, through: old, in: probe) else {
                return .failure(.track(.noRoom))
            }
            do throws(GameError) {
                for edge in taken {
                    _ = try apply(.removeTrack(edge), to: &probe)
                }
            } catch {
                return .failure(.refused(error))
            }
            removed = taken
        }
        return .success(StationLayoutPlan(layout: layout, platform: addition, tracks: tracks, removed: removed))
    }

    /// The middle of `stretch` in `world`.
    private func middle(of stretch: (edge: TrackEdgeID, start: Int64, end: Int64), in world: GameWorld) -> PlanPoint {
        world.trackGeometry(of: stretch.edge).map { $0.location(at: (stretch.start + stretch.end) / 2).position.plan } ?? PlanPoint(x: 0, y: 0)
    }

    /// `station`'s platform in `world` whose middle is nearest `point`,
    /// but `except`.
    private func nearestPlatform(of station: StationID, to point: PlanPoint, except: TrackPlatform, in world: GameWorld) -> TrackPlatform? {
        world.trackPlatforms(of: station)
            .filter { $0 != except }
            .min { Self.squaredDistance(middle(of: ($0.edge, $0.start, $0.end), in: world), point)
                < Self.squaredDistance(middle(of: ($1.edge, $1.start, $1.end), in: world), point) }
    }

    /// The side of `platform`'s track facing away from `other`'s track,
    /// at the platform's middle.
    private func side(of platform: TrackPlatform, awayFrom other: TrackPlatform, in world: GameWorld) -> PlatformTrackSide? {
        guard let geometry = world.trackGeometry(of: platform.edge) else { return nil }
        let here = geometry.location(at: (platform.start + platform.end) / 2)
        let there = middle(of: (other.edge, other.start, other.end), in: world)
        // Left of (dx, dy) is (dy, -dx): y grows south.
        let way = here.direction
        let toward = Double(there.x - here.position.x) * Double(way.dy) - Double(there.y - here.position.y) * Double(way.dx)
        return toward > 0 ? .right : .left
    }

    /// The edges of the track from the node at `start` to the node at
    /// `end` by way of the edge through `point`, through nodes the line
    /// runs straight on through; `nil` where it does not get there.
    private func stretchBetween(_ start: PlanPoint, _ end: PlanPoint, through point: PlanPoint, in world: GameWorld) -> [TrackEdgeID]? {
        guard let found = world.trackEdgePoint(near: point, within: WorldCoordinate.unitsPerMetre),
              let first = world.network.edge(found.edge) else { return nil }
        var edges = [first.id]
        var reached: Set<PlanPoint> = []
        for node in [first.from, first.to] {
            var nodeID = node, came = first.id
            for _ in 0..<64 {
                guard let current = world.network.node(nodeID) else { return nil }
                if current.position.plan == start || current.position.plan == end {
                    reached.insert(current.position.plan)
                    break
                }
                guard let into = current.end(of: came), into.exits.count == 1, let next = world.network.edge(into.exits[0]) else { return nil }
                edges.append(next.id)
                came = next.id
                nodeID = next.from == nodeID ? next.to : next.from
            }
        }
        return reached == [start, end] ? edges : nil
    }
}
