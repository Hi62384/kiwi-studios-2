class_name KiwiEnvironmentSession
extends KiwiModelSession
## Shares Kiwi's object transforms, parenting and bounded history. Terrain
## strokes are sparse custom transactions instead of full-document snapshots.
var _terrain_stroke: Dictionary={}
var _scatter_stroke: Dictionary={}
func begin_scatter(id: String) -> bool:
	var item:=document.component(id)
	var scatter:=environment().component_settings.get(id,{}).get("scatter") as KiwiEnvironmentScatter
	if item==null or scatter==null or not document.editable_component(item): return false
	_scatter_stroke={"id":id,"paint":scatter.paint_regions.duplicate(),"erase":scatter.erase_regions.duplicate()}; return true
func paint_scatter(point: Vector2,radius: float,erase: bool) -> void:
	if _scatter_stroke.is_empty(): return
	var scatter:=environment().component_settings.get(_scatter_stroke.id,{}).get("scatter") as KiwiEnvironmentScatter
	if scatter==null: return
	var area:=Vector3(point.x,point.y,radius)
	if erase: scatter.erase_regions.append(area)
	else: scatter.paint_regions.append(area)
	changed.emit()
func _apply_scatter_regions(id: String,paint: Array[Vector3],erase: Array[Vector3]) -> void:
	var scatter:=environment().component_settings.get(id,{}).get("scatter") as KiwiEnvironmentScatter
	if scatter!=null: scatter.paint_regions=paint.duplicate(); scatter.erase_regions=erase.duplicate()
func finish_scatter(cancelled: bool=false) -> void:
	if _scatter_stroke.is_empty(): return
	var stroke:=_scatter_stroke; _scatter_stroke={}; var scatter:=environment().component_settings.get(stroke.id,{}).get("scatter") as KiwiEnvironmentScatter
	if scatter==null: return
	if cancelled: _apply_scatter_regions(stroke.id,stroke.paint,stroke.erase); changed.emit(); return
	if stroke.paint==scatter.paint_regions and stroke.erase==scatter.erase_regions: return
	custom_action("Paint scatter region",_apply_scatter_regions.bind(stroke.id,stroke.paint,stroke.erase),_apply_scatter_regions.bind(stroke.id,scatter.paint_regions.duplicate(),scatter.erase_regions.duplicate()),scatter.paint_regions.size()+scatter.erase_regions.size())
func _init() -> void: document=KiwiEnvironmentDocument.new()
func environment() -> KiwiEnvironmentDocument: return document as KiwiEnvironmentDocument
func commit(label: String) -> void:
	if not _gesture.is_empty(): preload("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd").refresh_links(self)
	super.commit(label)
func _signature(data: KiwiModelDocument) -> int:
	var env:=data as KiwiEnvironmentDocument
	if env==null: return super._signature(data)
	var fields:=[]
	for id: String in env.component_settings:
		var settings: Dictionary=env.component_settings[id]; var terrain:=settings.get("terrain") as KiwiEnvironmentTerrain; var copy:=settings.duplicate(); copy.erase("terrain"); copy.erase("scatter"); fields.append([id,copy,terrain.signature() if terrain!=null else 0])
		var scatter:=settings.get("scatter") as KiwiEnvironmentScatter
		if scatter!=null: fields.append(scatter.signature())
	return hash([super._signature(data),fields,env.title,env.sunlight,env.atmosphere,env.environment_source,env.random_seed,env.climate.signature() if env.climate!=null and env.climate.has_method("signature") else 0])

func add_terrain() -> KiwiModelComponent:
	var result: KiwiModelComponent
	begin(); result=environment().add_terrain(); selected=[result.id]; commit("Add terrain"); return result
func add_group(name: String="Group") -> KiwiModelComponent:
	var result: KiwiModelComponent
	begin(); result=environment().add_group(name); selected=[result.id]; commit("Add environment group"); return result
