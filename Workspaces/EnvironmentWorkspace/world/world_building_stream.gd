extends RefCounted
## Saved architecture stays authoritative. CPU documents are cached; GPU detail
## exists near the camera, or stays available for complete offline collision.
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
var runtime: KiwiEnvironmentRuntime
var entries: Dictionary={}
var retired: Array[RefCounted]=[]
var physics_full:=false
var builds:=0
var cache_hits:=0
var cache_bytes:=0
func failure() -> String:
	for entry: Dictionary in entries.values():
		if not str(entry.get("error","")).is_empty(): return str(entry.error)
	return ""
func sync(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void:
	var authored:=Buildings.source(item)
	if authored==null: runtime.errors.append(item.title+": missing building source."); return
	var stamp:=Builder.mesh_key(item.mesh); var custom: bool=item.binding!=null or item.growth!=null or not item.modifiers.is_empty() or stamp!=int(item.parameters.get("_architecture_mesh",stamp))
	if custom:
		if entries.has(item.id): _retire(entries[item.id]); entries.erase(item.id)
		runtime._asset(item,node,metadata); runtime.warnings.append(item.title+": using its authored mesh override instead of procedural building detail."); return
	var render_source: Resource=Source.copy(authored)
	if item.surface_materials!=item.parameters.get("_architecture_materials",item.surface_materials):
		while render_source.materials.size()<item.surface_materials.size(): render_source.materials.append(null)
		for slot in item.surface_materials.size(): render_source.materials[slot]=item.surface_materials[slot]
	var key:=hash([Buildings._source_key(render_source),item.surface_materials]); var entry: Dictionary=entries.get(item.id,{})
	if not entry.is_empty() and (entry.key!=key or entry.node!=node): _retire(entry); entries.erase(item.id); entry={}
	if entry.is_empty():
		entry={"id":item.id,"key":key,"node":node,"source":render_source,"document":null,"job":null,"detail":null,"bytes":0,"used":0,"near":false,"error":""}; entries[item.id]=entry
	var shell:=node.get_node_or_null("BuildingDistanceShell") as MeshInstance3D
	var mesh_key:=runtime._native_asset_key(item)
	if shell==null:
		for child in node.get_children(): child.free()
	if shell==null: shell=MeshInstance3D.new(); shell.name="BuildingDistanceShell"; node.add_child(shell); shell.set_meta("kiwi_physics_excluded",true)
	if int(shell.get_meta("source_key",-1))!=mesh_key: shell.mesh=item.render_mesh(runtime._material_scope); shell.set_meta("source_key",mesh_key)
	entry.shell=shell; entry.collision=bool(metadata.get("collision",true))
func _retire(entry: Dictionary) -> void:
	if entry.get("job")!=null: entry.job.cancel(); retired.append(entry.job)
	if is_instance_valid(entry.get("detail")): entry.detail.free()
func dispose() -> void:
	for entry: Dictionary in entries.values(): _retire(entry)
	for job in retired: job.cancel(); job.collect()
	entries.clear(); retired.clear(); cache_bytes=0
func ready(need_physics: bool) -> bool:
	physics_full=need_physics
	process()
	if not failure().is_empty(): return false
	for entry: Dictionary in entries.values():
		if need_physics or bool(entry.get("wanted",false)):
			var detail:=entry.get("detail") as KiwiEnvironmentRuntime
			if detail==null or not detail.pending_assets.is_empty() or not detail.pending_chunks.is_empty(): return false
	return true
func _policy(entry: Dictionary) -> Dictionary:
	var item:=runtime.component_index.get(str(entry.id)) as KiwiModelComponent; var owner:=runtime.component_index.get(str(item.parameters.get("world_owner",""))) as KiwiModelComponent if item!=null else null; var source: Resource=owner.parameters.get("world_source") if owner!=null else null
	return {"distance":float(source.building_detail_distance) if source!=null else 180.,"active":int(source.max_active_buildings) if source!=null else 64,"cache":int(source.building_cache_mb)*1048576 if source!=null else 134217728}
func process() -> void:
	if runtime==null or runtime.document==null: return
	for index in range(retired.size()-1,-1,-1):
		if retired[index].complete(): retired[index].collect(); retired.remove_at(index)
	var wanted: Array[Dictionary]=[]; var working:=0; var memory_limit:=0; var policies: Dictionary={}; var upload_started:=Time.get_ticks_usec(); var uploaded:=false
	var camera:=runtime.get_viewport().get_camera_3d()
	if camera==null and is_instance_valid(runtime.priority_camera): camera=runtime.priority_camera
	for identity in entries.keys():
		var entry: Dictionary=entries[identity]; var item:=runtime.component_index.get(str(identity)) as KiwiModelComponent
		if item==null or runtime.document.component_settings.get(identity,{}).get("kind","")!="building" or not is_instance_valid(entry.node) or runtime.nodes.get(identity)!=entry.node: _retire(entry); entries.erase(identity); continue
		entry.wanted=false; var owner:=str(item.parameters.get("world_owner","independent"))
		if not policies.has(owner): policies[owner]=_policy(entry)
		var policy: Dictionary=policies[owner]; memory_limit=maxi(memory_limit,int(policy.cache)); var distance:=0. if camera==null else camera.global_position.distance_squared_to(entry.node.global_position); entry.distance=distance; entry.near=entry.node.is_visible_in_tree() and (camera==null or distance<pow(float(policy.distance),2.)); entry.active_limit=policy.active
		if entry.job!=null:
			if entry.job.complete():
				var result: Dictionary=entry.job.collect(); entry.job=null
				if not result.get("cancelled",false):
					if result.get("document")!=null and result.errors.is_empty():
						var document:=KiwiEnvironmentDocument.new(); document.components.assign(result.document.components)
						for component: KiwiModelComponent in document.components: document.component_settings[component.id]={"kind":"asset","collision":bool(entry.get("collision",true))}
						entry.document=document; entry.bytes=0
						for component in document.components: entry.bytes+=component.mesh.vertices.size()*64+component.mesh.faces.size()*96 if component.mesh!=null else 256
					else: entry.error=" · ".join(result.get("errors",PackedStringArray(["Could not generate building detail."]))); runtime.errors.append(entry.error)
			else: working+=1
		if entry.near or physics_full: wanted.append(entry)
	wanted.sort_custom(func(one: Dictionary,two: Dictionary): return float(one.distance)<float(two.distance))
	var visible: Dictionary={}; var per_world: Dictionary={}
	for entry: Dictionary in wanted:
		var item:=runtime.component_index.get(str(entry.id)) as KiwiModelComponent; var owner:=str(item.parameters.get("world_owner","independent")); var count:=int(per_world.get(owner,0)); var near: bool=entry.near and count<int(entry.active_limit)
		if near: per_world[owner]=count+1
		if not near and not physics_full: continue
		visible[entry.id]=true
		entry.wanted=true
		if entry.document==null and entry.job==null and str(entry.error).is_empty() and working<2:
			var job:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_job.gd").new(); entry.job=job; job.start(entry.source); builds+=1; working+=1
		if entry.document!=null:
			entry.used=Time.get_ticks_usec()
			if not is_instance_valid(entry.detail):
				var detail:=KiwiEnvironmentRuntime.new(); detail.name="BuildingDetail"; detail.progressive=true; detail.priority_camera=camera; detail.upload_budget_usec=500; entry.node.add_child(detail); detail.configure(entry.document); detail.set_process(false); detail.preview_time=runtime.preview_time; entry.detail=detail; cache_hits+=1
			var detail:=entry.detail as KiwiEnvironmentRuntime
			if not detail.pending_assets.is_empty() and (not uploaded or Time.get_ticks_usec()-upload_started<2000): detail.preview_time=runtime.preview_time; detail._process(0.); uploaded=true
			var complete:=detail.pending_assets.is_empty() and detail.pending_chunks.is_empty(); detail.visible=near and complete; entry.shell.visible=not near or not complete
	for entry: Dictionary in entries.values():
		if not visible.has(entry.id):
			if entry.job!=null: entry.job.cancel(); retired.append(entry.job); entry.job=null
			if is_instance_valid(entry.detail): entry.detail.free(); entry.detail=null
			entry.shell.visible=true
	cache_bytes=0; var disposable: Array[Dictionary]=[]
	for entry: Dictionary in entries.values():
		cache_bytes+=int(entry.bytes)
		if entry.document!=null and not is_instance_valid(entry.detail): disposable.append(entry)
	disposable.sort_custom(func(one: Dictionary,two: Dictionary): return int(one.used)<int(two.used))
	for entry: Dictionary in disposable:
		if cache_bytes<=memory_limit: break
		cache_bytes-=int(entry.bytes); entry.bytes=0; entry.document=null
	if uploaded:
		var actor:=runtime.get_parent() as ActorRuntime
		if actor!=null and actor.has_method("set_timeline_time"): actor.call("set_timeline_time",runtime.preview_time)
