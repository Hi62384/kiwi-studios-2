extends RefCounted
## File-backed source snapshots are shared read-only by compatible scene instances.
static var _resources: Dictionary={}
static var _instances: Dictionary={}
static var _revisions: Dictionary={}
static var _resolved: Dictionary={}
static func _path(path: String) -> String:
	if path.begins_with("uid://"):
		var id:=ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id): path=ResourceUID.get_id_path(id)
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
static func invalidate(path: String) -> void:
	path=_path(path); _resources.erase(path); _revisions[path]=int(_revisions.get(path,0))+1
static func load_resource(path: String) -> Resource:
	if path.is_empty(): return null
	path=_path(path)
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var file:=FileAccess.open(path,FileAccess.READ); var key:=hash([FileAccess.get_modified_time(path),file.get_length() if file!=null else 0,_revisions.get(path,0),KiwiEnvironmentAssets.revisions.get(path,0)])
	if _resources.has(path) and _resources[path].key==key: return _resources[path].resource
	var resource:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if _resources.size()>=16: _resources.erase(_resources.keys()[0])
	_resources[path]={"key":key,"resource":resource}; return resource
static func resolved_resource(path: String) -> Resource:
	var resource:=load_resource(path)
	if not resource is KiwiModelDocument or resource is KiwiEnvironmentDocument: return resource
	path=_path(path); var key:=hash([resource.get_instance_id(),KiwiEnvironmentAssets.generation])
	if _resolved.has(path) and _resolved[path].key==key: return _resolved[path].resource
	var result: Dictionary=load("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").resolve(resource)
	var resolved: Resource=result.document if result.document!=null else resource
	if _resolved.size()>=16: _resolved.erase(_resolved.keys()[0])
	_resolved[path]={"key":key,"resource":resolved}; return resolved
static func register_actor(actor: ActorData,runtime: Node=null) -> bool:
	if actor==null or not actor.values.get(&"model_component_bind_transform") is Transform3D: return false
	if str(actor.values.get(&"model_component_source","")).is_empty(): return false
	var instance:=str(actor.values.get(&"model_component_instance_id","")); var component:=str(actor.values.get(&"model_component_id",""))
	if instance.is_empty() or component.is_empty(): return false
	if not _instances.has(instance):
		if _instances.size()>=64:
			for key in _instances.keys():
				var alive:=false
				for entry: Dictionary in _instances[key].values():
					if _actor(entry)!=null: alive=true; break
				if not alive: _instances.erase(key)
		_instances[instance]={}
	var previous: Dictionary=_instances[instance].get(component,{})
	_instances[instance][component]={"actor":weakref(actor),"runtime":weakref(runtime) if runtime!=null else previous.get("runtime")}; return true
static func _actor(entry: Dictionary) -> ActorData:
	var reference: WeakRef=entry.get("runtime")
	if reference!=null:
		var runtime: Node=reference.get_ref()
		if runtime==null or runtime.is_queued_for_deletion(): return null
	return entry.actor.get_ref() as ActorData
static func refresh(actor: ActorData,path: String) -> bool:
	if actor==null or _path(str(actor.values.get(&"model_component_source","")))!=_path(path) or not register_actor(actor): return false
	if actor.type_id==&"skeleton_rig" or actor.values.has(&"model_rig_bind_signature"): return false
	var source:=resolved_resource(path) as KiwiModelDocument
	if source==null: return false
	var item:=source.component(str(actor.values.model_component_id))
	if item==null or item.parent_id!=str(actor.values.get(&"model_component_bind_parent",item.parent_id)): return false
	var old_pose: Transform3D=actor.values.model_component_bind_transform; var previous:=KiwiModelDocument.transform_values(old_pose); var desired:=KiwiModelDocument.transform_values(item.transform); var changed:=false
	for key in desired:
		var path_key:=PackedStringArray([str(key)]); var current: Variant=actor.values.get(key,previous[key]); var value: Variant=_reconcile(actor,previous[key],desired[key],current,path_key)
		if not _same(value,current): actor.values[key]=value; changed=true
	var mapping: Dictionary={}; var instance: Dictionary=_instances[str(actor.values.model_component_instance_id)]
	for id: String in instance.keys():
		var linked: ActorData=_actor(instance[id])
		if linked==null: instance.erase(id)
		else: mapping[id]=linked.id
	var old_structure:=_mapped_structure(actor.values.get(&"model_component_bind_structure",{}),mapping); var new_structure:=_mapped_structure(item.structural,mapping)
	for key in new_structure:
		var current: Variant=actor.values.get(key,old_structure.get(key)); var value: Variant=_reconcile(actor,old_structure.get(key),new_structure[key],current,PackedStringArray([str(key)]))
		if not _same(value,current): actor.values[key]=value; changed=true
	actor.values[&"model_component_bind_transform"]=item.transform; actor.values[&"model_component_bind_structure"]=item.structural.duplicate(true)
	return changed
static func _mapped_structure(settings: Dictionary,mapping: Dictionary) -> Dictionary:
	var result:=settings.duplicate(true)
	for link: Dictionary in result.get(&"structure_connections",{}).values(): link.target=mapping.get(str(link.get("target","")),"")
	if result.has(&"structure_assembly"): result[&"structure_assembly"]=mapping.get(str(result[&"structure_assembly"]),"")
	return result
static func _reconcile(actor: ActorData,old: Variant,next: Variant,current: Variant,path: PackedStringArray) -> Variant:
	for track in actor.animation_tracks:
		if track.path.size()>path.size(): continue
		var matches:=true
		for index in track.path.size(): matches=matches and track.path[index]==path[index]
		if matches: return current
	if old is Dictionary and next is Dictionary and current is Dictionary:
		var result: Dictionary=current.duplicate(true)
		for key in next:
			if not old.has(key) and not current.has(key): result[key]=ActorData.copy_value(next[key]); continue
			if not current.has(key): continue
			var nested:=path.duplicate(); nested.append(str(key)); result[key]=_reconcile(actor,old.get(key),next[key],current[key],nested)
		return result
	return ActorData.copy_value(next) if _same(old,current) else current
static func _same(one: Variant,two: Variant) -> bool:
	if typeof(one)!=typeof(two): return false
	if one is Vector3 or one is Basis or one is Transform3D: return one.is_equal_approx(two)
	if one is float: return is_equal_approx(one,two)
	return one==two