func selected_environment() -> KiwiEnvironmentDocument:
	if selected.is_empty(): return null
	var source:=environment(); var included:={}
	for item in source.components:
		if selected.has(item.id): included[item.id]=true
		for id in selected:
			if source.is_descendant(item.id,id): included[item.id]=true; break
	# A reusable scatter layer must retain the terrain it samples.
	for id: String in included.keys():
		var scatter:=source.component_settings.get(id,{}).get("scatter") as KiwiEnvironmentScatter
		if scatter!=null: included[scatter.terrain_id]=true
		var world: Variant=source.component(id).parameters.get("world_source")
		if world is Resource and world.get_script()==preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd") and source.terrain(str(world.terrain_id))!=null: included[str(world.terrain_id)]=true
	var result:=source.snapshot() as KiwiEnvironmentDocument; var retained: Array[KiwiModelComponent]=[]
	for item in result.components:
		if not included.has(item.id): result.component_settings.erase(item.id); continue
		if not item.parent_id.is_empty() and not included.has(item.parent_id): item.transform=source.world_transform(source.component(item.id)); item.parent_id=""
		retained.append(item)
	result.components=retained; result.environment_id=ActorData.new_id(); result.title=primary().title if primary()!=null else "Environment component"; result.workspace_state={}; result.environment_source=""; result.atmosphere=null; result.sunlight={"enabled":false}; return result
func insert_environment(source: KiwiEnvironmentDocument,origin: Vector3=Vector3.ZERO) -> String:
	if source==null or not source.validate().is_empty(): return "The environment component is invalid."
	action("Insert reusable environment",func():
		var copy:=source.snapshot() as KiwiEnvironmentDocument; var root:=environment().add_group(source.title); root.transform.origin=origin; var ids:={}
		for item in copy.components: ids[item.id]=ActorData.new_id()
		for item in copy.components:
			var old:=item.id; item.id=str(ids[old]); item.parent_id=str(ids.get(item.parent_id,root.id)); document.components.append(item); var metadata: Dictionary=copy.component_settings.get(old,{"kind":"group"}); environment().component_settings[item.id]=metadata
			preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").component(item,ids)
			preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").terrain(metadata.get("terrain") as KiwiEnvironmentTerrain,ids)
			var scatter:=metadata.get("scatter") as KiwiEnvironmentScatter
			if scatter!=null: scatter.terrain_id=str(ids.get(scatter.terrain_id,scatter.terrain_id))
		selected=[root.id])
	return ""

func place_asset(path: String,point: Vector3,normal: Vector3=Vector3.UP,align: bool=false) -> String:
	var source:=KiwiEnvironmentAssets.load_parts(path)
	if not str(source.error).is_empty(): return str(source.error)
	var bounds:=AABB(); var first:=true
	for part: Dictionary in source.parts:
		var box: AABB=part.mesh.get_aabb()
		for corner in 8:
			var p: Vector3=part.transform*(box.position+box.size*Vector3(corner&1,(corner>>1)&1,(corner>>2)&1))
			if first: bounds=AABB(p,Vector3.ZERO); first=false
			else: bounds=bounds.expand(p)
	action("Place environment asset",func():
		var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=path.get_file().get_basename(); var box:=BoxMesh.new(); box.size=bounds.size.max(Vector3.ONE*.01); item.mesh=KiwiModelMesh.from_mesh(box); var vertices:=item.mesh.vertices
		for i in vertices.size(): vertices[i]+=bounds.get_center()
		item.mesh.vertices=vertices; item.transform=Transform3D(Basis(Quaternion(Vector3.UP,normal.normalized())) if align else Basis.IDENTITY,point); document.components.append(item); environment().component_settings[item.id]={"kind":"asset","source":path,"collision":false}; selected=[item.id])
	return ""

func add_scatter(terrain_id: String,asset: String) -> String:
	var terrain:=environment().terrain(terrain_id)
	if terrain==null: return "Select a terrain first."
	var source:=KiwiEnvironmentAssets.load_parts(asset)
	if not str(source.error).is_empty(): return str(source.error)
	action("Add scatter layer",func():
		var layer:=environment().add_group("Scatter · "+asset.get_file().get_basename()); layer.parent_id=terrain_id; var settings:=KiwiEnvironmentScatter.new(); settings.terrain_id=terrain_id; settings.palette=[{"source":asset,"weight":1.}]; settings.region=Rect2(-terrain.dimensions*.5,terrain.dimensions); settings.density=.1; var proxy:=BoxMesh.new(); proxy.size=Vector3(terrain.dimensions.x,.1,terrain.dimensions.y); layer.mesh=KiwiModelMesh.from_mesh(proxy); environment().component_settings[layer.id]={"kind":"scatter","scatter":settings}; selected=[layer.id])
	return ""

