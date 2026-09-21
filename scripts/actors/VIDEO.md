# Video actors

Video decoding uses FFmpeg and FFprobe, discovered on PATH. Optional Godot project
settings `kiwi/media/ffmpeg_path` and `kiwi/media/ffprobe_path` can specify executable
paths. No shell command strings are used; filenames are passed as separate arguments.

Supported container extensions: MP4, MOV, MKV, WebM, AVI, M4V, OGV, MPEG, MPG, WMV,
and TS. Actual codec support depends on the installed FFmpeg build.

The source video stays unchanged. Clip source offsets preserve left trims, and
source duration bounds both edges. Preview frames are 720-pixel-wide, 24 fps JPEGs,
decoded on demand in ten-second windows under `user://video_cache`. At most two
decode processes run concurrently; decoded textures have a bounded memory cache.
Preview processes are stopped when the editor exits. This is a preview backend,
not a native full-resolution export pipeline.

A source containing audio creates an independently editable Audio child. Extracted
PCM audio is embedded in the child resource. `Linked Audio Actor` identifies the
owned child: replacing the source deletes that child and creates a replacement.
Clearing the reference unparents and releases the old child without deleting it.
`Create Audio` extracts another child if the source has an audio track.

Video actors start with children collapsed and linked. The scene-tree chain switch
links timeline movement/trimming to direct children, recursively through linked
children. Hidden children participate too. Collapse and chain switches appear only
on actors with children. Link state, clip edits, creation, replacement, extraction
and recreation participate in undo/redo; decoded preview cache contents do not.
