import Foundation
import GameCore

// Decision 706: the coach stops of a real-world map. The app bundles
// Taiwan's coach network (`Resources/RealCoaches/coach_network.json`, which
// `tools/real-coaches/build_coach_network.py` writes from the real routes'
// file): the hubs where the real freeway and highway coaches call, with the
// direct coaches from each to the others. A free game on a real-world map
// gets those inside its bounds, busiest first.

/// Taiwan's coach network (`coach_network.json`).
public struct CoachNetwork: Sendable, Equatable {
    public static let file = "coach_network.json"
    /// The file's version this reader knows.
    public static let schema = 1

    public struct Hub: Sendable, Equatable {
        public let name: String
        public let coordinate: RealRailways.Coordinate
        /// The coaches that call on a Wednesday.
        public let coaches: Int64
        /// The coach loads that board and alight here on a Wednesday, in
        /// hundredths of a coach.
        public let boarding: Int64
        public let alighting: Int64
        /// The coaches that call in each hour, hour 0 first.
        public let hours: [Int64]
        /// The direct coaches to other hubs: the hub's index, the coaches
        /// of a Wednesday, the minutes and the fare.
        public let links: [(to: Int, coaches: Int64, minutes: Int64, fare: Int64)]

        public static func == (lhs: Hub, rhs: Hub) -> Bool {
            lhs.name == rhs.name && lhs.coordinate == rhs.coordinate && lhs.coaches == rhs.coaches && lhs.boarding == rhs.boarding
                && lhs.alighting == rhs.alighting && lhs.hours == rhs.hours && lhs.links.elementsEqual(rhs.links, by: ==)
        }
    }

    public let hubs: [Hub]

