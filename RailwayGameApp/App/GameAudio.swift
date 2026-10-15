import AVFoundation
import GamePresentation
import Observation
import SwiftUI

/// Plays the game's music and sounds (`Resources/Audio/`, made by
/// `tools/audio/make_game_audio.py`): the soundtrack of the first promo
/// video, so the game sounds as the video does. Decision 219: an arrival
/// rings the station's chime (local, metro or tourist), or its motif at
/// high speed. The music loops while the
/// app is in the foreground; the sounds play for the session's cues
/// (``SoundCue``). The player turns either off in the game menu, and the
/// choice is kept on the device, never in a save. Decision 219, stage 2:
/// under the switches, three volumes (``SoundVolumes``): the music, the
/// station chimes and the other effects, also kept on the device.
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
    /// The player's three volumes (decision 219, stage 2).
    private(set) var volumes: SoundVolumes

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var music: AVAudioPlayer?
    @ObservationIgnored private var sounds: [SoundCue: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var lastPlayed: [SoundCue: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var isActive = false
    /// Decision 184: the latest tap of the phone a cue asked for, which
    /// the app's scene gives (`sensoryFeedback`): a refusal, a warning or
    /// something put up.
    private(set) var haptic: HapticPulse?

    /// A tap of the phone, numbered so the same kind twice is two taps.
    struct HapticPulse: Equatable {
        let feedback: SensoryFeedback
        let serial: Int
    }
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
        volumes = SoundVolumes(stored: { defaults.object(forKey: $0) })
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

    /// Sets one of the three volumes (decision 219, stage 2); the music
    /// follows at once, a sound from its next play.
    func setVolume(_ level: Double, of category: SoundCategory) {
        volumes.setLevel(level, of: category)
        defaults.set(volumes.level(of: category), forKey: SoundVolumes.key(for: category))
        if category == .music {
            music?.volume = volumes.volume(Self.musicVolume, for: .music)
        }
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
    ///
    /// Decision 184: a refusal, a warning and something put up also tap
    /// the phone (the system's haptics setting decides whether it does),
    /// with the sounds off too.
    func play(_ cue: SoundCue) {
        guard plays, isActive else { return }
        let now = ContinuousClock.now
        // Decision 219: the chimes of all stations share their spacing.
        let spaced = Self.spacingKey(of: cue)
        if let last = lastPlayed[spaced], now - last < Self.spacing(of: cue) { return }
        if let feedback = Self.feedback(for: cue) {
            haptic = HapticPulse(feedback: feedback, serial: (haptic?.serial ?? 0) &+ 1)
        }
        // Decision 219, stage 2: a volume at nothing plays nothing.
        let volume = volumes.volume(Self.baseVolume(of: cue), for: cue.category)
        guard soundsOn, volume > 0 else {
            lastPlayed[spaced] = now
            return
        }
        let players = sounds[cue] ?? loadSound(cue)
        // A free player of the sound's few, so a sound can overlap itself.
        guard let player = players.first(where: { !$0.isPlaying }) ?? players.first else { return }
        lastPlayed[spaced] = now
        if case .arrival(true, _, _) = cue {
            // The others' chime would only echo it.
            lastPlayed[.arrival(watched: false)] = now
        }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func updateMusic() {
        if plays && musicOn && isActive {
            if music == nil {
                music = Self.player(named: "music-loop", extension: "caf", volume: volumes.volume(Self.musicVolume, for: .music))
                music?.numberOfLoops = -1
            }
            music?.play()
        } else {
            music?.pause()
        }
    }

    /// The music's own volume, before the player's (decision 219, stage 2).
    private static let musicVolume: Float = 0.45

    /// A cue's own volume, before the player's (decision 219, stage 2).
    private static func baseVolume(of cue: SoundCue) -> Float {
        switch cue {
        case .arrival(true, _, _): 0.55
        case .arrival(false, _, _): 0.2
        case .track: 0.7
        case .transition: 0.3
        case .built: 0.6
        case .income: 0.35
        case .refused: 0.5
        case .warning: 0.45
        }
    }

    /// Decision 219: the file is the cue's (``SoundCue/resource``): the
    /// station's chime, or its motif at high speed. Each play sets its
    /// volume.
    private func loadSound(_ cue: SoundCue) -> [AVAudioPlayer] {
        let file = cue.resource
        let players = (0..<3).compactMap { _ in Self.player(named: file.name, extension: file.extension, volume: Self.baseVolume(of: cue)) }
        sounds[cue] = players
        return players
    }

    /// What a cue's spacing is kept by: an arrival by whether it is
    /// watched and a motif, whichever station's chime it is.
    private static func spacingKey(of cue: SoundCue) -> SoundCue {
        if case .arrival(let watched, _, let motif) = cue { return .arrival(watched: watched, motif: motif) }
        return cue
    }

    /// The least time between two plays of a sound.
    private static func spacing(of cue: SoundCue) -> Duration {
        switch cue {
        // Decision 219: the motif plays at 600× and faster, at most every
        // 1.5 s (the research note's §6).
        case .arrival(true, _, true): .milliseconds(1500)
        case .arrival(true, _, false): .milliseconds(500)
        case .arrival(false, _, _): .seconds(6)
        case .track: .milliseconds(100)
        case .transition: .milliseconds(250)
        case .built: .milliseconds(150)
        // At high speed an hour settles every second or two: one ding
        // stands for several.
        case .income: .seconds(3)
        // Decision 184: a burst of refusals (a drag across water) or of
        // worries (a new day's) sounds once.
        case .refused: .milliseconds(600)
        case .warning: .seconds(2)
        }
    }

    /// The tap a cue gives, if any (decision 184).
    private static func feedback(for cue: SoundCue) -> SensoryFeedback? {
        switch cue {
        case .refused: .error
        case .warning: .warning
        case .built: .success
        case .arrival, .track, .transition, .income: nil
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
