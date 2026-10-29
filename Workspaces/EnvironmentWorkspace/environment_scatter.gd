class_name KiwiEnvironmentScatter
extends Resource
## Authored rules, not one model/component per generated instance.
@export var terrain_id:=""
@export var palette: Array[Dictionary]=[] # source path and relative weight
@export var region:=Rect2(-8,-8,16,16)
@export var density:=.25
@export var minimum_distance:=1.
@export var seed:=1
@export var scale_range:=Vector2(.8,1.2)
@export var yaw_range:=Vector2(-180,180)
@export var align_normal:=true
@export var height_range:=Vector2(-10000,10000)
@export var slope_range:=Vector2(0,60)
@export var budget:=10000
@export var paint_regions: Array[Vector3]=[] # local x, z, radius
@export var erase_regions: Array[Vector3]=[]
@export var exclude_polygons: Array[PackedVector2Array]=[] # terrain-local development / protected masks
@export var include_polygons: Array[PackedVector2Array]=[]
@export var exclusion_margin:=0.
@export var patch_scale:=0. # zero keeps the original uniform distribution
@export var patch_strength:=0.
@export var use_anchors:=false
@export var anchor_points: Array[Transform3D]=[] # same terrain-local frame as scatter
@export var anchor_ids:=PackedStringArray()
@export_enum("Terrain height","Offset from terrain","Authored anchor height") var anchor_height_mode:=0
@export var collisions:=false
@export var render_cluster_size:=0. # zero retains one batch per source mesh
@export var render_distance:=0. # zero retains unlimited rendering
@export var lod_enabled:=false
@export var lod_bias:=1.
@export var stream_instances:=false # camera-dependent instance buffers; source poses remain cached
@export var biome_ids:=PackedStringArray()
@export var minimum_biome_weight:=.05
@export var cluster_count:=0
@export var cluster_radius:=4.
@export var temperature_range:=Vector2(-10000,10000)
@export var humidity_range:=Vector2(0,1)
@export var shore_range:=Vector2(0,1000000)
@export var water_depth_range:=Vector2(0,1000000)
@export var overrides: Dictionary={} # stable candidate ID -> deleted / transform / palette
@export_enum("Terrain","Cave floor","Cave ceiling","Cave wall") var surface_domain:=0

func signature() -> int: return hash([terrain_id,palette,region,density,minimum_distance,seed,scale_range,yaw_range,align_normal,height_range,slope_range,budget,paint_regions,erase_regions,exclude_polygons,include_polygons,exclusion_margin,patch_scale,patch_strength,use_anchors,anchor_points,anchor_ids,anchor_height_mode,collisions,biome_ids,minimum_biome_weight,cluster_count,cluster_radius,temperature_range,humidity_range,shore_range,water_depth_range,overrides,surface_domain])
func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if anchor_height_mode not in [0,1,2]: errors.append("Choose terrain, offset or authored anchor height.")
	if not is_finite(render_cluster_size) or render_cluster_size<0. or render_cluster_size>4096. or not is_finite(render_distance) or render_distance<0. or not is_finite(lod_bias) or lod_bias<.05 or lod_bias>16.: errors.append("Scatter rendering needs a valid cluster size, distance and detail bias.")
	if density<0. or not is_finite(density): errors.append("Scatter density must be a finite positive value.")
	if palette.is_empty(): errors.append("Choose at least one scatter asset.")
	if anchor_points.size()>20000 or (not anchor_ids.is_empty() and anchor_ids.size()!=anchor_points.size()): errors.append("Anchor placement needs matching IDs and no more than 20,000 points.")
	if not anchor_ids.is_empty() and _unique_anchor_count()!=anchor_ids.size(): errors.append("Placement anchor IDs must be unique.")
	for pose in anchor_points:
		if not pose.origin.is_finite() or not pose.basis.x.is_finite() or not pose.basis.y.is_finite() or not pose.basis.z.is_finite(): errors.append("Placement anchors must be finite transforms.")
	if exclude_polygons.size()+include_polygons.size()>16384: errors.append("Scatter masks exceed the editable polygon budget.")
	if not is_finite(exclusion_margin) or exclusion_margin<0. or not is_finite(patch_scale) or patch_scale<0. or not is_finite(patch_strength) or patch_strength<0. or patch_strength>1.: errors.append("Scatter clearing and margin settings must be finite and within their ranges.")
	for polygon: PackedVector2Array in exclude_polygons+include_polygons:
		if polygon.size()<3 or polygon.size()>1024: errors.append("Scatter masks need 3 to 1024 vertices.")
		for point in polygon:
			if not point.is_finite(): errors.append("Scatter mask points must be finite.")
	for item: Dictionary in palette:
		var source: Variant=item.get("source","")
		var path: bool=(source is String or source is StringName) and not str(source).is_empty()
		if source is KiwiEnvironmentDocument or not (source is KiwiModelDocument or path): errors.append("Scatter palette contains an empty or unsupported source.")
	return errors
