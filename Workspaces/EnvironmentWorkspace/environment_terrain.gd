class_name KiwiEnvironmentTerrain
extends Resource
## Procedural base and authored edits are distinct. Runtime chunks share edge
## heights/normals; brush history stores only changed samples.
const CHUNK_CELLS:=32
const VOLUME_FORMAT_VERSION:=1
const BASE_CACHE_BYTES:=64*1024*1024
const MAX_RESOLUTION:=1025
const PROXY_RESOLUTION:=129
const GEOLOGY:=["Mixed","Granite","Limestone","Sandstone","Basalt","Volcanic"]
static var _base_cache: Dictionary={}
static var _base_cache_size:=0
static var _base_cache_mutex:=Mutex.new()
@export var dimensions:=Vector2(32,32)
@export var resolution:=65
@export var seed:=1
@export_enum("Mixed","Granite","Limestone","Sandstone","Basalt","Volcanic") var geology:=0
@export var base_height:=0.
@export var amplitude:=0.
@export var frequency:=.05
@export var edits:=PackedFloat32Array()
@export var material_mask:=PackedFloat32Array()
@export var revision:=0
@export var generation: KiwiTerrainGenerator
@export var erosion: Array[KiwiTerrainErosion]=[]
@export var hydrology: KiwiTerrainHydrology
@export var water_delta:=PackedFloat32Array()
@export var water_data: Dictionary={}
@export var water_key:=0
@export var biomes: KiwiTerrainBiomes
@export var biome_data: Dictionary={}
@export var biome_key:=0
@export var cave_biome_data: Dictionary={}
@export var cave_biome_key:=0
@export var chunk_keys: Dictionary={}
@export var chunk_keys_stamp:=0
var _tracked_key_edits:=false
var water_status:=""
@export var caves: Array[KiwiTerrainCave]=[]
@export var voxel_height:=.5
@export var voxel_cell_budget:=500000
@export var lod_enabled:=true
@export var lod_bias:=1.
@export var render_distance:=0.
@export var volume_chunks: Dictionary={}
var volume_status:=""
var volume_chunks_rebuilt:=0
var _volume_validity_key:=0
var _volume_validity:=false
var derived_fields: Dictionary={}
var _base:=PackedFloat32Array()
var _base_key:=0
var dirty_chunks: Dictionary={}
var _chunk_cache: Dictionary={}

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if geology<0 or geology>=GEOLOGY.size(): errors.append("Unknown terrain geology.")
	if not dimensions.is_finite() or dimensions.x<=0. or dimensions.y<=0.: errors.append("Terrain dimensions must be positive finite values.")
	if resolution<3 or resolution>MAX_RESOLUTION: errors.append("Terrain resolution must be from 3 to %d samples per side."%MAX_RESOLUTION)
	if not is_finite(amplitude) or not is_finite(frequency) or not is_finite(base_height): errors.append("Terrain generation values must be finite.")
	if generation!=null: errors.append_array(generation.validate())
	if hydrology!=null: errors.append_array(hydrology.validate())
	if biomes!=null: errors.append_array(biomes.validate())
	for cave in caves:
		if cave!=null: errors.append_array(cave.validate())
	return errors

func erosion_signature() -> int:
	var values:=[]
	for operation in erosion: values.append(operation.signature())
	return hash(values)
func cave_signature() -> int:
	var values:=[]
	for cave in caves: values.append(cave.signature() if cave!=null else 0)
	return hash([values,voxel_height,voxel_cell_budget])
func signature() -> int: return hash([dimensions,resolution,seed,geology,base_height,amplitude,frequency,edits,material_mask,generation.signature() if generation!=null else 0,erosion_signature(),cave_signature(),lod_enabled,lod_bias,render_distance,hydrology.signature() if hydrology!=null else 0,biomes.signature() if biomes!=null else 0])
func climate_key() -> int: return hash([_base_key,edits,water_key,biomes.climate_signature() if biomes!=null else 0])
func cave_climate_key() -> int: return hash([1,climate_key(),cave_signature(),geology])
func cave_biomes_valid() -> bool:
	if biomes==null or caves.is_empty() or not biomes.has_cave_rules(): return true
	return biomes_valid() and cave_biome_key==cave_climate_key()
