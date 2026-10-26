class_name KiwiTransformationImage2D
extends Resource
@export var version := 1
@export var canvas_size := Vector2i(1280,720)
@export var duration := 3.
@export var components: Array[KiwiTransformationComponent]=[]
@export var workspace_state: Dictionary={}
@export var metadata: Dictionary={}
@export var preview_png := PackedByteArray()
@export var component_events: Array[Dictionary]=[]
func component(id: String) -> KiwiTransformationComponent:
	for item in components:
		if item.id==id: return item
	return null
func snapshot() -> KiwiTransformationImage2D:
	var result := KiwiTransformationImage2D.new(); result.version=version; result.canvas_size=canvas_size; result.duration=duration; result.workspace_state=workspace_state.duplicate(true); result.metadata=metadata.duplicate(true); result.preview_png=preview_png
	for item in components: result.components.append(item.copy_component())
	result.component_events.assign(component_events.duplicate(true))
	return result
static func blank(size: Vector2i=Vector2i(1280,720)) -> KiwiTransformationImage2D:
	var result := KiwiTransformationImage2D.new(); result.canvas_size=size
	result.components.append(make_component(size,"Drawing")); return result
static func make_component(size: Vector2i, title: String="Component") -> KiwiTransformationComponent:
	var item := KiwiTransformationComponent.new(); item.id=ActorData.new_id(); item.title=title; item.base_size=Vector2(size)
	var state := KiwiTransformationState.new(); state.id=ActorData.new_id(); state.title="Default"; state.artwork=KiwiImageLayer.create("basic",size); state.artwork.id=item.id; state.artwork.label=title
	item.states.append(state); item.default_state_id=state.id; return item
