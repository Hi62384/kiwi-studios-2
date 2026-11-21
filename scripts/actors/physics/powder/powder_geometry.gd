class_name KiwiPowderGeometry
extends RefCounted
## Small shared geometry bank, never one mesh or material per grain.
static var cache: Dictionary={}
static var builds:=0
static func variants(values: Dictionary) -> Array[Mesh]:
	var result: Array[Mesh]=[]
	result.assign(_native_geometry().variants(values,cache))
	return result

static func normalized(mesh: Mesh) -> Mesh:
	return _native_geometry().normalized(mesh)

static func deform(mesh: Mesh,amount: float,seed: int) -> Mesh:
	return _native_geometry().deform(mesh,amount,seed)


static func _built() -> void:
	builds+=1
static func _native_geometry() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_geometry")
