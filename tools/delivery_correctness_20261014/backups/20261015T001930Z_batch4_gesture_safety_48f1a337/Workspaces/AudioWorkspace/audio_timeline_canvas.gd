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
func _ready() -> void:
 focus_mode = Control.FOCUS_ALL
 mouse_default_cursor_shape = Control.CURSOR_ARROW
 custom_minimum_size = Vector2(400,180)
 clip_contents = true
 _font = ThemeDB.fallback_font
 if session != null:
  session.changed.connect(queue_redraw)
  session.selection_changed.connect(queue_redraw)
 if cache != null: cache.waveform_ready.connect(func(_key: String): queue_redraw())
func time_at(x: float) -> float:
 return maxf(0,scroll_time+(x-LABEL_WIDTH)/zoom)
func x_at(time: float) -> float:
 return LABEL_WIDTH+(time-scroll_time)*zoom
func track_at(y: float) -> int:
 if session==null: return -1
 return clampi(int((y-RULER+track_scroll)/track_height),0,maxi(0,session.document.tracks.size()-1))
func clip_rect(clip: ActorClip) -> Rect2:
 var track := session.document.track_for_clip(clip.id)
 var index := session.document.tracks.find(track)
 return Rect2(x_at(clip.start_time),RULER+index*track_height-track_scroll+7,maxf(3,clip.duration*zoom),track_height-14)
func clip_at(point: Vector2) -> ActorClip:
 if session==null or point.x<LABEL_WIDTH: return null
 for i in range(session.document.clips.size()-1,-1,-1):
  if clip_rect(session.document.clips[i]).has_point(point): return session.document.clips[i]
 return null
func project_conductor() -> KiwiAudioConductor:
 if _conductor==null or _conductor_revision!=session.revision or _conductor_document!=session.document:
  _conductor_document=session.document;_conductor_revision=session.revision;_conductor=session.document.conductor()
 return _conductor
func snap_time(time: float, excluded: Array[String] = []) -> float:
 if not snap or session==null: return maxf(0,time)
 var best := project_conductor().snap_seconds(time,snap_beats)
 var distance := absf(best-time)
 var candidates: Array[float] = []
 for marker in session.document.markers: candidates.append(float(marker.time))
 for clip in session.document.clips:
  if excluded.has(clip.id): continue
  candidates.append(clip.start_time); candidates.append(clip.start_time+clip.duration)
  var actor := session.document.actor_for_clip(clip.id)
  for attack in actor.values.get(&"transients", []): candidates.append(clip.start_time+(float(attack)-clip.source_offset)/clip.playback_speed)
 for candidate in candidates:
  var delta := absf(candidate-time)
  if delta<distance and delta*zoom<10: best=candidate;distance=delta
 return maxf(0,best)
