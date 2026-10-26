class_name KiwiModelComponent
extends Resource
@export var id := ""
@export var title := "Component"
@export var parent_id := ""
@export var transform := Transform3D.IDENTITY
@export var pivot := Vector3.ZERO
@export var mesh: KiwiModelMesh
@export var generator := ""
@export var parameters: Dictionary = {}
@export var modifiers: Array[Dictionary] = []
@export var surface_materials: Array[Material] = []
@export var visible := true
@export var locked := false
@export var is_skeleton := false
@export var bones: Array[Dictionary] = []
@export var skin: Skin
@export var skin_mesh: Mesh
@export var skeleton_id := ""
@export var binding: KiwiRigBinding
@export var geometry_source: Mesh
@export var geometry_source_hash := 0

func copy_component(new_identity: bool = false) -> KiwiModelComponent:
	var result := KiwiModelComponent.new()
	result.id=ActorData.new_id() if new_identity else id; result.title=title; result.parent_id=parent_id
	result.transform=transform; result.pivot=pivot; result.visible=visible; result.locked=locked
	result.mesh=mesh.copy_mesh() if mesh!=null else null
	result.generator=generator; result.parameters=parameters.duplicate(true); result.modifiers=modifiers.duplicate(true)
	result.surface_materials=surface_materials.duplicate()
	result.is_skeleton=is_skeleton; result.bones=bones.duplicate(true)
	result.skin=skin; result.skin_mesh=skin_mesh; result.skeleton_id=skeleton_id
	result.binding=binding.copy_binding() if binding!=null else null; result.geometry_source=geometry_source; result.geometry_source_hash=geometry_source_hash
	return result
