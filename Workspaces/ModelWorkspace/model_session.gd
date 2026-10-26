class_name KiwiModelSession
extends RefCounted
signal changed
var document := KiwiModelDocument.new()
var selected: Array[String] = []
var mode := "Object"
var elements := PackedInt32Array()
var dirty := false
var revision := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _gesture: Dictionary = {}
var last_command := ""
var rig_selection: Dictionary={}

func primary() -> KiwiModelComponent: return document.component(selected.back()) if not selected.is_empty() else null
func snapshot() -> Dictionary: return {"document":document.snapshot(),"selected":selected.duplicate(),"mode":mode,"elements":elements.duplicate(),"rig_selection":rig_selection.duplicate()}
func restore(state: Dictionary) -> void:
	document=state.document.snapshot(); selected.assign(state.selected); mode=state.mode; elements=state.elements.duplicate(); rig_selection=state.get("rig_selection",{}).duplicate(); changed.emit()
func begin() -> void:
	if _gesture.is_empty(): _gesture=snapshot()
func cancel() -> void:
	if _gesture.is_empty(): return
	var state := _gesture; _gesture={}; restore(state)
func commit(label: String) -> void:
	if _gesture.is_empty(): return
	if _signature(document)==_signature(_gesture.document): _gesture={}; changed.emit(); return
	_undo.append({"label":label,"before":_gesture,"after":snapshot()}); _gesture={}; _redo.clear()
	# Bounded snapshot history, with a vertex budget as well as an action limit.
	var budget := 0
	for i in range(_undo.size()-1,-1,-1):
		if _undo[i].has("custom"): budget+=int(_undo[i].get("cost",0)); continue
		for item: KiwiModelComponent in _undo[i].before.document.components:
			if item.mesh!=null: budget+=item.mesh.vertices.size()
		if budget>1500000 or _undo.size()>40:
			_undo.pop_front(); break
	dirty=true; revision+=1; last_command=label; changed.emit()
func _signature(data: KiwiModelDocument) -> int:
	var entries := []
	for item in data.components:
		var geometry: Array=[]
		if item.mesh!=null: geometry=[item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials,item.mesh.smooth]
		entries.append([item.id,item.title,item.parent_id,item.transform,item.pivot,item.visible,item.locked,item.generator,item.parameters,item.modifiers,item.surface_materials,geometry,item.is_skeleton,item.bones,item.skin,item.skin_mesh,item.skeleton_id,item.binding.signature() if item.binding!=null else 0,item.geometry_source,item.geometry_source_hash])
	return hash(entries)
func action(label: String, operation: Callable) -> void: begin(); operation.call(); commit(label)
func undo() -> void:
	if not _gesture.is_empty(): cancel(); return
	if _undo.is_empty(): return
	var entry: Dictionary=_undo.pop_back(); _redo.append(entry); dirty=true; revision+=1
	if entry.has("custom"): entry.undo.call(); changed.emit()
	else: restore(entry.before)
func redo() -> void:
	if _redo.is_empty(): return
	var entry: Dictionary=_redo.pop_back(); _undo.append(entry); dirty=true; revision+=1
	if entry.has("custom"): entry.redo.call(); changed.emit()
	else: restore(entry.after)

func custom_action(label: String, backward: Callable, forward: Callable, cost: int=0) -> void:
	_undo.append({"label":label,"custom":true,"undo":backward,"redo":forward,"cost":cost}); _redo.clear()
	while _undo.size()>40: _undo.pop_front()
	dirty=true; revision+=1; last_command=label; changed.emit()
func select(id: String, additive: bool=false) -> void:
	if not additive: selected.clear()
	if not id.is_empty():
		if selected.has(id): selected.erase(id)
		else: selected.append(id)
	elements=PackedInt32Array(); changed.emit()
func add(kind: String, parameters: Dictionary={}, position: Vector3=Vector3.ZERO) -> KiwiModelComponent:
	var item := KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=kind; item.generator=kind; item.parameters=KiwiModelPrimitives.defaults(kind); item.parameters.merge(parameters,true)
	item.mesh=KiwiModelPrimitives.create(kind,item.parameters); item.transform.origin=position
	action("Add "+kind,func(): document.components.append(item); selected.assign([item.id]); elements=PackedInt32Array())
	return item
