extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var workspace:=KiwiModelWorkspace.new(); root.add_child(workspace); await process_frame; var item:=workspace.session.add("Plant / Grass",{"wind_strength":1.}); var vertices:=item.mesh.vertices.duplicate(); var original:=item.surface_materials[1]
	preload("res://Workspaces/ModelWorkspace/natural_ui.gd").appearance(workspace,item.id,"season",2)
	check(item.mesh.vertices==vertices and item.surface_materials[1]!=original,"Season color changes clone material without regenerating geometry")
	workspace.session.undo(); check(workspace.session.document.component(item.id).surface_materials[1]==original,"Season appearance changes undo without mutating shared material")
	item=workspace.session.document.component(item.id); var native:=item.render_mesh(); var material:=native.surface_get_material(0) as ShaderMaterial
	check(material!=null and material.has_meta("kiwi_time_uniform") and not material.shader.code.contains("TIME"),"Natural wind uses a controllable timeline uniform")
	var view:=SubViewport.new(); view.size=Vector2i(300,300); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var node:=MeshInstance3D.new(); node.mesh=native; view.add_child(node)
	var world:=WorldEnvironment.new(); world.environment=Environment.new(); world.environment.background_mode=Environment.BG_COLOR; world.environment.background_color=Color.BLACK; world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color=Color.WHITE; world.environment.ambient_light_energy=1.; view.add_child(world)
	var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,1,3); camera.look_at(Vector3(0,.5,0)); camera.current=true; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1.6
	var updater=preload("res://Workspaces/ModelWorkspace/natural_render.gd"); updater.time(node,0.)
	if DisplayServer.get_name()!="headless":
		for i in 5: await RenderingServer.frame_post_draw
		var a:=view.get_texture().get_image().get_data(); updater.time(node,2.)
		for i in 3: await RenderingServer.frame_post_draw
		var b:=view.get_texture().get_image().get_data(); updater.time(node,0.)
		for i in 3: await RenderingServer.frame_post_draw
		var c:=view.get_texture().get_image().get_data(); check(a!=b and a==c,"Actual wind pixels move at another time and rewind exactly")
	view.queue_free(); workspace.queue_free(); await process_frame
	print("NATURAL WIND: %d checks, %d failures"%[checks,failures]); quit(failures)
