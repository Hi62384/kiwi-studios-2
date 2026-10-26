extends SceneTree
var failures:=0
var checks:=0
var gizmo:ActorUIGizmo
var editor:ActorTimelineEditor
var viewport:SubViewport
var lens:Camera3D
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
	print("PASS " if value else "FAIL ",label)
func click(point:Vector2,pressed:bool=true,shift:bool=false,ctrl:bool=false)->void:
	var event:=InputEventMouseButton.new();event.position=gizmo.get_global_transform_with_canvas()*point;event.global_position=event.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.shift_pressed=shift;event.ctrl_pressed=ctrl;root.push_input(event,true)
func motion(point:Vector2,ctrl:bool=false)->void:
	var event:=InputEventMouseMotion.new();event.position=gizmo.get_global_transform_with_canvas()*point;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.ctrl_pressed=ctrl;root.push_input(event,true)
func key(code:Key,ctrl:bool=false,shift:bool=false)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;event.ctrl_pressed=ctrl;event.shift_pressed=shift;root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true)
func settle()->void:
	for unused in 3:await process_frame
func make(position:Vector3,kind:StringName=&"basic_shape",extra:Dictionary={})->ActorClip:
	var values:Dictionary={&"position":position};values.merge(extra,true)
	editor.model.selected_layer=editor.model.clips.size()
	return editor.model.create_actor(editor.registry.get_definition(kind),0,values)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path("res://.godot/verification/viewport_tools");DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Viewport screenshot saves: "+name)
