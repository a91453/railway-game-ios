// Decision 895: every registered landmark (``Map3DLandmarkRegistration``),
// one line each. A new landmark adds its line at the end and changes
// nothing else in this file: `.gitattributes` merges it with
// `merge=union`, so two landmarks added on two branches keep both lines
// instead of conflicting. `Map3DLandmarkRegistryTests` checks the list
// against the registrations in the sources and their lock files.
extension Map3DLandmarkRegistry {
    static let landmarks: [Map3DLandmarkRegistration] = [
        Map3DFukuokaTower.registration,
        Map3DFukuokaDome.registration,
        Map3DHakataStation.registration,
        Map3DRovaniemiCandleBridge.registration,
        Map3DRovaniemiArcticGallery.registration,
        Map3DRovaniemiChurch.registration,
        Map3DRovaniemiArcticVillage.registration,
        Map3DPeakTower.registration,
    ]
}
