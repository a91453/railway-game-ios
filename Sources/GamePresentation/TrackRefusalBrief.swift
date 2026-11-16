import GameCore

// Decision 803, continued (BUILD-MODE-CLEAN-2; the owner, of the refused
// stretch's pill: "字不會太多嗎"): the map's ✕ ✓ pill says why a stretch is
// refused in one short line, with no figures and no conditions. The whole
// sentence (``NetworkPreview/problem``) stays where there is room to read
// it and for VoiceOver: the details card, the status banner, the pill's
// accessibility label. Each brief sits beside the sentence it stands for in
// decision 803's table; a refusal with no brief here is said whole.

extension GameError {
    /// The pill's one line for a stretch of track refused with this error,
    /// or `nil` for one that building track does not meet (said whole).
    public func trackBrief(in language: DisplayLanguage) -> String? {
        switch self {
        case .trackOverWater:
            language.text("Over water: bridge or tunnel", "要過水：用橋或走隧道")
        case .trackTooSteep:
            language.text("Too steep", "太陡了")
        case .structureTooHigh:
            language.text("Too high above the ground", "離地太高")
        case .invalidTrackStructure:
            language.text("That structure can't go at this height", "這個高度不能用這種結構")
        case .trackConflict:
            language.text("Crosses a track: go over, under, or join it", "撞到別的軌道：跨過、鑽過或接上")
        case .trackTooClose:
            language.text("Too close to the track beside it", "離旁邊的軌道太近")
        case .turnoutTooSteep:
            language.text("Too steep here to branch off", "這裡太陡，不能分岔")
        case .mapTileNotOwned:
            language.text("This land isn't yours yet", "這塊地還沒買")
        case .insufficientFunds:
            Self.shortOfCashBrief(in: language)
        case .invalidTrackGeometry:
            language.text("Track can't go here", "這裡不能鋪")
        case .groundNotLoaded:
            language.text("Still reading the ground here", "這裡的地面還在讀")
        case .trackReserved:
            language.text("A train is coming: wait for it", "有列車要過，等它通過")
        case .trackEdgeHasPlatform:
            language.text("A platform is in the way", "這裡有月台")
        case .buildingOnTrack, .buildingOnStation, .buildingOverlaps:
            language.text("A building is in the way", "這裡有建物擋著")
        case .unknownTrackNode:
            NetworkProblem.missingNode.brief(in: language)
        case .unknownTrackEdge:
            language.text("That track is gone", "這段軌道不見了")
        default:
            nil
        }
    }

    /// The pill's line for a build the cash does not cover: its ✓ says
    /// the price.
    public static func shortOfCashBrief(in language: DisplayLanguage) -> String {
        language.text("Not enough cash", "錢不夠")
    }

    /// ``trackBrief(in:)`` for `stretch`: for
    /// ``GameError/invalidTrackGeometry``, the check that refused it
    /// (decision 513), as ``playerMessage(building:in:heights:language:)``
    /// names it.
    func trackBrief(building stretch: PlayerCommand.TrackStretch, in world: GameWorld, heights: HeightGrid?, language: DisplayLanguage) -> String? {
        guard self == .invalidTrackGeometry, let problem = TrackGeometryProblem.of(stretch, in: world, heights: heights) else {
            return trackBrief(in: language)
        }
        return problem.brief(in: language)
    }
}

extension TrackGeometryProblem {
    /// The pill's one line (``text(in:)`` is the whole sentence).
    public func brief(in language: DisplayLanguage) -> String {
        switch self {
        case .tooHigh: language.text("One end is too high", "有一端太高")
        case .tooDeep: language.text("One end is too deep", "有一端太深")
        case .pointTaken: language.text("Track ends here: tap that end", "這裡已有軌道端點，改點它")
        case .geometry(let problem): problem.brief(in: language)
        }
    }
}

extension NetworkBuilding.GeometryProblem {
    /// The pill's one line (``text(in:)`` is the whole sentence).
    public func brief(in language: DisplayLanguage) -> String {
        switch self {
        case .sameSpot: language.text("Start and end are the same spot", "起點和終點在同一處")
        case .outsideMap: language.text("Runs off the map", "超出地圖")
        case .heightGap: language.text("The ends' heights are too far apart", "兩端高度差太大")
        case .tooBent: language.text("Too tight a bend: drag farther", "彎不過去：拖遠一點")
        }
    }
}

extension NetworkProblem {
    /// The pill's one line (``text(in:)`` is the whole sentence).
    func brief(in language: DisplayLanguage) -> String {
        switch self {
        case .geometry(let problem): problem.brief(in: language)
        case .missingNode: language.text("That end is gone: tap again", "端點不見了，重點一次")
        case .tooClose: language.text("The ends are too close", "兩端太近")
        case .tooSharp: language.text("Turns too sharply", "轉太急")
        case .steepTurnout: GameError.turnoutTooSteep.trackBrief(in: language) ?? text(in: language)
        case .turnoutOnVerticalCurve: language.text("Can't branch off where the slope changes", "坡度變化的地方不能分岔")
        }
    }
}

extension ScissorsProblem {
    /// The pill's one line (``text(in:)`` is the whole sentence).
    func brief(in language: DisplayLanguage) -> String {
        switch self {
        case .notLevel: language.text("The two tracks must be level", "兩條軌道要一樣高")
        case .notAcross: language.text("Tap two tracks side by side", "請點並行的兩條軌道")
        case .tooShort: language.text("Crossover too short", "渡線太短")
        case .nearANode: language.text("Too near a switch or a track end", "離道岔或軌道端點太近")
        case .tooSharp: language.text("The tracks curve too much here", "這裡的軌道彎太大")
        case .tooShallow: language.text("Crossover too long", "渡線太長")
        }
    }
}

extension GameSession {
    /// The pill's line for no room beside the stretch for a second track
    /// (``noParallelText(in:)`` is the whole sentence).
    static func noParallelBrief(in language: DisplayLanguage) -> String {
        language.text("No room for the second track", "旁邊放不下第二條軌道")
    }
}

extension NetworkHeightCard {
    /// The notes a height card says where it offers no fix, in the pill's
    /// one line and whole.
    enum Note {
        case looking, noneWorks, endsFixed

        func text(in language: DisplayLanguage) -> String {
            switch self {
            case .looking:
                language.text("Looking for a height that works…", "正在找可以鋪的高度…")
            case .noneWorks:
                language.text(
                    "No height of these ends gets through. Try a shorter stretch, or a point on each side of the water.",
                    "這兩端怎麼調高度都過不去。請把這段鋪短一點，或在水的兩岸各點一個點。"
                )
            case .endsFixed:
                language.text(
                    "Both ends are on track already, so their height cannot change. Tap a new point on each side and raise the stretch between them.",
                    "兩端都接在已有的軌道上，高度不能改。請在兩側各點一個新點，再調高中間那一段。"
                )
            }
        }

        func brief(in language: DisplayLanguage) -> String {
            switch self {
            case .looking: language.text("Finding a height…", "正在找高度…")
            case .noneWorks: language.text("No height works: try a shorter stretch", "調高度也過不去：鋪短一點")
            case .endsFixed: language.text("Both ends join track: heights can't change", "兩端都接著軌道，高度不能改")
            }
        }
    }
}
