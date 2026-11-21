extends RefCounted
const Number=preload("res://Workspaces/SceneWorkspace/scripts/Timeline/DragNumber.cs")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")
const MODES=["spot","heal","clone","pattern_heal","pattern_fill","procedural","patch"]
const NAMES=["Spot heal","Healing brush","Clone stamp","Pattern heal","Pattern fill","Procedural texture","Patch repair"]
const HINTS={
	"spot":"Paint over defects · no sample needed",
	"heal":"1 Sample source → 2 Paint to heal",
	"clone":"1 Sample source → 2 Paint a copy",
	"pattern_heal":"Sample clean texture → Paint to extend",
	"pattern_fill":"Load / sample → Paint or Preview",
	"procedural":"Generate → Paint / New layer",
	"patch":"Select pixels → Preview → Apply",
}

static func build(studio:KiwiImageWorkspace)->void:_native().repair_build(studio)

static func number(parent:Node,caption:String,value:float,minimum:float,maximum:float,step:float,changed:Callable)->void:_native().repair_number(parent,caption,value,minimum,maximum,step,changed)

static func setting(parent:Node,caption:String,value:float,changed:Callable)->void:_native().repair_setting(parent,caption,value,changed)

static func option(parent:Node,captions:Array,ids:Array,current:String,changed:Callable)->void:_native().repair_option(parent,captions,ids,current,changed)

static func options(studio:KiwiImageWorkspace)->void:_native().repair_options(studio)

static func load_pattern(studio:KiwiImageWorkspace)->void:
 var property:ActorProperty=_native().repair_pattern_property()
 var chosen:=await ActorProjectFilePicker.pick(studio,property,"Load pattern image or preset")
 _native().load_repair_pattern(studio,chosen)

static func save_pattern(studio:KiwiImageWorkspace)->void:
 var request:Dictionary=_native().prepare_repair_pattern_save(studio)
 if request.is_empty():return
 var destination:=await ActorProjectResourceSaveDialog.pick(studio,"Save pattern preset","Pattern","tres",false)
 _native().complete_repair_pattern_save(studio,request,destination)

static func _native()->Object:return Engine.get_singleton("KiwiNativeServices").service("image_workspace_ui")
static func _connect(control:Control,signal_name:String,callback:Callable)->void:control.connect(signal_name,callback)
static func _choice(callback:Callable,value:String)->void:callback.call(value)
static func _refresh_filesystem()->void:
 if LocalProjectFilesystem.node!=null:LocalProjectFilesystem.update_root_folder()