func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("101820"))
 if session==null: return
 var document := session.document
 var conductor := project_conductor()
 var previous_label := -1000.0
 for point in conductor.grid(scroll_time,scroll_time+maxf(0,size.x-LABEL_WIDTH)/zoom,zoom):
  var x := x_at(float(point.seconds))
  if x<LABEL_WIDTH: continue
  var major := bool(point.downbeat)
  draw_line(Vector2(x,RULER),Vector2(x,size.y),Color("354753") if major else Color("202d37"))
  if x-previous_label>=48 and (major or zoom*60/conductor.tempo_at(float(point.seconds))*float(point.unit)>55):
   draw_string(_font,Vector2(x+4,19),"%d.%d" % [int(point.bar),int(point.beat)],HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("9eb6c6"));previous_label=x
 # Small ticks mark conductor changes; full editable values live in Conductor.
 for points in [document.tempo_points,document.meter_points]:
  for point in points:
   var x:=x_at(conductor.beat_to_seconds(float(point.beat)))
   if x>=LABEL_WIDTH and x<size.x:draw_line(Vector2(x,1),Vector2(x,6),Color("d49aea"),2)
 for index in document.tracks.size():
  var track: Dictionary = document.tracks[index]
  var y := RULER+index*track_height-track_scroll
  if y+track_height<RULER or y>size.y: continue
  draw_line(Vector2(LABEL_WIDTH,y+track_height),Vector2(size.x,y+track_height),Color("283947"))
  if KiwiAudioAutomationLane.is_lane(track):_draw_automation_lane(track,y);continue
  var points: Array = track.get("automation",{}).get("volume_db",[])
  if not points.is_empty():
   var previous := Vector2.ZERO
   for i in points.size():
    var point := Vector2(x_at(float(points[i].time)),y+track_height-10-clampf((float(points[i].value)+60)/72,0,1)*20)
    if i>0: draw_line(previous,point,Color("efc676"),1.5)
    draw_circle(point,3,Color("efc676"));previous=point
 for clip in document.clips:
  var rect := clip_rect(clip)
  if rect.end.x<LABEL_WIDTH or rect.position.x>size.x or rect.end.y<RULER or rect.position.y>size.y: continue
  var actor := document.actor_for_clip(clip.id)
  var track := document.track_for_clip(clip.id)
  var color: Color = track.get("color",Color("63d9bc"))
  if bool(track.get("mute",false)) or bool(actor.values.get(&"muted",false)): color=color.darkened(0.55)
  draw_style_box(_style(color.darkened(0.65),color if session.selected_ids.has(clip.id) else color.darkened(0.35)),rect)
  var entry := cache.request_source(actor.values.get(&"audio")) if cache!=null else {}
  if not entry.is_empty():
   var left := maxf(rect.position.x,LABEL_WIDTH);var right:=minf(rect.end.x,size.x)
   var width := maxi(1,int(right-left))
   var offset := clip.source_offset+(left-rect.position.x)/zoom*clip.playback_speed
   var peaks := KiwiAudioSourceCache.range_peaks(entry,offset,float(width)/zoom*clip.playback_speed,width)
   for pixel in peaks.size():
    var peak := peaks[peaks.size()-1-pixel] if bool(actor.values.get(&"reverse",false)) else peaks[pixel]
    var middle := rect.position.y+rect.size.y*0.64
    draw_line(Vector2(left+pixel,middle-peak.y*rect.size.y*0.27),Vector2(left+pixel,middle-peak.x*rect.size.y*0.27),color.lightened(0.15))
  var title := actor.display_name
  if bool(entry.get("missing",false)): title="Missing: "+title
  draw_string(_font,rect.position+Vector2(7,16),title,HORIZONTAL_ALIGNMENT_LEFT,maxf(0,rect.size.x-14),12,Color("e5f0f4"))
  if session.selected_ids.has(clip.id):
   for edge in [rect.position.x,rect.end.x]: draw_line(Vector2(edge,rect.position.y+5),Vector2(edge,rect.end.y-5),color,3)
   var fade_in := minf(rect.size.x,float(actor.values.get(&"fade_in",0))*zoom)
   var fade_out := minf(rect.size.x,float(actor.values.get(&"fade_out",0))*zoom)
   draw_line(rect.position+Vector2(0,rect.size.y),rect.position+Vector2(fade_in,0),Color("efd288"),1.5)
   draw_line(Vector2(rect.end.x-fade_out,rect.position.y),rect.end,Color("efd288"),1.5)
   draw_circle(rect.position+Vector2(fade_in,3),4,Color("efd288"))
   draw_circle(Vector2(rect.end.x-fade_out,rect.position.y+3),4,Color("efd288"))
 var loop_left := x_at(document.loop_start);var loop_right := x_at(document.loop_end)
 if loop_right>LABEL_WIDTH and loop_left<size.x:
  draw_rect(Rect2(maxf(LABEL_WIDTH,loop_left),22,maxf(0,minf(loop_right,size.x)-maxf(LABEL_WIDTH,loop_left)),6),Color("467d6e"))
 for marker in document.markers:
  var x:=x_at(float(marker.time))
  if x>=LABEL_WIDTH and x<size.x:
   draw_line(Vector2(x,RULER),Vector2(x,size.y),Color("e3bb68"),1)
   draw_string(_font,Vector2(x+4,28),str(marker.get("name","Marker")),HORIZONTAL_ALIGNMENT_LEFT,120,10,Color("e3bb68"))
 if time_selection.y>time_selection.x:
  draw_rect(Rect2(x_at(time_selection.x),RULER,(time_selection.y-time_selection.x)*zoom,size.y-RULER),Color(0.3,0.7,0.9,0.13))
 var play_x:=x_at(playhead)
 if play_x>=LABEL_WIDTH:
  draw_line(Vector2(play_x,0),Vector2(play_x,size.y),Color("f6d691"),2)
  draw_colored_polygon(PackedVector2Array([Vector2(play_x-5,0),Vector2(play_x+5,0),Vector2(play_x,8)]),Color("f6d691"))
 draw_rect(Rect2(0,0,LABEL_WIDTH,size.y),Color("17232e"))
 draw_string(_font,Vector2(12,20),"TRACKS  /  BARS · BEATS",HORIZONTAL_ALIGNMENT_LEFT,155,10,Color("89a8ba"))
 for index in document.tracks.size():
  var track:Dictionary=document.tracks[index];var y:=RULER+index*track_height-track_scroll
  if y+track_height<RULER or y>size.y:continue
  if str(track.id)==session.selected_track:draw_rect(Rect2(0,y,LABEL_WIDTH,track_height),Color("223b45"))
  draw_rect(Rect2(0,y,4,track_height),track.get("color",Color("63d9bc")))
  draw_string(_font,Vector2(12,y+22),str(track.name),HORIZONTAL_ALIGNMENT_LEFT,LABEL_WIDTH-25,13,Color("e3edf2"))
  var lane:=KiwiAudioAutomationLane.is_lane(track)
  var sublabel:=str(KiwiAudioAutomationLane.lane_info(document,str(track.id)).get("label","CHOOSE A TARGET")) if lane else str(track.kind).to_upper()+"  %+.1f dB"%float(track.get("volume_db",0))
  draw_string(_font,Vector2(12,y+40),sublabel,HORIZONTAL_ALIGNMENT_LEFT,160,10,Color("8aa3b5"))
  for b in 3:
   var active:=bool(track.get("locked",false)) if lane and b==2 else (false if lane else bool(track.get(["mute","solo","locked"][b],false)))
   draw_style_box(_style(Color("4a7668") if active else Color("273744"),Color("496574")),Rect2(12+b*40,y+49,32,22))
   draw_string(_font,Vector2(22+b*40,y+65),(["E","T","L"][b] if lane else ["M","S","L"][b]),HORIZONTAL_ALIGNMENT_LEFT,20,11,Color("d7e8ec"))
