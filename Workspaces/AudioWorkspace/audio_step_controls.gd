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
 return {"steps":16,"division":0.25,"swing":0.0,"accent_variation":0.0,"seed":1,"lanes":{}}

func setup(value:KiwiAudioEditSession, view:KiwiAudioPatternCanvas) -> void:
 session=value;canvas=view
 if step_count==null:
  var row:=HFlowContainer.new();add_child(row)
  step_count=_spin(row,"Steps",1,256,1,func(v:float):_set_setting("steps",int(v),true))
  var label:=Label.new();label.text="Division";row.add_child(label)
  division=OptionButton.new();division.name="Division";row.add_child(division)
  for text in DIVISION_LABELS:division.add_item(text)
  division.item_selected.connect(func(index:int):_set_setting("division",DIVISIONS[index],true))
  swing=_spin(row,"Swing %",-45,45,1,func(v:float):_set_setting("swing",v/100.0))
  accent_variation=_spin(row,"Accent variation %",0,100,1,func(v:float):_set_setting("accent_variation",v/100.0))
  seed_input=_spin(row,"Seed",0,2147483647,1,func(v:float):_set_setting("seed",int(v)))
  var lanes:=HFlowContainer.new();add_child(lanes)
  for i in KiwiAudioPatternCanvas.DRUMS.size():
   var pitch:=int(KiwiAudioPatternCanvas.DRUMS[i]);var lane:=HBoxContainer.new();lanes.add_child(lane)
   var name_label:=Label.new();name_label.text=KiwiAudioPatternCanvas.DRUM_NAMES[i];lane.add_child(name_label)
   var mute:=CheckBox.new();mute.text="M";mute.tooltip_text="Mute "+name_label.text;lane.add_child(mute)
   var solo:=CheckBox.new();solo.text="S";solo.tooltip_text="Solo "+name_label.text;lane.add_child(solo)
   mute.toggled.connect(func(v:bool):_set_lane(pitch,"mute",v));solo.toggled.connect(func(v:bool):_set_lane(pitch,"solo",v))
   lane_controls[str(pitch)]={"mute":mute,"solo":solo}
 sync_selection()

func _spin(parent:Node,label:String,low:float,high:float,step:float,callback:Callable) -> SpinBox:
 var text:=Label.new();text.text=label;parent.add_child(text)
 var spin:=SpinBox.new();spin.name=label.replace(" ","");spin.min_value=low;spin.max_value=high;spin.step=step;spin.custom_minimum_size.x=70;parent.add_child(spin);spin.value_changed.connect(callback)
 return spin

func sync_selection() -> void:
 if step_count==null:return
 _syncing=true
 var actor:=session.primary_actor() if session!=null else null
 var editable:=actor!=null and KiwiAudioEditSession.is_note_source(actor) and session.primary_clip()!=null and session.can_edit(session.primary_clip().id)
 var settings:=default_settings()
 if actor!=null:settings.merge(actor.values.get(&"step_settings",{}),true)
 for spin in [step_count,swing,accent_variation,seed_input]:spin.editable=editable
 division.disabled=not editable
 step_count.set_value_no_signal(float(settings.steps));swing.set_value_no_signal(float(settings.swing)*100);accent_variation.set_value_no_signal(float(settings.accent_variation)*100);seed_input.set_value_no_signal(float(settings.seed))
 var index:=0
 for i in DIVISIONS.size():
  if is_equal_approx(float(settings.division),float(DIVISIONS[i])):index=i;break
 division.select(index)
 if canvas!=null:canvas.snap_beat=float(settings.division)
 for pitch in lane_controls:
  var lane:Dictionary=settings.lanes.get(pitch,{})
  for key in ["mute","solo"]:
   var control:CheckBox=lane_controls[pitch][key];control.disabled=not editable;control.set_pressed_no_signal(bool(lane.get(key,false)))
 _syncing=false

func _set_setting(key:String,value:Variant,resize_pattern:bool=false) -> void:
 if _syncing or session==null:return
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 if actor==null or clip==null or not KiwiAudioEditSession.is_note_source(actor) or not session.can_edit(clip.id):return
 session.action("Edit step "+key.replace("_"," "),func():
  var settings:=default_settings();settings.merge(actor.values.get(&"step_settings",{}),true);settings[key]=value
  actor.values[&"step_settings"]=settings;actor.values[&"notes_dirty"]=true
  if resize_pattern:actor.values[&"pattern_beats"]=float(settings.steps)*float(settings.division))
 sync_selection();changed.emit()

func _set_lane(pitch:int,key:String,value:bool) -> void:
 if _syncing or session==null:return
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 if actor==null or clip==null or not KiwiAudioEditSession.is_note_source(actor) or not session.can_edit(clip.id):return
 session.action("Edit step lane "+key,func():
  var settings:=default_settings();settings.merge(actor.values.get(&"step_settings",{}),true)
  var lanes:Dictionary=settings.lanes.duplicate(true);var lane:Dictionary=lanes.get(str(pitch),{}).duplicate(true);lane[key]=value;lanes[str(pitch)]=lane;settings.lanes=lanes
  actor.values[&"step_settings"]=settings;actor.values[&"notes_dirty"]=true)
 changed.emit()

static func render_copy(notes:Array,settings:Dictionary,instrument:Dictionary={}) -> Array:
 var result:Array=notes.duplicate(true)
 if settings.is_empty():return result
 var step_beats:=clampf(float(settings.get("division",0.25)),1.0/12.0,1.0)
 var amount:=clampf(float(settings.get("swing",0.0)),-0.45,0.45)
 var variation:=clampf(float(settings.get("accent_variation",0.0)),0,1)
 var lanes:Dictionary=settings.get("lanes",{})
 var has_solo:=false
 for lane in lanes.values():
  if lane is Dictionary and bool(lane.get("solo",false)):has_solo=true
 var seed_value:=int(settings.get("seed",instrument.get("seed",1)))
 for index in result.size():
  var note:Dictionary=result[index]
  var lane:Dictionary=lanes.get(str(int(note.get("pitch",60))),{})
  if bool(lane.get("mute",false)) or (has_solo and not bool(lane.get("solo",false))):note["mute"]=true
  var start:=float(note.get("start",0));var cell:=roundi(start/step_beats)
  if cell%2==1:note["start"]=maxf(0,start+amount*step_beats)
  if variation>0:
   # Per-note seed keeps unrelated lanes stable when another lane is muted.
   var rng:=RandomNumberGenerator.new();rng.seed=seed_value ^ str(note.get("id",index)).hash()
   note["velocity"]=clampf(float(note.get("velocity",0.8))*(1.0+rng.randf_range(-0.5,0.5)*variation),0,1)
 return result