func render_signature() -> int: return hash([render_cluster_size,render_distance,lod_enabled,lod_bias,stream_instances])

func generate(terrain: KiwiEnvironmentTerrain,cancel: Callable=Callable()) -> Dictionary:
	var started:=Time.get_ticks_usec(); var batches:={}; var ids: Dictionary={}; var placements: Dictionary={}; var error:=validate()
	if terrain==null or not error.is_empty(): return {"batches":batches,"count":0,"error":"Choose a terrain." if terrain==null else "\n".join(error)}
	terrain.prepare(); var rng:=RandomNumberGenerator.new(); rng.seed=seed; var bounds:=region.abs(); var total_weight:=0.; var weights:=PackedFloat32Array()
	var masks:=_mask_index(); var noise:=FastNoiseLite.new(); noise.seed=seed; noise.frequency=1./maxf(.01,patch_scale); noise.fractal_octaves=2
	for entry: Dictionary in palette: total_weight+=maxf(0.,float(entry.get("weight",1.))); weights.append(total_weight)
	if total_weight<=0.: return {"batches":batches,"count":0,"error":"At least one palette weight must be positive."}
	var desired:=mini(clampi(budget,1,20000),maxi(0,roundi(bounds.get_area()*maxf(0.,density)))); var spacing:=maxf(.001,minimum_distance); var grid_size:=spacing/sqrt(2.); var occupied:={}; var count:=0; var attempts:=0; var maximum_attempts:=mini(200000,maxi(100,desired*20))
	if use_anchors: desired=mini(clampi(budget,1,20000),anchor_points.size()); maximum_attempts=anchor_points.size()
	var clusters:=PackedVector2Array()
	for index in clampi(cluster_count,0,4096): clusters.append(bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size)
	var caves: Array[KiwiTerrainCave]=[]
	if surface_domain>0:
		for cave in terrain.caves:
			if cave!=null and cave.enabled: cave.prepare(); caves.append(cave)
		if caves.is_empty(): return {"batches":{},"count":0,"error":"Cave scatter requires an enabled cave."}
	while count<desired and attempts<maximum_attempts:
		if attempts%(8 if surface_domain>0 else 128)==0 and cancel.is_valid() and cancel.call(): return {"batches":{},"count":0,"error":"Generation canceled."}
		attempts+=1
		# Rejection, masks and terrain edits must not perturb later candidate RNG.
		var identity: String=anchor_ids[attempts-1] if use_anchors and not anchor_ids.is_empty() else "%d:%d"%[seed,attempts]; rng.seed=hash([seed,identity]) if use_anchors else hash([seed,attempts]); var override: Dictionary=overrides.get(identity,{})
		if override.get("deleted",false): continue
		var point:=bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
		if not clusters.is_empty(): point=clusters[rng.randi_range(0,clusters.size()-1)]+Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*maxf(.001,cluster_radius)
		if use_anchors: point=Vector2(anchor_points[attempts-1].origin.x,anchor_points[attempts-1].origin.z)
		var cave_hit: Dictionary=_cave_surface(terrain,rng,caves) if surface_domain>0 else {}
		if surface_domain>0:
			if cave_hit.is_empty(): continue
			point=Vector2(cave_hit.position.x,cave_hit.position.z)
		if not bounds.has_point(point): continue
		if not include_polygons.is_empty() and not include_polygons.any(func(polygon: PackedVector2Array): return Geometry2D.is_point_in_polygon(point,polygon)): continue
		if _excluded(point,masks): continue
		if patch_scale>0. and patch_strength>0.:
			var coverage:=smoothstep(-.35,.35,noise.get_noise_2dv(point)); var probability:=lerpf(1.,coverage,patch_strength)
			if rng.randf()>probability: continue
		var permitted:=paint_regions.is_empty()
		for area: Vector3 in paint_regions:
			if point.distance_to(Vector2(area.x,area.y))<=area.z: permitted=true; break
		if not permitted: continue
		for area: Vector3 in erase_regions:
			if point.distance_to(Vector2(area.x,area.y))<=area.z: permitted=false; break
		if not permitted: continue
		var cell:=Vector2i((point/grid_size).floor()); var close:=false
		for y in range(-2,3):
			for x in range(-2,3):
				if occupied.has(cell+Vector2i(x,y)) and point.distance_to(occupied[cell+Vector2i(x,y)])<spacing: close=true; break
			if close: break
		if close: continue
		var surface: Dictionary={"height":cave_hit.position.y,"normal":cave_hit.normal} if surface_domain>0 else terrain.sample(point)
		if surface.is_empty(): continue
		var sample_index:=clampi(roundi((point.x/terrain.dimensions.x+.5)*(terrain.resolution-1)),0,terrain.resolution-1)+clampi(roundi((point.y/terrain.dimensions.y+.5)*(terrain.resolution-1)),0,terrain.resolution-1)*terrain.resolution
		var unsuitable:=false
		for filter in [["temperature",temperature_range],["humidity",humidity_range]]:
			var field: PackedFloat32Array=terrain.biome_data.get(filter[0],PackedFloat32Array())
			if sample_index<field.size() and (field[sample_index]<filter[1].x or field[sample_index]>filter[1].y): unsuitable=true
		var shore: PackedFloat32Array=terrain.water_data.get("shore_distance",PackedFloat32Array())
		if sample_index<shore.size() and (shore[sample_index]<shore_range.x or shore[sample_index]>shore_range.y): unsuitable=true
		var water_depth:=0.
		if water_depth_range.x>0. or water_depth_range.y<1000000.:
			var depths: PackedFloat32Array=terrain.water_data.get("depth",PackedFloat32Array()); var wet_nearby:=surface_domain>0; var position: Vector2=(point/terrain.dimensions+Vector2.ONE*.5)*(terrain.resolution-1); var water_cell:=Vector2i(position.floor())
			for z in 2:
				for x in 2:
					var water_index:=clampi(water_cell.x+x,0,terrain.resolution-1)+clampi(water_cell.y+z,0,terrain.resolution-1)*terrain.resolution
					if water_index<depths.size() and depths[water_index]>0.: wet_nearby=true
			if wet_nearby: water_depth=float(terrain.water_at(Vector3(point.x,float(surface.height)+.001,point.y)).get("depth",0.))
		if water_depth<water_depth_range.x or water_depth>water_depth_range.y: unsuitable=true
		if unsuitable: continue
		var elevation:=float(surface.height); var normal: Vector3=surface.normal; var slope:=rad_to_deg(acos(clampf(absf(normal.y) if surface_domain>0 else normal.y,-1.,1.)))
		if elevation<height_range.x or elevation>height_range.y or slope<slope_range.x or slope>slope_range.y: continue
		if not biome_ids.is_empty():
			var suitability:=0.; var biome_weights: Dictionary=terrain.cave_biome_at(cave_hit.position) if surface_domain>0 else terrain.biome_at(point)
			for id in biome_ids: suitability+=float(biome_weights.get(id,0.))
			if suitability<minimum_biome_weight or rng.randf()>clampf(suitability,0.,1.): continue
		var choice:=rng.randf()*total_weight; var index:=0
		while index<weights.size()-1 and choice>weights[index]: index+=1
		index=clampi(int(override.get("palette",index)),0,palette.size()-1)
		var basis:=Basis(Quaternion(Vector3.UP,normal)) if align_normal else Basis.IDENTITY
		if use_anchors: basis*=anchor_points[attempts-1].basis
		basis*=Basis(Vector3.UP,deg_to_rad(rng.randf_range(yaw_range.x,yaw_range.y))); basis=basis.scaled(Vector3.ONE*rng.randf_range(maxf(.001,minf(scale_range.x,scale_range.y)),maxf(.001,maxf(scale_range.x,scale_range.y))))
		if not batches.has(index): batches[index]=[]; ids[index]=[]
		if use_anchors and anchor_height_mode!=0: elevation=(anchor_points[attempts-1] as Transform3D).origin.y+(elevation if anchor_height_mode==1 else 0.)
		var pose: Transform3D=override.get("transform",Transform3D(basis,Vector3(point.x,elevation,point.y)))
		batches[index].append(pose); ids[index].append(identity); placements[identity]={"transform":pose,"palette":index}; occupied[cell]=point; count+=1
	return {"batches":batches,"ids":ids,"placements":placements,"count":count,"requested":desired,"attempts":attempts,"milliseconds":float(Time.get_ticks_usec()-started)/1000.,"error":"","warning":"" if count==desired else "Placed %d / %d: spacing, slope, height or painted region limits prevented denser placement."%[count,desired]}

