extends RefCounted
## Native scatter sources, not a second tree renderer or one node per tree.
const Natural=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
const DataHash=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd")
const PROFILES=["Temperate Forest","Conifer Forest","Tropical Jungle","Alpine Forest","Sparse Woodland","Swamp Forest","Dry Woodland","Custom Forest"]
const SPECIES={
	"Temperate Forest":[["Tree / Oak","Tree / Birch"],["Tree / Maple"],["Plant / Bush","Plant / Fern"],["Plant / Grass","Plant / Mushroom"]],
	"Conifer Forest":[["Tree / Pine","Tree / Spruce"],["Tree / Fir"],["Plant / Fern"],["Plant / Grass","Prop / Log"]],
	"Tropical Jungle":[["Tree / Tropical","Tree / Palm"],["Tree / Tropical"],["Plant / Fern","Plant / Bush"],["Plant / Grass","Prop / Root"]],
	"Alpine Forest":[["Tree / Fir","Tree / Pine"],["Tree / Spruce"],["Plant / Bush"],["Plant / Grass","Rock / Granite"]],
	"Sparse Woodland":[["Tree / Oak","Tree / Birch"],["Tree / Maple"],["Plant / Bush"],["Plant / Grass","Plant / Flower"]],
	"Swamp Forest":[["Tree / Mangrove","Tree / Willow"],["Tree / Willow"],["Plant / Reed","Plant / Fern"],["Plant / Mushroom","Prop / Log"]],
	"Dry Woodland":[["Tree / Acacia","Tree / Desert"],["Tree / Acacia"],["Plant / Succulent"],["Rock / Sandstone","Prop / Stump"]],
	"Custom Forest":[["Tree / Oak"],["Tree / Birch"],["Plant / Bush"],["Plant / Grass"]]}
const LAYERS=["Canopy","Subcanopy","Understory","Ground"]
static func create(source: Resource,center: Vector3,profile: String="Temperate Forest") -> Resource:
	var next: Resource=source.copy(); var bounds:=Rect2(Vector2(center.x,center.z)-source.dimensions*.4,source.dimensions*.8).intersection(Rect2(-source.dimensions*.5,source.dimensions))
	if bounds.size.x<1. or bounds.size.y<1.: bounds=Rect2(-source.dimensions*.4,source.dimensions*.8)
	var forest: Dictionary={"id":ActorData.new_id(),"name":profile+" "+str(next.forests.size()+1),"profile":profile,"bounds":bounds,"seed":source.seed+next.forests.size()*101,"density":.35 if profile=="Sparse Woodland" else 1.,"enabled":true,"patch_scale":24.,"patch_strength":.85,"budget":2000,"variants":[],"biome_ids":PackedStringArray(),"height_range":Vector2(-10000,10000),"slope_range":Vector2(0,45),"humidity_range":Vector2(0,1),"temperature_range":Vector2(-10000,10000),"shore_range":Vector2(0,1000000)}
	# Rendering resources are prepared on the main thread. Only editable CPU
	# polygons and native resource containers are built by the generation worker.
	for layer in LAYERS.size():
		for kind: String in SPECIES.get(profile,SPECIES["Temperate Forest"])[layer]:
			var settings: Dictionary=Natural.defaults(kind); settings.seed=hash([forest.seed,layer,kind]); settings.segments=6; settings.levels=1; settings.branches=5; settings.detail=6; settings.roots=2; settings.wind_strength=.12
			if layer==1: settings.height*=.55; settings.radius*=.65
			forest.variants.append({"layer":layer,"kind":kind,"settings":settings,"materials":Natural.materials(kind,settings)})
	next.forests.append(forest); return next
