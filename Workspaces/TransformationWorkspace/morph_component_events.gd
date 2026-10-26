class_name KiwiMorphComponentEvents
extends RefCounted
## Explicit visibility/region transfers. Evaluation is a pure function of time;
## no simulation, mutation of source states, or implicit overlap-based merging.
static func evaluate(document: KiwiTransformationImage2D,id: String,time: float) -> Dictionary:
	var visible := true; var masks: Array[Texture2D]=[]
	for event in document.component_events:
		if event.target==id and time<float(event.time): visible=false
		if time>=float(event.time) and event.sources.has(id):
			if event.kind=="Merge": visible=false
			elif masks.size()<4: masks.append(event.mask)
	return {"visible":visible,"masks":masks}
static func detach(session: KiwiTransformationSession,mask: Image) -> String:
	var item := session.primary(); var state := session.active_state()
	if item==null or item.locked or mask==null: return "Select an unlocked component and some pixels first."
	var time_error := check_time(session,PackedStringArray([item.id]),session.playhead)
	if not time_error.is_empty(): return time_error
	var sample := session.sampled(item,session.playhead)
	if sample.a.id!=state.id or (sample.a!=sample.b and sample.t>.00001): return "Detach at an exact state key (or the default state), then choose Edit state."
	var active: Array[Image]=[]
	for event in session.document.component_events:
		if event.kind=="Split" and event.sources.has(item.id):
			var pixels: Image=event.mask.get_image()
			if pixels==null: return "Existing detach mask is unavailable."
			active.append(pixels.duplicate())
	if active.size()>=4: return "A component supports four disjoint region detaches. Split another component for more."
	var image := state.artwork.texture.get_image().duplicate() as Image; image.convert(Image.FORMAT_RGBA8)
	if image.get_size()!=mask.get_size(): return "Selection mask does not match this state artwork."
	for old in active:
		if old.get_size()!=mask.get_size(): old.resize(mask.get_width(),mask.get_height(),Image.INTERPOLATE_NEAREST)
	for y in image.get_height():
		for x in image.get_width():
			var amount := mask.get_pixel(x,y).a
			for old in active:
				if amount>.01 and old.get_pixel(x,y).a>.01: return "Detach regions must not overlap an existing region transfer."
			var color := image.get_pixel(x,y); color.a*=amount; image.set_pixel(x,y,color)
	if not image.get_used_rect().has_area(): return "The selection contains no visible artwork."
	var child := KiwiTransformationImage2D.make_component(Vector2i(item.base_size),item.title+" detached")
	child.base_size=item.base_size; child.states[0]=state.copy_state(true); child.default_state_id=child.states[0].id; child.states[0].artwork.id=child.id; child.states[0].artwork.texture=ImageTexture.create_from_image(image); child.states[0].artwork.paint_base=child.states[0].artwork.texture
	var born := KiwiTransformationKey.new(); born.id=ActorData.new_id(); born.time=session.playhead; born.state_id=child.default_state_id; child.keys.append(born)
	session.action("Detach region at playhead",func():
		session.document.components.insert(session.document.components.find(item)+1,child)
		session.document.component_events.append({"id":ActorData.new_id(),"kind":"Split","time":session.playhead,"sources":PackedStringArray([item.id]),"target":child.id,"mask":ImageTexture.create_from_image(mask)})
		session.selected.assign([child.id]))
	return ""
static func merge(session: KiwiTransformationSession,ids: PackedStringArray,image: Image,at: float) -> String:
	if ids.size()<2 or image==null or not image.get_used_rect().has_area(): return "Choose at least two visible components."
	if image.get_size()!=session.document.canvas_size: return "Merge image must match the full canvas."
	var time_error := check_time(session,ids,at)
	if not time_error.is_empty(): return time_error
	var highest := -1; var lowest := session.document.components.size()
	for id in ids:
		var item := session.document.component(id)
		if item==null or item.locked: return "Unlock the selected components before merging."
		var index := session.document.components.find(item); highest=maxi(highest,index); lowest=mini(lowest,index)
	if highest-lowest+1!=ids.size(): return "Select adjacent components so merging cannot change unrelated compositing order."
	var target := KiwiTransformationImage2D.make_component(session.document.canvas_size,"Merged component"); target.states[0].artwork.texture=ImageTexture.create_from_image(image); target.states[0].artwork.paint_base=target.states[0].artwork.texture
	var born := KiwiTransformationKey.new(); born.id=ActorData.new_id(); born.time=at; born.state_id=target.default_state_id; target.keys.append(born)
	session.action("Merge components at playhead",func():
		session.document.components.insert(highest+1,target)
		session.document.component_events.append({"id":ActorData.new_id(),"kind":"Merge","time":at,"sources":ids,"target":target.id})
		session.selected.assign([target.id]))
	return ""
static func check_time(session: KiwiTransformationSession,ids: PackedStringArray,at: float) -> String:
	if not is_finite(at) or at<0 or at>session.document.duration: return "Transfer time is outside the animation."
	var seen := {}
	for id in ids:
		if seen.has(id): return "A transfer cannot contain duplicate sources."
		seen[id]=true
		for event in session.document.component_events:
			if event.target==id and float(event.time)>at: return "A transfer cannot occur before its source component is born."
	return ""
