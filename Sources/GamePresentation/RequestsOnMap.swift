import GameCore

// The city's requests on the map (ARCHITECTURE decision 246, a player's
// report: the requests that ask for something on the map had no guide to
// where it was, so they were hard to keep track of). Each request in hand
// has a pin where it points; "Show on map" moves the camera there and
// rings the place (a new station's 800 m), with a card saying what it
// asks and how far it has come. The status bar counts the requests in
// hand, one tap from the list. All of it is read from the world; only
// which request is pointed out is kept, and never saved.

/// A request's pin on the map.
public struct CityRequestMark: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Where it points (``GameWorld/location(of:)``).
    public let location: PlanPoint
    /// The ring round a place for a new station: the 800 m a station
    /// there must stand within (``Land/catchmentRadius``); `nil` for a
    /// request that points at a station or a sight.
    public let radius: Int64?
    /// Whether it is the one ``GameSession/showRequestOnMap(_:)`` pointed
    /// out.
    public let isFocused: Bool

    public init(id: Int, location: PlanPoint, radius: Int64?, isFocused: Bool) {
        self.id = id
        self.location = location
        self.radius = radius
        self.isFocused = isFocused
    }
}

extension GameSession {
    /// The requests in hand that point somewhere, and the one pointed out
    /// (an offer too), for the map's pins.
    public var cityRequestMarks: [CityRequestMark] {
        guard let requests = world.cityRequests else { return [] }
        var shown = requests.active
        if let id = focusedRequestID, !shown.contains(where: { $0.id == id }), let offer = requests.offers.first(where: { $0.id == id }) {
            shown.append(offer)
        }
        return shown.compactMap { request in
            world.location(of: request).map { location in
                CityRequestMark(
                    id: request.id, location: location, radius: request.kind == .newStation ? Land.catchmentRadius : nil,
                    isFocused: request.id == focusedRequestID
                )
            }
        }
    }

    /// The request pointed out, as the goals panel lists it, while it is
    /// still in hand or on offer: the map's card.
    public var focusedRequest: CityRequestRow? {
        guard let id = focusedRequestID else { return nil }
        return world.cityRequestRows(in: language, placeNames: placeNames).first { $0.id == id && $0.location != nil }
    }

    /// The number of requests in hand, for the status bar's button; `nil`
    /// in a game without the city's requests.
    public var cityRequestsInHand: Int? {
        world.cityRequests.map(\.active.count)
    }

    /// Whether the city has offers waiting that the company has room to
    /// take on: the status bar's button says so.
    public var hasCityRequestOffers: Bool {
        guard let requests = world.cityRequests else { return false }
        return !requests.offers.isEmpty && requests.active.count < requests.capacity
    }

    /// The status bar's button, for VoiceOver: "City requests, 2 in hand,
    /// new offers".
    public var cityRequestsButtonValue: String {
        let count = cityRequestsInHand ?? 0
        let held = language.text("\(count) in hand", "進行中 \(count) 件")
        return hasCityRequestOffers ? held + language.text(", new offers", "，有新委託") : held
    }

    /// Points out request `id` on the map: the camera goes to where it
    /// points, which is ringed, with its card. Nothing for a request that
    /// points nowhere (the whole network) or is gone.
    public func showRequestOnMap(_ id: Int) {
        guard let request = world.cityRequest(id: id), let location = world.location(of: request) else { return }
        focusedRequestID = id
        lookAt(location)
    }

    /// Takes the ring and the card away.
    public func clearRequestFocus() {
        focusedRequestID = nil
    }
}
