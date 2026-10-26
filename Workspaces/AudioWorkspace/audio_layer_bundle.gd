extends RefCounted
## Native document subset: shared immutable media, absolute clip placement,
## independent IDs on insertion. No master/conductor replacement.
static func selected(document:KiwiAudioDocument,ids:Array)->Dictionary:
	if ids.is_empty():return {"error":"Select clips to save as a layer bundle."}
	var copy:=document.snapshot();var first:=INF
	var required:Dictionary={}
	for id in ids:
		var clip:=copy.clip_for_id(str(id))
		if clip==null:return {"error":"A selected clip no longer exists."}
		first=minf(first,clip.start_time)
		required[str(copy.track_for_clip(str(id)).get("id",""))]=true
	var pending:=required.keys()
	while not pending.is_empty():
		var track:=copy.track_for_id(str(pending.pop_back()));var targets:Array=[str(track.get("output","")),str(track.get("group",""))]
		for send in track.get("sends",[]):targets.append(str(send.get("target","")))
		for target in targets:
			if not str(target).is_empty() and not required.has(target):required[target]=true;pending.append(target)
	for i in range(copy.clips.size()-1,-1,-1):
		if not ids.has(copy.clips[i].id):copy.clips.remove_at(i);copy.actors.remove_at(i)
	for clip in copy.clips:
		clip.start_time-=first
		var actor:=copy.actor_for_clip(clip.id)
		if KiwiAudioEditSession.is_note_source(actor):
			actor.values[&"source_bpm"]=KiwiAudioEditSession.note_source_tempo(actor,document)
			var meter:=KiwiAudioEditSession.note_source_meter(actor,document);actor.values[&"source_meter"]=[meter.x,meter.y]
	# Keep route dependencies (including sends), but never unrelated automation
	# bindings, take selectors, frozen state or scene associations.
	for track in copy.tracks:
		for key in ["frozen_track","frozen_source","freeze_members","freeze_previous_mute","freeze_previous_locked","freeze_previous_solo"]:track.erase(key)
		track.locked=false
		var problem:=_rebase_owner(track,first)
		if not problem.is_empty() and required.has(str(track.id)):return {"error":problem}
		for effect in track.get("effects",[]):
			problem=_rebase_owner(effect,first)
			if not problem.is_empty() and required.has(str(track.id)):return {"error":problem}
	copy.tracks=copy.tracks.filter(func(track:Dictionary):return required.has(str(track.id)) and not KiwiAudioAutomationLane.is_lane(track))
	copy.takes.clear();copy.scene_binding={};copy.workspace_state={};copy.portable_media={};copy.output_path="";copy.resource_path=""
	copy.sections.clear();copy.chords.clear();copy.composer_settings={};copy.tempo_points.clear();copy.meter_points.clear();copy.presets={}
	return {"error":"","document":copy}

static func insert(session:KiwiAudioEditSession,bundle:KiwiAudioDocument,at:float)->String:
	if bundle==null or not is_finite(at) or at<0 or session._before!=null:return "Finish the current adjustment and choose a valid bundle."
	var errors:=bundle.validate()
	if not errors.is_empty():return "\n".join(errors)
	if bundle.clips.size()>512 or bundle.tracks.size()>128:return "A layer bundle supports at most 512 clips and 128 tracks."
	var copy:=bundle.snapshot();var ids:Dictionary={}
	for track in copy.tracks:ids[str(track.id)]=ActorData.new_id()
	for actor in copy.actors:ids[actor.id]=ActorData.new_id()
	for clip in copy.clips:ids[clip.id]=ActorData.new_id()
	for track in copy.tracks:
		track.id=ids[str(track.id)];track.output=ids.get(str(track.get("output","")),"");track.group=ids.get(str(track.get("group","")),"")
		for send in track.get("sends",[]):send.target=ids.get(str(send.get("target","")),"")
		for key in ["frozen_track","frozen_source","freeze_members"]:track.erase(key)
		track.locked=false
		for parameter in track.get("automation",{}):
			for point in track.automation[parameter]:point.time=float(point.time)+at
		for effect in track.get("effects",[]):
			for parameter in effect.get("automation",{}):
				for point in effect.automation[parameter]:point.time=float(point.time)+at
	for i in copy.clips.size():
		var clip:=copy.clips[i];var actor:=copy.actors[i]
		if KiwiAudioEditSession.is_note_source(actor):
			actor.values[&"source_bpm"]=KiwiAudioEditSession.note_source_tempo(actor,bundle)
			var meter:=KiwiAudioEditSession.note_source_meter(actor,bundle);actor.values[&"source_meter"]=[meter.x,meter.y]
		clip.id=ids[clip.id];clip.actor_id=ids[clip.actor_id];actor.id=ids[actor.id];clip.start_time+=at;actor.values[&"track_id"]=ids.get(str(actor.values.get(&"track_id","")),"")
		actor.parent_id=ids.get(actor.parent_id,"")
	var candidate:=session.document.snapshot();candidate.tracks.append_array(copy.tracks);candidate.actors.append_array(copy.actors);candidate.clips.append_array(copy.clips)
	errors=candidate.validate()
	if not errors.is_empty():return "Bundle insertion rejected: "+"\n".join(errors)
	session.action("Insert layer bundle",func():
		session.document.tracks.append_array(copy.tracks);session.document.actors.append_array(copy.actors);session.document.clips.append_array(copy.clips)
		session.selected_ids.clear()
		for clip in copy.clips:session.selected_ids.append(clip.id)
		if not copy.tracks.is_empty():session.selected_track=str(copy.tracks[0].id))
	session.selection_changed.emit()
	return ""

static func _rebase_owner(owner:Dictionary,origin:float)->String:
	for parameter in owner.get("automation",{}):
		var points:Array=owner.automation[parameter]
		if points.is_empty():continue
		var curve:="linear"
		for i in points.size():
			if float(points[i].time)<=origin:
				curve=str(points[i].get("curve","linear"))
				if curve=="smooth" and i+1<points.size() and float(points[i].time)<origin and float(points[i+1].time)>origin:return "A smooth bus/effect curve crosses the bundle origin. Split/bake it first; its easing will not be silently changed."
		var fallback:=float(owner.get("parameters",owner).get(parameter,0))
		var rebased:Array=[{"time":0.,"value":KiwiAudioEditSession.automation_value(points,origin,fallback),"curve":curve}]
		for point in points:
			if float(point.time)>origin:
				var copy:Dictionary=point.duplicate(true);copy.time=float(point.time)-origin;rebased.append(copy)
		owner.automation[parameter]=rebased
	return ""
