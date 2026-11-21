extends RefCounted
## Post-fader/pre-send route peaks tapped from the SAME offline render graph.
## Bounded 20 Hz data for previews <=10 minutes and <=32 routes.
const HZ:=20
const MAX_SECONDS:=600.
const MAX_ROUTES:=32
const MAX_LOG_BYTES:=4*1024*1024

static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_route_meters")
static func enabled(document: KiwiAudioDocument, options: Dictionary) -> bool: return _native().call("enabled", document, options)
static func tap(filters: PackedStringArray, label: String, index: int, directory: String, start: float, duration: float, rate: int) -> Dictionary: return _native().call("tap", filters, label, index, directory, start, duration, rate)
static func read(routes: Array, duration: float) -> Dictionary: return _native().call("read", routes, duration)
