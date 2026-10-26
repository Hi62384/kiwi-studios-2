# Audio synthesis, instruments, composition and MIDI

These modules render immutable completed PCM resources offline. The workspace must run expensive calls in its worker/cache system and use native Godot AudioStream playback. There is no GDScript real-time sample callback.

## Public interfaces

- KiwiAudioSynthesis.presets() -> Array[Dictionary]: 50 entries with id, label, category, description and parameters (id, label, default, min, max).
- default_settings(id), preset(id), generate(id, settings, seed_value=1, rate=44100).
- generate returns mono PCM16 WAV, or null for unknown IDs/missing required sample. Rate is bounded to 8–192 kHz; sound duration 0.03–60 seconds. Seed affects the variation and deterministic texture. Caller-owned resources are never mutated.
- layer(layers, rate) combines up to 32 PCM WAV/generated layers using start (seconds), duration, pitch (semitones), volume and pan. This convenience renderer is bounded to 60 seconds. Complex designs with effect stacks must use ordinary audio-document clips and the shared renderer, which owns effects/tails, rather than expecting this helper to process effects.
- variations(id, settings, seed, count, rate), save_preset(path, data), load_preset(path).
- KiwiAudioInstruments.presets(), default_instrument(id), midi_frequency(pitch), render_notes(notes, instrument, bpm, rate=44100).
- Notes: id, integer MIDI pitch, start/duration in quarter-note beats, velocity 0–1, pan -1–1. Optional enabled, mute, probability, accent, ratchets (1–8), and pitch_bend array of {time: beats from note onset, semitones}. Probability is seeded by instrument.seed.
- Instrument render returns stereo PCM16 with its release tail. It returns null for missing required samples, more than 8192 notes including ratchets, or a render longer than 300 seconds. For long arrangements, render bounded sections. A silent/empty arrangement returns a short silent stream.
- KiwiAudioComposer.generate(settings) -> {version,parts,sections,chords,settings}; regenerate(settings, previous, role="", section_id="") preserves every unrelated part/note/instrument/automation and custom section layout.
- Composer settings: style/genre, mood, tempo/bpm, key (name or 0–11), scale, duration (seconds) or bars, energy, complexity, repetition, variation, seed, time_signature [numerator,denominator], structure, progression (scale degrees), instruments by role.
- Theory helpers: scales, key_pitch, scale_pitch, quantize_pitch, chord, chord_suggestions, voice_lead, quantize_notes, humanize, arpeggiate, harmonize, new_note.
- Sequencing: drum_pattern(style,energy,complexity,fill,seed); pattern_notes(pattern,repeats,seed). Pattern stores steps, length in quarter-note beats, swing and lanes. Lane has pitch/mute/solo/values. Each cell is velocity or {enabled,velocity,probability,ratchets,accent}.
- KiwiAudioMIDI.read(path)/read_bytes(bytes) return an error string plus parts, tempo/time_signature defaults, tempos/time_signatures maps, ppq and warnings. write(path,parts,tempo,time_signature) -> Error and write_bytes return real MIDI bytes. Tempo may be a BPM number or the tempo-map array; meter may be [4,4] or a meter-map array. beat_to_seconds follows tempo changes.

## Sounds and instruments

All eleven requested SFX families have distinct representative presets: Impacts, Movement, Materials/Foley, Nature, Science Fiction, Magic/Fantasy, Horror, Cartoon/Comedy, User Interface, Music/Cinematic Transitions and Mechanical. A sample granulator adds an imported-sample family. The library uses modal resonances, layered pitched/noisy transients, filtered stochastic impulses, additive oscillators, PolyBLEP saw/pulse oscillators, FM, ring/AM movement and Hann-windowed source grains. Brightness applies a real output low-pass. Endpoints are faded and non-finite samples replaced; a peak-only safety scale leaves quiet dynamics intact.

Instrument IDs: piano, organ, bells, strings, brass, bass, lead, poly, pad, pluck, fm, additive, wavetable, chip, drums (also drum_kit alias), cinematic, sampler, drum_sampler, multisample, one_shot, loop_player.

