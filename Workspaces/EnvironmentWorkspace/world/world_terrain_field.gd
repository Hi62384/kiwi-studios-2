extends RefCounted
## Immutable CPU height snapshot. Workers never read a live terrain or SceneTree.
static var cache: Dictionary={}
var resolution:=0
var dimensions:=Vector2.ZERO
var heights:=PackedFloat32Array()
var native_resolution:=0
var native_base:=PackedFloat32Array()
var native_edits:=PackedFloat32Array()
var native_water:=PackedFloat32Array()
var water_resolution:=0
var water_levels:=PackedFloat32Array()
var water_depths:=PackedFloat32Array()
var to_ground:=Transform3D.IDENTITY
var to_world:=Transform3D.IDENTITY
var key:=0
var source_signature:=0
var root_id:=""
var terrain_id:=""
var terrain_input: WeakRef
static func signature(terrain: KiwiEnvironmentTerrain) -> int: return hash([terrain.signature(),terrain.water_key,terrain.water_delta])
static func capture(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary:
	if str(source.terrain_id).is_empty(): return {"error":"","field":null}
	var info:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").context(session,id,source)
	if not info.error.is_empty(): return {"error":info.error,"field":null}
	var terrain:=info.terrain as KiwiEnvironmentTerrain; var source_key:=signature(terrain); var snapshot_key:=hash([source_key,info.to_ground,info.to_world,id,source.terrain_id]); var cache_key:=hash([terrain.get_instance_id(),snapshot_key]); var existing: RefCounted=cache.get(cache_key)
	if terrain.hydrology!=null and terrain.hydrology.enabled and not terrain.water_valid(): return {"error":"Wait for terrain and water generation to finish before updating this world.","field":null}
	if existing!=null: return {"error":"","field":existing}
	var field: RefCounted=load("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").new(); field.key=snapshot_key; field.root_id=id; field.terrain_id=source.terrain_id; field.terrain_input=weakref(terrain); field.source_signature=source_key; field.to_ground=info.to_ground; field.to_world=info.to_world; field.dimensions=terrain.dimensions; field.resolution=mini(129,terrain.resolution); var samples:=PackedFloat32Array(); samples.resize(field.resolution*field.resolution); var native:=terrain.height_snapshot(); field.native_resolution=int(native.resolution); field.native_base=native.base; field.native_edits=native.edits; field.native_water=native.water
	for z in field.resolution:
		for x in field.resolution:
			var point:=Vector2(x,z)/float(field.resolution-1)*(terrain.resolution-1); var cell:=Vector2i(point.floor()); var f:=point-Vector2(cell); samples[x+z*field.resolution]=lerpf(lerpf(terrain.height(cell.x,cell.y),terrain.height(cell.x+1,cell.y),f.x),lerpf(terrain.height(cell.x,cell.y+1),terrain.height(cell.x+1,cell.y+1),f.x),f.y)
	field.heights=samples
	if terrain.hydrology!=null and terrain.hydrology.enabled and terrain.water_data.get("levels",PackedFloat32Array()).size()==terrain.resolution*terrain.resolution and terrain.water_data.get("depth",PackedFloat32Array()).size()==terrain.resolution*terrain.resolution:
		field.water_resolution=terrain.resolution; field.water_levels=terrain.water_data.levels.duplicate(); field.water_depths=terrain.water_data.depth.duplicate()
	if cache.size()>=8: cache.erase(cache.keys()[0])
	cache[cache_key]=field; return {"error":"","field":field}
func sample(point: Vector2) -> Dictionary:
	var local:=to_ground*Vector3(point.x,0.,point.y); var uv:=Vector2(local.x,local.z)/dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1. or resolution<2: return {}
	var grid:=native_resolution if native_resolution>1 else resolution; var p:=uv*(grid-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var height:=lerpf(lerpf(_sample_height(cell.x,cell.y),_sample_height(cell.x+1,cell.y),f.x),lerpf(_sample_height(cell.x,cell.y+1),_sample_height(cell.x+1,cell.y+1),f.x),f.y); var position:=to_world*Vector3(local.x,height,local.z); var dx:=(_sample_height(cell.x+1,cell.y)-_sample_height(cell.x-1,cell.y))/(dimensions.x/(grid-1)*maxi(1,mini(grid-1,cell.x+1)-maxi(0,cell.x-1))); var dz:=(_sample_height(cell.x,cell.y+1)-_sample_height(cell.x,cell.y-1))/(dimensions.y/(grid-1)*maxi(1,mini(grid-1,cell.y+1)-maxi(0,cell.y-1))); var normal: Vector3=(to_world.basis.inverse().transposed()*Vector3(-dx,1.,-dz)).normalized()
	var water:=water_at_uv(uv); var depth:=maxf(0.,float(water.get("level",position.y))-position.y) if not water.is_empty() else 0.; return {"height":position.y,"normal":normal,"water":depth>.03,"water_depth":depth,"water_level":float(water.get("level",position.y))}
func _sample_height(x: int,z: int) -> float:
	if native_resolution<2: return _height(x,z)
	var index:=clampi(x,0,native_resolution-1)+clampi(z,0,native_resolution-1)*native_resolution
	return native_base[index]+(native_edits[index] if index<native_edits.size() else 0.)+(native_water[index] if index<native_water.size() else 0.)
func water_at_uv(uv: Vector2) -> Dictionary:
	if water_resolution<2: return {}
	var p:=uv*(water_resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var level:=0.; var depth:=0.; var weight:=0.
	for z in 2:
		for x in 2:
			var index:=clampi(cell.x+x,0,water_resolution-1)+clampi(cell.y+z,0,water_resolution-1)*water_resolution; var blend: float=(f.x if x==1 else 1.-f.x)*(f.y if z==1 else 1.-f.y)
			if water_depths[index]<=0.: continue
			level+=water_levels[index]*blend; depth+=water_depths[index]*blend; weight+=blend
	if weight<=.000001: return {}
	var local:=uv*dimensions-dimensions*.5; var surface:=to_world*Vector3(local.x,level/weight,local.y); return {"level":surface.y,"depth":depth/weight*to_world.basis.y.length()}
func _height(x: int,z: int) -> float: return heights[clampi(x,0,resolution-1)+clampi(z,0,resolution-1)*resolution]
func valid(session: KiwiEnvironmentSession) -> bool:
	var terrain:=session.environment().terrain(terrain_id); var owner:=session.document.component(root_id); var ground:=session.document.component(terrain_id)
	if terrain_input==null or terrain!=terrain_input.get_ref() or terrain==null or owner==null or ground==null: return false
	if signature(terrain)!=source_signature: return false
	var pose:=session.document.world_transform(ground).affine_inverse()*session.document.world_transform(owner)
	return pose.is_equal_approx(to_ground)
