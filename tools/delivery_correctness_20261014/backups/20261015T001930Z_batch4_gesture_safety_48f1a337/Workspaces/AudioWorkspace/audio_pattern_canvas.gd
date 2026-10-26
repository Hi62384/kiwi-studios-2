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
var _origin := Vector2.ZERO
var _original: Dictionary = {}
var _font: Font
const KEYS := 70.0
const TOP := 24.0
const DRUMS := [36,38,42,46,45,49,51,39]
const DRUM_NAMES := ["Kick","Snare","Closed hat","Open hat","Tom","Crash","Ride","Clap"]
func _ready()->void:
 focus_mode=Control.FOCUS_ALL;clip_contents=true;custom_minimum_size=Vector2(300,180);_font=ThemeDB.fallback_font
func notes()->Array:
 var actor:=session.primary_actor() if session!=null else null
 return actor.values.get(&"notes",[]) if actor!=null else []
func _pitch(y:float)->int:
 var row:=int((y-TOP)/row_height)
 return int(DRUMS[clampi(row,0,DRUMS.size()-1)]) if mode=="steps" else clampi(start_pitch-row,0,127)
func _note_rect(note:Dictionary)->Rect2:
 var row:=DRUMS.find(int(note.pitch)) if mode=="steps" else start_pitch-int(note.pitch)
 return Rect2(KEYS+(float(note.start)-scroll_beat)*pixels_per_beat,TOP+row*row_height+1,maxf(5,float(note.duration)*pixels_per_beat),row_height-2)
func _hit(point:Vector2)->Dictionary:
 for note in notes():
  if _note_rect(note).has_point(point):return note
 return {}
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("101a24"))
 var rows:=DRUMS.size() if mode=="steps" else ceili((size.y-TOP)/row_height)
 for row in rows:
  var pitch:=int(DRUMS[row]) if mode=="steps" else start_pitch-row
  var y:=TOP+row*row_height
  var black:=pitch%12 in [1,3,6,8,10]
  var scale_notes: Array=KiwiAudioComposer.scales().get(session.document.scale if session!=null else "minor",[0,2,3,5,7,8,10])
  var in_scale:=scale_notes.has(posmod(pitch-(session.document.key if session!=null else 0),12))
  draw_rect(Rect2(KEYS,y,size.x-KEYS,row_height),Color("1a2b30") if in_scale else Color("17212b"))
  draw_line(Vector2(KEYS,y+row_height),Vector2(size.x,y+row_height),Color("263441"))
  draw_rect(Rect2(0,y,KEYS-2,row_height-1),Color("263542") if black else Color("a4b4bb"))
  if mode=="steps" or pitch%12==0:
   var label:=str(DRUM_NAMES[row]) if mode=="steps" else "C%d" % (pitch/12-1)
   draw_string(_font,Vector2(5,y+row_height-4),label,HORIZONTAL_ALIGNMENT_LEFT,64,10,Color("e5f0f2") if black else Color("142632"))
 var first:=floori(scroll_beat/snap_beat)
 var last:=ceili((scroll_beat+maxf(0,size.x-KEYS)/pixels_per_beat)/snap_beat)
 for step in range(first,last+1):
  var beat:=step*snap_beat;var x:=KEYS+(beat-scroll_beat)*pixels_per_beat
  draw_line(Vector2(x,TOP),Vector2(x,size.y),Color("466371") if is_zero_approx(fposmod(beat,1.0)) else Color("293b47"))
  if is_zero_approx(fposmod(beat,1.0)):draw_string(_font,Vector2(x+4,17),str(int(beat)+1),HORIZONTAL_ALIGNMENT_LEFT,50,11,Color("b0c5d1"))
 for note in notes():
  var rect:=_note_rect(note)
  var color:=Color("62d6b5").lerp(Color("e3c279"),float(note.get("velocity",0.8)))
  if selected.has(str(note.id)):color=color.lightened(0.25)
  draw_rect(rect,color)
  if session!=null:
   var clip:=session.primary_clip();var global_beat:float=float(note.start)+(clip.start_time*session.document.arrangement_tempo()/60 if clip!=null else 0)
   for chord in session.document.chords:
    if global_beat>=float(chord.get("start",0)) and global_beat<float(chord.get("start",0))+float(chord.get("duration",1)):
     var tones:Array=chord.get("pitches",[])
     for pitch in tones:
      if posmod(int(note.pitch),12)==posmod(int(pitch),12):draw_rect(rect,Color("ffefb4"),false,1.5);break
     break
  if rect.size.x>28:draw_string(_font,rect.position+Vector2(3,rect.size.y-3),str(int(note.pitch)),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-4,10,Color("143129"))
  var velocity:=clampf(float(note.get("velocity",0.8)),0,1)
  draw_line(Vector2(rect.position.x,size.y-2),Vector2(rect.position.x,size.y-2-velocity*22),color,3)
 if session!=null and session.primary_clip()!=null:
  var clip:=session.primary_clip();var actor:=session.primary_actor()
  var timing:=KiwiAudioTempoMap.new(actor.values.get(&"midi_tempos",[]),KiwiAudioEditSession.note_source_tempo(actor,session.document),float(actor.values.get(&"midi_tempo_scale",1.0)))
  if not timing.error.is_empty():return
  var source_seconds:=clip.source_offset*float(actor.values.get(&"notes_source_scale",1.0))
  var window_seconds:=clip.duration*clip.playback_speed
  var end_seconds:=source_seconds+window_seconds
  var wraps:=false
  if bool(actor.values.get(&"loop",false)):
   var period:=timing.beat_to_seconds(pattern_beats)
   if period>0.0:
    source_seconds=fposmod(source_seconds,period);end_seconds=source_seconds+window_seconds
    if window_seconds>=period:source_seconds=0.0;end_seconds=period
    elif end_seconds>period:end_seconds-=period;wraps=true
  var source_start:=timing.seconds_to_beat(source_seconds);var source_end:=timing.seconds_to_beat(end_seconds)
  var left:=KEYS+(source_start-scroll_beat)*pixels_per_beat;var right:=KEYS+(source_end-scroll_beat)*pixels_per_beat
  if wraps:
   draw_rect(Rect2(maxf(KEYS,right),TOP,maxf(0,minf(size.x,left)-maxf(KEYS,right)),size.y-TOP),Color(0,0,0,0.45))
  else:
   if source_start>0.00001:draw_rect(Rect2(KEYS,TOP,maxf(0,minf(size.x,left)-KEYS),size.y-TOP),Color(0,0,0,0.45))
   if right<size.x:draw_rect(Rect2(maxf(KEYS,right),TOP,size.x-maxf(KEYS,right),size.y-TOP),Color(0,0,0,0.45))
  for boundary in [left,right]:
   if boundary>=KEYS and boundary<=size.x:draw_line(Vector2(boundary,TOP),Vector2(boundary,size.y),Color("82afff"),2)
 var loop_x:=KEYS+(pattern_beats-scroll_beat)*pixels_per_beat
 draw_line(Vector2(loop_x,0),Vector2(loop_x,size.y),Color("eac56f"),2)