func _style(fill:Color,border:Color)->StyleBoxFlat:
 var style:=StyleBoxFlat.new();style.bg_color=fill;style.border_color=border;style.set_border_width_all(1);style.set_corner_radius_all(4);return style
func _gui_input(event:InputEvent)->void:
 if session==null:return
 if _handle_automation_input(event):accept_event();return
 if event is InputEventMouseButton:
  if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
   var direction:=1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0
   if event.ctrl_pressed:
    var anchor:=time_at(event.position.x);zoom=clampf(zoom*pow(1.2,direction),8,200000);scroll_time=maxf(0,anchor-(event.position.x-LABEL_WIDTH)/zoom)
   elif event.shift_pressed:scroll_time=maxf(0,scroll_time-direction*80/zoom)
   else:track_scroll=clampf(track_scroll-direction*35,0,maxf(0,session.document.tracks.size()*track_height-size.y+RULER))
   queue_redraw();accept_event();return
  if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
   var clip:=clip_at(event.position)
   if clip!=null and not session.selected_ids.has(clip.id):session.select(clip.id)
   context_requested.emit(event.global_position);accept_event();return
  if event.button_index!=MOUSE_BUTTON_LEFT:return
  if not event.pressed:
   if _drag in ["move","trim_left","trim_right","slip","stretch","fade_in","fade_out"]:
    if _changed:session.commit()
    else:session.cancel()
   _drag="";accept_event();return
  grab_focus();_origin=event.position;_changed=false
  if event.position.x<LABEL_WIDTH and event.position.y>=RULER:
   var index:=track_at(event.position.y)
   if index<0 or index>=session.document.tracks.size():return
   var track:Dictionary=session.document.tracks[index];session.selected_ids.clear();session.selected_track=track.id
   var local_y:float=event.position.y-(RULER+index*track_height-track_scroll)
   if local_y>=49 and local_y<=71:
    var button:=int((event.position.x-12)/40)
    if button>=0 and button<3:
     if KiwiAudioAutomationLane.is_lane(track) and button<2:
      session.selection_changed.emit();automation_requested.emit(str(track.id),button==1);queue_redraw();return
     var key:String=["mute","solo","locked"][button]
     session.action("Toggle "+key,func():track[key]=not bool(track.get(key,false)))
   session.selection_changed.emit();queue_redraw();return
  if event.position.y<RULER:
   _drag="range" if event.shift_pressed else "seek"
   var time:=snap_time(time_at(event.position.x))
   if _drag=="range":time_selection=Vector2(time,time)
   else:seek_requested.emit(time,true)
   queue_redraw();return
  var clip:=clip_at(event.position)
  if clip==null:
   if event.shift_pressed:
    _drag="range";var time:=snap_time(time_at(event.position.x));time_selection=Vector2(time,time)
   else:
    session.select("");seek_requested.emit(snap_time(time_at(event.position.x)),false)
   return
  if event.double_click:session.select(clip.id);edit_requested.emit(clip.id);return
  if not session.selected_ids.has(clip.id) or event.ctrl_pressed:session.select(clip.id,event.ctrl_pressed)
  if not session.can_edit(clip.id):return
  var rect:=clip_rect(clip);var actor:=session.document.actor_for_clip(clip.id)
  _drag="move"
  if event.alt_pressed:_drag="slip"
  elif event.position.y<rect.position.y+12:
   if absf(event.position.x-(rect.position.x+float(actor.values.get(&"fade_in",0))*zoom))<12:_drag="fade_in"
   elif absf(event.position.x-(rect.end.x-float(actor.values.get(&"fade_out",0))*zoom))<12:_drag="fade_out"
  if _drag=="move":
   if absf(event.position.x-rect.position.x)<7:_drag="trim_left"
   elif absf(event.position.x-rect.end.x)<7:_drag="stretch" if event.shift_pressed else "trim_right"
  _clip_originals.clear()
  for id in session.selected_ids:
   var current:=session.document.clip_for_id(id)
   if current!=null:_clip_originals[id]={"start":current.start_time,"duration":current.duration,"offset":current.source_offset,"speed":current.playback_speed,"track":session.document.track_for_clip(id).id,"fade_in":session.document.actor_for_clip(id).values.get(&"fade_in",0),"fade_out":session.document.actor_for_clip(id).values.get(&"fade_out",0)}
  session.begin(_drag.capitalize()+" clips");accept_event()
 elif event is InputEventMouseMotion and not _drag.is_empty():
  if _drag=="seek":seek_requested.emit(snap_time(time_at(event.position.x)),true)
  elif _drag=="range":
   var a:=snap_time(time_at(_origin.x));var b:=snap_time(time_at(event.position.x));time_selection=Vector2(minf(a,b),maxf(a,b));range_changed.emit(time_selection)
  else:
   var delta:float=(event.position.x-_origin.x)/zoom
   for id in _clip_originals:
    var original:Dictionary=_clip_originals[id];var clip:=session.document.clip_for_id(id)
    if clip==null or not session.can_edit(id):continue
    var actor:=session.document.actor_for_clip(id)
    var changes:Dictionary={"start_time":original.start,"duration":original.duration,"source_offset":original.offset,"playback_speed":original.speed}
    match _drag:
     "move":
      changes.start_time=snap_time(float(original.start)+delta,session.selected_ids)
      var old_index:=session.document.tracks.find(session.document.track_for_id(original.track));var shift:=int((event.position.y-_origin.y)/track_height)
      changes.track_id=session.document.tracks[clampi(old_index+shift,0,session.document.tracks.size()-1)].id
     "trim_left":
      var start:=clampf(snap_time(float(original.start)+delta,session.selected_ids),maxf(0,float(original.start)-float(original.offset)/float(original.speed)),float(original.start)+float(original.duration)-1.0/44100)
      changes.start_time=start;changes.duration=float(original.duration)+float(original.start)-start;changes.source_offset=float(original.offset)+(start-float(original.start))*float(original.speed)
     "trim_right":changes.duration=maxf(1.0/44100,snap_time(float(original.start)+float(original.duration)+delta,session.selected_ids)-float(original.start))
     "slip":changes.source_offset=maxf(0,float(original.offset)+delta*float(original.speed))
     "stretch":
      changes.duration=maxf(1.0/44100,snap_time(float(original.start)+float(original.duration)+delta,session.selected_ids)-float(original.start));changes.playback_speed=clampf(float(original.speed)*float(original.duration)/float(changes.duration),0.05,16)
     "fade_in":actor.values[&"fade_in"]=clampf(float(original.fade_in)+delta,0,clip.duration)
     "fade_out":actor.values[&"fade_out"]=clampf(float(original.fade_out)-delta,0,clip.duration)
    if session.edit_clip(id,changes):_changed=true
   session.preview()
  queue_redraw();accept_event()
