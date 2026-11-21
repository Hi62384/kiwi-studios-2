extends VBoxContainer
var host: ActorInspector
var actor: ActorData
var workflow:=false
var status: Label
func setup(inspector: ActorInspector,data: ActorData,actions: bool=false) -> void:
	_native_workflow().setup(self,inspector,data,actions)

func button(parent: Node,title: String,action: Callable) -> Button:
	return _native_workflow().button(self,parent,title,action)

func editor() -> ActorTimelineEditor:
	return _native_workflow().editor(self)

func capture() -> void:
	_native_workflow().capture(self)

func apply_setup() -> void:
	_native_workflow().apply_setup(self)

func capture_baked() -> void:
	_native_workflow().capture_baked(self)

func instantiate_baked() -> void:
	_native_workflow().instantiate_baked(self)

func run(title: String) -> void:
	_native_workflow().run(self,title)

func bake_dialog(view: ActorTimelineEditor) -> void:
	_native_workflow().bake_dialog(self,view)

func open_fragments() -> void:
	_native_workflow().open_fragments(self)

func _connect_button(button: Button,callback: Callable) -> void:
	button.pressed.connect(callback)
static func _native_workflow() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_workflow")

func _await_group_bake(view: ActorTimelineEditor,start: float,end: float,rate: int,progress: Callable,options: Dictionary,job: Dictionary) -> void:
	var result: String=await view.physics.bake_group(view,start,end,rate,progress,options)
	_native_workflow().group_bake_finished(job,result)
