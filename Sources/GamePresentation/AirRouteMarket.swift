import Foundation
import GameCore

// Decision 759 (A2 of docs/research/AIR_ROUTE_ACQUISITION_DESIGN_2026-11-15.md):
// the air routes for sale, the card of a route bought and the routes on the
// 2D map, over decision 758's GameCore routes.
//
// Every named destination of every airport of the map (decision 700) is a
// route for sale, except a rest ("others"). One between two airports of
// the map is listed once, from the airport listed first, since GameCore
// sells it once either way. A destination the map holds is flown to its
// airport (GameCore measures the straight line between them); one outside
// the map is flown the great-circle distance between the two airports' real
// places (``AirportCatalog/coordinate(ofDestination:)``). What a route
// costs and runs is GameCore's own offer (``GameWorld/airRouteOffer``);
// the panel adds an average day's estimate of each aircraft size, which
// reads the same rules GameCore settles a day by
// (``GameWorld/settleAirRoutes``), on the destination's average day rather
// than the day's own.

/// A route an airport flies that the company can buy (decision 759).
public struct AirRouteListing: Hashable, Sendable, Identifiable {
    public let airport: Int
    public let airportName: String
    public let airportEnglishName: String
    public let destination: AirDestination
    /// The map's airport the destination is, or `nil` for a place outside
    /// the map.
    public let farAirport: Int?
    /// The flight's length for a place outside the map; `nil` when GameCore
    /// measures it between the two airports.
    public let metres: Int64?
    /// The company's route, when it already flies this one (either way).
    public let bought: AirRouteID?

    public var id: String { "\(airport)|\(destination.name)" }

    /// "Taipei Songshan Airport → Penghu".
    public func title(in language: DisplayLanguage) -> String {
        language.text("\(airportEnglishName) → \(destination.englishName)", "\(airportName) → \(destination.name)")
    }
}

/// What a route would earn on an average day flown by one aircraft size.
public struct AirRouteEstimate: Hashable, Sendable {
    public let size: AircraftSize
    /// GameCore's offer, or `nil` when the size cannot fly the route (it
    /// would need more aircraft than a route keeps).
    public let offer: AirRouteOffer?
    /// The passengers of an average day, both ways, as many as the seats
    /// hold.
    public let passengers: Int64
    /// Fares less the aircraft's upkeep, kilometres and landings.
    public let dailyNet: Money

    /// The days the price takes to earn back, rounded up; `nil` when the
    /// route loses money.
    public var paybackDays: Int64? {
        guard let offer, dailyNet > .zero else { return nil }
        return (offer.price.amount + dailyNet.amount - 1) / dailyNet.amount
    }
}

/// An air route's card (decision 759): its rows and its settings.
public struct AirRouteCard: Hashable, Sendable, Identifiable {
    public let id: AirRouteID
    public let title: String
    public let rows: [String]
    public let frequency: AirRouteFrequency
    public let size: AircraftSize
    /// Whether it flew on its last day counted (a typhoon grounds it).
    public let flies: Bool
}

/// The company's air routes on the 2D map (decision 759): a dashed line
/// between the two airports, or from the airport to the map's edge toward
/// a place outside the map, with an arrow and the place's name there.
public struct AirRouteMapOverlay: Hashable, Sendable {
    public struct Route: Hashable, Sendable {
        public let id: AirRouteID
        public let from: PlanPoint
        public let to: PlanPoint
        /// The place's name at the map's edge; `nil` between two airports.
        public let edgeLabel: String?
        public let flies: Bool
    }

    public var routes: [Route] = []
}

extension AircraftSize {
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .commuter: language.text("19-seat commuter", "十九座小飛機")
        case .regional: language.text("70-seat turboprop", "七十座螺旋槳")
        case .narrowBody: language.text("Narrow-body jet", "窄體客機")
        case .wideBody: language.text("Wide-body jet", "廣體客機")
        }
    }
}

extension AirRouteFrequency {
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .reduced: language.text("Fewer", "減班")
        case .real: language.text("As real", "照真實")
        case .extra: language.text("More", "加班")
        }
    }
}

extension AirportCatalog {
    /// Where the destinations that are no airport of the catalogue lie
    /// (latitude, longitude, degrees): each one's main airport, from its
    /// published aerodrome reference point. Bangkok is Suvarnabhumi,
    /// Osaka Kansai.
    static let destinationPoints: [String: (latitude: Double, longitude: Double)] = [
        "knh": (24.4279, 118.3592), "lzn": (26.1598, 119.9582), "mfk": (26.2242, 120.0028), "wot": (23.3674, 119.5025),
        "nrt": (35.7647, 140.3864), "hnd": (35.5494, 139.7798), "osa": (34.4347, 135.2440), "icn": (37.4602, 126.4407),
        "gmp": (37.5583, 126.7906), "bkk": (13.6900, 100.7501), "sin": (1.3644, 103.9915), "mnl": (14.5086, 121.0198),
        "oka": (26.1958, 127.6459), "mfm": (22.1496, 113.5915), "sgn": (10.8188, 106.6519), "sha": (31.1979, 121.3363),
    ]