func _can_drop_data(_at:Vector2,data:Variant)->bool:
 if session==null:return false
 var destination:=track_at(_at.y)
 if destination<0 or destination>=session.document.tracks.size() or KiwiAudioAutomationLane.is_lane(session.document.tracks[destination]):return false
 if data is String:return str(data).get_extension().to_lower() in ["wav","mp3","ogg","flac"]
 if data is PackedStringArray or data is Array:
  for path in data:
   if path is String and str(path).get_extension().to_lower() in ["wav","mp3","ogg","flac"]:return true
  return false
 if not data is Dictionary:return false
 if data.has("audio_library"):return KiwiAudioLibrary.valid_entry(data.audio_library)
 if data.has("audio_generator_payload"):return data.audio_generator_payload is Dictionary and data.audio_generator_payload.get("stream") is AudioStreamWAV and not str(data.audio_generator_payload.get("id","")).is_empty()
 if data.has("generator"):return KiwiAudioLibrary.valid_entry(data.generator)
 if data.has("audio_source"):return data.audio_source is AudioStream or _can_drop_data(_at,data.audio_source)
 if data.has("files"):return _can_drop_data(_at,data.files)
 return false

func _drop_data(at:Vector2,data:Variant)->void:
 var index:=track_at(at.y)
 if index>=0 and index<session.document.tracks.size():asset_dropped.emit(data,snap_time(time_at(at.x)),session.document.tracks[index].id)

