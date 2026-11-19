import Foundation
import GameCore

/// Decision 883: plays a melody the player wrote (``PlayerMelody``) on
/// the music's sampled piano, as the official departure melodies are
/// (decision 853: 150 bpm, 3/4, four bars and the last chord ringing on,
/// 7.8 s), made on the device from a few recorded notes
/// (`melody-piano-<root>.wav`, `tools/audio/make_game_audio.py`), with no
/// audio framework: each note is the nearest recording, played faster or
/// slower to its pitch, its key let go a beat after it ends at the
/// earliest (as the official melodies' pedal holds it), the whole through
/// a small room (Freeverb's algorithm, public domain) and levelled to
/// sound as loud as the official melodies. The app plays the result
/// (``wav(_:)``) as it plays a sound file. Pure and deterministic, so a
/// Linux test can hold it.
public struct PlayerMelodySynth: Sendable {
    /// The samples' and the result's rate.
    public static let rate = 32_000
    /// The tempo, as the official melodies'.
    public static let tempo = 150
    /// The recorded notes' pitches (MIDI), a major third apart up to A6,
    /// and C7, the top of ``PlayerMelody/pitches``: every note a player
    /// can write is within two semitones of one.
    public static let roots = [74, 78, 82, 86, 90, 93, 96]
    /// The file of the recorded note `root`, in the app's `Audio`
    /// resources.
    public static func sampleName(_ root: Int) -> String {
        "melody-piano-\(root)"
    }

    /// Seconds the result rings on after the melody's four bars, as the
    /// official melodies' (`tools/audio`: 7.8 s in all).
    static let tail = 3.0
    /// The result's peak: a piano alone peaks some 3 dB higher than the
    /// official melodies (piano and accompaniment, peak 0.6, decision
    /// 853) at the same loudness, so it peaks there to sound as loud
    /// (−15.6 LUFS for official melody 1's tune, as loud as melody 1).
    static let peak: Float = 0.85
    /// Seconds a let-go key takes to fall silent (its damper).
    static let damping = 0.12
    /// The room's share of the result.
    static let wet: Float = 0.22

    /// The recorded notes, by pitch, at ``rate``.
    let samples: [Int: [Float]]

    /// A synth on `samples`: one recording for each of ``roots``, mono,
    /// at ``rate``.
    public init?(samples: [Int: [Float]]) {
        guard Set(samples.keys) == Set(Self.roots), samples.values.allSatisfy({ !$0.isEmpty }) else { return nil }
        self.samples = samples
    }

    /// A synth on the recordings in `files` (each a 16-bit mono WAV file
    /// at ``rate``, by root), or `nil` if one is missing or not one.
    public init?(wavFiles: [Int: [UInt8]]) {
        var samples: [Int: [Float]] = [:]
        for (root, bytes) in wavFiles {
            guard let frames = Self.frames(ofWAV: bytes) else { return nil }
            samples[root] = frames
        }
        self.init(samples: samples)
    }

    /// The frame at which `ticks` fall.
    static func frame(_ ticks: Int) -> Int {
        ticks * rate * 60 / (tempo * PlayerMelody.ticksPerBeat)
    }

    /// `notes` played, mono at ``rate``: the four bars and ``tail``.
    public func render(_ notes: [MelodyNote]) -> [Float] {
        let count = Self.frame(PlayerMelody.length) + Int(Self.tail * Double(Self.rate))
        var out = [Float](repeating: 0, count: count)
        let beat = Self.frame(PlayerMelody.ticksPerBeat)
        let bar = 3 * PlayerMelody.ticksPerBeat
        let decay = Float(1 / (Self.damping * Double(Self.rate)))
        for note in notes {
            let root = Self.roots.min { abs($0 - note.pitch) < abs($1 - note.pitch) } ?? Self.roots[0]
            guard let sample = samples[root] else { continue }
            let step = Float(pow(2, Double(note.pitch - root) / 12))
            let start = Self.frame(note.start)
            let end = note.start + note.length
            // The last notes ring on; any other key is let go a beat after
            // it was struck at the earliest.
            let release = end >= PlayerMelody.length ? Int.max : max(Self.frame(end), start + beat)
            // A phrase swells to its middle and eases off, a bar's first
            // beat leans a little (`sampled_music.played`).
            let contour = 0.90 + 0.14 * sin(Double.pi * (Double(note.start) + Double(note.length) / 2) / Double(PlayerMelody.length))
            let accent = note.start % bar == 0 ? 1.05 : note.start % PlayerMelody.ticksPerBeat == 0 ? 1.0 : 0.95
            let gain = Float(contour * accent)
            var position: Float = 0
            var frame = start
            let last = Float(sample.count - 1)
            while frame < count, position < last {
                let index = Int(position)
                let fraction = position - Float(index)
                var value = sample[index] + (sample[index + 1] - sample[index]) * fraction
                if frame >= release {
                    let since = Float(frame - release) * decay
                    if since > 9 { break }
                    value *= exp(-since)
                }
                out[frame] += gain * value
                position += step
                frame += 1
            }
        }
        var room = Room(rate: Self.rate)
        for index in out.indices {
            out[index] += Self.wet * room.process(out[index])
        }
        // The last 0.3 s fade out, so the file ends in silence.
        let fade = Int(0.3 * Double(Self.rate))
        for index in 0..<fade {
            out[count - fade + index] *= Float(fade - index) / Float(fade)
        }
        let loudest = out.reduce(Float(0)) { max($0, abs($1)) }
        if loudest > 0 {
            let scale = Self.peak / loudest
            for index in out.indices { out[index] *= scale }
        }
        return out
    }

