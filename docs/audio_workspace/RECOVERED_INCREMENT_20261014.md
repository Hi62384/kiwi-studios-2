# Audio Workspace recovered increment 01, guard revision 02 + region editing — 2026-10-14

This increment is reconstructed against the exact on-PC source recovered on October 14. The previous overnight cloud payload was unavailable; its old test totals and hashes do not describe this reconstruction.

## Delivered code

- Processed playback remains processed across seek and committed edits. Pending Play/Pause, Stop, Cancel Job and tab switches invalidate old render intent. Processed audio uses a dedicated output bus, avoiding double application of master effects.
- Export materializes current note/instrument/tempo/step signatures in an owned render snapshot, even when note preview jobs are still queued. Existing output files remain protected.
- Generator previews and comparison variations capture their settings, seed, identity and PCM together. Stale previews cannot be added with new metadata. Generator preset insertion and validated library drops use real synthesis.
- Mixer keyboard changes are dirty/undoable and preserve focus. A/B bypass restores the original enable mask. Master selection survives Undo.
- Waveform, piano, step view and right splitter state are per-document. Analysis actions reject replaced sources; source attack times map through clip start, offset, speed, reverse and looping.
- Native step controls expose count, straight/triplet division, swing, lane mute/solo and deterministic accent variation. The shared note renderer applies these controls for both previews and exports without changing editable notes.
- Full pattern presets retain notes, instrument, step settings, length and tags. Pattern library drops are a single Undo action. Bounded data-only JSON import/export refuses malformed data, script-bearing sample paths and overwrites.
- Composer controls expose role instruments and exact section names/start/length. Partial regeneration preserves split/slipped/stretched source windows and unrelated notes/automation. Missing sampler sources fail before document mutation.

## Recording preference correction in revision 02

The shared recorder now exposes a copied requested-preferences snapshot. The workspace checks this actual persisted/override preference before countdown, checks processing again before capture, and passes the same immutable settings to start. Stale runtime flags cannot bypass the refusal or incorrectly block a non-timeline take. Original increment 01 remains preserved but must not be applied.

## Follow-on production-only region editing

The waveform editor now decodes only the selected source frames, with a conservative 32 MiB temporary PCM budget. A source longer than 300 seconds is no longer rejected solely because a small selection lies inside it. Cut, paste, silence, gain, normalize, reverse, fades, repair, invert, mono and existing time/pitch transforms operate on the selected region. Clipboard data carries its sample rate; differing-rate paste uses linear interpolation. Trim changes source offset/duration without decoding or rewriting PCM.

Edited audio becomes a new embedded 16-bit WAV; untouched before/after regions remain adjacent clips pointing to the exact original source. They retain source windows, timeline positions, playback speed and layer. One session action replaces the original clip, so the existing undo machinery retains the original source. Actor hierarchy/section metadata is also retained by document snapshots. The PCM16 conversion scale now matches the decoder's 32768 divisor, avoiding a one-step loss when an unchanged PCM16 channel is re-encoded.

Source/geometry changes, locks, concurrent edits, incomplete decode and cross-document job completions prevent application. Reversed/looped clips, clip effects/automation/animation, nonunit clip pitch and editable instrument patterns require a rendered bounce before source-region editing. Track effects remain usable. Existing endpoint fades are preserved when they fit the outer pieces; a splice crossing a fade is refused rather than restarting its envelope silently.

No tests, test sources, parsing, compilation, app launch or device checks were performed for this integration, following the user's latest instruction. The separately preserved helper had older parse-only results, which do not validate this integrated revision.

## Follow-on production-only processed recording

Processed timeline recording now has a preparation stage instead of immediately refusing offline effects/reverse/sends. It uses the existing renderer and job queue before opening recording devices, then sends the prepared PCM through the existing exact-playback bus into the shared recorder's timeline capture bus. With system loopback selected, it sends to Master and relies on the existing recorder's single system-capture path, avoiding an additional duplicate timeline capture.

