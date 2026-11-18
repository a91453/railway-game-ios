/// Decision 866: the sounds a station can be set to play, which the player
/// picks on the station panel (decision 219, stage 2). GameCore only keeps
/// the choice (``Station/chime``, ``Station/departureMelody``); no rule reads
/// it, and the app plays the sounds. A station set to neither plays what
/// its place in the network calls for, as every station did before.

/// Which of the arrival chimes a station rings (decision 219, stage 1).
public enum StationChime: String, Codable, CaseIterable, Hashable, Sendable {
    /// A small station: the two-note bell (`station-chime.wav`).
    case local
    /// An interchange: two passenger lines or more call there, or a high
    /// speed line does. The four-note bell of the reference's airport
    /// announcements, C5–E5–G5–C6.
    case metro
    /// An attraction is within the station's catchment (decision 174): a
    /// light plucked phrase on the C major pentatonic scale.
    case tourist
}

/// Decision 853: the melodies a train plays as its doors start closing,
/// written for the game (`tools/audio/scores/departure-*.score.json`).
public enum DepartureMelody: String, Codable, CaseIterable, Hashable, Sendable {
    /// Rising: I, IV, ii, I, over a harp.
    case a
    /// Falling, the bass stepping down: IV, I, ii, I, over pizzicato strings.
    case b
    /// Over a held C: I, IV, a suspended V, I, over a harp and soft strings.
    case c
}
