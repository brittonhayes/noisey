# Sound Design for Noisey

Generative ambient sound design philosophy inspired by Disasterpeace's work on Mini Motorways. Use this as a creative brief when designing new procedural sounds or iterating on existing ones.

---

## Philosophy

### Environment as Conductor

In Mini Motorways, gameplay drives the music. In Noisey, **absence of interaction is the goal** — the soundscape should feel alive on its own, like sitting by a pond at dusk. No scripted sequences. Emergent behavior from simple rules interacting.

### Success Through Absence

A good ambient soundscape is one where individual events dissolve into a wash. Discrete events (a frog croak, a bird chirp) should be noticeable but never jarring. The ideal state is what Disasterpeace calls "highway white noise" — continuous vehicle movement producing ambient texture rather than distinct sonic events.

### Musicality Over Immediacy

Events should be quantized to a beat grid for musical feel, even if no one consciously hears the pulse. The frogs use 60 BPM / 16th-note quantization. This creates a subtle groove that the listener feels rather than hears. Disasterpeace delayed car horns to land on-beat — we do the same with croaks.

### Harmonic Cohesion via Scale Snapping

All pitched elements snap to world-specific scales defined in `Tonality.swift`. No random frequencies — even "natural" sounds pick from curated pitch sets. The three worlds:

- **Night** — D Aeolian (dark, warm, intimate)
- **Day** — G Lydian (bright, open, dreamy)
- **Dusk** — Bb Dorian (mysterious, warm tension)

Chord subsets (e.g. `duskChord` = Bb major pentatonic) further constrain creature pitches to zero-tension intervals: roots, 5ths, and 9ths only.

### Common Tone Movement

When harmony changes (chord drone progressions, key shifts), maximize shared tones between adjacent chords. Disasterpeace's Common Tone Chord Network defaulted to `MaxGroups - 1` common tones — most notes stay, one or two move. This makes transitions feel inevitable rather than jarring. The `ChordDrone` in EveningFrogs pins Bb and F while only the top voice floats.

### Emergent Rhythm Through Probability + Momentum

Don't script patterns. Give each voice a **density** (probability of firing per beat) and let **cross-species momentum** create call-and-response. When one species croaks, it boosts the probability that *other* species respond. The pattern is never the same twice, but it always sounds like a conversation.

### Distance as a Design Axis

Per-voice LP cutoff + gain randomization simulates near/far placement. A sound with 3-6 voices at varying distances feels like a **field**, not a point source. Close voices are bright and loud; distant voices are dark and quiet. This is how 6 sine oscillators become a pond full of frogs.

### Envelope Shapes Carry Character

The envelope IS the timbre for simple oscillator-based sounds:

- **Fast attack + long exponential decay** = nostalgic, fairy-chime, Zelda-like (morning birds)
- **Fast attack + settle + plateau + gentle release** = warm, natural, organic (frog croaks)
- **Slow attack + sustained + slow release** = pad-like, ambient (chord drones)

### Layered Composite Sounds

Most convincing sounds are 3-4 layers, not a single generator:

1. **Ambient fill** — filtered noise (wind, water texture)
2. **Harmonic bed** — slow chord drone underneath
3. **Creature calls** — the featured voices
4. **Detail/shimmer** — high-frequency texture or occasional bright accents

Naked creature calls feel thin. The bed and fill give them a world to live in.

### Subtle DSP for Life

Synthetic tones become organic with small imperfections:

- **Vibrato**: 8-16 cents depth, 0.4-0.9 Hz rate (per-voice randomized)
- **Detuning**: +/-5 cents per voice (fixed at init, simulates natural pitch drift)
- **Slow filter modulation**: SmoothedRandom LFOs on cutoff frequencies
- **Gain variation**: Per-event random gain within a range (distance/energy variation)

---

## Practical Patterns

### Voice Architecture

Each creature type gets 2-3 voices at varying "distances":

| Tier | LP Cutoff | Gain Range | Character |
|------|-----------|------------|-----------|
| Close | 500-900 Hz | 0.2-1.0 | Bright, present, full dynamic range |
| Mid | 350-700 Hz | 0.1-0.5 | Softer, filtered, moderate variation |
| Far | 150-500 Hz | 0.05-0.3 | Dark, quiet, narrow dynamic range |