func selected_vertices() -> PackedInt32Array:
	var item := primary(); var used := {}; var result := PackedInt32Array()
	if item==null or item.mesh==null: return result
	if (item.skin_mesh!=null or item.binding!=null) and mode!="Object": return result
	match mode:
		"Vertex":
			for index in elements:
				if index>=0 and index<item.mesh.vertices.size(): result.append(index)
			return result
		"Edge":
			var edges := item.mesh.edges()
			for index in elements:
				if index>=0 and index<edges.size(): used[edges[index].a]=true; used[edges[index].b]=true
		"Face":
			for f in elements:
				if f>=0 and f<item.mesh.faces.size():
					for vertex in item.mesh.faces[f]: used[vertex]=true
		_:
			for i in item.mesh.vertices.size(): used[i]=true
	for index in used: result.append(index)
	return result
func edit_mesh(kind: String, amount: float=.2, preview: bool=false) -> String:
	var item := primary()
	if item==null or item.mesh==null or item.locked: return "Select an unlocked mesh first."
	if item.skin_mesh!=null or item.binding!=null: return "Bound mesh geometry is preserved. Detach it in Rigging before editing topology."
	var mesh := item.mesh; var result: KiwiModelMesh; var chosen := elements.duplicate()
	var selected_set := {}
	for index in elements: selected_set[index]=true
	match kind:
		"Extrude","Extrude individual","Inset":
			if mode!="Face" or elements.is_empty(): return "Select faces first (4)."
			var output := KiwiModelGeometry.inset(mesh,elements,amount) if kind=="Inset" else KiwiModelGeometry.extrude(mesh,elements,amount,kind=="Extrude individual")
			result=output.mesh; chosen=output.selection
		"Subdivide":
			if mode=="Edge" and not elements.is_empty(): result=KiwiModelGeometry.subdivide_edges(mesh,elements)
			else: result=KiwiModelGeometry.subdivide(mesh,elements if mode=="Face" else PackedInt32Array())
		"Bevel":
			var edges := elements.duplicate() if mode=="Edge" else PackedInt32Array()
			if mode=="Face" and not elements.is_empty():
				var topology := mesh.edges()
				for i in topology.size():
					for face in topology[i].faces:
						if elements.has(face): edges.append(i); break
			result=KiwiModelGeometry.bevel(mesh,edges,amount)
			if result==null: return "Bevel currently supports convex meshes with up to 64 clipping planes."
		"Weld": result=KiwiModelGeometry.weld(mesh,amount)
		"Smooth": result=KiwiModelGeometry.smooth_mesh(mesh,amount)
		"Flip normals":
			result=mesh.copy_mesh()
			for f in result.faces.size():
				if elements.is_empty() or mode!="Face" or selected_set.has(f): result.faces[f].reverse(); result.uv[f].reverse()
		"Delete":
			var removed := PackedInt32Array(); var vertices := selected_vertices()
			var vertex_set := {}
			for index in vertices: vertex_set[index]=true
			for f in mesh.faces.size():
				if mode=="Face" and selected_set.has(f): removed.append(f)
				elif mode!="Face":
					for vertex in mesh.faces[f]:
						if vertex_set.has(vertex): removed.append(f); break
			result=KiwiModelGeometry.remove_faces(mesh,removed); chosen=PackedInt32Array()
	if result==null: return "Unsupported operation."
	if result.faces.is_empty() and not mesh.faces.is_empty() and kind!="Delete": return "Operation would remove the mesh. Use a smaller amount."
	var errors := result.validate()
	if not errors.is_empty(): return "Operation cancelled: "+errors[0]
	var apply := func(): item.mesh=result; item.generator=""; elements=chosen if kind in ["Extrude","Extrude individual","Inset"] else PackedInt32Array()
	if preview: apply.call(); changed.emit()
	else: action(kind,apply)
	return ""
func duplicate_selected(preview: bool=false) -> void:
	var duplicate := func():
		var mapping := {}; var copies: Array[KiwiModelComponent]=[]
		for item in document.components:
			var included := selected.has(item.id)
			for id in selected:
				if document.is_descendant(item.id,id): included=true; break
			if included:
				var copy := item.copy_component(true); copy.title+=" copy"; mapping[item.id]=copy.id; copies.append(copy)
		for copy in copies:
			if mapping.has(copy.parent_id): copy.parent_id=mapping[copy.parent_id]
			if mapping.has(copy.skeleton_id): copy.skeleton_id=mapping[copy.skeleton_id]
			document.components.append(copy)
		var roots := selected.duplicate(); selected.clear()
		for id in roots:
			if mapping.has(id): selected.append(mapping[id])
	if preview: begin(); duplicate.call(); changed.emit()
	else: action("Duplicate components",duplicate)

