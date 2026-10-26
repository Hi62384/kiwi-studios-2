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
 _settings=settings.duplicate(true);_layout=settings.get("section_layout",sections).duplicate(true)
 var title:=Label.new();title.text="Role instruments";add_child(title)
 var roles:=HFlowContainer.new();add_child(roles)
 for role in ROLES:
  var label:=Label.new();label.text=str(role).capitalize();roles.add_child(label)
  var choice:=OptionButton.new();choice.name=str(role).capitalize()+"Instrument";roles.add_child(choice);choice.add_item("Style default");choice.set_item_metadata(0,"")
  var current:Variant=_settings.get("instruments",{}).get(role,"")
  var current_id:=str(current.get("id","")) if current is Dictionary else str(current)
  for preset in KiwiAudioInstruments.presets():
   choice.add_item(str(preset.label));choice.set_item_metadata(choice.item_count-1,str(preset.id))
   if str(preset.id)==current_id:choice.select(choice.item_count-1)
  choice.item_selected.connect(func(index:int):
   var instruments:Dictionary=_settings.get("instruments",{}).duplicate(true);var id:=str(choice.get_item_metadata(index))
   if id.is_empty():instruments.erase(role)
   else:instruments[role]=KiwiAudioInstruments.default_instrument(id)
   _settings.instruments=instruments)
  role_controls[role]=choice
 var structure_label:=Label.new();structure_label.text="Section names (comma separated)";add_child(structure_label)
 structure_input=LineEdit.new();structure_input.name="SectionStructure";structure_input.placeholder_text="Intro, Verse, Chorus, Outro";add_child(structure_input)
 var names:=PackedStringArray()
 for item in _settings.get("structure",[]):names.append(str(item.get("name","Section")) if item is Dictionary else str(item))
 structure_input.text=", ".join(names)
 layout_toggle=CheckBox.new();layout_toggle.text="Use exact section positions and lengths (quarter-note beats)";layout_toggle.button_pressed=not _layout.is_empty();add_child(layout_toggle)
 section_rows=VBoxContainer.new();add_child(section_rows);_rebuild_rows()
 var add:=Button.new();add.text="Add section";add_child(add);add.pressed.connect(add_section)
 var note:=Label.new();note.text="Regeneration preserves other parts, source windows and automation. Missing samples leave the document unchanged.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)

func add_section() -> void:
 var end:=0.0
 for item in _layout:end=maxf(end,float(item.start)+float(item.duration))
 _layout.append({"id":ActorData.new_id(),"name":"Section "+str(_layout.size()+1),"start":end,"duration":4.0});layout_toggle.button_pressed=true;_rebuild_rows()

func _rebuild_rows() -> void:
 for child in section_rows.get_children():section_rows.remove_child(child);child.queue_free()
 for index in _layout.size():
  var item:Dictionary=_layout[index];var row:=HFlowContainer.new();section_rows.add_child(row)
  var label:=LineEdit.new();label.text=str(item.get("name","Section"));label.custom_minimum_size.x=120;row.add_child(label);label.text_changed.connect(func(value:String):item.name=value)
  _section_spin(row,"Start",float(item.get("start",0)),0,2048,func(value:float):item.start=value)
  _section_spin(row,"Length",float(item.get("duration",4)),0.25,1024,func(value:float):item.duration=value)
  var remove:=Button.new();remove.text="Remove";row.add_child(remove);remove.pressed.connect(func():_layout.remove_at(index);_rebuild_rows())

func _section_spin(parent:Node,label:String,value:float,low:float,high:float,callback:Callable) -> void:
 var text:=Label.new();text.text=label;parent.add_child(text)
 var spin:=SpinBox.new();spin.min_value=low;spin.max_value=high;spin.step=0.25;spin.value=value;parent.add_child(spin);spin.value_changed.connect(callback)

func settings_copy() -> Dictionary:
 var result:={"instruments":_settings.get("instruments",{}).duplicate(true)}
 var names:Array=[]
 for name in structure_input.text.split(",",false):
  if not name.strip_edges().is_empty():names.append(name.strip_edges().substr(0,128))
 if not names.is_empty():result.structure=names
 if layout_toggle.button_pressed and not _layout.is_empty():result.section_layout=_layout.duplicate(true)
 else:result.erase("section_layout")
 return result

