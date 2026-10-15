import Foundation
import GameCore

/// Decision 219, stage 2: the music steps aside while the player follows a
/// train into an interchange (the research note's §2.8), so the station's
/// chime is heard over it. Only at 60× and slower, where stations are far
/// enough apart that the music does not keep going down and up.
///
/// The distances are the reference's `MetroPlatformAmbience` bands
/// (1,500 / 800 / 300 / 75 m): the music starts going down 800 m before the
/// station, is 6 dB down from 300 m, stays down while the train stands
/// there, and comes back as it leaves. A factor on the player's music
/// volume (``SoundVolumes``), worked out after each step; never part of the
/// world, never saved.
public enum MusicDuck {
    /// Where the music starts going down, in metres before the station.
    static let startMetres = 800.0
    /// Where it is all the way down.
    static let fullMetres = 300.0
    /// How far down, in decibels.
    static let depthDecibels = -6.0
    /// The steps the level moves in, in decibels: the app is told only
    /// when it moves a step (a dozen times on the way in), and fades
    /// between them.
    static let stepDecibels = 0.5

    /// The factor on the music `metres` before an interchange: 1 from
    /// 800 m out, then down evenly in decibels to 6 dB down (about 0.5) at
    /// 300 m and nearer, in half-decibel steps.
    public static func gain(metresToStation metres: Double) -> Double {
        let share = min(max((startMetres - metres) / (startMetres - fullMetres), 0), 1)
        let decibels = (share * depthDecibels / stepDecibels).rounded() * stepDecibels
        return decibels == 0 ? 1 : pow(10, decibels / 20)
    }

    /// The factor on the music while `train` is followed in `world`: 1
    /// unless the game runs at 60× or slower and the train is on its way
    /// to, or stands at, a station that rings the interchange chime
    /// (``StationChime/metro``). The way there is the path the service
    /// gave it, which ends at the platform (``TrainMovement``).
    static func gain(following train: Train?, in world: GameWorld) -> Double {
        guard let train, world.clock.speed.tenthsPerTick <= GameSpeed.x60.tenthsPerTick,
              let execution = train.execution, train.timetable.indices.contains(execution.stop)
        else { return 1 }
        let station = train.timetable[execution.stop].station
        guard StationChime.of(station, in: world) == .metro else { return 1 }
        switch execution {
        case .waitingAtStop:
            return gain(metresToStation: 0)
        case .travellingToStop:
            // No path left on the way there: it stands where its path
            // ends, at the platform.
            let left = world.pathDistanceLeft(of: train) ?? 0
            return gain(metresToStation: Double(left) / Double(WorldCoordinate.unitsPerMetre))
        }
    }
}
