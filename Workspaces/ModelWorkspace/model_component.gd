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
@export var structural: Dictionary = {}
@export var growth: KiwiSurfaceGrowthData

func render_mesh(material_scope: Variant=null) -> ArrayMesh:
	var evaluated:=KiwiModelModifiers.evaluate(self); var result:=evaluated.render_mesh(surface_materials)
	for surface in result.get_surface_count():
		var material:=result.surface_get_material(surface)
		if material is ShaderMaterial:
			if material_scope is Dictionary:
				var identity:=material.get_instance_id()
				if not material_scope.has(identity): material_scope[identity]=KiwiEnvironmentAssets.timeline_material(material,true)
				result.surface_set_material(surface,material_scope[identity])
			else: result.surface_set_material(surface,KiwiEnvironmentAssets.timeline_material(material))
	if parameters.has("architecture_type"):
		result.set_meta("kiwi_editable_topology",evaluated)
		if not parameters.get("_architecture_manual",false): result.set_meta("kiwi_compound_points",preload("res://Workspaces/EnvironmentWorkspace/architecture/building_collision.gd").parts(evaluated))
	return preload("res://Workspaces/ModelWorkspace/natural_render.gd").prepare(result,self)

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
	result.structural=structural.duplicate(true)
	result.growth=growth.copy_data() if growth!=null else null
	return result
