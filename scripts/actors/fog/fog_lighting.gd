extends RefCounted
## Native per-light and per-geometry controls, shared by ordinary and fog lighting.
static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id in [&"light_3d",&"directional_light"]:
		for row in [["volumetric_fog_energy","Volumetric fog energy",1.,0.,32.],["shadow_bias","Shadow bias",.1,0.,16.],["shadow_normal_bias","Shadow normal bias",2.,0.,16.],["shadow_opacity","Shadow opacity",1.,0.,1.],["shadow_blur","Shadow softness",1.,0.,8.],["light_size","Light source size",0.,0.,10.],["attenuation","Distance attenuation",1.,.01,16.],["spot_attenuation","Cone attenuation",1.,.01,16.]]:
			if d.find_property(StringName(row[0]))!=null: continue
			var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge({"min":row[3],"max":row[4],"group":"Volumetric lighting" if row[0]=="volumetric_fog_energy" else "Shadows"})
			if row[0]=="volumetric_fog_energy": p.options.tooltip="Zero removes only this light's volumetric contribution. Surface lighting still uses Energy."
			if row[0] in ["attenuation","spot_attenuation","light_size"]:
				if d.type_id==&"directional_light": continue
				p.options.group="Light"; p.options.visible_when={"property":"light_type","values":[2] if row[0]=="spot_attenuation" else [1,2]}
			d.properties.append(p)
	if d.type_id in [&"basic_mesh",&"basic_shape",&"text_3d",&"image_3d"] and d.find_property(&"shadow_casting")==null:
		var p:=ActorProperty.create(&"shadow_casting","Shadow casting",0,true); p.options.merge({"group":"Lighting","choices":["Keep original","Off","On","Double-sided","Shadows only"],"tooltip":"Uses native shadow maps. Transparent and custom materials retain the renderer's shadow limitations."}); d.properties.append(p)

static func extend_environment(d: ActorObjectDefinition) -> void:
	for row in [["volumetric_fog_temporal_reprojection_enabled","Temporal reprojection",true,{}],["volumetric_fog_temporal_reprojection_amount","Temporal history strength",.9,{"min":0.,"max":.99}],["volumetric_fog_ambient_inject","Ambient illumination injection",0.,{"min":0.,"max":16.}]]:
		if d.find_property(StringName(row[0]))!=null: continue
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[3]); p.options.group="Volumetric Fog"; p.options.tooltip="Environment-wide. Offline frame capture disables temporal history to prevent trails after time jumps."; d.properties.append(p)

static func apply_light(light: Light3D,v: Dictionary) -> void:
	light.light_volumetric_fog_energy=maxf(0.,float(v.get(&"volumetric_fog_energy",1.)))
	light.shadow_bias=v.get(&"shadow_bias",.1); light.shadow_normal_bias=v.get(&"shadow_normal_bias",2.); light.shadow_opacity=v.get(&"shadow_opacity",1.); light.shadow_blur=v.get(&"shadow_blur",1.)
	light.light_size=maxf(0.,float(v.get(&"light_size",0.)))
	if light is OmniLight3D: light.omni_attenuation=v.get(&"attenuation",1.)
	if light is SpotLight3D: light.spot_attenuation=v.get(&"attenuation",1.); light.spot_angle_attenuation=v.get(&"spot_attenuation",1.)

static func apply_geometry(runtime: Node,v: Dictionary) -> void:
	if not v.has(&"shadow_casting"): return
	visit_geometry(runtime,runtime,clampi(int(v.get(&"shadow_casting",0)),0,4))
static func visit_geometry(node: Node,owner: Node,mode: int) -> void:
	if node!=owner and node is ActorRuntime: return
	if node is GeometryInstance3D:
		if not node.has_meta("kiwi_original_shadow_mode"): node.set_meta("kiwi_original_shadow_mode",node.cast_shadow)
		node.cast_shadow=node.get_meta("kiwi_original_shadow_mode") if mode==0 else mode-1
	for child in node.get_children(): visit_geometry(child,owner,mode)
