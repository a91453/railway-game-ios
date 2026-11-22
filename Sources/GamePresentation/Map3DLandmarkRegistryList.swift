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
        Map3DFukuokaTanks.gasHolder701217744,
        Map3DFukuokaTanks.gasHolder701217745,
        Map3DFukuokaTanks.gasHolder804614370,
        Map3DFukuokaTanks.gasHolder804614371,
        Map3DFukuokaTanks.gasHolder727497179,
        Map3DFukuokaTanks.gasHolder727497184,
        Map3DFukuokaTanks.gasHolder727497186,
        Map3DFukuokaTanks.gasHolder727497187,
        Map3DFukuokaTanks.gasHolder727497188,
        Map3DFukuokaTanks.gasHolder804613317,
        Map3DFukuokaTanks.waterTower292979178,
        Map3DFukuokaTanks.waterTower603581064,
        Map3DFukuokaTanks.waterTower715740961,
        Map3DFukuokaTanks.waterTower964202521,
        Map3DFukuokaTanks.waterTower964502374,
        Map3DFukuokaTanks.waterTower1175768613,
        Map3DFukuokaTanks.waterTower1418044218,
        Map3DBaguashanBuddha.registration,
        Map3DDragonTigerPagodas.registration,
        Map3DHKObservationWheel.registration,
        Map3DHKMPlus.registration,
        Map3DHKPalaceMuseum.registration,
    ]
}
