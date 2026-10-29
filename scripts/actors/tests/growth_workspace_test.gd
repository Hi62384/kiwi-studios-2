extends "res://scripts/actors/tests/powder_material_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var workspace:=KiwiModelWorkspace.new(); root.add_child(workspace); await settle(8); var session:=workspace.session; var source:=session.add("Plane",{"size":Vector3(2,1,2)}); var source_id:=source.id; await settle()
	check(workspace.context.find_children("*","Button",true,false).any(func(node: Button): return node.text=="Surface growth…"),"Native Modeling Workspace exposes the surface growth menu")
	check(KiwiSurfaceGrowth.add(session,0).is_empty(),"Generation works in the running native workspace"); await settle(8); var growth_id:=session.primary().id
	var toggle:=workspace.properties.find_child("GrowthGroomMode",true,false) as CheckButton; check(toggle!=null,"A growth component exposes compact Groom mode controls"); await click(toggle); await settle()
	var canvas:=workspace.canvas; canvas.camera.global_position=Vector3(0,3,4); canvas.camera.look_at(Vector3.ZERO); canvas.groom_tool.tool="Comb"; canvas.groom_tool.radius=.65; canvas.groom_tool.strength=.8
	var start:=canvas.project(Vector3(-.3,0,0)); var end:=canvas.project(Vector3(.3,0,0))
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new(); input.button_index=MOUSE_BUTTON_LEFT; input.pressed=pressed; input.position=canvas.get_global_transform_with_canvas()*(start if pressed else end); input.global_position=input.position; root.push_input(input,true)
		if pressed:
			for step in range(1,6):
				var move:=InputEventMouseMotion.new(); move.button_mask=MOUSE_BUTTON_MASK_LEFT; move.position=canvas.get_global_transform_with_canvas()*start.lerp(end,float(step)/5); move.global_position=move.position; root.push_input(move,true); await process_frame
	await settle(); var data:=session.document.component(growth_id).growth
	check(data.groom_layers.size()==1 and data.groom_layers[0].changes.size()>0,"Real viewport brushing creates one sparse grooming layer on mouse release")
	var final:=data.groom_layers.duplicate(true); session.undo(); await settle(); check(session.document.component(growth_id).growth.groom_layers.is_empty(),"One undo restores the entire continuous viewport stroke")
	session.redo(); await settle(); check(session.document.component(growth_id).growth.groom_layers==final,"Redo restores procedural grooming and visible geometry")
	var original: int=session.document.component(growth_id).growth.groom_layers.size(); canvas.groom_tool.drawing=true; canvas.groom_tool.component_id=growth_id; canvas.groom_tool.stroke_id="cancel"; canvas.groom_tool.apply_at(session.document.component(growth_id).growth,Vector3.ZERO,Vector3(.1,0,0),Vector3.UP); canvas.groom_tool.finish(true); check(session.document.component(growth_id).growth.groom_layers.size()==original,"Cancel discards uncommitted grooming without adding history")
	check(session.document.component(source_id).mesh.vertices==source.mesh.vertices,"Viewport grooming leaves the base surface intact")
	canvas.groom_tool.tool="Guide"; canvas.groom_tool.create_guide(0); await settle(); data=session.document.component(growth_id).growth; var guide_id:=canvas.groom_tool.selected_guide; var before_point: Vector3=data.guides[guide_id].points[3]
	var handle:=canvas.project(canvas.groom_tool.guide_frame()*before_point)
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new(); input.button_index=MOUSE_BUTTON_LEFT; input.pressed=pressed; input.position=canvas.get_global_transform_with_canvas()*(handle if pressed else handle+Vector2(20,0)); input.global_position=input.position; root.push_input(input,true)
		if pressed:
			var move:=InputEventMouseMotion.new(); move.button_mask=MOUSE_BUTTON_MASK_LEFT; move.position=canvas.get_global_transform_with_canvas()*(handle+Vector2(20,0)); move.global_position=move.position; root.push_input(move,true)
	await settle(); data=session.document.component(growth_id).growth; check(data.guides[guide_id].points[0]==Vector3.ZERO and data.guides[guide_id].points[3]!=before_point,"Dragging a visible guide handle changes its curve while preserving the root")
	session.undo(); await settle(); check((session.document.component(growth_id).growth.guides[guide_id].points[3] as Vector3).is_equal_approx(before_point),"A continuous guide-handle drag is one undoable action")
	await RenderingServer.frame_post_draw; check(root.get_texture().get_image().save_png("res://.godot/verification/growth_workspace.png")==OK,"Native growth/groom screenshot captured")
	workspace.queue_free(); await settle(); print("GROWTH WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
