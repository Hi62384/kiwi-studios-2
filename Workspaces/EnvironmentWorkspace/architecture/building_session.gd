extends RefCounted
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
static func source(item: KiwiModelComponent) -> Resource:
	var value: Variant=item.parameters.get("architecture_source") if item!=null else null
	return value if value is Resource and value.get_script()==Source else null
static func owner(session: KiwiModelSession,item: KiwiModelComponent) -> KiwiModelComponent:
	var current:=item
	while current!=null:
		if source(current)!=null: return current
		current=session.document.component(current.parent_id)
	return null
static func add(session: KiwiModelSession,position:=Vector3.ZERO,levels: int=1) -> KiwiModelComponent:
	var authored: Resource=Source.rectangular(6,8,levels); var generated:=Builder.generate(authored); var model:=generated.document as KiwiModelDocument
	if model==null: return null
	var root:=model.components[0]; root.transform.origin=position
	session.action("Add building",func():
		for item in model.components: _mark(item); session.document.components.append(item); _environment_settings(session,item)
		session.selected=[root.id])
	return root
static func update(session: KiwiModelSession,id: String,authored: Resource,label: String="Edit building",preview: bool=false,force: bool=false,prepared: Dictionary={}) -> Dictionary:
	var root:=session.document.component(id)
	if root==null: return {"errors":PackedStringArray(["The building no longer exists."]),"warnings":PackedStringArray()}
	var desired: Resource=Source.copy(authored); desired.source_id=id; var previous_source:=source(root)
	if not force and previous_source!=null and _source_key(previous_source)==_source_key(desired): return {"document":session.document,"errors":PackedStringArray(),"warnings":PackedStringArray()}
	var generated: Dictionary=prepared if prepared.get("source_key") == _source_key(desired) else Builder.generate(desired); var model:=generated.document as KiwiModelDocument
	if model==null or not generated.errors.is_empty(): return generated
	var old: Dictionary={}; var original_ids: Dictionary={}
	for item in session.document.components:
		if item.id==id or (session.document.is_descendant(item.id,id) and item.parameters.has("architecture_key") and owner(session,item)==root):
			old[str(item.parameters.get("architecture_key",""))]=item; original_ids[item.id]=true
	var remap: Dictionary={}; var live: Dictionary={}; var replacements: Array[KiwiModelComponent]=[]
	for item in model.components:
		var key:=str(item.parameters.architecture_key); var previous:=old.get(key) as KiwiModelComponent; remap[item.id]=previous.id if previous!=null else item.id
	for item in model.components:
		var generated_id:=item.id; var key:=str(item.parameters.architecture_key); var previous:=old.get(key) as KiwiModelComponent
		item.id=remap[generated_id]; item.parent_id=remap.get(item.parent_id,item.parent_id); live[item.id]=true
		if previous!=null:
			item.visible=previous.visible; item.locked=previous.locked
			for parameter: Variant in previous.parameters:
				if not item.parameters.has(parameter) and not str(parameter).begins_with("_architecture"): item.parameters[parameter]=ActorData.copy_value(previous.parameters[parameter])
			var manual_name: bool=bool(previous.parameters.get("_architecture_manual_name",false)) or previous.title!=str(previous.parameters.get("_architecture_generated_name",previous.title))
			if manual_name: item.title=previous.title; item.parameters._architecture_manual_name=true
			item.modifiers=previous.modifiers.duplicate(true); item.pivot=previous.pivot
			var last_pose: Transform3D=previous.parameters.get("_architecture_pose",previous.transform)
			var manual_pose: bool=bool(previous.parameters.get("_architecture_manual_pose",false)) or not previous.transform.is_equal_approx(last_pose)
			if key.is_empty() or manual_pose: item.transform=previous.transform
			if key.is_empty(): item.parent_id=previous.parent_id
			item.parameters._architecture_manual_pose=manual_pose
			var format:=int(previous.parameters.get("_architecture_mesh_format",1)); var current_hash:=Builder.mesh_key(previous.mesh,format)
			var manual: bool=bool(previous.parameters.get("_architecture_manual",false)) or current_hash!=int(previous.parameters.get("_architecture_mesh",current_hash))
			var changed_base: bool=int(item.parameters._architecture_generated_mesh)!=int(previous.parameters.get("_architecture_generated_mesh",item.parameters._architecture_generated_mesh))
			if format<2: changed_base=Builder.mesh_key(item.mesh,1)!=int(previous.parameters.get("_architecture_generated_mesh",Builder.mesh_key(item.mesh,1)))
			if changed_base and (manual or previous.binding!=null or previous.skin_mesh!=null):
				return {"document":null,"errors":PackedStringArray(["Reset this component's geometry override or detach its rig before changing its procedural dimensions/openings."]),"warnings":PackedStringArray()}
			if manual: item.mesh=previous.mesh; item.parameters._architecture_manual=true
			elif not changed_base and (item.mesh==null or previous.mesh==null or item.mesh.materials==previous.mesh.materials): item.mesh=previous.mesh
			if previous.binding!=null: item.binding=previous.binding.copy_binding(); item.skeleton_id=previous.skeleton_id
			item.skin=previous.skin; item.skin_mesh=previous.skin_mesh
			if manual: item.geometry_source=previous.geometry_source; item.geometry_source_hash=previous.geometry_source_hash
			var manual_material: bool=bool(previous.parameters.get("_architecture_manual_material",false)) or previous.surface_materials!=previous.parameters.get("_architecture_materials",previous.surface_materials)
			if manual_material: item.surface_materials=previous.surface_materials
			item.parameters._architecture_manual_material=manual_material
			var manual_structure: bool=bool(previous.parameters.get("_architecture_manual_structure",false)) or previous.structural!=previous.parameters.get("_architecture_structure",previous.structural)
			if manual_structure: item.structural=previous.structural.duplicate(true); item.parameters._architecture_manual_structure=true
		for connection: Dictionary in item.structural.get(&"structure_connections",{}).values(): connection.target=remap.get(str(connection.target),connection.target)
		_mark(item); replacements.append(item)
	var orphan_worlds: Dictionary={}
	for item in session.document.components:
		if not original_ids.has(item.id) and original_ids.has(item.parent_id) and not live.has(item.parent_id): orphan_worlds[item.id]=session.document.world_transform(item)
	var apply:=func():
		for index in range(session.document.components.size()-1,-1,-1):
			var item:=session.document.components[index]
			if original_ids.has(item.id):
				session.document.components.remove_at(index)
				if session.document is KiwiEnvironmentDocument: session.document.component_settings.erase(item.id)
		for item in replacements: session.document.components.append(item); _environment_settings(session,item)
		var inverse:=session.document.world_transform(session.document.component(id)).affine_inverse()
		for orphan_id: String in orphan_worlds:
			var orphan:=session.document.component(orphan_id); orphan.parent_id=id; orphan.transform=inverse*orphan_worlds[orphan_id]
		session.selected.assign(session.selected.filter(func(identity: String): return session.document.component(identity)!=null))
	if preview: session.begin(); apply.call(); session.changed.emit()
	else: session.action(label,apply)
	return generated
