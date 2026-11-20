/// Decision 907: the Arktikum museum's glass gallery, a 172 m vaulted
/// glass tube reaching out over the slope to the Ounasjoki, its north end
/// high above the bank. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/rovaniemi-landmarks-2026-11/revision-4`,
/// #226), turned 58° to run from the museum to the river as OpenStreetMap's
/// buildings there lie (estimated: the gallery has no outline of its own),
/// and written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DRovaniemiArcticGallery {
    static let registration = Map3DLandmarkRegistration(
        id: "rovaniemi-glass-gallery", map: "rovaniemi",
        // Between the museum's building and the gallery's northern one.
        latitude: 66.5080, longitude: 25.7268,
        // glassBright (the vault), stone (the retaining walls), frame (its
        // steel), dark (the entrances).
        palette: [Map3DPalette.cityOfficeWalls[4], Map3DPalette.stone, Map3DPalette.steel, Map3DPalette.dark],
        glass: [0],
        encoded: encoded,
        size: (100.97, 151.48, 15.2))
}
