extends SceneTree
var failures := 0
var checks := 0
var workspace: KiwiModelWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func settle() -> void:
	for i in 4: await process_frame
func click(point: Vector2, pressed: bool=true, shift: bool=false) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.shift_pressed=shift; event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(event,true)
func key(code: Key, ctrl: bool=false) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true; event.ctrl_pressed=ctrl; root.push_input(event,true)
	event=event.duplicate(); event.pressed=false; root.push_input(event,true)
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame; await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://.godot/verification/model_workspace"); DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"Native screenshot: "+label)
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true
	workspace=KiwiModelWorkspace.new(); root.add_child(workspace); workspace.open_source(KiwiModelDocument.new()); await settle()
	check(workspace.canvas.size.x>root.size.x*.5,"Viewport occupies most of the modeling workspace")
	var session := workspace.session; var box := session.add("Box"); workspace.canvas.frame(); await settle()
	var center := workspace.canvas.project(Vector3.ZERO); session.select(""); click(center); click(center,false)
	check(session.primary()!=null and session.primary().id==box.id,"Root viewport click selects model geometry")
	var handles := workspace.canvas.geometry(); var original := session.primary().transform
	click(handles.ends[0]); motion(workspace.canvas.project(handles.pivot+handles.axes[0]*handles.length*1.5)); click(handles.ends[0],false)
	check(session.primary().transform.origin.x>original.origin.x,"Visible move handle transforms component live")
	key(KEY_Z,true); check(session.primary().transform.is_equal_approx(original),"One viewport undo restores complete drag")
	key(KEY_4); workspace.canvas.set_view("Front"); await settle(); center=workspace.canvas.project(Vector3.ZERO); click(center); click(center,false)
	check(session.mode=="Face" and session.elements.size()==1,"Face selection uses actual ray-triangle geometry")
	workspace.canvas.begin_extrusion(center); workspace.canvas.update_extrusion(center+Vector2(0,-40)); workspace.canvas.finish_extrusion()
	check(session.primary().mesh.faces.size()==10,"Direct push/pull adds editable side faces")
	key(KEY_Z,true); check(session.primary().mesh.faces.size()==6,"One undo restores push/pull topology")
	workspace.canvas.begin_extrusion(center); workspace.canvas.update_extrusion(center+Vector2(0,-20)); workspace.canvas.finish_extrusion(true)
	check(session.primary().mesh.faces.size()==6,"Escape/cancel restores extrusion without history damage")
	await shot("face_editing")
	# Acceptance A: table, duplicated independently editable legs and true bevel.
	session=KiwiModelSession.new(); workspace.open_source(KiwiModelDocument.new(),{"session":session}); session.mode="Object"
	var top := session.add("Box",{"size":Vector3(4,.25,2)},Vector3(0,1.5,0)); top.title="Tabletop"
	top.mesh=KiwiModelGeometry.bevel(top.mesh,PackedInt32Array(),.025); top.generator=""
	for x in [-1.7,1.7]:
		for z in [-.7,.7]: session.add("Box",{"size":Vector3(.2,1.4,.2)},Vector3(x,.7,z)).title="Leg"
	check(session.document.components.size()==5 and top.mesh.validate().is_empty(),"Table workflow creates top, bevel and four editable legs")
	workspace.canvas.yaw=.65; workspace.canvas.pitch=-.35; workspace.canvas.camera.projection=Camera3D.PROJECTION_PERSPECTIVE; workspace.canvas.frame(true); await settle()
	check(await workspace.save_to("user://model_table.tres")==OK,"Editable table saves with workspace state")
	var reopened := KiwiModelImport.load_document("user://model_table.tres")
	check(reopened.components.size()==5 and reopened.components[0].mesh.faces.size()>6 and reopened.workspace_state.has("view"),"Reopening preserves geometry and view state")
	await shot("table")
	# Acceptance B: gear assemblies and a real through-hole in the housing.
	var housing := KiwiModelPrimitives.box(Vector3(2,2,2)); var cutter := KiwiModelPrimitives.create("Cylinder",{"radius":.3,"height":4.,"segments":16})
	var cut := await KiwiModelImport.boolean(workspace.canvas.world,housing,cutter,Transform3D.IDENTITY,CSGShape3D.OPERATION_SUBTRACTION)
	check(cut!=null and cut.validate().is_empty(),"Boolean difference produces valid editable polygon data")
	if cut!=null:
		var triangle_mesh := cut.render_mesh().generate_triangle_mesh()
		check(triangle_mesh.intersect_ray(Vector3(0,4,0),Vector3.DOWN).is_empty(),"Cylinder subtraction cuts a real through-hole, not a visual overlay")
		check(not triangle_mesh.intersect_ray(Vector3(.8,4,.8),Vector3.DOWN).is_empty(),"Boolean preserves the housing outside the hole")
	var gear := session.add("Gear",{"teeth":12,"hole":.12},Vector3(3,1,0)); gear.modifiers.append({"type":"Linear array","axis":2,"count":3,"amount":1.5})
	check(KiwiModelModifiers.evaluate(gear).faces.size()==gear.mesh.faces.size()*3,"Mechanical workflow uses evaluated arrays while retaining editable source")
	# Acceptance C: organic primitives with symmetry and local deformation.
	var body := session.add("Sphere",{"segments":12}); body.modifiers.append({"type":"Mirror","axis":0}); var vertices := body.mesh.vertices.duplicate()
	body.mesh=KiwiModelGeometry.smooth_mesh(body.mesh,.2)
	check(body.mesh.validate().is_empty() and body.mesh.vertices!=vertices,"Organic smoothing modifies geometry without breaking topology")
	# Acceptance D: walls and an inset/extruded room panel remain scene-compatible.
	var wall := session.add("Box",{"size":Vector3(4,3,.3)}); session.mode="Face"; session.elements=PackedInt32Array([1])
	check(session.edit_mesh("Inset",.1).is_empty() and session.edit_mesh("Extrude",-.1).is_empty(),"Room workflow supports inset and recessed wall geometry")
	await shot("assemblies")
	workspace.queue_free(); await process_frame; await process_frame
	print("MODEL_WORKSPACE checks=%d failures=%d"%[checks,failures]); quit(failures)
