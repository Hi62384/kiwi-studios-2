extends RefCounted
## Native renderer-bounded PBR palette and volumetric biome uploads.
const MAX_BIOME_MATERIALS:=8
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_biome_render")
static func capacity() -> int: return _native().call("capacity")
static func material(owner: Node3D,terrain: KiwiEnvironmentTerrain,ground: Material,paint: Material) -> Material:
	return _native().call("material",owner,terrain,ground,paint,KiwiEnvironmentAssets.revisions)
static func _bind_cave(owner: Node3D,material: ShaderMaterial,terrain: KiwiEnvironmentTerrain,layers: Array[Dictionary]) -> void:
	_native().call("bind_cave",owner,material,terrain,layers)
static func shader() -> Shader: return _native().call("shader")
