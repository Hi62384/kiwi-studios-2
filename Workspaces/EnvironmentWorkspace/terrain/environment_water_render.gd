extends RefCounted
## Uses the shared liquid appearance shader, with terrain depth and flow fields.
static func sync(node: Node3D,terrain: KiwiEnvironmentTerrain) -> void:
	var visual:=node.get_node_or_null("Water") as MeshInstance3D
	if terrain.hydrology==null or not terrain.water_valid() or not terrain.hydrology.enabled:
		if visual!=null: visual.hide()
		return
	var data: Dictionary=terrain.water_data.get("mesh",{})
	if data.get("vertices",PackedVector3Array()).is_empty():
		if visual!=null: visual.hide()
		return
	if visual==null:
		visual=MeshInstance3D.new(); visual.name="Water"; visual.set_meta("kiwi_physics_excluded",true); visual.set_meta("terrain_water",true); visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; node.add_child(visual)
	visual.show()
	if int(visual.get_meta("water_key",-1))!=terrain.water_key:
		var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX)
		for pair in [[Mesh.ARRAY_VERTEX,"vertices"],[Mesh.ARRAY_NORMAL,"normals"],[Mesh.ARRAY_TEX_UV,"uv"],[Mesh.ARRAY_TEX_UV2,"uv2"],[Mesh.ARRAY_COLOR,"colors"],[Mesh.ARRAY_INDEX,"indices"]]: arrays[pair[0]]=data[pair[1]]
		var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); visual.mesh=mesh; visual.set_meta("water_key",terrain.water_key)
	var source:=terrain.hydrology; var material:=KiwiEnvironmentAssets.material(source.material_asset)
	if material==null:
		var shader_material:=visual.material_override as ShaderMaterial
		if shader_material==null or not shader_material.get_meta("terrain_water",false):
			shader_material=ShaderMaterial.new(); shader_material.shader=preload("res://scripts/actors/physics/fluid/fluid.gdshader"); shader_material.set_meta("terrain_water",true); shader_material.set_meta("kiwi_time_uniform","liquid_time")
		for key in ["wave_strength","wave_scale","wave_direction","flow_speed","roughness","foam_color","foam_amount"]: shader_material.set_shader_parameter(key,source.get(key))
		shader_material.set_shader_parameter("terrain_surface",true); shader_material.set_shader_parameter("liquid_color",source.water_color); material=shader_material
	visual.material_override=material; visual.custom_aabb=visual.mesh.get_aabb().grow(absf(source.wave_strength)+.01); visual.visibility_range_end=maxf(0.,terrain.render_distance); visual.visibility_range_end_margin=terrain.render_distance*.15
	preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_waterfall_render.gd").sync(visual,terrain)
