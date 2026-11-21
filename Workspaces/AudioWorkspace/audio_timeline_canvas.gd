class_name KiwiAudioTimelineCanvas
extends Control
signal seek_requested(seconds: float, scrub: bool)
signal edit_requested(clip_id: String)
signal context_requested(at: Vector2)
signal asset_dropped(data: Variant, seconds: float, track_id: String)
signal range_changed(selection: Vector2)
signal automation_requested(lane_id: String, retarget: bool)
var session: KiwiAudioEditSession
var cache: KiwiAudioSourceCache
var playhead: float = 0
var zoom: float = 100
var scroll_time: float = 0
var track_scroll: float = 0
var track_height: float = 82
var snap := true
var snap_beats: float = 0.25
var time_selection := Vector2.ZERO
var _drag := ""
var _gesture := KiwiAudioEditGesture.new()
var _origin := Vector2.ZERO
var _clip_originals: Dictionary = {}
var _changed := false
var _lane_id := ""
var _lane_point: Dictionary = {}
var _lane_before: KiwiAudioDocument
var _lane_session: KiwiAudioEditSession
var _conductor_revision := -1
var _conductor_document: KiwiAudioDocument
var _conductor: KiwiAudioConductor
var _font: Font
const LABEL_WIDTH := 174.0
const RULER := 30.0
func _ready()->void:
 _native().ready(self)
func time_at(x:float)->float:
 return _native().time_at(self,x)
func x_at(time:float)->float:
 return _native().x_at(self,time)
func track_at(y:float)->int:
 return _native().track_at(self,y)
func clip_rect(clip:ActorClip)->Rect2:
 return _native().clip_rect(self,clip)
func clip_at(point:Vector2)->ActorClip:
 return _native().clip_at(self,point)
func project_conductor()->KiwiAudioConductor:
 return _native().project_conductor(self)
func snap_time(time:float,excluded:Array[String]=[])->float:
 return _native().snap_time(self,time,excluded)
func _draw()->void:
 _native().draw(self)
func _get_tooltip(at_position:Vector2)->String:
 return _native().tooltip(self,at_position)
func _style(fill:Color,border:Color)->StyleBoxFlat:
 return _native().style(fill,border)
func _gui_input(event:InputEvent)->void:
 _native().gui_input(self,event)
func finish_edit(keep:bool=true)->void:
 _native().finish_edit(self,keep)
func _can_drop_data(_at:Vector2,data:Variant)->bool:
 return _native().can_drop_data(self,_at,data)
func _drop_data(at:Vector2,data:Variant)->void:
 _native().drop_data(self,at,data)
func _automation_point_position(info:Dictionary,point:Dictionary,y:float)->Vector2:
 return _native().automation_point_position(self,info,point,y)
func _draw_automation_lane(track:Dictionary,y:float)->void:
 _native().draw_automation_lane(self,track,y)
func _automation_hit(info:Dictionary,position:Vector2,y:float)->int:
 return _native().automation_hit(self,info,position,y)
func _automation_value_at(info:Dictionary,position:Vector2,y:float)->Dictionary:
 return _native().automation_value_at(self,info,position,y)
func _handle_automation_input(event:InputEvent)->bool:
 return _native().handle_automation_input(self,event)
func finish_automation_edit(keep:bool=true)->void:
 _native().finish_automation_edit(self,keep)
func _notification(what:int)->void:
 _native().canvas_notification(self,what)
func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_timeline_canvas")

func _waveform_ready(_key:String)->void:
 queue_redraw()
