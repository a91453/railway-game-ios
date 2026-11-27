import Foundation

/// Decision 918: five more people the streets, platforms and bus stops
/// show close up, beside decision 787's commuter
/// (``Map3DCommuterFigure``): an office worker with a briefcase, a student
/// with a school bag, an elder with a cloth bag, someone under an umbrella
/// and a traveller pulling a suitcase, each standing and mid-stride.
///
/// Made with Meshy (AI-generated, the owner's plan) and rebuilt for the
/// game by the local studio (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/pedestrians-2026-11/revision-4`, #257;
/// lessons in `docs/studio/lessons/pedestrians.md`), each a closed body of
/// at most 360 triangles; written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): +x the way the
/// figure faces, +y its left, the middle of its feet at the origin.
///
/// Each figure close to the eye is one of the six, the same one every
/// frame (``kind(_:)``); farther, the block figure stands in as before.
///
/// Decision 1037: nine more from the studio's second batch
/// (`pedestrians-2a-2026-11`, `pedestrians-2b-2026-11`, each revision-2;
/// ``Map3DPedestrianBatch2``), and who stands where by the place, the
/// hour and the day (``kind(slot:at:clock:region:)``).
public enum Map3DPedestrian {
    /// The people besides the commuter: decision 918's five, then
    /// decision 1037's nine.
    public enum Kind: String, CaseIterable, Sendable {
        case office, student, elderly, umbrella, traveller
        case officeWoman = "office-woman", schoolboy, phone, tourist, worker
        case grandmaCart = "grandma-cart", motherStroller = "mother-stroller", jogger, delivery

        /// Decision 918's five, in the first batch's mesh.
        static let firstBatch: [Kind] = [.office, .student, .elderly, .umbrella, .traveller]
        /// Decision 1037's nine, in ``Map3DPedestrianBatch2``.
        static var secondBatch: [Kind] { allCases.filter { !firstBatch.contains($0) } }
        var isSecondBatch: Bool { !Self.firstBatch.contains(self) }
    }

    /// `kind`'s model's name in ``Map3DModelPack``, standing or mid-stride:
    /// its GLB's file name. The jogger has one, running.
    public static func name(_ kind: Kind, walking: Bool) -> String {
        kind == .jogger ? "ped-jogger-running" : "ped-\(kind.rawValue)-\(walking ? "walking" : "standing")"
    }

    /// The colour of each of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names skin, hair, shirt (alpha 0: the instance's colour, as the
    /// commuter's), trousers, dark (shoes, bags, the suitcase, a cap),
    /// white (the office worker's and the student's shirts), greyHair,
    /// bag (the elder's cloth bag) and umbrella. All the game's own.
    static let palette: [UInt32] = [
        Map3DStreetModel.skin, Map3DStreetModel.hair, Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF, Map3DStreetModel.trousers, Map3DStreetModel.tyre,
        Map3DPalette.sidewalk, Map3DPalette.tankSteel, Map3DPalette.terrazzo, Map3DPalette.tankBlue,
    ]

