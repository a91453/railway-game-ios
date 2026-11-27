import Foundation
import GameCore

// Decision 1035 (STREET-TEMPLE-VIADUCT-TRAM-RULES §3.3): a street dog and a
// few pigeons standing on some temples' squares and some stations'
// forecourts. Three temples in ten have a dog and four a flock of two to
// five pigeons, two stations in ten a dog and four a flock, each from the
// place's own seed, so the same square always has the same ones. Dogs in
// Taiwan only (its street dogs' look; Japan and Hong Kong have few loose
// on the street, Finland's map is under snow), pigeons everywhere but
// Finland. They stand still: the models have one pose, and standing is
// cheapest. Close up only, like the temples' other small pieces.

extension Map3DScene.Builder {
    /// The shares of temples and of station forecourts with a dog and with
    /// pigeons.
    static let templeDogShare: Float = 0.3
    static let templePigeonShare: Float = 0.4
    static let stationDogShare: Float = 0.2
    static let stationPigeonShare: Float = 0.4

    /// Whether this map's squares have dogs, and pigeons.
    var hasStreetDogs: Bool { look.streets == .taiwan }
    var hasPigeons: Bool { look.streets != .finland }

    /// Where on a temple of `size` (its front +x, its square's middle at
    /// the origin) the dog stands and the flock gathers, on the side
    /// `side` (+1 or −1, the flock across from the dog), and the ground
    /// the flock keeps to (x and |z| between). `nil` for a large temple,
    /// which takes none (decision 935's budget).
    static func templeAnimalSpots(_ size: RealTemples.Size, side: Float)
        -> (dog: Map3DPoint, flock: Map3DPoint, x: ClosedRange<Float>, z: ClosedRange<Float>)? {
        switch size {
        // Between the hall's platform (to 1 m) and the gate's pad (from
        // 5 m), clear of the Tiangong burner at 2 m.
        case .temple: (Map3DPoint(3.7, 0.12, side * 3.6), Map3DPoint(3.0, 0.12, -side * 4.4), 1.4...4.7, 2.8...7.4)
        // Before the side hall's platform (to 3 m) round the burner at
        // 4.5 m.
        case .small: (Map3DPoint(4.7, 0.12, side * 3.2), Map3DPoint(4.4, 0.12, -side * 3.4), 3.3...5.7, 1.9...5.1)
        case .large: nil
        }
    }

    /// The animals of one square from `seed`: a dog `dog` times in one,
    /// a flock `pigeons` times, built facing +x as `spots` are; an empty
    /// mesh for none.
    static func squareAnimals(seed: (Int32, Int32), dog: Float, pigeons: Float, dogs: Bool, birds: Bool,
                              spots: (dog: Map3DPoint, flock: Map3DPoint, x: ClosedRange<Float>, z: ClosedRange<Float>)) -> Map3DMesh {
        func r(_ salt: Int32) -> Float { map3DRandom(seed.0, seed.1, salt: salt) }
        var builder = StationKitBuilder()
        if dogs, r(1035) < dog, let model = Map3DTempleProp.streetDog.model {
            builder.add(model, at: spots.dog, angle: r(1036) * 2 * .pi)
        }
        if birds, r(1037) < pigeons, let model = Map3DTempleProp.pigeon.model {
            let count = 2 + Int(r(1038) * 4) // 2 to 5
            for bird in 0..<count {
                let salt = Int32(1040 + bird * 3)
                let angle = r(salt) * 2 * .pi, out = 0.3 + 1.0 * r(salt + 1)
                let x = min(max(spots.flock.x + cosf(angle) * out, spots.x.lowerBound), spots.x.upperBound)
                let z = spots.flock.z + sinf(angle) * out
                let across = min(max(abs(z), spots.z.lowerBound), spots.z.upperBound) * (z < 0 ? -1 : 1)
                builder.add(model, at: Map3DPoint(x, spots.flock.y, across), angle: r(salt + 2) * 2 * .pi)
            }
        }
        return builder.mesh
    }

    /// Decision 1035: the animals of a temple of `size` whose middle is
    /// `centre` (in the scene), built facing +x on its square's middle.
    func templeAnimals(_ size: RealTemples.Size, centre: Map3DPoint) -> Map3DMesh {
        let seed = lifeSeed(centre, salt: 1035)
        guard let spots = Self.templeAnimalSpots(size, side: map3DRandom(seed.0, seed.1, salt: 1039) < 0.5 ? -1 : 1) else { return Map3DMesh() }
        return Self.squareAnimals(seed: seed, dog: Self.templeDogShare, pigeons: Self.templePigeonShare, dogs: hasStreetDogs, birds: hasPigeons,
                                  spots: spots)
    }

    /// Decision 1035: on each station building's forecourt (decision 458's
    /// fronts), beyond its bushes, a dog and a flock on either side of
    /// the way in, each where no track, platform or road is near.
    mutating func addStationAnimals() {
        guard hasStreetDogs || hasPigeons else { return }
        let saved = target
        defer { target = saved }
        target = .close
        for front in state.stations.stationFronts {
            let seed = lifeSeed(front.centre, salt: 1036)
            let side: Float = map3DRandom(seed.0, seed.1, salt: 1039) < 0.5 ? -1 : 1
            let right = front.forward.cross(.up), entrance = front.centre + front.forward * (front.depth / 2 + 7)
            let out = max(front.wide / 4, 3)
            // Built facing +x on the forecourt's middle: the dog's spot and
            // the flock's either side of the way in.
            let spots = (dog: Map3DPoint(0, 0, side * out), flock: Map3DPoint(0, 0, -side * out), x: Float(-1.2)...1.2,
                         z: (out - 1.2)...(out + 1.2))
            let animals = Self.squareAnimals(seed: seed, dog: Self.stationDogShare, pigeons: Self.stationPigeonShare, dogs: hasStreetDogs,
                                             birds: hasPigeons, spots: spots)
            guard !animals.indices.isEmpty else { continue }
            // Each side's 3 m square clear, at the forecourt's ground.
            let clear = [out, -out].allSatisfy { across in
                let spot = entrance + right * across
                let footprint = [(-1.5, -1.5), (1.5, -1.5), (1.5, 1.5), (-1.5, 1.5)].map { spot + front.forward * Float($0.0) + right * Float($0.1) }
                return isClear(footprint, facing: front.forward)
            }
            guard clear else { continue }
            let foot = Map3DPoint(entrance.x, drawnGround(x: entrance.x, z: entrance.z) + 0.05, entrance.z)
            mesh(at: entrance) { $0.append(animals, at: foot, forward: front.forward) }
        }
    }
}
