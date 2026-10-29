extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(600,400); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var cube:=add(&"basic_shape",{&"position":Vector3(0,2,0)})
	cube.values.physics={"enabled":true,"gravity":1.0,"collision":false}
	var error:=await editor.physics.bake_group(editor,0,1,30)
	check(error.is_empty(),"Original interacting bake completes")
	var previous: Dictionary=cube.values.physics.bake.duplicate(); var old: KiwiPhysicsBakeCache=previous.cache; var exact: Transform3D=old.frame(30)[cube.id].pose
	error=await editor.physics.bake_group(editor,0,1,30,Callable(),{"reuse":previous,"recalculate_from":.5,"external":true,"directory":"user://interval-bakes"})
	check(error.is_empty(),"Verified interval resumes from a fixed-step checkpoint: "+error)
	var next: KiwiPhysicsBakeCache=cube.values.physics.bake.cache
	check(next!=old and next.frame(10)[cube.id].pose==old.frame(10)[cube.id].pose,"Unchanged prefix is preserved exactly")
	check(next.frame(30)[cube.id].pose.is_equal_approx(exact),"Resumed simulation matches full recalculation")
	editor.model.undo(); check(cube.values.physics.bake.cache==old,"Interval replacement is one atomic undo")
	editor.model.redo(); check(cube.values.physics.bake.cache==next,"Redo restores streamed interval cache")
	var altered:=KiwiPhysicsSettings.authored(cube); altered.gravity=2.; cube.values.physics=altered
	error=await editor.physics.bake_group(editor,0,1,30,Callable(),{"reuse":previous,"recalculate_from":.5})
	check(error.contains("earlier physical edits") and cube.values.physics.bake.cache==next,"Earlier physical edits reject unsafe prefix reuse without replacing the bake")
	next.abort_stream(); editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("BAKE INTERVAL: %d checks, %d failures"%[checks,failures]); quit(failures)
