extends RefCounted
## Reuses editable owner curves; no second modulation/rendering engine.
static func apply(session:KiwiAudioEditSession,rows:Array)->String:
	if session._before!=null or rows.is_empty() or rows.size()>32:return "Finish the current adjustment; a matrix supports 1–32 targets."
	var operations:Array=[];var seen:Dictionary={}
	for row in rows:
		var info:=KiwiAudioAutomationLane.resolve(session.document,row.get("target",{}));var key:=KiwiAudioAutomationLane.key(row.get("target",{}))
		if info.is_empty() or bool(info.locked) or seen.has(key):return "Every modulation target must be available, unlocked and unique."
		seen[key]=true
		var seconds:=minf(600.,float(info.duration))
		if float(info.duration)>600:return "Split sources or select a shorter composition before generating modulation (10-minute curve limit)."
		var values:=KiwiAudioAutomationCanvas.modulation_points(row,seconds,session.document.tempo,float(info.minimum),float(info.maximum))
		operations.append({"info":info,"values":values})
	session.action("Apply modulation matrix",func():
		for operation in operations:
			var curves:Dictionary=operation.info.owner.get("automation",{}).duplicate(true);curves[str(operation.info.parameter)]=operation.values;operation.info.owner.automation=curves
		session.document.presets["modulation_matrix"]=rows.duplicate(true))
	return ""
