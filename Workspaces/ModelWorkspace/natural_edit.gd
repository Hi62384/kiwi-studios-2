extends RefCounted
## One pending source gesture per workspace. Superseded workers are cancelled,
## collected, and never allowed to install stale geometry into a different tab.
static func request(workspace: Control,id: String,key: String,value: Variant,finished: bool) -> void:
	var source: KiwiModelComponent=workspace.session.document.component(id)
	if source==null: return
	var previous: Dictionary=workspace.get_meta("natural_edit",{})
	var parameters:=source.parameters.duplicate(true)
	if not previous.is_empty():
		previous.job.cancel()
		if previous.id==id: parameters=previous.parameters.duplicate(true)
	parameters[key]=value; workspace.session.begin()
	var job:=preload("res://Workspaces/ModelWorkspace/natural_job.gd").new()
	var state:={"job":job,"id":id,"parameters":parameters,"finished":finished,"applied":false,"session":workspace.session,"document":workspace.session.document,"source":source,"label":"Change natural "+key,"was_dirty":previous.get("was_dirty",workspace.session.dirty),"revision":previous.get("revision",workspace.session.revision)}
	workspace.session.dirty=true; workspace.document_changed.emit()
	workspace.set_meta("natural_edit",state); job.start(source.generator,parameters); _collect(workspace,state)
static func finish(workspace: Control) -> void:
	var state: Dictionary=workspace.get_meta("natural_edit",{})
	if state.is_empty(): workspace.session.commit("Change natural source"); return
	state.finished=true
	if state.applied: state.session.commit(state.label); workspace.set_meta("natural_edit",{})
static func cancel(workspace: Control) -> void:
	var state: Dictionary=workspace.get_meta("natural_edit",{})
	if not state.is_empty(): state.job.cancel(); _restore_dirty(state)
	workspace.set_meta("natural_edit",{}); workspace.session.cancel()
static func flush(workspace: Control) -> bool:
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").flush(workspace.session): return false
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(workspace.session): return false
	if not await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").flush(workspace.session): return false
	if workspace.get_meta("natural_edit",{}).is_empty(): return true
	var session: KiwiModelSession=workspace.session; finish(workspace)
	while not workspace.get_meta("natural_edit",{}).is_empty():
		await workspace.get_tree().process_frame
		if not workspace.is_inside_tree() or workspace.session!=session: return false
	return true
static func _restore_dirty(state: Dictionary) -> void:
	if state.session.revision==state.revision: state.session.dirty=state.was_dirty
static func _collect(workspace: Control,state: Dictionary) -> void:
	var tree:=workspace.get_tree(); var stale:=false
	while not state.job.complete():
		if not is_instance_valid(workspace) or not workspace.is_inside_tree(): state.job.cancel(); stale=true
		elif workspace.get_meta("natural_edit",{}).get("job")!=state.job: state.job.cancel(); stale=true
		elif workspace.session!=state.session or state.session.document!=state.document or state.document.component(state.id)!=state.source: state.job.cancel(); stale=true
		await tree.process_frame
	var result: Dictionary=state.job.collect()
	if not is_instance_valid(workspace) or not workspace.is_inside_tree():
		_restore_dirty(state)
		if state.session.document==state.document: state.session.cancel()
		return
	if workspace.get_meta("natural_edit",{}).get("job")!=state.job: return
	if stale or workspace.session!=state.session or state.session.document!=state.document or state.document.component(state.id)!=state.source:
		workspace.set_meta("natural_edit",{})
		_restore_dirty(state)
		if state.session.document==state.document: state.session.cancel()
		else: state.session.changed.emit()
		return
	if result.get("mesh")==null:
		workspace.status.text=str(result.get("error","Could not generate geometry.")); workspace.set_meta("natural_edit",{}); _restore_dirty(state); state.session.cancel(); return
	state.source.parameters=state.parameters; state.source.mesh=result.mesh; state.applied=true; workspace.canvas.request_sync()
	if state.finished: state.session.commit(state.label); workspace.set_meta("natural_edit",{})
