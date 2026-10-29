extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
static var pending: Dictionary={}
static func source(session: KiwiEnvironmentSession,id: String) -> Resource:
	var state: Dictionary=pending.get(session.get_instance_id(),{})
	if not state.is_empty() and state.id==id and session.document==state.document and session.revision==state.revision: return state.desired
	return Worlds.source(session.document.component(id))
static func cancel(session: KiwiModelSession) -> void:
	var state: Dictionary=pending.get(session.get_instance_id(),{})
	if state.is_empty(): return
	state.job.cancel(); pending.erase(session.get_instance_id()); session.pending_source_cancel=Callable()
	if session.document==state.document and session.revision==state.revision: session.dirty=state.was_dirty
	session.changed.emit()
static func request(session: KiwiEnvironmentSession,id: String,authored: Resource,label: String="Edit world") -> Dictionary:
	var root:=session.document.component(id)
	if root==null or not session._gesture.is_empty(): return {"errors":PackedStringArray(["Finish the current edit before generating this world."]),"warnings":PackedStringArray()}
	var previous: Dictionary=pending.get(session.get_instance_id(),{}); var was_dirty:=session.dirty
	if not previous.is_empty(): was_dirty=previous.was_dirty; cancel(session)
	elif session.pending_source_cancel.is_valid(): session.pending_source_cancel.call()
	var desired: Resource=authored.copy(); desired.world_id=id; Worlds.preserve_reservations(Worlds.source(root),desired); var field_result:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").capture(session,id,desired)
	preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").prepare(desired)
	var occupancy_error:=preload("res://Workspaces/EnvironmentWorkspace/world/world_occupancy.gd").capture(session,id,desired)
	if not occupancy_error.is_empty(): return {"errors":PackedStringArray([occupancy_error]),"warnings":PackedStringArray()}
	if not str(field_result.error).is_empty(): return {"errors":PackedStringArray([str(field_result.error)]),"warnings":PackedStringArray()}
	desired.terrain_field=field_result.field; desired.terrain_dependency_key=int(field_result.field.key) if field_result.field!=null else 0
	preload("res://Workspaces/EnvironmentWorkspace/world/road_follow.gd").controls(desired)
	var plan:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").tunnels_plan(session,id,desired)
	if not str(plan.get("error","")).is_empty(): return {"errors":PackedStringArray([str(plan.error)]),"warnings":PackedStringArray()}
	for road: Dictionary in desired.roads:
		if plan.get("portal_points",{}).has(road.id): road.portal_points=plan.portal_points[road.id]; road.portal_frames=plan.portal_frames[road.id]
	if not plan.has("settings"):
		var visual:=preload("res://Workspaces/EnvironmentWorkspace/world/world_visual_edit.gd").snapshot(session,id,desired)
		if not visual.is_empty(): return Worlds.update(session,id,desired,label,visual)
	var job:=preload("res://Workspaces/EnvironmentWorkspace/world/world_job.gd").new(); var state:={"job":job,"desired":desired,"document":session.document,"revision":session.revision,"id":id,"root":root,"was_dirty":was_dirty,"success":true}
	pending[session.get_instance_id()]=state; session.pending_source_cancel=cancel.bind(session); session.dirty=true; job.start(desired,plan,Worlds.development_snapshot(session,id,desired)); session.changed.emit()
	var tree:=Engine.get_main_loop() as SceneTree
	while not job.complete():
		if session.document!=state.document or session.revision!=state.revision: job.cancel()
		elif desired.terrain_field!=null and not desired.terrain_field.valid(session): job.cancel()
		elif plan.has("source"):
			var terrain:=session.environment().terrain(plan.id)
			if terrain!=plan.source or terrain==null or terrain.signature()!=plan.signature: job.cancel()
		await tree.process_frame
	var result:=job.collect()
	if pending.get(session.get_instance_id(),{}).get("job")!=job: return {"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	pending.erase(session.get_instance_id()); session.pending_source_cancel=Callable()
	if result.get("cancelled",false) or session.document!=state.document or session.revision!=state.revision or session.document.component(id)!=root:
		if session.document==state.document and session.revision==state.revision: session.dirty=was_dirty
		return {"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	if result.get("document")==null or not result.errors.is_empty(): state.success=false; session.dirty=was_dirty; return result
	result.signature=desired.signature(); var applied:=Worlds.update(session,id,desired,label,result)
	if not applied.errors.is_empty(): state.success=false; session.dirty=was_dirty
	return applied
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree; var success:=true
	while pending.has(session.get_instance_id()):
		var state: Dictionary=pending[session.get_instance_id()]; await tree.process_frame; success=success and state.success
	return success
