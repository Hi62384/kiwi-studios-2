class_name KiwiPhysicsSettings
extends RefCounted
const TYPES := ["Rigid Body", "Soft Body", "Ragdoll / Jiggle", "Skeleton Ragdoll / Jiggle", "Cloth", "Rope"]
const MODES := ["Animated", "Simulated", "Guided", "Frozen", "Baked"]
const DEFAULTS := {
	"enabled": false, "type": 0, "mode": 1, "body_mode": 0,
	"gravity": 9.8, "gravity_direction": Vector3.DOWN, "mass": 1.0,
	"damping": 0.4, "angular_damping": 0.6, "friction": 0.5, "bounce": 0.25,
	"water_interaction":true,"water_drag":1.0,"water_buoyancy":1.0,
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
	"end_offset": Vector3.ZERO, "forces": [], "frozen": {}, "bake": {},
	"powder_accumulation":true,"powder_adhesion":0.0,"powder_max_coating":1.0
}
static func compatible(actor: ActorData) -> bool:
	if actor!=null and actor.type_id==&"global_fog": return false
	return actor != null and actor.values.get(&"position") is Vector3 and actor.type_id not in [&"world_environment", &"audio"] and not actor.type_id.ends_with("_2d")
static func authored(actor: ActorData) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	if actor.values.get(&"physics") is Dictionary: result.merge(actor.values[&"physics"], true)
	if actor.type_id==&"environment_asset": result.enabled=bool(result.enabled) and actor.values.get(&"environment_path") is String and not str(actor.values.get(&"environment_path","")).is_empty()
	if actor.type_id==&"fog_volume":
		result.type=9; result.enabled=int(actor.values.get(&"fog_motion_mode",0))>=2 and bool(actor.values.get(&"physics",{}).get("enabled",true))
		if not actor.values.get(&"physics",{}).has("steps"): result.steps=30
	if actor.type_id==&"fluid": result.type=6
	if actor.type_id==&"powder": result.type=7
	if KiwiGrowthPhysics.data(actor)!=null: result.type=8
	if actor.values.get(&"destruction_enabled",false) and not result.enabled:
		result.enabled=true; result.body_mode=2
	if actor.values.get(&"structure_enabled",false): result.enabled=true; result.type=0; result.body_mode=int(actor.values.get(&"structure_role",0))
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
	if actor.type_id==&"powder":
		result.type=7
		result.enabled=result.enabled and bool(ActorAnimation.sampled_value(actor,PackedStringArray(["powder_enabled"]),time,actor.values.get(&"powder_enabled",true)))
	if actor.animation_track(PackedStringArray(["destruction_enabled"]))!=null and not actor.values.get(&"physics",{}).get("enabled",false): result.enabled=true; result.body_mode=2
	if ActorAnimation.sampled_value(actor,PackedStringArray(["structure_enabled"]),time,actor.values.get(&"structure_enabled",false)):
		result.enabled=true; result.type=0; result.body_mode=int(ActorAnimation.sampled_value(actor,PackedStringArray(["structure_role"]),time,actor.values.get(&"structure_role",0)))
	elif (actor.get_value(&"structure_enabled",false) or actor.animation_track(PackedStringArray(["structure_enabled"]))!=null) and not actor.values.get(&"physics",{}).get("enabled",false) and not actor.get_value(&"destruction_enabled",false): result.enabled=false
	if KiwiGrowthPhysics.data(actor)!=null: result.type=8
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
	if actor.animation_tracks.any(func(track: ActorAnimationTrack): return track.path==PackedStringArray(["destruction_enabled"])): return true
	if actor.animation_tracks.any(func(track: ActorAnimationTrack): return track.path==PackedStringArray(["structure_enabled"])): return true
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
	var snapshots: Array=result.get("bake",{}).get("frames",[]).duplicate()
	if result.get("frozen",{}).get("state") is Dictionary: snapshots.append(result.frozen.state)
	for state: Dictionary in snapshots:
		for fragment: Dictionary in state.get("destruction_fragments",[]):
			var source:=str(fragment.id).get_slice(":fragment:",0)
			if ids.has(source): fragment.id=str(ids[source])+":fragment:"+str(fragment.id).get_slice(":fragment:",1)
		for event: Dictionary in state.get("destruction_events",[]):
			event.source_actor=ids.get(str(event.get("source_actor","")),event.get("source_actor",""))
		if state.has("structural"):
			var island:=str(state.structural.get("island","")); state.structural.island=ids.get(island,island)
		for deposit: Dictionary in state.get("powder_deposits",{}).values():
			deposit.actor=ids.get(str(deposit.actor),deposit.actor)
			if str(deposit.get("proxy","")).contains(":p"):
				var old:=str(deposit.proxy).get_slice(":p",0); deposit.proxy=str(ids.get(old,old))+":p"+str(deposit.proxy).get_slice(":p",1)
		if not state.has("powder_bonds"): continue
		var bonds:={}
		for bond: Dictionary in state.powder_bonds.values():
			bond.actor=ids.get(str(bond.actor),bond.actor); bonds[str(bond.a)+"|"+str(bond.actor)+"|"+str(bond.b)]=bond
		state.powder_bonds=bonds
	if not ids.is_empty() and result.get("bake",{}) is Dictionary and not result.get("bake",{}).is_empty():
		if result.bake.get("portable",false):
			var mapped:={}; var previous: Dictionary=result.bake.get("portable_ids",{})
			if previous.is_empty():
				for id: String in ids: mapped[id]=ids[id]
			else:
				for id: String in previous: mapped[id]=ids.get(str(previous[id]),previous[id])
			result.bake.portable_ids=mapped
		else: result.bake.signature="" # Ordinary world-space bakes need recalculation after a copy.
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
		var growth: Array=[]
		if value.growth!=null:
			var physical:=KiwiSurfaceGrowth.base_settings(value.growth).duplicate()
			for field: String in ["color","quality","cross_section","flatten","twist","thickness","tip_thickness","taper","width","feather_tip","feather_asymmetry"]: physical.erase(field)
			var layers:=[]
			for layer: Dictionary in value.growth.groom_layers:
				var edits:=physical_groom(layer.get("changes",{}))
				if not edits.is_empty(): layers.append([layer.get("enabled",true),edits])
			var regions:=[]
			for region: Dictionary in value.growth.regions:
				if region.get("style") is KiwiGrowthStyle:
					var style_values: Dictionary=region.style.values.duplicate()
					for field: String in ["color","quality","cross_section","flatten","twist","thickness","tip_thickness","taper","width","feather_tip","feather_asymmetry"]: style_values.erase(field)
					if not style_values.is_empty(): regions.append([region.get("roots",PackedInt32Array()),region.get("faces",PackedInt32Array()),region.get("enabled",true),region.get("all",false),style_values])
			growth=[value.growth.source_id,value.growth.roots,value.growth.source_points,physical,physical_groom(value.growth.groom),layers,value.growth.guides,physical_groom(value.growth.individual),regions,value.growth.source_weights,canonical(value.growth.source_skin)]
		return [canonical(value.mesh),canonical(value.skin),canonical(value.skin_mesh),value.transform,value.skeleton_id,value.bones,canonical(value.modifiers),value.parameters,value.generator,growth]
	if value is KiwiModelMesh:
		return [hash(value.vertices),hash(value.faces),value.smooth]
	if value is Resource:
		return [value.get_class(), value.resource_path]
	return value
