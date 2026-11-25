// Decision 976: what each layer of the 3D scene keeps while the scene is
// built (``Map3DScene/Builder/state``), one line a layer. The layer's
// state is a struct in the layer's own file; a new layer adds its struct
// there and its line at the end here, and changes nothing else in this
// file or in the builder: `.gitattributes` merges this file with
// `merge=union`, so two layers added on two branches keep both lines
// instead of conflicting. `Map3DSceneLayerRegistryTests` checks the list.
extension Map3DScene.Builder {
    struct LayerStates {
        var airfields = AirfieldState()
        var facades = FacadeState()
        var track = TrackState()
        var guideway = GuidewayState()
        var trackKinds = TrackKindState()
        var platforms = PlatformState()
        var underground = UndergroundState()
        var stations = StationState()
        var nameBoards = NameBoardState()
        var stationCrossings = StationCrossingState()
        var elevated = ElevatedState()
        var baseMap = BaseMapState()
        var land = LandCoverState()
        var winter = WinterState()
        var reindeer = ReindeerState()
        var streets = StreetState()
        var realTrains = RealTrainState()
        var overhead = OverheadState()
        var roadside = RoadsideState()
        var lowRise = LowRiseState()
        var realCover = RealCoverState()
        var shops = ShopState()
        var exteriors = ExteriorState()
        var freight = FreightState()
        var landmarks = LandmarkState()
        var suspensionBridges = SuspensionBridgeState()
        var archBridges = ArchBridgeState()
        var roadBridges = Map3DRoadBridges()
        var roadGrade = Map3DRoadGrade()
        var roadBed = Map3DRoadBed()
    }
}
