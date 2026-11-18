// Decision 782: every registered train (``Map3DTrainRegistration``), one
// line each. A new train adds its line at the end and changes nothing
// else in this file: `.gitattributes` merges it with `merge=union`, so two
// trains added on two branches keep both lines instead of conflicting.
// `Map3DTrainRegistryTests` checks the list against the registrations in
// the sources and their lock files.
extension Map3DTrainRegistry {
    static let trains: [Map3DTrainRegistration] = [
        Map3DMTRAirportLine.registration,
        Map3DMTRUrbanLine.registration,
        Map3DFreightWagons.registration,
        Map3DMTRTuenMaLine.registration,
        Map3DMTRSouthIslandLine.registration,
    ]
}
