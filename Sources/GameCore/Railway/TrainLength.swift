// Train length (Phase 4.5 Stage S2). A train's position is its head: the
// centre of its first car. Its cars stand ``Train/carLength`` apart, centre
// to centre, so a train of more than one car has a body behind its head
// lying over the track it came along. The body cannot be derived from the
// network where the track branches, so the edges it lies over are stored
// with the train (its trailEdges) and kept up by every command and step that
// moves the head. A train of one car (every train bought before Stage S2,
// and every new one) has no body. Until Stage F3c a train on the grid kept
// its body as the tiles behind it; that went with the grid (ARCHITECTURE
// decision 51).

extension Train {
    /// How far apart two cars' centres are, in world units: 1024, 16 m.
    /// A train's own measure since Stage S2 (it was a tile's width then;
    /// Stage F3d keeps the number and drops the tie).
    public static let carLength: Int64 = 1_024
    /// The fewest and the most cars a train may have.
    public static let minimumCars = 1
    public static let maximumCars = 16

    /// A standard car's length in a world with real car lengths
    /// (decision 227): 20 m, as the map has drawn each car since
    /// decision 205.
    public static let realStandardCarLength: Int64 = 1_280

    /// How far apart the cars of a train of `type` stand when it is bought
    /// or changes type (decision 227): its type's real length (a standard
    /// car's 20 m without a type) when `real`, otherwise ``carLength``.
    public static func carPitch(of type: TrainType?, real: Bool) -> Int64 {
        guard real else { return carLength }
        return type?.carLength ?? realStandardCarLength
    }

    /// Whether a train's cars may stand `pitch` apart: ``carLength``, the
    /// standard car's real length or one of the types' (decision 227).
    static func isCarPitch(_ pitch: Int64) -> Bool {
        pitch == carLength || pitch == realStandardCarLength || TrainType.allCases.contains { $0.carLength == pitch }
    }

    /// The train's length, in world units: from its first car's centre
    /// to its last car's, ``carPitch`` for each car after the first. 0 for
    /// a train of one car.
    public var length: Int64 {
        Int64(cars - 1) * carPitch
    }
}
