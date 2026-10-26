# Complete Audio Workspace acceptance checklist

Updated 2026-10-13. Status terms: **Implemented** means concrete source/UI functionality exists, **Partial** identifies remaining scope, and **Pending Windows** means source has not yet passed the user's complete local integration/hardware checks. Cloud evidence is not local verification. No listening approval has been obtained.

| Spec | Requirement | Current evidence / remaining acceptance |
|---|---|---|
| 1 | Inspect existing project | Existing audio actors, recorder, exporter, timeline, tabs, project instructions and shader/material edits inspected and preserved. |
| 2 | Register Audio Workspace | Implemented tab/open-file/Scene-context integration; Pending Windows. |
| 3 | Main interface | Native toolbar, library, timeline, inspector, waveform, piano, steps, effects, mixer, analysis; isolated functional tests pass; visual/manual acceptance pending. |
| 4 | Efficient UI | Search, shortcuts, command palette, drag/drop, inspectors and collapsible panels implemented; ergonomic acceptance pending. |
| 5 | Multitrack editing | Audio/instrument/group lanes, controls, routing, nondestructive clip operations and multi-selection implemented. Dedicated automation-track targeting remains partial; curves edit owners directly. |
| 6 | Waveform editor | Immutable sample edits, stereo/channel view, zero crossing, spectrogram, selection playback, pitch/time processing implemented and sample/frame tested. Long operations are bounded. |
| 7 | Effects library | 56 actual processors; convolution/Rubber Band conditional on backend. Dedicated Doppler/spatial preview and reliable dereverberation are not implemented. |
| 8 | Nondestructive effects | Clip/track/master stacks, bypass, reorder, copy/paste, presets, exact preview and bake implemented; native/offline differences disclosed. |
| 9 | Procedural SFX | Actual synthesis; deterministic presets and parameter tests; perceptual realism acceptance pending. |
| 10 | SFX families | 50 presets / 11 families; representative WAV collection exists in cloud evidence; actual listening pending. |
| 11 | Synthesis engine | Modal/FM/noise/resonant/granular/sample techniques, envelopes and modulation; no live per-sample synthesis loop in UI thread. |
| 12 | Generator controls | Editable parameters, seed, preview, variations and source-sample selection implemented. |
| 13 | Instant generation | Debounced background preview/cache, cancellation and generation guards implemented; laptop latency measurements pending. |
| 14 | Layered designer | Shared tracks/clips implement source/time/gain/pitch/effects/envelope/pan layers; composition presets and render. No incompatible second timeline. |
| 15 | Modulation/automation | Editable gain/pan/pitch and supported effect curves; LFO/envelope/random/step and baked synthesis/velocity modulation. Arbitrary instrument controls remain partial. |
| 16 | Music composition | Editable note patterns, instruments, MIDI and arrangements implemented. |
| 17 | Piano roll | Add/move/resize/delete/copy/paste, velocity, selection, zoom, scale/chord display; source-event tests pass, manual usability pending. |
| 18 | Step sequencer | Editable note grid, probability, ratchets/accent and beat-exact pattern buffers; timing tests pass. |
| 19 | Instruments | 21 synthesis/sampler presets, envelopes, root/loop/multisample mapping. Acoustic presets are models; realistic sample libraries are not supplied. |
| 20 | Music theory | Keys/scales, chords, harmonization, arpeggiation and humanization implemented. |
| 21 | Procedural composer | 16 styles, coherent rule-based harmony/rhythm/sections, partial regeneration and editable outputs; musical listening acceptance pending. |
| 22 | Asset browser | Search, categories, imported assets, duration, preview, favorites and recents implemented; wider project-folder indexing remains partial. |
| 23 | Presets | Generator, instrument, effect, pattern and composition resources; favorites and library restore; save/reopen tested. |
| 24 | Voice editing | Cleanup chains, real noise-profile learning, silence/pause edits, leveling/alignment/ducking, joining and batch FX implemented. Speech transcription and dedicated breath classification absent. |
| 25 | Optional AI providers | Partial: safe adapter/consent/vault-injection interfaces only. No concrete service, credential storage or paid call configured. |
| 26 | Mixer | Track/master faders, pan, mute/solo, group routing, sends, FX and level meters; exact preview handles sends; hardware/native behavior pending. |
| 27 | Mastering | EQ/dynamics/limiter/normalization, LUFS/true-peak analysis and optional export presets; output limiter is not certified inter-sample protection. |
| 28 | Recording | Existing recorder reused; countdown/takes/latency compensation and safe tab-switch state tested with a simulated recorder. Real Windows sources/devices/monitoring pending. |
| 29 | Smart edits | Transient/silence/tempo estimates, alignment, reviewed undoable pause edits, level matching and volume-curve ducking. Detection is heuristic. |
| 30 | Audio export | Real WAV 16/24/float32, MP3, Vorbis, FLAC, rates/channels/ranges/tails/stems tested with independent decoding in cloud. Windows codecs/backend pending. |
| 31 | Music import/export | MIDI SMF 0/1 PPQ supported. Type 2/SMPTE rejected; changing tempo maps preserved for export but constant-BPM playback is a remaining limitation. |
| 32 | Scene integration | Bound actor update/new actor render, shared source/playback/recording infrastructure and UndoRedo hooks implemented; actual full-project test pending. |
| 33 | Performance | Cancellable worker queue, waveform/preview caches, buffer/evaluation/undo limits and source identity reuse. Laptop CPU/RAM/audio glitch measurements pending. |
| 34 | Document and undo | Versioned resources, stable IDs, validation, immutable source sharing, atomic save/backup, bounded undo/redo tested. Split/stretch note edits, tempo changes, empty-pattern redo and pattern-length undo pass targeted source-event tests; Windows acceptance remains pending. |
| 35 | Efficiency features | Palette, shortcuts, favorites/recents, variations, FX copy/batch, repeat/duplicate, snapping, loops, selection render, bake/bounce, reversible freeze and nine templates. Recently-used effect ranking is persisted and tested. |
| 36 | Editing tests | Cloud sample editing, pitch/time, snapshot/clipboard/undo, graph routing, loops, codec durations and UI actions checked. Windows regression remains open. |
| 37 | Generation tests | Determinism, finite/nonclipping PCM, parameter differences, boundaries and example collection checked. Audible inspection remains open. |
| 38 | Music tests | Notes/pitches/timing/velocity/envelopes, key/scale, sections, partial regeneration and MIDI checked. Musical listening and full local playback pending. |
| 39 | Effects tests | Applied 56-effect snapshot: 369-case cloud sweep, 368 successful renders, one bounded repair cancellation and zero independent PCM/codec assertion failures. Windows sweep pending. |
| 40 | Integration tests | Isolated multi-document/save/reopen/UI/recording-state checks pass. Full local project, real devices, scene bindings and exports pending. |
| 41 | Shared architecture | 23 Audio modules plus scoped edits to existing actors/tabs/timeline; no duplicated incompatible engine. |
| 42 | Phased delivery | Phases 1–6 have substantial implemented functionality with the partial items above. Phase 7 local regression, listening, performance and final acceptance remains open. |

## Required release gates

- [ ] Run the guarded Windows checkpoint against Godot 4.6.1 with enough free memory.
- [ ] Fix every local parse/runtime failure and rerun relevant existing project regressions.
- [ ] Exercise real microphone/system/timeline recording and device selection without unexpected permissions.
- [ ] Inspect native UI at normal laptop resolution and test actual pointer/keyboard workflows when authorized tools permit.
- [ ] Listen to representative SFX/music, processor comparisons and restoration examples; objective statistics alone are insufficient.
- [ ] Confirm scene-bound actor updates and undo preserve existing video/shader/material behavior.
- [ ] Measure representative long-session, waveform and playback performance on the laptop.
- [ ] Resolve or explicitly accept every Partial item above; do not label the original full specification complete before this.