func _automation_point_position(info:Dictionary,point:Dictionary,y:float)->Vector2:
 var fraction:=clampf((float(point.value)-float(info.minimum))/maxf(0.000001,float(info.maximum)-float(info.minimum)),0,1)
 return Vector2(x_at(float(info.offset)+float(point.time)),y+track_height-12-fraction*(track_height-28))

func _draw_automation_lane(track:Dictionary,y:float)->void:
 var info:=KiwiAudioAutomationLane.lane_info(session.document,str(track.id))
 if info.is_empty():
  draw_string(_font,Vector2(LABEL_WIDTH+12,y+35),"Target missing or unassigned. Choose T to link a parameter.",HORIZONTAL_ALIGNMENT_LEFT,maxf(1,size.x-LABEL_WIDTH-20),11,Color("d9ba78"));return
 var points:=KiwiAudioAutomationLane.points(info)
 var left:=maxf(LABEL_WIDTH,x_at(float(info.offset)))
 var right:=size.x
 if str(info.target.owner_kind)=="clip":right=minf(right,x_at(float(info.offset)+float(info.duration)))
 if right<=left:return
 var color:=Color("edc874") if KiwiAudioAutomationLane.editable(session.document,str(track.id)) else Color("82919c")
 var samples:=maxi(1,ceili((right-left)/6.0));var previous:=Vector2.ZERO
 for i in samples+1:
  var x:=lerpf(left,right,float(i)/samples);var local:=maxf(0,time_at(x)-float(info.offset))
  var value:=KiwiAudioAutomationLane.value(points,local,float(info.fallback))
  var at:=_automation_point_position(info,{"time":local,"value":value},y)
  if i>0:draw_line(previous,at,color,1.5)
  previous=at
 for point in points:
  var at:=_automation_point_position(info,point,y)
  if at.x>=left and at.x<=right:draw_circle(at,4,color)
 if points.is_empty():draw_string(_font,Vector2(left+6,y+18),"Ctrl-click to add · double-click to edit",HORIZONTAL_ALIGNMENT_LEFT,maxf(1,right-left-12),10,Color("819aab"))

func _automation_hit(info:Dictionary,position:Vector2,y:float)->int:
 var points:=KiwiAudioAutomationLane.points(info)
 var closest:=-1;var distance:=9.0
 for i in points.size():
  var delta:=position.distance_to(_automation_point_position(info,points[i],y))
  if delta<distance:closest=i;distance=delta
 return closest

