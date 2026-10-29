extends "res://scripts/actors/tests/surface_growth_test.gd"
func settle() -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
func centroid(image: Image) -> Vector3:
	var sum:=Vector2.ZERO; var count:=0
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			var color:=image.get_pixel(x,y)
			if color.g>color.r+.08 and color.g>color.b+.08: sum+=Vector2(x,y); count+=1
	return Vector3(sum.x/maxi(1,count),sum.y/maxi(1,count),count)
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("GPU visual test requires a native renderer."); quit(1); return
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(1,1,1)}); KiwiSurfaceGrowth.add(session,0); var component:=session.primary(); component.growth.settings.length=.6; component.growth.settings.thickness=.018; component.growth.settings.variation=0.; component.growth.settings.curvature=0.; component.growth.settings.orientation_variation=0.; component.growth.rendering.automatic_lod=false
	component.growth.appearance.root_color=Color.BLACK; component.growth.appearance.tip_color=Color.BLACK; component.growth.appearance.emission=Color.GREEN; component.growth.appearance.specular=0.
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,1.,2.5); camera.look_at(Vector3(0,.3,0)); camera.current=true
	var cpu:=KiwiSurfaceGrowthInstance.new(); var gpu:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(cpu); viewport.add_child(gpu); cpu.configure(component,true); gpu.configure(component,true); cpu.data.rendering.gpu_threshold=100000; gpu.data.rendering.gpu_threshold=1
	var points:=PackedVector3Array(); var deltas:=PackedVector3Array()
	for i in 9: var t:=float(i)/8.; points.append(Vector3(t*t*.35,t*.6,0)); deltas.append(Vector3(t*t*.35,0,0))
	for instance: KiwiSurfaceGrowthInstance in [cpu,gpu]:
		instance.data.motion_guides={"g":{"points":points,"delta_points":deltas}}; instance.data.motion_binding=123
		for row: Dictionary in instance.data.roots: instance.data.motion_weights[str(row.id)]={"g":1.}
		instance.update_growth()
	gpu.hide(); await settle(); var reference:=viewport.get_texture().get_image(); cpu.hide(); gpu.show(); await settle(); var actual:=viewport.get_texture().get_image()
	var a:=centroid(reference); var b:=centroid(actual)
	check(a.z>50 and b.z>50,"CPU reference and GPU guides both produce visible strand geometry")
	check(Vector2(a.x,a.y).distance_to(Vector2(b.x,b.y))<2.,"GPU guide displacement matches CPU reference in the rendered viewport")
	check(gpu.data.gpu_motion and gpu.material_override.get_shader_parameter("growth_guide_motion"),"Dense attachment uses the real guide deformation shader path")
	var cached:=gpu.mesh; var builds:=gpu.data.chunk_builds; var uploads:=gpu.gpu.uploads
	deltas[8]+=Vector3(.15,0,0); gpu.data.motion_guides.g.delta_points=deltas; gpu.update_growth(); await settle()
	check(gpu.mesh==cached and gpu.data.chunk_builds==builds and gpu.gpu.uploads>uploads,"Changed guide motion updates its small texture without rebuilding strand buffers")
	check(viewport.get_texture().get_image().get_data()!=actual.get_data(),"Guide texture updates change the actual rendered pixels")
	check(cpu.material_override!=gpu.material_override and not cpu.data.gpu_motion,"Instances keep independent motion materials and buffers")
	actual.save_png("res://.godot/verification/growth_gpu_guides.png"); reference.save_png("res://.godot/verification/growth_cpu_guides.png")
	print("GPU_GUIDES roots=",gpu.data.roots.size()," uploads=",gpu.gpu.uploads," uploaded_bytes=",gpu.gpu.uploaded_bytes," cpu_centroid=",a," gpu_centroid=",b)
	cpu.hide(); gpu.hide()
	var rig_session:=KiwiModelSession.new(); var body:=rig_session.add("Cylinder",{"height":2.,"radius":.3,"segments":8}); var body_id:=body.id; var author:=KiwiRigEditor.new(rig_session); var rig:=author.create("Tentacle",3); author.bind("Smooth"); rig_session.select(body_id); KiwiSurfaceGrowth.add(rig_session,1); var skinned:=rig_session.primary()
	skinned.growth.rendering.automatic_lod=false; skinned.growth.appearance.root_color=Color.BLACK; skinned.growth.appearance.tip_color=Color.BLACK; skinned.growth.appearance.emission=Color.GREEN; skinned.growth.appearance.specular=0.; skinned.growth.settings.thickness=.015
	var skeleton:=ActorSkeletonRigRuntime.create_skeleton(rig.bones); viewport.add_child(skeleton); skeleton.set_bone_pose_rotation(1,Quaternion(Vector3.FORWARD,.6)); skeleton.force_update_all_bone_transforms()
	var cpu_skin:=KiwiSurfaceGrowthInstance.new(); var gpu_skin:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(cpu_skin); viewport.add_child(gpu_skin); cpu_skin.configure(skinned,true); gpu_skin.configure(skinned,true); cpu_skin.data.rendering.gpu_threshold=100000; gpu_skin.data.rendering.gpu_threshold=1; cpu_skin.growth_skeleton=skeleton; gpu_skin.growth_skeleton=skeleton; cpu_skin.update_growth(); gpu_skin.update_growth()
	camera.position=Vector3(0,.2,3.); camera.look_at(Vector3.ZERO); gpu_skin.hide(); await settle(); var skin_reference:=viewport.get_texture().get_image(); cpu_skin.hide(); gpu_skin.show(); await settle(); var skin_actual:=viewport.get_texture().get_image(); var ca:=centroid(skin_reference); var cb:=centroid(skin_actual)
	check(ca.z>50 and cb.z>50 and Vector2(ca.x,ca.y).distance_to(Vector2(cb.x,cb.y))<2.,"GPU barycentric skin attachment matches a real multi-bone CPU reference")
	check(gpu_skin.data.gpu_motion and gpu_skin.material_override.get_shader_parameter("growth_skin_attachment"),"Skinned growth enables the source-vertex texture adapter")
	var skin_mesh:=gpu_skin.mesh; var skin_uploads:=gpu_skin.gpu.uploads; skeleton.set_bone_pose_rotation(1,Quaternion(Vector3.FORWARD,-.6)); gpu_skin.update_growth(); await settle()
	check(gpu_skin.mesh==skin_mesh and gpu_skin.gpu.uploads>skin_uploads and viewport.get_texture().get_image().get_data()!=skin_actual.get_data(),"Skeletal animation updates rendered growth through source-point uploads while retaining strand geometry")
	print("GPU_SKIN source_vertices=",gpu_skin.data.source_points.size()," roots=",gpu_skin.data.roots.size()," cpu_centroid=",ca," gpu_centroid=",cb)
	viewport.queue_free(); await process_frame; await process_frame; print("GROWTH GPU: %d checks, %d failures"%[checks,failures]); quit(failures)
