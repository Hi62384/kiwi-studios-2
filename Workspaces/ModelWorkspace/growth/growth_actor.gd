class_name KiwiGrowthActor
extends RefCounted
const APPEARANCE:=["root_color","tip_color","highlight_color","roughness","specular","secondary_highlight","highlight_shift","backlight","opacity","emission","variation","pattern_scale","pattern_rotation","pattern_mix","texture_scale","texture_offset","texture_rotation","bands","edge_softness","outline","shaft_color","feather_detail","iridescence","left_vane_color","right_vane_color","feather_pattern_color","feather_pattern_scale","feather_pattern_width","shaft_roughness"]
static func extend_actor(definition: ActorDefinition) -> void:
	if definition.type_id!=&"basic_mesh" or definition.find_property(&"is_surface_growth")!=null: return
	var flag:=ActorProperty.create(&"is_surface_growth","Surface growth",false); flag.options.inspector_hidden=true; flag.options.group="Growth appearance"; definition.properties.append(flag)
	var kind:=ActorProperty.create(&"growth_kind","Growth type",0); kind.options.inspector_hidden=true; kind.options.group="Growth appearance"; definition.properties.append(kind)
	var defaults:=KiwiGrowthMaterial.new()
	for field: String in APPEARANCE:
		var property:=ActorProperty.create(StringName("growth_"+field),field.replace("_"," ").capitalize(),defaults.get(field),true)
		property.options.group="Growth appearance"; property.options.visible_when={"property":"is_surface_growth","values":[true]}
		property.options.visible_when_all=[{"property":"growth_rendering_mode","values":[0,1]}]
		if field.begins_with("feather_") or field in ["shaft_color","shaft_roughness","left_vane_color","right_vane_color","iridescence"]: property.options.visible_when_all.append({"property":"growth_kind","values":[2]})
		if typeof(defaults.get(field)) in [TYPE_FLOAT,TYPE_INT]: property.options.min=0.; property.options.max=1.; property.options.step=.01
		if field in ["pattern_scale","pattern_rotation","texture_rotation","feather_pattern_scale"]: property.options.min=-100.; property.options.max=100.
		if field=="bands": property.options.min=1; property.options.max=8; property.options.step=1
		if field=="highlight_shift": property.options.min=-.8; property.options.max=.8
		definition.properties.append(property)
	var mode:=ActorProperty.create(&"growth_rendering_mode","Rendering mode",0,false); mode.options={"default":0,"group":"Growth appearance","choices":["Realistic","Stylized / M2DO","Custom"],"visible_when":{"property":"is_surface_growth","values":[true]},"refresh_inspector":true,"no_keyframes":true}; definition.properties.append(mode)
	var custom:=ActorProperty.create(&"growth_custom_material","Custom material",null,false); custom.object_type=&"material"; custom.options.group="Growth appearance"; custom.options.visible_when_all=[{"property":"is_surface_growth","values":[true]},{"property":"growth_rendering_mode","values":[2]}]; definition.properties.append(custom)
static func initialize(actor: ActorData,data: KiwiSurfaceGrowthData) -> void:
	actor.values[&"is_surface_growth"]=true
	actor.values[&"growth_kind"]=int(data.settings.get("type",0))
	if data.appearance!=null:
		for field: String in APPEARANCE: actor.values[StringName("growth_"+field)]=data.appearance.get(field)
		actor.values[&"growth_rendering_mode"]=data.appearance.mode
		if data.appearance.custom_asset!=null: actor.values[&"growth_custom_material"]=ActorObjectReference.from_object(data.appearance.custom_asset.copy_object())
static func apply(runtime: ActorRuntime,values: Dictionary) -> void:
	if not values.get(&"is_surface_growth",false): return
	for node: Node in runtime.find_children("*","MeshInstance3D",true,false):
		if node is KiwiSurfaceGrowthInstance and node.data.appearance!=null:
			for field: String in APPEARANCE:
				if values.has(StringName("growth_"+field)): node.data.appearance.set(field,values[StringName("growth_"+field)])
			var reference: Variant=values.get(&"growth_custom_material"); var asset:=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
			if node.data.appearance.custom_asset!=null and asset==null: node.data.appearance.custom=null
			node.data.appearance.custom_asset=asset; node.data.appearance.mode=int(values.get(&"growth_rendering_mode",0)); node.update_growth()
