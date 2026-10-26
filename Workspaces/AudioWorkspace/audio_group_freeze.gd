extends RefCounted
## Closed routed subgraphs only: external dry/send branches must never vanish
## or be doubled when a group is replaced by one rendered source.
static func members(document:KiwiAudioDocument,root:String)->Dictionary:
	var target:=document.track_for_id(root)
	if target.is_empty():return {"error":"Choose an existing track or group."}
	var tracks:Array=[];var ids:Dictionary={}
	for track in document.tracks:
		if str(track.id)==root or KiwiAudioRenderer.route_reaches(document,str(track.id),root):
			if bool(track.get("locked",false)) or track.has("frozen_track") or track.has("frozen_source"):return {"error":"Unlock/unfreeze every incoming track before freezing this routed group."}
			if KiwiAudioAutomationLane.is_lane(track):continue
			tracks.append(track);ids[str(track.id)]=true
	for track in tracks:
		if str(track.id)==root:continue
		if not ids.has(str(track.get("output",""))):return {"error":"An incoming track also has a dry output outside this group. Route it entirely inside the group, or bounce without replacing the sources."}
		for send in track.get("sends",[]):
			if not ids.has(str(send.get("target",""))):return {"error":"An incoming track sends audio outside the group. Freeze would lose that branch; use Bounce or reroute it first."}
	return {"error":"","tracks":tracks}

static func apply(session:KiwiAudioEditSession,root:String,stream:AudioStream)->String:
	var prepared:=members(session.document,root)
	if not str(prepared.get("error","")).is_empty():return prepared.error
	if stream==null:return "No frozen audio is available."
	var original:=session.document.track_for_id(root)
	var state:Array=[];var any_solo:=false
	for track in prepared.tracks:
		state.append({"id":str(track.id),"mute":bool(track.get("mute",false)),"solo":bool(track.get("solo",false)),"locked":bool(track.get("locked",false))});any_solo=any_solo or bool(track.get("solo",false))
	session.action("Freeze routed track/group",func():
		var frozen:=session.document.add_track("Frozen "+str(original.get("name","Track")),"audio")
		frozen.output=original.get("output","");frozen.sends=original.get("sends",[]).duplicate(true);frozen.frozen_source=root;frozen.locked=true;frozen.mute=bool(original.get("mute",false));frozen.solo=any_solo
		var clip:=session.document.insert_source(stream,str(frozen.id),0,"Frozen routed audio")
		if clip!=null:
			var actor:=session.document.actor_for_clip(clip.id);actor.values[&"fade_in"]=0.;actor.values[&"fade_out"]=0.
		original.freeze_members=state;original.frozen_track=str(frozen.id)
		for track in prepared.tracks:track.mute=true;track.solo=false;track.locked=true)
	return ""

static func restore_members(document:KiwiAudioDocument,original:Dictionary)->void:
	for state in original.get("freeze_members",[]):
		var track:=document.track_for_id(str(state.id))
		if not track.is_empty():track.mute=state.mute;track.solo=state.solo;track.locked=state.locked
	original.erase("freeze_members")
