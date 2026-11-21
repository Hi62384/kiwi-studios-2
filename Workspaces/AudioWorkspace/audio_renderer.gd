class_name KiwiAudioRenderer
extends RefCounted
## Streaming FFmpeg render graph. Original assets are never modified.
static var _afir_capabilities:Dictionary={}
static var _capability_mutex:=Mutex.new()
static var _publish_mutex:=Mutex.new()
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_renderer")
static func render(document: KiwiAudioDocument, destination: String, options: Dictionary={}, job: RefCounted=null) -> Dictionary: return _native().call("render", document, destination, options, job)

static func execute(encoder: String, args: PackedStringArray, duration: float=1., job: RefCounted=null) -> Dictionary: return _native().call("execute", encoder, args, duration, job)

static func encoded_peak(encoder: String, path: String, duration: float, job: RefCounted=null) -> Dictionary: return _native().call("encoded_peak", encoder, path, duration, job)

static func build_graph(document: KiwiAudioDocument, directory: String, options: Dictionary, rate: int, job: RefCounted=null) -> Dictionary: return _native().call("build_graph", document, directory, options, rate, job)

static func _ordered_effect_chain(effects: Array, rate: int, context: String, directory: String, inputs: Array[String], filters: PackedStringArray, input_label: String, chain: PackedStringArray, duration: float, job: RefCounted=null) -> Dictionary: return _native().call("ordered_effect_chain", effects, rate, context, directory, inputs, filters, input_label, chain, duration, job)

static func _staging_bytes(directory: String) -> int: return _native().call("staging_bytes", directory)

static func _render_float_stage(inputs: Array[String], filters: PackedStringArray, label: String, path: String, rate: int, frames: int, max_bytes: int, job: RefCounted) -> Dictionary: return _native().call("render_float_stage", inputs, filters, label, path, rate, frames, max_bytes, job)

static func _stage_graph(filters: PackedStringArray, selected_label: String) -> String: return _native().call("stage_graph", filters, selected_label)

static func effect_chain(effects: Array, rate: int, context: String, directory: String, inputs: Array[String], job: RefCounted=null) -> Dictionary: return _native().call("effect_chain", effects, rate, context, directory, inputs, job)

static func _afir_normalization(job: RefCounted=null) -> String: return _native().call("afir_normalization", job)

static func route_reaches(document: KiwiAudioDocument, source: String, target: String, visited: Dictionary={}) -> bool: return _native().call("route_reaches", document, source, target, visited)

static func unsupported_automation(document: KiwiAudioDocument, options: Dictionary={}) -> String: return _native().call("unsupported_automation", document, options)

static func pan_automation_filter(points: Array, fallback: float) -> String: return _native().call("pan_automation_filter", points, fallback)

static func gain_filter(points: Array, fallback: float) -> String: return _native().call("gain_filter", points, fallback)

static func automation_expression(points: Array, fallback: float) -> String: return _native().call("automation_expression", points, fallback)

static func _automation_tree(points: Array, first: int, last: int) -> String: return _native().call("automation_tree", points, first, last)

static func _publish_complete(temporary: String, destination: String, job: RefCounted=null) -> Dictionary: return _native().call("publish_complete", temporary, destination, job)

static func finish_process_files(result: Dictionary, directory: String) -> Dictionary: return _native().call("finish_process_files", result, directory)

static func _remove_owned(directory: String) -> PackedStringArray: return _native().call("remove_owned", directory)

static func _fallback_wav(document: KiwiAudioDocument, destination: String, options: Dictionary, job: RefCounted) -> Dictionary: return _native().call("fallback_wav", document, destination, options, job)

static func selection_error(document: KiwiAudioDocument, options: Dictionary) -> String: return _native().call("selection_error", document, options)

