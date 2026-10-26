extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 var samples:=PackedVector2Array();samples.resize(4800)
 for i in samples.size():samples[i]=Vector2(0.1*sin(TAU*400*i/48000.0),0.05*cos(TAU*900*i/48000.0))
 var source:=KiwiAudioSourceCache.to_wav(samples,48000)
 var original:=KiwiAudioDocument.from_source(source,"Document regression")
 check(original.validate().is_empty(),"valid source document")
 var bad:=original.snapshot();bad.clips[0]=null
 check(not bad.validate().is_empty(),"null clip rejected without dereference")
 bad=original.snapshot();bad.actors[0]=null
 check(not bad.validate().is_empty(),"null actor rejected without dereference")
 for property in ["sends","effects","automation"]:
  bad=original.snapshot();bad.tracks[0][property]="corrupt"
  check(not bad.validate().is_empty(),"malformed track "+property)
 bad=original.snapshot();bad.tracks[0].sends=[null,4,"bad"]
 check(not bad.validate().is_empty(),"malformed individual sends")
 bad=original.snapshot();bad.tracks[0].effects=[null,4]
 check(not bad.validate().is_empty(),"malformed individual effects")
 bad=original.snapshot();bad.tracks[0].automation={"pan":[null,4]}
 check(not bad.validate().is_empty(),"malformed automation points")
 bad=original.snapshot();bad.tracks[0].automation={"pan":[{"time":NAN,"value":INF}]}
 check(not bad.validate().is_empty(),"non-finite automation points")
 for meter in [Vector2i(0,4),Vector2i(4,0),Vector2i(3,7)]:
  bad=original.snapshot();bad.time_signature=meter
  check(not bad.validate().is_empty(),"invalid meter "+str(meter))
 bad=original.snapshot();bad.tempo=NAN
 check(not bad.validate().is_empty(),"non-finite tempo")
 bad=original.snapshot();bad.clips[0].source_offset=-1
 check(not bad.validate().is_empty(),"negative source offset")
 bad=original.snapshot();bad.actors[0].values[&"notes"]=[null,"bad"]
 check(not bad.validate().is_empty(),"malformed notes")
 bad=original.snapshot();bad.actors[0].values[&"notes"]=[{"pitch":-1,"duration":-1,"velocity":INF}]
 check(not bad.validate().is_empty(),"invalid note properties")
 bad=original.snapshot();bad.actors[0].values[&"audio"]={"corrupt":true}
 check(not bad.validate().is_empty(),"invalid source reference")
 for definition in KiwiAudioEffects.catalog():
  bad=original.snapshot();bad.tracks[0].effects=[KiwiAudioEffects.create(definition.id)]
  check(bad.validate().is_empty(),"valid default effect "+str(definition.id))
 var deep:=KiwiAudioDocument.new()
 for i in 2000:deep.add_track(str(i))
 for i in 1999:deep.tracks[i].output=deep.tracks[i+1].id
 check(deep.validate().is_empty(),"2000-track routing validation is iterative")
 deep.tracks[-1].output=deep.tracks[0].id
 check(not deep.validate().is_empty(),"deep routing feedback rejected")
 var copy:=original.snapshot();copy.actors[0].values[&"notes"]=[{"pitch":60}];copy.tracks[0].volume_db=-20
 check(original.actors[0].values[&"notes"].is_empty() and original.tracks[0].volume_db==0,"snapshot metadata independently editable")
 check(copy.actors[0].values[&"audio"]==source,"snapshot shares immutable source identity")
 var session:=KiwiAudioEditSession.new();session.open(original)
 session.begin("Nested transaction")
 session.insert_source(source,1,session.selected_track,"second")
 check(session.insert_source(null,2,session.selected_track)==null,"invalid source import rejected")
 check(session._before!=null,"failed nested import preserves outer transaction")
 session.commit();check(session.document.clips.size()==2,"nested edit committed")
 session.undo();check(session.document.clips.size()==1 and session.document.actors[0].values[&"audio"]==source,"single undo restores nested edit and source identity")
 session.redo();check(session.document.clips.size()==2,"redo restores nested edit")
 var points:Array=[{"time":0.0,"value":-20.0,"curve":"hold"},{"time":1.0,"value":0.0,"curve":"hold"}]
 check(KiwiAudioEditSession.automation_value(points,0.999,1)==-20,"hold left interval")
 check(KiwiAudioEditSession.automation_value(points,1,1)==0,"hold switches exactly at boundary")
 var fitted:=KiwiAudioSourceCache.fit_pattern(source,0.25)
 check(fitted.data.size()==12000*4,"pattern fitting is sample exact")
 check(KiwiAudioSourceCache.fit_pattern(source,INF)==null,"infinite pattern length rejected")
 var token:=KiwiAudioJobs.Work.new();token.cancel()
 check(KiwiAudioSourceCache.build_envelope(source,token).get("cancelled",false),"waveform job cancellation")
 check(KiwiAudioInstruments.render_notes([{"pitch":60,"start":0,"duration":100}],{"id":"poly"},120,44100,token)==null,"instrument job cancellation")
 print("AUDIO_DOCUMENT checks=",checks," failures=",failures)
 quit(failures)
