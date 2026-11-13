/// Decision 721: the 3D map after dark. As the city's lights come on
/// (``Map3DLighting``'s `lights`) the model look's light (decision 370)
/// falls to ``dim`` of itself, so what shows is what is lit: the windows,
/// the street lights' pools on the roads, and the player's line, whose
/// ballast and trains keep their light and take a little more.
///
/// The numbers the shader works with (`Map3DShaders.metal`'s `nightDim`,
/// `trackLit`, `stockLit`, `roadPool`, `roadPoolCell`, `nightWindowsMore`,
/// `nightBays`, `nightFall`) and tools/map3d-preview's page with them; the tests hold
/// the three to one another.
public enum Map3DNight {
    /// The share of the day's light left on the city once its lights are
    /// fully on.
    public static let dim: Float = 0.42
    /// How much of its own colour a track's ballast is lit with after dark.
    public static let trackLit: Float = 0.30
    /// And a train (``Map3DInstance/lit``).
    public static let stockLit: Float = 0.30
    /// The street lights' pools on a road: the light between pools, the
    /// light added at a pool's middle, and how fast it falls off (the
    /// divisor of the squared metres from it).
    public static let roadPool: (between: Float, middle: Float, spread: Float) = (0.08, 1.6, 28)
    /// A pool somewhere in every square of this many metres.
    public static let roadPoolCell: Float = 24
    /// The lit windows after dark: their share times this,
    public static let windowsShare: Float = 1.7
    /// their light times this,
    public static let windowsLight: Float = 1.35
    /// and the share of a landmark's bays lit.
    public static let bays: Float = 0.42
    /// The shares of the city's lights between which the dimming and the
    /// track's and trains' light come in: fast, as the track turns from
    /// darker than the ground to lighter and is neither in between.
    public static let fall: (from: Float, to: Float) = (0.45, 0.60)
    /// The ballast's layer, which the shader tells the track bed by.
    public static let trackSurface = Map3DSurface.ballast
}