static func snapshot_arrangement(document:KiwiAudioDocument) -> Dictionary:
 var previous:={"settings":document.composer_settings.duplicate(true),"sections":document.sections.duplicate(true),"chords":document.chords.duplicate(true),"parts":[]}
 for clip in document.clips:
  var actor:=document.actor_for_clip(clip.id)
  if actor==null or not actor.values.has(&"composer_role"):continue
  var beats:=float(actor.values.get(&"pattern_beats",float(actor.values.get(&"source_duration",0))*KiwiAudioEditSession.note_source_tempo(actor,document)/60.0))
  previous.parts.append({"id":actor.values.get(&"composer_part_id",""),"role":actor.values[&"composer_role"],"notes":actor.values.get(&"notes",[]).duplicate(true),"instrument":actor.values.get(&"instrument",{}).duplicate(true),"automation":actor.values.get(&"automation",{}).duplicate(true),"step_settings":actor.values.get(&"step_settings",{}).duplicate(true),"pattern_beats":beats,"_actor_id":actor.id,"_clip_id":clip.id})
  if actor.values.has(&"drum_instances"):
   var patterns:Array=[]
   for instance in actor.values.drum_instances:
    var pattern:Dictionary=actor.values.get(&"drum_patterns",{}).get(str(instance.pattern_id),{}).duplicate(true)
    pattern.id=instance.id;pattern.start=instance.start;pattern.section_id=instance.get("section_id","");patterns.append(pattern)
   previous.parts.back()["patterns"]=patterns
 return previous

static func render_arrangement(config:Dictionary,previous:Dictionary,role:String="",section_id:String="",job:RefCounted=null,rate:int=44100) -> Dictionary:
 var partial:=not role.is_empty() or not section_id.is_empty()
 if partial and previous.get("parts",[]).is_empty():return {"error":"There is no generated arrangement to regenerate."}
 if not section_id.is_empty() and not previous.get("sections",[]).any(func(item:Dictionary):return str(item.id)==section_id):return {"error":"The selected arrangement section no longer exists."}
 if not role.is_empty() and role not in ROLES:return {"error":"Unknown composer role."}
 var arrangement:=KiwiAudioComposer.regenerate(config,previous,role,section_id) if partial else KiwiAudioComposer.generate(config)
 var outputs:Array=[]
 for index in arrangement.parts.size():
  if job!=null and job.is_cancelled():return {"error":"Cancelled"}
  var part:Dictionary=arrangement.parts[index]
  if not role.is_empty() and str(part.role)!=role:continue
  if job!=null:job.update(float(index)/arrangement.parts.size(),"Rendering "+str(part.role))
  if partial and config.get("instruments",{}).has(str(part.role)):
   var override:Variant=config.instruments[str(part.role)]
   part.instrument=override.duplicate(true) if override is Dictionary else KiwiAudioInstruments.default_instrument(str(override))
   var choices:Dictionary=arrangement.settings.get("instruments",{}).duplicate(true);choices[str(part.role)]=part.instrument.duplicate(true);arrangement.settings["instruments"]=choices
  var notes:=KiwiAudioStepControls.render_copy(part.notes,part.get("step_settings",{}),part.instrument)
  var stream:=KiwiAudioInstruments.render_notes(notes,part.instrument,float(arrangement.settings.tempo),rate,job)
  if stream==null:return {"error":"Could not render "+str(part.role)+". Check required samples and the 300-second render limit; no changes were applied."}
  var beats:=float(part.get("pattern_beats",float(arrangement.settings.duration)*float(arrangement.settings.tempo)/60.0))
  for note in part.notes:beats=maxf(beats,float(note.get("start",0))+float(note.get("duration",0)))
  if beats*60/float(arrangement.settings.tempo)>300:return {"error":"The arrangement exceeds the 300-second render limit; no changes were applied."}
  stream=KiwiAudioSourceCache.fit_pattern(stream,beats*60/float(arrangement.settings.tempo))
  if stream==null:return {"error":"The arrangement source could not be fitted; no changes were applied."}
  part["pattern_beats"]=beats;outputs.append({"part":part,"stream":stream})
 if outputs.is_empty():return {"error":"No matching composer parts were found."}
 return {"error":"","arrangement":arrangement,"outputs":outputs,"role":role,"section_id":section_id,"partial":partial}