Preparation and countdown carry an owning session, generation, immutable requested device preferences and an audio-content signature. Stop, a second Record/Play press, Cancel Job and tab changes invalidate pending starts. Device startup remains busy until an asynchronous cancellation returns and is cleaned up. Changes to the arrangement during preparation/startup prevent a stale take from beginning. A processed take uses a frozen prepared mix; edits during that capture affect subsequent takes. A seek outside its prepared range stops the take rather than silently switching to unprocessed playback.

Loop takes reuse unchanged prepared audio, with owner/generation checks on deferred restart. Recorded timeline-mix takes begin muted so subsequent passes do not record the previous mix again; the Takes browser can preview or explicitly choose them. Each saved take still uses one undo action, and a take finishing after a tab switch belongs to its originating document. Device teardown/restart between loop takes is not gapless.

Prepared stereo PCM is limited to 64 MiB (roughly six minutes at 44.1 kHz), including a conservative tail estimate and a completed-file size guard before loading. Longer processed ranges need a shorter loop selection or prior bounce. This bound excludes existing source resources, decoder/renderer internals, and the recorder's growing captured take; long hardware recordings can still use substantial memory. Temporary prepared files are private to each job and removed after loading or failure.

This is newly written production code only. No tests, test files, parsing, compilation, app launch, listening or device checks were performed for this increment. Hardware permissions, latency, capture quality and actual Windows codec behavior remain unverified.

## Historical focused verification

These results belong to the earlier checkpoints described below, not the final region-editing integration.

Godot 4.6.3 Linux, isolated copied runtime fixture with neighboring application services explicitly stubbed. This is not a full Kiwi app/device test:
- Module loading: zero failures.
- Transport/current-note/export-safety: 22 assertions, zero failures, rerun on revision 02.
- Recording preferences: 9 assertions, zero failures on revision 02. Uses actual recorder code with hardware/settings services explicitly stubbed; no device recording claimed.
- Prior increment 01 generator/undo/mixer/view state: 16 assertions, zero failures.
- Prior increment 01 music controls/presets/composer atomicity: 42 assertions, zero failures.
- Prior increment 01 native workspace-widget functional smoke: zero failures.

No listening, Windows codec/device, full app, native GUI or performance acceptance is claimed. The user's reduced-testing request leaves those checks to interactive use.

## Known limits and next increment

- Processed timeline capture is now implemented through prepared playback and the existing recorder, but has not been run or device-verified. Preparation/device errors remain visible and do not create a take.
- Region-edit buffers are capped at an estimated 32 MiB. Oversized selections are refused with a shorter-region instruction; this is not unlimited whole-file DSP. The existing waveform envelope cache is bounded and generated in background chunks, but source-loader resources, decoder internals, undo-retained resources and FFmpeg memory are separate from this edit budget. Large WAV/FLAC sources may still load whole-file resources.
- Processed regions are 16-bit; higher-resolution sources can quantize within the processed selection. Untouched source bytes/references are preserved. Compressed seek accuracy and audible joins, especially with nonunit playback speed, remain unverified. Other timeline clips are not rippled by cut/paste; only the edited clip and its new adjacent pieces change.
- Dedicated automation-track target controls, source-cache memory improvements, encoder cancellation cleanup and stable scene-tab callback identities remain unfinished.
- Full-app loading is deferred until its transitive resource/static-initializer execution scope is reviewed. This package does not run the full project.
- The captured project class cache contains no Audio Workspace classes. Open the project normally in the Godot editor so its normal filesystem scan registers the audio scripts before testing. Do not manually overwrite unrelated generated cache entries.
- Procedural acoustic-like patches are synthesized approximations. No trained AI provider call, credential setup, paid service, neural denoising or high-quality source separation is implied.

## Suggested interactive check

Open an Audio tab after Godot's normal script scan. Generate a sound, compare a variation, add it and Undo/Redo. Edit a note pattern and export immediately. Try swing/lane mute and compare playback with export. Save/import a pattern JSON. Regenerate one composer role or section after splitting a clip. Seek while an offline effect is active. Move a mixer fader with arrow keys, switch tabs and reopen a saved composition.


