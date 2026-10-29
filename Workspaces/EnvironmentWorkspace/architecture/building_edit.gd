extends RefCounted
## Jobs belong to the document session, so switching tabs never redirects a result.
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
static var _pending: Dictionary={}
static func source(session: KiwiModelSession,id: String) -> Resource:
	var state: Dictionary=_pending.get(session.get_instance_id(),{})
	if not state.is_empty() and state.id==id and state.document==session.document and state.revision==session.revision: return state.desired
	return Buildings.source(session.document.component(id))
static func cancel(session: KiwiModelSession) -> void:
	var state: Dictionary=_pending.get(session.get_instance_id(),{})
	if state.is_empty(): return
	state.job.cancel(); _pending.erase(session.get_instance_id()); session.pending_source_cancel=Callable()
	if session.document==state.document and session.revision==state.revision: session.dirty=state.was_dirty
	session.changed.emit()
static func request(session: KiwiModelSession,id: String,authored: Resource,label: String) -> Dictionary:
	var root:=session.document.component(id)
	if root==null: return {"errors":PackedStringArray(["The building no longer exists."]),"warnings":PackedStringArray()}
	if not session._gesture.is_empty(): return {"errors":PackedStringArray(["Finish the current transform or stroke before editing building settings."]),"warnings":PackedStringArray()}
	var previous: Dictionary=_pending.get(session.get_instance_id(),{}); var was_dirty:=session.dirty
	if not previous.is_empty():
		previous.job.cancel()
		if previous.revision==session.revision: was_dirty=previous.was_dirty
	elif session.pending_source_cancel.is_valid(): session.pending_source_cancel.call()
	var desired: Resource=Source.copy(authored); desired.source_id=id; var job:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_job.gd").new()
	var state:={"job":job,"desired":desired,"id":id,"root":root,"document":session.document,"revision":session.revision,"was_dirty":was_dirty,"success":true}
	_pending[session.get_instance_id()]=state; session.pending_source_cancel=cancel.bind(session); session.dirty=true; job.start(desired); session.changed.emit()
	var tree:=Engine.get_main_loop() as SceneTree
	while not job.complete():
		if session.document!=state.document or session.revision!=state.revision or session.document.component(id)!=root: job.cancel()
		await tree.process_frame
	var result: Dictionary=job.collect()
	if _pending.get(session.get_instance_id(),{}).get("job")!=job: return {"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	_pending.erase(session.get_instance_id()); session.pending_source_cancel=Callable()
	if result.get("cancelled",false) or session.document!=state.document or session.revision!=state.revision or session.document.component(id)!=root:
		if session.document==state.document and session.revision==state.revision: session.dirty=was_dirty
		return {"errors":PackedStringArray(),"warnings":PackedStringArray(),"cancelled":true}
	if result.get("document")==null or not result.errors.is_empty():
		state.success=false; session.dirty=was_dirty; return result
	var environment:=session.document as KiwiEnvironmentDocument
	if environment!=null and environment.component_kind(id)=="building":
		var stamp:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
		if root.binding!=null or root.growth!=null or not root.modifiers.is_empty() or stamp.mesh_key(root.mesh)!=int(root.parameters.get("_architecture_mesh",stamp.mesh_key(root.mesh))):
			state.success=false; session.dirty=was_dirty; return {"errors":PackedStringArray(["This building has a custom mesh, rig or groom. Preserve or reset that override before expanding generated detail."]),"warnings":PackedStringArray()}
		result.source_key=Buildings._source_key(desired); session.begin()
		if root.parameters.has("world_owner"): preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd").detach_building(session,id)
		root.parameters._architecture_generated_mesh=stamp.mesh_key(root.mesh)
		root.parameters.erase("world_lazy_building"); var expanded:=Buildings.update(session,id,desired,label,true,true,result)
		if not expanded.errors.is_empty(): session.cancel(); state.success=false; return expanded
		session.commit(label); return expanded
	result.source_key=Buildings._source_key(desired); var applied:=Buildings.update(session,id,desired,label,false,false,result)
	if not applied.errors.is_empty(): state.success=false; session.dirty=was_dirty
	return applied
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree; var success:=true
	while _pending.has(session.get_instance_id()):
		var state: Dictionary=_pending[session.get_instance_id()]
		await tree.process_frame; success=success and bool(state.success)
	return success
