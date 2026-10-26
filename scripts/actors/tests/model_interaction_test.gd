extends SceneTree
var failures := 0
var checks := 0
var workspace: KiwiModelWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(text)
	print("PASS " if ok else "FAIL ",text)
func settle() -> void:
	for i in 4: await process_frame
func click(point: Vector2, pressed: bool=true) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; root.push_input(event,true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=workspace.canvas.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiModelWorkspace.new(); root.add_child(workspace)
	workspace.open_source(KiwiModelDocument.new()); var session := workspace.session; var canvas := workspace.canvas
	var box := session.add("Box"); canvas.frame(); await settle()
	var data := canvas.geometry(); var count := session._undo.size()
	canvas.begin_transform(0,data.ends[0]); canvas.finish_transform()
	check(session._undo.size()==count,"Clicking a handle without dragging creates no history entry")
	session.duplicate_selected(true); data=canvas.geometry(); canvas.begin_transform(-1,data.center); canvas.update_transform(data.center+Vector2(20,0)); canvas.finish_transform(true)
	check(session.document.components.size()==1 and session._undo.size()==count,"Cancelling duplicate-and-move restores the pre-duplicate document")
	session.duplicate_selected(true); data=canvas.geometry(); canvas.begin_transform(-1,data.center); canvas.update_transform(data.center+Vector2(20,0)); canvas.finish_transform()
	check(session.document.components.size()==2 and session._undo.size()==count+1,"Duplicate-and-move commits one combined undo action")
	session.undo(); check(session.document.components.size()==1,"One undo removes the moved duplicate")
	session.mode="Vertex"; session.elements=PackedInt32Array([7]); var old := session.primary().mesh.vertices.duplicate(); data=canvas.geometry()
	canvas.begin_transform(0,data.ends[0]); canvas.update_transform(canvas.project(data.pivot+data.axes[0]*data.length*1.5)); canvas.finish_transform()
	check(session.primary().mesh.vertices[7].x>old[7].x and session.primary().mesh.vertices[0]==old[0],"Vertex handle modifies only selected geometry")
	session.undo(); check(session.primary().mesh.vertices==old,"Vertex editing undo restores exact positions")
	canvas.proportional=true; canvas.radius=2.; data=canvas.geometry()
	canvas.begin_transform(0,data.ends[0]); var endpoint := canvas.project(data.pivot+data.axes[0]*data.length*1.5); canvas.update_transform(endpoint)
	var selected_delta := session.primary().mesh.vertices[7].x-old[7].x; var neighbor_delta := session.primary().mesh.vertices[6].x-old[6].x
	check(neighbor_delta>0. and neighbor_delta<selected_delta,"Proportional editing moves neighboring vertices with distance falloff")
	canvas.radius=.4; canvas.update_transform(endpoint)
	check(session.primary().mesh.vertices[6]==old[6],"Reducing proportional radius restores points which leave the falloff")
	canvas.finish_transform(true); canvas.proportional=false
	session.mode="Edge"; session.elements=PackedInt32Array([0]); var edge := session.primary().mesh.edges()[0]; data=canvas.geometry()
	canvas.begin_transform(1,data.ends[1]); canvas.update_transform(canvas.project(data.pivot+data.axes[1]*data.length*1.4)); canvas.finish_transform()
	check(session.primary().mesh.vertices[edge.a].y>old[edge.a].y and session.primary().mesh.vertices[edge.b].y>old[edge.b].y,"Edge handle transforms both connected endpoints")
	session.undo(); session.mode="Object"; session.elements=PackedInt32Array(); canvas.tool="Scale"; data=canvas.geometry()
	canvas.begin_transform(2,data.ends[2]); canvas.update_transform(data.ends[2]+(data.ends[2]-data.center)*.5); canvas.finish_transform()
	check(absf(session.primary().transform.basis.get_scale().z-1.5)<.01,"Axis scale follows its projected handle rather than arbitrary screen X")
	session.undo(); canvas.tool="Rotate"; data=canvas.geometry(); var ring: PackedVector2Array=data.rings[1]
	canvas.begin_transform(1,ring[0]); canvas.update_transform(ring[8]); canvas.finish_transform()
	check(absf(session.primary().transform.basis.get_euler().y)>.1,"Rotation ring performs an actual axis rotation")
	session.undo(); canvas.tool="Move"; canvas.set_view("Front"); session.mode="Vertex"; session.elements=PackedInt32Array(); await settle()
	canvas.xray=false; canvas.box_select(Rect2(Vector2.ZERO,canvas.size),false); var visible_count := session.elements.size()
	canvas.xray=true; canvas.box_select(Rect2(Vector2.ZERO,canvas.size),false)
	check(visible_count<session.elements.size() and session.elements.size()==8,"X-ray rectangle selection includes vertices hidden behind the surface")
	canvas.xray=false; session.mode="Object"; session.elements=PackedInt32Array()
	var other := session.add("Cylinder",{},Vector3(2,0,0)); canvas.sync(); var cached := (canvas.visuals[other.id] as MeshInstance3D).mesh.get_instance_id()
	session.select(box.id); session.action("Edit one component",func(): session.primary().mesh.vertices[0].x-=.1); canvas.sync()
	check((canvas.visuals[other.id] as MeshInstance3D).mesh.get_instance_id()==cached,"Unchanged components retain their evaluated rendering mesh")
	canvas.camera.projection=Camera3D.PROJECTION_PERSPECTIVE; canvas.pitch=-.5; canvas.yaw=.6; canvas.frame(true); await settle()
	var before_count := session.document.components.size(); var before_history := session._undo.size(); canvas.start_creation("Box")
	var start := canvas.size*.5; click(start); motion(start+Vector2(70,45)); click(start+Vector2(70,45),false); motion(start+Vector2(70,-20)); click(start+Vector2(70,-20)); click(start+Vector2(70,-20),false)
	check(session.document.components.size()==before_count+1 and session.primary().mesh.validate().is_empty(),"Interactive footprint-and-height creation produces valid geometry")
	check(session._undo.size()==before_history+1,"Interactive creation is one undoable gesture")
	session.undo(); check(session.document.components.size()==before_count,"One undo removes the interactively created component")
	var plate := session.add("Box",{"size":Vector3(3,.2,3)},Vector3(0,-1,0)); plate.transform.basis=Basis(Vector3.FORWARD,.3)
	var bolt := session.add("Bolt",{"radius":.2,"height":.6},Vector3(0,2,0)); canvas.frame(true); await settle(); canvas.sync()
	canvas.snap=true; canvas.snap_kind="Surface"; canvas.align_surface=true; canvas.tool="Move"; data=canvas.geometry()
	var point := canvas.project(session.document.world_transform(plate)*Vector3(0,.1,0)); var hit := canvas.pick(point,[bolt.id])
	check(not hit.is_empty(),"Surface placement finds the angled target mesh")
	canvas.begin_transform(-1,data.center); canvas.update_transform(point); canvas.finish_transform()
	if not hit.is_empty():
		check(session.primary().transform.basis.y.normalized().dot(hit.normal)>.99,"Surface placement aligns the component to the hit normal")
		var minimum := INF
		for vertex in session.primary().mesh.vertices: minimum=minf(minimum,(session.document.world_transform(session.primary())*vertex-hit.point).dot(hit.normal))
		check(absf(minimum)<.001,"Surface placement rests the mesh on the surface instead of burying its origin")
	# A second source tab retains the first session, and captures cancel previews.
	canvas.snap=false; data=canvas.geometry(); var transform := session.primary().transform; canvas.begin_transform(0,data.ends[0]); canvas.update_transform(data.ends[0]+Vector2(30,0)); var retained := workspace.capture_state()
	check(session._gesture.is_empty() and session.primary().transform.is_equal_approx(transform),"Switching documents cancels unfinished transforms before capture")
	workspace.open_source(KiwiModelDocument.new()); workspace.session.add("Cone"); workspace.open_source(KiwiModelDocument.new(),retained)
	check(workspace.session==session and workspace.session.primary().id==bolt.id,"Each model document retains its own undoable edit session")
	root.size=Vector2i(960,700); workspace._initial_layout(); await settle()
	check(canvas.size.x>root.size.x*.5,"Compact window prioritizes viewport and keeps optional hierarchy collapsible")
	workspace.queue_free(); await process_frame; await process_frame
	print("MODEL_INTERACTION checks=%d failures=%d"%[checks,failures]); quit(failures)
