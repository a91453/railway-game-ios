import GameCore

// Decision 374 (City Transport Manager study 4.12): beside the fare
// steppers, a line on how many riders the fare shown would keep, against
// the city's usual fare, before the player charges it. The share is
// GameCore's own (`FareRules.demandFactor`, decision 36): a flat fare's for
// every trip, distance steps' for the shortest and the longest. The rules
// charged now are given beside it, so the line says how the change moves
// demand; until the player sets fares, trips are not priced into demand,
// which the hint gives as 100 %. In free play fares change nothing, so no
// hint is made.

/// How many riders a fare keeps, as the economy panel says it.
public struct FareDemandHint: Equatable, Sendable {
    /// Riders kept, in thousandths of those at the city's usual fare: on
    /// the shortest trips and on the longest (the same for a flat fare).
    public struct Share: Equatable, Sendable {
        public let shortest: Int64
        public let longest: Int64

        /// The share `rules` keep in a city whose usual fare is `baseline`.
        public init(rules: FareRules, baseline: Money) {
            switch rules {
            case .flat(let fare):
                let share = FareRules.demandFactor(fare: fare, baseline: baseline)
                shortest = share
                longest = share
            case .distance(let bands):
                shortest = FareRules.demandFactor(fare: bands.first?.fare ?? .zero, baseline: baseline)
                longest = FareRules.demandFactor(fare: bands.last?.fare ?? .zero, baseline: baseline)
            }
        }

        public init(shortest: Int64, longest: Int64) {
            self.shortest = shortest
            self.longest = longest
        }

        /// Fares that do not change demand: the usual fare's riders.
        public static let unchanged = Share(shortest: 1_000, longest: 1_000)

        /// The two ends' mean, which the level reads.
        public var mean: Int64 {
            (shortest + longest) / 2
        }

        /// "54%", or "103%–81%" when the ends differ.
        public var percentText: String {
            let short = Self.percent(shortest), long = Self.percent(longest)
            return short == long ? "\(short)%" : "\(short)%–\(long)%"
        }

        /// Thousandths to whole percent, half up.
        static func percent(_ thousandths: Int64) -> Int64 {
            (thousandths + 5) / 10
        }
    }

    /// What the riders do, in a word.
    public enum Level: Equatable, Sendable {
        case more, usual, lower, veryLow

        /// The level of `share`'s mean: above 101% more, from 90% usual,
        /// from 50% lower, and very low under that.
        public init(_ share: Share) {
            switch share.mean {
            case 1_010...: self = .more
            case 900...: self = .usual
            case 500...: self = .lower
            default: self = .veryLow
            }
        }

        public func text(in language: DisplayLanguage) -> String {
            switch self {
            case .more: language.text("a few more riders", "乘客略多")
            case .usual: language.text("normal", "大致正常")
            case .lower: language.text("fewer riders", "偏低")
            case .veryLow: language.text("very few riders", "很低")
            }
        }
    }

    /// The fare shown on the stepper.
    public let proposed: Share
    /// The rules charged now.
    public let current: Share

    public init(proposed: Share, current: Share) {
        self.proposed = proposed
        self.current = current
    }

    public var level: Level {
        Level(proposed)
    }

    /// Whether the line should warn: fewer riders than now, and under the
    /// usual level.
    public var isWarning: Bool {
        proposed.mean < current.mean && level != .usual && level != .more
    }

    /// "Demand: fewer riders, about 54% of those at the usual fare (now
    /// 100%)."
    public func text(in language: DisplayLanguage) -> String {
        let level = level.text(in: language)
        if proposed.shortest == proposed.longest {
            return language.text(
                "Demand: \(level), about \(proposed.percentText) of the riders at the usual fare (now \(current.percentText)).",
                "需求：\(level)，約是一般票價時乘客的 \(proposed.percentText)（現在 \(current.percentText)）。"
            )
        }
        let short = "\(Share.percent(proposed.shortest))%", long = "\(Share.percent(proposed.longest))%"
        return language.text(
            "Demand: \(level), about \(short) of the riders at the usual fare on short trips and \(long) on the longest (now \(current.percentText)).",
            "需求：\(level)，短程約是一般票價時乘客的 \(short)，最遠的 \(long)（現在 \(current.percentText)）。"
        )
    }

    /// "Usual fare in this city: $0.75."
    public static func usualFareText(_ baseline: Money, in language: DisplayLanguage) -> String {
        language.text("Usual fare in this city: \(baseline.centsText).", "這座城市的一般票價：\(baseline.centsText)。")
    }
}

extension GameWorld {
    /// The hint for charging `rules` (decision 374), or `nil` unless the
    /// company is managed: in free play fares change no one's trip.
    public func fareDemandHint(for rules: FareRules) -> FareDemandHint? {
        guard accounts.mode == .management else { return nil }
        let baseline = accounts.fareBaseline
        let current = accounts.fareRules.map { FareDemandHint.Share(rules: $0, baseline: baseline) } ?? .unchanged
        return FareDemandHint(proposed: FareDemandHint.Share(rules: rules, baseline: baseline), current: current)
    }
}
