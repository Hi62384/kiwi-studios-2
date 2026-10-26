extends SceneTree
func _initialize()->void:
 var errors:=0;var samples:=PackedVector2Array();samples.resize(4800);var stream:=KiwiAudioSourceCache.to_wav(samples,48000)
 var session:=KiwiAudioEditSession.new();session.open(KiwiAudioDocument.from_source(stream));session.history_limit=3
 for i in 7:session.action("change",func():session.document.title=str(i))
 print("COUNT ",session.history.get_history_count()," metadata sources ",session._history_footprints.size())
 if session.history.get_history_count()!=3:errors+=1
 session.history_byte_budget=50000
 for i in 7:session.action("source",func():session.document.actors[0].values[&"audio"]=KiwiAudioSourceCache.to_wav(samples,48000))
 print("BUDGET_COUNT ",session.history.get_history_count()," pruned ",session.history_pruned_actions)
 if session.history.get_history_count()!=1 or session.history_pruned_actions<1:errors+=1
 var latest:Variant=session.document.actors[0].values[&"audio"];session.undo()
 if session.document.actors[0].values[&"audio"]==latest:errors+=1
 session.redo()
 if session.document.actors[0].values[&"audio"]!=latest:errors+=1
 session.undo();session.action("branched",func():session.document.title="branch")
 if session.history.has_redo():errors+=1
 print("UNDO_BUDGET failures=",errors);quit(errors)
