extends RefCounted
## Local projection of integrated concentration toward the real sun.
## Bounded decal approximation; not native volume-to-surface shadows.
const Fog=preload("res://scripts/actors/fog/fog_actor.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
static func grid_sample(grid: Dictionary,unit: Vector3) -> float:
	var n:=int(grid.n); var p:=unit*n-Vector3.ONE*.5; var base:=Vector3i(p.floor()); var fraction:=p-Vector3(base); var value:=0.; var rho: PackedFloat32Array=grid.density
	for z in 2:
		for y in 2:
			for x in 2:
				var cell: Vector3i=(base+Vector3i(x,y,z)).clamp(Vector3i.ZERO,Vector3i.ONE*(n-1)); var weight: float=(fraction.x if x==1 else 1.-fraction.x)*(fraction.y if y==1 else 1.-fraction.y)*(fraction.z if z==1 else 1.-fraction.z); value+=rho[cell.x+n*(cell.y+n*cell.z)]*weight
	return value

static func sample_density(world: Vector3,pose: Transform3D,size: Vector3,source: Dictionary,grid: Dictionary) -> float:
	var unit: Vector3=(pose.affine_inverse()*world)/size+Vector3.ONE*.5
	if not AABB(Vector3.ZERO,Vector3.ONE).has_point(unit): return 0.
	if not grid.is_empty(): return grid_sample(grid,unit)
	if source.is_empty(): return 1.
	var v: Dictionary=source["values"]
	var motion: Dictionary=source.get("motion",{}); var time:=float(source.get("time",0.)); var sampled_world:=world; var sampled_unit:=unit
	if int(motion.get(&"fog_motion_mode",0)) in [1,3]:
		var wind: Vector3=(motion.get(&"fog_wind",Vector3.ZERO) as Vector3)*float(motion.get(&"fog_wind_influence",1.)); var frequency:=float(motion.get(&"fog_gust_frequency",1.)); var elapsed:=time+float(motion.get(&"fog_gust_strength",0.))*(1.-cos(time*frequency))/maxf(.000001,frequency) if frequency>0. else time
		var rotation:=Basis.from_euler((motion.get(&"fog_procedural_rotation",Vector3.ZERO) as Vector3)*time*PI/180.); sampled_unit=rotation*(unit-Vector3.ONE*.5)+Vector3.ONE*.5-pose.basis.inverse()*wind*elapsed/size; sampled_world=rotation*(world-pose.origin)+pose.origin-wind*elapsed
	if not v.get(&"enabled",true) or int(v.get(&"target",0))!=0: return 1.
	var strength:=float(v.get(&"strength",1.))
	if not source.mask.is_empty(): strength*=Field.sample_prepared(source.mask,unit,world)
	return Field.combine(1.,Field.sample_prepared(source,sampled_unit,sampled_world),int(v.get(&"combine",1)),strength)

static func interval(origin: Vector3,direction: Vector3,pose: Transform3D,size: Vector3) -> Vector2:
	var inverse:=pose.affine_inverse(); var p:=inverse*origin; var ray:=inverse.basis*direction; var near:=0.; var far:=100000.
	for axis in 3:
		if absf(ray[axis])<.000001:
			if absf(p[axis])>size[axis]*.5: return Vector2(-1,-1)
			continue
		var a: float=(-size[axis]*.5-p[axis])/ray[axis]; var b: float=(size[axis]*.5-p[axis])/ray[axis]; near=maxf(near,minf(a,b)); far=minf(far,maxf(a,b))
	return Vector2(near,far) if far>near else Vector2(-1,-1)

static func sync(runtime: Node,sun: DirectionalLight3D,scene_time: float,exact: bool=false) -> void:
	var fog: FogVolume=runtime.content; var decal:=fog.get_node_or_null("KiwiCloudShadow") as Decal; var values:=ActorAnimation.sampled_values(runtime.actor,runtime.actor.animation_time if not is_nan(runtime.actor.animation_time) else scene_time); var appearance:=Fog.resolve(values.get(&"appearance")); var v: Dictionary=appearance.values if appearance!=null else {}
	var enabled: bool=runtime.active and v.get(&"projected_shadow",false) and sun!=null and fog.material is ShaderMaterial and fog.material.shader==preload("res://scripts/actors/fog/fog_surface.gdshader") and runtime.actor.type_id!=&"global_fog"
	var direction:=sun.global_basis.z.normalized() if sun!=null else Vector3.UP
	if not enabled or direction.y<.08:
		if decal!=null: decal.hide()
		return
	if decal==null: decal=Decal.new(); decal.name="KiwiCloudShadow"; fog.add_child(decal); decal.albedo_mix=1.; decal.normal_fade=0.; decal.upper_fade=.05; decal.lower_fade=.05
	decal.show(); var pose:=fog.global_transform; var size:=fog.size; var grid: Dictionary=fog.get_meta("kiwi_fog_shadow_grid",{}); var field:=Fog.resolve(values.get(&"field")); var source:=Field.prepare_cpu(field.values) if field!=null and grid.is_empty() else {}; var elevation:=float(v.get(&"shadow_ground",0.)); var resolution: int=[16,32][clampi(int(v.get(&"shadow_resolution",0)),0,1)]
	var moving:=not grid.is_empty() or int(values.get(&"fog_motion_mode",0)) in [1,3]
	var key:=hash([pose,size,direction,elevation,resolution,v,float(values.get(&"density",1.)),preload("res://scripts/actors/fog/fog_motion_definition.gd").content(field),not grid.is_empty(),floor(scene_time*8.) if moving and not exact else [grid.get("key",0),scene_time if moving else 0.]])
	if fog.get_meta("cloud_shadow_key",0)==key: return
	if not source.is_empty(): source.motion=values; source.time=scene_time
	fog.set_meta("cloud_shadow_key",key); var started:=Time.get_ticks_usec(); var region:=Rect2(); var first:=true
	for corner in 8:
		var point:=pose*(size*(Vector3(corner&1,(corner>>1)&1,(corner>>2)&1)-Vector3.ONE*.5)); var distance:=(point.y-elevation)/direction.y; var ground:=point-direction*distance; var horizontal:=Vector2(ground.x,ground.z)
		if first: region=Rect2(horizontal,Vector2.ZERO); first=false
		else: region=region.expand(horizontal)
	region.size=region.size.max(Vector2.ONE*.01); var image:=Image.create(resolution,resolution,false,Image.FORMAT_RGBA8); var strength:=float(v.get(&"shadow_strength",.7)); var base_density:=float(values.get(&"density",1.))*float(v.get(&"density_multiplier",1.))*float(v.get(&"opacity",1.))*(1.+float(v.get(&"absorption",0.)))
	for y in resolution:
		for x in resolution:
			var point:=region.position+(Vector2(x,y)+Vector2.ONE*.5)/resolution*region.size; var world:=Vector3(point.x,elevation,point.y); var segment:=interval(world,direction,pose,size); var optical:=0.
			if segment.x>=0.:
				var step: float=(segment.y-segment.x)/16.
				for sample in 16: optical+=sample_density(world+direction*(segment.x+(sample+.5)*step),pose,size,source,grid)*base_density*step
			image.set_pixel(x,y,Color(0,0,0,clampf((1.-exp(-optical))*strength,0.,1.)))
	var texture:=decal.texture_albedo as ImageTexture
	if texture==null or texture.get_width()!=resolution: texture=ImageTexture.create_from_image(image); decal.texture_albedo=texture
	else: texture.update(image)
	decal.global_transform=Transform3D(Basis.IDENTITY,Vector3(region.get_center().x,elevation,region.get_center().y)); decal.size=Vector3(region.size.x,maxf(.05,float(v.get(&"shadow_depth",2.))),region.size.y); decal.cull_mask=int(v.get(&"shadow_cull_mask",1048575)); decal.distance_fade_enabled=true; decal.distance_fade_begin=float(v.get(&"shadow_distance",100.)); decal.distance_fade_length=20.
	fog.set_meta("cloud_shadow_ms",float(Time.get_ticks_usec()-started)/1000.)
