import Foundation

/// Decision 338: the train pack, new trains' looks sold apart from the
/// game. Until it is unlocked its sets are drawn as the trains were before
/// them, so a locked pack changes how a train looks and nothing else: not
/// its speed, its seats or its fares, and not the save.
///
/// Until the App Store sells it, only a test build (Xcode or TestFlight)
/// unlocks it, with a switch in the settings (``testUnlockKey``); before the
/// game is on the App Store the switch gives way to the purchase.
///
/// Decision 427: the E1000 look of the push-pull Tze-Chiang is the pack's
/// too, but off by default: an unlocked pack draws the E500 until its own
/// switch (``pushPullE1000Key``) is on.
public enum TrainPack {
    /// The pack's sets (``Map3DTrainSet/key``): the three-car urban EMU
    /// and, later, the light metro's five- and seven-section LRTs; decision
    /// 399: the four-car metro and the seven-section car; decision 338
    /// (second later): the N700S-G, not a Taiwanese train. While it is
    /// locked every high-speed train is the 700T
    /// (``Map3DTrainSet/variant(of:number:locked:)``); decision 427: and the
    /// push-pull Tze-Chiang's E1000 look, which the pack's second switch
    /// turns on.
    public static let sets: Set<String> = ["threeCarUrban", "fiveSectionLRT", "sevenSectionLRT", "fourCarMetro", "blueSeven", "n700sG", "pushPullE1000"]

    /// The settings switch that unlocks the pack in a test build.
    public static let testUnlockKey = "trainPack.testUnlocked"

    /// Decision 427: the settings switch that draws the push-pull
    /// Tze-Chiang as the E1000 once the pack is unlocked; off by default.
    public static let pushPullE1000Key = "trainPack.pushPullE1000"

    /// The sets to draw as before them: the pack's, unless it is unlocked;
    /// decision 427: and the E1000 look, unless `pushPullE1000` is on too.
    public static func locked(unlocked: Bool, pushPullE1000: Bool = false) -> Set<String> {
        guard unlocked else { return sets }
        return pushPullE1000 ? [] : ["pushPullE1000"]
    }

    /// Whether the pack is unlocked: only in a test build, and only with
    /// its switch on.
    public static func isUnlocked(testBuild: Bool, switchOn: Bool) -> Bool {
        testBuild && switchOn
    }
}