static func apply_rendered(session:KiwiAudioEditSession,data:Dictionary) -> String:
 if not str(data.get("error","")).is_empty():return str(data.error)
 if not data.get("arrangement") is Dictionary or not data.get("outputs") is Array:return "The composition result is incomplete."
 var arrangement:Dictionary=data.arrangement
 var operations:Array=[]
 # Validate every source and binding before opening the one undo transaction.
 for output in data.outputs:
  if not output is Dictionary or not output.get("stream") is AudioStreamWAV or not output.get("part") is Dictionary:return "A composer source failed; the arrangement was not changed."
  var part:Dictionary=output.part;var targets:Array=[]
  if part.has("_clip_id"):
   var clip:=session.document.clip_for_id(str(part._clip_id));var actor:=session.document.actor_for_clip(str(part._clip_id))
   if clip==null or actor==null or actor.id!=str(part.get("_actor_id","")):return "A generated source changed; regenerate again."
   targets.append(clip.id)
  else:
   for clip in session.document.clips:
    var actor:=session.document.actor_for_clip(clip.id)
    if actor!=null and str(actor.values.get(&"composer_role",""))==str(part.role):targets.append(clip.id)
  for id in targets:
   if not session.can_edit(str(id)):return "A generated clip is locked or frozen; the arrangement was not changed."
  operations.append({"part":part,"stream":output.stream,"targets":targets})
 if operations.is_empty():return "The composition result has no sources."
 data["applied_clip_ids"]=[]
 session.action("Generate editable arrangement",func():
  # Composer timing remains source-relative. Preserve an existing conductor.
  if session.document.clips.is_empty() and session.document.tempo_points.is_empty() and session.document.meter_points.is_empty() and session.document.note_base_tempo==0.0:session.document.tempo=float(arrangement.settings.tempo)
  session.document.key=int(arrangement.settings.key);session.document.scale=str(arrangement.settings.scale)
  session.document.composer_settings=arrangement.settings.duplicate(true);session.document.sections.assign(arrangement.sections);session.document.chords=arrangement.chords.duplicate(true)
  if arrangement.has("last_regeneration"):session.document.composer_settings["last_regeneration"]=arrangement.last_regeneration.duplicate(true)
  for operation in operations:
   var part:Dictionary=operation.part;var stream:AudioStreamWAV=operation.stream;var targets:Array=operation.targets
   if targets.is_empty():
    var track:=session.document.add_track(str(part.role).capitalize(),"instrument");track.instrument=part.instrument.duplicate(true);track.volume_db=-3
    var clip:=session.document.insert_source(stream,str(track.id),0,str(part.role).capitalize());targets.append(clip.id)
   for id in targets:
    var clip:=session.document.clip_for_id(str(id));var actor:=session.document.actor_for_clip(str(id))
    actor.values[&"source_bpm"]=float(arrangement.settings.tempo)
    var signature:Array=arrangement.settings.get("time_signature",[4,4])
    actor.values[&"source_meter"]=[int(signature[0]),int(signature[1])]
    actor.values[&"notes"]=part.notes.duplicate(true);actor.values[&"instrument"]=part.instrument.duplicate(true);actor.values[&"composer_role"]=part.role;actor.values[&"composer_part_id"]=part.id;actor.values[&"pattern_beats"]=float(part.pattern_beats)
    if str(part.role)=="drums" and not part.get("patterns",[]).is_empty():
     var linked:=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").from_part(part,signature)
     actor.values[&"drum_patterns"]=linked.definitions;actor.values[&"drum_instances"]=linked.instances;preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").sync(actor)
    else:
     actor.values.erase(&"drum_patterns");actor.values.erase(&"drum_instances")
    if part.has("step_settings"):actor.values[&"step_settings"]=part.step_settings.duplicate(true)
    elif not bool(data.get("partial",false)):actor.values.erase(&"step_settings")
    KiwiAudioEditSession.apply_note_render(clip,actor,stream,"");data.applied_clip_ids.append(clip.id)
 )
 return ""