func _mask_index() -> Dictionary:
	# A road network can contain thousands of small corridor polygons. Check only
	# masks in the candidate's cell; large regional masks are kept separately.
	var cells: Dictionary={}; var large: Array[PackedVector2Array]=[]
	for polygon in exclude_polygons:
		if polygon.size()<3: continue
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: bounds=bounds.expand(point)
		bounds=bounds.grow(exclusion_margin+.001); var low:=Vector2i((bounds.position/16.).floor()); var high:=Vector2i((bounds.end/16.).floor())
		if (high.x-low.x+1)*(high.y-low.y+1)>256: large.append(polygon); continue
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell:=Vector2i(x,y)
				if not cells.has(cell): cells[cell]=[]
				cells[cell].append(polygon)
	return {"cells":cells,"large":large}
func _unique_anchor_count() -> int:
	var ids: Dictionary={}
	for id in anchor_ids: ids[id]=true
	return ids.size()
func _excluded(point: Vector2,index: Dictionary) -> bool:
	var masks: Array=index.cells.get(Vector2i((point/16.).floor()),[]).duplicate(); masks.append_array(index.large)
	for polygon: PackedVector2Array in masks:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
		for edge in polygon.size():
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[edge],polygon[(edge+1)%polygon.size()]))<=exclusion_margin: return true
	return false

