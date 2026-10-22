import Foundation

/// Decision 338: the train pack, new trains' looks sold apart from the
/// game. Until it is unlocked its sets are drawn as the trains were before
/// them, so a locked pack changes how a train looks and nothing else: not
/// its speed, its seats or its fares, and not the save.
///
/// Until the App Store sells it, only a test build (Xcode or TestFlight)
/// unlocks it, with a switch in the settings (``testUnlockKey``); before the
/// game is on the App Store the switch gives way to the purchase.
public enum TrainPack {
    /// The pack's sets (``Map3DTrainSet/key``): the three-car urban EMU
    /// and, later, the light metro's five- and seven-section LRTs.
    public static let sets: Set<String> = ["threeCarUrban", "fiveSectionLRT", "sevenSectionLRT"]

    /// The settings switch that unlocks the pack in a test build.
    public static let testUnlockKey = "trainPack.testUnlocked"

    /// The sets to draw as before them: the pack's, unless it is unlocked.
    public static func locked(unlocked: Bool) -> Set<String> {
        unlocked ? [] : sets
    }

    /// Whether the pack is unlocked: only in a test build, and only with
    /// its switch on.
    public static func isUnlocked(testBuild: Bool, switchOn: Bool) -> Bool {
        testBuild && switchOn
    }
}
