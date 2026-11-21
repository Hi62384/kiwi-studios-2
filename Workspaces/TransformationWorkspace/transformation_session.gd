class_name KiwiTransformationSession
extends RefCounted
signal changed
var document := (load("res://Workspaces/TransformationWorkspace/KiwiTransformationImage2D.cs").call("blank") as KiwiTransformationImage2D)
var selected: Array[String]=[]
var edit_states: Dictionary={}
var selected_keys: Array[String]=[]
var playhead := 0.
var dirty := true
var revision := 0
var undo_stack: Array[Dictionary]=[]
var redo_stack: Array[Dictionary]=[]
var pending: Dictionary={}
var clipboard: Array[KiwiTransformationComponent]=[]
var state_clipboard: KiwiTransformationState
var message := ""
var pixel_mask: Image
var pixel_reference: Dictionary={}
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_session")
func restore_view_state(saved: Dictionary) -> void: _native().call("restore_view_state", self, saved)
func primary() -> KiwiTransformationComponent: return _native().call("primary", self)
func active_state(item: KiwiTransformationComponent=null) -> KiwiTransformationState: return _native().call("active_state", self, item)
func snapshot() -> Dictionary: return _native().call("snapshot", self)
func restore(state: Dictionary) -> void: _native().call("restore", self, state)
func begin() -> void: _native().call("begin", self)
func cancel() -> void: _native().call("cancel", self)
func commit(label: String) -> void: _native().call("commit", self, label)
func history_bytes() -> int: return _native().call("history_bytes", self)
func action(label: String, operation: Callable) -> void: begin(); operation.call(); commit(label)
func undo() -> void: _native().call("undo", self)
func redo() -> void: _native().call("redo", self)
func select(id: String, additive: bool=false) -> void: _native().call("select", self, id, additive)
func add_component() -> KiwiTransformationComponent: return _native().call("add_component", self)
func delete_components() -> void: _native().call("delete_components", self)
func copy_components() -> void: _native().call("copy_components", self)
func paste_components() -> void: _native().call("paste_components", self)
func duplicate_components() -> void: _native().call("duplicate_components", self)
func reorder(id: String, target: int) -> void: _native().call("reorder", self, id, target)
func add_state(blank: bool=false) -> KiwiTransformationState: return _native().call("add_state", self, blank)
func delete_state() -> void: _native().call("delete_state", self)
func key_at(item: KiwiTransformationComponent, at: float) -> KiwiTransformationKey: return _native().call("key_at", item, at)
func insert_key() -> void: _native().call("insert_key", self)
func delete_keys() -> void: _native().call("delete_keys", self)
func duplicate_keys() -> void: _native().call("duplicate_keys", self)
func set_duration(value: float) -> void: _native().call("set_duration", self, value)
func sampled(item: KiwiTransformationComponent, time: float) -> Dictionary: return _native().call("sampled", item, time)
