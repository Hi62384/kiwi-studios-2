extends RefCounted
const RESOLUTIONS:=[8,12,16,24]
static func extend_actor(d: ActorDefinition) -> void:
	if not d.type_id in [&"fog_volume",&"global_fog"] or d.find_property(&"fog_motion_mode")!=null: return
	var mode:=ActorProperty.create(&"fog_motion_mode","Movement",0); mode.options.merge({"group":"Motion & simulation","choices":["Static","Procedural"] if d.type_id==&"global_fog" else ["Static","Procedural","Simulated","Simulated + procedural detail"],"refresh_inspector":true,"no_keyframes":true}); d.properties.append(mode)
	var rows:=[
		["fog_wind","Wind velocity (m/s)",Vector3.ZERO,"Wind",{}],
		["fog_wind_influence","Wind influence",1.,"Wind",{"min":0.,"max":8.}],
		["fog_gust_strength","Gust strength",0.,"Wind",{"min":0.,"max":8.}],
		["fog_gust_frequency","Gust frequency",1.,"Wind",{"min":0.,"max":16.}],
		["fog_turbulence","Turbulence acceleration",0.,"Turbulence",{"min":0.,"max":32.}],
		["fog_turbulence_scale","Turbulence scale (m)",1.,"Turbulence",{"min":.01,"max":1000.}],
		["fog_turbulence_frequency","Turbulence frequency",1.,"Turbulence",{"min":0.,"max":16.}],
		["fog_seed","Motion seed",1,"Turbulence",{"no_keyframes":true}],
		["fog_procedural_rotation","Procedural rotation (°/s)",Vector3.ZERO,"Procedural detail",{}],
		["fog_expansion","Expansion velocity",0.,"Transport",{"min":0.,"max":32.}],
		["fog_diffusion","Diffusion / mixing (m²/s)",0.,"Transport",{"min":0.,"max":4.}],
		["fog_dissipation","Density decay (1/s)",0.,"Transport",{"min":0.,"max":32.}],
		["fog_buoyancy","Buoyancy acceleration",0.,"Transport",{"min":-32.,"max":32.}],
		["fog_velocity_damping","Velocity damping",.1,"Transport",{"min":0.,"max":16.}],
		["fog_quality","Simulation quality",0,"Domain",{"choices":["Fast · 8³","Balanced · 12³","Detailed · 16³","Final · 24³","Custom"],"no_keyframes":true,"refresh_inspector":true}],
		["fog_resolution","Custom resolution",16,"Domain",{"min":4,"max":32,"no_keyframes":true}],
		["fog_initial","Initial concentration",0,"Domain",{"choices":["Authored density field","Empty · use sources"],"no_keyframes":true}],
		["fog_domain_behavior","Domain behavior",0,"Domain",{"choices":["Fixed world domain","Move domain with actor"],"no_keyframes":true,"tooltip":"A fixed domain retains previously emitted fog in world space. Moving emitters are evaluated separately."}],
		["fog_boundaries","Domain boundaries",0,"Domain",{"choices":["Open · concentration can leave","Sealed"],"no_keyframes":true}],
		["fog_pressure_iterations","Pressure iterations",2,"Domain",{"min":0,"max":24,"no_keyframes":true}],
		["fog_max_density","Concentration maximum",32.,"Domain",{"min":.1,"max":256.}],
		["fog_obstacles","Obstacle interaction",true,"Obstacles",{}],
		["fog_obstacle_motion","Moving boundary influence",1.,"Obstacles",{"min":0.,"max":4.}],
		["fog_character_proxies","Character / deformable proxies",true,"Obstacles",{}]
	]
	for row in rows:
		if d.type_id==&"global_fog" and not row[3] in ["Wind","Turbulence","Procedural detail"]: continue
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[4]); p.options.group=row[3]; p.options.visible_when={"property":"fog_motion_mode","values":[1,2,3] if row[3] in ["Wind","Turbulence"] else ([1,3] if row[3]=="Procedural detail" else [2,3])}; d.properties.append(p)
	if d.type_id==&"global_fog": return
	var links:=ActorProperty.create(&"fog_motion_links","Source attachment remapping",{}); links.options.hidden=true; links.options.no_keyframes=true; links.options.group="Motion & simulation"; d.properties.append(links)
	for index in 4:
		for type in ["source","velocity"]:
			var p:=ActorProperty.create(StringName("fog_%s_%d"%[type,index]),("Emission source" if type=="source" else "Velocity influence")+" %d"%(index+1),null); p.object_type=&"fog_emitter" if type=="source" else &"fog_velocity_field"; p.options.group="Emission" if type=="source" else "Velocity fields"; p.options.visible_when={"property":"fog_motion_mode","values":[2,3]}; d.properties.append(p)
	var status:=ActorProperty.create(&"fog_motion_status","Transport status",false); status.options.merge({"group":"Motion & simulation","fog_motion_status":true,"no_keyframes":true}); d.properties.append(status)

