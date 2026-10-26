# High-value remaining Audio Workspace work after batch 8

The available scope is 76 source files. This ranking proposes bounded next chunks; none was started during ledger consolidation. Native acceptance and current application status remain separate from source implementation.

## 1. Dry overdubs with independent backing monitoring

Value: high. Effort: medium. Best next bounded implementation.

Current evidence: scripts/actors/core/actor_audio_recorder.gd:30–69 uses record_timeline both to monitor timeline audio and include it in the recorded take. Lines 101–126 mix microphone, system and timeline streams. scripts/actors/core/editor_audio_settings.gd:7–14 exposes record_mic/system/timeline, device, gain and mono, without a separate backing-monitor choice. audio_workspace.gd:1696,1785–1800 prepares/starts backing only when record_timeline is enabled. The microphone bus is deliberately muted, avoiding speaker feedback.

Bounded chunk: explicit Hear backing versus Include backing in take settings within the available workspace preferences override, preserving existing defaults. Record a dry microphone take while monitoring the prepared/direct backing. Reject combinations with system loopback when a dry result cannot be guaranteed, because system loopback already includes monitored output. Do not add live microphone monitoring or claim latency compensation without hardware checks.

Dependencies: available actor_audio_recorder.gd, audio_workspace.gd, editor_audio_settings.gd, existing playback/backing classes. The missing shared editor_settings_button.gd is avoidable for a workspace-only control; changing the shared dropdown needs that file. Focused routing/lifecycle tests are possible in cloud; actual device separation, feedback and timing require authorized native acceptance.

## 2. Collect media into a portable composition copy

Value: high. Effort: medium-large, with a strict supported-reference inventory.

Current evidence: audio_document.gd stores external file strings in actor values and nested document metadata; snapshot() shares immutable resources rather than copying external assets. audio_instruments.gd:93–99 loads sampler and multisample mappings from sample paths. Batch5 relinks missing files, and batch8 checkpoints their references, but neither collects or versions external media. No collect-media workflow exists in the available source.

Bounded chunk: review an inventory of supported audio/sample/impulse/provenance paths, copy and deduplicate media into a new owned folder, rewrite only a cloned composition, validate the result, and publish the new composition atomically. Preserve windows, shared-source relationships and every non-destructive edit. Missing, unknown or unsupported references should refuse a purportedly complete portable copy; the originals remain untouched. Include cancel, collision, quota and source-change checks.

Dependencies: available document/workspace/source/instrument classes and file APIs; no Scene write is needed. Scope the first version explicitly to known audio reference schemas. Native path/dialog behavior and complete-project reopen still need acceptance.

## 3. Bound long captured takes and final recording mix memory

Value: high for long sessions. Effort: large; split capture storage from device acceptance.

Current evidence: actor_audio_recorder.gd:18–22,65–69 and80–85 create AudioEffectRecord accumulators. stop():101–126 retrieves complete recordings and mixes them; mix_streams():171–187 allocates a full output buffer plus whole-source data getters. Batch6 only streams prepared playback backing. Batch8 excludes in-progress capture and does not change this recorder memory behavior.

Bounded first chunk: introduce an owned disk-backed captured-take representation and bounded PCM finalization/mix path using existing PCM-file utilities, with explicit overflow/cancel/error handling and provenance. Do not silently replace all capture routing or promise crash recovery of active devices. Preserve present ActorAudioRecorder consumers or add a clearly versioned compatible path.

Dependencies: actor_audio_recorder.gd, windows_system_audio.gd, audio_pcm_file.gd, audio_workspace.gd and caller inspection. Changing the shared recorder contract may require the missing Scene/timeline integration files to audit all consumers. Core file lifecycle/mix tests are feasible in cloud; microphone/system/device dropouts, duration limits, latency and channel acceptance are native work.

## Acceptance and other substantial limits

The highest-priority non-feature task is the sole bridge's complete 76-file precondition check (six key hashes already match batch3), followed by the ordered pending application and bounded native import/module receipts. Full UI/tab/Scene/save, real-device audio, codec/listening parity and long-session acceptance remain incomplete.

Known additional limits are deliberate: batch7 dialogue analysis is whole-source, up to 600 seconds / 64 MiB, and its audition bypasses the track/master mix. Batch8 recovery is best effort, excludes active capture and unsupported embedded resource/audio formats, and leaves external assets referenced. Hardware MIDI input, automatic tempo-follow/warping/ramp workflows and a configured AI-provider adapter are not implemented by these batches. These are not reasons to expand the next chunk indiscriminately.
