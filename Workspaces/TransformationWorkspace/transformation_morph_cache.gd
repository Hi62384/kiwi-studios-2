class_name KiwiTransformationMorphCache
extends Node
signal prepared
var entries: Dictionary={}
var requests: Array[Dictionary]=[]
var worker: Thread
var active := ""
var analysis_count := 0
var preparation_usec := 0
var field_analysis_count := 0
var basis_cache: Dictionary={}
var active_basis := ""
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_morph_cache")
func signature(a: KiwiTransformationState, b: KiwiTransformationState, key: KiwiTransformationKey) -> String: return _native().call("signature", a, b, key)
func get_pair(a: KiwiTransformationState, b: KiwiTransformationState, key: KiwiTransformationKey) -> Dictionary: return _native().call("get_pair", self, a, b, key)
static func analysis_image(texture: Texture2D, limit: int=128) -> Image: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_morph_cache").call("analysis_image", texture, limit)
func _process(_delta: float) -> void: _native().call("process", self)
func _exit_tree() -> void: _native().call("exit_tree", self)
