extends RefCounted
## Definitions and instances are authoritative; the notes array is a derived
## compatibility view for the existing piano roll, MIDI and synthesis engines.
static func validate(definitions:Variant,instances:Variant)->String:
	if not definitions is Dictionary or not instances is Array or definitions.size()>256 or instances.size()>512:return "Linked drums support 256 definitions and 512 instances."
	var costs:Dictionary={}
	for id in definitions:
		var pattern:Variant=definitions[id]
		if not id is String or id.length()>128 or not pattern is Dictionary:return "Invalid linked drum definition."
		if not KiwiAudioConductor._number(pattern.get("steps",16),1,256) or not KiwiAudioConductor._number(pattern.get("length",4),.0625,64) or not KiwiAudioConductor._number(pattern.get("swing",0),-.45,.45):return "Invalid linked drum dimensions."
		var lanes:Variant=pattern.get("lanes",[])
		if not lanes is Array or lanes.size()>128:return "Invalid linked drum lanes."
		var cost:=0
		for lane in lanes:
			if not lane is Dictionary or not KiwiAudioConductor._number(lane.get("pitch",36),0,127) or not lane.get("values",[]) is Array or lane.get("values",[]).size()>256:return "Invalid linked drum lane."
			for cell in lane.get("values",[]):
				if cell is Dictionary:
					if not KiwiAudioConductor._number(cell.get("velocity",.8),0,1) or not KiwiAudioConductor._number(cell.get("probability",1),0,1) or not KiwiAudioConductor._number(cell.get("ratchets",1),1,8):return "Invalid linked drum step."
					cost+=int(cell.get("ratchets",1)) if bool(cell.get("enabled",true)) and float(cell.get("velocity",.8))>0 else 0
				elif KiwiAudioConductor._number(cell,0,1):cost+=1 if float(cell)>0 else 0
				else:return "Invalid linked drum step."
		costs[id]=cost
	var total:=0;var seen:Dictionary={}
	for instance in instances:
		if not instance is Dictionary:return "Invalid linked drum instance."
		var id:=str(instance.get("id",""));var pattern_id:=str(instance.get("pattern_id",""))
		if id.is_empty() or id.length()>128 or seen.has(id) or not definitions.has(pattern_id) or not KiwiAudioConductor._number(instance.get("start",0),0,2048) or not KiwiAudioConductor._number(instance.get("length",4),.001,64):return "Invalid linked drum instance reference or timing."
		seen[id]=true;total+=int(costs[pattern_id])
		if total>8192:return "Linked drum expansion exceeds the 8192-note source budget."
	return ""

static func from_part(part:Dictionary,meter:Array)->Dictionary:
	var definitions:Dictionary={};var instances:Array=[];var by_content:Dictionary={}
	var span:=float(meter[0])*4./float(meter[1])
	for source in part.get("patterns",[]):
		var pattern:Dictionary=source.duplicate(true)
		for key in ["id","start","section_id"]:pattern.erase(key)
		var hash:=var_to_str(pattern).sha256_text();var id:=str(by_content.get(hash,""))
		if id.is_empty():id=ActorData.new_id();definitions[id]=pattern;by_content[hash]=id
		instances.append({"id":str(source.get("id",ActorData.new_id())),"pattern_id":id,"start":float(source.get("start",0)),"length":minf(span,maxf(.001,float(part.pattern_beats)-float(source.get("start",0)))),"section_id":str(source.get("section_id","")),"seed":int(str(source.get("id","")).hash())})
	return {"definitions":definitions,"instances":instances}

static func notes(actor:ActorData)->Array:
	if not actor.values.has(&"drum_instances"):return actor.values.get(&"notes",[]).duplicate(true)
	var result:Array=[];var definitions:Dictionary=actor.values.get(&"drum_patterns",{})
	for instance in actor.values.get(&"drum_instances",[]):
		var id:=str(instance.get("pattern_id",""))
		if not definitions.has(id):continue
		var pattern:Dictionary=definitions[id]
		var span:=float(instance.get("length",4));var length:=maxf(.0625,float(pattern.get("length",4)))
		for source in KiwiAudioComposer.pattern_notes(pattern,1,int(instance.get("seed",1))):
			var note:Dictionary=source.duplicate(true);var local:=float(note.start)/length*span
			note.start=float(instance.start)+local;note.duration=minf(float(note.duration),span-local);note.id=str(instance.id)+"_"+str(source.id);note.section_id=str(instance.get("section_id",""));result.append(note)
	result.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.start)<float(b.start))
	return result

static func sync(actor:ActorData)->void:
	if actor.values.has(&"drum_instances"):actor.values[&"notes"]=notes(actor)

static func detach(actor:ActorData)->void:
	sync(actor);actor.values.erase(&"drum_patterns");actor.values.erase(&"drum_instances")
