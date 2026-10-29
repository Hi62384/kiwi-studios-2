extends "res://scripts/actors/tests/destruction_timeline_test.gd"
const Ground=preload("res://scripts/actors/fog/fog_ground_sampler.gd")
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var floor_actor:=add(&"basic_shape",{&"position":Vector3(0,-.1,0),&"box_size":Vector3(8,.2,8)}); floor_actor.values.physics={"enabled":true,"body_mode":1}
	var hill:=add(&"basic_shape",{&"position":Vector3(1,1,0),&"box_size":Vector3(2,2,6)}); hill.values.physics={"enabled":true,"body_mode":1}
	var field:=editor.registry.get_object_definition(&"fog_field").create_object(); field.values.merge({&"mode":8,&"cloud_type":4,&"cloud_follow_ground":true,&"cloud_ground_falloff":.5,&"cloud_coverage":1.},true)
	var fog:=add(&"fog_volume",{&"position":Vector3(0,2,0),&"volume_size":Vector3(6,6,6),&"shape":3,&"field":ActorObjectReference.from_object(field)}); editor.model.changed.emit(); await seek(0.)
	var runtime: Node=editor._runtime_for_clip(editor.model.clip_for_actor_id(fog.id).id); var settings:=ActorAnimation.resolve_reference(fog.values[&"field"]).values; var result:=Ground.prepare(editor.physics,runtime.content.global_transform,runtime.content.size,settings)
	check(result.get("image") is Image and result.hits>0,"Ground mist samples actual scene collision surfaces")
	if result.get("image") is Image:
		var low:=Ground.sample_height(result.image,Vector3(.2,.5,.5)); var high:=Ground.sample_height(result.image,Vector3(.65,.5,.5)); print("GROUND HEIGHT valley=",low," hill=",high," ms=",result.milliseconds)
		check(high>low+1.5,"Height sampling follows raised terrain instead of a single horizontal fog plane")
		check(Ground.prepare(editor.physics,runtime.content.global_transform,runtime.content.size,settings).texture==result.texture,"Unchanged collision surfaces reuse their bounded height texture")
		for i in 3: await process_frame
		check(runtime.content.material.get_shader_parameter("scene_ground")==true,"Native fog rendering receives the sampled terrain height field")
		var old_key: int=result.key; hill.values[&"position"]=Vector3(1,2,0); editor.model.changed.emit(); await seek(0.); result=Ground.prepare(editor.physics,runtime.content.global_transform,runtime.content.size,settings)
		check(result.key!=old_key and Ground.sample_height(result.image,Vector3(.65,.5,.5))>high+.8,"Moving a terrain collider invalidates the height cache and updates mist")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame; print("FOG GROUND: %d checks, %d failures"%[checks,failures]); quit(failures)
