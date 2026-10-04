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

    /// The train's length, in world units: from its first car's centre
    /// to its last car's, ``carLength`` for each car after the first. 0 for
    /// a train of one car.
    public var length: Int64 {
        Int64(cars - 1) * Self.carLength
    }
}
