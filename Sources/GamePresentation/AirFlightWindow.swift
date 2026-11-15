import Foundation
import GameCore

// Decision 771 (AIR-A4): the flight window. The camera follows a company
// route's aircraft from its stand up to its cruise's start
// (``Map3DAircraft/cruiseHeight``); from there the window shows the rest
// of its flight over the 3D map, which stays behind it as it was: the sky,
// the aircraft, how far along its route it is and when it lands. Nothing
// of the ground is drawn while it is open (the design's §5.2, second part).
//
// When the route's other end is an airport of the map (a domestic route),
// the window closes a little before its aircraft touches down there and
// the camera follows the landing on to the stand (§5.2, third part). A
// destination abroad is another game (the B part of the design, not yet
// built), so its window says it has arrived and stays until closed.
//
// View state only: nothing here changes the world, the save or a golden
// value.

/// What the flight window shows, read through ``GameSession/airFlightWindow``.
public struct AirFlightWindow: Equatable, Sendable {
    /// The leg flown (its leaving end).
    public let leg: Map3DAircraft.Leg
    /// "Taipei Songshan Airport → Penghu".
    public var title: String
    /// The places at either end, as the window's line names them.
    public var fromText: String
    public var toText: String
    /// How far along its flight it is, 0 to 1.
    public var progress: Double
    /// "Lands at 14:35", "Landed at 14:35".
    public var arrivalText: String
    /// "About 25 minutes to go", "Arrived in Hong Kong".
    public var remainingText: String
    /// Whether it has reached its stand at the far end.
    public var arrived: Bool
    /// Whether the camera will follow its landing (the far end is on the
    /// map).
    public var landsOnMap: Bool
    /// "The camera follows its landing." for one landing on the map; "Hong
    /// Kong is a map of its own: open it from the map list." for one that
    /// has arrived in a city with a map; `nil` otherwise.
    public var noteText: String?
    /// Whether its sky is the night's: from 18:00 to 06:00.
    public var night: Bool
    public var runningSpeed: GameSpeed?
}

extension AirFlightWindow {
    /// The camera follows the landing on the map from this many game
    /// seconds before touchdown: the slowest type's approach is drawn
    /// from some 94 s out (``Map3DAircraft/seenFrom`` at 74 m/s).
    public static let landingLead = 90.0

    /// Leg `leg`'s window in `world` at its clock, or `nil` when its route
    /// is no longer the company's.
    static func make(_ leg: Map3DAircraft.Leg, in world: GameWorld, language: DisplayLanguage) -> AirFlightWindow? {
        guard let route = world.airRoute(id: leg.route), let home = world.airports.first(where: { $0.id == route.airport }) else { return nil }
        let far = route.farAirport.flatMap { id in world.airports.first { $0.id == id } }
        let english = home.destinations.first { $0.name == route.destination }?.englishName ?? route.destination
        let farName = far.map { language.text($0.englishName, $0.name) } ?? language.text(english, route.destination)
        let homeName = language.text(home.englishName, home.name)
        let (from, to) = leg.outbound ? (homeName, farName) : (farName, homeName)
        let now = Double(world.clock.now.seconds)
        let leaves = Double(leg.departure * 60), lands = Double((leg.departure + route.flightMinutes) * 60)
        let progress = min(1, max(0, (now - leaves) / max(1, lands - leaves)))
        let arrived = now >= lands
        let clock = clockText(minuteOfDay: Int((leg.departure + route.flightMinutes) % GameTime.minutesPerDay))
        let left = Int(((lands - now) / 60).rounded(.up))
        let remaining = arrived
            ? language.text("Arrived at \(to)", "已抵達\(to)")
            : left <= 1 ? language.text("Landing in a minute", "就要降落了") : language.text("About \(left) minutes to go", "還要約 \(left) 分鐘")
        let toOnMap = leg.outbound ? far != nil : true
        // A city with a map of its own (Hong Kong), not one of a place
        // abroad no map has, nor of an airport of Taiwan off a city's map.
        let isCity = leg.outbound && OverseasMap.allCases.contains { $0.destinationName == route.destination }
        let hour = (world.clock.now.seconds % GameTime.secondsPerDay + GameTime.secondsPerDay) % GameTime.secondsPerDay / GameTime.secondsPerHour
        return AirFlightWindow(leg: leg, title: language.text("\(home.englishName) → \(english)", "\(home.name) → \(route.destination)"),
                               fromText: from, toText: to, progress: progress,
                               arrivalText: arrived ? language.text("Landed at \(clock)", "\(clock) 到達") : language.text("Lands at \(clock)", "預計 \(clock) 到達"),
                               remainingText: remaining, arrived: arrived, landsOnMap: toOnMap,
                               noteText: toOnMap ? language.text("The camera follows its landing.", "降落時鏡頭會接著跟。")
                                   : arrived && isCity ? language.text("\(to) is a map of its own: open it from the map list.", "\(to)是另一張地圖，從選地圖進入。") : nil,
                               night: hour < 6 || hour >= 18,
                               runningSpeed: world.clock.isPaused ? nil : world.clock.speed)
    }

    /// Where the leg lands, as the 3D map names its flight: the airport
    /// of the map at its far end; `nil` for a place abroad.
    static func landing(of leg: Map3DAircraft.Leg, in world: GameWorld) -> Map3DAircraft.FlightID? {
        guard let route = world.airRoute(id: leg.route) else { return nil }
        let at = leg.outbound ? route.farAirport : route.airport
        guard let at, let index = world.airports.firstIndex(where: { $0.id == at }) else { return nil }
        return Map3DAircraft.FlightID(leg: Map3DAircraft.Leg(route: leg.route, departure: leg.departure, outbound: leg.outbound, airport: index),
                                      landing: true)
    }

    /// The game second leg `leg` touches down at its far end.
    static func touchdown(of leg: Map3DAircraft.Leg, in world: GameWorld) -> Double? {
        world.airRoute(id: leg.route).map { Double((leg.departure + $0.flightMinutes - Map3DAircraft.taxiMinutes) * 60) }
    }
}

extension GameSession {
    /// The flight window's close button (and the 3D map closing): the
    /// camera stays where it let the aircraft go.
    public func closeAirFlightWindow() {
        airFlightWindow = nil
    }

    /// The 3D map lost the aircraft followed: a company route's that has
    /// climbed to its cruise's start (or out over the map's edge) opens
    /// the flight window.
    func openAirFlightWindow(after state: Map3DAircraft.State) {
        guard let leg = state.flight.leg, !state.flight.landing, state.phase == .climb else { return }
        airFlightWindow = AirFlightWindow.make(leg, in: world, language: language)
    }

    /// After a step: the window kept up to date; close to touchdown on the
    /// map, the camera follows the landing in its place.
    func keepAirFlightWindow() {
        guard let window = airFlightWindow else { return }
        guard let made = AirFlightWindow.make(window.leg, in: world, language: language) else {
            airFlightWindow = nil
            return
        }
        if made.landsOnMap, let touchdown = AirFlightWindow.touchdown(of: window.leg, in: world),
           Double(world.clock.now.seconds) >= touchdown - AirFlightWindow.landingLead,
           let landing = AirFlightWindow.landing(of: window.leg, in: world),
           let route = world.airRoute(id: window.leg.route) {
            airFlightWindow = nil
            followAircraft(Map3DAircraft.State(flight: landing, kind: Map3DAircraft.kind(of: route.size), phase: .approach,
                                               airport: landing.leg?.airport))
            return
        }
        if made != window { airFlightWindow = made }
    }
}
