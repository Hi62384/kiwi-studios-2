extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func add(type: StringName,values: Dictionary={}) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=6; clip.layer=editor.model.clips.size()-1; return editor.model.selected_actor()
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	for scenario in 3:
		editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
		view.size=Vector2i(800,600); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(.85,.9,1.25); camera.look_at(Vector3(0,.04,0)); camera.make_current()
		var world:=WorldEnvironment.new(); world.environment=Environment.new(); world.environment.background_mode=Environment.BG_COLOR; world.environment.background_color=Color("18232c"); world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; world.environment.ambient_light_color=Color.WHITE; world.environment.ambient_light_energy=.8; view.add_child(world)
		var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-30,0); view.add_child(sun)
		var floor_actor:=add(&"basic_shape",{&"box_size":Vector3(10,.2,10),&"position":Vector3(0,-.1,0)}); floor_actor.values.physics={"enabled":true,"body_mode":1,"bounce":0.0}
		var powder:=add(&"powder",{&"powder_dimensions":Vector3(.66,.08,.66),&"position":Vector3(0,.17,0),&"powder_spacing":.11,&"powder_radius":.04,&"powder_density":400.,&"powder_deposition":true,&"powder_sleep_delay":.1,&"powder_settling":.15,&"powder_restitution":0.})
		editor.model.changed.emit(); await seek(.8); var state: Dictionary=editor.physics.display_states[powder.id]; var initial: PackedVector3Array=state.points.duplicate(); var mass:=float(KiwiPowderTransport.inventory(state).total)
		check(state.powder_deposits.size()>20,"Scenario %d starts with a real attached powder layer"%scenario)
		if scenario<2:
			var tool:=add(&"basic_shape",{&"box_size":Vector3(.28,.13,.28),&"position":Vector3(0,1,0)})
			if scenario==1: tool.values.shape=2; tool.values.cylinder_top_radius=.16; tool.values.cylinder_bottom_radius=.16; tool.values.cylinder_height=.14; tool.values.rotation=Vector3(90,0,0)
			tool.values.physics={"enabled":true,"body_mode":2,"friction":.8,"bounce":0.0}
			for pair in ([[0.,Vector3(0,1,0)],[.9,Vector3(0,1,0)],[1.2,Vector3(0,-.015,0)],[1.5,Vector3(0,-.015,0)],[1.8,Vector3(0,1,0)]] if scenario==0 else [[0.,Vector3(-1,1,0)],[.9,Vector3(-1,1,0)],[1.1,Vector3(-.5,.10,0)],[1.9,Vector3(.5,.10,0)],[2.1,Vector3(1,1,0)]]): key(tool,PackedStringArray(["position"]),pair[0],pair[1])
		else:
			var fluid:=add(&"fluid",{&"position":Vector3(-.1,.12,0),&"fluid_dimensions":Vector3(.45,.2,.45),&"fluid_spacing":.1,&"fluid_budget":128})
			fluid.values.physics={"enabled":true,"activation":.9,"gravity":0.,"velocity":Vector3(2,0,0)}
		editor.model.changed.emit(); await seek(2.5); state=editor.physics.display_states[powder.id]
		var changed:=0
		for i in initial.size():
			if state.points[i].distance_to(initial[i])>.03: changed+=1
		print("TRANSPORT interaction=",scenario," releases=",state.powder_releases," moved=",changed," deposited=",state.powder_deposits.size())
		check(int(state.powder_releases)>0 and changed>0,["Foot collider leaves persistent physically displaced material","Rolling cylinder creates actual granular tracks","Flowing fluid detaches and transports deposited powder"][scenario])
		check(absf(KiwiPowderTransport.inventory(state).total-mass)<.000001,"Interaction %d conserves material instead of drawing a fake track or deleting sediment"%scenario)
		if DisplayServer.get_name()!="headless":
			await process_frame; await RenderingServer.frame_post_draw
			check(view.get_texture().get_image().save_png("res://.godot/verification/"+["powder_footprint","powder_wheel_track","powder_fluid_erosion"][scenario]+".png")==OK,"Interaction %d captures the actual native-rendered geometry"%scenario)
		var snapshot: Dictionary=editor.physics._snapshot({powder.id:state})[powder.id]; await seek(.4); await seek(2.5)
		check(editor.physics.display_states[powder.id].points==snapshot.points,"Interaction %d replays deterministically"%scenario)
		editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame
	print("POWDER TRANSPORT INTERACTIONS: %d checks, %d failures"%[checks,failures]); quit(failures)
