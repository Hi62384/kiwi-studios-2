class_name KiwiFluidRuntime
extends "res://scripts/actors/examples/basic_actor.gd"
var surface: MeshInstance3D
var liquid_material: ShaderMaterial
var surface_key: int = -1
var surface_stats: Dictionary = {}
func _ready() -> void:
	content=Node3D.new(); super._ready()
	surface=MeshInstance3D.new(); surface.name="LiquidSurface"; content.add_child(surface); surface.set_as_top_level(true); surface.global_transform=Transform3D.IDENTITY; surface.layers=1
	liquid_material=ShaderMaterial.new(); liquid_material.shader=preload("res://scripts/actors/physics/fluid/fluid.gdshader"); surface.material_override=liquid_material
func evaluate(time: float, values: Dictionary) -> void:
	super.evaluate(time,values)
	if surface==null: return
	if not values.get(&"physics",{}).get("enabled",true): clear_surface()
	var reference: Variant=values.get(&"fluid_material")
	if reference is ActorObjectReference: _apply_material_reference(reference,null,false)
	else:
		surface.material_override=liquid_material
		for pair in [["liquid_color","fluid_color"],["foam_color","fluid_foam_color"],["opacity","fluid_opacity"],["roughness","fluid_roughness"],["metallic","fluid_metallic"],["specular","fluid_specular"],["glow","fluid_emission"],["foam_amount","fluid_foam"],["texture_scale","fluid_texture_scale"],["texture_offset","fluid_texture_offset"],["texture_flow","fluid_texture_flow"],["texture_blend","fluid_texture_blend"],["normal_strength","fluid_normal_strength"]]: liquid_material.set_shader_parameter(pair[0],values.get(StringName(pair[1])))
		liquid_material.set_shader_parameter("texture_rotation",deg_to_rad(float(values.get(&"fluid_texture_rotation",0))))
		for pair in [["fluid_texture","detail_texture","has_texture"],["fluid_normal","normal_texture","has_normal"]]:
			var texture: Texture2D=_texture_for_value(values.get(StringName(pair[0])))
			liquid_material.set_shader_parameter(pair[1],texture); liquid_material.set_shader_parameter(pair[2],texture!=null)
		liquid_material.set_shader_parameter("liquid_time",time)
func show_state(state: Dictionary, values: Dictionary) -> void:
	var effective:=KiwiFluidSettings.effective(values)
	var key:=hash([state.points,state.get("fluid_foam",PackedFloat32Array()),effective.cell,values.fluid_surface_level])
	if key==surface_key: return
	surface_key=key; surface_stats=KiwiFluidSurface.build(state.points,state.get("fluid_foam",PackedFloat32Array()),effective); surface.mesh=surface_stats.mesh
func clear_surface() -> void:
	if surface!=null: surface.mesh=null; surface_key=-1