func _cave_surface(terrain: KiwiEnvironmentTerrain,rng: RandomNumberGenerator,caves: Array[KiwiTerrainCave]) -> Dictionary:
	var cave:=caves[rng.randi_range(0,caves.size()-1)]; var origin:=Vector3.ZERO
	if not cave.paths.is_empty():
		var path: PackedVector3Array=cave.paths[rng.randi_range(0,cave.paths.size()-1)]
		if path.size()<2: return {}
		var index:=rng.randi_range(0,path.size()-2); origin=path[index].lerp(path[index+1],rng.randf())
	elif not cave.chambers.is_empty():
		var chamber: Vector4=cave.chambers[rng.randi_range(0,cave.chambers.size()-1)]; origin=Vector3(chamber.x,chamber.y,chamber.z)
	else: return {}
	origin+=Vector3(rng.randf_range(-.3,.3),rng.randf_range(-.3,.3),rng.randf_range(-.3,.3))*cave.radius
	var angle:=rng.randf()*TAU
	var direction:=Vector3.DOWN if surface_domain==1 else (Vector3.UP if surface_domain==2 else Vector3(cos(angle),rng.randf_range(-.1,.1),sin(angle)).normalized())
	if _cave_distance(origin,caves)>=0.: return {}
	var distance:=0.; var limit:=minf(1000.,cave.bounds().size.length()*2.)
	for step in 256:
		var air:=_cave_distance(origin+direction*distance,caves)
		if air>=0.:
			var low:=0.; var high:=distance
			# Locate the actual air/solid boundary, not the cave center path.
			for i in 16:
				var middle: float=(low+high)*.5
				if _cave_distance(origin+direction*middle,caves)<0.: low=middle
				else: high=middle
			var hit:=origin+direction*((low+high)*.5); var ground:=terrain.sample(Vector2(hit.x,hit.z))
			if ground.is_empty() or hit.y>=float(ground.height)-.02: return {}
			var h:=.01; var n: Vector3=-Vector3(_cave_distance(hit+Vector3(h,0,0),caves)-_cave_distance(hit-Vector3(h,0,0),caves),_cave_distance(hit+Vector3(0,h,0),caves)-_cave_distance(hit-Vector3(0,h,0),caves),_cave_distance(hit+Vector3(0,0,h),caves)-_cave_distance(hit-Vector3(0,0,h),caves)).normalized()
			if (surface_domain==1 and n.y<.5) or (surface_domain==2 and n.y>-.5) or (surface_domain==3 and absf(n.y)>.5): return {}
			return {"position":hit,"normal":n}
		distance+=clampf(-air*.7,.03,.5)
		if distance>limit: break
	return {}
static func _cave_distance(point: Vector3,caves: Array[KiwiTerrainCave]) -> float:
	var value:=INF
	for cave in caves: value=minf(value,cave.distance(point))
	return value

