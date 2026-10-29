extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); var tree:=session.add("Tree / Oak",{"levels":1}); var native:=tree.render_mesh(); var levels: Array=native.get_meta("environment_lods",[]); var reduced:=false
	for surface in levels.size():
		var arrays:=native.surface_get_arrays(surface); var original: int=(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arrays[Mesh.ARRAY_INDEX]!=null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for indices: PackedInt32Array in levels[surface].values(): reduced=reduced or indices.size()<original
	check(reduced,"Natural model carries actual native reduced-index LODs")
	var collision: PackedVector3Array=native.get_meta("kiwi_collision_faces"); var all:=native.get_faces()
	check(collision.size()>0 and collision.size()<all.size(),"Tree collision includes wood and excludes leaf geometry")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var data:=registry.get_definition(&"basic_mesh").create_actor(); data.set_value(&"mesh_path",session.document); data.values[&"model_component_id"]=tree.id
	var runtime:=registry.get_definition(&"basic_mesh").create_runtime(data); root.add_child(runtime); runtime.evaluate_clip(ActorClip.create(data),0.)
	var captured:=KiwiPhysicsGeometry.capture(runtime,{})
	check(captured.has("collision_points") and captured.collision_points.size()==collision.size() and not captured.points.is_empty(),"Scene physics captures wood proxy while retaining complete render geometry")
	var settings:=KiwiPhysicsSettings.DEFAULTS.duplicate(true); settings.shape=6; settings.body_mode=1; var collider:=KiwiPhysicsGeometry.collider(captured,settings)
	check(collider.shape is ConcavePolygonShape3D and collider.shape.get_faces().size()==collision.size(),"Offline collider uses exact same wood-only triangles")
	var path:="user://promote_natural.res"; ResourceSaver.save(session.document,path); var environment:=KiwiEnvironmentSession.new(); var terrain:=environment.add_terrain(); var layer:=environment.environment().add_group("Natural scatter"); layer.parent_id=terrain.id; var scatter:=KiwiEnvironmentScatter.new(); scatter.terrain_id=terrain.id; scatter.palette=[{"source":path}]; environment.environment().component_settings[layer.id]={"kind":"scatter","scatter":scatter}
	var pose:=Transform3D(Basis(Vector3.UP,.4),Vector3(1,0,2)); check(environment.promote_scatter(layer.id,"stable",{"palette":0,"transform":pose}).is_empty(),"One instance promotes through native model hierarchy")
	var group:=environment.primary(); var copy:=environment.document.components[-1]
	check(environment.document.world_transform(group).is_equal_approx(environment.document.world_transform(layer)*pose) and copy.parent_id==group.id and copy.generator==tree.generator,"Promotion preserves world pose, source settings and component parent")
	environment.undo(); check(not (environment.environment().component_settings[layer.id].scatter as KiwiEnvironmentScatter).overrides.has("stable") and environment.document.component(group.id)==null,"Promotion and scatter removal undo together")
	environment.redo(); check(environment.document.component(group.id)!=null,"Promotion redoes exact hierarchy")
	runtime.queue_free(); await process_frame
	print("NATURAL LOD COLLISION: %d checks, %d failures"%[checks,failures]); quit(failures)