    /// `frames` as a 16-bit mono WAV file at ``rate``.
    public static func wav(_ frames: [Float]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(44 + 2 * frames.count)
        func word(_ value: UInt32) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)] }
        func half(_ value: UInt16) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }
        let data = UInt32(2 * frames.count)
        bytes += Array("RIFF".utf8); word(36 + data); bytes += Array("WAVE".utf8)
        bytes += Array("fmt ".utf8); word(16); half(1); half(1); word(UInt32(rate)); word(UInt32(rate * 2)); half(2); half(16)
        bytes += Array("data".utf8); word(data)
        for frame in frames {
            let value = Int16(max(-32767, min(32767, (frame * 32767).rounded())))
            half(UInt16(bitPattern: value))
        }
        return bytes
    }

    /// The frames of a 16-bit mono PCM WAV file at ``rate``, or `nil` for
    /// any other.
    static func frames(ofWAV bytes: [UInt8]) -> [Float]? {
        func word(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        func half(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        guard bytes.count >= 12, Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WAVE".utf8) else { return nil }
        var at = 12
        var format = false
        while at + 8 <= bytes.count {
            let tag = Array(bytes[at..<at + 4]), size = word(at + 4), body = at + 8
            guard body + size <= bytes.count else { return nil }
            if tag == Array("fmt ".utf8) {
                guard size >= 16, half(body) == 1, half(body + 2) == 1, word(body + 4) == rate, half(body + 14) == 16 else { return nil }
                format = true
            } else if tag == Array("data".utf8) {
                guard format else { return nil }
                return stride(from: body, to: body + size - 1, by: 2).map { Float(Int16(bitPattern: UInt16(half($0)))) / 32768 }
            }
            at = body + size + size % 2
        }
        return nil
    }
}

/// A small room: Freeverb's eight combs and four all-passes (Jezar at
/// Dreampoint's algorithm, public domain), mono, its delays scaled from
/// 44.1 kHz.
private struct Room {
    private var combs: [(buffer: [Float], index: Int, store: Float)]
    private var passes: [(buffer: [Float], index: Int)]
    private let feedback: Float = 0.80
    private let damp: Float = 0.3

    init(rate: Int) {
        let scale = Double(rate) / 44_100
        combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map { (Array(repeating: 0, count: max(1, Int(Double($0) * scale))), 0, 0) }
        passes = [556, 441, 341, 225].map { (Array(repeating: 0, count: max(1, Int(Double($0) * scale))), 0) }
    }

    mutating func process(_ input: Float) -> Float {
        let fed = input * 0.015
        var out: Float = 0
        for i in combs.indices {
            let delayed = combs[i].buffer[combs[i].index]
            combs[i].store = delayed * (1 - damp) + combs[i].store * damp
            combs[i].buffer[combs[i].index] = fed + combs[i].store * feedback
            combs[i].index = (combs[i].index + 1) % combs[i].buffer.count
            out += delayed
        }
        for i in passes.indices {
            let delayed = passes[i].buffer[passes[i].index]
            passes[i].buffer[passes[i].index] = out + delayed * 0.5
            passes[i].index = (passes[i].index + 1) % passes[i].buffer.count
            out = delayed - out
        }
        return out * 3
    }
}
