class_name KiwiDestructionDefinition
extends RefCounted
static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id not in [&"basic_shape",&"basic_mesh"] or d.find_property(&"destruction_enabled")!=null: return
	for row in [
		["destruction_enabled","Destruction enabled",false,{"refresh_inspector":true}],
		["destruction_mode","Damage mode",0,{"choices":["Manual","Physics","Combined"]}],
		["destruction_resistance","Impact resistance (joules)",5.0,{"min":.01,"max":10000.0}],
		["destruction_impact_type","Impact response",9,{"choices":KiwiDestructionGeometry.TYPES}],
		["destruction_detail","Fracture pieces",6,{"min":2,"max":16,"step":1}],
		["destruction_strength","Deformation strength",.2,{"min":0.0,"max":5.0}],
		["destruction_permanent","Permanent damage",true,{}],
		["destruction_recovery","Elastic recovery (1/s)",3.0,{"min":0.0,"max":30.0}],
		["destruction_interior_color","Interior color",Color(.24,.19,.13),{}],
		["destruction_operations","Operations",{}, {"destruction_editor":true,"no_keyframes":true}]
	]: KiwiPowderDefinition.add(d,row[0],row[1],row[2],"Destruction",row[3])
	var p:=ActorProperty.create(&"destruction_interior","Interior material",null); p.object_type=&"material"; p.options={"default":null,"group":"Destruction","accepted_object_types":["material","shader_material","natural_material"]}; d.properties.append(p)
	KiwiPowderDefinition.add(d,"destruction_preset","Physical material presets",0,"Destruction",{"damage_presets":true},false)
	KiwiPowderDefinition.add(d,"destruction_use_density","Use material density for mass",false,"Destruction",{"tooltip":"Off uses the existing Physics mass. On derives mass from the material density and source mesh volume."},false)
	for key in [&"destruction_material",&"destruction_region",&"destruction_region_2"]:
		var slot:=ActorProperty.create(key,"Damage material" if key==&"destruction_material" else ("Local material region" if key==&"destruction_region" else "Local material region 2"),null); slot.object_type=&"destruction_material" if key==&"destruction_material" else &"destruction_region"; slot.options.group="Destruction"; d.properties.append(slot)
	for property in d.properties:
		if str(property.id).begins_with("destruction_") and property.id!=&"destruction_enabled": property.options.visible_when={"property":"destruction_enabled","values":[true]}
		if str(property.id) in ["destruction_resistance","destruction_impact_type","destruction_detail","destruction_strength","destruction_permanent","destruction_recovery","destruction_interior_color","destruction_interior","destruction_use_density","destruction_region","destruction_region_2"]: property.options.advanced=true
	var order:=[&"destruction_enabled",&"destruction_preset",&"destruction_material",&"destruction_mode",&"destruction_operations"]
	var sorted: Array[ActorProperty]=[]
	for property in d.properties:
		if not str(property.id).begins_with("destruction_"): sorted.append(property)
	for key in order: sorted.append(d.find_property(key))
	for property in d.properties:
		if str(property.id).begins_with("destruction_") and not property.id in order: sorted.append(property)
	d.properties=sorted
static func operation(kind: int,time: float=0) -> Dictionary:
	return {"type":kind,"enabled":true,"time":time,"position":Vector3.ZERO,"direction":Vector3.RIGHT,"radius":.5,"amount":.25 if kind==12 else (.4 if kind in [3,6,7,8,9] else 1.0),"falloff":2.0,"pieces":6,"seed":1,"impulse":1.0,"physical":false,"energy":20.0,"irregularity":0.0,"direction_bias":0.0,"region_enabled":false,"region_center":Vector3.ZERO,"region_radius":.5,"depends_on":[]}
static func assign(reference: WeakRef,actor: ActorData,values: Dictionary) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model==null: return
	actor.values[&"destruction_operations"]=ActorData.copy_value(values); actor.animation_previews.clear(); actor.emit_changed(); model.changed.emit()
static func edit(model: ActorTimeline,actor: ActorData,operations: Dictionary,label: String="Edit destruction") -> void:
	var before:=model.animation_snapshot(actor); var after: Array[ActorAnimationTrack]=[]
	for track in before:
		if track.path.size()>1 and track.path[0]=="destruction_operations" and not operations.has(track.path[1]): continue
		after.append(track.copy_track())
	model.history.create_action(label)
	model.history.add_do_method(restore_animation.bind(weakref(model),actor,operations.duplicate(true),after))
	model.history.add_undo_method(restore_animation.bind(weakref(model),actor,ActorData.copy_value(actor.values.get(&"destruction_operations",{})),before))
	model.history.commit_action()
static func restore_animation(reference: WeakRef,actor: ActorData,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model==null: return
	actor.values[&"destruction_operations"]=ActorData.copy_value(values); actor.animation_previews.clear(); model.restore_animation(actor,tracks)