Reference: `FrogVoice` init params in `Generators.swift:622-646`

### Beat Grid

Quantize events to a musically useful grid:

- **Tempo**: 60 BPM (one beat per second — natural, breathing pace)
- **Grid resolution**: 16th notes = 11,025 samples at 44.1kHz
- **Why 60 BPM**: Matches resting heart rate. Feels unconsciously natural for sleep/relaxation content.

### Density + Momentum System

Each voice has a `density` — probability of firing on any given beat:

- **Sparse** (peepers, rare events): 0.02-0.03
- **Moderate** (treefrogs, backbone voices): 0.04-0.05
- **Active** (dominant species): 0.05-0.08

Cross-species momentum creates call-and-response:
- When a voice fires, boost momentum for *other* species by ~0.5
- Decay all momentum channels by 0.65x per beat
- Effective density = base density + (momentum * 0.25)

Reference: `Generators.swift:650-669`

### Pitch Selection

Always use scale-snapped pitch selection:

```
Tonality.<world>Chord.randomTone(in: freqRange, rng: &rng)
```

Never generate raw random Hz values. The chord subset scales ensure zero-tension intervals. Each species occupies a distinct frequency band with minimal overlap:

- **Low** (bullfrog-like): 100-350 Hz
- **Mid** (treefrog-like): 400-800 Hz
- **High** (peeper-like): 800-1400 Hz

Reference: `Tonality.swift:54-61`

### Envelope Template

The standard creature call envelope (adjust ratios per character):

```
[0-8%]   Fast attack — ramp to 1.0
[8-20%]  Settle — ease down to 0.6
[20-75%] Plateau — sustain at 0.6
[75-100%] Release — linear fade to 0.0
```

Reference: `Generators.swift:593-605`

### Harmonic Bed

A `ChordDrone` or equivalent pad underneath creature calls:

- 2-3 sine tones with harmonics (fundamental + 2nd + 3rd partial)
- Slow chord changes every ~16 seconds
- Volume breathing via slow cosine LFO (~25 second cycle, range 0.5-1.0)
- Double LP filter for warmth (400 Hz cutoff)
- Portamento/glide between chord tones (0.3s coefficient)
- Pin the bass and fifth — only move the color tone

Reference: `Generators.swift:426-509`

### Ambient Fill

Pink or white noise filtered to a frequency band (wind, water texture):

- Band-pass via HP subtraction + LP cap (e.g. 300-1200 Hz for breeze)
- Very slow amplitude LFO: SmoothedRandom at 0.02-0.08 Hz
- Amplitude range: 0.02-0.06 (barely there — felt not heard)

Reference: `Generators.swift:410-414, 671-676`

---

## Anti-Patterns

- **Don't script sequences** — use probability and momentum for emergent patterns
- **Don't use raw frequencies** — always snap to the world's scale/chord
- **Don't make all voices equidistant** — vary LP cutoff + gain for spatial depth
- **Don't skip the harmonic bed** — naked creature calls feel thin and synthetic
- **Don't over-quantize** — the grid should be felt, not heard
- **Don't crowd the spectrum** — 2-3 species with clear frequency band separation
- **Don't make events too loud or too frequent** — discrete events should dissolve into the wash
- **Don't use uniform randomness** — SmoothedRandom with slow rates creates natural drift, not chaos

---

## Designing a New Sound: Checklist

1. **Pick the world** — which Tonality scale/chord does this belong to?
2. **Define species** — 1-3 creature types with distinct frequency bands
3. **Set distance tiers** — 2-3 voices per species at close/mid/far
4. **Choose density** — how active is each species? Start sparse, increase if needed
5. **Design the envelope** — what character should the call have?
6. **Build the bed** — chord drone with slow movement, volume breathing
7. **Add ambient fill** — filtered noise for texture
8. **Wire momentum** — cross-species call-and-response
9. **Season with DSP** — vibrato, detuning, per-croak gain randomization
10. **Listen and subtract** — remove elements until only the essential remain
