extends PanelContainer
## Embedded, non-modal floating browser: drags remain in the same viewport.
var service: Node
var store: KiwiClipboardStore
var search:=LineEdit.new()
var tree:=Tree.new()
var files:=ItemList.new()
var preview:=TextureRect.new()
var details:=Label.new()
var status:=Label.new()
var default_button:=Button.new()
var folder:="default"
var trash:=false
var grid:=false
var copied:=PackedStringArray()
var cut:=false
var _dragging:=false
var _resizing:=false
var _origin:=Vector2.ZERO
var _before:=Vector2.ZERO
var _generation:=0
var _listing:=0
var _thumbnails: Dictionary={}
var _thumbnail_jobs: Array[Dictionary]=[]
var _thumbnail_busy:=false
func configure(host: Node) -> void:
	_native_window().configure(self,host)

func _restore_bounds(state: Dictionary) -> void:
	_native_window().restore_bounds(self,state)

func _build_theme() -> void:
	_native_window().build_theme(self)

func _selection() -> PackedStringArray:
	return _native_window().selection(self)

func button(parent: Node,text: String,action: Callable,tip: String="") -> Button:
	var input: Button=_native_window().make_button(parent,text,tip)
	input.pressed.connect(action)
	return input

func _refresh() -> void:
	_native_window().refresh(self)

func _folders(parent: TreeItem,id: String,visited: Dictionary) -> void:
	_native_window().folders(self,parent,id,visited)

func _refresh_files() -> void:
	var state: Dictionary=_native_window().begin_listing(self)
	while _native_window().continue_listing(self,state):
		await get_tree().process_frame

func _queue_thumbnails() -> void:
	_native_window().queue_thumbnails(self)

func _process(_dt: float) -> void:
	_native_window().process(self)

func _thumbnail(job: Dictionary) -> void:
	var path: String=_native_window().thumbnail_path(self,job)
	var texture: Texture2D
	if not path.is_empty(): texture=await FileOperations.get_file_thumbnail(path)
	_native_window().finish_thumbnail(self,job,texture)

func selected() -> PackedStringArray:
	return _native_window().selected(self)

func _preview() -> void:
	var plan: Dictionary=_native_window().begin_preview(self)
	if plan.is_empty(): return
	var texture: Texture2D=await FileOperations.get_file_thumbnail(plan.path)
	_native_window().finish_preview(self,plan,texture)

func _use() -> void:
	_native_window().use(self)

func _rename() -> void:
	_native_window().rename(self)

func _delete() -> void:
	_native_window().delete(self)

func _prompt(title: String,value: String,confirmed: Callable) -> void:
	_native_window().prompt(self,title,value,confirmed)

func _move_menu() -> void:
	_native_window().move_menu(self)

func _file_drag(_at: Vector2) -> Variant:
	return _native_window().file_drag(self)

func _folder_drag(_at: Vector2) -> Variant:
	return _native_window().folder_drag(self)

func _can_drop(_at: Vector2,data: Variant) -> bool:
	return _native_window().can_drop(data)

func _drop(_at: Vector2,data: Variant) -> void:
	_native_window().drop(self,data)

func _folder_can_drop(at: Vector2,data: Variant) -> bool:
	return _native_window().folder_can_drop(self,at,data)

func _folder_drop(at: Vector2,data: Variant) -> void:
	_native_window().folder_drop(self,at,data)

func _receive(data: Dictionary,destination: String) -> void:
	_native_window().receive(self,data,destination)

func _result(ok: bool) -> void:
	_native_window().result(self,ok)

func _keys(event: InputEvent) -> void:
	_native_window().keys(self,event)

func _title_input(event: InputEvent) -> void:
	_native_window().title_input(self,event)

func _resize_input(event: InputEvent) -> void:
	_native_window().resize_input(self,event)

func _clamp_window() -> void:
	_native_window().clamp_window(self)

func _remember() -> void:
	_native_window().remember(self)

func _close() -> void:
	_native_window().close(self)


func _invoke_window_callback(callback: Callable,text: String) -> void:
	if callback.is_valid(): callback.call(text)

static func _native_window() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("clipboard_window")
