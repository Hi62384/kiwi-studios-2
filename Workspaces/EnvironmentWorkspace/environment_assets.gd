class_name KiwiEnvironmentAssets
extends RefCounted
static var cache: Dictionary={}
static var revisions: Dictionary={}
static var material_cache: Dictionary={}
static var generation:=0
static func invalidate(path: String) -> void:
	generation+=1
	_native().call("invalidate",path,cache,revisions,material_cache)
static func load_parts(path: String) -> Dictionary:
	return _native().call("load_parts",path,cache,revisions)
static func load_scatter_parts(value: Variant) -> Dictionary:
	return _native().call("load_scatter_parts",value,cache,revisions)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_assets")
static func _model_parts(source: KiwiModelDocument) -> Array:
	return _native().call("model_parts",source)

static func material(value: Variant) -> Material:
	return _native().call("material",value,material_cache,revisions)
static func _material(value: Variant) -> Material:
	return _native().call("raw_material",value)

static func timeline_material(source: Material,force_copy: bool=false) -> Material:
	if not source is ShaderMaterial or source.shader==null: return source
	var existing: Variant=source.get_meta("kiwi_timeline_link") if source.has_meta("kiwi_timeline_link") else null
	if not force_copy and existing!=null and existing.has_method("active_for") and existing.active_for_id(source.get_instance_id()): return source
	if force_copy:
		var seen: Dictionary={}
		while existing!=null and existing.has_method("authoring_source") and not seen.has(source.get_instance_id()):
			seen[source.get_instance_id()]=true; var original: ShaderMaterial=existing.authoring_source()
			if original==null: break
			source=original; existing=source.get_meta("kiwi_timeline_link") if source.has_meta("kiwi_timeline_link") else null
	var result:=source.duplicate(false) as ShaderMaterial; var link:=preload("res://Workspaces/EnvironmentWorkspace/TimelineMaterialBinding.cs").new(); result.set_meta("kiwi_timeline_link",link); link.setup_weak(weakref(source),weakref(result)); return result

static func content_stamp(value: Variant,seen: Dictionary={},depth: int=0) -> int:
	return _native().call("content_stamp",value,seen,depth,revisions)
static func world_stamp(document: KiwiEnvironmentDocument) -> int:
	return _native().call("world_stamp",document,revisions)
static func world_environment(document: KiwiEnvironmentDocument) -> Environment:
	return _native().call("world_environment",document)

static func _revision_state() -> Dictionary: return revisions