func validate() -> PackedStringArray:
	var errors := PackedStringArray(); var ids := {}
	if version!=1: errors.append("Unsupported Transformation Image version.")
	if canvas_size.x<1 or canvas_size.y<1 or canvas_size.x>8192 or canvas_size.y>8192 or canvas_size.x*canvas_size.y>16777216: errors.append("Canvas must be 1–8192 pixels per side and at most 16 megapixels.")
	if not is_finite(duration) or duration<=0 or duration>86400: errors.append("Invalid animation duration.")
	for item in components:
		if item==null: errors.append("Missing component."); continue
		if item.id.is_empty() or ids.has(item.id): errors.append("Missing or duplicate component ID.")
		ids[item.id]=true; var states := {}; var keys := {}; var times := {}
		if item.states.is_empty(): errors.append("A component needs at least one state.")
		if not item.base_size.is_finite() or item.base_size.x<=0 or item.base_size.y<=0: errors.append("Invalid component base dimensions.")
		for state in item.states:
			if state==null: errors.append("Missing state."); continue
			if state.id.is_empty() or states.has(state.id): errors.append("Missing or duplicate state ID.")
			states[state.id]=true
			if state.artwork==null or state.artwork.texture==null: errors.append("Missing state artwork."); continue
			var art := state.artwork
			if art.kind!="basic" or art.texture.get_width()<1 or art.texture.get_height()<1 or art.texture.get_width()>8192 or art.texture.get_height()>8192 or art.texture.get_width()*art.texture.get_height()>16777216: errors.append("State artwork must be a valid raster drawing of at most 8192 pixels per side / 16 megapixels.")
			if art.opacity<0 or art.opacity>1 or state.pivot.x<0 or state.pivot.x>1 or state.pivot.y<0 or state.pivot.y>1: errors.append("State opacity and pivot must be within 0–1.")
			if art.id!=item.id or not art.parent_id.is_empty(): errors.append("Invalid component artwork identity.")
			if not art.position.is_finite() or not art.dimensions.is_finite() or art.dimensions.x<=0 or art.dimensions.y<=0 or not is_finite(art.rotation) or not is_finite(art.opacity) or not state.pivot.is_finite(): errors.append("Invalid state transform.")
			for axis in ["basis_x","basis_y"]:
				if art.properties.has(axis) and (not art.properties[axis] is Vector2 or not art.properties[axis].is_finite()): errors.append("Invalid state affine transform.")
		if not states.has(item.default_state_id): errors.append("Missing default state.")
		for key in item.keys:
			if key==null: errors.append("Missing keyframe."); continue
			if key.id.is_empty() or keys.has(key.id): errors.append("Missing or duplicate keyframe ID.")
			keys[key.id]=true
			if not states.has(key.state_id): errors.append("Keyframe references a missing state.")
			if not is_finite(key.time) or key.time<0 or key.time>duration or times.has(snappedf(key.time,.000001)): errors.append("Invalid or overlapping keyframe times.")
			times[snappedf(key.time,.000001)]=true
			if key.mode not in KiwiTransformationKey.MODES+KiwiTransformationKey.LEGACY_MODES or key.points_a.size()!=key.points_b.size() or key.points_a.size()>24 or key.reveal_path.size()>64: errors.append("Invalid transition controls.")
			if key.alignment not in ["Bounds","Local"] or key.appearance not in ["Feature reveal","Aligned blend"] or key.quality not in ["Fast","High"] or key.reveal_mode not in ["Point","Path","Directional","Shape expansion"]: errors.append("Invalid morph settings.")
			if not is_finite(key.preservation) or key.preservation<0 or key.preservation>1 or not key.morph_origin.is_finite() or key.morph_origin.x<0 or key.morph_origin.x>1 or key.morph_origin.y<0 or key.morph_origin.y>1 or not is_finite(key.direction) or not is_finite(key.topology_bias) or absf(key.topology_bias)>.15: errors.append("Invalid morph parameter.")
			if not is_finite(key.reveal_width) or key.reveal_width<=0 or key.reveal_width>2: errors.append("Invalid reveal width.")
			if key.curve!=null:
				if key.curve.point_count<2 or key.curve.point_count>1024: errors.append("A timing curve needs 2–1024 points.")
				for i in key.curve.point_count:
					var p := key.curve.get_point_position(i)
					if not p.is_finite() or p.x<0 or p.x>1 or not is_finite(key.curve.get_point_left_tangent(i)) or not is_finite(key.curve.get_point_right_tangent(i)): errors.append("Invalid timing curve data.")
			for point in key.points_a+key.points_b+key.reveal_path:
				if not point.is_finite() or point.x<0 or point.y<0 or point.x>1 or point.y>1: errors.append("Invalid morph/reveal point.")
			for i in key.points_a.size():
				for j in i:
					if key.points_a[i].distance_squared_to(key.points_a[j])<.00000001 or (key.points_b.size()==key.points_a.size() and key.points_b[i].distance_squared_to(key.points_b[j])<.00000001): errors.append("Conflicting correction pair coordinates.")
	var event_ids := {}; var births := {}; var split_counts := {}
	for event in component_events:
		if not event.get("id") is String or event.id.is_empty() or event_ids.has(event.id): errors.append("Invalid component event ID."); continue
		event_ids[event.id]=true
		if event.get("kind","") not in ["Split","Merge"] or not event.get("target") is String or component(event.target)==null or births.has(event.target): errors.append("Invalid component event target."); continue
		var at: Variant=event.get("time")
		if not (at is float or at is int) or not is_finite(float(at)) or at<0 or at>duration: errors.append("Invalid component event time."); continue
		births[event.target]=float(at)
		if not event.get("sources") is PackedStringArray or event.sources.is_empty(): errors.append("Invalid component event sources."); continue
		if event.kind=="Merge" and event.sources.size()<2: errors.append("A merge needs at least two source components.")
		var source_ids := {}
		for source: String in event.sources:
			if source==event.target or component(source)==null: errors.append("Missing component transfer source.")
			if source_ids.has(source): errors.append("Duplicate transfer source.")
			source_ids[source]=true
		if event.kind=="Split":
			if event.sources.size()!=1 or not event.get("mask") is Texture2D: errors.append("Invalid split mask."); continue
			var source: String=event.sources[0]; split_counts[source]=int(split_counts.get(source,0))+1
			if split_counts[source]>4: errors.append("At most four disjoint split masks per source.")
			if event.mask.get_width()<1 or event.mask.get_height()<1 or event.mask.get_width()>8192 or event.mask.get_height()>8192 or event.mask.get_width()*event.mask.get_height()>16777216: errors.append("Split mask exceeds image limits.")
	for event in component_events:
		if not event.get("sources") is PackedStringArray or not (event.get("time") is float or event.get("time") is int): continue
		for source: String in event.sources:
			if births.has(source) and births[source]>float(event.time): errors.append("A component transfer cannot precede its source's birth.")
	var dependencies := {}; var resolved := {}
	for event in component_events:
		if births.has(event.get("target")) and event.get("sources") is PackedStringArray:
			dependencies[event.target]=Array(event.sources).filter(func(id: String): return births.has(id))
	for pass_index in births.size()+1:
		var changed := false
		for target in dependencies.keys():
			if dependencies[target].all(func(id: String): return resolved.has(id)): resolved[target]=true; dependencies.erase(target); changed=true
		if not changed: break
	if not dependencies.is_empty(): errors.append("Cyclic component transfers are not valid.")
	return errors
func thumbnail() -> Texture2D:
	if preview_png.is_empty(): return null
	var image := Image.new()
	return ImageTexture.create_from_image(image) if image.load_png_from_buffer(preview_png)==OK else null
