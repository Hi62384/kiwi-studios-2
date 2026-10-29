class_name KiwiTerrainBiomes
extends Resource
## Continuous environmental fields and normalized suitability, never interpolated
## categorical IDs. The climate stage consumes completed ground and water data.
const NAMES:=["Grassland","Forest","Desert","Tropical","Jungle","Savanna","Swamp","Snow / tundra","Alpine","Rocky mountains","Badlands","Volcanic","Coastal beach","Rocky coast"]
const FORMAT_VERSION:=4
const CAVE_NAMES:=["Dry cave","Damp cave","Flooded cave","Cold cave","Limestone cave","Volcanic cave"]
@export var definitions: Array[Dictionary]=[]
@export var fallback_id:="grassland"
@export var cave_fallback_id:="cave_dry"
@export var sea_temperature:=24.
@export var latitude_range:=Vector2(-30,30)
@export var altitude_lapse:=.0065
@export var base_humidity:=.45
@export var climate_region_size:=100.
@export var paint_masks: Dictionary={}
class BaseField extends Resource:
	var resolution: int
	var dimensions: Vector2
	var water_data: Dictionary={}
	var geology:=0
	var values: PackedFloat32Array
	func height(x: int,z: int) -> float: return values[clampi(x,0,resolution-1)+clampi(z,0,resolution-1)*resolution]
	func position(x: int,z: int) -> Vector3: return Vector3((float(x)/(resolution-1)-.5)*dimensions.x,height(x,z),(float(z)/(resolution-1)-.5)*dimensions.y)
	func normal(x: int,z: int) -> Vector3: return Vector3((height(x-1,z)-height(x+1,z))/(dimensions.x/(resolution-1)*2.),1.,(height(x,z-1)-height(x,z+1))/(dimensions.y/(resolution-1)*2.)).normalized()
func landform_signature() -> int:
	for definition in definitions:
		if definition.get("enabled",true) and not (definition.get("landforms",[]) as Array).is_empty(): return climate_signature()
	return 0
func apply_landforms(heights: PackedFloat32Array,n: int,dimensions: Vector2,seed: int,cancel: Callable=Callable(),geology: int=0) -> Dictionary:
	if landform_signature()==0: return {"heights":heights}
	var source:=BaseField.new(); source.values=heights; source.resolution=n; source.dimensions=dimensions; source.geology=geology
	# Freeze climate on unmodified macro terrain. Final biome weights are computed
	# separately after erosion/sculpt/water, so geometry has no feedback cycle.
	var initial:=generate(source,seed,cancel)
	if initial.get("cancelled",false) or not str(initial.get("error","")).is_empty(): return initial
	var output:=heights.duplicate()
	for z in n:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for x in n:
			var index:=x+z*n; var p:=source.position(x,z); var point:=Vector2(p.x,p.z)
			for definition in definitions:
				var id:=str(definition.id)
				if not initial.weights.has(id): continue
				var weight: float=initial.weights[id][index]
				for layer: Dictionary in definition.get("landforms",[]):
					if not layer.get("enabled",true): continue
					var contribution:=KiwiTerrainGenerator._landform(point,layer); var amount:=weight*KiwiTerrainGenerator.mask(point,layer.get("mask",{}))
					match str(layer.get("blend","add")):
						"replace": output[index]=lerpf(output[index],contribution,amount)
						"maximum": output[index]=lerpf(output[index],maxf(output[index],contribution),amount)
						"minimum": output[index]=lerpf(output[index],minf(output[index],contribution),amount)
						_: output[index]+=contribution*amount
	return {"heights":output,"initial_biomes":initial}
func signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([FORMAT_VERSION,definitions,fallback_id,cave_fallback_id,sea_temperature,latitude_range,altitude_lapse,base_humidity,climate_region_size,paint_masks])
func climate_signature() -> int:
	var rules:=[]
	for definition in definitions:
		var rule:=definition.duplicate(); rule.erase("materials"); rule.erase("name"); rules.append(rule)
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([FORMAT_VERSION,rules,fallback_id,cave_fallback_id,sea_temperature,latitude_range,altitude_lapse,base_humidity,climate_region_size,paint_masks])
static func starter(index: int) -> Dictionary:
	index=clampi(index,0,NAMES.size()-1)
	var ids:=["grassland","forest","desert","tropical","jungle","savanna","swamp","snow","alpine","mountains","badlands","volcanic","beach","rocky_coast"]
	var temperatures:=[Vector2(4,30),Vector2(-4,25),Vector2(16,60),Vector2(22,45),Vector2(23,45),Vector2(18,40),Vector2(8,38),Vector2(-80,3),Vector2(-15,12),Vector2(-50,40),Vector2(8,45),Vector2(-80,80),Vector2(0,50),Vector2(-40,40)]
	var humidities:=[Vector2(.2,.75),Vector2(.45,1),Vector2(0,.3),Vector2(.5,1),Vector2(.7,1),Vector2(.12,.5),Vector2(.7,1),Vector2(0,1),Vector2(0,1),Vector2(0,1),Vector2(0,.4),Vector2(0,1),Vector2(0,1),Vector2(0,1)]
	var slopes:=[Vector2(0,35),Vector2(0,45),Vector2(0,50),Vector2(0,55),Vector2(0,45),Vector2(0,30),Vector2(0,8),Vector2(0,60),Vector2(15,70),Vector2(35,90),Vector2(12,75),Vector2(0,90),Vector2(0,15),Vector2(25,90)]
	var result:={"id":ids[index],"name":NAMES[index],"enabled":true,"temperature":temperatures[index],"humidity":humidities[index],"altitude":Vector2(-10000,10000),"slope":slopes[index],"shore_distance":Vector2(-10000,8) if index in [6,12,13] else Vector2(-100000,100000),"roughness":Vector2(0,10000),"frequency":.2 if index in [10,11] else 1.,"region_size":80.,"transition":.2,"weight":1.,"materials":[]}
	if index==11: result["geology"]=[4,5]
	if index==10: result["geology"]=[3]
	return result
static func cave_starter(index: int) -> Dictionary:
	index=clampi(index,0,CAVE_NAMES.size()-1); var result:=starter(0); result.id="cave_"+["dry","damp","flooded","cold","limestone","volcanic"][index]; result.name=CAVE_NAMES[index]; result["domain"]="cave"; result.temperature=Vector2(-100,100); result.humidity=Vector2(0,1); result.slope=Vector2(0,180); result["cave_depth"]=Vector2(0,10000); result["surface_type"]="any"; result["submersion"]=Vector2(-10000,10000); result.region_size=40.; var material:=StandardMaterial3D.new(); material.albedo_color=[Color("625b52"),Color("30433c"),Color("354652"),Color("9fbbc7"),Color("b2a788"),Color("29201d")][index]; material.roughness=.9; result.materials=[material]
	if index==0: result.humidity=Vector2(0,.65); result.submersion=Vector2(-10000,0)
	if index==1: result.humidity=Vector2(.6,1.)
	if index==2: result.submersion=Vector2(0,10000)
	if index==3: result.temperature=Vector2(-100,4)
	if index==4: result["geology"]=[2]
	if index==5: result["geology"]=[4,5]
	return result
func validate() -> PackedStringArray:
	var errors:=PackedStringArray(); var ids:={}
	if not is_finite(sea_temperature) or not is_finite(base_humidity) or not latitude_range.is_finite() or not is_finite(altitude_lapse) or not is_finite(climate_region_size): errors.append("Climate values must be finite.")
	for definition in definitions:
		var id:=str(definition.get("id",""))
		if id.is_empty() or ids.has(id): errors.append("Every biome needs a unique stable ID.")
		ids[id]=true
		for key in ["frequency","region_size","transition","weight"]:
			if not is_finite(float(definition.get(key,1.))): errors.append("Biome suitability values must be finite.")
		var generator:=KiwiTerrainGenerator.new(); generator.layers.assign(definition.get("landforms",[])); errors.append_array(generator.validate())
		for key in ["temperature","humidity","altitude","slope","shore_distance","roughness"]:
			var limits: Vector2=definition.get(key,Vector2(-100000,100000))
			if not limits.is_finite() or limits.x>limits.y: errors.append("Biome ranges must be finite and ordered.")
	return errors
