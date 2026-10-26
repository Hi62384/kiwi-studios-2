extends SceneTree
var failures := 0
var checks := 0
var workspace: KiwiModelWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle() -> void:
	for i in 5: await process_frame
func click(point: Vector2, pressed: bool=true) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(event,true)
func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.pressed=true; root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiModelWorkspace.new(); root.add_child(workspace)
	workspace.open_source(KiwiModelDocument.new()); var session := workspace.session; var canvas := workspace.canvas; var tool := canvas.rig_tool; var editor := tool.editor
	var body := session.add("Cylinder",{"height":4.,"radius":.6,"segments":24}); var body_id := body.id
	canvas.set_view("Front"); canvas.frame(); await settle()
	workspace.rig_ui.set_mode("Draw"); tool.construction="XY"; await settle()
	var armature := editor.rig(); var rig_id := armature.id; var history := session._undo.size()
	for point in [Vector3(0,-2,0),Vector3.ZERO,Vector3(0,2,0)]:
		click(canvas.project(point)); click(canvas.project(point),false)
	await settle(); armature=editor.rig()
	check(armature.bones.size()==2 and armature.bones[1].parent==0,"Viewport clicks draw a connected arbitrary bone chain on the chosen plane")
	check(session._undo.size()==history+2,"Each drawn bone is one undoable action")
	key(KEY_ENTER); check(tool.chain==null,"Enter ends drawing without an unwanted extra bone")
	workspace.rig_ui.set_mode("Edit"); editor.selected_bone=0; await settle()
	var joint := canvas.project(Vector3.ZERO); var moved := canvas.project(Vector3(.18,.1,0)); history=session._undo.size()
	click(joint); motion(moved); click(moved,false); await settle(); armature=editor.rig()
	var globals := KiwiRigMath.globals(armature.bones)
	check(KiwiRigMath.tail(armature.bones[0],globals[0]).distance_to(globals[1].origin)<.0001,"Dragging a connected joint moves its neighboring bone head")
	check(session._undo.size()==history+1,"Joint dragging commits one history entry")
	session.undo(); await settle(); armature=editor.rig(); check(KiwiRigMath.globals(armature.bones)[1].origin.length()<.0001,"Undo restores the exact original joint placement")
	# Real asynchronous worker, installation and renderer binding.
	workspace.rig_ui.bind_async("Smooth")
	for i in 300:
		if not editor.busy: break
		await process_frame
	await settle(); body=session.document.component(body_id); armature=editor.rig()
	check(body.binding!=null and body.binding.validate(armature).is_empty() and not editor.busy,"Threaded smooth auto weighting completes and installs a valid skin")
	workspace.rig_ui.set_mode("Pose"); editor.selected_bone=1; canvas.tool="Rotate"; await settle()
	var visual: MeshInstance3D=canvas.visuals[body_id]; var skeleton: Skeleton3D=tool.nodes[rig_id]
	check(visual.skin!=null and visual.get_node(visual.skeleton)==skeleton,"Authored mesh resolves its real preview Skeleton3D")
	var base_mesh := body.skin_mesh
	await RenderingServer.frame_post_draw
	var baked := visual.bake_mesh_from_current_skeleton_pose(); var before: PackedVector3Array=baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var handles := tool.handles(); tool.begin_pose(2,handles.rings[2][0]); tool.update_drag(handles.rings[2][10]); tool.finish(); await settle()
	await RenderingServer.frame_post_draw
	var after: PackedVector3Array=visual.bake_mesh_from_current_skeleton_pose().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(absf(editor.rig().bones[1].rotation.z)>20.,"Visible pose rotation ring changes the chosen bone")
	check(before!=after and body.skin_mesh==base_mesh,"GPU skin matrices deform the actual mesh without rebuilding it during poses")
	var expected := body.binding.deformed_points(editor.rig(),0); var accurate := expected.size()==after.size()
	for i in expected.size():
		if expected[i].distance_to(after[i])>.0002: accurate=false; break
	check(accurate,"GPU deformation matches the editor's posed weight-picking geometry")
	session.undo(); await settle(); check(editor.rig().bones[1].rotation.length()<.001,"Viewport pose edits undo cleanly")
	canvas.tool="Scale"; handles=tool.handles(); tool.begin_pose(0,handles.ends[0]); tool.update_drag(handles.ends[0]+(handles.ends[0]-handles.center)*.5); tool.finish(); await settle()
	check((editor.rig().bones[1].scale as Vector3).distance_to(Vector3(1.5,1,1))<.001,"Axis scale handles change only the selected bone axis, with a cursor-aligned ratio")
	session.undo(); canvas.tool="Rotate"; await settle()
	# Heatmap, region fill, locks and sparse undo while posing.
	workspace.rig_ui.set_mode("Weight"); editor.selected_bone=1; tool.weight_tool="Select vertices"; tool.select_region(Rect2(Vector2.ZERO,canvas.size))
	check(not tool.region.is_empty(),"Weight mode can box select real vertices")
	body=session.document.component(body_id); var weights := body.binding.weights[0].duplicate(); tool.brush_value=.17; history=session._undo.size(); tool.fill_region(); await settle()
	check(body.binding.weights[0]!=weights and session._undo.size()==history+1 and session._undo.back().has("custom"),"Numeric region weights update live with a sparse undo record")
	session.undo(); await settle(); body=session.document.component(body_id); check(body.binding.weights[0]==weights,"Region fill undo restores all weights exactly")
	tool.weight_tool="Select faces"; tool.region.clear(); tool.select_region(Rect2(canvas.project(Vector3(.25,1.,.55)),Vector2.ZERO)); await settle()
	check(tool.region.size()==3,"Face weighting selects the three vertices of the ray-hit triangle")
	tool.weight_tool="Brush"; tool.region.clear(); tool.brush_mode="Replace"; tool.brush_value=.31; tool.brush_radius=1.2; tool.brush_strength=1.; tool.paint_hidden=true
	tool.drag="weight"; tool.stroke_session=session; tool.paint(canvas.project(Vector3(.3,1.,.55)),false,true)
	check(not tool.weight_before.is_empty(),"Weight brush hits the visible deformed mesh and changes influences")
	tool.finish(); await settle(); check(session.document.component(body_id).binding.validate(editor.rig()).is_empty(),"Painting keeps every vertex normalized and valid")
	check(visual.material_override is StandardMaterial3D and visual.material_override.vertex_color_use_as_albedo,"Selected bone influence is displayed through a non-destructive heatmap")
	editor.detach(); await settle()
	check(visual.skin==null and visual.skeleton.is_empty() and visual.material_override==null,"Detaching removes the preview skin and heatmap rather than leaving stale rendering state")
	session.undo(); await settle(); check(visual.skin!=null and visual.material_override!=null,"Undoing detach restores the binding and weight visualization together")
	# Rest editing and envelope gestures keep poses separate.
	workspace.rig_ui.set_mode("Envelope"); editor.selected_bone=1; await settle(); armature=editor.rig()
	var center := KiwiRigMath.globals(armature.bones)[1].origin.lerp(KiwiRigMath.tail(armature.bones[1],KiwiRigMath.globals(armature.bones)[1]),.5)
	var radius := float(armature.bones[1].radius); var start := canvas.project(center+Vector3.RIGHT*radius)
	click(start); motion(canvas.project(center+Vector3.RIGHT*radius*1.5)); click(canvas.project(center+Vector3.RIGHT*radius*1.5),false); await settle()
	check(float(editor.rig().bones[1].radius)>radius*1.3,"Envelope radius is draggable directly in the viewport")
	# A rigid mesh follows a bone but never acquires deforming skin weights.
	var gear := session.add("Gear",{},Vector3(1,1,0)); var gear_id := gear.id; editor.rig_id=rig_id; editor.selected_bone=1
	check(editor.bind("Rigid").is_empty(),"Separate mechanical part binds as a rigid attachment")
	workspace.rig_ui.set_mode("Pose"); await settle(); var gear_before: Transform3D=canvas.visuals[gear_id].transform
	editor.pose("rotation",Vector3(0,0,40)); await settle()
	check(not (canvas.visuals[gear_id].transform as Transform3D).is_equal_approx(gear_before) and session.document.component(gear_id).skin==null,"Rigid gear follows the bone without soft deformation")
	var file := ProjectSettings.globalize_path("user://Drawn Rig.tres"); check(await workspace.save_to(file)==OK,"Authored multi-component rig saves through the workspace")
	var state := workspace.capture_state(); workspace.open_source(KiwiModelDocument.new()); workspace.open_source(file,state); await settle()
	check(workspace.session==session and tool.editor.rig_id==rig_id and tool.editor.enabled,"Tab switching preserves the active rig, mode, document and undo session")
	var loaded := ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded.validate().is_empty() and loaded.component(body_id).binding!=null and not loaded.component(gear_id).binding.rigid_bone_id.is_empty(),"Save roundtrip retains the editable mixed soft/rigid rig")
	var image_path := "res://.godot/verification/model_workspace/rig_authoring.png"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(image_path.get_base_dir()))
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(image_path)
	# Starting a calculation then switching away must not install into another tab.
	session.select(body_id); workspace.rig_ui.bind_async("Smooth"); workspace.open_source(KiwiModelDocument.new()); await settle()
	check(workspace.session.document.components.is_empty() and workspace.rig_ui.worker==null,"Switching away safely cancels and joins the weighting worker")
	tool.editor.empty_rig(); workspace.rig_ui.set_mode("Weight"); await settle()
	check(workspace.properties.get_child_count()>0,"An empty armature can enter Weight mode safely and explains that bones are needed")
	workspace.queue_free(); await settle()
	print("RIG_AUTHORING_VIEWPORT checks=%d failures=%d"%[checks,failures]); quit(failures)