func promote_scatter(layer_id: String,identity: String,placement: Dictionary) -> String:
	var layer:=document.component(layer_id); var scatter:=environment().component_settings.get(layer_id,{}).get("scatter") as KiwiEnvironmentScatter
	if layer==null or scatter==null or placement.is_empty(): return "Choose a generated instance first."
	var index:=int(placement.get("palette",-1))
	if index<0 or index>=scatter.palette.size(): return "The instance source is no longer in the palette."
	var asset: Variant=scatter.palette[index].get("source",""); var source: KiwiModelDocument=asset if asset is KiwiModelDocument else KiwiModelImport.load_document(str(asset))
	if source==null or source.components.is_empty(): return "The source model could not be opened."
	action("Promote scatter instance",func():
		var title: String=source.components[0].title if asset is KiwiModelDocument and not source.components.is_empty() else str(asset).get_file().get_basename(); var group:=environment().add_group("Editable · "+title); group.transform=document.world_transform(layer)*(placement.transform as Transform3D)
		var remap: Dictionary={}
		for part in source.components: remap[part.id]=ActorData.new_id()
		for part in source.components:
			var copy:=part.copy_component(); copy.id=remap[part.id]; copy.parent_id=remap.get(part.parent_id,group.id)
			preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").component(copy,remap)
			document.components.append(copy); environment().component_settings[copy.id]={"kind":"asset","collision":scatter.collisions}
		scatter.overrides[identity]={"deleted":true}; selected=[group.id])
	return ""

func duplicate_selected(preview: bool=false) -> void:
	var duplicate:=func():
		var ids:={}; var copies: Array[KiwiModelComponent]=[]; var metadata:={}
		for item in document.components:
			var included:=selected.has(item.id)
			for id in selected:
				if document.is_descendant(item.id,id): included=true; break
			if not included or not document.editable_component(item): continue
			var copy:=item.copy_component(true); ids[item.id]=copy.id; copy.title+=" copy"; copies.append(copy); metadata[copy.id]=environment().component_settings.get(item.id,{}).duplicate(true)
			for key in ["terrain","scatter"]:
				if metadata[copy.id].get(key) is Resource: metadata[copy.id][key]=metadata[copy.id][key].duplicate(true)
		for copy in copies:
			copy.parent_id=str(ids.get(copy.parent_id,copy.parent_id)); document.components.append(copy); environment().component_settings[copy.id]=metadata[copy.id]
			preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").component(copy,ids)
			preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").terrain(metadata[copy.id].get("terrain") as KiwiEnvironmentTerrain,ids)
			var scatter:=metadata[copy.id].get("scatter") as KiwiEnvironmentScatter
			if scatter!=null: scatter.terrain_id=str(ids.get(scatter.terrain_id,scatter.terrain_id))
		var roots:=selected.duplicate(); selected.clear()
		for id in roots:
			if ids.has(id): selected.append(str(ids[id]))
	if preview: begin(); duplicate.call(); changed.emit()
	else: action("Duplicate environment components",duplicate)

func begin_terrain(id: String,material: bool=false) -> bool:
	var item:=document.component(id)
	if item==null or not document.editable_component(item) or environment().terrain(id)==null: return false
	_terrain_stroke={"id":id,"before":{},"after":{},"material":material}; return true
