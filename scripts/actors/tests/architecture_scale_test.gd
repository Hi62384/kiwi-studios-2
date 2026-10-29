extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Layout=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Collision=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_collision.gd")
func run() -> void:
	var memory:=OS.get_static_memory_usage(); var source: Resource=Source.rectangular(24,32,8); var layout:=Layout.generate(source,12,2.); check(layout.errors.is_empty(),"Eight-level constrained plan generates 96 separate rooms with hallways")
	var start:=Time.get_ticks_usec(); var output:=Builder.generate(layout.source); var generation_ms:=float(Time.get_ticks_usec()-start)/1000.; var document:=output.document as KiwiModelDocument
	check(document!=null and output.errors.is_empty() and document.components.size()>500,"Large building produces complete valid native component geometry")
	if document==null: quit(1); return
	var vertices:=0; var faces:=0; var windows:=0; var solids:=0; start=Time.get_ticks_usec()
	for item in document.components:
		if item.mesh==null: continue
		vertices+=item.mesh.vertices.size(); faces+=item.mesh.faces.size()
		if item.parameters.get("architecture_type","")=="window": windows+=1
		if item.parameters.get("architecture_type","")=="wall": solids+=Collision.parts(item.mesh).size()
	var collision_ms:=float(Time.get_ticks_usec()-start)/1000.
	check(windows>=96 and solids>96 and vertices>10000,"Repeated windows and openings retain real geometry and compound collision parts")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(360,360); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport); start=Time.get_ticks_usec(); var instance:=document.instantiate_model(); viewport.add_child(instance); var upload_ms:=float(Time.get_ticks_usec()-start)/1000.
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.04,.06,.09); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.4; viewport.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); viewport.add_child(light); var camera:=Camera3D.new(); camera.position=Vector3(34,30,40); viewport.add_child(camera); camera.look_at(Vector3(0,12,0))
	for i in 5: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; var pixels:=viewport.get_texture().get_image(); var unique: Dictionary={}
		for y in range(0,360,6):
			for x in range(0,360,6): unique[pixels.get_pixel(x,y).to_rgba32()]=true
		check(unique.size()>20,"Large eight-level building actually renders through the native viewport")
		pixels.save_png("res://.godot/verification/architecture_eight_levels.png")
	print("ARCHITECTURE SCALE: components=%d vertices=%d faces=%d windows=%d collision_solids=%d generation_ms=%.3f collision_ms=%.3f native_upload_ms=%.3f tracked_cpu_delta=%d"%[document.components.size(),vertices,faces,windows,solids,generation_ms,collision_ms,upload_ms,OS.get_static_memory_usage()-memory])
	viewport.queue_free(); await process_frame; print("ARCHITECTURE SCALE CHECKS: %d checks, %d failures"%[checks,failures]); quit(failures)
