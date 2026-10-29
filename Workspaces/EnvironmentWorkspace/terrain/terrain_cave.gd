class_name KiwiTerrainCave
extends Resource
## Editable void geometry in terrain-local coordinates. Negative distance is air
## inside the tunnel/chamber; the terrain mesher subtracts this from solid ground.
@export var cave_id:=ActorData.new_id()
@export var title:="Cave"
@export var enabled:=true
@export var seed:=1
@export var radius:=2.
@export var radius_variation:=.15
@export var junction_smoothing:=.4
@export var roughness:=.15
@export var detail_frequency:=.7
@export var paths: Array[PackedVector3Array]=[]
@export var chambers:=PackedVector4Array() # center.xyz, radius.w
@export var edits: Array[Dictionary]=[] # signed spherical dig/fill operations
var _noise: FastNoiseLite
func signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([cave_id,title,enabled,seed,radius,radius_variation,junction_smoothing,roughness,detail_frequency,paths,chambers,edits])
func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if radius<=0. or not is_finite(radius): errors.append("Cave radius must be positive and finite.")
	for path in paths:
		if path.size()<2: errors.append("Cave tunnel paths need at least two points.")
		for point in path:
			if not point.is_finite(): errors.append("Cave points must be finite."); break
	for chamber in chambers:
		if not chamber.is_finite() or chamber.w<=0.: errors.append("Cave chambers need finite centers and a positive radius.")
	return errors
func prepare() -> void:
	_noise=FastNoiseLite.new(); _noise.seed=seed; _noise.frequency=maxf(.001,detail_frequency)
func segment_radius(index: int) -> float: return maxf(.05,radius*(1.+clampf(radius_variation,0.,.5)*sin(float(seed)*1.713+index*2.399)))
func bounds() -> AABB:
	var bounds:=AABB(); var first:=true; var margin:=maxf(.05,radius)*(1.+clampf(radius_variation,0.,.5))+absf(roughness)+maxf(0.,junction_smoothing)
	for path in paths:
		for point in path:
			var box:=AABB(point-Vector3.ONE*margin,Vector3.ONE*margin*2.); bounds=box if first else bounds.merge(box); first=false
	for chamber in chambers:
		var center:=Vector3(chamber.x,chamber.y,chamber.z); var size:=Vector3.ONE*(chamber.w+absf(roughness)+maxf(0.,junction_smoothing)); var box:=AABB(center-size,size*2.); bounds=box if first else bounds.merge(box); first=false
	for edit in edits:
		var center: Vector3=edit.get("center",Vector3.ZERO); var size:=Vector3.ONE*maxf(.01,float(edit.get("radius",1.))); var box:=AABB(center-size,size*2.); bounds=box if first else bounds.merge(box); first=false
	return bounds
func distance(point: Vector3) -> float:
	var result:=_raw_distance(point)
	if not is_finite(result): return result
	var weight:=0.; var step:=0.
	for edit in edits:
		if not bool(edit.get("smooth",false)): continue
		var radius:=maxf(.01,float(edit.get("radius",1.))); var distance:=point.distance_to(edit.get("center",Vector3.ZERO))/radius
		if distance>=1.: continue
		var influence:=pow(1.-distance,2.)*clampf(float(edit.get("strength",1.)),0.,1.); weight=1.-(1.-weight)*(1.-influence); step=maxf(step,radius*.15)
	if weight<=0.: return result
	var x:=Vector3(step,0,0); var y:=Vector3(0,step,0); var z:=Vector3(0,0,step); var average:=(_raw_distance(point+x)+_raw_distance(point-x)+_raw_distance(point+y)+_raw_distance(point-y)+_raw_distance(point+z)+_raw_distance(point-z))/6.
	return lerpf(result,average,weight)
