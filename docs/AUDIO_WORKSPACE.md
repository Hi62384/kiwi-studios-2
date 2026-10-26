# Audio Workspace

## Status

The implementation is applied for integration testing. This is **not a completed, qualified release of every item in the original 42-section specification**. Cloud tests use Godot 4.6.3 and an isolated fixture. The user's Windows Godot 4.6.1 integration, real recording devices, manual interaction, perceptual listening and full project regressions still require verification. See `audio_workspace_acceptance.md` for the remaining acceptance work.

## Opening and editing

Use the workspace tab's Audio entry, open WAV/MP3/Ogg/FLAC or an Audio document, or use **Edit in Audio Workspace** on a Scene audio actor. Scene binding lets **Update Scene Actor** replace that actor's audio through the existing Scene undo history. Other compositions use **To Scene** to create an actor. Save editable compositions as `.audio.tres`; audio exports are separate files.

The main timeline uses the existing ActorData/ActorClip source model and ActorAudioSystem playback. Select tracks, import or generate clips, move/trim them, use Alt-drag for slip and Shift-drag for stretching, and edit gain, pan, pitch, fades, looping, routing and effects in the inspector. Multiple selection supports common gain/pan/pitch/fades, relative movement, copy/paste, duplication, splitting, deletion and effect-chain batch application. The command palette lists actions and customizable shortcuts.

Double-click a clip for the detailed stereo waveform. Zoom to samples, select with zero-crossing assistance, edit either channel, or view a spectrogram. Gain, normalization, reversal, fades, silence and local repair create new source resources. Time stretching changes the selected region's exact frame count; pitch shift retains its length. Duration-changing edits require Stereo selection so channels remain aligned. Sources are never overwritten. Render in Place also joins selected clips, including their intended gaps. Freeze/Unfreeze keeps the original sources, note patterns and processing recoverable.

## Music and sound design

- 50 procedural sound-effect presets across 11 families use modal, FM, subtractive/noise, resonant, granular and sample techniques as appropriate. Granular processing requires a selected source sample.
- 21 editable instrument presets include synthesis, drums, sampler and multisample patches. Acoustic-like synthesized presets are approximations, not recordings of real instruments.
- Piano roll and step editor store actual notes, velocity, probability, ratchets, accents, pan and durations. Scale/chord highlighting, chords, harmonization, arpeggiation and humanization are editable operations.
- 16 procedural composer styles produce editable parts, harmony and arrangement sections. Parts/sections can be regenerated independently. Results are rule-based sketches, not a promise of human-level composition or acoustic realism.
- Layered sound design uses ordinary tracks and clips with the same processing/export engine. Composition presets preserve the entire layered design.
- MIDI files preserve note/event and tempo/meter-map data. Playback currently uses the project BPM; imported changing tempo maps are retained for export but are not rendered as a tempo-changing composition.

See `AUDIO_SYNTHESIS_MUSIC.md` for synthesis interfaces, parameters, determinism and examples.

## Processing and automation

The ordered catalog contains 56 processors. Native Godot monitoring is explicitly an approximation of the offline FFmpeg algorithms. An exact rendered preview uses the same graph as export. Effects include dynamics, multiband compression, EQ/filtering, delay/reverb, modulation, distortion, restoration, stereo processing, pitch/time and distance attenuation. Bypass, ordering, per-owner automation and source-preserving baking are supported.

Convolution accepts a user-supplied impulse response. Plate and spring processors generate deliberately labelled modeled responses; ping-pong echoes alternate between channels. Their actual FIR tap gain, channel behavior and tails have regression tests. High-quality pitch bend, independent formant shifting and automated time warping require an FFmpeg build with Rubber Band support. Missing backend support produces an error rather than silently substituting another process.

Gain/pan automation is sample evaluated offline. Supported effect commands are updated at a bounded maximum 50 Hz, at decoder frame boundaries. Long curves use an adaptive interval. LFO, envelope, random and step shapes generate editable automation points. Synthesis modulation is baked into generated audio. Unsupported arbitrary instrument/effect automation is rejected explicitly.

Important limits:

