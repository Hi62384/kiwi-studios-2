class_name KiwiPhysicsSettings
extends RefCounted
const TYPES := ["Rigid Body", "Soft Body", "Ragdoll / Jiggle", "Skeleton Ragdoll / Jiggle", "Cloth", "Rope"]
const MODES := ["Animated", "Simulated", "Guided", "Frozen", "Baked"]
const DEFAULTS := {
	"enabled": false, "type": 0, "mode": 1, "body_mode": 0,
	"gravity": 9.8, "gravity_direction": Vector3.DOWN, "mass": 1.0,
	"damping": 0.4, "angular_damping": 0.6, "friction": 0.5, "bounce": 0.25,
	"velocity": Vector3.ZERO, "angular_velocity": Vector3.ZERO, "inherit_velocity": true,
	"collision": true, "layer": 1, "mask": 1, "shape": 0, "collision_only": false,
	"activation": 0.0, "end": -1.0, "influence": 1.0, "steps": 60,
	"stiffness": 35.0, "recovery": 8.0, "stretch": 0.95, "bend": 0.2,
	"radius": 0.04, "limit": 80.0, "position_limit": 2.0, "ragdoll": false,
	"attachment": "", "attachment_bone": "", "pivot": Vector3.ZERO,
	"constraint": 0, "axis": Vector3.UP, "distance": 1.0, "body_pivot": Vector3.ZERO,
	"bones": [], "bone_settings": {}, "pins": [], "pin_region": 0,
	"particles": 128, "iterations": 8, "wind": Vector3.ZERO,
	"rope_points": 20, "rope_length": 3.0, "rope_radius": 0.035,
	"rope_start": true, "rope_end": false, "end_actor": "", "end_bone": "",
	"end_offset": Vector3.ZERO, "forces": [], "frozen": {}, "bake": {}
}
static func compatible(actor: ActorData) -> bool:
	return actor != null and actor.values.get(&"position") is Vector3 and actor.type_id not in [&"world_environment", &"audio"] and not actor.type_id.ends_with("_2d")
static func authored(actor: ActorData) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	if actor.values.get(&"physics") is Dictionary: result.merge(actor.values[&"physics"], true)
	if actor.type_id==&"fluid": result.type=6
	return result
static func sample(actor: ActorData, time: float) -> Dictionary:
	var result := authored(actor)
	var sampled := {}
	for track in actor.animation_tracks:
		if track.path.size() >= 2 and track.path[0] == "physics":
			var id := " / ".join(track.path)
			if sampled.has(id): continue
			sampled[id] = true
			var path := track.path.slice(1)
			set_nested(result,path,ActorAnimation.sampled_value(actor,track.path,time,get_nested(result,path)))
	for preview: Dictionary in actor.animation_previews.values():
		if preview.path.size() >= 2 and preview.path[0] == "physics": set_nested(result,preview.path.slice(1),preview.value)
	if actor.type_id==&"fluid": result.type=6
	return result
static func get_nested(values: Dictionary, path: PackedStringArray) -> Variant:
	var value: Variant = values
	for key in path:
		if not value is Dictionary: return null
		value = value.get(key)
	return value
static func set_nested(values: Dictionary, path: PackedStringArray, value: Variant) -> void:
	if path.is_empty(): return
	var target := values
	for i in path.size()-1:
		var child: Variant = target.get(path[i],{})
		if not child is Dictionary: child = {}
		target[path[i]] = child.duplicate(true); target = target[path[i]]
	target[path[-1]] = ActorData.copy_value(value)
static func configured(actor: ActorData) -> bool:
	if not compatible(actor): return false
	if authored(actor).enabled: return true
	return actor.animation_tracks.any(func(track: ActorAnimationTrack): return track.path == PackedStringArray(["physics", "enabled"]))
static func edit(model: RefCounted, actor: ActorData, key: String, value: Variant) -> void:
	var path := PackedStringArray(["physics", key])
	if actor.animation_track(path) != null:
		model.commit_animation_value(actor, path, value)
		return
	var before: Variant = ActorData.copy_value(actor.values.get(&"physics", {}))
	var after := authored(actor); after[key] = ActorData.copy_value(value)
	if before == after: return
	model.history.create_action("Physics: " + key.capitalize())
	model.history.add_do_method(assign.bind(model, actor, after))
	model.history.add_undo_method(assign.bind(model, actor, before))
	model.history.commit_action()
static func assign(model: RefCounted, actor: ActorData, values: Dictionary) -> void:
	actor.values[&"physics"] = ActorData.copy_value(values); actor.animation_previews.clear(); actor.emit_changed(); model.changed.emit()
static func remap(values: Dictionary, ids: Dictionary) -> Dictionary:
	var result := values.duplicate(true)
	for key in ["attachment", "end_actor"]:
		if result.has(key): result[key] = ids.get(str(result[key]), result[key])
	for pin: Dictionary in result.get("pins", []): pin["actor"] = ids.get(str(pin.get("actor", "")), pin.get("actor", ""))
	return result
