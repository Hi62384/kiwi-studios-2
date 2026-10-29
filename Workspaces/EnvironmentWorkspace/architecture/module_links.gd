extends RefCounted
const References=preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd")
const SourceFiles=preload("res://Workspaces/ModelWorkspace/model_source_link.gd")
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
static func _parameters(item: KiwiModelComponent) -> Dictionary:
	var result:=item.parameters.duplicate(true); result.erase("_module_bindings"); return result
static func bind(item: KiwiModelComponent,owner: String,source_id: String) -> void:
	var bindings: Dictionary=item.parameters.get("_module_bindings",{}).duplicate(true)
	bindings[owner]={"source":source_id,"pose":item.transform,"parent":item.parent_id,"mesh":Geometry.mesh_key(item.mesh),"materials":item.surface_materials.duplicate(),"modifiers":item.modifiers.duplicate(true),"parameters":_parameters(item),"generator":item.generator,"name":item.title,"visible":item.visible,"locked":item.locked,"structure":item.structural.duplicate(true),"bones":item.bones.duplicate(true),"rig_rest":KiwiRigMath.bind_signature(item.bones) if item.is_skeleton else 0,"binding":item.binding.signature() if item.binding!=null else 0,"growth":growth_key(item.growth)}; item.parameters._module_bindings=bindings
static func growth_key(growth: KiwiSurfaceGrowthData) -> int:
	if growth==null: return 0
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([growth.settings,growth.faces,growth.groom,growth.groom_layers,growth.guides,growth.protected_faces,growth.appearance.signature() if growth.appearance!=null else 0,growth.growth_style.values if growth.growth_style!=null else {},growth.rendering,growth.regions,growth.individual])
static func _load(path: String,chain: PackedStringArray,cache: Dictionary) -> Dictionary:
	if path.is_empty(): return {"document":null,"error":"The linked source path is empty."}
	path=SourceFiles._path(path)
	if chain.has(path) or chain.size()>=16: return {"document":null,"error":"Linked model sources contain a cycle or exceed sixteen levels."}
	if cache.has(path): return {"document":cache[path],"error":""}
	var source:=SourceFiles.load_resource(path) as KiwiModelDocument
	if source==null or source is KiwiEnvironmentDocument: return {"document":null,"error":"A linked source must be an editable native Model resource: "+path.get_file()}
	var document:=source.snapshot(); var next:=chain.duplicate(); next.append(path); var roots: Array[String]=[]
	for item in document.components:
		if item.parameters.get("module_linked",false): roots.append(item.id)
	for id in roots:
		var group:=document.component(id)
		if group==null: continue
		var loaded:=_load(str(group.parameters.get("architecture_module_source","")),next,cache)
		if loaded.document==null: return loaded
		var error:=_replace(document,id,loaded.document,false)
		if not error.is_empty(): return {"document":null,"error":error}
	cache[path]=document; return {"document":document,"error":""}
