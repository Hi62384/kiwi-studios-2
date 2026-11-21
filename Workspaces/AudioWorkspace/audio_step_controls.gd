class_name KiwiAudioStepControls
extends VBoxContainer
## Native controls over canonical note data. Render-only groove never rewrites notes.
signal changed
const DIVISIONS := [1.0, 0.5, 1.0 / 3.0, 0.25, 1.0 / 6.0, 0.125, 1.0 / 12.0]
const DIVISION_LABELS := ["1/4", "1/8", "1/8 triplet", "1/16", "1/16 triplet", "1/32", "1/32 triplet"]
var session: KiwiAudioEditSession
var canvas: KiwiAudioPatternCanvas
var step_count: SpinBox
var division: OptionButton
var swing: SpinBox
var accent_variation: SpinBox
var seed_input: SpinBox
var lane_controls: Dictionary = {}
var _syncing := false

static func default_settings() -> Dictionary:
 return _native().call("default_settings")

func setup(value:KiwiAudioEditSession, view:KiwiAudioPatternCanvas) -> void:
 _native().call("setup", self, value, view)

func _spin(parent:Node,label:String,low:float,high:float,step:float,callback:Callable) -> SpinBox:
 var text:=Label.new();text.text=label;parent.add_child(text)
 var spin:=SpinBox.new();spin.name=label.replace(" ","");spin.min_value=low;spin.max_value=high;spin.step=step;spin.custom_minimum_size.x=70;parent.add_child(spin);spin.value_changed.connect(callback)
 return spin

func sync_selection() -> void:
 _native().call("sync_selection", self)

func _set_setting(key:String,value:Variant,resize_pattern:bool=false) -> void:
 _native().call("set_setting", self, key, value, resize_pattern)

func _set_lane(pitch:int,key:String,value:bool) -> void:
 _native().call("set_lane", self, pitch, key, value)

static func render_copy(notes:Array,settings:Dictionary,instrument:Dictionary={}) -> Array:
 return _native().call("render_copy", notes, settings, instrument)

static func _native() -> RefCounted:
 return Engine.get_singleton("KiwiNativeServices").call("service", "audio_step_controls")
