import Foundation

// MARK: - Musical Tonality per World
//
// Each world has a key and scale. All tonal elements (bird chirps, cricket
// songs, frog calls) snap to scale degrees so the soundscape feels cohesive.
//
//   Night  → D Aeolian   (dark, warm, intimate)
//   Day    → G Lydian    (bright, open, dreamy)
//   Dusk   → Bb Dorian   (mysterious, warm tension)

enum Tonality {

    struct Scale {
        /// MIDI note number of the root in octave 1
        let root: Float
        /// Semitone intervals from root within one octave
        let intervals: [Int]

        /// All scale-tone frequencies between `lo` and `hi` Hz.
        func frequencies(from lo: Float, to hi: Float) -> [Float] {
            var result: [Float] = []
            for octave in 0..<10 {
                for interval in intervals {
                    let midi = root + Float(octave * 12 + interval)
                    let freq = midiToHz(midi)
                    if freq >= lo && freq <= hi {
                        result.append(freq)
                    }
                }
            }
            return result.sorted()
        }

        /// Snap a frequency to the nearest scale tone.
        func snap(_ freq: Float) -> Float {
            let midi = hzToMidi(freq)
            var bestDist: Float = .greatestFiniteMagnitude
            var bestMidi: Float = midi
            for octave in 0..<10 {
                for interval in intervals {
                    let candidate = root + Float(octave * 12 + interval)
                    let dist = abs(candidate - midi)
                    if dist < bestDist {
                        bestDist = dist
                        bestMidi = candidate
                    }
                }
            }
            return midiToHz(bestMidi)
        }

        /// Pick a random scale tone in a frequency range using a real-time safe RNG.
        func randomTone(in range: ClosedRange<Float>, rng: inout FastRNG) -> Float {
            let tones = frequencies(from: range.lowerBound, to: range.upperBound)
            guard !tones.isEmpty else {
                return snap((range.lowerBound + range.upperBound) / 2.0)
            }
            let idx = Int(rng.next() % UInt32(tones.count))
            return tones[idx]
        }
    }

    // D Aeolian (natural minor): D E F G A Bb C
    static let night = Scale(root: 26, intervals: [0, 2, 3, 5, 7, 8, 10])

    // G Lydian: G A B C# D E F#
    static let day = Scale(root: 31, intervals: [0, 2, 4, 6, 7, 9, 11])

    // Gmaj9 chord tones: G A B D F#
    static let dayChord = Scale(root: 31, intervals: [0, 2, 4, 7, 11])

    // Bb Dorian: Bb C Db Eb F G Ab
    static let dusk = Scale(root: 34, intervals: [0, 2, 3, 5, 7, 9, 10])

    // D minor pentatonic chord tones: D F G A C — dark, zero tension
    static let nightChord = Scale(root: 26, intervals: [0, 3, 5, 7, 10])

    // Bb major pentatonic chord tones: Bb C D F G — warm, zero tension
    static let duskChord = Scale(root: 34, intervals: [0, 2, 4, 7, 9])
}

// MARK: - MIDI / Hz conversion (file-private)

private func midiToHz(_ midi: Float) -> Float {
    440.0 * powf(2.0, (midi - 69.0) / 12.0)
}

private func hzToMidi(_ hz: Float) -> Float {
    69.0 + 12.0 * log2f(hz / 440.0)
}
