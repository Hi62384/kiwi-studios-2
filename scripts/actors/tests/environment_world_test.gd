extends "res://scripts/actors/tests/surface_growth_test.gd"
const Coordinator=preload("res://Workspaces/EnvironmentWorkspace/environment_world_override.gd")
class Instance extends Node3D:
	var active:=true
	var actor:=ActorData.new()
	var content:=KiwiEnvironmentRuntime.new()
	var source_document:=KiwiEnvironmentDocument.new()
	var shader_time:=0.
func run() -> void:
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(128,128); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var camera:=Camera3D.new(); view.add_child(camera); camera.current=true
	var original:=Environment.new(); original.background_mode=Environment.BG_COLOR; original.background_color=Color(.05,.1,.6); var world:=view.find_world_3d(); world.environment=original
	var authored:=Environment.new(); authored.background_mode=Environment.BG_COLOR; authored.background_color=Color(.6,.1,.05); var path:="user://environment-world.tres"; ResourceSaver.save(authored,path)
	var instance:=Instance.new(); instance.actor.id="a"; instance.source_document.environment_source=path; view.add_child(instance); instance.add_child(instance.content); Coordinator.attach(instance); var coordinator:=view.get_node("KiwiEnvironmentWorld")
	coordinator._process(0.); check(world.environment==original,"Environment instance leaves the scene world alone until its world option is enabled")
	instance.content.include_atmosphere=true; coordinator._process(0.); check(world.environment!=original and world.environment.background_color.r>.5,"Opt-in environment world becomes the actual scene world")
	if DisplayServer.get_name()!="headless":
		for i in 6: await RenderingServer.frame_post_draw
		var pixel:=view.get_texture().get_image().get_pixel(64,64); check(pixel.r>pixel.b+.2,"Camera pixels show the authored environment rather than only inspector settings")
	instance.active=false; coordinator._process(0.); check(world.environment==original,"Ending an environment actor restores the previous scene world")
	var sky:=Sky.new(); var sky_material:=ShaderMaterial.new(); sky_material.shader=Shader.new(); var code:="shader_type sky; void sky(){ COLOR=vec3(0.2+sin(TIME)*0.1,0.3,0.4); }"; sky_material.shader.code=code; sky.sky_material=sky_material; authored.sky=sky; authored.background_mode=Environment.BG_SKY; ResourceSaver.save(authored,path); KiwiEnvironmentAssets.invalidate(path); instance.active=true; instance.shader_time=2.5; coordinator._process(0.)
	var runtime_material:=coordinator.owned.sky.sky_material as ShaderMaterial; var uniform:=str(runtime_material.get_meta("kiwi_time_uniform","")); check(not uniform.is_empty() and is_equal_approx(runtime_material.get_shader_parameter(uniform),2.5) and sky_material.shader.code==code,"Native sky TIME is controlled by the scene timeline without modifying authored shader code")
	instance.shader_time=.75; coordinator._process(0.); check(is_equal_approx(runtime_material.get_shader_parameter(uniform),.75),"Rewinding an environment updates its existing sky shader time")
	instance.active=true; coordinator._process(0.); var unrelated:=Environment.new(); world.environment=unrelated; instance.active=false; coordinator._process(0.); check(world.environment==unrelated,"Releasing ownership does not overwrite another world assigned in the meantime")
	world.environment=original; instance.active=true; coordinator._process(0.); instance.queue_free(); await process_frame; coordinator._process(0.); check(world.environment==original,"Deleting an environment instance releases world ownership")
	var empty: Node=load("res://Workspaces/EnvironmentWorkspace/environment_actor.gd").new(); view.add_child(empty); empty.content.include_lighting=true; empty._load_source("")
	check(empty.content.sun==null or not empty.content.sun.visible,"A missing environment source does not create an unintended default sun")
	view.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("ENVIRONMENT WORLD: %d checks, %d failures"%[checks,failures]); quit(failures)