func sculpt(center: Vector2,radius: float,amount: float,falloff: float,operation: int,flatten: float=0.,options: Dictionary={}) -> void:
	if _terrain_stroke.is_empty(): return
	var terrain:=environment().terrain(str(_terrain_stroke.id)); var edits:=terrain.paint_material(center,radius,amount,falloff,operation==1) if bool(_terrain_stroke.material) else terrain.sculpt(center,radius,amount,falloff,operation,flatten,options)
	for index: int in edits.before:
		if not _terrain_stroke.before.has(index): _terrain_stroke.before[index]=edits.before[index]
		_terrain_stroke.after[index]=edits.after[index]
	patch_editable(str(_terrain_stroke.id),edits.after); changed.emit()
func patch_editable(id: String,samples: Dictionary) -> void:
	var item:=document.component(id); var terrain:=environment().terrain(id)
	if item==null or item.mesh==null or terrain==null: return
	var vertices:=item.mesh.vertices
	if vertices.size()!=terrain.resolution*terrain.resolution:
		var side:=roundi(sqrt(float(vertices.size())))
		if side<2 or side*side!=vertices.size(): return
		for index in vertices.size():
			var x:=roundi(float(index%side)/(side-1)*(terrain.resolution-1)); var z:=roundi(float(index/side)/(side-1)*(terrain.resolution-1))
			if samples.has(x+z*terrain.resolution): var point:=vertices[index]; point.y=terrain.height(x,z); vertices[index]=point
		item.mesh.vertices=vertices; return
	for index: int in samples:
		if index>=0 and index<vertices.size():
			var point:=vertices[index]; point.y=terrain.height(index%terrain.resolution,index/terrain.resolution); vertices[index]=point
	item.mesh.vertices=vertices
func apply_terrain(id: String,samples: Dictionary,material: bool=false) -> void:
	var terrain:=environment().terrain(id)
	if terrain==null: return
	if material: terrain.apply_material_samples(samples)
	else: terrain.apply_samples(samples); patch_editable(id,samples)
func finish_terrain(cancelled: bool=false) -> void:
	if _terrain_stroke.is_empty(): return
	var stroke:=_terrain_stroke; _terrain_stroke={}
	if cancelled: apply_terrain(str(stroke.id),stroke.before,stroke.material); changed.emit(); return
	if stroke.after.is_empty(): return
	custom_action("Paint terrain material" if stroke.material else "Sculpt terrain",apply_terrain.bind(str(stroke.id),stroke.before.duplicate(),stroke.material),apply_terrain.bind(str(stroke.id),stroke.after.duplicate(),stroke.material),stroke.after.size())

func regenerate_terrain(id: String,settings: Dictionary,reset_edits: bool=false) -> void:
	var terrain:=environment().terrain(id)
	if terrain==null: return
	action("Regenerate terrain",func():
		for key: String in settings:
			if key in ["dimensions","resolution","seed","geology","base_height","amplitude","frequency","generation","erosion","caves","hydrology","biomes","voxel_height","voxel_cell_budget"]: terrain.set(key,settings[key])
		if reset_edits: terrain.edits=PackedFloat32Array()
		terrain.prepare(); terrain.prepare_water(); terrain.prepare_biomes(); terrain.prepare_volumes(); terrain.prepare_cave_biomes(); terrain.revision+=1; document.component(id).mesh=terrain.editable_mesh())

func delete_selected() -> String:
	action("Delete environment components",func():
		var removed:={}
		for item in document.components:
			if selected.has(item.id) and document.editable_component(item): removed[item.id]=true
		for id: String in removed.keys():
			var authored: Variant=document.component(id).parameters.get("world_source")
			if authored is Resource and authored.get_script()==preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd") and not str(authored.owned_terrain_id).is_empty(): removed[str(authored.owned_terrain_id)]=true
		for item in document.components:
			if item.parameters.get("world_generated",false) and removed.has(str(item.parameters.get("world_owner",""))): removed[item.id]=true
		preload("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd").remove_for_owners(self,removed)
		for item in document.components:
			if removed.has(item.parent_id) and not removed.has(item.id): item.transform=document.world_transform(item); item.parent_id=""
		var retained: Array[KiwiModelComponent]=[]
		for item in document.components:
			if removed.has(item.id): environment().component_settings.erase(item.id)
			else: retained.append(item)
		document.components=retained; selected.clear(); elements=PackedInt32Array())
	return ""