static func emitter_definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"fog_emitter"; d.display_name="Fog Emission Source"
	add_rows(d,[
		["enabled","Enabled",true,{}],["mode","Emission",0,{"choices":["Continuous","Burst"]}],
		["shape","Source shape",1,{"choices":["Point","Sphere","Box","Disk","Cone","Closed mesh volume"]}],
		["position","Source position",Vector3.ZERO,{}],["size","Source size (m)",Vector3.ONE*.5,{}],
		["direction","Direction",Vector3.UP,{}],["spread","Spread (°)",0.,{"min":0.,"max":180.}],
		["rate","Concentration volume / second",.2,{"min":0.,"max":1000.}],
		["burst","Burst concentration volume",1.,{"min":0.,"max":1000.}],
		["start","Start (source seconds)",0.,{}],["end","End (-1 = no stop)",-1.,{}],
		["velocity","Initial velocity (m/s)",Vector3.UP,{}],["inherit_velocity","Inherit source movement",true,{}],
		["seed","Seed",1,{"no_keyframes":true}],["source_actor","Follow actor","",{"fog_actor_link":true,"no_keyframes":true,"refresh_inspector":true}],["source_bone","Bone (optional)","",{"no_keyframes":true}]
	])
	var p:=ActorProperty.create(&"mesh","Closed source mesh",""); p.options.merge({"file_picker":true,"extensions":["tres","res","mesh"],"native_resource_types":["Mesh"],"file_resource_mode":"uneditable","group":"Source","visible_when":{"property":"shape","values":[5]}}); d.properties.append(p); return d
static func velocity_definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"fog_velocity_field"; d.display_name="Fog Velocity Influence"
	add_rows(d,[
		["enabled","Enabled",true,{}],["type","Influence",0,{"choices":["Directional","Radial outward","Radial inward","Vortex","Coherent turbulence"]}],
		["position","Center",Vector3.ZERO,{}],["direction","Direction / vortex axis",Vector3.UP,{}],
		["radius","Radius (m)",2.,{"min":.01,"max":10000.}],["strength","Acceleration (m/s²)",1.,{"min":-100.,"max":100.}],["falloff","Falloff",1.,{"min":0.,"max":16.}],
		["source_actor","Follow actor","",{"fog_actor_link":true,"no_keyframes":true,"refresh_inspector":true}],["source_bone","Bone (optional)","",{"no_keyframes":true}]
	]); return d
static func add_rows(d: ActorObjectDefinition,rows: Array) -> void:
	for row in rows:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[3]); p.options.group="Source" if d.type_id==&"fog_emitter" else "Influence"; d.properties.append(p)
static func resolution(values: Dictionary) -> int:
	var index:=clampi(int(values.get(&"fog_quality",0)),0,4); return clampi(int(values.get(&"fog_resolution",16)),4,32) if index==4 else RESOLUTIONS[index]

static func physical_path(path: PackedStringArray) -> bool:
	if path.is_empty(): return false
	return path[0] in ["position","rotation","scale","volume_size","shape","boundary_mesh","field","fog_motion_links"] or (path[0].begins_with("fog_") and not path[0] in ["fog_presets","fog_motion_status"])

static func content(value: Variant,depth: int=0) -> Variant:
	if depth>12: return "reference depth limit"
	if value is ActorObjectReference: return content(ActorAnimation.resolve_reference(value),depth+1)
	if value is ActorObjectData:
		var result:={"type":value.type_id}
		for key: Variant in value.values:
			if str(key).begins_with("brush_") or str(key) in ["paint_tool","paint_plane","paint_depth","paint_symmetry","quality","custom_size"]: continue
			result[str(key)]=content(value.values[key],depth+1)
		return result
	if value is Dictionary:
		var result:={}
		for key: Variant in value: result[key]=content(value[key],depth+1)
		return result
	return value

static func dependencies(actor: ActorData) -> Array[String]:
	var result: Array[String]=[]
	for slot in 4:
		for kind in ["source","velocity"]:
			var reference: Variant=actor.values.get(StringName("fog_%s_%d"%[kind,slot])); var object: ActorObjectData=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
			if object!=null:
				var id:=str(object.values.get(&"source_actor","")); id=str(actor.values.get(&"fog_motion_links",{}).get(id,id))
				if not id.is_empty(): result.append(id)
	return result

static func remap_actor(actor: ActorData,ids: Dictionary,clear_external: bool=false) -> void:
	if actor.type_id!=&"fog_volume": return
	var links: Dictionary=actor.values.get(&"fog_motion_links",{}).duplicate()
	for slot in 4:
		for kind in ["source","velocity"]:
			var reference: Variant=actor.values.get(StringName("fog_%s_%d"%[kind,slot])); var object: ActorObjectData=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
			if object==null: continue
			var original:=str(object.values.get(&"source_actor","")); var current:=str(links.get(original,original))
			if not original.is_empty(): links[original]=ids.get(current,"" if clear_external else current)
	if not links.is_empty(): actor.values[&"fog_motion_links"]=links
