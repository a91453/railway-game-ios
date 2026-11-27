// Decision 1018 (continued 4): the Chikugo River Lift Bridge (筑後川昇開橋,
// the former Saga Line's Chikugo River bridge, 1935, an Important Cultural
// Property), now a footbridge between Okawa and Morodomi, on the Fukuoka
// map: its two 30 m red lifting towers over the 24.2 m span between them,
// raised as it stands for the boats, a red Warren truss beyond each tower
// and the plate girders on fourteen piers either side. Modelled by the
// local studio from photographs, the Agency for Cultural Affairs' record
// and OpenStreetMap's line (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-chikugo-lift-bridge-2026-11/revision-2`;
// lessons in `docs/studio/lessons/jp-chikugo-lift-bridge.md`), its +x
// toward the Saga (north-west) end, and written here by
// `tools/landmarks/glb_to_swift.py --centre --turn 146.85` (``encoded``).

/// 507.2 m from end to end, its lifting span 43.9 m south-east of its
/// middle, as OpenStreetMap's line has it (relation 11745196). Its piers'
/// feet are the river's surface; it is sunk 1 m into the water, set on the
/// ground at its middle, in the river.
enum Map3DChikugoLiftBridge {
    static let registration = Map3DLandmarkRegistration(
        id: "jp-chikugo-lift-bridge", map: "fukuoka",
        // 43.9 m north-west of the middle of the lifting span
        // (way 772812136) along the line's 303.15°.
        latitude: 33.2149031, longitude: 130.3619754,
        sink: 1,
        // towerRed (towers, trusses, girders, lifting span), girderDark
        // (machinery, cables, the decks under the trusses), railing,
        // concrete (piers and the walkway).
        palette: [Map3DPalette.mtrRed, Map3DPalette.mtrCharcoal, Map3DPalette.timberSiding, Map3DPalette.concrete],
        encoded: encoded,
        // 507.2 m by 9.6 m turned 146.85°, the towers 30 m up.
        size: (429.02, 284.06, 30.00))
}