func prepare_cave_biomes(cancel: Callable=Callable()) -> bool:
	if biomes==null or caves.is_empty() or not biomes.has_cave_rules(): cave_biome_data={}; cave_biome_key=0; return true
	if cave_biomes_valid(): return true
	var data:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_biomes.gd").generate(self,cancel)
	if data.get("cancelled",false): return false
	if not str(data.get("error","")).is_empty(): volume_status=str(data.error); return false
	cave_biome_data=data; cave_biome_key=cave_climate_key(); return true
func cave_biome_at(point: Vector3) -> Dictionary: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_biomes.gd").query(self,point)
func biomes_valid() -> bool:
	prepare(); return biomes==null or (water_valid() and biome_key==climate_key() and not biome_data.is_empty())
func prepare_biomes(cancel: Callable=Callable()) -> bool:
	if biomes==null: biome_data={}; biome_key=0; return true
	if biomes_valid(): return true
	var result:=biomes.generate(self,seed,cancel)
	if result.get("cancelled",false): return false
	if not str(result.get("error","")).is_empty(): water_status=str(result.error); return false
	biome_data=result; biome_key=climate_key(); return true
func biome_at(point: Vector2) -> Dictionary:
	if biomes==null or biome_data.is_empty(): return {}
	var uv:=point/dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1.: return {}
	var p:=uv*(resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var output:={}
	for id: String in biome_data.get("weights",{}):
		var values: PackedFloat32Array=biome_data.weights[id]; var value:=0.
		for z in 2:
			for x in 2: value+=values[mini(cell.x+x,resolution-1)+mini(cell.y+z,resolution-1)*resolution]*(f.x if x==1 else 1.-f.x)*(f.y if z==1 else 1.-f.y)
		output[id]=value
	return output
func hydrology_key() -> int: return hash([2,_base_key,edits,cave_signature(),hydrology.geometry_signature() if hydrology!=null else 0])
func water_valid() -> bool:
	prepare(); return hydrology==null or (water_key==hydrology_key() and water_delta.size()==resolution*resolution)
func height_snapshot() -> Dictionary:
	# Duplicate the packed buffers: GDScript assignments share mutable arrays.
	# This avoids per-sample UI conversion while giving workers private data.
	prepare(); return {"resolution":resolution,"base":_base.duplicate(),"edits":edits.duplicate(),"water":water_delta.duplicate() if hydrology!=null and hydrology.enabled and water_delta.size()==resolution*resolution else PackedFloat32Array()}
func prepare_water(cancel: Callable=Callable()) -> bool:
	prepare(cancel); water_status=""
	if hydrology==null: water_delta=PackedFloat32Array(); water_data={}; water_key=0; return true
	var key:=hydrology_key()
	if water_key==key and water_delta.size()==resolution*resolution: return true
	var ground:=PackedFloat32Array(); ground.resize(resolution*resolution)
	for index in ground.size(): ground[index]=_base[index]+edits[index]
	var source:=ground
	if hydrology.enabled and not caves.is_empty():
		var exposed:=_water_cave_ground(ground,cancel)
		if not exposed.has("ground"): return false
		source=exposed.ground
	var result:=hydrology.generate(source,resolution,dimensions,seed,cancel)
	if bool(result.get("cancelled",false)): return false
	if not str(result.get("error","")).is_empty(): water_status=str(result.error); return false
	var previous_delta:=water_delta; var previous_data:=water_data; water_delta=result.delta
	for index in ground.size(): water_delta[index]+=source[index]-ground[index]
	result.erase("delta"); water_data=result
	if hydrology.enabled and not caves.is_empty():
		var cave_water:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").generate(self,cancel)
		if cave_water.get("cancelled",false) or not str(cave_water.get("error","")).is_empty(): water_status=str(cave_water.get("error","")); water_delta=previous_delta; water_data=previous_data; return false
		if cave_water.has("mesh"): water_data.mesh=cave_water.mesh; cave_water.erase("mesh"); water_data["cave_volume"]=cave_water
	water_key=key; mark_all_dirty(); return true
func _water_cave_ground(ground: PackedFloat32Array,cancel: Callable) -> Dictionary:
	var output:=ground.duplicate(); var lower:=INF; var sources: Array[KiwiTerrainCave]=[]
	for cave in caves:
		if cave==null or not cave.enabled: continue
		cave.prepare(); sources.append(cave); lower=minf(lower,cave.bounds().position.y)
	if sources.is_empty(): return {"ground":output}
	var step:=maxf(.05,minf(.25,voxel_height*.5)); var samples:=0
	for z in resolution:
		if cancel.is_valid() and cancel.call(): return {}
		for x in resolution:
			var index:=x+z*resolution; var point:=Vector3((float(x)/(resolution-1)-.5)*dimensions.x,ground[index],(float(z)/(resolution-1)-.5)*dimensions.y); var distance:=_water_void_distance(point,sources)
			if distance>=0.: continue
			var above:=point.y
			while point.y>lower-step:
				samples+=1
				if samples>maxi(1000,voxel_cell_budget): water_status="Cave water sampling budget exceeded. Reduce extent or increase the voxel budget."; return {}
				if samples%128==0 and cancel.is_valid() and cancel.call(): return {}
				point.y-=step
				if _water_void_distance(point,sources)>=0.:
					var below:=point.y
					for iteration in 12:
						point.y=(above+below)*.5
						if _water_void_distance(point,sources)<0.: above=point.y
						else: below=point.y
					output[index]=(above+below)*.5; break
				above=point.y
	return {"ground":output}
static func _water_void_distance(point: Vector3,sources: Array[KiwiTerrainCave]) -> float:
	var result:=INF
	for cave in sources: result=minf(result,cave.distance(point))
	return result
func water_at(point: Vector3) -> Dictionary:
	if hydrology==null or not hydrology.enabled or water_data.is_empty() or not water_data.has("levels"): return {}
	var uv:=Vector2(point.x,point.z)/dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1.: return {}
	var p:=uv*(resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var level:=0.; var sum:=0.; var flow:=Vector2.ZERO; var depths: PackedFloat32Array=water_data.depth; var levels: PackedFloat32Array=water_data.levels; var flows: PackedVector2Array=water_data.flow
	for z in 2:
		for x in 2:
			var index:=mini(cell.x+x,resolution-1)+mini(cell.y+z,resolution-1)*resolution; var weight: float=(f.x if x==1 else 1.-f.x)*(f.y if z==1 else 1.-f.y)
			if depths[index]<=0.: continue
			level+=levels[index]*weight; flow+=flows[index]*weight; sum+=weight
	if sum<=.000001: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").query(self,point)
	level/=sum; flow/=sum; var ground:=float(sample(Vector2(point.x,point.z)).height)
	if point.y<ground: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").query(self,point)
	if ground>=level: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave_water.gd").query(self,point)
	return {"surface":Vector3(point.x,level,point.z),"depth":level-ground,"flow":Vector3(flow.x,0,flow.y),"inside":point.y<=level and point.y>=ground,"bottom":ground}

func chunk_bounds(coordinate: Vector2i) -> AABB:
	var start:=coordinate*CHUNK_CELLS; var cells:=Vector2i(mini(CHUNK_CELLS,resolution-1-start.x),mini(CHUNK_CELLS,resolution-1-start.y)); var spacing:=dimensions/(resolution-1)
	return AABB(Vector3((float(start.x)/(resolution-1)-.5)*dimensions.x,-100000.,(float(start.y)/(resolution-1)-.5)*dimensions.y),Vector3(cells.x*spacing.x,200000.,cells.y*spacing.y)).grow(.001)
func needs_volume(coordinate: Vector2i) -> bool:
	var region:=chunk_bounds(coordinate)
	for cave in caves:
		if cave!=null and cave.enabled and cave.bounds().intersects(region): return true
	return false
func _local_samples_key(coordinate: Vector2i,materials: bool) -> int:
	var start:=coordinate*CHUNK_CELLS-Vector2i.ONE; var end:=(coordinate+Vector2i.ONE)*CHUNK_CELLS+Vector2i.ONE; start=start.max(Vector2i.ZERO); end=end.min(Vector2i.ONE*(resolution-1)); var samples:=PackedFloat32Array()
	for z in range(start.y,end.y+1):
		for x in range(start.x,end.x+1): samples.append(material_mask[x+z*resolution] if materials else height(x,z))
	return hash(samples)
func volume_key(coordinate: Vector2i) -> int:
	var region:=chunk_bounds(coordinate); var keys:=[]
	for cave in caves:
		if cave!=null and cave.enabled and cave.bounds().intersects(region): keys.append(cave.local_signature(region))
	return hash([VOLUME_FORMAT_VERSION,coordinate,dimensions,resolution,voxel_height,_local_samples_key(coordinate,false),keys])
func volume_signature() -> int: return hash([_base_key,edits,water_delta,cave_signature()])
func volumes_valid() -> bool:
	prepare()
	var key:=volume_signature()
	if key==_volume_validity_key: return _volume_validity
	_volume_validity_key=key; _volume_validity=false
	for z in ceili(float(resolution-1)/CHUNK_CELLS):
		for x in ceili(float(resolution-1)/CHUNK_CELLS):
			var coordinate:=Vector2i(x,z)
			if needs_volume(coordinate) and (not volume_chunks.has(coordinate) or int(volume_chunks[coordinate].get("key",-1))!=volume_key(coordinate)): return false
	_volume_validity=true; return true
func prepare_volumes(cancel: Callable=Callable(),progress: Callable=Callable()) -> bool:
	prepare(cancel); volume_status=""; volume_chunks_rebuilt=0; var live:={}; var used_cells:=0; var used_vertices:=0; var completed:=0; var side:=ceili(float(resolution-1)/CHUNK_CELLS)
	for z in side:
		for x in side:
			if cancel.is_valid() and cancel.call(): return false
			var coordinate:=Vector2i(x,z)
			if needs_volume(coordinate):
				live[coordinate]=true; var key:=volume_key(coordinate); var data: Dictionary=volume_chunks.get(coordinate,{})
				if int(data.get("key",-1))!=key:
					data=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_volume_mesher.gd").new().build(self,coordinate,caves,voxel_height,maxi(1,voxel_cell_budget-used_cells),cancel)
					if bool(data.get("cancelled",false)): return false
					if not str(data.get("error","")).is_empty(): volume_status=str(data.error); return false
					data.key=key; volume_chunks[coordinate]=data; volume_chunks_rebuilt+=1; chunk_keys.erase(coordinate); _tracked_key_edits=true
				used_cells+=int(data.get("cells",0)); used_vertices+=(data.get("vertices",PackedVector3Array()) as PackedVector3Array).size()
				if used_cells>voxel_cell_budget or used_vertices>500000: volume_status="Cave geometry budget exceeded. Reduce its extent or voxel detail."; return false
			completed+=1
			if progress.is_valid(): progress.call(float(completed)/maxi(1,side*side))
	for coordinate: Vector2i in volume_chunks.keys():
		if not live.has(coordinate): volume_chunks.erase(coordinate); chunk_keys.erase(coordinate); _tracked_key_edits=true
	_volume_validity_key=volume_signature(); _volume_validity=true
	return true
func chunk_geometry_key(coordinate: Vector2i,include_paint: bool=true) -> int:
	if not chunk_keys.has(coordinate):
		var heights:=_local_samples_key(coordinate,false); var mask:=_local_samples_key(coordinate,true); var cave:=volume_key(coordinate) if needs_volume(coordinate) else 0; chunk_keys[coordinate]={false:hash([coordinate,dimensions,resolution,lod_enabled,heights,0,cave]),true:hash([coordinate,dimensions,resolution,lod_enabled,heights,mask,cave])}
	# LOD can be toggled by a direct source edit between chunk queries, without
	# changing any samples or running a complete geometry-key preparation pass.
	return hash([int(chunk_keys[coordinate][include_paint]),lod_enabled])
func _geometry_stamp() -> int: return hash([1,_base_key,dimensions,resolution,edits,water_delta,material_mask,cave_signature(),lod_enabled])
func prepare_geometry_keys(cancel: Callable=Callable()) -> bool:
	prepare(); var stamp:=_geometry_stamp()
	if stamp!=chunk_keys_stamp and not _tracked_key_edits: chunk_keys.clear()
	for z in ceili(float(resolution-1)/CHUNK_CELLS):
		if cancel.is_valid() and cancel.call(): return false
		for x in ceili(float(resolution-1)/CHUNK_CELLS): chunk_geometry_key(Vector2i(x,z))
	chunk_keys_stamp=stamp; _tracked_key_edits=false; return true
func prepare(cancel: Callable=Callable()) -> void:
	resolution=clampi(resolution,3,MAX_RESOLUTION); dimensions=dimensions.abs().max(Vector2.ONE*.01)
	var key:=hash([dimensions,resolution,seed,geology,base_height,amplitude,frequency,generation.signature() if generation!=null else 0,erosion_signature(),biomes.landform_signature() if biomes!=null else 0])
	if _base_key==key and _base.size()==resolution*resolution and edits.size()==resolution*resolution and material_mask.size()==resolution*resolution: return
	_base_key=key; _base=PackedFloat32Array(); _base.resize(resolution*resolution)
	_chunk_cache.clear()
	if material_mask.size()!=resolution*resolution:
		var old:=material_mask; var old_n:=floori(sqrt(float(old.size()))); material_mask=PackedFloat32Array(); material_mask.resize(resolution*resolution)
		if old_n>1 and old_n*old_n==old.size():
			for z in resolution:
				for x in resolution: material_mask[x+z*resolution]=old[roundi(float(x)/(resolution-1)*(old_n-1))+roundi(float(z)/(resolution-1)*(old_n-1))*old_n]
	if edits.size()!=resolution*resolution:
		var old:=edits; var old_n:=floori(sqrt(float(old.size()))); edits=PackedFloat32Array(); edits.resize(resolution*resolution)
		if old_n>1 and old_n*old_n==old.size():
			for z in resolution:
				for x in resolution:
					var p:=Vector2(x,z)/float(resolution-1)*(old_n-1); var a:=Vector2i(p.floor()); var b:=a.min(Vector2i.ONE*(old_n-2)); var f:=p-Vector2(b); edits[x+z*resolution]=lerpf(lerpf(old[b.x+b.y*old_n],old[b.x+1+b.y*old_n],f.x),lerpf(old[b.x+(b.y+1)*old_n],old[b.x+1+(b.y+1)*old_n],f.x),f.y)
	_base_cache_mutex.lock(); var cached: Dictionary=_base_cache.get(key,{}); _base_cache_mutex.unlock()
	if not cached.is_empty():
		_base=cached.heights; derived_fields=cached.fields.duplicate(); mark_all_dirty(); return
	var noise:=FastNoiseLite.new(); noise.seed=seed; noise.frequency=maxf(.000001,frequency); noise.fractal_type=FastNoiseLite.FRACTAL_FBM; noise.fractal_octaves=4
	if generation!=null: generation.prepare(seed,frequency)
	for z in resolution:
		if cancel.is_valid() and cancel.call(): return
		for x in resolution:
			var p:=Vector2(float(x)/(resolution-1)-.5,float(z)/(resolution-1)-.5)*dimensions; _base[x+z*resolution]=generation.value(p,dimensions,amplitude,base_height) if generation!=null else base_height+noise.get_noise_2dv(p)*amplitude
	derived_fields.clear()
	if biomes!=null and biomes.landform_signature()!=0:
		var modified:=biomes.apply_landforms(_base,resolution,dimensions,seed,cancel,geology)
		if bool(modified.get("cancelled",false)) or not modified.has("heights"): return
		_base=modified.heights; derived_fields["initial_biomes"]=modified.get("initial_biomes",{})
	for operation in erosion:
		if not operation.enabled: continue
		var effective:=operation.duplicate(true) as KiwiTerrainErosion; var resistance: float=[1.,.35,.7,1.3,.25,.9][clampi(geology,0,5)]; effective.strength*=resistance; effective.mobility*=resistance; var result:=effective.apply(_base,resolution,dimensions,cancel)
		if bool(result.get("cancelled",false)): return
		_base=result.heights; var fields:=result.duplicate(); fields.erase("heights"); derived_fields[operation.operation_id]=fields
	if generation!=null:
		var foundations:=generation.apply_foundations(_base,resolution,dimensions,cancel)
		if foundations.size()!=_base.size(): return
		_base=foundations
	var bytes:=_base.size()*4+_data_bytes(derived_fields)
	if bytes<=BASE_CACHE_BYTES:
		_base_cache_mutex.lock()
		if not _base_cache.has(key):
			while not _base_cache.is_empty() and (_base_cache_size+bytes>BASE_CACHE_BYTES or _base_cache.size()>=16):
				var oldest: int=_base_cache.keys()[0]; _base_cache_size-=int(_base_cache[oldest].bytes); _base_cache.erase(oldest)
			_base_cache[key]={"heights":_base,"fields":derived_fields.duplicate(),"bytes":bytes}; _base_cache_size+=bytes
		_base_cache_mutex.unlock()
	mark_all_dirty()

static func _data_bytes(data: Variant) -> int:
	if data is PackedFloat32Array or data is PackedInt32Array: return data.size()*4
	if data is PackedVector2Array or data is PackedFloat64Array or data is PackedInt64Array: return data.size()*8
	if data is PackedVector3Array: return data.size()*12
	if data is PackedColorArray or data is PackedVector4Array: return data.size()*16
	if data is PackedByteArray: return data.size()
	var total:=0
	if data is Dictionary:
		for value in data.values(): total+=_data_bytes(value)
	elif data is Array:
		for value in data: total+=_data_bytes(value)
	return total

func mark_all_dirty() -> void:
	if chunk_keys_stamp!=_geometry_stamp(): chunk_keys.clear()
	_tracked_key_edits=false
	dirty_chunks.clear()
	for z in ceili(float(resolution-1)/CHUNK_CELLS):
		for x in ceili(float(resolution-1)/CHUNK_CELLS): dirty_chunks[Vector2i(x,z)]=0
func height(x: int,z: int) -> float:
	if _base.size()!=resolution*resolution or edits.size()!=resolution*resolution: prepare()
	var index:=clampi(x,0,resolution-1)+clampi(z,0,resolution-1)*resolution
	return _base[index]+edits[index]+_water_offset(index)
func _water_offset(index: int) -> float: return water_delta[index] if hydrology!=null and hydrology.enabled and water_delta.size()==resolution*resolution else 0.
func position(x: int,z: int) -> Vector3: return Vector3((float(x)/(resolution-1)-.5)*dimensions.x,height(x,z),(float(z)/(resolution-1)-.5)*dimensions.y)
func normal(x: int,z: int) -> Vector3:
	var dx: float=(height(x+1,z)-height(x-1,z))/(dimensions.x/(resolution-1)*2.); var dz: float=(height(x,z+1)-height(x,z-1))/(dimensions.y/(resolution-1)*2.)
	return Vector3(-dx,1.,-dz).normalized()
func sample(point: Vector2) -> Dictionary:
	prepare(); var uv:=point/dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1.: return {}
	var p:=uv*(resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var h:=lerpf(lerpf(height(cell.x,cell.y),height(cell.x+1,cell.y),f.x),lerpf(height(cell.x,cell.y+1),height(cell.x+1,cell.y+1),f.x),f.y)
	return {"height":h,"normal":normal(cell.x,cell.y)}

func sculpt(center: Vector2,radius: float,strength: float,falloff: float,mode: int,flatten_height: float=0.,options: Dictionary={}) -> Dictionary:
	prepare(); var before:={}; var after:={}; var spacing:=dimensions/(resolution-1); var p:=(center/dimensions+Vector2.ONE*.5)*(resolution-1); var extent:=Vector2(radius,radius)/spacing; var low:=Vector2i((p-extent).floor()).max(Vector2i.ZERO); var high:=Vector2i((p+extent).ceil()).min(Vector2i.ONE*(resolution-1)); var targets:={}
	var noise:=FastNoiseLite.new(); noise.seed=int(options.get("seed",seed)); noise.frequency=1./maxf(.01,radius*.25); var transfers:={}
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var offset: Vector2=(Vector2(x,z)-p)*spacing; var distance: float=maxf(absf(offset.x),absf(offset.y)) if bool(options.get("square",false)) else offset.length()
			if distance>radius: continue
			var weight:=pow(maxf(0.,1.-distance/maxf(.001,radius)),maxf(.01,falloff)); var old:=height(x,z); var next:=old; var index:=x+z*resolution
			match mode:
				0: next=old+strength*weight
				1: next=old-strength*weight
				2: next=lerpf(old,(height(x-1,z)+height(x+1,z)+height(x,z-1)+height(x,z+1))*.25,clampf(strength*weight,0.,1.))
				3: next=lerpf(old,flatten_height,clampf(strength*weight,0.,1.))
				4: next=lerpf(old,float(options.get("target",0.)),clampf(strength*weight,0.,1.))
				5: next=lerpf(old,snappedf(old,maxf(.01,float(options.get("terrace_step",.5)))),clampf(strength*weight,0.,1.))
				6: next=old+noise.get_noise_2dv(center+offset)*strength*weight
				7: next=old+strength*weight*weight
				8: next=old-strength*weight*weight
				9: next=old+(old-(height(x-1,z)+height(x+1,z)+height(x,z-1)+height(x,z+1))*.25)*clampf(strength*weight,0.,.5)
				10:
					var average:=0.
					for dz in [-1,0,1]:
						for dx in [-1,0,1]: average+=height(x+dx,z+dz)
					next=lerpf(old,average/9.,clampf(strength*weight,0.,1.))
				11:
					var lower:=old; var destination:=index
					for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						var neighbor:=Vector2i(x,z)+direction
						if neighbor.x<0 or neighbor.y<0 or neighbor.x>=resolution or neighbor.y>=resolution: continue
						if height(neighbor.x,neighbor.y)<lower: lower=height(neighbor.x,neighbor.y); destination=neighbor.x+neighbor.y*resolution
					var amount:=maxf(0.,old-lower)*clampf(strength*weight,0.,1.)*.25
					if amount>0.: transfers[index]=float(transfers.get(index,0.))-amount; transfers[destination]=float(transfers.get(destination,0.))+amount
				12:
					var image:=options.get("stamp") as Image
					if image!=null and not image.is_empty():
						var uv:=offset/maxf(.001,radius)*.5+Vector2.ONE*.5; var sample:=image.get_pixel(clampi(roundi(uv.x*(image.get_width()-1)),0,image.get_width()-1),clampi(roundi(uv.y*(image.get_height()-1)),0,image.get_height()-1)); next=old+sample.get_luminance()*sample.a*strength*weight
			if is_equal_approx(old,next): continue
			before[index]=edits[index]; after[index]=next-_base[index]-_water_offset(index); targets[index]=after[index]
	for index: int in transfers:
		before[index]=edits[index]; after[index]=edits[index]+float(transfers[index]); targets[index]=after[index]
	apply_samples(targets); return {"before":before,"after":after}

func apply_samples(samples: Dictionary) -> void:
	prepare()
	for index: int in samples:
		if index<0 or index>=edits.size(): continue
		edits[index]=float(samples[index])
	mark_samples_dirty(samples)
func mark_samples_dirty(samples: Dictionary) -> void:
	for index: int in samples:
		var x:=index%resolution; var z:=index/resolution
		for dz in [-1,0,1]:
			for dx in [-1,0,1]:
				var cx:=clampi(x+dx,0,resolution-2)/CHUNK_CELLS; var cz:=clampi(z+dz,0,resolution-2)/CHUNK_CELLS; dirty_chunks[Vector2i(cx,cz)]=revision+1
				chunk_keys.erase(Vector2i(cx,cz))
	if not samples.is_empty(): _tracked_key_edits=true
	if not samples.is_empty(): revision+=1; emit_changed()
func apply_material_samples(samples: Dictionary) -> void:
	prepare()
	for index: int in samples:
		if index>=0 and index<material_mask.size(): material_mask[index]=clampf(float(samples[index]),0.,1.)
	mark_samples_dirty(samples)
func paint_material(center: Vector2,radius: float,strength: float,falloff: float,erase: bool) -> Dictionary:
	prepare(); var before:={}; var after:={}; var spacing:=dimensions/(resolution-1); var p:=(center/dimensions+Vector2.ONE*.5)*(resolution-1); var extent:=Vector2.ONE*radius/spacing; var low:=Vector2i((p-extent).floor()).max(Vector2i.ZERO); var high:=Vector2i((p+extent).ceil()).min(Vector2i.ONE*(resolution-1))
	for z in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var distance:=((Vector2(x,z)-p)*spacing).length()
			if distance>radius: continue
			var index:=x+z*resolution; var weight:=pow(maxf(0.,1.-distance/maxf(.001,radius)),maxf(.01,falloff)); var value:=clampf(material_mask[index]+strength*weight*(-1. if erase else 1.),0.,1.)
			if is_equal_approx(value,material_mask[index]): continue
			before[index]=material_mask[index]; after[index]=value
	apply_material_samples(after); return {"before":before,"after":after}

func chunk_mesh(chunk: Vector2i,cutaway: bool=false,smooth_paint: bool=false) -> ArrayMesh:
	prepare(); var key:=hash([chunk_geometry_key(chunk,not smooth_paint),cutaway,smooth_paint])
	if _chunk_cache.has(chunk) and _chunk_cache[chunk].key==key: return _chunk_cache[chunk].mesh
	if needs_volume(chunk):
		var data: Dictionary=volume_chunks.get(chunk,{})
		if data.is_empty() or int(data.get("key",-1))!=volume_key(chunk):
			volume_status="Cave geometry needs generation."; return ArrayMesh.new()
		var mesh:=_volume_native_mesh(data,cutaway,smooth_paint)
		if lod_enabled: mesh=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_lod.gd").prepare(mesh)
		_chunk_cache[chunk]={"key":key,"mesh":mesh}; return mesh
	var start:=chunk*CHUNK_CELLS; var count:=Vector2i(mini(CHUNK_CELLS,resolution-1-start.x),mini(CHUNK_CELLS,resolution-1-start.y)); var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var uv:=PackedVector2Array(); var indices:=PackedInt32Array(); var painted:=PackedInt32Array()
	if count.x<=0 or count.y<=0: return ArrayMesh.new()
	for z in count.y+1:
		for x in count.x+1: vertices.append(position(start.x+x,start.y+z)); normals.append(normal(start.x+x,start.y+z)); uv.append(Vector2(start.x+x,start.y+z)/(resolution-1))
	for z in count.y:
		for x in count.x:
			var a:=x+z*(count.x+1); var b:=a+1; var c:=a+count.x+1; var d:=c+1; var sample_index:=start.x+x+(start.y+z)*resolution
			var amount: float=(material_mask[sample_index]+material_mask[sample_index+1]+material_mask[sample_index+resolution]+material_mask[sample_index+resolution+1])*.25
			if not smooth_paint and amount>=.5: painted.append_array(PackedInt32Array([a,b,c,b,d,c]))
			else: indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; var mesh:=ArrayMesh.new(); var slots:=PackedInt32Array()
	for slot in 2:
		var triangles:=indices if slot==0 else painted
		if triangles.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX]=triangles; mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); slots.append(slot)
	mesh.set_meta("environment_material_slots",slots)
	if lod_enabled: mesh=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_lod.gd").prepare(mesh)
	_chunk_cache[chunk]={"key":key,"mesh":mesh}; return mesh
func _volume_native_mesh(data: Dictionary,cutaway: bool=false,smooth_paint: bool=false) -> ArrayMesh:
	var base:=PackedInt32Array(); var painted:=PackedInt32Array(); var indices: PackedInt32Array=data.indices; var vertices: PackedVector3Array=data.vertices
	for index in range(0,indices.size(),3):
		if cutaway and (data.get("triangle_kind",PackedByteArray()) as PackedByteArray).size()>index/3 and int(data.triangle_kind[index/3])==0: continue
		var a:=indices[index]; var b:=indices[index+1]; var c:=indices[index+2]; var center: Vector3=(vertices[a]+vertices[b]+vertices[c])/3.; var p: Vector2=((Vector2(center.x,center.z)/dimensions+Vector2.ONE*.5)*(resolution-1)).round(); var point:=Vector2i(p).clamp(Vector2i.ZERO,Vector2i.ONE*(resolution-1))
		if not smooth_paint and material_mask[point.x+point.y*resolution]>=.5: painted.append_array(PackedInt32Array([a,b,c]))
		else: base.append_array(PackedInt32Array([a,b,c]))
	var mesh:=ArrayMesh.new(); var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=data.normals; arrays[Mesh.ARRAY_TEX_UV]=data.uv; var slots:=PackedInt32Array()
	for slot in 2:
		var triangles:=base if slot==0 else painted
		if triangles.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX]=triangles; mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); slots.append(slot)
	mesh.set_meta("environment_material_slots",slots); return mesh

func editable_mesh(cancel: Callable=Callable()) -> KiwiModelMesh:
	prepare(); var mesh:=KiwiModelMesh.new(); mesh.smooth=true
	var side:=resolution if resolution<=257 else PROXY_RESOLUTION
	for z in side:
		if cancel.is_valid() and cancel.call(): return null
		for x in side: mesh.vertices.append(position(roundi(float(x)/(side-1)*(resolution-1)),roundi(float(z)/(side-1)*(resolution-1))))
	for z in side-1:
		if cancel.is_valid() and cancel.call(): return null
		for x in side-1:
			var a:=x+z*side; mesh.add_face(PackedInt32Array([a,a+1,a+side])); mesh.add_face(PackedInt32Array([a+1,a+side+1,a+side]))
	return mesh
