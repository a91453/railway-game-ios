import AVFoundation
import GamePresentation
import Observation

/// Plays the game's music and sounds (`Resources/Audio/`, made by
/// `tools/audio/make_game_audio.py`): the soundtrack of the first promo
/// video, so the game sounds as the video does. The music loops while the
/// app is in the foreground; the sounds play for the session's cues
/// (``SoundCue``). The player turns either off in the game menu, and the
/// choice is kept on the device, never in a save.
///
/// The audio session is ambient: the game mixes with whatever else is
/// playing, and the ring/silent switch silences it.
@MainActor
@Observable
final class GameAudio {
    /// Whether the music plays.
    private(set) var musicOn: Bool
    /// Whether the sounds play.
    private(set) var soundsOn: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var music: AVAudioPlayer?
    @ObservationIgnored private var sounds: [SoundCue: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var lastPlayed: [SoundCue: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var isActive = false
    /// Whether anything is played at all: not in UI tests (see `init`).
    @ObservationIgnored private let plays: Bool

    private enum Key {
        static let music = "audio.music"
        static let sounds = "audio.sounds"
    }

    /// `plays` false keeps the switches working and plays nothing: the UI
    /// tests' Simulator runs on a 3-core runner, and the music, on by
    /// default, looped through every test. On #211's run the audio I/O
    /// thread reported "skipping cycle due to overload" while XCTest's
    /// queries took 1 to 2 s each and a test timed out, though the app's
    /// main thread answered every one in time.
    init(defaults: UserDefaults = .standard, plays: Bool = true) {
        self.defaults = defaults
        self.plays = plays
        musicOn = defaults.object(forKey: Key.music) as? Bool ?? true
        soundsOn = defaults.object(forKey: Key.sounds) as? Bool ?? true
        // A call, an alarm or another app can stop the music while the app
        // stays active (a call declined from its banner): pick it up again
        // when iOS says the interruption is over. The observer lives as
        // long as the app, as this object does.
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .ended, let self else { return }
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                self.updateMusic()
            }
        }
    }

    func setMusicOn(_ on: Bool) {
        musicOn = on
        defaults.set(on, forKey: Key.music)
        updateMusic()
    }

    func setSoundsOn(_ on: Bool) {
        soundsOn = on
        defaults.set(on, forKey: Key.sounds)
    }

    /// Follows the app in and out of the foreground: the music plays only
    /// while it is active, and resumes where it stopped.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            // Without the session the players still play, as the default
            // (solo ambient) session does.
            _ = try? AVAudioSession.sharedInstance().setCategory(.ambient)
            _ = try? AVAudioSession.sharedInstance().setActive(true)
        }
        updateMusic()
    }

    /// Plays the sound for `cue`, unless sounds are off, the app is not
    /// active, or the same sound played too recently: at high speed many
    /// trains arrive within a second, and one chime stands for them. The
    /// trains the player is not looking at ring quieter and at most every
    /// few seconds, so a busy network does not ring all the time.
    func play(_ cue: SoundCue) {
        guard plays, soundsOn, isActive else { return }
        let now = ContinuousClock.now
        if let last = lastPlayed[cue], now - last < Self.spacing(of: cue) { return }
        let players = sounds[cue] ?? loadSound(cue)
        // A free player of the sound's few, so a sound can overlap itself.
        guard let player = players.first(where: { !$0.isPlaying }) ?? players.first else { return }
        lastPlayed[cue] = now
        if cue == .arrival(watched: true) {
            // The others' chime would only echo it.
            lastPlayed[.arrival(watched: false)] = now
        }
        player.currentTime = 0
        player.play()
    }

    private func updateMusic() {
        if plays && musicOn && isActive {
            if music == nil {
                music = Self.player(named: "music-loop", extension: "caf", volume: 0.45)
                music?.numberOfLoops = -1
            }
            music?.play()
        } else {
            music?.pause()
        }
    }

    private func loadSound(_ cue: SoundCue) -> [AVAudioPlayer] {
        let (name, volume): (String, Float) = switch cue {
        case .arrival(watched: true): ("station-chime", 0.55)
        case .arrival(watched: false): ("station-chime", 0.2)
        case .track: ("rail-joint", 0.7)
        case .transition: ("whoosh", 0.3)
        }
        let players = (0..<3).compactMap { _ in Self.player(named: name, extension: "wav", volume: volume) }
        sounds[cue] = players
        return players
    }

    /// The least time between two plays of a sound.
    private static func spacing(of cue: SoundCue) -> Duration {
        switch cue {
        case .arrival(watched: true): .milliseconds(500)
        case .arrival(watched: false): .seconds(6)
        case .track: .milliseconds(100)
        case .transition: .milliseconds(250)
        }
    }

    private static func player(named name: String, extension ext: String, volume: Float) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.volume = volume
        player.prepareToPlay()
        return player
    }
}