func editable()->bool:
 return session!=null and session.primary_clip()!=null and session.primary_actor()!=null and session.can_edit(session.primary_clip().id)
func _mark_changed()->void:
 var actor:=session.primary_actor()
 if actor==null:return
 actor.values[&"notes_dirty"]=true
 var length:=float(actor.values.get(&"pattern_beats",pattern_beats))
 for note in notes():length=maxf(length,ceilf(float(note.start)+float(note.duration)))
 actor.values[&"pattern_beats"]=length;pattern_beats=length
func _changed()->void:
 notes_changed.emit();queue_redraw()
func _gui_input(event:InputEvent)->void:
 if session==null or session.primary_actor()==null or not session.can_edit(session.primary_clip().id):return
 if event is InputEventMouseButton:
  if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
   var direction:=1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1
   if event.ctrl_pressed:pixels_per_beat=clampf(pixels_per_beat*pow(1.2,direction),15,1000)
   elif event.shift_pressed:scroll_beat=maxf(0,scroll_beat-direction)
   elif mode=="piano":start_pitch=clampi(start_pitch+direction*3,12,127)
   queue_redraw();accept_event();return
  if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
   var note:=_hit(event.position)
   if not note.is_empty():session.action("Delete note",func():notes().erase(note);_mark_changed());_changed()
   return
  if event.button_index!=MOUSE_BUTTON_LEFT:return
  if not event.pressed:
   if not _drag.is_empty():_mark_changed();session.commit();_changed()
   _drag="";return
  grab_focus();_origin=event.position
  if event.position.x<KEYS:audition.emit(_pitch(event.position.y));return
  var note:=_hit(event.position)
  if note.is_empty():
   var created:Dictionary={"id":ActorData.new_id(),"pitch":_pitch(event.position.y),"start":maxf(0,snappedf(scroll_beat+(event.position.x-KEYS)/pixels_per_beat,snap_beat)),"duration":snap_beat,"velocity":0.8,"probability":1.0,"ratchets":1}
   session.action("Add note",func():
    var values:=notes();values.append(created);session.primary_actor().values[&"notes"]=values;_mark_changed())
   selected.assign([created.id]);audition.emit(int(created.pitch));_changed();return
  if mode=="steps" and not event.ctrl_pressed and not event.shift_pressed:
   session.action("Remove step",func():notes().erase(note);_mark_changed());_changed();return
  if not event.ctrl_pressed:selected.clear()
  if not selected.has(str(note.id)):selected.append(str(note.id))
  _drag="velocity" if event.alt_pressed or event.position.y>size.y-26 else ("resize" if event.position.x>_note_rect(note).end.x-8 else "move")
  _original.clear()
  for entry in notes():
   if selected.has(str(entry.id)):_original[entry.id]=entry.duplicate(true)
  session.begin("Edit notes");queue_redraw()
 elif event is InputEventMouseMotion and not _drag.is_empty():
  var delta:Vector2=event.position-_origin
  var earliest:=INF;var lowest:=127;var highest:=0
  for original in _original.values():
   earliest=minf(earliest,float(original.start));lowest=mini(lowest,int(original.pitch));highest=maxi(highest,int(original.pitch))
  var beat_delta:=maxf(-earliest,snappedf(delta.x/pixels_per_beat,snap_beat))
  var pitch_delta:=clampi(-int(round(delta.y/row_height)),-lowest,127-highest)
  for note in notes():
   if not _original.has(note.id):continue
   var original:Dictionary=_original[note.id]
   match _drag:
    "move":
     note.start=float(original.start)+beat_delta
     if mode=="piano":note.pitch=int(original.pitch)+pitch_delta
    "resize":note.duration=maxf(snap_beat,snappedf(float(original.duration)+delta.x/pixels_per_beat,snap_beat))
    "velocity":note.velocity=clampf(float(original.get("velocity",0.8))-delta.y/100,0.01,1)
  queue_redraw()