func generate(terrain: Resource,seed: int,cancel: Callable=Callable()) -> Dictionary:
	var errors:=validate()
	if not errors.is_empty(): return {"error":"\n".join(errors)}
	var n: int=terrain.resolution; var count:=n*n; var temperatures:=PackedFloat32Array(); temperatures.resize(count); var humidities:=PackedFloat32Array(); humidities.resize(count); var slopes:=PackedFloat32Array(); slopes.resize(count); var roughness:=PackedFloat32Array(); roughness.resize(count); var weights: Dictionary={}; var noises: Dictionary={}; var fallback:=""
	var climate:=FastNoiseLite.new(); climate.seed=seed; climate.frequency=1./maxf(1.,climate_region_size)
	for definition in definitions:
		if not definition.get("enabled",true) or definition.get("domain","surface")!="surface": continue
		var id:=str(definition.id); var values:=PackedFloat32Array(); values.resize(count); weights[id]=values; var noise:=FastNoiseLite.new(); noise.seed=seed+int(hash(id)%1000000); noise.frequency=1./maxf(1.,float(definition.get("region_size",80.))); noises[id]=noise
	var water: Dictionary=terrain.water_data; var moisture: PackedFloat32Array=water.get("moisture",PackedFloat32Array()); var shore: PackedFloat32Array=water.get("shore_distance",PackedFloat32Array())
	for z in n:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		for x in n:
			var index:=x+z*n; var position: Vector3=terrain.position(x,z); var point:=Vector2(position.x,position.z); var elevation: float=position.y; var slope:=rad_to_deg(acos(clampf((terrain.normal(x,z) as Vector3).y,-1.,1.))); var spacing: Vector2=terrain.dimensions/maxi(1,n-1); var local_roughness:=absf(terrain.height(x-1,z)+terrain.height(x+1,z)-elevation*2.)/(spacing.x*spacing.x)+absf(terrain.height(x,z-1)+terrain.height(x,z+1)-elevation*2.)/(spacing.y*spacing.y); var latitude:=lerpf(latitude_range.x,latitude_range.y,float(z)/maxi(1,n-1)); var temperature:=sea_temperature-absf(latitude)*.35-elevation*altitude_lapse+climate.get_noise_2dv(point)*8.; var humidity:=clampf(base_humidity+climate.get_noise_2d(point.x+1731.,point.y-543.)*.3+(moisture[index] if moisture.size()==count else 0.)*.35,0.,1.)
			temperatures[index]=temperature; humidities[index]=humidity; slopes[index]=slope; roughness[index]=local_roughness
			var sample:=_weights_sample(point,elevation,slope,temperature,humidity,shore[index] if shore.size()==count else 100000.,local_roughness,index,n,noises,{"geology":terrain.geology})
			for id: String in sample: weights[id][index]=sample[id]
	return {"weights":weights,"temperature":temperatures,"humidity":humidities,"slope":slopes,"roughness":roughness,"error":"","cancelled":false}
func noise_fields(seed: int,domain: String="surface") -> Dictionary:
	var result:={}
	for definition in definitions:
		if not definition.get("enabled",true) or definition.get("domain","surface")!=domain: continue
		var id:=str(definition.id); var noise:=FastNoiseLite.new(); noise.seed=seed+int(hash(id)%1000000); noise.frequency=1./maxf(1.,float(definition.get("region_size",80.))); result[id]=noise
	return result