## 2026-10-14: linked automation lanes (production increment 01)

Source-only implementation; no tests, test-file creation, parsing, compilation, application/device launch or listening was performed for this increment. Historical checks elsewhere in this document do not validate this code.

- Add Track → Automation lane opens a searchable list of existing clip, track, master and supported effect parameters. An existing automation editor also has **Show in timeline lane**.
- Each lane stores stable owner/effect identifiers and a parameter name. Its displayed points are the original owner’s curve, shared by existing native playback and offline export. There is no duplicate automation renderer, independent copy or silent override.
- Timeline lanes draw the linked curve with its actual linear/smooth/hold interpolation. Ctrl-click adds a point, dragging changes its time/value, right-click removes a point, double-click opens the curve editor. Changes commit as an undoable action when a drag ends. Lane header E opens the editor, T retargets, L locks editing.
- The curve editor includes interpolation, a view range and editable deterministic sine/triangle/saw/square/random-step/envelope modulation. Existing 10,000-point document and 4,096-segment generated-modulation bounds remain in force. Curve display uses bounded visible-width sampling with binary point lookup.
- A clip lane uses local clip time plus the clip start when drawn. It follows clip moves by stable ID; track/master curves remain absolute-time curves. Splitting keeps the lane attached to the original clip ID; the split child retains the existing shifted-curve behavior and can receive a separate lane.
- Retargeting or deleting a lane leaves its source curves intact. Missing clip/effect targets remain visible and reconnectable; Undo can restore their original source. Lane and owner locks both prevent point edits. Changing the target makes an already-open old editor read-only, and lane dialogs close when switching documents.
- Empty display lanes are excluded from mixer strips and stems. They cannot accept audio drops, source imports, pasted/moved clips, recording takes or new send/output routes. Their curve still acts on the selected source’s original audio path. Legacy automation tracks containing audio/routing/processing are preserved and require explicit conversion back to an audio track before being repurposed.

Limits: no latch/touch/write recording of live parameter gestures; point changes become active on commit. Instrument-specific controls still use the existing baked note modulation workflow. Existing native/offline algorithm differences, Rubber Band requirements for clip pitch, and effect-command update limits remain. Full-app class registration and usability are unverified under the current no-tests instruction.

## 2026-10-14: scene-return and close-dialog identities (production increment 01)

Source-only implementation, with no tests, parsing, compilation or application execution.

- Audio tabs now receive stable in-memory document IDs and retain their originating scene ID. Returning rendered audio resolves that exact scene ID after tabs close or reorder; a stale numeric tab position is never used as the destination.
- When the original scene is closed or unavailable, a destination dialog requires an explicit choice of an existing scene or a new scene. It creates a new audio actor rather than silently updating an actor in some other scene. If the original actor was deleted, the same explicit placement choice is offered.
- Successful replacement still uses the existing scene model’s audio snapshot/restore UndoRedo methods. A chosen replacement destination can rebind the source audio tab to the newly created actor. Unrelated scene, image and shader implementations are unchanged.
- Unsaved-audio Save/Discard callbacks resolve the original audio document ID when they run, including after an asynchronous save dialog. They inspect the captured source session’s dirty state, so switching to a clean tab cannot cause the wrong unsaved composition to close.

Limits: scene/audio tab identities and bindings are in-memory UI state; this does not add cross-application-restart scene-link persistence. Full SceneTabs dependency loading and native dialog/Undo behavior remain unverified under the no-tests instruction. No generated class-cache metadata was edited.


## 2026-10-14: bounded project audio indexing (production increment 01)

Source-only implementation; no tests, parsing, compilation, audio processing or application launch.