- Native compressor attack is capped at 2 ms by Godot. Native/offline pitch, reverb and dynamics need not sound identical.
- Time Stretch and Automated Time Warp effects process within a fixed clip slot; expansion can be truncated and contraction padded. Use timeline speed/duration or waveform time stretching for duration-changing edits.
- Abrupt large Rubber Band pitch changes can produce measurable spectral sidebands/phasiness. They have not received listening approval.
- The master safety limiter checks sample peaks. Lossy exports are decoded and re-rendered with headroom if needed. This is not a certified inter-sample true-peak limiter.
- Restoration is imperfect. Heavily clipped or pathological click-repair input can be very slow; jobs can be cancelled. Noise overlapping speech or reverberation cannot be perfectly removed.

## Dialogue, recording and analysis

Analysis provides sample/RMS peak statistics, transient and silence regions, correlation alignment and a tempo estimate with confidence. Review detections before applying undoable silence/pause edits or dialogue ducking. **Sample Noise** learns an actual 15-band spectral profile from a selected noise-only region. The denoiser's two-hop FFT latency is compensated so dialogue stays aligned. Integrated LUFS, true peak and loudness range use FFmpeg's loudness analysis rather than being inferred from RMS.

Recording reuses ActorAudioRecorder and its shared device/source settings. Countdown, latency offset, loop takes and keep/reject/choose operations are available. A stopped asynchronous take stays with the document where recording began. Device capture and monitoring still need Windows hardware testing; the automated recording-state test uses a simulated recorder and never activates hardware.

## Performance and safety bounds

- One cancellable background DSP/render worker; two bounded waveform-envelope workers.
- Multiresolution waveform cache: 48 MiB; generator preview cache: 48 MiB / 12 entries.
- Sample-edit working buffer: 128 MiB and normally 300 seconds per region. Large files use streaming export; waveform scrolling reads cached envelopes.
- Undo defaults to 64 actions with an estimated 256 MiB shared-PCM budget. Oldest undo actions are pruned immediately when needed; at least the latest action remains. This budget counts immutable PCM references without copying the buffers and is not a complete process-memory accounting.
- Instrument rendering has note/evaluation limits and cooperative cancellation. MIDI, long-file decoding, malformed documents and routing cycles have explicit validation.
- Exports refuse to overwrite an existing destination. Native saves use a temporary resource and recoverable prior-save backup. Temporary render jobs are cleaned up; deliberately bounced/frozen assets remain available.

## Verification evidence

The exact applied 56-effect cloud checkpoint ran 369 actual render cases: 368 successes and one minimum-threshold de-click stress case cancelled after eight seconds. Independent decoding found zero PCM/codec assertion failures, including exact durations, sample rates, stereo isolation, bypass, tails, routing, pitch preservation and determinism. Separate functional tests cover split/stretch note editing, source-window preservation through tempo changes, empty-pattern redo, atomic pattern-length undo and track-header selection. Windows execution remains pending: its source hash checks passed, then its RAM safety gate stopped at 704 MiB free before launching Godot.

Additional cloud tests cover document validation and source-preserving undo, real waveform pitch/time transformations, convolution response, loudness, learned-noise improvement, effect automation, recording/tab races, reversible freeze, and bounded undo retention. A suitable synthetic colored-noise fixture improved from 11.83 to 16.25 dB SNR after learned-profile processing and latency correction. These measurements do not constitute audible inspection.

Use `tools/verify_audio_workspace.ps1` for the memory-gated Windows integration checkpoint. It requires at least 2 GiB free RAM before each Godot process, limits each process to 180 seconds / 1.5 GiB working set, stops on low system memory or errors, and writes logs under `.godot/verification/audio_workspace`. Do not run it concurrently with other heavy project jobs.

## Optional external providers

Provider interfaces expose registration, cost estimation, explicit prompt/audio/cost consent and an injected credential-vault boundary. No concrete paid provider, credential vault, speech transcription or cloud generation service is configured. No keys are embedded, no authentication is changed, and no provider call is made by these interfaces alone.

## Primary implementation references

- [FFmpeg audio filter documentation](https://ffmpeg.org/ffmpeg-filters.html)
- [FFmpeg denoiser implementation](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_afftdn.c), used to confirm its FFT hop latency.
- [FFmpeg Rubber Band wrapper](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_rubberband.c), used to inspect runtime command behavior.

Note patterns retain source-relative notes when their timeline clips are split, trimmed, slipped or stretched. The piano roll shades the source region outside the selected clip’s window. Editing those notes preserves the clip window and stretch. The whole source remains recoverable; extending an untrimmed pattern expands its clip. Recent effects are ordered first in the effect browser.
