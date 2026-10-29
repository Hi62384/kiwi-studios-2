extends RefCounted
## Native full-resolution chunks become editable Model components. The authoring
## proxy is never mistaken for the baked geometry. Work yields between chunks.
var cancelled:=false
var progress:=0.
var error:=""
func cancel() -> void: cancelled=true
func run(runtime: KiwiEnvironmentRuntime,id: String,owner: Node,include_water: bool=false) -> KiwiModelDocument:
	error=""; progress=0.
	if runtime.document==null or runtime.document.terrain(id)==null: error="Choose a terrain component."; return null
	var source:=runtime.document.terrain(id).duplicate(true) as KiwiEnvironmentTerrain; var item:=runtime.document.component(id); var pose:=runtime.document.world_transform(item); var metadata: Dictionary=runtime.document.component_settings[id]; var output:=KiwiModelDocument.new(); var group:=KiwiModelComponent.new(); group.id=ActorData.new_id(); group.title=item.title; group.transform=pose; output.components.append(group)
	if not source.water_valid() or not source.biomes_valid() or not source.volumes_valid() or not source.cave_biomes_valid(): error="Finish terrain generation before baking."; return null
	var root: Node3D=runtime.nodes.get(id); var ground:=KiwiEnvironmentAssets.material(metadata.get("material")); var paint:=KiwiEnvironmentAssets.material(metadata.get("paint_material"))
	if ground==null: ground=runtime.default_ground
	var blended: Material=null
	if root!=null:
		blended=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_render.gd").material(root,source,ground,paint)
		if blended==null: blended=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint_render.gd").material(root,source,ground,paint)
	var first_material:=_freeze(blended if blended!=null else ground); var materials: Array[Material]=[first_material,first_material if blended!=null else _freeze(paint if paint!=null else ground)]; var side:=ceili(float(source.resolution-1)/source.CHUNK_CELLS); var completed:=0
	for z in side:
		for x in side:
			if cancelled or not is_instance_valid(owner) or not owner.is_inside_tree(): return null
			var mesh:=source.chunk_mesh(Vector2i(x,z),false,blended!=null)
			if mesh.get_surface_count()>0:
				var baked:=KiwiModelImport._add_mesh(output,mesh,Transform3D.IDENTITY,"Terrain %d · %d"%[x,z]); baked.parent_id=group.id; var slots: PackedInt32Array=mesh.get_meta("environment_material_slots",PackedInt32Array()); baked.surface_materials.clear()
				for surface in mesh.get_surface_count(): baked.surface_materials.append(materials[1] if surface<slots.size() and slots[surface]==1 else materials[0])
				for name in ["kiwi_terrain_collision","environment_lods"]:
					if baked.geometry_source.has_meta(name): baked.geometry_source.remove_meta(name)
			completed+=1; progress=float(completed)/(side*side); await owner.get_tree().process_frame
	if cancelled: return null
	if include_water and root!=null:
		var water:=root.get_node_or_null("Water") as MeshInstance3D
		if water!=null and water.mesh!=null:
			var baked:=KiwiModelImport._add_mesh(output,water.mesh,Transform3D.IDENTITY,"Water surface"); baked.parent_id=group.id; baked.surface_materials=[_freeze(water.material_override)]
	var errors:=output.validate()
	if not errors.is_empty(): error=errors[0]; return null
	return output
static func _freeze(source: Material) -> Material:
	if source==null: return null
	var result:=source.duplicate(true) as Material
	if source is ShaderMaterial and source.shader!=null:
		for uniform in source.shader.get_shader_uniform_list():
			var value: Variant=source.get_shader_parameter(uniform.name)
			if value is Texture2D:
				var image: Image=value.get_image()
				if image!=null and not image.is_empty(): result.set_shader_parameter(uniform.name,ImageTexture.create_from_image(image))
			elif value is Texture3D:
				var images: Array[Image]=value.get_data(); var texture:=ImageTexture3D.new()
				if not images.is_empty() and texture.create(value.get_format(),value.get_width(),value.get_height(),value.get_depth(),value.has_mipmaps(),images)==OK: result.set_shader_parameter(uniform.name,texture)
	return result
