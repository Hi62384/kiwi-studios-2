class_name KiwiPhysicsMeshSnapshot
extends RefCounted
## Explicit, bounded conversion to a normal reusable mesh. Simulation/source data
## is never overwritten. The saved mesh uses world coordinates at this playhead.
const MAX_VERTICES:=150000
static func capture(editor: ActorTimelineEditor,actor: ActorData,deposits_only: bool=false) -> Dictionary:
	var state: Dictionary=editor.physics.display_states.get(actor.id,{})
	if state.is_empty(): return {"error":"No evaluated physics state at this playhead."}
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id)
	var combined:=KiwiModelMesh.new(); var materials: Array[Material]=[]
	if runtime is KiwiPowderRuntime:
		var maximum:=0
		for i in state.points.size():
			if deposits_only and int(state.powder_phase[i])!=KiwiPowderTransport.Phase.DEPOSITED: continue
			var identity: Dictionary=runtime.identities.get(int(state.powder_ids[i]),{})
			if identity.is_empty(): continue
			var mesh:=KiwiModelMesh.from_mesh(runtime.geometry[int(identity.variant)])
			maximum+=mesh.vertices.size()
			if maximum>MAX_VERTICES: return {"error":"Mesh conversion exceeds 150,000 vertices. Use fewer grains or lower geometry detail."}
			combined.append_mesh(mesh,Transform3D(identity.basis.scaled(Vector3.ONE*float(state.powder_radii[i])),state.points[i]))
		materials.append(runtime.batches[0].material_override)
	else:
		for node: MeshInstance3D in editor.physics.destruction.nodes.get(actor.id,[]):
			if not node.visible or node.mesh==null: continue
			var mesh:=KiwiModelMesh.from_mesh(node.mesh)
			if combined.vertices.size()+mesh.vertices.size()>MAX_VERTICES: return {"error":"Mesh conversion exceeds 150,000 vertices. Use simpler damage geometry."}
			combined.append_mesh(mesh,node.global_transform,materials.size())
			for surface in node.mesh.get_surface_count(): materials.append(node.get_active_material(surface))
	if combined.faces.is_empty(): return {"error":"There is no compatible visible geometry to save at this time."}
	return {"error":"","mesh":combined.render_mesh(materials),"editable":combined}
static func prompt(owner: Node,model: ActorTimeline,actor: ActorData,deposits_only: bool=false) -> void:
	for node in owner.get_tree().get_nodes_in_group("actor_timeline_editors"):
		if node.model!=model: continue
		var result:=capture(node,actor,deposits_only)
		if result.error.is_empty():
			var destination:=await ActorProjectResourceSaveDialog.pick(owner,"Save evaluated mesh",actor.display_name+" Mesh","tres",false,PackedStringArray(["tres"]),result.mesh)
			if destination.get("cancelled",true): return
			var path:=str(destination.get("path",""))
			if path.is_empty(): return
			if ResourceSaver.save(result.mesh,path)==OK:
				if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
				return
			result.error="The mesh could not be saved to the chosen location."
		var dialog:=AcceptDialog.new(); dialog.title="Mesh snapshot"; dialog.dialog_text=result.error; owner.add_child(dialog); dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(380,130)); return
