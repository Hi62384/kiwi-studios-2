class_name KiwiAudioAnalysis
extends RefCounted
## Lightweight deterministic analysis. Estimates are labeled and editable.
const MAX_FILE_SOURCE_SECONDS := 86400.0
const MAX_FILE_ANALYSIS_SECONDS := 7200.0
const MAX_FILE_ANALYSIS_BINS := 720000
const MAX_SILENCE_REGIONS := 2048
const MAX_FILE_TRANSIENTS := 65536
const FILE_TEMPO_SECONDS := 60.0

# File-backed dialogue detection reads only the requested source window. Its
# timestamps remain source-relative and duration remains the FULL file length,
# as required by SilencePlan. The legacy stream path below is still available.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_analysis")

static func analyze_source(value: Variant, threshold_db: float=-42, minimum_silence: float=.25, job: RefCounted=null, start: float=0., duration: float=-1.) -> Dictionary: return _native().call("analyze_source", value, threshold_db, minimum_silence, job, start, duration)

static func _analysis_file_signature(path: String) -> Dictionary: return _native().call("analysis_file_signature", path)

static func _pcm_file_current(path: String, info: Dictionary, file: FileAccess=null, inspect_header: bool=false) -> bool: return _native().call("pcm_file_current", path, info, file, inspect_header)

static func _analyze_pcm_file(path: String, info: Dictionary, threshold_db: float, minimum_silence: float, job: RefCounted, start: float, duration: float) -> Dictionary: return _native().call("analyze_pcm_file", path, info, threshold_db, minimum_silence, job, start, duration)

static func _finish_pcm_analysis(energies: PackedFloat32Array, first: int, total: int, rate: int, source_duration: float, peak: float, sum_squared: float, threshold_db: float, minimum_silence: float, job: RefCounted) -> Dictionary: return _native().call("finish_pcm_analysis", energies, first, total, rate, source_duration, peak, sum_squared, threshold_db, minimum_silence, job)

static func analyze(stream: AudioStream, threshold_db: float=-42, minimum_silence: float=.25, job: RefCounted=null) -> Dictionary: return _native().call("analyze", stream, threshold_db, minimum_silence, job)

static func nearest_zero(samples: PackedVector2Array, at: int, radius: int=256, channel: int=-1) -> int: return _native().call("nearest_zero", samples, at, radius, channel)

static func edit(samples: PackedVector2Array, operation: String, first: int, last: int, amount: float=1., channel: int=-1, clipboard: PackedVector2Array=PackedVector2Array()) -> PackedVector2Array: return _native().call("edit", samples, operation, first, last, amount, channel, clipboard)

static func alignment(reference: PackedVector2Array, candidate: PackedVector2Array, rate: int, max_offset: float=2.) -> Dictionary: return _native().call("alignment", reference, candidate, rate, max_offset)

static func spectrum(samples: PackedVector2Array, first: int=0, size: int=1024) -> PackedFloat32Array: return _native().call("spectrum", samples, first, size)

static func spectrogram(stream: AudioStream, start: float, duration: float, columns: int=256, rows: int=128, job: RefCounted=null) -> Dictionary: return _native().call("spectrogram", stream, start, duration, columns, rows, job)

static func remap_edit_boundary(position: float, first: float, last: float, inserted: float) -> float: return _native().call("remap_edit_boundary", position, first, last, inserted)

static func loudness(source: Variant, job: RefCounted=null) -> Dictionary: return _native().call("loudness", source, job)

static func transform_selection(samples: PackedVector2Array, operation: String, first: int, last: int, amount: float, channel: int, rate: int, job: RefCounted=null) -> Dictionary: return _native().call("transform_selection", samples, operation, first, last, amount, channel, rate, job)

static func noise_profile(stream: AudioStream, start: float, seconds: float, job: RefCounted=null) -> Dictionary: return _native().call("noise_profile", stream, start, seconds, job)

static func silence_boundary_audio(value: Variant, boundary: Dictionary, job: RefCounted=null) -> Dictionary: return _native().call("silence_boundary_audio", value, boundary, job)

static func _silence_audition_windows(boundary: Dictionary, speed: float) -> Dictionary: return _native().call("silence_audition_windows", boundary, speed)

static func _pcm_silence_boundary(path: String, info: Dictionary, windows: Array, speed: float, curve: String, job: RefCounted) -> Dictionary: return _native().call("pcm_silence_boundary", path, info, windows, speed, curve, job)

static func silence_source_error(value: Variant) -> String: return _native().call("silence_source_error", value)