static func build(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var settings: Dictionary={}; var warnings:=PackedStringArray()
	if source.forests.is_empty(): return {"settings":settings,"errors":PackedStringArray(),"warnings":warnings}
	if source.terrain_field==null: return {"settings":settings,"errors":PackedStringArray(["Choose a terrain before generating forests."]),"warnings":warnings}
	var field: RefCounted=source.terrain_field; var masks:=_development(source,layout,graph,field.to_ground)
	for forest: Dictionary in source.forests:
		if not forest.get("enabled",true): continue
		var group:=_component(source,str(forest.id),str(forest.name),source.world_id); group.parameters.world_forest=forest.id; document.components.append(group); settings[group.id]={"kind":"group"}
		for layer in LAYERS.size():
			if cancel.is_valid() and cancel.call(): return {"cancelled":true}
			var palette: Array[Dictionary]=[]
			for variant: Dictionary in forest.get("variants",[]):
				if int(variant.layer)!=layer: continue
				var generated:=Natural.generate(str(variant.kind),variant.settings,cancel)
				if generated.get("cancelled",false): return {"cancelled":true}
				if generated.get("mesh")==null: return {"errors":PackedStringArray([str(generated.get("error","Could not generate forest vegetation."))]),"warnings":warnings}
				var model:=KiwiModelDocument.new(); var part:=KiwiModelComponent.new(); part.id=str(forest.id)+":"+str(layer)+":"+str(palette.size()); part.title=variant.kind; part.generator=variant.kind; part.parameters=generated.settings; part.mesh=generated.mesh; part.surface_materials.assign(variant.materials); model.components.append(part); palette.append({"source":model,"weight":1.})
			if palette.is_empty(): continue
			var rules:=KiwiEnvironmentScatter.new(); rules.terrain_id=source.terrain_id; rules.palette=palette; rules.seed=hash([forest.seed,layer]); rules.density=[.014,.009,.035,.12][layer]*float(forest.density); rules.minimum_distance=[4.,3.,1.5,.7][layer]; rules.budget=clampi(int(forest.get("budget",2000)),1,20000); rules.scale_range=Vector2(.7,1.35); rules.align_normal=layer>=2; rules.patch_scale=float(forest.get("patch_scale",24.)); rules.patch_strength=float(forest.get("patch_strength",.85)); rules.exclusion_margin=[2.,1.2,.6,.2][layer]; rules.exclude_polygons.assign(masks)
			rules.water_depth_range=Vector2(0,1.5 if str(forest.profile)=="Swamp Forest" and layer<3 else .03)
			rules.render_cluster_size=32.; rules.render_distance=minf(float(source.render_distance),[500.,350.,200.,120.][layer]) if source.render_distance>0. else 0.; rules.lod_enabled=true
			rules.stream_instances=true
			for key in ["height_range","slope_range","humidity_range","temperature_range","shore_range","biome_ids"]: rules.set(key,forest.get(key,rules.get(key)))
			var polygon:=_rectangle(forest.bounds,field.to_ground); rules.include_polygons=[polygon]; var bounds:=Rect2(polygon[0],Vector2.ZERO)
			for point in polygon: bounds=bounds.expand(point)
			rules.region=bounds
			var item:=_component(source,str(forest.id)+":"+str(layer),LAYERS[layer],group.id); item.transform=field.to_world; item.parameters.world_pose=item.transform; item.mesh=KiwiModelPrimitives.box(Vector3(bounds.size.x,.05,bounds.size.y))
			for vertex in item.mesh.vertices.size(): item.mesh.vertices[vertex]+=Vector3(bounds.get_center().x,0.,bounds.get_center().y)
			item.parameters.world_mesh_key=hash([item.mesh.vertices,item.mesh.faces]); item.parameters.world_forest=forest.id; item.parameters.world_scatter_defaults=baseline(rules); document.components.append(item); settings[item.id]={"kind":"scatter","scatter":rules,"collision":false}
	return {"settings":settings,"errors":PackedStringArray(),"warnings":warnings}
static func _component(source: Resource,key: String,title: String,parent: String) -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=str(source.world_id)+":forest:"+key; item.title=title; item.parent_id=parent; item.parameters={"world_owner":source.world_id,"world_generated":true,"world_key":item.id.trim_prefix(source.world_id),"world_pose":item.transform,"world_structure":{},"world_materials":[],"world_mesh_key":0,"world_generated_visible":true}; return item
static func baseline(rules: KiwiEnvironmentScatter) -> Dictionary:
	var result: Dictionary={}
	for property in rules.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage)&PROPERTY_USAGE_STORAGE: result[str(property.name)]=DataHash.value(rules.get(property.name))
	return result
static func preserve(old: KiwiEnvironmentScatter,rules: KiwiEnvironmentScatter,defaults: Dictionary) -> void:
	for key in baseline(old):
		if key in ["terrain_id","exclude_polygons"]: continue
		if key in ["paint_regions","erase_regions","overrides"] or (defaults.has(key) and DataHash.value(old.get(key))!=int(defaults[key])): rules.set(key,old.get(key))
static func _rectangle(bounds: Rect2,pose: Transform3D) -> PackedVector2Array:
	return _polygon(PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]),pose)
static func _polygon(polygon: PackedVector2Array,pose: Transform3D) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for point in polygon:
		var local:=pose*Vector3(point.x,0.,point.y); result.append(Vector2(local.x,local.z))
	return result
static func _development(source: Resource,layout: Dictionary,graph: Dictionary,pose: Transform3D,sidewalks: bool=false) -> Array[PackedVector2Array]:
	var masks: Array[PackedVector2Array]=[]
	for road: Dictionary in graph.edges:
		if str(road.get("mode","Ground"))=="Tunnel": continue
		var points: PackedVector3Array=road.points
		for index in points.size()-1:
			var a:=Vector2(points[index].x,points[index].z); var b:=Vector2(points[index+1].x,points[index+1].z); var clearance:=float(road.width)*.5+float(road.get("shoulder",0.))+.1 if sidewalks else preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(road)+.5; var side: Vector2=(b-a).orthogonal().normalized()*clearance
			masks.append(_polygon(PackedVector2Array([a-side,b-side,b+side,a+side]),pose))
	for plot: Dictionary in layout.plots: masks.append(_polygon(plot.polygon,pose))
	for area: Dictionary in source.exclusions:
		if area.get("exclude_vegetation",true) and (area.get("polygon",PackedVector2Array()) as PackedVector2Array).size()>=3: masks.append(_polygon(area.polygon,pose))
	for area: Dictionary in source.occupied: masks.append(_polygon(area.polygon,pose))
	for region: Dictionary in source.regions:
		if not region.get("enabled",true): masks.append(_rectangle(region.bounds,pose))
	return masks