func group_selected() -> void:
	if selected.is_empty(): return
	action("Group components",func():
		var group := KiwiModelComponent.new(); group.id=ActorData.new_id(); group.title="Group"
		var roots: Array[KiwiModelComponent]=[]; var worlds := {}
		for id in selected:
			var nested := false
			for other in selected:
				if document.is_descendant(id,other): nested=true; break
			if not nested:
				var item := document.component(id); roots.append(item); worlds[id]=document.world_transform(item); group.transform.origin+=worlds[id].origin
		group.transform.origin/=maxi(1,roots.size()); document.components.append(group)
		for item in roots: item.parent_id=group.id; item.transform=group.transform.affine_inverse()*worlds[item.id]
		selected.assign([group.id]); elements=PackedInt32Array())
func parent_selected(unparent: bool=false) -> void:
	var target := primary()
	if target==null: return
	var ids: Array[String]=selected.duplicate()
	if not unparent: ids.erase(target.id)
	reparent_components(ids,"" if unparent else target.id)

func can_reparent(ids: Array[String], parent_id: String) -> bool:
	var target := document.component(parent_id)
	if not parent_id.is_empty() and (target==null or not document.editable_component(target)): return false
	var changes := false
	var roots := _reparent_roots(ids)
	for id in ids:
		var item := document.component(id)
		if item==null or not document.editable_component(item): return false
		if id==parent_id or document.is_descendant(parent_id,id): return false
		if roots.has(id): changes=changes or item.parent_id!=parent_id
	return changes

func _reparent_roots(ids: Array[String]) -> Array[String]:
	var roots: Array[String]=[]
	for id in ids:
		var nested := false
		for other in ids:
			if document.is_descendant(id,other): nested=true; break
		if not nested: roots.append(id)
	return roots

func reparent_components(ids: Array[String], parent_id: String) -> void:
	if not can_reparent(ids,parent_id): return
	# Snapshot every world pose before changing any parent (including selections
	# that contain both a parent and its descendant).
	var worlds := {}
	var roots := _reparent_roots(ids)
	for id in roots: worlds[id]=document.world_transform(document.component(id))
	var target := document.component(parent_id)
	var inverse := document.world_transform(target).affine_inverse() if target!=null else Transform3D.IDENTITY
	action("Unparent components" if parent_id.is_empty() else "Parent components",func():
		for id in roots:
			var item := document.component(id); item.parent_id=parent_id; item.transform=inverse*worlds[id]
		mode="Object"; elements=PackedInt32Array())
func delete_selected() -> String:
	if mode!="Object":
		if not elements.is_empty(): return edit_mesh("Delete")
		return ""
	for item in document.components:
		if selected.has(item.skeleton_id) and not selected.has(item.id): return "Detach this armature's meshes first, or select them together with the armature for deletion."
	action("Delete components",func():
		for item in document.components:
			if selected.has(item.parent_id) and not selected.has(item.id): item.transform=document.world_transform(item); item.parent_id=""
		document.components=document.components.filter(func(item:KiwiModelComponent)->bool: return not selected.has(item.id) or item.locked)
		selected.clear(); elements=PackedInt32Array())
	return ""
func join_selected() -> void:
	var target := primary()
	if target==null or selected.size()<2: return
	for id in selected:
		var item := document.component(id)
		if item.is_skeleton or item.skin_mesh!=null or item.binding!=null: return
	action("Join meshes",func():
		var world := document.world_transform(target); var mesh := KiwiModelMesh.new(); var mats: Array[Material]=[]; var worlds := {}
		for item in document.components: worlds[item.id]=document.world_transform(item)
		for id in selected:
			var item := document.component(id)
			if item.mesh!=null:
				var offset := mats.size(); var slots := item.surface_materials.duplicate()
				var highest := 0
				for material in item.mesh.materials: highest=maxi(highest,material)
				while slots.size()<=highest: slots.append(null)
				mesh.append_mesh(KiwiModelModifiers.evaluate(item),world.affine_inverse()*document.world_transform(item),offset); mats.append_array(slots)
		target.mesh=mesh; target.surface_materials=mats; target.modifiers.clear(); target.generator=""
		while selected.has(target.parent_id):
			var ancestor := document.component(target.parent_id); target.parent_id=ancestor.parent_id if ancestor!=null else ""
		target.transform=(worlds[target.parent_id] as Transform3D).affine_inverse()*world if worlds.has(target.parent_id) else world
		for item in document.components:
			if item!=target and selected.has(item.parent_id) and item.parent_id!=target.id:
				item.parent_id=target.id; item.transform=world.affine_inverse()*worlds[item.id]
		document.components=document.components.filter(func(item:KiwiModelComponent)->bool: return not selected.has(item.id) or item==target)
		selected.assign([target.id]); elements=PackedInt32Array())
