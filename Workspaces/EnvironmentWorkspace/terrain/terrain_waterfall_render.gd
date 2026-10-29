extends RefCounted
## Analytical seeded spray: animation and frame export use the same liquid_time.
## No wall-clock particle simulation and no node-per-particle overhead.
static func sync(water: MeshInstance3D,terrain: KiwiEnvironmentTerrain) -> void:
	var source:=terrain.hydrology; var falls: Array=terrain.water_data.get("waterfalls",[]); var visual:=water.get_node_or_null("Spray") as MultiMeshInstance3D
	if not source.waterfall_spray or falls.is_empty():
		if visual!=null: visual.hide()
		return
	if visual==null:
		visual=MultiMeshInstance3D.new(); visual.name="Spray"; visual.set_meta("kiwi_physics_excluded",true); visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; water.add_child(visual)
	visual.show(); var key:=hash([falls,terrain.seed,source.spray_per_fall,source.spray_lifetime,source.spray_size])
	if visual.get_meta("spray_key",-1)!=key:
		var count:=mini(2048,falls.size()*clampi(source.spray_per_fall,1,128)); var mesh:=MultiMesh.new(); mesh.transform_format=MultiMesh.TRANSFORM_3D; mesh.use_custom_data=true; mesh.mesh=QuadMesh.new(); mesh.instance_count=count; var rng:=RandomNumberGenerator.new(); rng.seed=terrain.seed; var bounds:=AABB(); var first:=true
		for index in count:
			var fall: Dictionary=falls[index/clampi(source.spray_per_fall,1,128)]; var direction: Vector2=fall.get("flow",Vector2.ZERO); var side:=Vector3(direction.y,0,-direction.x); var center: Vector3=fall.to; center+=side*rng.randf_range(-.5,.5)*float(fall.width); var velocity:=side*rng.randf_range(-.8,.8)+Vector3(direction.x,rng.randf_range(.5,1.5)*sqrt(maxf(.01,float(fall.drop))),direction.y)*.55; var lifetime:=maxf(.01,source.spray_lifetime); var end:=center+velocity*lifetime+Vector3(0,-2,0)*lifetime*lifetime
			mesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,center)); mesh.set_instance_custom_data(index,Color(velocity.x,velocity.y,velocity.z,rng.randf())); var box:=AABB(center,Vector3.ZERO).expand(end).grow(absf(source.spray_size)+velocity.y*velocity.y/8.); bounds=box if first else bounds.merge(box); first=false
		mesh.custom_aabb=bounds; visual.multimesh=mesh; visual.set_meta("spray_key",key)
	var material:=visual.material_override as ShaderMaterial
	if material==null: material=ShaderMaterial.new(); material.shader=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_spray.gdshader"); material.set_meta("kiwi_time_uniform","liquid_time"); material.set_meta("terrain_water",true); visual.material_override=material
	material.set_shader_parameter("lifetime",maxf(.01,source.spray_lifetime)); material.set_shader_parameter("size",maxf(.001,source.spray_size)); material.set_shader_parameter("foam_color",source.foam_color)