static func _replace(document: KiwiModelDocument,id: String,source: KiwiModelDocument,reset: bool) -> String:
	var group:=document.component(id)
	if group==null: return "The linked instance no longer exists."
	var old: Dictionary={}; var old_ids: Dictionary={}
	for item in document.components:
		var bindings: Dictionary=item.parameters.get("_module_bindings",{})
		if bindings.has(id): old[str(bindings[id].source)]=item; old_ids[item.id]=true
	if old.is_empty(): return "This older snapshot has no source bindings. Insert a fresh linked instance; its existing edits are preserved."
	if reset:
		var procedural_owners: Dictionary={}
		for item: KiwiModelComponent in old.values():
			if item.parameters.has("architecture_source"): procedural_owners[item.id]=true
		for item in document.components:
			if item.parameters.has("architecture_key") and procedural_owners.has(str(item.parameters.get("architecture_owner",""))): old_ids[item.id]=true
	var mapping: Dictionary={}; var parts: Array[KiwiModelComponent]=[]; var live: Dictionary={}; var changed_surfaces: Dictionary={}; var changed_rigs: Dictionary={}
	for original in source.components: mapping[original.id]=(old[original.id] as KiwiModelComponent).id if old.has(original.id) else ActorData.new_id()
	for original in source.components:
		if not old.has(original.id): continue
		var previous: KiwiModelComponent=old[original.id]; var baseline: Dictionary=previous.parameters._module_bindings[id]
		if Geometry.mesh_key(original.mesh)!=int(baseline.mesh): changed_surfaces[previous.id]=true
		if original.is_skeleton and KiwiRigMath.bind_signature(original.bones)!=int(baseline.get("rig_rest",0)): changed_rigs[previous.id]=true
	for original in source.components:
		var item:=original.copy_component(); item.id=mapping[original.id]; item.parent_id=mapping.get(original.parent_id,id); References.component(item,mapping); bind(item,id,original.id); var previous:=old.get(original.id) as KiwiModelComponent
		if previous!=null:
			var before: Dictionary=previous.parameters._module_bindings[id]; var fresh: Dictionary=item.parameters._module_bindings[id]
			var manual_parameters: bool=before.get("manual_parameters",false) or _parameters(previous)!=before.parameters
			if not reset and manual_parameters and previous.parameters.has("architecture_source"): return "This linked procedural building has local source edits. Make it unique or reset its source overrides before updating."
			if not reset and manual_parameters and before.parameters.has("architecture_module_source"): return "A nested linked source has local edits. Make the outer instance unique or reset source overrides before updating."
			var bindings: Dictionary={} if reset else previous.parameters.get("_module_bindings",{}).duplicate(true)
			for owner in item.parameters.get("_module_bindings",{}): bindings[owner]=item.parameters._module_bindings[owner]
			item.parameters._module_bindings=bindings; fresh=item.parameters._module_bindings[id]
			if not reset:
				if previous.bones!=before.get("bones",[]) or before.get("manual_bones",false):
					if changed_rigs.has(previous.id): return "Local rig edits conflict with changed source rest bones. Make unique or reset source overrides."
					item.bones=previous.bones.duplicate(true); fresh.manual_bones=true
				if (previous.binding.signature() if previous.binding!=null else 0)!=int(before.get("binding",0)) or before.get("manual_binding",false):
					if changed_rigs.has(previous.skeleton_id): return "Local skin weights require an explicit rebind after source rest-bone changes."
					item.binding=previous.binding.copy_binding() if previous.binding!=null else null; item.skin=previous.skin; item.skin_mesh=previous.skin_mesh; item.mesh=previous.mesh; fresh.manual_binding=true
				if growth_key(previous.growth)!=int(before.get("growth",0)) or before.get("manual_growth",false):
					if previous.growth!=null and changed_surfaces.has(previous.growth.source_id): return "Local grooming needs a surface rebind before updating changed source geometry. Make unique or reset source overrides."
					item.growth=previous.growth.copy_data() if previous.growth!=null else null; fresh.manual_growth=true
				if before.get("manual_pose",false) or previous.transform!=before.pose: item.transform=previous.transform; fresh.manual_pose=true
				if before.get("manual_parent",false) or previous.parent_id!=before.parent: item.parent_id=previous.parent_id; fresh.manual_parent=true
				if before.get("manual_mesh",false) or Geometry.mesh_key(previous.mesh)!=int(before.mesh): item.mesh=previous.mesh; item.geometry_source=previous.geometry_source; item.geometry_source_hash=previous.geometry_source_hash; item.skin=previous.skin; item.skin_mesh=previous.skin_mesh; item.binding=previous.binding.copy_binding() if previous.binding!=null else null; fresh.manual_mesh=true
				if before.get("manual_material",false) or previous.surface_materials!=before.materials: item.surface_materials=previous.surface_materials; fresh.manual_material=true
				if before.get("manual_modifiers",false) or previous.modifiers!=before.modifiers: item.modifiers=previous.modifiers.duplicate(true); fresh.manual_modifiers=true
				if manual_parameters:
					var retained:=previous.parameters.duplicate(true); retained._module_bindings=bindings; item.parameters=retained; item.generator=previous.generator; fresh.manual_parameters=true
				if previous.title!=before.name or before.get("manual_name",false): item.title=previous.title; fresh.manual_name=true
				if previous.structural!=before.structure or before.get("manual_structure",false): item.structural=previous.structural.duplicate(true); fresh.manual_structure=true
				if previous.visible!=before.visible or before.get("manual_visible",false): item.visible=previous.visible; fresh.manual_visible=true
				if previous.locked!=before.locked or before.get("manual_locked",false): item.locked=previous.locked; fresh.manual_locked=true
		live[item.id]=true; parts.append(item)
	var extra_poses: Dictionary={}
	for item in document.components:
		if not old_ids.has(item.id) and old_ids.has(item.parent_id) and not live.has(item.parent_id): extra_poses[item.id]=document.world_transform(item)
	for item in parts:
		if old_ids.has(item.parent_id) and not live.has(item.parent_id): item.transform=document.world_transform(group).affine_inverse()*document.world_transform(old[str(item.parameters._module_bindings[id].source)]); item.parent_id=id
	var retained: Array[KiwiModelComponent]=[]
	for item in document.components:
		if not old_ids.has(item.id): retained.append(item)
	for item in parts: retained.append(item)
	document.components=retained
	for child_id in extra_poses:
		var child:=document.component(child_id); child.parent_id=id; child.transform=document.world_transform(group).affine_inverse()*extra_poses[child_id]
	if document is KiwiEnvironmentDocument:
		for removed in old_ids:
			if not live.has(removed): document.component_settings.erase(removed)
		for item in parts: document.component_settings[item.id]={"kind":"asset","collision":item.mesh!=null}
	return ""
