extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var owner:=Worlds.add(session); var source: Resource=Worlds.source(owner); source.render_distance=180.; var terrain:=KiwiEnvironmentTerrain.new(); terrain.dimensions=Vector2(256,256); terrain.resolution=33; var ground:=session.environment().add_terrain(terrain); ground.visible=false
	var model:=KiwiModelDocument.new(); var sphere:=KiwiModelComponent.new(); sphere.id="sphere"; sphere.mesh=KiwiModelPrimitives.create("Sphere",{"segments":48,"radius":2.}); model.components.append(sphere)
	var item:=KiwiModelComponent.new(); item.id="world-mesh"; item.parent_id=owner.id; item.mesh=sphere.mesh; item.parameters.world_owner=owner.id; session.document.components.append(item); session.environment().component_settings[item.id]={"kind":"asset","collision":true}
	var rules:=KiwiEnvironmentScatter.new(); rules.terrain_id=ground.id; rules.palette=[{"source":model,"weight":1.}]; rules.region=Rect2(-80,-80,160,160); rules.use_anchors=true; rules.render_cluster_size=16.; rules.render_distance=140.; rules.lod_enabled=true; rules.minimum_distance=.1
	for z in 3:
		for x in 3: rules.anchor_points.append(Transform3D(Basis.IDENTITY,Vector3((x-1)*24.,0.,(z-1)*24.)))
	var layer:=session.environment().add_group("Clustered spheres"); layer.parent_id=owner.id; session.environment().component_settings[layer.id]={"kind":"scatter","scatter":rules}; var generated:=rules.generate(terrain); var layout_key:=rules.signature()
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(640,480); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,28,75); camera.look_at(Vector3.ZERO); camera.current=true; var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(session.environment()); var batches: Array=runtime.nodes[layer.id].find_children("*","MultiMeshInstance3D",true,false); var count:=0; var poses:=PackedVector3Array(); var detail:=true
	for batch: MultiMeshInstance3D in batches:
		count+=batch.multimesh.instance_count; detail=detail and batch.multimesh.mesh.has_meta("environment_lods") and batch.visibility_range_end==140.
		for index in batch.multimesh.instance_count: poses.append(batch.transform*batch.multimesh.get_instance_transform(index).origin)
	var same:=true
	for pose: Transform3D in generated.batches[0]:
		var found:=false
		for point in poses: found=found or point.is_equal_approx(pose.origin)
		same=same and found
	check(batches.size()==9 and count==9 and same,"Spatial MultiMesh clusters preserve every authored instance transform without extra scene actors")
	check(detail and runtime.errors.is_empty(),"Cluster meshes have actual native LOD indices and independent fading distances")
	var visual:=runtime.nodes[item.id].get_child(0) as MeshInstance3D; var before:=item.mesh.vertices.duplicate(); var collision:=visual.get_node("Collision").get_child(0) as CollisionShape3D
	check(visual.mesh.has_meta("environment_lods") and visual.visibility_range_end==180. and collision.shape.get_faces().size()==visual.mesh.get_faces().size() and item.mesh.vertices==before,"World assets use native LOD and render distance while source geometry and full collision remain intact")
	var captured: Dictionary=runtime.nodes[layer.id].get_meta("scatter_result"); rules.render_cluster_size=32.; rules.lod_bias=.5; rules.render_distance=90.; runtime.sync(); batches=runtime.nodes[layer.id].find_children("*","MultiMeshInstance3D",true,false); var updated:=true
	for batch: MultiMeshInstance3D in batches: updated=updated and batch.lod_bias==.5 and batch.visibility_range_end==90.
	check(rules.signature()==layout_key and runtime.nodes[layer.id].get_meta("scatter_result")==captured and batches.size()<9 and updated,"Changing cluster size, distance or detail reuses placements instead of regenerating scatter")
	if DisplayServer.get_name()!="headless":
		view.mesh_lod_threshold=0.
		for i in 5: await RenderingServer.frame_post_draw
		var high:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME); view.mesh_lod_threshold=1000.
		for i in 5: await RenderingServer.frame_post_draw
		var low:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME); check(high>1000 and low<high*.7,"Native renderer submits substantially fewer asset and scatter primitives at distant detail")
		print("WORLD RENDER actual primitives: full=",high," coarse=",low)
	var saved:=ResourceSaver.save(session.environment(),"user://world_rendering_test.res"); var loaded:=ResourceLoader.load("user://world_rendering_test.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and (loaded.component_settings[layer.id].scatter as KiwiEnvironmentScatter).render_cluster_size==32. and Worlds.source(loaded.component(owner.id)).render_distance==180.,"Native cluster, detail and world distance settings survive environment save/reopen")
	view.queue_free(); await process_frame; print("WORLD RENDERING: %d checks, %d failures"%[checks,failures]); quit(failures)

