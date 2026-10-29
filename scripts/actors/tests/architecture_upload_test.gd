extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); Buildings.add(session,Vector3.ZERO,6); var count:=0
	for item in session.document.components:
		if item.mesh!=null: count+=1
	var renderer:=KiwiEnvironmentRuntime.new(); renderer.progressive=true; renderer.upload_budget_usec=1; root.add_child(renderer); renderer.set_process(false); renderer.configure(session.environment())
	check(count>64 and renderer.pending_assets.size()==count,"Large building previews queue native component uploads before rendering all meshes")
	var bridge: Node=load("res://Workspaces/EnvironmentWorkspace/environment_actor.gd").new(); bridge.content=renderer
	check(not bridge.physics_geometry_ready(),"Scene physics waits while generated structural collision is still uploading")
	renderer._process(0.); check(renderer.pending_assets.size()==count-1,"A tiny upload budget installs one real building mesh per scheduling pass")
	var passes:=0
	while not renderer.pending_assets.is_empty() and passes<count+5: renderer._process(0.); passes+=1
	var complete:=true
	for item in session.document.components:
		if item.mesh!=null: complete=complete and renderer.nodes[item.id].get_child_count()>0
	check(complete and renderer.pending_assets.is_empty(),"Progressive environment preview eventually installs every generated mesh and collider")
	check(bridge.physics_geometry_ready(),"Scene physics becomes ready after the complete structural upload"); bridge.free()
	var model_canvas:=KiwiModelViewport.new(); model_canvas.session=session; model_canvas.upload_budget_usec=1; root.add_child(model_canvas); model_canvas.set_process(false); model_canvas.sync()
	check(model_canvas._pending_sync and model_canvas.signatures.size()==1,"Model preview uses the same bounded per-frame upload policy")
	while model_canvas._pending_sync: model_canvas.sync()
	check(model_canvas.signatures.size()==count,"Model upload scheduling preserves all authored components")
	var state:=session.document.hierarchy_state(); var same:=true
	for item in session.document.components: same=same and (state.poses[item.id] as Transform3D).is_equal_approx(session.document.world_transform(item)) and bool(state.visible[item.id])==session.document.visible_component(item)
	check(same,"Indexed hierarchy traversal preserves original transform and visibility semantics")
	var other:=KiwiEnvironmentDocument.new(); var group:=other.add_group("New source"); renderer.configure(session.environment()); renderer.pending_assets["stale"]={"node":renderer.nodes.values()[0],"item":session.document.components[0]}; renderer.configure(other); renderer._process(0.)
	check(renderer.pending_assets.is_empty() and renderer.nodes.size()==1 and renderer.nodes.has(group.id),"Switching environments discards stale native component uploads")
	model_canvas.queue_free(); renderer.queue_free(); await process_frame; print("ARCHITECTURE UPLOAD: %d checks, %d failures"%[checks,failures]); quit(failures)
