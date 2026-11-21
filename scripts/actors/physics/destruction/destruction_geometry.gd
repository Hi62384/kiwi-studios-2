class_name KiwiDestructionGeometry
extends RefCounted
## Immutable operation evaluation on Kiwi's existing editable polygon topology.
const TYPES := ["Plane fracture","Multi-piece fracture","Impact fracture","Crack","Bend","Tear","Carve sphere","Carve box","Carve cylinder","Dent","Twist","Stretch","Weakness region","Protected region","Impact impulse"]
const MAX_VERTICES:=20000
const MAX_PARTS:=48
static func closed(mesh: KiwiModelMesh) -> bool:
	return _native_geometry().closed(mesh)

static func volume(mesh: KiwiModelMesh) -> float:
	return _native_geometry().volume(mesh)

static func cut(mesh: KiwiModelMesh,normal: Vector3,distance: float,interior: int) -> KiwiModelMesh:
	return _native_geometry().cut(mesh,normal,distance,interior)

static func split(mesh: KiwiModelMesh,normal: Vector3,point: Vector3,interior: int) -> Array[KiwiModelMesh]:
	var result: Array[KiwiModelMesh]=[]
	result.assign(_native_geometry().split(mesh,normal,point,interior))
	return result

static func subtract(mesh: KiwiModelMesh,cutter: KiwiModelMesh,interior: int) -> Array[KiwiModelMesh]:
	var result: Array[KiwiModelMesh]=[]
	result.assign(_native_geometry().subtract(mesh,cutter,interior))
	return result

static func evaluate(source: KiwiModelMesh,operations: Dictionary,interior: int) -> Dictionary:
	var result: Dictionary=_native_geometry().evaluate(source,operations,interior)
	var parts: Array[KiwiModelMesh]=[]
	parts.assign(result.parts)
	result.parts=parts
	return result

static func _solid_islands(source: KiwiModelMesh) -> Array[KiwiModelMesh]:
	var result: Array[KiwiModelMesh]=[]
	result.assign(_native_geometry().solid_islands(source))
	return result

static func _island_root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index:
		parents[index]=parents[parents[index]]; index=parents[index]
	return index
static func _native_geometry() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_geometry")