static func refresh(session: KiwiModelSession,id: String,reset: bool=false) -> String:
	if not session._gesture.is_empty(): return "Finish the current edit before updating linked sources."
	var group:=session.document.component(id)
	if group==null: return "Select a linked model instance."
	var loaded:=_load(str(group.parameters.get("architecture_module_source","")),PackedStringArray(),{})
	if loaded.document==null: return loaded.error
	var candidate:=session.document.snapshot(); var error:=_replace(candidate,id,loaded.document,reset)
	if not error.is_empty(): return error
	var errors:=candidate.validate()
	if not errors.is_empty(): return "The source update is incompatible with local rig or hierarchy edits: "+errors[0]
	session.action("Reset linked source overrides" if reset else "Update linked model instance",func(): session.document=candidate)
	return ""
static func resolve(document: KiwiModelDocument) -> Dictionary:
	var roots: Array[String]=[]
	for item in document.components:
		if item.parameters.get("module_linked",false): roots.append(item.id)
	if roots.is_empty(): return {"document":document,"error":"","dependencies":[]}
	var candidate:=document.snapshot(); var cache: Dictionary={}
	for id in roots:
		var group:=candidate.component(id)
		if group==null: continue
		var source:=_load(str(group.parameters.get("architecture_module_source","")),PackedStringArray(),cache)
		if source.document==null: return {"document":null,"error":source.error}
		var error:=_replace(candidate,id,source.document,false)
		if not error.is_empty(): return {"document":null,"error":error}
	var errors:=candidate.validate()
	return {"document":candidate if errors.is_empty() else null,"error":errors[0] if not errors.is_empty() else "","dependencies":cache.keys()}
static func depends_on(path: String,target: String) -> bool: return _depends_on(path,target,{})
static func _depends_on(path: String,target: String,visited: Dictionary) -> bool:
	path=SourceFiles._path(path); target=SourceFiles._path(target)
	if path==target: return true
	if visited.has(path): return false
	if visited.size()>=64: return true
	visited[path]=true; var document:=SourceFiles.load_resource(path) as KiwiModelDocument
	if document==null: return false
	for item in document.components:
		if item.parameters.get("module_linked",false) and _depends_on(str(item.parameters.get("architecture_module_source","")),target,visited): return true
	return false
static func refresh_changed(session: KiwiModelSession,path: String) -> String:
	var roots: Array[String]=[]
	for item in session.document.components:
		if item.parameters.get("module_linked",false) and depends_on(str(item.parameters.get("architecture_module_source","")),path): roots.append(item.id)
	if roots.is_empty(): return ""
	var resolved:=resolve(session.document)
	if resolved.document==null: return resolved.error
	var errors: PackedStringArray=resolved.document.validate()
	if not errors.is_empty(): return errors[0]
	if not session._gesture.is_empty(): return "Finish the current edit before updating linked sources."
	session.action("Update linked model sources",func(): session.document=resolved.document)
	return ""
static func make_unique(session: KiwiModelSession,id: String) -> void:
	var group:=session.document.component(id)
	if group==null: return
	session.action("Make model instance unique",func():
		group.parameters.erase("architecture_module_source"); group.parameters.erase("module_linked")
		for item in session.document.components:
			if item.parameters.get("_module_bindings") is Dictionary: item.parameters._module_bindings.erase(id))
