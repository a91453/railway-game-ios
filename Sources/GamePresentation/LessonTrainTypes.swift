import GameCore

// Decision 374 (City Transport Manager study 4.11): in the lessons the train
// types open lesson by lesson, as the tools do (decision 266), and the
// showroom lists the ones still shut with the lesson that opens them, so a
// player sees what comes later. Every other game has them all. The types
// follow what the lessons teach: the city's metro cars from the first, the
// metro's others with the second train (lesson 3), the railway's everyday
// trains with the line between towns (lesson 4), the high-speed set with
// double track (lesson 5), the special ones with the service settings
// (lesson 6) and the sightseeing trains with the sights (lesson 9). All are
// open by lesson 10, after which "every tool is yours".

extension Lesson {
    /// The lesson from which `type` can be chosen in a lesson: 1 for the
    /// types open from the start.
    public static func number(unlocking type: TrainType) -> Int {
        switch type.family {
        case .metro:
            type.spec.offer == .referenceMain ? 1 : 3
        case .highSpeed:
            5
        case .special:
            6
        case .railway:
            type.isSightseeing ? 9 : 4
        }
    }

    /// Whether `type` can be chosen in this lesson.
    public func allows(_ type: TrainType) -> Bool {
        Self.number(unlocking: type) <= number
    }
}

extension GameWorld {
    /// The lesson that opens `type` in this game (decision 374), or `nil`
    /// when it is open: in a lesson, after the lesson played; in any other
    /// game, never.
    public func lessonUnlocking(_ type: TrainType) -> Int? {
        guard let lesson, !lesson.allows(type) else { return nil }
        return Lesson.number(unlocking: type)
    }

    /// The offered types that can be chosen now (decision 374): all of
    /// ``offeredTrainTypes`` but, in a lesson, those a later lesson opens.
    public var openTrainTypes: [TrainType] {
        offeredTrainTypes.filter { lessonUnlocking($0) == nil }
    }

    /// "Opens in lesson 6" for a type a later lesson opens, or `nil`.
    public func lessonUnlockText(for type: TrainType, in language: DisplayLanguage) -> String? {
        lessonUnlocking(type).map { language.text("Opens in lesson \($0)", "第 \($0) 關解鎖") }
    }
}