- The Audio Library has opt-in project-folder sources, refresh/stop controls and a Project category. Only selected res:// folders are traversed; .godot, .git and linked path components are excluded.
- One cancellable background worker reads metadata headers rather than decoding every asset. A scan is limited to 2,048 indexed assets, 512 directories, depth 16, 20,000 visited entries, 16 MiB cumulative header reads and a cooperative 15-second budget. A stalled filesystem operation itself is not interruptible by that budget; linked-component checks are best effort, not a race-proof filesystem sandbox.
- WAV/FLAC header durations are marked estimates. MP3/Ogg durations remain unknown until the shared scene audio loader is used. Missing, unreadable, blocked and unverified entries are distinguished; a clipped scan does not pretend an unvisited asset was deleted.
- Indexed preview/add/drop paths recheck readability and scope. Workspace inspector previews use the same entry guard. Intentionally imported local assets keep their previous behavior, including when also discovered in an indexed folder.
- Source paths participate in search. Stable asset IDs preserve favorites and recents; settings saves reload and change only the requested field, preserving unknown keys and other project source lists. Indexed results are rebuilt; the chosen project folder list is persisted. No audio files are copied, modified or removed by indexing.

Limits: no waveform/audio decoding is performed by the index. It is a bounded refresh-based browser, not an operating-system file watcher or unlimited recursive catalog. Actual Godot UI/threading and Windows filesystem behavior are unverified under the no-tests instruction.


## 2026-10-14: source timing, cache ownership and Doppler (core production increment 01)

Source-only implementation. No tests, parsing, compilation, application/native/device runs, synthesis, rendering or listening were performed. Exact file hashing and source readback establish delivery only. These source features remain unverified at runtime.

### Imported MIDI timing and preset integrity

New MIDI note sources retain immutable per-source tempo/meter maps and editable note beats. Shared instrument rendering maps both note boundaries through that source map, so preview and offline audio export use the same changing tempo. Project BPM edits uniformly scale the map and existing clip/source windows; frozen sources stay audio. Wrapped-loop piano-roll shading uses inverse map timing.

Pattern preset capture, JSON and apply preserve per-source timing. Ordinary presets clear stale MIDI timing/channel metadata instead of accidentally inheriting a previous import. Tempo/meter arrays are strictly validated and bounded to 4096 entries each; imports and serialized documents bound per-source and aggregate map, note and channel-event copies before snapshot/render. The existing undo budget now includes conservative snapshot-specific nested metadata charges while retaining shared-PCM identity deduplication; it is estimated accounting, not measured RSS, and always retains the newest action.

MIDI export remains source-pattern export at the existing 480 PPQ. It rejects incompatible source tempo/meter maps instead of pretending the sources share one conductor. Timeline clip placement/trims/speed/loops/effects are not flattened into MIDI. Grid/metronome/arrangement guides remain project-BPM based, and full MIDI controller playback is still absent. Ambiguous older imports need reimport for source-map playback. Existing 300-second, note/evaluation and sampler requirements still apply.

### Source retention and waveform loading

The shared ActorAudio cache uses conservative 64 MiB strong-retention accounting plus a 32-entry ceiling, LRU eviction and weak identity for active oversized streams. One-second metadata throttling avoids reopening source files on every lookup; explicit invalidation advances generations so an obsolete in-flight load cannot repopulate the cache. Active caller/player/document/decoder memory is outside that cache accounting.

Timeline waveform requests look up path/version keys before decoding and perform misses in existing background envelope workers. This prevents paused redraws from repeatedly reopening a large weak-only source. Duration lookups reuse measured metadata. FLAC completed decode files use content-digest keys, including safe concurrent promotion reuse. FLAC disk-cache storage is separate and is not globally disk-bounded by this change.

### Encoder lifecycle and publishing

The shared owned encoder helper replaces ad-hoc renderer cancellation. It sends FFmpeg a private-pipe quit request, drains bounded diagnostics, makes at most one owned-child forced termination attempt, closes both pipe objects, and preserves staging with a diagnostic when exit cannot be confirmed. Analysis and FLAC consumers use the same cleanup result. Completed exports publish through an owned sibling staging file after cancellation/destination checks; pre-existing destinations are rejected.