func _automation_value_at(info:Dictionary,position:Vector2,y:float)->Dictionary:
 var local:=maxf(0,snap_time(time_at(position.x))-float(info.offset))
 local=clampf(local,0,float(info.duration) if str(info.target.owner_kind)=="clip" else 10000000.0)
 var fraction:=clampf((y+track_height-12-position.y)/maxf(1,track_height-28),0,1)
 return {"time":local,"value":lerpf(float(info.minimum),float(info.maximum),fraction),"curve":"linear"}

func _handle_automation_input(event:InputEvent)->bool:
 if not _lane_id.is_empty():
  if session!=_lane_session or session._before!=_lane_before:
   _lane_id="";_lane_point={};_lane_before=null;_lane_session=null
  elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
   finish_automation_edit();return true
  elif event is InputEventMouseMotion:
   var info:=KiwiAudioAutomationLane.lane_info(session.document,_lane_id)
   if info.is_empty() or not KiwiAudioAutomationLane.editable(session.document,_lane_id):finish_automation_edit();return true
   var index:=session.document.tracks.find(session.document.track_for_id(_lane_id))
   var value:=_automation_value_at(info,event.position,RULER+index*track_height-track_scroll)
   var points:=KiwiAudioAutomationLane.points(info)
   # Keep time ordering, and keep adjacent points a small distance apart.
   var at:=points.find(_lane_point)
   if at<0:finish_automation_edit();return true
   var low:=float(points[at-1].time)+0.000001 if at>0 else 0.0
   var high:=float(points[at+1].time)-0.000001 if at+1<points.size() else (float(info.duration) if str(info.target.owner_kind)=="clip" else 10000000.0)
   _lane_point.time=clampf(float(value.time),low,maxf(low,high));_lane_point.value=value.value
   queue_redraw();return true
 if not event is InputEventMouseButton or not event.pressed:return false
 if not event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return false
 if event.position.x<LABEL_WIDTH or event.position.y<RULER or event.position.y>=RULER+session.document.tracks.size()*track_height-track_scroll:return false
 var index:=track_at(event.position.y)
 if index<0 or index>=session.document.tracks.size():return false
 var lane:Dictionary=session.document.tracks[index]
 if not KiwiAudioAutomationLane.is_lane(lane):return false
 # Preserve access to legacy clips until the user converts the old lane to audio.
 if clip_at(event.position)!=null:return false
 if event.shift_pressed:return false
 session.selected_ids.clear();session.selected_track=str(lane.id);session.selection_changed.emit();grab_focus()
 if event.double_click:automation_requested.emit(str(lane.id),false);return true
 var info:=KiwiAudioAutomationLane.lane_info(session.document,str(lane.id))
 if info.is_empty():automation_requested.emit(str(lane.id),true);return true
 var y:=RULER+index*track_height-track_scroll
 var hit:=_automation_hit(info,event.position,y)
 if event.button_index==MOUSE_BUTTON_RIGHT:
  if hit>=0 and KiwiAudioAutomationLane.editable(session.document,str(lane.id)):
   session.action("Delete lane automation point",func():KiwiAudioAutomationLane.points(info).remove_at(hit))
  else:automation_requested.emit(str(lane.id),false)
  return true
 if not KiwiAudioAutomationLane.editable(session.document,str(lane.id)):return true
 if hit<0 and not event.ctrl_pressed:seek_requested.emit(snap_time(time_at(event.position.x)),false);queue_redraw();return true
 var values:=KiwiAudioAutomationLane.points(info)
 var point:=_automation_value_at(info,event.position,y)
 if hit<0:
  for i in values.size():
   if absf(float(values[i].time)-float(point.time))<0.000001:hit=i;break
 if hit<0 and values.size()>=10000:return true
 session.begin("Edit lane automation")
 _lane_id=str(lane.id);_lane_session=session;_lane_before=session._before
 if hit<0:
  var curves:Dictionary=info.owner.get("automation",{});values.append(point);values.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
  curves[str(info.parameter)]=values;info.owner["automation"]=curves;_lane_point=point
 else:_lane_point=values[hit]
 queue_redraw();return true

func finish_automation_edit()->void:
 var owner:=_lane_session;var before:=_lane_before
 _lane_id="";_lane_point={};_lane_session=null;_lane_before=null
 if owner!=null and before!=null and owner._before==before:owner.commit()
 queue_redraw()

func _notification(what:int)->void:
 if what==NOTIFICATION_FOCUS_EXIT or what==NOTIFICATION_EXIT_TREE:
  if not _lane_id.is_empty():finish_automation_edit()
