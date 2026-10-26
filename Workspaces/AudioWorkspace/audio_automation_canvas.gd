class_name KiwiAudioAutomationCanvas
extends Control
## Editable automation and deterministic modulation baked into ordinary document points.
var session:KiwiAudioEditSession
var owner_kind:="track"
var owner_id:=""
var effect_id:=""
var lane_id:=""
var _drag_before:KiwiAudioDocument
var _gesture:=KiwiAudioEditSession.Gesture.new()
var _drag_changed:=false
var parameter:="volume_db"
var duration:=10.0
var minimum:=-60.0
var maximum:=12.0
var grid:=0.125
var selected:=-1
var _drag:=false
func _ready()->void:
 focus_mode=Control.FOCUS_ALL
 custom_minimum_size=Vector2(360,230);mouse_default_cursor_shape=Control.CURSOR_CROSS;clip_contents=true
 if session!=null:session.changed.connect(func():
  if _drag and not _gesture.valid(session):finish_edit(false)
  queue_redraw())
func owner_data()->Dictionary:
 if session==null:return {}
 var owner:Dictionary={}
 if owner_kind=="master":owner=session.document.master
 elif owner_kind=="clip":
  var actor:=session.document.actor_for_clip(owner_id)
  owner=actor.values if actor!=null else {}
 else:owner=session.document.track_for_id(owner_id)
 if not effect_id.is_empty():
  for effect in owner.get("effects",[]):
   if str(effect.get("id",""))==effect_id:return effect
  return {}
 return owner
func can_edit()->bool:
 if session==null or owner_data().is_empty():return false
 if not lane_id.is_empty():
  if not KiwiAudioAutomationLane.editable(session.document,lane_id):return false
  var target:Dictionary={"owner_kind":owner_kind,"owner_id":owner_id,"effect_id":effect_id,"parameter":parameter}
  if KiwiAudioAutomationLane.key(session.document.track_for_id(lane_id).get("automation_target",{}))!=KiwiAudioAutomationLane.key(target):return false
 if owner_kind=="master":return true
 if owner_kind=="clip":return session.can_edit(owner_id)
 return not bool(session.document.track_for_id(owner_id).get("locked",false))
func points()->Array:
 return owner_data().get("automation",{}).get(parameter,[])
func position_for(point:Dictionary)->Vector2:
 return Vector2(45+float(point.time)/duration*(size.x-60),size.y-28-(float(point.value)-minimum)/(maximum-minimum)*(size.y-44))
func value_for(point:Vector2)->Dictionary:
 return {"time":clampf(snappedf((point.x-45)/(size.x-60)*duration,grid),0,duration),"value":clampf(minimum+(size.y-28-point.y)/(size.y-44)*(maximum-minimum),minimum,maximum),"curve":"linear"}
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("101c27"))
 var font:=ThemeDB.fallback_font
 for i in 7:
  var value:=lerpf(minimum,maximum,float(i)/6);var y:=position_for({"time":0,"value":value}).y
  draw_line(Vector2(45,y),Vector2(size.x-15,y),Color("304352"));draw_string(font,Vector2(2,y+4),"%.1f"%value,HORIZONTAL_ALIGNMENT_LEFT,40,10)
 for i in 9:
  var t:=duration*i/8;var x:=position_for({"time":t,"value":0}).x
  draw_line(Vector2(x,12),Vector2(x,size.y-28),Color("263846"));draw_string(font,Vector2(x-6,size.y-9),"%.2f"%t,HORIZONTAL_ALIGNMENT_LEFT,55,10)
 var values:=points()
 if values.is_empty():return
 var last:=Vector2.ZERO
 for pixel in maxi(1,int(size.x-60)):
  var time:=duration*pixel/(size.x-60)
  var value:=KiwiAudioAutomationLane.value(values,time,float(owner_data().get("parameters",owner_data()).get(parameter,0)))
  var at:=position_for({"time":time,"value":value})
  if pixel>0:draw_line(last,at,Color("70dfc3"),2)
  last=at
 for i in values.size():draw_circle(position_for(values[i]),5,Color("f7cc74") if i==selected else Color("d6ece7"))
func _hit(position:Vector2)->int:
 for i in points().size():
  if position.distance_to(position_for(points()[i]))<10:return i
 return -1
