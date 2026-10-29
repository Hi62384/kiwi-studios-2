extends RefCounted
## Multi-scale bounded atmospheric density. Sampling is independent of renderer
## quality and scene clocks; the shared fog field caches the resulting 3D texture.
static func extend_definition(d: ActorObjectDefinition) -> void:
	d.find_property(&"mode").options.choices.append("Cloud / atmospheric structure")
	var rows:=[
		["cloud_type","Formation",0,{"choices":["Cumulus","Stratus","Wispy / cirrus","Storm","Ground mist","Atmospheric haze"]}],
		["cloud_coverage","Coverage",.55,{"min":0.,"max":1.}],
		["cloud_size","Macro scale",1.,{"min":.05,"max":16.}],
		["cloud_macro","Macro irregularity",.65,{"min":0.,"max":2.}],
		["cloud_detail","Billow detail",.35,{"min":0.,"max":2.}],
		["cloud_erosion","Edge erosion",.25,{"min":0.,"max":1.}],
		["cloud_softness","Silhouette softness",.12,{"min":.005,"max":.5}],
		["cloud_base","Base altitude (local fraction)",.1,{"min":0.,"max":.95}],
		["cloud_thickness","Layer thickness",.8,{"min":.01,"max":1.}],
		["cloud_profile","Vertical density profile",1.,{"min":.1,"max":8.}],
		["cloud_stretch","Streak direction / scale",Vector3(5.,1.,1.),{}],
		["cloud_ground_height","Ground elevation (world m)",0.,{}],
		["cloud_follow_ground","Follow scene collision surfaces",false,{"tooltip":"Samples a cached 16² height field from configured timeline colliders. Missing surfaces use Ground elevation."}],
		["cloud_ground_search","Surface search range (m)",1000.,{"min":1.,"max":10000.}],
		["cloud_ground_mask","Surface collision layer mask",1,{"min":1,"max":2147483647}],
		["cloud_ground_falloff","Ground height falloff (m)",2.,{"min":.01,"max":10000.}]
	]
	for row in rows:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[3]); p.options.group="Cloud shape"; p.options.visible_when={"property":"mode","values":[8]}; d.properties.append(p)
	d.find_property(&"seed").options.visible_when={"property":"mode","values":[4,8]}
	d.find_property(&"contrast").options.visible_when={"property":"mode","values":[4,5,7,8]}
	d.find_property(&"threshold").options.visible_when={"property":"mode","values":[4,5,7,8]}

static func prepare(v: Dictionary) -> Dictionary:
	var macro:=FastNoiseLite.new(); macro.seed=int(v.get(&"seed",1)); macro.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; macro.frequency=2.4/maxf(.05,float(v.get(&"cloud_size",1.))); macro.fractal_type=FastNoiseLite.FRACTAL_FBM; macro.fractal_octaves=3
	var detail:=FastNoiseLite.new(); detail.seed=macro.seed+7919; detail.frequency=macro.frequency*3.2; detail.fractal_type=FastNoiseLite.FRACTAL_FBM; detail.fractal_octaves=2
	var fine:=FastNoiseLite.new(); fine.seed=macro.seed+104729; fine.frequency=macro.frequency*9.
	var rng:=RandomNumberGenerator.new(); rng.seed=macro.seed; var lobes: Array[Vector4]=[]
	for i in 10:
		lobes.append(Vector4(.5+rng.randf_range(-.23,.23),rng.randf_range(.24,.68),.5+rng.randf_range(-.23,.23),rng.randf_range(.16,.27)))
	return {"macro":macro,"detail":detail,"fine":fine,"lobes":lobes}

static func sample_density(v: Dictionary,noise: Dictionary,p: Vector3,world: Vector3=Vector3.ZERO) -> float:
	var kind:=int(v.get(&"cloud_type",0)); var base:=float(v.get(&"cloud_base",.1)); var thickness:=maxf(.01,float(v.get(&"cloud_thickness",.8))); var height: float=(p.y-base)/thickness
	if height<0. or height>1.: return 0.
	var q:=p; var softness:=maxf(.005,float(v.get(&"cloud_softness",.12))); var coverage:=clampf(float(v.get(&"cloud_coverage",.55)),0.,1.)
	if coverage<=0.: return 0.
	if kind==2: q/= (v.get(&"cloud_stretch",Vector3(5,1,1)) as Vector3).abs().max(Vector3.ONE*.05)
	var macro: float=noise.macro.get_noise_3dv(q)*.5+.5; var detail: float=noise.detail.get_noise_3dv(q)*.5+.5; var fine: float=noise.fine.get_noise_3dv(q)*.5+.5
	var shape:=0.; var horizontal:=Vector2(p.x-.5,p.z-.5).length()*2.; var vertical:=smoothstep(0.,softness,height)*(1.-smoothstep(1.-softness,1.,height))
	match kind:
		0:
			# Wide flat base, noisy rounded upper lobes, narrowing near the top.
			var point:=Vector3(p.x,height,p.z); var radius_scale:=.55+coverage*.7
			shape=(1.-((point-Vector3(.5,.26,.5))/Vector3(.38,.27,.38)/radius_scale).length())*.25
			for lobe: Vector4 in noise.lobes:
				var distance:=lobe.w*radius_scale-(point-Vector3(lobe.x,lobe.y,lobe.z)).length(); var blend:=clampf(.5+.5*(distance-shape)/.07,0.,1.); shape=lerpf(shape,distance,blend)+.07*blend*(1.-blend)
			shape+=(macro-.5)*float(v.get(&"cloud_macro",.65))*.18+(detail-.5)*float(v.get(&"cloud_detail",.35))*.12
		1: shape=macro-(1.-coverage)*.8-absf(height-.5)*.25+(detail-.5)*float(v.get(&"cloud_detail",.35))*.3
		2:
			var streak:=absf(noise.macro.get_noise_3dv(q*Vector3(1.,3.,5.))); shape=coverage*.35-streak-absf(height-.5)*.3+(detail-.5)*.08
		3: shape=macro+detail*.3-(1.-coverage)*1.1-horizontal*.15+(1.-height)*.15
		4: shape=macro+coverage-.7
		5: shape=1.; vertical*=exp(-height*float(v.get(&"cloud_profile",1.)))
	var edge:=1.-smoothstep(softness,softness*4.,absf(shape)); shape-=fine*float(v.get(&"cloud_erosion",.25))*edge*.35
	var density:=smoothstep(-softness,softness,shape)*pow(maxf(0.,vertical),float(v.get(&"cloud_profile",1.)))
	return clampf(density,0.,1.)