static func _source_key(value: Resource) -> int:
	return hash([value.title,value.seed,value.footprint,value.floors,value.wall_thickness,value.slab_thickness,value.roof_type,value.roof_pitch,value.roof_overhang,value.materials,value.stairs,value.physics_enabled,value.foundation_depth,value.style,value.facade_detail,value.detail_width,value.baseboard_height,value.crown_height,value.interior_trim_depth])
static func _mark(item: KiwiModelComponent) -> void:
	item.parameters._architecture_pose=item.transform; item.parameters._architecture_mesh=Builder.mesh_key(item.mesh); item.parameters._architecture_mesh_format=2; item.parameters._architecture_materials=item.surface_materials.duplicate()
	item.parameters._architecture_structure=item.structural.duplicate(true)
static func _environment_settings(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	if session.document is KiwiEnvironmentDocument: session.document.component_settings[item.id]={"kind":"asset","collision":true}
static func set_material(session: KiwiModelSession,id: String,slot: int,material: Material) -> void:
	var root:=session.document.component(id); var current:=source(root)
	if current==null or slot<0 or slot>6: return
	var next: Resource=Source.copy(current)
	while next.materials.size()<=slot: next.materials.append(next.materials[1] if next.materials.size()==6 and next.materials.size()>1 else (next.materials[0] if not next.materials.is_empty() else null))
	next.materials[slot]=material
	if session.document is KiwiEnvironmentDocument and (session.document as KiwiEnvironmentDocument).component_kind(id)=="building": load("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").request(session,id,next,"Assign building material"); return
	if current.materials.size()<7 and slot>=5: update(session,id,next,"Assign building material"); return
	session.action("Assign building material",func():
		root.parameters.architecture_source=next
		for item in session.document.components:
			var slots: PackedInt32Array=item.parameters.get("architecture_material_slots",PackedInt32Array([int(item.parameters.get("architecture_material_slot",-1))]))
			if item.mesh==null or owner(session,item)!=root or not slots.has(slot): continue
			if item.parameters.get("_architecture_manual_material",false) or item.surface_materials!=item.parameters.get("_architecture_materials",item.surface_materials): item.parameters._architecture_manual_material=true; continue
			for index in slots.size():
				if slots[index]==slot and index<item.surface_materials.size(): item.surface_materials[index]=material
			item.parameters._architecture_materials=item.surface_materials.duplicate())
static func reset_overrides(session: KiwiModelSession,id: String,component_id: String) -> Dictionary:
	var item:=session.document.component(component_id); var root:=session.document.component(id)
	if item==null or root==null: return {"errors":PackedStringArray(["The component no longer exists."]),"warnings":PackedStringArray()}
	session.begin(); item.parameters._architecture_manual=false; item.parameters._architecture_manual_pose=false; item.parameters._architecture_manual_material=false; item.parameters._architecture_manual_structure=false; _mark(item); item.pivot=Vector3.ZERO
	var result:=update(session,id,source(root),"Reset building component overrides",true,true)
	if not result.errors.is_empty(): session.cancel()
	else: session.commit("Reset building component overrides")
	return result