func run()->void:
	root.size=Vector2i(1100,720);root.gui_embed_subwindows=true
	editor=ActorTimelineEditor.new();root.add_child(editor);editor.hide()
	viewport=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	lens=Camera3D.new();viewport.add_child(lens);lens.position=Vector3(0,0,4);lens.make_current()
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("172330");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1.;viewport.add_child(environment)
	editor.runtime_holder=Node3D.new();viewport.add_child(editor.runtime_holder)
	var display:=TextureRect.new();display.position=Vector2(24,32);display.size=Vector2(960,600);display.texture=viewport.get_texture();display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;root.add_child(display)
	gizmo=ActorUIGizmo.new();gizmo.editor=editor;gizmo.display=display;display.add_child(gizmo)
	var back:=make(Vector3(0,0,-4),&"basic_shape",{&"box_size":Vector3(3,3,1)})
	var front:=make(Vector3(0,0,-2),&"basic_shape",{&"shape":1,&"sphere_radius":.5,&"sphere_height":1.})
	await settle();var center:Vector2=gizmo.spatial.project(Vector3(0,0,-2))
	check(gizmo.spatial.pick(center)==front.id,"Picking chooses the nearest surface, not creation/layer order")
	var sphere_corner:Vector2=gizmo.spatial.project(Vector3(.46,.46,-2))
	check(gizmo.spatial.pick(sphere_corner)==back.id,"Triangle picking does not select empty corners of a sphere's AABB")
	editor.model.select("");click(center);click(center,false)
	check(editor.model.selected_id==front.id,"A real viewport click selects the 3D actor")
	check(gizmo.spatial.box_lines(editor._runtime_for_clip(front.id)).size()==12,"Selection has all twelve projected bounding-box edges")
	var other:=make(Vector3(2.2,0,-3));editor.model.select(front.id)
	var other_point:Vector2=gizmo.spatial.project(Vector3(2.2,0,-3));click(other_point,true,true);click(other_point,false,true)
	check(editor.model.selected_ids.size()==2 and editor.model.selected_id==other.id,"Shift-click adds actors and makes the last clicked actor primary")
	click(other_point,true,false,true);click(other_point,false,false,true)
	check(editor.model.selected_ids==[front.id],"Ctrl-click toggles an already-selected actor off")
	var blank:=Vector2(920,560);click(blank);click(blank,false);check(editor.model.selected_ids.is_empty(),"Clicking empty viewport space clears selection")
	editor.model.select(front.id);var sphere_runtime:=editor._runtime_for_clip(front.id)
	lens.position=Vector3(5,4,6);lens.look_at(Vector3(0,0,-3));await settle()
	var original:Vector3=sphere_runtime.actor.get_value(&"position");var geometry:Dictionary=gizmo.spatial.geometry()
	if geometry.is_empty():check(false,"Selected actor has transform handle geometry");quit(1);return
	var start:Vector2=geometry.ends[0];var finish:Vector2=gizmo.spatial.project(geometry.origin+geometry.axes[0]*geometry.length*1.5)
	click(start);motion(finish);click(finish,false)
	var moved:Vector3=sphere_runtime.actor.get_value(&"position")
	check(moved.x>original.x+.05 and is_equal_approx(moved.y,original.y) and is_equal_approx(moved.z,original.z),"Dragging the X move arrow moves only along world X")
	editor.model.undo();check(sphere_runtime.actor.get_value(&"position").is_equal_approx(original),"Move handle undo restores the original transform")
	editor.model.redo();check(sphere_runtime.actor.get_value(&"position").is_equal_approx(moved),"Move handle redo restores its committed transform")
	key(KEY_Z,true);check(sphere_runtime.actor.get_value(&"position").is_equal_approx(original),"Ctrl+Z works while the viewport owns keyboard focus")
	key(KEY_Z,true,true);check(sphere_runtime.actor.get_value(&"position").is_equal_approx(moved),"Ctrl+Shift+Z redoes the viewport gesture")
	geometry=gizmo.spatial.geometry();click(geometry.ends[1]);motion(gizmo.spatial.project(geometry.origin+geometry.axes[1]*geometry.length*1.3));key(KEY_ESCAPE);click(geometry.ends[1],false)
	check(sphere_runtime.actor.get_value(&"position").is_equal_approx(moved),"Escape cancels a move without leaving a preview")
	key(KEY_E);check(gizmo.spatial.mode=="rotate","E chooses rotate while the viewport owns focus")
	geometry=gizmo.spatial.geometry();var ring:PackedVector2Array=geometry.rings[2]
	check(gizmo.spatial.begin(2,ring[0]),"A rotation ring starts a world-axis rotation")
	gizmo.spatial.update(ring[12]);gizmo.spatial.finish()
	var rotated:Vector3=sphere_runtime.actor.get_value(&"rotation")
	check(rotated.length()>10 and rotated.is_finite(),"Rotation ring writes finite actor Euler properties")
	editor.model.undo();check((sphere_runtime.actor.get_value(&"rotation") as Vector3).is_equal_approx(Vector3.ZERO),"Rotation ring is undoable")
	key(KEY_R);geometry=gizmo.spatial.geometry();click(geometry.center);motion(geometry.center+Vector2(70,0));click(geometry.center+Vector2(70,0),false)
	check((sphere_runtime.actor.get_value(&"scale") as Vector3).is_equal_approx(Vector3.ONE*1.5),"The scale center handle uniformly scales the actor")
	editor.model.undo();check(sphere_runtime.actor.get_value(&"scale")==Vector3.ONE,"Scale handle is undoable")
	key(KEY_W);editor.model.select(other.id,true);geometry=gizmo.spatial.geometry()
	var first_start:Vector3=sphere_runtime.actor.get_value(&"position");var other_actor:=editor.model.actor_for_id(other.actor_id);var other_start:Vector3=other_actor.get_value(&"position")
	gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*geometry.length*1.4));gizmo.spatial.finish()
	check((sphere_runtime.actor.get_value(&"position")-first_start).is_equal_approx(other_actor.get_value(&"position")-other_start),"A move handle applies the same world delta to all selected actors")
	editor.model.undo();check(sphere_runtime.actor.get_value(&"position").is_equal_approx(first_start) and other_actor.get_value(&"position").is_equal_approx(other_start),"One undo restores the entire multi-selection gesture")
	var parent:=make(Vector3(-2,0,-3),&"point_3d",{&"rotation":Vector3(0,30,0),&"scale":Vector3(2,1,1)})
	var child:=make(Vector3(.6,0,0));editor.model.set_parent(child.actor_id,parent.actor_id,false);editor.model.select(child.id)
	var child_runtime:=editor._runtime_for_clip(child.id);var world_start:=child_runtime.remote_transform().origin
	geometry=gizmo.spatial.geometry();gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*geometry.length*1.4));gizmo.spatial.finish()
	var world_moved:=child_runtime.remote_transform().origin
	check(world_moved.x>world_start.x+.05 and absf(world_moved.y-world_start.y)<.0001 and absf(world_moved.z-world_start.z)<.0001,"Parented actor moves along world X through rotated/scaled parent space")
	editor.model.undo();check(child_runtime.remote_transform().origin.is_equal_approx(world_start),"Parent-space movement undo is exact")
	check(gizmo.spatial.pick(gizmo.spatial.project(world_start))==child.id,"Nested geometry is picked as the child, not its parent")
	editor.model.select(parent.id);editor.model.select(child.id,true);geometry=gizmo.spatial.geometry();var local_before:Vector3=child_runtime.actor.get_value(&"position")
	gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*geometry.length*1.4));gizmo.spatial.finish()
	check(child_runtime.actor.get_value(&"position")==local_before,"A selected parent/child pair is not transformed twice")
	editor.model.undo()
	await shot("move_multiselection")
	key(KEY_E);await shot("rotate_handles");key(KEY_R);await shot("scale_handles")
	editor.exporting=true;check(not gizmo.spatial.enabled() and gizmo.spatial.pick(center).is_empty(),"Editor picking/handles are disabled for render/export")
	editor.exporting=false
	editor.model.select(child.id);key(KEY_W);geometry=gizmo.spatial.geometry();gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*geometry.length*.8));editor.model.select(parent.id);gizmo.spatial.sync()
	check(gizmo.spatial.before.is_empty() and child_runtime.actor.get_value(&"position")==local_before,"Changing selection cancels an in-progress transform safely")
	var ui:=make(Vector3.ZERO,&"basic_shape_2d");editor.model.select(ui.id);var ui_runtime:=editor._runtime_for_clip(ui.id) as ActorUIRuntime
	var ui_center:Vector2=gizmo.display_transform()*ui_runtime.anchor.position;click(ui_center);motion(ui_center+Vector2(20,10));click(ui_center+Vector2(20,10),false)
	check((ui_runtime.actor.get_value(&"position") as Vector2).length()>0,"Existing 2D direct movement still works")
	var future:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),10,{&"position":Vector3(0,0,0)})
	check(not editor._runtime_for_clip(future.id).active,"Future clips are inactive at the current time")
	var animated:=make(Vector3(1,1,-4));var animated_actor:=editor.model.actor_for_id(animated.actor_id)
	var path:=PackedStringArray(["position"])
	editor.model.playhead_time=0;editor.model.add_keyframe(animated_actor,path,"Position",Vector3(1,1,-4))
	editor.model.playhead_time=4;editor.model.add_keyframe(animated_actor,path,"Position",Vector3(3,1,-4))
	editor.canvas.playhead=2;editor._evaluate_runtimes();editor.model.select(animated.id);key(KEY_W)
	geometry=gizmo.spatial.geometry();var sampled:Vector3=editor._runtime_for_clip(animated.id).remote_transform().origin
	gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*(geometry.length+.24)),true);gizmo.spatial.finish()
	var inserted:=animated_actor.animation_track(path).key_at(2)
	check(inserted!=null and inserted.value.is_equal_approx(sampled+Vector3(.2,0,0)),"Ctrl-snapped transform inserts an animated position key at the playhead")
	check(animated_actor.values[&"position"]==Vector3(1,1,-4),"Animated transforms preserve the base property")
	editor.model.undo();check(animated_actor.animation_track(path).key_at(2)==null and animated_actor.animation_previews.is_empty(),"Undo removes the gesture's keyframe and all previews")
	editor.model.redo();check(animated_actor.animation_track(path).key_at(2)!=null,"Redo restores the gesture's keyframe")
	geometry=gizmo.spatial.geometry();var version:=editor.model.history.get_version()
	gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(geometry.ends[0]);gizmo.spatial.finish()
	check(editor.model.history.get_version()==version,"A no-op handle gesture does not create an undo entry")
	gizmo.spatial.begin(0,geometry.ends[0]);gizmo.spatial.update(gizmo.spatial.project(geometry.origin+Vector3.RIGHT*(geometry.length+.5)));editor.canvas.playhead=3;gizmo.spatial.sync()
	check(gizmo.spatial.before.is_empty() and animated_actor.animation_previews.is_empty(),"Seeking during a transform cancels rather than keying at the wrong time")
	gizmo.queue_free();editor.queue_free();display.queue_free();viewport.queue_free();await process_frame;await process_frame
	await full_workspace()
	print("VIEWPORT_SELECTION_TRANSFORM checks=%d failures=%d"%[checks,failures]);quit(failures)