    /// The ten models, for ``Map3DModelPack``: after the bicycles and
    /// before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Kind.firstBatch.flatMap { kind in [false, true].compactMap { model(kind, walking: $0) } }
    }

    /// Decision 1037: the second batch's seventeen models (the jogger's
    /// one), after the bicycle parking and before the route bus, so that
    /// no model before them moves.
    static var secondDrawn: [Map3DModelPack.Model] {
        Kind.secondBatch.flatMap { kind in (kind == .jogger ? [false] : [false, true]).compactMap { model(kind, walking: $0) } }
    }

    /// Every model's name, the first batch's and the second's.
    static var names: [String] {
        Kind.allCases.flatMap { kind in (kind == .jogger ? [false] : [false, true]).map { name(kind, walking: $0) } }
    }

    /// `kind`'s model; `nil` if its mesh does not decode.
    public static func model(_ kind: Kind, walking: Bool) -> Map3DModelPack.Model? {
        let name = name(kind, walking: walking)
        let second = kind.isSecondBatch
        guard let text = second ? Map3DPedestrianBatch2.encoded[name] : encoded[name],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: second ? Map3DPedestrianBatch2.palette : palette)
    }

    // MARK: Who stands where (decision 1037)

    /// Who stands in each of a place's 24 slots (the assets repository's
    /// `docs/handoff/STREET-TEMPLE-VIADUCT-TRAM-RULES.md` §1.1), the
    /// commuter (`nil`) first: platform, station front, shops, temple,
    /// pavement. Each column adds up to 24.
    static let table: [(who: Kind?, counts: [Int])] = [
        (nil, [5, 4, 2, 2, 3]),
        (.office, [4, 3, 1, 1, 2]),
        (.officeWoman, [4, 3, 2, 1, 2]),
        (.student, [3, 2, 2, 1, 2]),
        (.schoolboy, [1, 1, 0, 1, 2]),
        (.elderly, [2, 2, 3, 6, 3]),
        (.phone, [3, 3, 3, 2, 3]),
        (.traveller, [1, 2, 1, 1, 0]),
        (.tourist, [1, 1, 2, 4, 0]),
        (.umbrella, [0, 1, 1, 1, 1]),
        (.worker, [0, 0, 0, 0, 2]),
        (.grandmaCart, [0, 1, 3, 3, 1]),
        (.motherStroller, [0, 0, 2, 1, 1]),
        (.jogger, [0, 0, 0, 0, 1]),
        (.delivery, [0, 1, 2, 0, 1]),
    ]
    static let slots = 24

    /// The column of `place` in ``table``.
    static func column(_ place: Map3DStreetLife.Spot.Kind) -> Int {
        switch place {
        case .platform: 0
        case .stationFront: 1
        case .shops: 2
        case .temple: 3
        case .sidewalk: 4
        }
    }

    /// The game's time of day and whether it is a rest day (a Saturday,
    /// a Sunday or a holiday), which some people go out by.
    public struct Clock: Sendable, Equatable {
        /// Minutes since midnight, 0–1439.
        public var minute: Int
        public var restDay: Bool

        public init(minute: Int, restDay: Bool) {
            self.minute = minute
            self.restDay = restDay
        }

        /// Ten in the morning of a weekday: where no world tells the time.
        public static let morning = Clock(minute: 600, restDay: false)

        func within(_ windows: [(Int, Int)]) -> Bool { windows.contains { minute >= $0.0 && minute < $0.1 } }
    }

    /// Who stands in slot `slot` (0–23, the figure's own draw) of a
    /// `place` at `clock` in `region`: the table's, Finland's joggers and
    /// tourists the commuter (shorts in the snow), a rest day's first
    /// slot a tourist, and those out only at some hours someone else
    /// outside them (§1.2), so the street never empties.
    static func kind(slot: Int, at place: Map3DStreetLife.Spot.Kind, clock: Clock, region: Map3DStreetRegion) -> Kind? {
        let column = column(place)
        var left = min(max(slot, 0), slots - 1)
        var who: Kind?
        for row in table {
            if left < row.counts[column] { who = row.who; break }
            left -= row.counts[column]
        }
        if clock.restDay, slot == 0 { who = .tourist }
        if region == .finland, who == .jogger || who == .tourist { who = nil }
        let school = !clock.restDay && clock.within([(390, 510), (930, 1_080)])
        switch who {
        case .schoolboy where !school: return nil
        case .worker where clock.restDay || !clock.within([(420, 1_080)]): return nil
        case .jogger where !clock.within([(330, 480), (1_050, 1_260)]): return .phone
        case .grandmaCart where !clock.within([(420, 720), (900, 1_080)]): return .elderly
        case .motherStroller where !clock.within([(540, 1_080)]): return .officeWoman
        case .delivery where !clock.within([(630, 840), (1_020, 1_260)]): return .phone
        default: return who
        }
    }
}

/// Decision 1037: the second batch's colours, in the order
/// `glb_to_swift.py --materials` gave them (``Map3DPedestrianBatch2Mesh``):
/// skin, hair, shirt (alpha 0: the instance's colour), trousers, dark,
/// white, helmet (a cap or hard hat), schoolBag, khaki, vest, boot,
/// greyHair, cartRed, frame. All the game's own.
enum Map3DPedestrianBatch2 {
    static let palette: [UInt32] = [
        Map3DStreetModel.skin, Map3DStreetModel.hair, Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF, Map3DStreetModel.trousers, Map3DStreetModel.tyre,
        Map3DPalette.sidewalk, Map3DPalette.platformEdge, Map3DPalette.lantern, Map3DPalette.terrazzo, Map3DStreetLife.shirts[9],
        Map3DPalette.timber, Map3DPalette.tankSteel, Map3DPalette.lantern, Map3DPalette.steel,
    ]
}
