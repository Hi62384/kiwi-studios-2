class_name KiwiPowderSettings
extends RefCounted
## Simple flow controls derive contact coefficients; Advanced uses explicit values.
static func number(values: Dictionary,key: String,fallback: float,low: float,high: float) -> float:
	var value:=float(values.get(StringName(key),fallback))
	return clampf(value,low,high) if is_finite(value) else fallback
static func effective(values: Dictionary) -> Dictionary:
	var result:=values.duplicate()
	var flow:=number(values,"powder_flowability",.5,0,1); var friction:=number(values,"powder_friction",.6,0,2)
	var advanced:=bool(values.get(&"powder_advanced_material",false))
	result.static_friction=number(values,"powder_static_friction",.66,0,3) if advanced else friction*lerpf(1.8,.4,flow)
	result.dynamic_friction=minf(result.static_friction,number(values,"powder_dynamic_friction",.495,0,3)) if advanced else result.static_friction*.75
	result.rolling=number(values,"powder_rolling",.06,0,1) if advanced else friction*(1-flow)*.2
	result.cohesion=number(values,"powder_cohesion",0,0,10)
	result.separation=number(values,"powder_bond_range",.5,.05,2)
	result.packing=number(values,"powder_compaction",.98,.05,1)
	result.restitution=number(values,"powder_restitution",.05,0,1)
	result.damping=number(values,"powder_damping",.08,0,20)
	result.contact_damping=number(values,"powder_contact_damping",.2,0,1)
	result.density=number(values,"powder_density",1600,1,30000)
	result.gravity_scale=number(values,"powder_gravity",1,0,10)
	result.wind_influence=number(values,"powder_wind",1,0,20)
	result.air_drag=number(values,"powder_air_drag",.47,0,5)
	result.turbulence=number(values,"powder_turbulence",0,0,20)
	result.fluid_strength=number(values,"powder_fluid",1,0,2)
	result.max_speed=number(values,"powder_max_speed",20,.1,100)
	result.sleep_speed=number(values,"powder_sleep_speed",.025,.001,.2)
	result.sleep_delay=number(values,"powder_sleep_delay",.4,.05,5)
	var quality:=clampi(int(values.get(&"powder_quality",1)),0,2)
	result.substeps=clampi(int(values.get(&"powder_substeps",2))+[-1,0,2][quality],1,12)
	result.iterations=clampi(int(values.get(&"powder_iterations",6))+[-2,0,4][quality],2,16)
	return result

static func switch_mode(model: ActorTimeline,actors: Array[ActorData],advanced: bool) -> void:
	var before:=[]; var after:=[]
	for actor in actors:
		if actor.type_id!=&"powder": continue
		var values:=actor.values.duplicate(true); var effective_values:=effective(values)
		before.append({"actor":actor,"values":values.duplicate(true)})
		if advanced:
			values[&"powder_static_friction"]=effective_values.static_friction; values[&"powder_dynamic_friction"]=effective_values.dynamic_friction; values[&"powder_rolling"]=effective_values.rolling
		else: values[&"powder_friction"]=float(effective_values.static_friction)/lerpf(1.8,.4,number(values,"powder_flowability",.5,0,1))
		values[&"powder_advanced_material"]=advanced; after.append({"actor":actor,"values":values})
	model.history.create_action("Powder contact controls")
	model.history.add_do_method(assign.bind(weakref(model),after)); model.history.add_undo_method(assign.bind(weakref(model),before)); model.history.commit_action()
static func assign(reference: Variant,entries: Array) -> void:
	var model: ActorTimeline=reference.get_ref() if reference is WeakRef else reference
	if model==null: return
	for entry: Dictionary in entries: entry.actor.values=entry.values.duplicate(true); entry.actor.animation_previews.clear(); entry.actor.emit_changed()
	model.changed.emit()