func _raw_distance(point: Vector3) -> float:
	var distance:=INF
	for path in paths:
		for index in path.size()-1:
			var a:=path[index]; var b:=path[index+1]; var direction:=b-a; var t:=clampf((point-a).dot(direction)/maxf(.000001,direction.length_squared()),0.,1.); var radius:=lerpf(segment_radius(index),segment_radius(index+1),t); var sample:=point.distance_to(a+direction*t)-radius; distance=_smooth_min(distance,sample,maxf(0.,junction_smoothing))
	for chamber in chambers: distance=_smooth_min(distance,point.distance_to(Vector3(chamber.x,chamber.y,chamber.z))-chamber.w,maxf(0.,junction_smoothing))
	if is_finite(distance) and _noise!=null and roughness!=0.: distance+=_noise.get_noise_3dv(point)*roughness
	for edit in edits:
		if bool(edit.get("smooth",false)): continue
		var sample:=point.distance_to(edit.get("center",Vector3.ZERO))-maxf(.01,float(edit.get("radius",1.)))
		var changed:=maxf(distance,-sample) if bool(edit.get("fill",false)) else _smooth_min(distance,sample,maxf(0.,junction_smoothing))
		distance=lerpf(distance,changed,clampf(float(edit.get("strength",1.)),0.,1.)) if is_finite(distance) else changed
	return distance
func local_signature(region: AABB) -> int:
	var values: Array=[enabled,seed,radius,radius_variation,junction_smoothing,roughness,detail_frequency]; var margin:=maxf(.05,radius)*(1.+clampf(radius_variation,0.,.5))+absf(roughness)+maxf(0.,junction_smoothing)
	for path in paths:
		for index in path.size()-1:
			var box:=AABB(path[index],Vector3.ZERO).expand(path[index+1]).grow(margin)
			if box.intersects(region): values.append([path[index],path[index+1],segment_radius(index),segment_radius(index+1)])
	for chamber in chambers:
		var center:=Vector3(chamber.x,chamber.y,chamber.z); var radius:=chamber.w+absf(roughness)+junction_smoothing
		if AABB(center-Vector3.ONE*radius,Vector3.ONE*radius*2.).intersects(region): values.append(chamber)
	for edit in edits:
		var center: Vector3=edit.get("center",Vector3.ZERO); var radius:=maxf(.01,float(edit.get("radius",1.)))+junction_smoothing
		if AABB(center-Vector3.ONE*radius,Vector3.ONE*radius*2.).intersects(region): values.append(edit)
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value(values)
static func _smooth_min(a: float,b: float,width: float) -> float:
	if not is_finite(a): return b
	if width<=.00001: return minf(a,b)
	var blend:=clampf(.5+.5*(b-a)/width,0.,1.); return lerpf(b,a,blend)-width*blend*(1.-blend)
static func network(entrance: Vector3,depth: float=6.,length: float=16.,branches: int=2,seed: int=1) -> KiwiTerrainCave:
	var cave:=KiwiTerrainCave.new(); cave.seed=seed; var rng:=RandomNumberGenerator.new(); rng.seed=seed; var main:=PackedVector3Array()
	for index in 7:
		var t:=float(index)/6.; main.append(entrance+Vector3(sin(t*PI)*rng.randf_range(-length*.15,length*.15),-depth*smoothstep(0.,.8,t),length*t))
	cave.paths.append(main)
	for branch in clampi(branches,0,12):
		var junction:=main[2+branch%4]; var direction:=Vector3(-1. if branch%2==0 else 1.,rng.randf_range(-.3,.1),rng.randf_range(.2,.7)).normalized(); var path:=PackedVector3Array([junction,junction+direction*length*.25,junction+direction*length*.5+Vector3(0,-1,0)]); cave.paths.append(path); var end:=path[-1]; cave.chambers.append(Vector4(end.x,end.y,end.z,cave.radius*1.5))
	var end:=main[-1]; cave.chambers.append(Vector4(end.x,end.y,end.z,cave.radius*1.8)); return cave