func _weights_sample(point: Vector2,elevation: float,slope: float,temperature: float,humidity: float,shore: float,roughness: float,index: int,n: int,noises: Dictionary,features: Dictionary={}) -> Dictionary:
	var result:={}; var total:=0.; var fallback:=""
	for definition in definitions:
		var id:=str(definition.id)
		if not noises.has(id): continue
		if features.get("domain","surface")=="cave":
			if id==cave_fallback_id: fallback=id
		elif fallback.is_empty() or id==fallback_id: fallback=id
		var transition:=clampf(float(definition.get("transition",.2)),.001,1.); var suitability:=maxf(0.,float(definition.get("weight",1.)))
		for factor in [["temperature",temperature],["humidity",humidity],["altitude",elevation],["slope",slope],["shore_distance",shore],["roughness",roughness]]: suitability*=_range(float(factor[1]),definition.get(factor[0],Vector2(-100000,100000)),transition)
		for key in ["cave_depth","submersion"]:
			if definition.has(key) and features.has(key): suitability*=_range(float(features[key]),definition[key],transition)
		if definition.has("geology") and features.has("geology") and not (definition.geology as Array).has(int(features.geology)): suitability=0.
		if definition.has("surface_type") and str(definition.surface_type)!="any" and str(definition.surface_type)!=str(features.get("surface_type","any")): suitability=0.
		var frequency:=clampf(float(definition.get("frequency",1.)),0.,1.); var noise:=noises[id] as FastNoiseLite; var sampled:=noise.get_noise_3dv(features.noise_position) if features.has("noise_position") else noise.get_noise_2dv(point); var region:=clampf(.5+sampled*.75,0.,1.)
		if frequency<1.: suitability*=smoothstep(1.-frequency-transition*.25,1.-frequency+transition*.25,region) if frequency>0. else 0.
		var mask: PackedFloat32Array=paint_masks.get(id,PackedFloat32Array())
		if not mask.is_empty(): suitability=lerpf(suitability,1.,clampf(_mask_at(mask,index%n,index/n,n),0.,1.))
		result[id]=suitability; total+=suitability
	if total<=.000001 and not fallback.is_empty(): result[fallback]=1.; total=1.
	if total>0.:
		for id: String in result: result[id]/=total
	return result
func refresh_samples(terrain: Resource,indices: Array,noises: Dictionary) -> void:
	var fields: Dictionary=terrain.biome_data; var n: int=terrain.resolution; var shore: PackedFloat32Array=terrain.water_data.get("shore_distance",PackedFloat32Array())
	if fields.is_empty(): return
	for index: int in indices:
		if index<0 or index>=n*n: continue
		var p: Vector3=terrain.position(index%n,index/n); var values:=_weights_sample(Vector2(p.x,p.z),p.y,fields.slope[index],fields.temperature[index],fields.humidity[index],shore[index] if shore.size()==n*n else 100000.,fields.roughness[index],index,n,noises,{"geology":terrain.geology})
		for id: String in values: fields.weights[id][index]=values[id]
func has_cave_rules() -> bool:
	for definition in definitions:
		if definition.get("enabled",true) and definition.get("domain","surface")=="cave": return true
	return false
static func _range(value: float,limits: Vector2,transition: float) -> float:
	var fade:=maxf(.0001,(limits.y-limits.x)*transition)
	return smoothstep(limits.x-fade,limits.x,value)*(1.-smoothstep(limits.y,limits.y+fade,value))
static func _mask_at(mask: PackedFloat32Array,x: int,z: int,n: int) -> float:
	if mask.size()==n*n: return mask[x+z*n]
	var old_n:=roundi(sqrt(float(mask.size())))
	if old_n<2 or old_n*old_n!=mask.size(): return 0.
	var p:=Vector2(x,z)/maxi(1,n-1)*(old_n-1); var a:=Vector2i(p.floor()).min(Vector2i.ONE*(old_n-2)); var f:=p-Vector2(a)
	return lerpf(lerpf(mask[a.x+a.y*old_n],mask[a.x+1+a.y*old_n],f.x),lerpf(mask[a.x+(a.y+1)*old_n],mask[a.x+1+(a.y+1)*old_n],f.x),f.y)
