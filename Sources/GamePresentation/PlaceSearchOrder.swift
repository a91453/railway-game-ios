/// Orders what a place search found by how each name meets what was typed
/// (2026-11-27: 小倉城, searched by name, was listed under other places
/// and had to be scrolled to): the name itself first, then the names it
/// starts, then the names it is in, then the rest, each in the order
/// found. Names are compared as the picker's list compares them
/// (``RealWorldPlace/searchKey(_:)``: case, accents, spaces and 臺/台
/// ignored).
public enum PlaceSearchOrder {
    /// How `name` meets `query` (both already ``RealWorldPlace/searchKey(_:)``
    /// keys): 0 the same, 1 starts with it, 2 has it, 3 neither.
    static func rank(_ name: String, _ query: String) -> Int {
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains(query) { return 2 }
        return 3
    }

    /// `places` by ``rank(_:_:)`` of their `name` against `query`, each rank
    /// in the given order; as given for an empty query.
    public static func ordered<Place>(_ places: [Place], query: String, name: (Place) -> String) -> [Place] {
        let key = RealWorldPlace.searchKey(query)
        guard !key.isEmpty else { return places }
        return places.enumerated()
            .map { (rank: rank(RealWorldPlace.searchKey(name($0.element)), key), offset: $0.offset, place: $0.element) }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.place)
    }
}