    /// The catalogue's place a destination's key is: Taoyuan's second
    /// terminal for Taoyuan.
    private static func place(ofKey key: String) -> Place? {
        let wanted = key == "tpe" ? "tpe2" : key
        return (places + overseasPlaces).first { $0.key == wanted }
    }

    private static func key(ofDestination name: String) -> String? {
        destinations.first { $0.value.chinese == name }?.key
    }

    /// The airport of the catalogue named `name` (``Airport/name``).
    static func place(named name: String) -> Place? {
        (places + overseasPlaces).first { $0.chinese == name }
    }

    /// Where the destination named `name` (``AirDestination/name``) lies.
    public static func coordinate(ofDestination name: String) -> (latitude: Double, longitude: Double)? {
        guard let key = key(ofDestination: name) else { return nil }
        if let place = place(ofKey: key) { return (place.latitude, place.longitude) }
        return destinationPoints[key]
    }

    /// The name the catalogue's airport `name` is a destination by:
    /// "臺北松山機場" is "臺北", both Taoyuan terminals "臺北桃園".
    static func destinationName(ofAirport name: String) -> String? {
        guard let place = place(named: name) else { return nil }
        let key = place.key.hasPrefix("tpe") ? "tpe" : place.key
        return destinations[key]?.chinese
    }

    /// The great-circle distance between two places, in whole metres.
    static func metres(from a: (latitude: Double, longitude: Double), to b: (latitude: Double, longitude: Double)) -> Int64 {
        let radians = Double.pi / 180
        let dLatitude = (b.latitude - a.latitude) * radians, dLongitude = (b.longitude - a.longitude) * radians
        let h = sin(dLatitude / 2) * sin(dLatitude / 2)
            + cos(a.latitude * radians) * cos(b.latitude * radians) * sin(dLongitude / 2) * sin(dLongitude / 2)
        return Int64((2 * 6_371_000 * asin(min(1, h.squareRoot()))).rounded())
    }
}

extension AirRouteMarket {
    /// The routes for sale in `world`, by airport and then in each
    /// airport's order of destinations.
    public static func listings(in world: GameWorld) -> [AirRouteListing] {
        let airports = world.airports
        var byDestinationName: [String: Airport] = [:]
        for airport in airports {
            if let name = AirportCatalog.destinationName(ofAirport: airport.name), byDestinationName[name] == nil {
                byDestinationName[name] = airport
            }
        }
        var list: [AirRouteListing] = []
        for airport in airports {
            let home = AirportCatalog.destinationName(ofAirport: airport.name)
            for destination in airport.destinations where !destination.isRest {
                let far = byDestinationName[destination.name].flatMap { $0.id == airport.id ? nil : $0 }
                // Listed once between two airports of the map: from the
                // first of them that lists the other.
                if let far, far.id < airport.id, let home, far.destinations.contains(where: { $0.name == home }) { continue }
                var metres: Int64?
                if far == nil {
                    guard let from = AirportCatalog.place(named: airport.name).map({ (latitude: $0.latitude, longitude: $0.longitude) }),
                          let to = AirportCatalog.coordinate(ofDestination: destination.name)
                    else { continue }
                    metres = max(1, AirportCatalog.metres(from: from, to: to))
                }
                let bought = world.airRoutes.first { route in
                    (route.airport == airport.id && route.destination == destination.name)
                        || (far != nil && route.airport == far?.id && route.farAirport == airport.id)
                }
                list.append(AirRouteListing(
                    airport: airport.id, airportName: airport.name, airportEnglishName: airport.englishName, destination: destination,
                    farAirport: far?.id, metres: metres, bought: bought?.id
                ))
            }
        }
        return list
    }

    /// What `offer` earns on an average day: its passengers at the
    /// frequency's share, as many as its seats hold, at its fare, less
    /// its aircraft's upkeep and its flights' kilometres and landings.
    public static func estimate(_ offer: AirRouteOffer) -> (passengers: Int64, dailyNet: Money) {
        let route = offer.route
        let passengers = min(route.dailySeats, offer.dailyPassengers * route.frequency.passengerShare / 1_000)
        let flights = 2 * route.departures
        let net = passengers * route.fare.amount - Int64(route.aircraft) * route.size.dailyUpkeep.amount
            - flights * (route.flightCost.amount + route.size.landingFee.amount)
        return (passengers, Money(net))
    }

