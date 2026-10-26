extends RefCounted
## Reviewed, all-or-nothing source edits. Crossfades overlap real source handles
## inside removed quiet regions; they are not merely adjacent anti-click fades.
const MAX_CLIPS := 64

static func analyze(document:KiwiAudioDocument,ids:Array,threshold:float,minimum:float,job:RefCounted=null)->Dictionary:
	if ids.is_empty() or ids.size()>MAX_CLIPS:return {"error":"Select between 1 and 64 dialogue clips."}
	var entries:Array=[]
	for id in ids:
		if job!=null and job.is_cancelled():return {"error":"Cancelled."}
		var clip:=document.clip_for_id(str(id));var actor:=document.actor_for_clip(str(id))
		if clip==null or actor==null:return {"error":"A selected clip is unavailable."}
		var reason:=KiwiAudioRegionEdit.unsupported_reason(clip,actor,"cut")
		if not reason.is_empty():return {"error":actor.display_name+": "+reason}
		var identity:=KiwiAudioEditSession.silence_source_identity(actor)
		var data:=KiwiAudioAnalysis.analyze_source(actor.values.get(&"audio"),threshold,minimum,job,clip.source_offset,clip.duration*clip.playback_speed)
		if not str(data.get("error","")).is_empty():return data
		if identity.is_empty() or identity!=KiwiAudioEditSession.silence_source_identity(actor):return {"error":"A dialogue source changed during analysis."}
		entries.append({"id":str(id),"label":actor.display_name,"data":data,"identity":identity})
		if job!=null:job.update(float(entries.size())/ids.size(),"Reviewing dialogue sources")
	return {"error":"","entries":entries}

static func prepare(session:KiwiAudioEditSession,entries:Array,keep:float)->Dictionary:
	var plans:Array=[]
	for entry in entries:
		var result:=session.create_silence_plan(entry.id,entry.data.get("silences",[]),float(entry.data.get("duration",0)),keep,entry.identity)
		if not str(result.get("error","")).is_empty():return result
		plans.append(result.plan)
	return {"error":"","plans":plans}

static func review(session:KiwiAudioEditSession,plans:Array,choices:Array,scope:String,overlap:float)->Dictionary:
	if plans.size()!=choices.size() or plans.is_empty() or plans.size()>MAX_CLIPS:return {"error":"Invalid dialogue review queue."}
	if not is_finite(overlap) or overlap<0 or overlap>.1:return {"error":"Choose a crossfade between 0 and 100 ms."}
	var operations:Array=[];var seen:Dictionary={};var total:=0.
	for index in plans.size():
		var plan:KiwiAudioEditSession.SilencePlan=plans[index]
		if plan==null or seen.has(plan.clip_id()):return {"error":"Duplicate or missing dialogue plan."}
		seen[plan.clip_id()]=true
		var preview:=session.preview_silence_plan(plan,choices[index],scope)
		if not str(preview.get("error","")).is_empty():return preview
		var clip:=session.document.clip_for_id(plan.clip_id());var actor:=session.document.actor_for_clip(plan.clip_id())
		if overlap>0 and str(actor.values.get(&"fade_curve","linear")) not in ["linear",""] and (float(actor.values.get(&"fade_in",0))>0 or float(actor.values.get(&"fade_out",0))>0):return {"error":"Render existing nonlinear outer fades first, or set overlap to zero. Their curve will not be silently changed."}
		var parts:Array=[];var cursor:=clip.start_time;var joins:Array=[]
		for i in maxi(0,preview.ranges.size()-1):
			var left:Dictionary=preview.ranges[i];var right:Dictionary=preview.ranges[i+1]
			joins.append(minf(overlap*.5,minf((right.start-left.end)/clip.playback_speed*.5,minf(left.end-left.start,right.end-right.start)/clip.playback_speed*.25)))
		for i in preview.ranges.size():
			var interval:Dictionary=preview.ranges[i]
			var head:=float(joins[i-1]) if i>0 else 0.;var tail:=float(joins[i]) if i<joins.size() else 0.
			var length:float=(interval.end-interval.start)/clip.playback_speed
			var part:=KiwiAudioRegionEdit._piece(actor,clip,cursor-head,interval.start-head*clip.playback_speed,length+head+tail)
			if i==0:part.actor.id=actor.id;part.clip.id=clip.id;part.clip.actor_id=actor.id
			part.actor.values[&"fade_in"]=head*2 if head>0 else (float(actor.values.get(&"fade_in",0)) if i==0 else minf(.003,length*.1))
			part.actor.values[&"fade_out"]=tail*2 if tail>0 else (float(actor.values.get(&"fade_out",0)) if i==preview.ranges.size()-1 else minf(.005,length*.1))
			# Linear complementary fades preserve level for correlated quiet handles.
			if head>0 or tail>0:part.actor.values[&"fade_curve"]="linear"
			parts.append(part);cursor+=length
		operations.append({"id":clip.id,"track":str(actor.values.get(&"track_id","")),"end":clip.start_time+clip.duration,"removed":float(preview.removed),"parts":parts,"moved":preview.moved_ids})
		total+=float(preview.removed)
	return {"error":"","operations":operations,"removed":total,"scope":scope}

static func apply(session:KiwiAudioEditSession,plans:Array,choices:Array,scope:String,overlap:float)->Dictionary:
	var result:=review(session,plans,choices,scope,overlap)
	if not str(result.get("error","")).is_empty() or float(result.get("removed",0))<=.000001:return result
	# All plans are validated against the same revision before ANY mutation.
	var shifts:Dictionary={}
	if scope=="track_following":
		for operation in result.operations:
			for id in operation.moved:shifts[id]=float(shifts.get(id,0))+float(operation.removed)
	for plan in plans:plan.cancel()
	session.action("Reviewed dialogue queue",func():
		for operation in result.operations:
			if float(operation.removed)<=.000001:continue
			var clip:=session.document.clip_for_id(operation.id);var index:=session.document.clips.find(clip)
			session.document.clips.remove_at(index);session.document.actors.remove_at(index)
			for i in operation.parts.size():
				var part:Dictionary=operation.parts[i];part.clip.start_time-=float(shifts.get(operation.id,0))
				session.document.clips.insert(index+i,part.clip);session.document.actors.insert(index+i,part.actor)
			shifts.erase(operation.id)
		for id in shifts:
			var clip:=session.document.clip_for_id(id)
			if clip!=null:clip.start_time-=float(shifts[id])
		session.selected_ids.clear()
		for operation in result.operations:
			for part in operation.parts:
				if session.document.clip_for_id(part.clip.id)!=null:session.selected_ids.append(part.clip.id))
	session.selection_changed.emit()
	return {"error":"","removed":result.removed}