func finish_edit(keep:bool=true)->void:
 var changed:=_drag_changed
 if keep and _gesture.valid(session):points().sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
 _drag=false;_drag_before=null;_drag_changed=false
 _gesture.finish(session,keep and changed)
 queue_redraw()
func _notification(what:int)->void:
 if what==NOTIFICATION_FOCUS_EXIT:finish_edit()
func _gui_input(event:InputEvent)->void:
 if _drag and not _gesture.valid(session):finish_edit(false)
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:finish_edit(false);accept_event();return
 if not can_edit():
  finish_edit();return
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
   var hit:=_hit(event.position)
   if hit>=0:session.action("Delete automation point",func():points().remove_at(hit));selected=-1;queue_redraw()
   accept_event();return
  if event.button_index!=MOUSE_BUTTON_LEFT:return
  if not event.pressed:
   finish_edit();accept_event();return
  grab_focus();selected=_hit(event.position)
  var proposed:=value_for(event.position)
  if selected<0:
   for i in points().size():
    if absf(float(points()[i].time)-float(proposed.time))<0.000001:selected=i;break
  if selected<0 and points().size()>=10000:return
  _gesture.begin(session,"Edit automation");_drag_before=session._before;_drag_changed=false
  if selected<0:
   var point:=proposed;var curves:Dictionary=owner_data().get("automation",{});var values:Array=curves.get(parameter,[]);values.append(point);values.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time));curves[parameter]=values;owner_data()["automation"]=curves;selected=values.find(point);_drag_changed=true;session.preview()
  _drag=true;queue_redraw();accept_event()
 elif event is InputEventMouseMotion and _drag:
  if selected>=0 and selected<points().size():
   var value:=value_for(event.position);var point:Dictionary=points()[selected]
   var low:=float(points()[selected-1].time)+0.000001 if selected>0 else 0.0
   var high:=float(points()[selected+1].time)-0.000001 if selected+1<points().size() else duration
   var time:=clampf(float(value.time),low,maxf(low,high))
   if not is_equal_approx(float(point.time),time) or not is_equal_approx(float(point.value),float(value.value)):
    point.time=time;point.value=value.value;_drag_changed=true;session.preview()
  queue_redraw();accept_event()
func set_curve(curve:String)->void:
 if not can_edit():return
 if selected<0 or selected>=points().size():return
 session.action("Automation interpolation",func():points()[selected].curve=curve);queue_redraw()
func clear_points()->void:
 if not can_edit():return
 session.action("Clear automation",func():var curves:Dictionary=owner_data().get("automation",{});curves.erase(parameter);owner_data()["automation"]=curves);selected=-1;queue_redraw()
func modulate(settings:Dictionary)->void:
 if not can_edit():return
 var values:=modulation_points(settings,duration,session.document.tempo,minimum,maximum)
 session.action("Generate editable modulation",func():var curves:Dictionary=owner_data().get("automation",{});curves[parameter]=values;owner_data()["automation"]=curves)
 selected=-1;queue_redraw()
static func modulation_points(settings:Dictionary,seconds:float,tempo:float,low:float,high:float)->Array:
 var output:Array=[];var rate:=clampf(float(settings.get("rate",1)),0.01,20)
 if bool(settings.get("sync",true)):rate=tempo/60/maxf(0.0625,float(settings.get("beats",1)))
 var random:=RandomNumberGenerator.new();random.seed=int(settings.get("seed",1));var held:=random.randf_range(-1,1);var cycle:=-1
 var count:=clampi(ceili(seconds*rate*32),2,4096)
 for i in count+1:
  var time:=seconds*i/count;var phase:=time*rate+float(settings.get("phase",0));var value:=sin(TAU*phase)
  match str(settings.get("shape","sine")):
   "triangle":value=1-4*absf(fposmod(phase,1)-0.5)
   "saw":value=2*fposmod(phase,1)-1
   "square":value=1 if fposmod(phase,1)<0.5 else -1
   "random step":
    if floori(phase)!=cycle:cycle=floori(phase);held=random.randf_range(-1,1)
    value=held
   "envelope":value=-1+2*sin(PI*float(i)/count)
  output.append({"time":time,"value":clampf(float(settings.get("center",0))+float(settings.get("depth",1))*value,low,high),"curve":"hold" if str(settings.get("shape","")) in ["square","random step"] else "linear"})
 return output

func _exit_tree()->void:
 finish_edit()
