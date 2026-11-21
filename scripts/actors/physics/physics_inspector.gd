class_name KiwiPhysicsInspector
extends RefCounted
var inspector: Control
var actor: ActorData
var model: RefCounted
var panel: VBoxContainer
var settings: Dictionary
static func build(host: Control, data: ActorData, parent: VBoxContainer) -> void:
	_native_inspector().build(host,data,parent)

func _change(key: String, value: Variant, rebuild: bool=false) -> void:
	_native_inspector().change(self,key,value,rebuild)

func _heading(text: String) -> void:
	_native_inspector().heading(self,text)

func _property(key: String, title: String, parent: VBoxContainer, keyed: bool=true) -> HBoxContainer:
	return _native_inspector().property(self,key,title,parent,keyed)

func _check(key: String, title: String, parent: VBoxContainer, rebuild: bool=false) -> void:
	_native_inspector().check(self,key,title,parent,rebuild)

func _choice(key: String, title: String, choices: Array, parent: VBoxContainer) -> void:
	_native_inspector().choice(self,key,title,choices,parent)

func _number(key: String, title: String, parent: VBoxContainer, low: float=0.0, high: float=1000.0, step: float=.01, keyed: bool=true) -> void:
	_native_inspector().number(self,key,title,parent,low,high,step,keyed)

func _bind_number(input: DragNumber, key: String, axis: int=-1) -> void:
	_native_inspector().bind_number(self,input,key,axis)

func _vector(key: String, title: String, parent: VBoxContainer) -> void:
	_native_inspector().vector(self,key,title,parent)

func _target(key: String, bone_key: String, title: String, parent: VBoxContainer) -> void:
	_native_inspector().target(self,key,bone_key,title,parent)

func _fold(title: String) -> VBoxContainer:
	return _native_inspector().fold(self,title)

func _build() -> void:
	_native_inspector().build_layout(self)

func _bones() -> void:
	_native_inspector().bones(self)

func _structured_number(input: DragNumber, field: String, amend: Callable) -> void:
	_native_inspector().structured_number(self,input,field,amend)

func _events() -> void:
	_native_inspector().events(self)

func _editor() -> Control:
	return _native_inspector().editor(self)

func _pins() -> void:
	_native_inspector().pins(self)

func _actions() -> void:
	_native_inspector().actions(self)

func _action(action: String, button: Button, status: Label) -> void:
	_native_inspector().action(self,action,button,status)

static func _native_inspector() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","physics_inspector")

func _amend(callback: Callable,value: float) -> Variant:
	return callback.call(value)

func _await_bake(editor: Control,start: float,end: float,button: Button,status: Label,popup: ConfirmationDialog) -> void:
	var error: String=await editor.physics.bake(editor,actor,start,end)
	_native_inspector().bake_finished(button,status,popup,error)