    /// Reads the file. Throws for another schema or a hub out of shape:
    /// no coaches, hours that are not 24 or all empty, links that are not
    /// four numbers each or lead to no hub.
    public init(data: Data) throws {
        struct File: Decodable {
            struct Hub: Decodable {
                let name: String
                let x: Int
                let y: Int
                let coaches: Int64
                let boarding: Int64
                let alighting: Int64
                let hours: [Int64]
                let links: [Int64]?
            }
            let schema: Int
            let scale: Int
            let hubs: [Hub]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == Self.schema else { throw RealBusError.schema(file.schema) }
        guard file.scale > 0 else { throw RealBusError.malformed("the scale is \(file.scale)") }
        let scale = 1 / Double(file.scale)
        hubs = try file.hubs.map { hub in
            let flat = hub.links ?? []
            guard !hub.name.isEmpty, hub.coaches > 0, hub.boarding >= 0, hub.alighting >= 0, hub.hours.count == 24,
                  hub.hours.allSatisfy({ $0 >= 0 }), hub.hours.contains(where: { $0 > 0 }), flat.count.isMultiple(of: 4) else {
                throw RealBusError.malformed("hub \(hub.name)")
            }
            let links = try stride(from: 0, to: flat.count, by: 4).map { index -> (to: Int, coaches: Int64, minutes: Int64, fare: Int64) in
                guard (0 ..< Int64(file.hubs.count)).contains(flat[index]), flat[index + 1] > 0, flat[index + 2] > 0, flat[index + 3] > 0 else {
                    throw RealBusError.malformed("hub \(hub.name): a link")
                }
                return (Int(flat[index]), flat[index + 1], flat[index + 2], flat[index + 3])
            }
            return Hub(name: hub.name, coordinate: RealRailways.Coordinate(latitude: Double(hub.y) * scale, longitude: Double(hub.x) * scale),
                       coaches: hub.coaches, boarding: hub.boarding, alighting: hub.alighting, hours: hub.hours, links: links)
        }
    }
}

public enum CoachCatalog {
    /// The coach stops that lie inside a world of `bounds` laid over the
    /// Earth as `frame` says: the busiest ``CoachRules/maximumStops`` by
    /// coaches (ties in the file's order), in the file's order, each with
    /// its busiest ``CoachRules/maximumLinks`` links to the others kept.
    /// A stop's passengers are its coach loads at
    /// ``CoachRules/passengersPerCoach`` a coach.
    public static func stops(of network: CoachNetwork, in frame: RealWorldFrame, bounds: WorldBounds) -> [CoachStop] {
        var inside: [(hub: Int, point: PlanPoint)] = []
        for (index, hub) in network.hubs.enumerated() {
            let position = frame.worldPosition(latitude: hub.coordinate.latitude, longitude: hub.coordinate.longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height),
                  (hub.boarding + hub.alighting) * CoachRules.passengersPerCoach >= 100 else { continue }
            inside.append((index, PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))))
        }
        if inside.count > CoachRules.maximumStops {
            let busiest = inside.sorted {
                let a = network.hubs[$0.hub].coaches, b = network.hubs[$1.hub].coaches
                return a != b ? a > b : $0.hub < $1.hub
            }.prefix(CoachRules.maximumStops).map(\.hub)
            let kept = Set(busiest)
            inside.removeAll { !kept.contains($0.hub) }
        }
        var number: [Int: Int] = [:]
        for (index, entry) in inside.enumerated() { number[entry.hub] = index + 1 }
        return inside.enumerated().map { index, entry in
            let hub = network.hubs[entry.hub]
            let links = hub.links.filter { number[$0.to] != nil }
                .sorted { $0.coaches != $1.coaches ? $0.coaches > $1.coaches : $0.to < $1.to }
                .prefix(CoachRules.maximumLinks)
                .map { CoachLink(to: number[$0.to]!, dailyCoaches: $0.coaches, minutes: $0.minutes, fare: $0.fare) }
                .sorted { $0.to < $1.to }
            return CoachStop(id: index + 1, name: hub.name, point: entry.point, dailyCoaches: hub.coaches,
                             dailyPassengers: (hub.boarding + hub.alighting) * CoachRules.passengersPerCoach / 100,
                             hours: hub.hours, links: links)
        }
    }

    /// `world` with the coach stops of its map, when it is a free game on a
    /// real-world map (as ``AirportCatalog/withAirports(_:)``): one saved
    /// before there were coaches gets them, and one whose stops are an
    /// earlier file's gets today's, each stop it had keeping yesterday's
    /// counts. Any other world is returned as it is.
    public static func withCoachStops(_ world: GameWorld, network: CoachNetwork) -> GameWorld {
        guard world.tourism != nil, world.scenario == nil, let frame = RealWorldFrame(world: world) else { return world }
        var world = world
        world.setCoachStops(stops(of: network, in: frame, bounds: world.bounds))
        return world
    }
}

extension CoachDay {
    /// The coach stop's day in a sentence: its coaches and passengers, and
    /// how many ride the company's trains.
    public func summary(in language: DisplayLanguage) -> String {
        if isClosed {
            return language.text("No coaches today because of the typhoon.", "今天因颱風，客運停駛。")
        }
        let today = language.text(
            "\(coaches.groupedText) coaches call today, with \(passengers.groupedText) passengers getting on and off.",
            "今天 \(coaches.groupedText) 班客運停靠，\(passengers.groupedText) 人上下車。"
        )
        guard riders > 0 else {
            return today + language.text(
                " None of them ride your trains yet: this station needs a line to stations where people live.",
                "還沒有人轉搭你的車：這一站要有路線通到有人住的車站。"
            )
        }
        return today + language.text(
            " \(ridersFrom.groupedText) of them go on by your trains and \(ridersTo.groupedText) come by your trains to catch a coach.",
            "其中 \(ridersFrom.groupedText) 人下車後轉搭你的列車，\(ridersTo.groupedText) 人搭你的列車來轉客運。"
        )
    }
}

extension CoachStop {
    /// The day that last ended, or `nil` before one has.
    public func yesterdayText(in language: DisplayLanguage) -> String? {
        guard yesterdayPassengers > 0 else { return nil }
        return language.text(
            "Yesterday: \(yesterdayPassengers.groupedText) coach passengers, \(yesterdayRiders.groupedText) of them on your trains.",
            "昨天：\(yesterdayPassengers.groupedText) 人搭客運，其中 \(yesterdayRiders.groupedText) 人搭了你的列車。"
        )
    }
}
