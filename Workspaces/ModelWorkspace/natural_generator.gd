extends RefCounted
## CPU-only editable geometry. Source settings live in normal component parameters;
## native material slots, hierarchy, history and scene import remain authoritative.
const TREES=["Oak","Maple","Birch","Willow","Pine","Spruce","Fir","Palm","Tropical","Mangrove","Acacia","Desert","Twisted","Dead","Wind-shaped","Ancient","Fantasy"]
const PLANTS=["Bush","Grass","Flower","Fern","Vine","Reed","Succulent","Mushroom","Cactus"]
const ROCKS=["Granite","Basalt","Limestone","Sandstone","Slate","River stone","Volcanic"]
const PROPS=["Log","Stump","Driftwood","Root","Stalactite","Stalagmite"]
const MAX_VERTICES=200000
const CACHE_BYTES=67108864
class Cancellation:
	extends RefCounted
	var callback: Callable
	func cancelled() -> bool: return callback.is_valid() and bool(callback.call())
static func kinds() -> Array: return Engine.get_singleton("KiwiNativeServices").call("service","natural_settings").kinds()
static func accepts(kind: String) -> bool: return Engine.get_singleton("KiwiNativeServices").call("service","natural_settings").accepts(kind)
static func defaults(kind: String) -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service","natural_settings").defaults(kind)
static func generate(kind: String, settings: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var cancellation: RefCounted=null
	if cancel.is_valid():
		cancellation=Cancellation.new()
		cancellation.callback=cancel
	return Engine.get_singleton("KiwiNativeServices").call("service","natural_generator").generate(kind,settings,cancellation)
static func cache_info() -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service","natural_generator").cache_info()
static func materials(kind: String,settings: Dictionary={}) -> Array[Material]: return Engine.get_singleton("KiwiNativeServices").call("service","natural_settings").materials(kind,settings)
