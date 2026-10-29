extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Fields=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd")
const Occupancy=preload("res://Workspaces/EnvironmentWorkspace/world/world_occupancy.gd")
const DataHash=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd")
static func state(workspace: Control) -> Dictionary:
	var value: Dictionary=workspace.get_meta("world_dependencies",{})
	if value.get("session")!=workspace.session:
		value={"session":workspace.session,"time":0,"history":workspace.session.history_revision,"seen":{},"failed":{},"pause":{}}; workspace.set_meta("world_dependencies",value)
	return value
static func suspend(workspace: Control) -> void:
	var value:=state(workspace); value.pause={"depth":workspace.session._undo.size(),"entry":workspace.session._undo.back() if not workspace.session._undo.is_empty() else {}}
static func poll(workspace: Control) -> void:
	var value:=state(workspace); var session: KiwiEnvironmentSession=workspace.session
	if int(value.history)!=session.history_revision: value.history=session.history_revision; suspend(workspace)
	if not (value.pause as Dictionary).is_empty():
		if int(value.pause.depth)==session._undo.size() and (session._undo.is_empty() or session._undo.back()==value.pause.entry): return
		value.pause={}
	if Time.get_ticks_msec()-int(value.time)<250 or session.pending_source_cancel.is_valid() or not session._gesture.is_empty(): return
	value.time=Time.get_ticks_msec()
	for item in session.document.components:
		var current:=Worlds.source(item)
		if current==null or not current.auto_update_dependencies or not item.parameters.has("world_graph") or str(current.terrain_id).is_empty(): continue
		var field: RefCounted=current.terrain_field; var terrain_changed: bool=field==null or not field.valid(session); var objects_changed: bool=int(value.seen.get(item.id,-1))!=session.revision
		if not terrain_changed and not objects_changed: continue
		var desired: Resource=current.copy(); var captured:=Fields.capture(session,item.id,desired)
		if not str(captured.error).is_empty(): continue # terrain worker reports its own pending/error state
		var key:=hash([int(captured.field.key),session.revision,current.signature()])
		if int(value.failed.get(item.id,0))==key: continue
		var error:=Occupancy.capture(session,item.id,desired)
		if not error.is_empty(): value.failed[item.id]=key; workspace.status.text=error; continue
		value.seen[item.id]=session.revision
		if int(captured.field.key)==current.terrain_dependency_key and DataHash.value(desired.occupied)==DataHash.value(current.occupied): current.terrain_field=captured.field; continue
		_update(workspace,session,item.id,desired,key); return
static func _update(workspace: Control,session: KiwiEnvironmentSession,id: String,desired: Resource,key: int) -> void:
	var revision:=session.revision; var previous: Dictionary=session._undo.back() if not session._undo.is_empty() else {}; var result:=await Edit.request(session,id,desired,"Refresh dependent world")
	if not is_instance_valid(workspace) or workspace.session!=session: return
	if result.get("cancelled",false): return
	if not result.errors.is_empty(): state(workspace).failed[id]=key; workspace.status.text=result.errors[0]; return
	if session.revision!=revision+1 or previous.is_empty() or session._undo.is_empty(): return
	var generated: Dictionary=session._undo.back()
	if str(generated.get("label",""))!="Refresh dependent world": return
	# Derived geometry belongs to the edit that caused it. Sparse sculpt actions
	# retain their callbacks; the native world snapshots restore their dependents.
	if previous.get("custom",false):
		var before: Dictionary=generated.before; var after: Dictionary=generated.after; var backward: Callable=previous.undo; var forward: Callable=previous.redo
		previous.undo=func(): session.restore(before); backward.call()
		previous.redo=func(): forward.call(); session.restore(after)
		previous.cost=int(previous.get("cost",0))+_cost(before)+_cost(after)
	else: previous.after=generated.after
	session._undo.pop_back()
	if session._undo.is_empty() or session._undo.back()!=previous: session._undo.append(previous)
static func _cost(snapshot: Dictionary) -> int:
	var count:=0
	for item in snapshot.document.components:
		if item.mesh!=null: count+=item.mesh.vertices.size()
	return count
