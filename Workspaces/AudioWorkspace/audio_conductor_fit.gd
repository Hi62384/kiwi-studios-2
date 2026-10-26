extends RefCounted
## Explicit one-shot timing policy, not a hidden response to conductor edits.
## Starts stay in seconds; source notes stay in quarter-note beats; lengths
## follow the current step-tempo conductor. Local automation stays in seconds.
static func prepare(session:KiwiAudioEditSession,ids:Array)->Dictionary:
	if ids.is_empty() or session._before!=null:return {"error":"Select full note clips and finish the current adjustment."}
	var conductor:=session.document.conductor();var operations:Array=[]
	if not conductor.error.is_empty():return {"error":conductor.error}
	for id in ids:
		var clip:=session.document.clip_for_id(str(id));var actor:=session.document.actor_for_clip(str(id))
		if clip==null or actor==null or not session.can_edit(str(id)) or not KiwiAudioEditSession.is_note_source(actor):return {"error":"Every selected clip must be an unlocked editable note source."}
		var length:=float(actor.values.get(&"source_duration",0));var beats:=float(actor.values.get(&"pattern_beats",0))
		if clip.source_offset>.00001 or not is_equal_approx(clip.playback_speed,1.) or bool(actor.values.get(&"loop",false)) or bool(actor.values.get(&"reverse",false)) or absf(clip.duration-length)>.01:return {"error":"Conductor fitting requires full, forward, unlooped note clips at normal speed. Keep trimmed/stretched sources unchanged or duplicate a full source first."}
		if beats<=0:return {"error":"A source has no explicit pattern length."}
		var origin:=conductor.seconds_to_beat(clip.start_time);var bpm:=conductor.tempo_at(clip.start_time);var tempos:Array=[{"beat":0.,"bpm":bpm}]
		for point in session.document.tempo_points:
			var local:=float(point.beat)-origin
			if local>.000001 and local<beats:tempos.append({"beat":local,"bpm":float(point.bpm)})
		var timing:=KiwiAudioTempoMap.new(tempos,bpm);var duration:=timing.beat_to_seconds(beats)
		if not timing.error.is_empty() or duration>300:return {"error":"The fitted source would exceed the five-minute editable-note limit."}
		operations.append({"clip":clip,"actor":actor,"tempos":tempos,"bpm":bpm,"duration":duration})
	return {"error":"","operations":operations}

static func apply(session:KiwiAudioEditSession,ids:Array)->String:
	var prepared:=prepare(session,ids)
	if not str(prepared.get("error","")).is_empty():return prepared.error
	session.action("Fit notes to conductor snapshot",func():
		for operation in prepared.operations:
			operation.actor.values[&"source_bpm"]=operation.bpm;operation.actor.values[&"midi_tempos"]=operation.tempos;operation.actor.values[&"midi_tempo_scale"]=1.;operation.actor.values[&"notes_dirty"]=true
			operation.actor.values.erase(&"notes_source_scale");operation.clip.duration=operation.duration)
	return ""