func delete_selected()->void:
 if not editable():return
 session.action("Delete notes",func():
  var keep:Array=notes().filter(func(note:Dictionary):return not selected.has(str(note.id)))
  session.primary_actor().values[&"notes"]=keep;_mark_changed())
 selected.clear();_changed()
func copy()->void:
 _clipboard.clear()
 for note in notes():
  if selected.has(str(note.id)):_clipboard.append(note.duplicate(true))
func paste(at:float=0)->void:
 if _clipboard.is_empty() or not editable():return
 var earliest:=INF
 for note in _clipboard:earliest=minf(earliest,float(note.start))
 session.action("Paste notes",func():
  selected.clear()
  for note in _clipboard:
   var duplicate:Dictionary=note.duplicate(true);duplicate.id=ActorData.new_id();duplicate.start=float(note.start)-earliest+at
   notes().append(duplicate);selected.append(duplicate.id)
  _mark_changed())
 _changed()
func quantize()->void:
 if not editable():return
 session.action("Quantize notes",func():
  for note in notes():
   if selected.is_empty() or selected.has(str(note.id)):
    note.start=snappedf(float(note.start),snap_beat);note.duration=maxf(snap_beat,snappedf(float(note.duration),snap_beat))
  _mark_changed())
 _changed()
func _unhandled_key_input(event:InputEvent)->void:
 if not has_focus() or not event is InputEventKey or not event.pressed or event.echo:return
 if event.keycode==KEY_DELETE:delete_selected()
 elif event.ctrl_pressed and event.keycode==KEY_A:
  selected.clear()
  for note in notes():selected.append(str(note.id))
  queue_redraw()
 elif event.ctrl_pressed and event.keycode==KEY_C:copy()
 elif event.ctrl_pressed and event.keycode==KEY_V:paste(scroll_beat)
 elif event.ctrl_pressed and event.keycode==KEY_D:copy();paste(pattern_beats)
 else:return
 get_viewport().set_input_as_handled()