static func physical_groom(edits: Dictionary) -> Dictionary:
	var result:={}
	for id: Variant in edits:
		var values: Dictionary=edits[id].duplicate()
		for field: String in ["color","density","width","thickness","tip_thickness","roll","locked","material"]: values.erase(field)
		if not values.is_empty(): result[id]=values
	return result
static func fingerprint(model: RefCounted) -> String:
	var needed := {}; var queue: Array[String] = []; var geometry_roots:={}
	for actor: ActorData in model.actors:
		if configured(actor): queue.append(actor.id)
		if configured(actor) and actor.type_id==&"powder": geometry_roots[str(actor.values.get(&"powder_mesh_actor",""))]=true
	while not queue.is_empty():
		var id := queue.pop_back() as String
		if needed.has(id): continue
		var actor: ActorData = model.actor_for_id(id)
		if actor == null: continue
		needed[id] = true
		if actor.type_id==&"fog_volume":
			queue.append_array(preload("res://scripts/actors/fog/fog_motion_definition.gd").dependencies(actor))
			if actor.values.get(&"fog_character_proxies",true):
				for candidate: ActorData in model.actors:
					if not (candidate.values.get(&"rig_bones",[]) as Array).is_empty(): queue.append(candidate.id)
		if not str(actor.values.get(&"model_skeleton_actor","")).is_empty(): queue.append(str(actor.values[&"model_skeleton_actor"]))
		if actor.type_id==&"powder":
			queue.append(str(actor.values.get(&"powder_mesh_actor","")))
			if actor.values.get(&"powder_characters",true):
				for candidate: ActorData in model.actors:
					if not (candidate.values.get(&"rig_bones",[]) as Array).is_empty(): queue.append(candidate.id)
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
		if configured(actor) or geometry_roots.has(id):
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
		if actor.type_id in [&"basic_shape",&"basic_mesh"]:
			var damage_material:=KiwiDestructionMaterial.resolve(actor.values)
			if damage_material!=null: values["resolved_damage_material"]=KiwiDestructionMaterial.physical(damage_material)
		for key: Variant in actor.values:
			if actor.type_id==&"fog_volume":
				if not preload("res://scripts/actors/fog/fog_motion_definition.gd").physical_path(PackedStringArray([str(key)])): continue
				values[str(key)]=canonical(preload("res://scripts/actors/fog/fog_motion_definition.gd").content(actor.values[key])); continue
			if str(key)=="shadow_casting": continue
			if str(key).begins_with("growth_"): continue
			if str(key) in ["structure_overlay","structure_assembly","destruction_overrides","destruction_setup","destruction_setup_actions","destruction_vfx_offset","growth_overrides"]: continue
			if str(key) in KiwiDebris.VISUAL: continue
			if str(key) in ["destruction_interior","destruction_interior_color","destruction_preset"]: continue
			if str(key) in ["destruction_material","destruction_region","destruction_region_2"]: values[str(key)]=KiwiDestructionMaterial.physical(actor.values[key]); continue
			if actor.type_id==&"fluid" and str(key) in KiwiFluidSettings.APPEARANCE: continue
			if actor.type_id==&"powder" and not KiwiPowderMaterial.physical_path(PackedStringArray([str(key)])): continue
			if str(key) in ["material", "color", "text_settings", "image_path", "shader", "uniforms", "text", "physics"]: continue
			var value: Variant = actor.values[key]
			values[str(key)] = canonical(value)
			if str(key) == "mesh_path" and value is String and FileAccess.file_exists(value): values["mesh_modified"] = FileAccess.get_modified_time(value)
			if str(key)=="environment_path" and value is String and FileAccess.file_exists(value): values["environment_modified"]=[FileAccess.get_modified_time(value),KiwiEnvironmentAssets.revisions.get(value,0)]
		var config := authored(actor)
		if int(config.mode) == 4: config.mode = int(config.bake.get("source_mode",1))
		config.erase("bake")
		var tracks := []
		for track in actor.animation_tracks:
			if actor.type_id==&"fog_volume" and not preload("res://scripts/actors/fog/fog_motion_definition.gd").physical_path(track.path): continue
			if not track.path.is_empty() and track.path[0]=="shadow_casting": continue
			if not track.path.is_empty() and track.path[0].begins_with("growth_"): continue
			if not track.path.is_empty() and track.path[0] in ["destruction_overrides","destruction_vfx_offset"]: continue
			if not track.path.is_empty() and track.path[0] in KiwiDebris.VISUAL: continue
			if not track.path.is_empty() and track.path[0] in ["destruction_interior","destruction_interior_color","destruction_preset"]: continue
			if track.path.size()>1 and track.path[0]=="destruction_material" and track.path[1] in KiwiDestructionMaterial.VISUAL: continue
			if actor.type_id==&"fluid" and not track.path.is_empty() and track.path[0] in KiwiFluidSettings.APPEARANCE: continue
			if actor.type_id==&"powder" and not KiwiPowderMaterial.physical_path(track.path): continue
			if track.path.is_empty() or track.path[0] in ["material","color","text_settings","image_path","shader","uniforms","text"]: continue
			var keys := []
			for key in track.keys: keys.append([key.time, canonical(key.value), key.interpolation, key.attenuation, canonical(key.value_curve)])
			tracks.append([track.path, keys])
		var previews := {}
		for key in actor.animation_previews:
			var preview: Dictionary = actor.animation_previews[key]
			if actor.type_id==&"fog_volume":
				if preload("res://scripts/actors/fog/fog_motion_definition.gd").physical_path(preview.path): previews[key]=preview
				continue
			if not preview.path.is_empty() and (preview.path[0] in ["destruction_overrides","destruction_vfx_offset"] or preview.path[0].begins_with("growth_")): continue
			if not preview.path.is_empty() and preview.path[0].begins_with("destruction_") and not preview.path[0] in ["destruction_interior","destruction_interior_color","destruction_preset"]:
				if preview.path.size()<2 or not preview.path[1] in KiwiDestructionMaterial.VISUAL: previews[key]=preview
			if not preview.path.is_empty() and (preview.path[0] in ["physics","position","rotation","scale","bone_poses"] or (actor.type_id==&"fluid" and not preview.path[0] in KiwiFluidSettings.APPEARANCE) or (actor.type_id==&"powder" and KiwiPowderMaterial.physical_path(preview.path))): previews[key] = preview
			if not preview.path.is_empty() and preview.path[0].begins_with("structure_") and not preview.path[0] in ["structure_overlay","structure_assembly"]: previews[key]=preview
		data.append([actor.id, actor.type_id, actor.parent_id, values, config, tracks, canonical(previews), [clip.start_time, clip.duration, clip.source_offset, clip.playback_speed] if clip != null else []])
	return var_to_str(canonical(data)).sha256_text()