func full_workspace()->void:
	root.size=Vector2i(1440,1000)
	var project_path:="user://viewport_tools_project_"+ActorData.new_id()
	DirAccess.make_dir_recursive_absolute(project_path.path_join(".proj/.trash"))
	var project:=Project.new("Viewport tools verification")
	check(ResourceSaver.save(project,project_path.path_join(".proj/Project.tres"))==OK,"Isolated application project saves")
	project.take_over_path(ProjectSettings.globalize_path(project_path.path_join(".proj/Project.tres")))
	StaticData.loaded_project=project
	var main:Node=load("res://scenes/Main.tscn").instantiate();root.add_child(main)
	for unused in 10:await process_frame
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	editor=tabs.timeline;gizmo=editor.viewport_gizmo;lens=gizmo.spatial.camera()
	check(gizmo!=null and lens!=null,"Actual Scene workspace exposes the viewport tools")
	var location:=lens.global_position-lens.global_basis.z*6
	var clip:=make(editor.runtime_holder.global_transform.affine_inverse()*location)
	await settle();var point:Vector2=gizmo.spatial.project(location)
	editor.model.select("");click(point);click(point,false)
	check(editor.model.selected_id==clip.id,"Actor picking works through the actual application UI")
	var data:Dictionary=gizmo.spatial.geometry()
	check(not data.is_empty() and gizmo.spatial.box_lines(editor._runtime_for_clip(clip.id)).size()==12,"Scene workspace displays handles and bounding box together")
	if not data.is_empty():
		var original:Vector3=editor.model.selected_actor().get_value(&"position")
		click(data.ends[0]);motion(gizmo.spatial.project(data.origin+Vector3.RIGHT*data.length*1.5));click(data.ends[0],false)
		check(editor.model.selected_actor().get_value(&"position").x>original.x,"Actual application routes handle dragging to the actor, not the inspector behind it")
		key(KEY_Z,true);check(editor.model.selected_actor().get_value(&"position").is_equal_approx(original),"Viewport undo works in the complete application")
	await shot("scene_workspace_move_handles")
	main.queue_free();await process_frame;await process_frame;StaticData.loaded_project=null