The pluck uses Karplus–Strong feedback; the other synth modes use actual subtractive/FM/additive/table/modal implementations. Acoustic-like labels are stylizations. For acoustic realism, provide properly licensed samples. No VST, SoundFont or third-party instrument-library compatibility is claimed.

Sample settings use sample as an AudioStream or existing ActorAudio.source-compatible file path, root_pitch, one_shot, loop, loop_start/loop_end in seconds. Multisamples is an array of {sample,low,high,root_pitch,velocity_low,velocity_high}. Samples decode through KiwiAudioSourceCache once per render. Stereo remains independent. Sample-loop boundaries have a short crossfade, and note envelopes include release.

Electronic drum MIDI pitches: 35/36 kick, 38/40 snare, 42/44 closed hat, 46 open hat, 39 clap, 49/57 crash, 51 ride-like cymbal; other pitches produce tuned percussion, including 45 tom.

## Musical behavior

Sixteen styles differ through harmonic rhythm, progression choices, motifs, call/response, groove, orchestration, density, swing, section dynamics and arrangement structure. Ten scales are supported. Voice-leading selects compact inversions. Strong melody positions use chord tones; passing notes remain in the scale. Bass regeneration varies rhythms while preserving the existing chord map. Notes, drum patterns, harmony and sections stay editable. This produces structured sketches, not a promise of professional composition.

## Modulation and effects boundary

Synthesis/instruments accept modulators with kind lfo/envelope/random/step/velocity/automation, target pitch/amplitude/cutoff, amount, and rate. Step uses values; automation uses ordered {time,value} points in seconds. Instrument ADSR, filter resonance, detune, vibrato and stereo width are applied during synthesis. Clip/track effects and other automation belong to the shared audio-document/effects renderer. Stored instrument effects are metadata for that renderer, not silently applied by render_notes.

## MIDI compatibility and limits

SMF formats 0 and 1 with PPQ division are supported, including running status and velocity-zero note-offs. Writer emits type 1, 480 PPQ. Simultaneous equal-pitch notes use FIFO note pairing. Tempo changes, meters, channel programs, controllers, pitch bend and channel/poly pressure are preserved as part events. The basic instrument renderer does not interpret arbitrary MIDI controller/program event maps; the workspace must route/convert those for expressive playback. Per-note pan and bend cannot be losslessly expressed on one shared MIDI channel and are not invented as MPE.

Type 2 and SMPTE division are explicitly rejected. SysEx is skipped with a warning. Files are bounded at 32 MiB and one million parsed events. Malformed chunk sizes/VLQs/data fail explicitly. Third-party plugins, SysEx devices, MPE, arbitrary metadata and full MIDI device sequencing are outside this module.

## Validation

New scripts under scripts/actors/tests:

- audio_synthesis_test.gd: all 50 preset outputs, all 11 categories, distinct PCM, seed identity, pitch/brightness/density/distance controls, gain, variation, endpoint/peak safety, layer timing/stereo/source immutability, preset persistence and explicit failure cases.
- audio_music_test.gd: A4 frequency/onset, velocity, tempo, filter attenuation, FM controls, deterministic rendering, ADSR/release tail, all 21 instruments, sampler stereo, missing samples, all 16 styles, scale/timing constraints, partial regeneration preservation, changed harmony, non-4/4 meter, sequencer probability/ratchets/repeats.
- audio_midi_test.gd: note/overlap/velocity/channel/program/controller/bend/tempo/meter roundtrip, file I/O, beat-time conversion, running status, malformed/truncated/SMPTE input.
- audio_examples_test.gd: writes 39 representative 44.1 kHz WAVs plus editable four-bar electronic arrangement WAV/MIDI/JSON and a manifest. Default destination user://audio_test_collection; pass -- --out=PATH to override. The manifest does not claim auditory review.

Cloud Godot 4.6.3 isolated preflight passed the three regression suites. The fixture used the real shared source-cache module, direct-stream/PCM ActorAudio adapter and the exact ActorData ID factory. This is not Windows Godot 4.6.1 integration or UI verification. Acoustic listening remains separate from objective validation. Extreme FM/custom wavetable settings may alias; integer-delay pluck tuning is approximate at high pitches. No hardware-independent 60 FPS or professional-acoustic-quality claim is made.
