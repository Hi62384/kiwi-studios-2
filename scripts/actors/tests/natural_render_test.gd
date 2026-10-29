extends "res://scripts/actors/tests/surface_growth_test.gd"
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
func run() -> void:
	var view:=SubViewport.new(); view.size=Vector2i(1100,650); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var world:=WorldEnvironment.new(); world.environment=Environment.new(); world.environment.background_mode=Environment.BG_COLOR; world.environment.background_color=Color("182732"); world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color=Color.WHITE; world.environment.ambient_light_energy=.65; view.add_child(world)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); light.light_energy=2.; view.add_child(light)
	var kinds: Array=["Tree / Oak","Tree / Pine","Tree / Palm","Tree / Willow","Tree / Acacia","Tree / Ancient"]
	for index in kinds.size():
		var result:=Generator.generate(kinds[index],{}); var node:=MeshInstance3D.new(); node.mesh=result.mesh.render_mesh(Generator.materials(kinds[index])); node.position=Vector3((index%3-1)*10.,0.,(index/3)*11.); view.add_child(node)
	var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(23,21,36); camera.look_at(Vector3(0,3,5)); camera.current=true; camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=33.
	if DisplayServer.get_name()!="headless":
		for i in 7: await RenderingServer.frame_post_draw
		var image:=view.get_texture().get_image(); var colors: Dictionary={}; var green:=0
		for y in range(0,image.get_height(),3):
			for x in range(0,image.get_width(),3):
				var color:=image.get_pixel(x,y); colors[color.to_html()]=true
				if color.g>color.r*1.15 and color.g>color.b*1.1: green+=1
		check(colors.size()>200 and green>100,"Actual native viewport renders detailed bark and foliage silhouettes")
		image.save_png("res://.godot/verification/natural_tree_showcase.png")
	view.queue_free(); await process_frame
	print("NATURAL RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
