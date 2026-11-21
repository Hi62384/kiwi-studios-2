class_name KiwiAudioConductorControls
extends VBoxContainer
## A bounded draft editor: Apply is one undo action; Cancel leaves no edits.
signal applied
signal seek_requested(seconds: float)
var session: KiwiAudioEditSession
var _owner: KiwiAudioDocument
var _is_current := Callable()
var _revision := -1
var _tempo := 120.0
var _signature := Vector2i(4, 4)
var _tempos: Array = []
var _meters: Array = []
var _tempos_list := ItemList.new()
var _meters_list := ItemList.new()
var _tempo_beat: SpinBox
var _tempo_value: SpinBox
var _meter_beat: SpinBox
var _meter_numerator: SpinBox
var _meter_denominator: OptionButton
var _status := Label.new()

func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_conductor_controls")
func setup(value:KiwiAudioEditSession,at:float=0.0,is_current:Callable=Callable())->void:
 _is_current=is_current
 _native().setup(self,value,at)
func _owner_current()->bool:return not _is_current.is_valid() or bool(_is_current.call())
func _put_tempo()->void:_native().put_tempo(self)
func _put_meter()->void:_native().put_meter(self)
func _move_tempo()->void:_native().move_tempo(self)
func _move_meter()->void:_native().move_meter(self)
func _move(points:Array,list:ItemList,point:Dictionary)->void:_native().move(self,points,list,point)
func _put(points:Array,point:Dictionary)->void:_native().put(self,points,point)
func _remove_tempo()->void:_native().remove_tempo(self)
func _remove_meter()->void:_native().remove_meter(self)
func _refresh_lists()->void:_native().refresh_lists(self)
func _seek(beat:float)->void:_native().seek(self,beat)
func _apply()->void:_native().apply(self)
func _label(parent:Node,text:String)->void:_native().label(parent,text)
func _button(parent:Node,text:String,callback:Callable)->void:
 var button:=Button.new();button.text=text;parent.add_child(button);button.pressed.connect(callback)
func _spin(parent:Node,text:String,value:float,low:float,high:float,step:float)->SpinBox:return _native().spin(parent,text,value,low,high,step)
func _denominator(parent:Node,selected:int)->OptionButton:return _native().denominator(parent,selected)
