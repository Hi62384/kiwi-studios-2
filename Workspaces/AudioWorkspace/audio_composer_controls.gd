class_name KiwiAudioComposerControls
extends VBoxContainer
## Extra composer controls and a source-window-safe transaction boundary.
const ROLES := ["melody","chords","bass","drums","pad"]
var role_controls:Dictionary={}
var section_rows:VBoxContainer
var layout_toggle:CheckBox
var structure_input:LineEdit
var _settings:Dictionary={}
var _layout:Array=[]

func setup(settings:Dictionary,sections:Array=[]) -> void:
 _native().call("setup", self, settings, sections)

func add_section() -> void:
 _native().call("add_section", self)

func _rebuild_rows() -> void:
 _native().call("rebuild_rows", self)

func _section_spin(parent:Node,label:String,value:float,low:float,high:float,callback:Callable) -> void:
 var text:=Label.new();text.text=label;parent.add_child(text)
 var spin:=SpinBox.new();spin.min_value=low;spin.max_value=high;spin.step=0.25;spin.value=value;parent.add_child(spin);spin.value_changed.connect(callback)

func settings_copy() -> Dictionary:
 return _native().call("settings_copy", self)

static func snapshot_arrangement(document:KiwiAudioDocument) -> Dictionary:
 return _native().call("snapshot_arrangement", document)

static func render_arrangement(config:Dictionary,previous:Dictionary,role:String="",section_id:String="",job:RefCounted=null,rate:int=44100) -> Dictionary:
 return _native().call("render_arrangement", config, previous, role, section_id, job, rate)

static func apply_rendered(session:KiwiAudioEditSession,data:Dictionary) -> String:
 return _native().call("apply_rendered", session, data)

static func _native() -> RefCounted:
 return Engine.get_singleton("KiwiNativeServices").call("service", "audio_composer_controls")
