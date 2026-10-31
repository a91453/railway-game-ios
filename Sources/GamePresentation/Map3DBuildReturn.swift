import GameCore

/// Decision 517 (the owner's recording, 2026-10-31: Build on the 3D map
/// jumps to the 2D map): building stays on the 2D map (decision 313), and
/// the 3D map's Build hands it the 3D camera's middle and zoom
/// (``Map3DHandoff/plan(from:in:)``), but a player who came from the 3D map
/// goes back to it as building ends, to the camera they left, its heading
/// and lean too (the 2D map always faces north). One who opened the tools
/// on the 2D map stays there.
///
/// Screen state only, never in the world: which map building was started
/// from, kept from the 3D map's Build until the tools close.
public struct Map3DBuildReturn: Equatable, Sendable {
    /// The 3D camera Build left, kept by the world point it looked at:
    /// the scene the 3D map builds again (after the building) can stand
    /// round another origin.
    public struct Viewpoint: Equatable, Sendable {
        public let camera: Map3DCamera
        public let x: Double
        public let y: Double

        public init(camera: Map3DCamera, in scene: Map3DScene) {
            self.camera = camera
            let middle = scene.worldPosition(of: camera.target)
            x = middle.x
            y = middle.y
        }

        /// Where the 3D map opens again, its scene built round it.
        public var plan: Map3DHandoff.Plan {
            Map3DHandoff.Plan(x: x, y: y, referenceSize: Map3DHandoff.referenceSize(distance: camera.distance,
                                                                                    viewportHeight: Double(camera.viewport.height)))
        }

        /// The camera as it was left, in `scene`, for a view `viewport`
        /// points: the same point, distance, heading and lean.
        public func camera(in scene: Map3DScene, viewport: (width: Float, height: Float)) -> Map3DCamera {
            var camera = camera
            camera.target = scene.point(worldX: x, worldY: y, height: Double(camera.target.y) * Double(WorldCoordinate.unitsPerMetre))
            camera.viewport = viewport
            return camera
        }
    }

    /// The 3D view Build left, and the game it was left in.
    public private(set) var view: Viewpoint?
    private var game: ObjectIdentifier?

    public init() {}

    /// Whether a return to the 3D map is waiting for building to end.
    public var waits: Bool { view != nil }

    /// The 3D map's Build pressed with its view at `view`, in `game`
    /// (the session): building ends back there.
    public mutating func leftForBuilding(from view: Viewpoint, in game: ObjectIdentifier) {
        self.view = view
        self.game = game
    }

    /// The tool chosen in `game` is now `tool`. The view to open the 3D
    /// map at again when building ends (the tools closed: Done, or Build
    /// pressed again) after the 3D map's Build, else `nil`. A tool changed
    /// for another (track to trains, buildings, zones, buses) still builds,
    /// and waits. Never with the 3D map off (decision 365) or the tutorial
    /// running (its steps are on the 2D map), and not in another game,
    /// which forget the return.
    public mutating func toolChanged(to tool: ConstructionTool, in game: ObjectIdentifier,
                                     shows3D: Bool, tutorialRuns: Bool) -> Viewpoint? {
        guard let view else { return nil }
        guard game == self.game, shows3D, !tutorialRuns else {
            forget()
            return nil
        }
        guard tool == .select else { return nil }
        forget()
        return view
    }

    /// Nothing to go back to: the 3D map opened some other way (its
    /// button, a pinch, a train followed), or the tutorial started.
    public mutating func forget() {
        view = nil
        game = nil
    }
}
