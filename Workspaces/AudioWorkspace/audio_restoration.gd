extends RefCounted
## Conservative, offline multiband decay suppression. Not blind source
## separation or a reconstruction of a dry room. Can attenuate musical tails.
const MAX_BYTES:=64*1024*1024
const BLOCK:=256
const CROSSOVERS:=[200.,500.,1200.,3000.,7000.]

static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_restoration")
static func process_f32(input_path: String, output_path: String, effect: Dictionary, rate: int, job: RefCounted=null) -> Dictionary: return _native().call("process_f32", input_path, output_path, effect, rate, job)
static func breath_candidates(source: Variant, start: float, duration: float, job: RefCounted=null) -> Dictionary: return _native().call("breath_candidates", source, start, duration, job)
