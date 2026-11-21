class_name KiwiAudioAutomationCanvas
extends Control
## Editable automation and deterministic modulation baked into ordinary document points.
var session:KiwiAudioEditSession
var owner_kind:="track"
var owner_id:=""
var effect_id:=""
var lane_id:=""
var _drag_before:KiwiAudioDocument
var _gesture:=KiwiAudioEditGesture.new()
var _drag_changed:=false
var parameter:="volume_db"
var duration:=10.0
var minimum:=-60.0
var maximum:=12.0
var grid:=0.125
var selected:=-1
var _drag:=false
static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_automation_canvas")
func _ready()->void:_native().ready(self)
func _session_changed()->void:_native().session_changed(self)
func owner_data()->Dictionary:return _native().owner_data(self)
func can_edit()->bool:return _native().can_edit(self)
func points()->Array:return _native().points(self)
func position_for(point:Dictionary)->Vector2:return _native().position_for(self,point)
func value_for(point:Vector2)->Dictionary:return _native().value_for(self,point)
func _draw()->void:_native().draw(self)
func _hit(position:Vector2)->int:return _native().hit(self,position)
func finish_edit(keep:bool=true)->void:_native().finish_edit(self,keep)
func _notification(what:int)->void:_native().canvas_notification(self,what)
func _gui_input(event:InputEvent)->void:_native().gui_input(self,event)
func set_curve(curve:String)->void:_native().set_curve(self,curve)
func clear_points()->void:_native().clear_points(self)
func modulate(settings:Dictionary)->void:_native().modulate(self,settings)
static func modulation_points(settings:Dictionary,seconds:float,tempo:float,low:float,high:float)->Array:
 return _native().modulation_points(settings,seconds,tempo,low,high)
func _exit_tree()->void:finish_edit()