Polling, shutdown and log buffers are bounded, but synchronous engine process/kill/filesystem calls cannot be forcibly timed out from GDScript. Godot 4.6 Windows process registry handles after natural completion are an engine limitation; pipe closure does not establish native-handle reclamation. No post-exit unrelated PID kill is attempted. An unrelated external writer can still race the final existence-check/rename because Godot has no atomic no-replace rename API. See the source delivery notes for exact budgets and platform limits.

### Doppler processor

The effect catalog now includes an offline Doppler processor. It solves source emission/receiver arrival timing for a bounded subsonic pass, then performs streamed sinc resampling, distance attenuation, stereo balance and dry/wet blending. This creates an actual radial pitch/delay change rather than a pan-only approximation.

Clip, track and master chains stage their complete upstream float32 signal at each Doppler, process it, then continue the remaining ordered effects. Static geometry, ordinary bypass and derived propagation tails use the same helper. Each accepted stage is limited to 512 MiB and retained job intermediates to 2 GiB. Processing has a cooperative 60-second budget and may require shorter regions. Existing upstream graph branches may be reevaluated, so offline cost can rise with multiple Dopplers.

No realtime Doppler, live parameter automation, HRTF/binaural simulation, reflections, air absorption, supersonic movement or measured acoustic quality is claimed. Disk/decoder/OS stalls are outside cooperative timing guarantees. FFmpeg and full native app integration still require the user's normal environment; no new dependency was installed and no generated class cache was edited.


## 2026-10-14: finite completion-source increment (cloud only)

This later source package depends on the full intended core increment. Its predecessor is currently only 11/17 applied locally after a cancelled source-cache write; six exact baseline files remain held. Do not launch that partial checkout. No tests, test sources, compilation, app launch or audio processing was performed for these changes. Historical checks above do not validate them.

### Live automation gestures

An explicitly armed owner parameter can use Read, Write, Touch or Latch. The existing owner curve remains the sole persistent automation data. A toolbar control, matching mixer gain/pan controls and linked-lane target controls record a bounded pass; Stop/Finish commits one Undo action. Owner/lane locks, stale document revisions, session switching, seek, loop wrap and Undo have explicit lifecycle handling. Capture is at most 30 Hz, 2048 retained points, 64 gestures and one hour. Pending capture is discarded with a visible status if an unrelated edit invalidates it; use Finish first to retain it. Native track/master monitoring uses a temporary playback snapshot. Clip/effect and already-rendered exact playback are explicitly capture-only until replay. Punch guards and decimation are approximations, not sample-accurate control-surface capture.

### Project conductor and explicit source retime

A bounded tempo/meter editor stores project conductor points in the resource and applies edits as one Undo action. Timeline beat/bar grid, snapping, bar/beat transport and live/exact-preview metronome share its step-tempo map. Grid BPM and conductor edits preserve absolute clips and source-relative note/MIDI timing; this is not nonlinear audio warping. A separate Uniformly Retime Notes action scales editable note sources and MIDI maps under source/range guards, skipping locked/frozen tracks. Source BPM/meter persists through presets, source-window shading, preview/export, and composer regeneration. Existing imported source maps and constant-tempo composer sections remain independent from project points. Generated modulation Beat sync still bakes at the initial BPM; existing curves remain absolute-time data.

### Durable scene/audio links

A bounded exported association stores scene identity/path and actor ID and participates in document Undo. Scene saves preserve that identity; reopening both saved resources can resolve the original actor without relying on tab order. Scene Save As updates matching open audio associations and marks them unsaved without rewriting their files. Rendered actors receive a backlink when sent from a saved editable composition; the explicit Scene Edit Audio command can reopen it. Missing/moved files, duplicate identities and deleted actors require explicit relinking. Save the composition before sending, then save the scene and any changed association. Saves/Undo remain separate across workspaces; no implicit resource opening or project-wide atomic save is introduced.

See SOURCE_DELIVERY_20261014.md and the sealed source notes for current capability and native-acceptance limits. The original full specification is not declared verified or completely accepted.
