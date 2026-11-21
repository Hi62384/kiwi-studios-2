extends RefCounted
## Compatibility API; immutable field sampling/capture runs in C#.
static var cache: Dictionary={}
var _field:=preload("res://Workspaces/EnvironmentWorkspace/WorldTerrainField.cs").new()
const FIELDS:=["resolution","dimensions","heights","native_resolution","native_base","native_edits","native_water","water_resolution","water_levels","water_depths","to_ground","to_world","key","source_signature","root_id","terrain_id","terrain_input"]
func _get(name: StringName) -> Variant:
	return _field.get(name) if str(name) in FIELDS else null
func _set(name: StringName,value: Variant) -> bool:
	if str(name) not in FIELDS: return false
	_field.set(name,value); return true
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_terrain_field")
static func signature(terrain: KiwiEnvironmentTerrain) -> int:
	return _native().call("signature",terrain)
static func capture(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary:
	return _native().call("capture",session,id,source,cache)
func sample(point: Vector2) -> Dictionary: return _field.sample(point)
func _sample_height(x: int,z: int) -> float: return _field._sample_height(x,z)
func water_at_uv(uv: Vector2) -> Dictionary: return _field.water_at_uv(uv)
func _height(x: int,z: int) -> float: return _field._height(x,z)
func valid(session: KiwiEnvironmentSession) -> bool: return _field.valid(session)
