extends RefCounted
## Field resources are reused by spatial density and appearance influences.
static var textures: Dictionary={}
static var texture_images: Dictionary={}
static var builds:=0
const MAX_CACHE:=32
const PAINT_SIZE:=32

static func definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"fog_field"; d.display_name="Fog Density Field"
	var rows:=[
		["enabled","Enabled",true,{}],
		["mode","Field",0,{"choices":["Uniform","Height","Radial","Directional","3D noise","Painted / volume texture","Shape mask / composite","Closed mesh mask"]}],
		["combine","Combination",1,{"choices":["Add","Multiply","Maximum","Minimum","Subtract","Replace"]}],
		["target","Affect",0,{"choices":["Density","Color tint","Emission"]}],
		["color","Tint",Color.WHITE,{}],
		["strength","Strength",1.,{"min":0.,"max":8.}],
		["value","Uniform value",1.,{"min":0.,"max":16.}],
		["direction","Direction",Vector3.UP,{}],
		["start","Start",0.,{}], ["end","End",1.,{}],
		["falloff","Falloff",1.,{"min":.01,"max":16.}],
		["invert","Invert",false,{}],
		["world_space","World coordinates",false,{}],
		["scale","Scale",Vector3.ONE,{}], ["offset","Offset",Vector3.ZERO,{}],
		["shape","Mask shape",0,{"choices":["Box","Sphere","Ellipsoid","Cylinder","Cone","Capsule"]}],
		["shape_size","Mask size",Vector3.ONE,{"min":.001}],
		["shape_rotation","Mask rotation (°)",Vector3.ZERO,{}],
		["shape_edge","Mask edge softness",.05,{"min":.0001,"max":1.}],
		["noise_type","Noise",0,{"choices":["Smooth simplex","Perlin","Fractal","Ridged","Cellular","Domain warped"]}],
		["seed","Seed",1,{}], ["frequency","Frequency",3.,{"min":.01,"max":64.}],
		["octaves","Octaves",3,{"min":1,"max":8}], ["lacunarity","Lacunarity",2.,{"min":1.,"max":4.}],
		["gain","Gain",.5,{"min":0.,"max":1.}], ["contrast","Contrast",1.,{"min":.01,"max":16.}],
		["threshold","Threshold",0.,{"min":0.,"max":.99}],
		["resolution","Volume quality",1,{"choices":["Low · 16³","Balanced · 32³","High · 64³","Custom"]}],
		["custom_resolution","Custom volume resolution",32,{"min":8,"max":64,"visible_when":{"property":"resolution","values":[3]}}]
	]
	for row in rows:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],true); p.options.merge(row[3]); p.options.group="Field"; d.properties.append(p)
		if str(p.id) in ["noise_type","seed","frequency","octaves","lacunarity","gain","contrast","threshold"]: p.options.visible_when={"property":"mode","values":[4]}
		if str(p.id) in ["noise_type","seed","frequency","octaves","lacunarity","gain"]: p.options.group="Noise"
		if str(p.id) in ["contrast","threshold"]: p.options.visible_when={"property":"mode","values":[4,5,7]}
		if str(p.id).begins_with("shape"): p.options.visible_when={"property":"mode","values":[6]}; p.options.group="Shape mask"
		if str(p.id) in ["world_space","scale","offset"]: p.options.group="Mapping"
		if str(p.id) in ["resolution","custom_resolution"]: p.options.group="Quality"
		if p.id==&"value": p.options.visible_when={"property":"mode","values":[0]}
		if p.id==&"mode": p.options.refresh_inspector=true
		if p.id==&"resolution": p.options.refresh_inspector=true
	for row in [["brush_radius","Paint radius (voxels)",3.,{"min":.5,"max":16.}],["brush_strength","Paint strength",.5,{"min":0.,"max":1.}],["brush_falloff","Paint falloff",1.,{"min":0.,"max":4.}],["brush_tool","Paint operation",0,{"choices":["Add","Subtract","Set","Smooth","Reset"]}],["paint_plane","Editing plane",0,{"choices":["View","X","Y","Z"]}],["paint_depth","Plane depth",.5,{"min":0.,"max":1.}],["symmetry_x","Mirror X",false,{}],["symmetry_y","Mirror Y",false,{}],["symmetry_z","Mirror Z",false,{}]]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2]); p.options.merge(row[3]); p.options.group="Painting"; p.options.no_keyframes=true; d.properties.append(p)
	var p:=ActorProperty.create(&"volume","3D texture",""); p.options.merge({"group":"Volume","file_picker":true,"extensions":["tres","res"],"native_resource_types":["Texture3D"],"file_resource_mode":"uneditable"}); d.properties.append(p)
	p=ActorProperty.create(&"boundary_mesh","Closed exclusion mesh",""); p.options.merge({"group":"Volume","file_picker":true,"extensions":["tres","res","mesh"],"native_resource_types":["Mesh"],"file_resource_mode":"uneditable","visible_when":{"property":"mode","values":[7]}}); d.properties.append(p)
	p=ActorProperty.create(&"paint","Painted voxels",{}); p.options={"default":{},"fog_paint":true,"group":"Volume"}; d.properties.append(p)
	p=ActorProperty.create(&"mask","Local volume mask",null); p.object_type=&"fog_field"; p.options.group="Mask"; p.options.tooltip="Uses this field as a local-space influence mask. Nested mask chains are not evaluated."; d.properties.append(p)
	preload("res://scripts/actors/fog/fog_cloud_field.gd").extend_definition(d)
	return d

