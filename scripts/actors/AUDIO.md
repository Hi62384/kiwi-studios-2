# Audio actors

Add an **Audio** actor and choose a project WAV, MP3, or Ogg Vorbis file. Its initial duration matches the source. Playback uses the timeline's play/pause control and mixes overlapping clips on different layers.

- Left trimming changes the source offset; right trimming changes the source end. Neither edge can extend beyond the file.
- Speed preserves the trimmed source interval and adjusts timeline duration. If a slower clip needs extra room, it moves to a free layer instead of overlapping another clip.
- Pitch is independent of speed, using a per-clip pitch-compensation effect. Volume and mute are also available; pitch, volume and mute support keyframes.
- Waveforms decode in background threads and use source time, including trims, speed changes, copies and splits.
- Inspector edits and timeline edits participate in undo/redo.
- Gold handles at the top edges adjust fade-in and fade-out. Their seconds are relative to the current timeline clip, and playback applies the resulting gain envelope.
- The microphone button (or **R** with timeline/scene-tree focus) starts recording. Stop it to create an embedded audio actor at the playhead position where recording began. The capture bus is muted so the microphone is not echoed through the speakers. Restart the application after enabling microphone input; Windows must permit microphone access.
- Recording starts playback and displays a growing temporary clip with live captured waveform peaks. Stopping pauses playback and commits the captured source as one undoable actor. The **▾ dropdown next to Record** opens persistent source, microphone device, input gain and mono/stereo preferences; changes apply to the next recording.
- Independent checkboxes select microphone audio, system audio, or both. Both sources are mixed into one recording, with sample-rate conversion and clipping protection. Windows system audio uses WASAPI loopback on the default output device through a hidden PowerShell/C# helper; it captures desktop output, including timeline playback. The helper writes only to a unique temporary capture directory and removes it on completion. Other platforms currently support microphone capture only.

The saved actor schema is `examples/audio_actor.tres`. Source loading and bounds are in `core/actor_audio.gd`; transport, mixing and waveform caching are in `core/actor_audio_system.gd`.