static func pin(editor: Control, actor: ActorData, index: int, position: Vector3, remove: bool=false) -> void:
	var config:=authored(actor); var pins: Array=config.pins.duplicate(true)
	for i in range(pins.size()-1,-1,-1):
		if int(pins[i].get("point",-1))==index: pins.remove_at(i)
	if not remove:
		var target:=str(config.attachment); var offset:=position
		if not target.is_empty(): offset=editor.physics.bone_world(target,str(config.attachment_bone),editor.canvas.playhead).affine_inverse()*position
		pins.append({"point":index,"actor":target,"bone":str(config.attachment_bone),"follow":not target.is_empty(),"offset":offset,"world":position})
	edit(editor.model,actor,"pins",pins)
static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}; var keys: Array = value.keys(); keys.sort_custom(func(a: Variant, b: Variant): return str(a) < str(b))
		for key in keys: result[str(key)] = canonical(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(canonical(item))
		return result
	if value is Curve:
		var result := []
		for i in value.point_count: result.append([value.get_point_position(i), value.get_point_left_tangent(i), value.get_point_right_tangent(i), value.get_point_left_mode(i), value.get_point_right_mode(i)])
		return result
	if value is Mesh:
		var surfaces := []
		for i in value.get_surface_count(): surfaces.append(hash(value.surface_get_arrays(i)))
		return [value.get_class(),value.resource_path,surfaces]
	if value is Skin:
		var binds := []
		for i in value.get_bind_count(): binds.append([value.get_bind_bone(i),value.get_bind_name(i),value.get_bind_pose(i)])
		return binds
	if value is KiwiModelComponent:
		return [canonical(value.mesh),canonical(value.skin),canonical(value.skin_mesh),value.transform,value.skeleton_id,value.bones,canonical(value.modifiers),value.parameters,value.generator]
	if value is KiwiModelMesh:
		return [hash(value.vertices),hash(value.faces),value.smooth]
	if value is Resource:
		return [value.get_class(), value.resource_path]
	return value
static func fingerprint(model: RefCounted) -> String:
	var needed := {}; var queue: Array[String] = []
	for actor: ActorData in model.actors:
		if configured(actor): queue.append(actor.id)
	while not queue.is_empty():
		var id := queue.pop_back() as String
		if needed.has(id): continue
		var actor: ActorData = model.actor_for_id(id)
		if actor == null: continue
		needed[id] = true
		if actor.type_id==&"fluid":
			queue.append(str(actor.values.get(&"fluid_mesh_actor","")))
			if actor.values.get(&"fluid_characters",true):
				for candidate: ActorData in model.actors:
					if not (candidate.values.get(&"rig_bones",[]) as Array).is_empty(): queue.append(candidate.id)
		for driver: ActorData in model.actors:
			if driver.type_id==&"remote_transform" and str(driver.values.get(&"remote_actor",""))==id: queue.append(driver.id)
		if not actor.parent_id.is_empty(): queue.append(actor.parent_id)
		var settings := authored(actor)
		for target in [settings.attachment, settings.end_actor]:
			if not str(target).is_empty(): queue.append(str(target))
		for pin: Dictionary in settings.pins:
			if not str(pin.get("actor", "")).is_empty(): queue.append(str(pin.actor))
		# Group actors may own a model hierarchy rather than a mesh themselves.
		if configured(actor):
			for candidate: ActorData in model.actors:
				var parent: ActorData = model.actor_for_id(candidate.parent_id); var seen := {}
				while parent != null and not seen.has(parent.id):
					if parent.id == id: queue.append(candidate.id); break
					seen[parent.id] = true; parent = model.actor_for_id(parent.parent_id)
	var data := []
	for actor: ActorData in model.actors:
		if not needed.has(actor.id): continue
		var clip: ActorClip = model.clip_for_actor_id(actor.id)
		var values := {}
		for key: Variant in actor.values:
			if actor.type_id==&"fluid" and str(key) in KiwiFluidSettings.APPEARANCE: continue
			if str(key) in ["material", "color", "text_settings", "image_path", "shader", "uniforms", "text", "physics"]: continue
			var value: Variant = actor.values[key]
			values[str(key)] = canonical(value)
			if str(key) == "mesh_path" and value is String and FileAccess.file_exists(value): values["mesh_modified"] = FileAccess.get_modified_time(value)
		var config := authored(actor)
		if int(config.mode) == 4: config.mode = int(config.bake.get("source_mode",1))
		config.erase("bake")
		var tracks := []
		for track in actor.animation_tracks:
			if actor.type_id==&"fluid" and not track.path.is_empty() and track.path[0] in KiwiFluidSettings.APPEARANCE: continue
			if track.path.is_empty() or track.path[0] in ["material","color","text_settings","image_path","shader","uniforms","text"]: continue
			var keys := []
			for key in track.keys: keys.append([key.time, canonical(key.value), key.interpolation, key.attenuation, canonical(key.value_curve)])
			tracks.append([track.path, keys])
		var previews := {}
		for key in actor.animation_previews:
			var preview: Dictionary = actor.animation_previews[key]
			if not preview.path.is_empty() and (preview.path[0] in ["physics","position","rotation","scale","bone_poses"] or (actor.type_id==&"fluid" and not preview.path[0] in KiwiFluidSettings.APPEARANCE)): previews[key] = preview
		data.append([actor.id, actor.type_id, actor.parent_id, values, config, tracks, canonical(previews), [clip.start_time, clip.duration, clip.source_offset, clip.playback_speed] if clip != null else []])
	return var_to_str(canonical(data)).sha256_text()