static func noise_for(v: Dictionary) -> FastNoiseLite:
	var n:=FastNoiseLite.new(); var kind:=int(v.get(&"noise_type",0)); n.seed=int(v.get(&"seed",1)); n.frequency=maxf(.01,float(v.get(&"frequency",3.)))
	n.noise_type=FastNoiseLite.TYPE_PERLIN if kind==1 else (FastNoiseLite.TYPE_CELLULAR if kind==4 else FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
	n.fractal_type=FastNoiseLite.FRACTAL_RIDGED if kind==3 else (FastNoiseLite.FRACTAL_FBM if kind in [2,5] else FastNoiseLite.FRACTAL_NONE)
	n.fractal_octaves=clampi(int(v.get(&"octaves",3)),1,8); n.fractal_lacunarity=clampf(float(v.get(&"lacunarity",2.)),1.,4.); n.fractal_gain=clampf(float(v.get(&"gain",.5)),0.,1.)
	n.domain_warp_enabled=kind==5; n.domain_warp_amplitude=.25; n.domain_warp_frequency=n.frequency
	return n

static func texture(v: Dictionary,as_mask: bool=false) -> Texture3D:
	if int(v.get(&"mode",0))==7: return preload("res://scripts/actors/fog/fog_mesh.gd").prepare(str(v.get(&"boundary_mesh",""))).get("texture") as Texture3D
	var path:=str(v.get(&"volume",""))
	if not path.is_empty() and ResourceLoader.exists(path): return ResourceLoader.load(path) as Texture3D
	var cloud_settings:={}
	for name: Variant in v:
		if str(name).begins_with("cloud_"): cloud_settings[name]=v[name]
	var key:=str([v.get(&"noise_type",0),v.get(&"seed",1),v.get(&"frequency",3.),v.get(&"octaves",3),v.get(&"lacunarity",2.),v.get(&"gain",.5),v.get(&"resolution",1),v.get(&"custom_resolution",32),v.get(&"paint",{}),v.get(&"mode",0),cloud_settings,as_mask,mask_signature(v) if as_mask else 0].hash())
	if textures.has(key): return textures[key]
	var quality:=clampi(int(v.get(&"resolution",1)),0,3); var size: int=clampi(int(v.get(&"custom_resolution",32)),8,64) if quality==3 else [16,32,64][quality]; var slices: Array[Image]=[]; var n:=noise_for(v); var paint: Dictionary=v.get(&"paint",{})
	var cloud:=preload("res://scripts/actors/fog/fog_cloud_field.gd").prepare(v) if int(v.get(&"mode",0))==8 else {}
	for z in size:
		var image:=Image.create(size,size,false,Image.FORMAT_RF); var bytes:=PackedByteArray(); bytes.resize(size*size*4)
		for y in size:
			for x in size:
				var paint_point:=Vector3i(((Vector3(x,y,z)+Vector3.ONE*.5)/size*PAINT_SIZE).floor()).clamp(Vector3i.ZERO,Vector3i.ONE*(PAINT_SIZE-1))
				var value:=clampf(n.get_noise_3d(float(x)/size,float(y)/size,float(z)/size)*.5+.5,0.,1.) if int(v.get(&"mode",0))==4 else float(paint.get(paint_point,0.))
				if not cloud.is_empty(): value=preload("res://scripts/actors/fog/fog_cloud_field.gd").sample_density(v,cloud,(Vector3(x,y,z)+Vector3.ONE*.5)/size)
				if as_mask: value=sample_mask(v,(Vector3(x,y,z)+Vector3.ONE*.5)/size,n,paint,size,cloud)
				bytes.encode_float((y*size+x)*4,value)
		image.set_data(size,size,false,Image.FORMAT_RF,bytes); slices.append(image)
	var result:=ImageTexture3D.new(); result.create(Image.FORMAT_RF,size,size,size,false,slices); builds+=1
	if textures.size()>=MAX_CACHE:
		var first: Variant=textures.keys()[0]; texture_images.erase(textures[first].get_instance_id()); textures.erase(first)
	texture_images[result.get_instance_id()]=slices
	textures[key]=result; return result

static func prepare_cpu(v: Dictionary,depth: int=0) -> Dictionary:
	var images: Array[Image]=[]; var kind:=int(v.get(&"mode",0))
	if kind==7: images.assign(preload("res://scripts/actors/fog/fog_mesh.gd").prepare(str(v.get(&"boundary_mesh",""))).get("slices",[]))
	elif kind in [4,5,8]:
		var volume:=texture(v)
		if volume!=null:
			if texture_images.has(volume.get_instance_id()): images.assign(texture_images[volume.get_instance_id()])
			else: images=volume.get_data()
	var mask: Dictionary={}; var reference: Variant=v.get(&"mask")
	if reference is ActorObjectReference and depth<3:
		var object:=ActorAnimation.resolve_reference(reference)
		if object!=null: mask=prepare_cpu(object.values,depth+1)
	return {"values":v,"images":images,"mask":mask}

static func sample_volume(images: Array[Image],point: Vector3,repeat: bool=true) -> float:
	if images.is_empty(): return 0.
	var size:=Vector3i(images[0].get_width(),images[0].get_height(),images.size()); var p:=point*Vector3(size)-Vector3.ONE*.5; var base:=Vector3i(p.floor()); var f:=p-Vector3(base); var result:=0.
	for z in 2:
		for y in 2:
			for x in 2:
				var cell:=base+Vector3i(x,y,z)
				if repeat: cell=Vector3i(posmod(cell.x,size.x),posmod(cell.y,size.y),posmod(cell.z,size.z))
				else: cell=cell.clamp(Vector3i.ZERO,size-Vector3i.ONE)
				var weight: float=(f.x if x==1 else 1.-f.x)*(f.y if y==1 else 1.-f.y)*(f.z if z==1 else 1.-f.z); result+=images[cell.z].get_pixel(cell.x,cell.y).r*weight
	return result

static func sample_prepared(source: Dictionary,unit: Vector3,world: Vector3) -> float:
	var v: Dictionary=source["values"]; var kind:=int(v.get(&"mode",0)); var p: Vector3=(world if v.get(&"world_space",false) else unit)*v.get(&"scale",Vector3.ONE)+v.get(&"offset",Vector3.ZERO); var value:=float(v.get(&"value",1.))
	match kind:
		1: value=p.y
		2: value=1.-(p-Vector3.ONE*.5).length()*2.
		3: value=p.dot((v.get(&"direction",Vector3.UP) as Vector3).normalized())
		4,5,7,8:
			value=sample_volume(source.images,p,kind!=7)
			if kind==7 and not AABB(Vector3.ZERO,Vector3.ONE).has_point(p): value=0.
			if kind==8 and int(v.get(&"cloud_type",0)) in [4,5]:
				var ground:=float(v.get(&"cloud_ground_height",0.))
				if source.get("ground") is Image: ground=preload("res://scripts/actors/fog/fog_ground_sampler.gd").sample_height(source.ground,unit)
				var height:=maxf(0.,world.y-ground); var attenuation:=exp(-height/maxf(.01,float(v.get(&"cloud_ground_falloff",2.))))
				value=attenuation if int(v.get(&"cloud_type",0))==5 else value*attenuation
		6:
			var distance:=shape_distance(Basis.from_euler((v.get(&"shape_rotation",Vector3.ZERO) as Vector3)*PI/180.).inverse()*(p-Vector3.ONE*.5),v.get(&"shape_size",Vector3.ONE),int(v.get(&"shape",0))); value=smoothstep(0.,maxf(.0001,float(v.get(&"shape_edge",.05))),-distance)
	if kind in [1,2,3]: value=pow(clampf((value-float(v.get(&"start",0.)))/maxf(.0001,float(v.get(&"end",1.))-float(v.get(&"start",0.))),0.,1.),maxf(.01,float(v.get(&"falloff",1.))))
	if kind in [4,5,7,8]: value=pow(maxf(0.,value-float(v.get(&"threshold",0.))),maxf(.01,float(v.get(&"contrast",1.))))
	return maxf(0.,1.-value if v.get(&"invert",false) else value)

static func mask_signature(v: Dictionary) -> int:
	return [v.get(&"scale",Vector3.ONE),v.get(&"offset",Vector3.ZERO),v.get(&"direction",Vector3.UP),v.get(&"start",0.),v.get(&"end",1.),v.get(&"falloff",1.),v.get(&"invert",false),v.get(&"contrast",1.),v.get(&"threshold",0.),v.get(&"value",1.),v.get(&"shape",0),v.get(&"shape_size",Vector3.ONE),v.get(&"shape_rotation",Vector3.ZERO),v.get(&"shape_edge",.05)].hash()
static func sample_mask(v: Dictionary,point: Vector3,noise: FastNoiseLite,paint: Dictionary,size: int,cloud: Dictionary={}) -> float:
	var p: Vector3=point*v.get(&"scale",Vector3.ONE)+v.get(&"offset",Vector3.ZERO); var mode:=int(v.get(&"mode",0)); var value:=float(v.get(&"value",1.))
	match mode:
		1: value=p.y
		2: value=1.-(p-Vector3.ONE*.5).length()*2.
		3: value=p.dot((v.get(&"direction",Vector3.UP) as Vector3).normalized())
		4: value=clampf(noise.get_noise_3dv(p)*.5+.5,0.,1.)
		5: value=float(paint.get(Vector3i((p*PAINT_SIZE).floor()).clamp(Vector3i.ZERO,Vector3i.ONE*(PAINT_SIZE-1)),0.))
		8: value=preload("res://scripts/actors/fog/fog_cloud_field.gd").sample_density(v,cloud,p) if not cloud.is_empty() else 0.
		6:
			var distance:=shape_distance(Basis.from_euler((v.get(&"shape_rotation",Vector3.ZERO) as Vector3)*PI/180.).inverse()*(p-Vector3.ONE*.5),v.get(&"shape_size",Vector3.ONE),int(v.get(&"shape",0)))
			value=smoothstep(0.,maxf(.0001,float(v.get(&"shape_edge",.05))),-distance)
	if mode in [1,2,3]: value=pow(clampf((value-float(v.get(&"start",0.)))/maxf(.0001,float(v.get(&"end",1.))-float(v.get(&"start",0.))),0.,1.),maxf(.01,float(v.get(&"falloff",1.))))
	if mode>=4: value=pow(maxf(0.,value-float(v.get(&"threshold",0.))),maxf(.01,float(v.get(&"contrast",1.))))
	return clampf(1.-value if v.get(&"invert",false) else value,0.,1.)

static func shape_distance(p: Vector3,dimensions: Vector3,shape: int) -> float:
	var extent:=dimensions.abs().max(Vector3.ONE*.001)*.5
	match shape:
		1: return p.length()-minf(extent.x,minf(extent.y,extent.z))
		2: return ((p/extent).length()-1.)*minf(extent.x,minf(extent.y,extent.z))
		3: return maxf(Vector2(p.x/extent.x,p.z/extent.z).length()-1.,absf(p.y)/extent.y-1.)*minf(extent.x,minf(extent.y,extent.z))
		4: return maxf(Vector2(p.x/extent.x,p.z/extent.z).length()-(.5-p.y/(extent.y*2.)),absf(p.y)/extent.y-1.)*minf(extent.x,minf(extent.y,extent.z))
		5:
			var r:=minf(extent.x,extent.z); var q:=p; q.y-=clampf(q.y,-maxf(0.,extent.y-r),maxf(0.,extent.y-r)); return q.length()-r
	var q:=p.abs()-extent; return q.max(Vector3.ZERO).length()+minf(maxf(q.x,maxf(q.y,q.z)),0.)

static func paint_dab(source: Dictionary,center: Vector3i,radius: float,strength: float,falloff: float,mode: int) -> Dictionary:
	var result:=source.duplicate(); var extent:=ceili(radius)
	for z in range(maxi(0,center.z-extent),mini(PAINT_SIZE,center.z+extent+1)):
		for y in range(maxi(0,center.y-extent),mini(PAINT_SIZE,center.y+extent+1)):
			for x in range(maxi(0,center.x-extent),mini(PAINT_SIZE,center.x+extent+1)):
				var p:=Vector3i(x,y,z); var distance:=Vector3(p-center).length()/maxf(.5,radius)
				if distance>1.: continue
				var weight:=pow(1.-distance,falloff); var value:=float(source.get(p,0.)); var target:=strength
				match mode:
					0: target=value+strength*weight
					1: target=value-strength*weight
					2: target=lerpf(value,strength,weight)
					3:
						var average:=value
						for delta in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]: average+=float(source.get(p+delta,0.))
						target=lerpf(value,average/7.,strength*weight)
					4: target=lerpf(value,0.,weight)
				if target<=.0001: result.erase(p)
				else: result[p]=clampf(target,0.,1.)
	return result

static func combine(a: float,b: float,mode: int,strength: float) -> float:
	match mode:
		0: return maxf(0.,a+b*strength)
		1: return maxf(0.,a*lerpf(1.,b,clampf(strength,0.,1.)))
		2: return lerpf(a,maxf(a,b),clampf(strength,0.,1.))
		3: return lerpf(a,minf(a,b),clampf(strength,0.,1.))
		4: return maxf(0.,a-b*strength)
	return maxf(0.,lerpf(a,b,clampf(strength,0.,1.)))
