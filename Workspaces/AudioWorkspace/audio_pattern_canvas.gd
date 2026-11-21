class_name KiwiAudioPatternCanvas
extends Control
signal notes_changed
signal audition(pitch: int)
var session: KiwiAudioEditSession
var mode := "piano"
var pixels_per_beat: float = 90
var row_height: float = 16
var start_pitch: int = 84
var scroll_beat: float = 0
var snap_beat: float = 0.25
var pattern_beats: float = 4
var selected: Array[String] = []
var _clipboard: Array = []
var _drag := ""
var _gesture := KiwiAudioEditGesture.new()
var _drag_clip := ""
var _drag_changed := false
var _origin := Vector2.ZERO
var _original: Dictionary = {}
var _font: Font
const KEYS := 70.0
const TOP := 24.0
const DRUMS := [36,38,42,46,45,49,51,39]
const DRUM_NAMES := ["Kick","Snare","Closed hat","Open hat","Tom","Crash","Ride","Clap"]
func _ready()->void:
 _native().ready(self)
func notes()->Array:
 return _native().notes(self)
func _pitch(y:float)->int:
 return _native().pitch(self,y)
func _note_rect(note:Dictionary)->Rect2:
 return _native().note_rect(self,note)
func _hit(point:Vector2)->Dictionary:
 return _native().hit(self,point)
func _draw()->void:
 _native().draw(self)
func editable()->bool:
 return _native().editable(self)
func _mark_changed()->void:
 _native().mark_changed(self)
func _changed()->void:
 notes_changed.emit();queue_redraw()
func finish_edit(keep:bool=true)->void:
 _native().finish_edit(self,keep)
func _notification(what:int)->void:
 _native().canvas_notification(self,what)
func _gui_input(event:InputEvent)->void:
 _native().gui_input(self,event)
func delete_selected()->void:
 _native().delete_selected(self)
func copy()->void:
 _native().copy(self)
func paste(at:float=0)->void:
 _native().paste(self,at)
func quantize()->void:
 _native().quantize(self)
func _unhandled_key_input(event:InputEvent)->void:
 _native().key_input(self,event)

func _native()->Variant:
 return Engine.get_singleton("KiwiNativeServices").service("audio_pattern_canvas")
