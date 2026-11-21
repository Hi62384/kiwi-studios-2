class_name KiwiModelSession
extends RefCounted
signal changed
var document := KiwiModelDocument.new()
var selected: Array[String] = []
var mode := "Object"
var elements := PackedInt32Array()
var dirty := false
var revision := 0
var history_revision:=0 # explicit history navigation, separate from derived refreshes
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _gesture: Dictionary = {}
var last_command := ""
var pending_source_cancel:=Callable()
var rig_selection: Dictionary={}

# Native history preserves virtual snapshot/signature/commit behavior in subclasses.
func _history_native() -> RefCounted: return Engine.get_singleton("KiwiNativeServices").call("service","model_session_history")
func _pending_source_valid() -> bool: return pending_source_cancel.is_valid()
func _invoke_pending_source_cancel() -> void:
	if pending_source_cancel.is_valid(): pending_source_cancel.call()
func _invoke_custom_history(entry: Dictionary,direction: String) -> void: entry[direction].call()
func _history_entry_cost(entry: Dictionary) -> int:
	# Packed-array size access stays with the legacy storage adapter, avoiding copies.
	var cost:=0
	for item: KiwiModelComponent in entry.before.document.components:
		if item.mesh!=null: cost+=item.mesh.vertices.size()
	return cost
func primary() -> KiwiModelComponent: return _history_native().primary(self)
func snapshot() -> Dictionary: return _history_native().snapshot(self)
func restore(state: Dictionary) -> void: _history_native().restore(self,state)
func begin() -> void: _history_native().begin(self)
func cancel() -> void: _history_native().cancel(self)
func commit(label: String) -> void: _history_native().commit(self,label)
func _signature(data: KiwiModelDocument) -> int: return _history_native()._signature(data)
func action(label: String,operation: Callable) -> void: begin(); operation.call(); commit(label)
func undo() -> void: _history_native().undo(self)
func redo() -> void: _history_native().redo(self)
func custom_action(label: String,backward: Callable,forward: Callable,cost: int=0) -> void:
	# Keep existing GDScript callables in their owning language until callers migrate.
	_undo.append({"label":label,"custom":true,"undo":backward,"redo":forward,"cost":cost}); _redo.clear()
	_history_native().finish_custom_action(self,label)
func _edits_native() -> RefCounted: return Engine.get_singleton("KiwiNativeServices").call("service","model_session_edits")
func select(id: String,additive: bool=false) -> void:
	_edits_native().select(self,id,additive)

func add(kind: String,parameters: Dictionary={},position: Vector3=Vector3.ZERO) -> KiwiModelComponent:
	return _edits_native().add(self,kind,parameters,position)

func selected_vertices() -> PackedInt32Array:
	return _edits_native().selected_vertices(self)

func edit_mesh(kind: String,amount: float=.2,preview: bool=false) -> String:
	return _edits_native().edit_mesh(self,kind,amount,preview)

func duplicate_selected(preview: bool=false) -> void:
	_edits_native().duplicate_selected(self,preview)

func group_selected() -> void:
	_edits_native().group_selected(self)

func parent_selected(unparent: bool=false) -> void:
	_edits_native().parent_selected(self,unparent)

func can_reparent(ids: Array[String],parent_id: String) -> bool:
	return _edits_native().can_reparent(self,ids,parent_id)

func _reparent_roots(ids: Array[String]) -> Array[String]:
	return _edits_native()._reparent_roots(self,ids)

func reparent_components(ids: Array[String],parent_id: String) -> void:
	_edits_native().reparent_components(self,ids,parent_id)

func delete_selected() -> String:
	return _edits_native().delete_selected(self)

func join_selected() -> void:
	_edits_native().join_selected(self)