    /// Each aircraft size's offer and average day for `listing` in `world`.
    public static func estimates(_ listing: AirRouteListing, frequency: AirRouteFrequency, in world: GameWorld) -> [AirRouteEstimate] {
        AircraftSize.allCases.map { size in
            let offer = try? world.airRouteOffer(from: listing.airport, to: listing.destination.name, farAirport: listing.farAirport,
                                                 metres: listing.metres, size: size, frequency: frequency)
            guard let offer else { return AirRouteEstimate(size: size, offer: nil, passengers: 0, dailyNet: .zero) }
            let (passengers, net) = estimate(offer)
            return AirRouteEstimate(size: size, offer: offer, passengers: passengers, dailyNet: net)
        }
    }

    /// The size the panel picks first: the one that earns most on an
    /// average day; the smaller of two that earn the same.
    public static func suggestedSize(_ estimates: [AirRouteEstimate]) -> AircraftSize {
        estimates.filter { $0.offer != nil }.max { a, b in
            a.dailyNet != b.dailyNet ? a.dailyNet < b.dailyNet : a.size.seats > b.size.seats
        }?.size ?? .narrowBody
    }
}

/// The air routes the company can buy and the cards of those it flies
/// (decision 759).
public enum AirRouteMarket {}

extension GameSession {
    /// ``AirRouteMarket/listings(in:)`` of the world.
    public var airRouteListings: [AirRouteListing] {
        AirRouteMarket.listings(in: world)
    }

    /// Whether the map has airports, so the lines panel shows its air
    /// routes' page.
    public var showsAirRoutes: Bool {
        !world.airports.isEmpty || !world.airRoutes.isEmpty
    }

    public func airRouteEstimates(_ listing: AirRouteListing, frequency: AirRouteFrequency) -> [AirRouteEstimate] {
        AirRouteMarket.estimates(listing, frequency: frequency, in: world)
    }

    /// Buys `listing`'s route flown by `size` at `frequency`. Returns
    /// whether it did.
    @discardableResult
    public func buyAirRoute(_ listing: AirRouteListing, size: AircraftSize, frequency: AirRouteFrequency) -> Bool {
        let edit = PlayerCommand.Edit.buyAirRoute(airport: listing.airport, destination: listing.destination.name, farAirport: listing.farAirport,
                                                  metres: listing.metres, size: size, frequency: frequency)
        let language = language
        let bought = perform(edit) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            return language.text("\(listing.title(in: .english)) now flies, for \(price.moneyText).",
                                 "\(listing.title(in: .traditionalChinese)) 開航了，花費 \(price.moneyText)。")
        } != nil
        // Decision 763: a route to a closed map's airport opens it.
        if bought { onAirRouteBought?() }
        return bought
    }

    /// What buying `listing` opens besides (decision 763), for its offer:
    /// the map of a city its destination is, while that map is closed.
    public func airRouteOpensMapText(_ listing: AirRouteListing) -> String? {
        airRoutes.opensByBuying(listing.destination.name, in: language)
    }

    /// What changing route `id` to `frequency` or to `size` would cost:
    /// the aircraft it would buy (all new ones for another size, the ones
    /// more for more flights); `nil` when GameCore would refuse it. Worked
    /// out from the offer of the same route, flown so, on a copy of the
    /// world without it.
    public func airRouteChangePrice(_ id: AirRouteID, frequency: AirRouteFrequency? = nil, size: AircraftSize? = nil) -> Money? {
        guard let route = world.airRoute(id: id) else { return nil }
        var copy = world
        let size = size ?? route.size, frequency = frequency ?? route.frequency
        guard (try? copy.sellAirRoute(id)) != nil,
              let offer = try? copy.airRouteOffer(from: route.airport, to: route.destination, farAirport: route.farAirport,
                                                  metres: route.metres, size: size, frequency: frequency)
        else { return nil }
        let bought = size == route.size ? max(0, offer.route.aircraft - route.aircraft) : offer.route.aircraft
        return Money(size.price.amount * Int64(bought))
    }

    public func setAirRouteFrequency(_ id: AirRouteID, to frequency: AirRouteFrequency) {
        let language = language
        perform(.setAirRouteFrequency(id, frequency)) { _, _, after in
            let departures = after.airRoute(id: id)?.departures ?? 0
            return language.text("Now \(departures) flights each way a day.", "現在每天來回各 \(departures) 班。")
        }
    }

    public func setAirRouteSize(_ id: AirRouteID, to size: AircraftSize) {
        let language = language
        perform(.setAirRouteSize(id, size)) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            return language.text("Now flown by \(size.name(in: .english).lowercased()) aircraft, for \(price.moneyText).",
                                 "改用\(size.name(in: .traditionalChinese))，花費 \(price.moneyText)。")
        }
    }

    /// Sells route `id`: nothing is paid back.
    public func sellAirRoute(_ id: AirRouteID) {
        let language = language
        perform(.sellAirRoute(id)) { _, _, _ in
            language.text("The air route is sold.", "航線賣掉了。")
        }
    }

    /// The route's title: its airport and its destination.
    func airRouteTitle(_ route: GameCore.AirRoute) -> String {
        guard let airport = world.airports.first(where: { $0.id == route.airport }) else { return route.destination }
        let english = airport.destinations.first { $0.name == route.destination }?.englishName ?? route.destination
        return language.text("\(airport.englishName) → \(english)", "\(airport.name) → \(route.destination)")
    }

    /// Route `id`'s card, or `nil`.
    public func airRouteCard(_ id: AirRouteID) -> AirRouteCard? {
        guard let route = world.airRoute(id: id) else { return nil }
        let km = max(1, (route.metres + 500) / 1_000)
        var rows: [String] = []
        rows.append(language.text(
            "\(route.departures) flights each way a day (\(route.realDepartures) in real life) · \(route.aircraft) × \(route.size.name(in: .english).lowercased())",
            "每天來回各 \(route.departures) 班（真實 \(route.realDepartures) 班）· \(route.aircraft) 架\(route.size.name(in: .traditionalChinese))"
        ))
        rows.append(language.text(
            "\(km.groupedText) km · \(route.flightMinutes) min a flight · \(route.fare.moneyText) a passenger · \(route.dailySeats.groupedText) seats a day",
            "\(km.groupedText) 公里 · 每班 \(route.flightMinutes) 分 · 每人 \(route.fare.moneyText) · 一天 \(route.dailySeats.groupedText) 個座位"
        ))
        if let last = route.days.last {
            let cost = last.running + last.landingFees
            rows.append(last.closed
                ? language.text("Yesterday: grounded by a typhoon · cost \(cost.moneyText)", "昨天：颱風停飛 · 成本 \(cost.moneyText)")
                : language.text(
                    "Yesterday: \(last.passengers.groupedText) passengers · fares \(last.fares.moneyText) · cost \(cost.moneyText)",
                    "昨天：乘客 \(last.passengers.groupedText) 人 · 票收 \(last.fares.moneyText) · 成本 \(cost.moneyText)"
                ))
        } else {
            rows.append(language.text("Its first day is counted at midnight.", "第一天的帳在午夜結算。"))
        }
        return AirRouteCard(id: id, title: airRouteTitle(route), rows: rows, frequency: route.frequency, size: route.size,
                            flies: route.days.last?.closed != true)
    }

    /// The company's routes on the 2D map, or `nil` when it flies none.
    public var airRouteMapOverlay: AirRouteMapOverlay? {
        guard !world.airRoutes.isEmpty else { return nil }
        let frame = RealWorldFrame(world: world)
        var overlay = AirRouteMapOverlay()
        for route in world.airRoutes {
            guard let origin = world.airports.first(where: { $0.id == route.airport }) else { continue }
            let flies = route.days.last?.closed != true
            if let farID = route.farAirport, let far = world.airports.first(where: { $0.id == farID }) {
                overlay.routes.append(.init(id: route.id, from: origin.point, to: far.point, edgeLabel: nil, flies: flies))
                continue
            }
            guard let frame, let place = AirportCatalog.coordinate(ofDestination: route.destination) else { continue }
            let target = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
            guard let edge = Self.edgePoint(from: origin.point, toward: target, in: world.bounds) else { continue }
            let english = origin.destinations.first { $0.name == route.destination }?.englishName ?? route.destination
            overlay.routes.append(.init(id: route.id, from: origin.point, to: edge, edgeLabel: language.text(english, route.destination), flies: flies))
        }
        return overlay.routes.isEmpty ? nil : overlay
    }

    /// Where the straight line from `start` toward `target` leaves the map
    /// of `bounds`; `nil` when `target` lies inside it.
    nonisolated static func edgePoint(from start: PlanPoint, toward target: (x: Double, y: Double), in bounds: WorldBounds) -> PlanPoint? {
        let (x0, y0) = (Double(start.x), Double(start.y))
        let (dx, dy) = (target.x - x0, target.y - y0)
        let (width, height) = (Double(bounds.width), Double(bounds.height))
        guard target.x < 0 || target.y < 0 || target.x > width || target.y > height else { return nil }
        var t = 1.0
        if dx < 0 { t = min(t, -x0 / dx) } else if dx > 0 { t = min(t, (width - x0) / dx) }
        if dy < 0 { t = min(t, -y0 / dy) } else if dy > 0 { t = min(t, (height - y0) / dy) }
        t = max(0, t)
        return PlanPoint(x: Int64((x0 + dx * t).rounded()), y: Int64((y0 + dy * t).rounded()))
    }
}
