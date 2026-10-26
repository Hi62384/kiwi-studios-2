class_name KiwiRigEditor
extends RefCounted
var session: KiwiModelSession
var rig_id := ""
var selected_bone: int:
	get: return int(session.rig_selection.get(rig_id,0)) if session!=null else 0
	set(value):
		if session!=null: session.rig_selection[rig_id]=value
var enabled := false
var mode := "Edit"
var symmetry := false
var symmetry_axis := 0
var symmetry_offset := 0.
var show_bones := true
var only_chain := false
var connected := true
var busy := false
var message := ""

func _init(owner: KiwiModelSession=null) -> void: session=owner
func rig() -> KiwiModelComponent:
	var primary := session.primary()
	if rig_id.is_empty():
		if primary!=null and primary.is_skeleton: rig_id=primary.id
		elif primary!=null and not primary.skeleton_id.is_empty(): rig_id=primary.skeleton_id
	var result := session.document.component(rig_id)
	if result==null:
		for item in session.document.components:
			if item.is_skeleton: result=item; rig_id=item.id; break
	if result!=null: KiwiRigMath.ensure(result); selected_bone=clampi(selected_bone,0,maxi(0,result.bones.size()-1))
	return result
func meshes() -> Array[KiwiModelComponent]:
	var result: Array[KiwiModelComponent]=[]
	for item in session.document.components:
		if item.mesh==null or not session.document.editable_component(item): continue
		var included := session.selected.has(item.id)
		for id in session.selected:
			if session.document.is_descendant(item.id,id): included=true
		if included: result.append(item)
	if result.is_empty() and rig()!=null:
		for item in session.document.components:
			if item.mesh!=null and item.skeleton_id==rig_id and session.document.editable_component(item): result.append(item)
	return result
func bounds() -> AABB:
	var first := true; var result := AABB(Vector3.ONE*-.5,Vector3.ONE)
	for item in meshes():
		var box := session.document.world_transform(item)*item.mesh.bounds(); result=box if first else result.merge(box); first=false
	return result
func create(kind: String="Flexible chain", count: int=6) -> KiwiModelComponent:
	var item := KiwiRigTemplates.create(kind,bounds(),count)
	session.action("Create "+kind+" rig",func(): session.document.components.append(item))
	rig_id=item.id; selected_bone=0; enabled=true; mode="Edit"; message="Drag joints to fit. Bind when ready."; return item
func empty_rig() -> KiwiModelComponent:
	var item := KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title="Armature"; item.is_skeleton=true
	session.action("Create armature",func(): session.document.components.append(item)); rig_id=item.id; enabled=true; mode="Draw"; return item
static func source(item: KiwiModelComponent) -> Mesh:
	if item.binding!=null: return item.binding.source_mesh
	if item.skin_mesh!=null: return item.skin_mesh
	if item.geometry_source!=null and item.modifiers.is_empty() and item.geometry_source_hash==hash([item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials]): return item.geometry_source
	return KiwiModelModifiers.evaluate(item).render_mesh(item.surface_materials)
func bind(method: String="Smooth", influences: int=4) -> String:
	var armature := rig(); var targets := meshes()
	if armature==null or armature.bones.is_empty(): return "Create bones first."
	if targets.is_empty(): return "Select one or more meshes to bind."
	var bindings := {}; var inverse := session.document.world_transform(armature).affine_inverse()
	var total_vertices := 0
	for item in targets:
		var original := source(item); var transform := inverse*session.document.world_transform(item)
		if method=="Rigid":
			var data := KiwiRigBinding.new(); data.source_mesh=original; data.mesh_to_rig=transform
			for bone in armature.bones: data.bone_ids.append(str(bone.id))
			data.rigid_bone_id=str(armature.bones[selected_bone].id); data.attachment_offset=KiwiRigMath.globals(armature.bones)[selected_bone].affine_inverse()*transform; bindings[item.id]=data
		else:
			var vertices := 0
			for surface in original.get_surface_count():
				if original.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: return "Soft binding needs triangular mesh surfaces. Use Rigid for line or point components."
				vertices+=(original.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			total_vertices+=vertices
			if total_vertices>KiwiRigWeighting.MAX_VERTICES or total_vertices*armature.bones.size()>KiwiRigWeighting.MAX_PAIRS: return "Weighting limit: 100,000 source vertices / 3 million vertex-bone pairs. Bind smaller selections or use fewer bones."
			var data := KiwiRigWeighting.compute(original,armature.bones,transform,method,influences)
			if data==null: return "No eligible deforming bones. Enable at least one bone's deform metadata."
			bindings[item.id]=data
	return install_bindings(armature.id,bindings)
func install_bindings(id: String, bindings: Dictionary) -> String:
	var armature := session.document.component(id)
	if armature==null: return "Armature no longer exists."
	if bindings.is_empty(): return "No usable weights were generated. Nothing changed."
	for component_id: String in bindings:
		var item := session.document.component(component_id); var data: KiwiRigBinding=bindings[component_id]
		if item==null or item.binding==null or item.binding.locked_bones.is_empty() or not data.rigid_bone_id.is_empty(): continue
		var old := item.binding; data.locked_bones=old.locked_bones.duplicate()
		for locked in old.locked_bones:
			if not data.bone_ids.has(locked): return "Locked influences do not exist on the chosen armature. Unlock them before rebinding to another rig."
		if old.source_mesh!=data.source_mesh: return "Locked weights need the same source topology. Unlock or restore it first."
		for surface in data.indices.size():
			var changes := {}
			for v in data.weights[surface].size()/data.influence_count:
				var values := data.vertex(surface,v); var previous := old.vertex(surface,v)
				for b in data.bone_ids.size():
					if data.locked_bones.has(data.bone_ids[b]): values[b]=float(previous.get(old.bone_ids.find(data.bone_ids[b]),0.))
				changes[v]=data.normalized(values)
			data.assign_vertices(surface,changes)
	for data: KiwiRigBinding in bindings.values():
		var errors := data.validate(armature)
		if not errors.is_empty(): return errors[0]
	session.action("Bind meshes to armature",func():
		for component_id: String in bindings:
			var item := session.document.component(component_id)
			if item==null: continue
			item.binding=bindings[component_id]; item.skeleton_id=armature.id
			if item.binding.rigid_bone_id.is_empty(): item.skin=item.binding.make_skin(armature); item.skin_mesh=item.binding.render_mesh()
			else: item.skin=null; item.skin_mesh=null)
	message="Bound %d mesh(es). Pose the bones to test deformation."%bindings.size(); return ""
static func refresh_bindings(document: KiwiModelDocument, armature: KiwiModelComponent, remap: bool=false, fallback: Dictionary={}) -> void:
	for item in document.components:
		if item.skeleton_id!=armature.id or item.binding==null: continue
		if remap: item.binding.remap(armature,fallback)
		if item.binding.rigid_bone_id.is_empty():
			item.skin=item.binding.make_skin(armature)
			if remap: item.skin_mesh=item.binding.render_mesh()
		else:
			for i in armature.bones.size():
				if str(armature.bones[i].id)==item.binding.rigid_bone_id: item.binding.attachment_offset=KiwiRigMath.globals(armature.bones)[i].affine_inverse()*item.binding.mesh_to_rig

func can_edit_rest() -> bool:
	var armature := rig()
	if armature==null: return true
	for item in session.document.components:
		if item.skeleton_id==armature.id and item.skin_mesh!=null and item.binding==null:
			message="Adopt imported weights in Weight mode before editing this rig's rest structure, or explicitly rebind its meshes. Original custom binds are preserved."
			return false
	return true
func add(head: Vector3, tail: Vector3, parent_index: int=-1) -> void:
	if not can_edit_rest(): return
	var armature := rig()
	if armature==null: armature=empty_rig()
	session.action("Draw bone",func():
		selected_bone=KiwiRigMath.add_bone(armature,head,tail,parent_index)
		if symmetry: _mirror(armature,PackedInt32Array([selected_bone]))
		refresh_bindings(session.document,armature,true))
func move_joint(index: int, end: bool, point: Vector3) -> void:
	if not can_edit_rest(): return
	var armature := rig(); KiwiRigMath.move_joint(armature,index,end,point,connected)
	if symmetry:
		var mirror := str(armature.bones[index].get("mirror_id",""))
		for i in armature.bones.size():
			if str(armature.bones[i].id)==mirror:
				var reflected := point; reflected[symmetry_axis]=2.*symmetry_offset-point[symmetry_axis]; KiwiRigMath.move_joint(armature,i,end,reflected,connected); break
	refresh_bindings(session.document,armature); session.changed.emit()
func reset_pose(all: bool=false) -> void:
	var armature := rig()
	if armature==null: return
	session.action("Reset rig pose",func():
		for i in armature.bones.size():
			if all or i==selected_bone: KiwiRigMath.set_rest(armature.bones[i],armature.bones[i].rest,false))
func pose(channel: String, value: Vector3) -> void:
	var armature := rig()
	if armature==null or armature.bones.is_empty(): return
	session.action("Pose bone",func(): armature.bones[selected_bone][channel]=value)
func rename(title: String) -> void:
	var armature := rig(); title=title.strip_edges()
	if armature==null or armature.bones.is_empty() or title.is_empty(): return
	if title.contains(":") or title.contains("/"): message="Bone names cannot contain ':' or '/'."; return
	for i in armature.bones.size():
		if i!=selected_bone and armature.bones[i].name==title: message="Bone names must be unique."; return
	session.action("Rename bone",func(): armature.bones[selected_bone].name=title)
func parent(parent_index: int, connect: bool=false) -> void:
	if not can_edit_rest(): return
	var armature := rig()
	if armature==null: return
	if selected_bone>=armature.bones.size() or parent_index< -1 or parent_index>=armature.bones.size() or KiwiRigMath.descendants(armature,selected_bone).has(parent_index): message="A bone cannot be parented to itself or its descendants."; return
	session.action("Parent bone",func(): KiwiRigMath.parent_bone(armature,selected_bone,parent_index,connect); refresh_bindings(session.document,armature))
func delete_bone() -> void:
	if not can_edit_rest(): return
	var armature := rig()
	if armature==null or armature.bones.is_empty(): return
	if armature.bones.size()==1:
		for item in session.document.components:
			if item.skeleton_id==armature.id: message="Detach the meshes before deleting the last bone."; return
	var removed := selected_bone; var world := KiwiRigMath.globals(armature.bones); var previous := armature.bones.duplicate(true)
	session.action("Delete bone",func():
		armature.bones.remove_at(removed)
		for i in armature.bones.size():
			if str(armature.bones[i].mirror_id)==str(previous[removed].id): armature.bones[i].mirror_id=""
			var old := i+1 if i>=removed else i; var parent_index := int(previous[old].parent)
			if parent_index==removed: parent_index=int(previous[removed].parent)
			armature.bones[i].parent=parent_index-1 if parent_index>removed else parent_index
			KiwiRigMath.set_rest(armature.bones[i],world[parent_index].affine_inverse()*world[old] if parent_index>=0 else world[old]); armature.bones[i].connected=false
		var fallback := {}
		if not armature.bones.is_empty():
			var p := int(previous[removed].parent); p=p-1 if p>removed else p
			fallback[str(previous[removed].id)]=str(armature.bones[clampi(p,0,armature.bones.size()-1)].id)
		for item in session.document.components:
			if item.skeleton_id==armature.id and item.binding!=null and fallback.has(item.binding.rigid_bone_id): item.binding.rigid_bone_id=fallback[item.binding.rigid_bone_id]
		refresh_bindings(session.document,armature,true,fallback))
	selected_bone=clampi(removed,0,maxi(0,armature.bones.size()-1))
func insert_joint() -> void:
	if not can_edit_rest(): return
	var armature := rig()
	if armature==null or armature.bones.is_empty(): return
	var world := KiwiRigMath.globals(armature.bones); var old := selected_bone; var end := KiwiRigMath.tail(armature.bones[old],world[old]); var midpoint := world[old].origin.lerp(end,.5)
	session.action("Insert bone joint",func():
		armature.bones[old].length*=.5
		var added := KiwiRigMath.add_bone(armature,midpoint,end,old,str(armature.bones[old].name)+" tip")
		for i in range(added):
			if int(armature.bones[i].parent)==old: armature.bones[i].parent=added; KiwiRigMath.set_rest(armature.bones[i],KiwiRigMath.globals(armature.bones)[added].affine_inverse()*world[i])
		selected_bone=added; refresh_bindings(session.document,armature,true))
func duplicate_chain(mirror: bool=false) -> void:
	if not can_edit_rest(): return
	var armature := rig()
	if armature==null or armature.bones.is_empty(): return
	var chosen := KiwiRigMath.descendants(armature,selected_bone)
	session.action("Mirror bones" if mirror else "Duplicate bone chain",func(): _mirror(armature,chosen,mirror); refresh_bindings(session.document,armature,true))
func _mirror(armature: KiwiModelComponent, chosen: PackedInt32Array, reflect: bool=true) -> void:
	var world := KiwiRigMath.globals(armature.bones); var mapping := {}
	for i in chosen:
		var bone := armature.bones[i]; var head := world[i].origin; var end := KiwiRigMath.tail(bone,world[i])
		if reflect: head[symmetry_axis]=2.*symmetry_offset-head[symmetry_axis]; end[symmetry_axis]=2.*symmetry_offset-end[symmetry_axis]
		else: head+=Vector3.RIGHT*.1; end+=Vector3.RIGHT*.1
		var title := str(bone.name).trim_suffix("_L")+"_R" if str(bone.name).ends_with("_L") else (str(bone.name).trim_suffix("_R")+"_L" if str(bone.name).ends_with("_R") else str(bone.name)+("_R" if reflect else " copy"))
		var parent_index := int(mapping.get(int(bone.parent),bone.parent)); var added := KiwiRigMath.add_bone(armature,head,end,parent_index,title); mapping[i]=added
		armature.bones[added].radius=bone.radius; armature.bones[added].metadata=bone.metadata.duplicate(true)
		if reflect: armature.bones[i].mirror_id=armature.bones[added].id; armature.bones[added].mirror_id=bone.id
func preset() -> KiwiRigPreset:
	var result := KiwiRigPreset.new(); var armature := rig()
	if armature!=null:
		result.title=armature.title; result.bones=armature.bones.duplicate(true)
		for bone in result.bones: KiwiRigMath.set_rest(bone,bone.rest,false)
	return result
func load_preset(value: KiwiRigPreset, fit: bool=true) -> bool:
	if value==null or not KiwiRigMath.validate(value.bones).is_empty(): return false
	var armature := KiwiModelComponent.new(); armature.id=ActorData.new_id(); armature.title=value.title; armature.is_skeleton=true; armature.bones=value.bones.duplicate(true); KiwiRigMath.ensure(armature)
	if fit and not armature.bones.is_empty():
		var world := KiwiRigMath.globals(armature.bones); var original := AABB(world[0].origin,Vector3.ZERO)
		for i in world.size(): original=original.expand(world[i].origin); original=original.expand(KiwiRigMath.tail(armature.bones[i],world[i]))
		var target := bounds(); var scale := target.size.max(Vector3.ONE*.05)/original.size.max(Vector3.ONE*.05)
		var heads := PackedVector3Array(); var tails := PackedVector3Array()
		for i in world.size(): heads.append(target.get_center()+(world[i].origin-original.get_center())*scale); tails.append(target.get_center()+(KiwiRigMath.tail(armature.bones[i],world[i])-original.get_center())*scale)
		for i in world.size(): world[i]=KiwiRigMath.frame(heads[i],tails[i]); armature.bones[i].length=heads[i].distance_to(tails[i])
		for i in world.size():
			var parent_index := int(armature.bones[i].parent); KiwiRigMath.set_rest(armature.bones[i],world[parent_index].affine_inverse()*world[i] if parent_index>=0 else world[i],false)
	session.action("Load rig preset",func(): session.document.components.append(armature)); rig_id=armature.id; enabled=true; mode="Edit"; return true
static func apply_weight_patch(target: Variant, patch: Dictionary) -> void:
	var owner: KiwiModelSession=target.get_ref() if target is WeakRef else target
	if owner==null: return
	var touched := {}
	var surfaces := {}
	for key: String in patch:
		var entry: Dictionary=patch[key]; var item := owner.document.component(entry.id)
		if item==null or item.binding==null: continue
		var surface_key := str(entry.id)+":"+str(entry.surface)
		if not surfaces.has(surface_key): surfaces[surface_key]={"item":item,"surface":int(entry.surface),"changes":{}}
		surfaces[surface_key].changes[int(entry.vertex)]=entry.values; touched[item.id]=item
	for entry: Dictionary in surfaces.values(): entry.item.binding.assign_vertices(entry.surface,entry.changes)
	for item: KiwiModelComponent in touched.values(): item.skin_mesh=item.binding.render_mesh()
	owner.changed.emit()

func adopt_imported() -> String:
	var armature := rig()
	if armature==null: return "Select an armature."
	var bindings := {}; var rest := KiwiRigMath.globals(armature.bones)
	for item in meshes():
		if item.skeleton_id!=armature.id or item.skin_mesh==null or item.binding!=null: continue
		var data := KiwiRigBinding.new(); data.source_mesh=item.skin_mesh; data.mesh_to_rig=session.document.world_transform(armature).affine_inverse()*session.document.world_transform(item)
		if item.skin==null or not data.mesh_to_rig.is_equal_approx(Transform3D.IDENTITY): return "Imported custom mesh-space binding retained. Rebind explicitly to make its weights editable."
		for bone in armature.bones: data.bone_ids.append(str(bone.id))
		var remap := {}
		for slot in item.skin.get_bind_count():
			var bone_index := item.skin.get_bind_bone(slot)
			if bone_index<0:
				for i in armature.bones.size():
					if str(armature.bones[i].name)==str(item.skin.get_bind_name(slot)): bone_index=i; break
			if bone_index<0 or bone_index>=rest.size(): return "Invalid imported skin binding. Original retained."
			if not item.skin.get_bind_pose(slot).is_equal_approx(rest[bone_index].affine_inverse()): return "Custom imported bind matrices retained. Rebind explicitly to generate editable weights."
			remap[slot]=bone_index
		for surface in data.source_mesh.get_surface_count():
			var arrays := data.source_mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES]==null or arrays[Mesh.ARRAY_WEIGHTS]==null: return "This surface has no editable skin weights."
			var ids: PackedInt32Array=(arrays[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate(); var weights: PackedFloat32Array=(arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).duplicate()
			data.influence_count=ids.size()/(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for i in ids.size(): ids[i]=int(remap.get(ids[i],0))
			data.indices.append(ids); data.weights.append(weights)
		bindings[item.id]=data
	if bindings.is_empty(): return "No imported skins selected."
	return install_bindings(armature.id,bindings)

func cleanup(kind: String="Fix Weights") -> String:
	var armature := rig()
	if armature==null: return "Select an armature first."
	var before := {}; var after := {}; var mirror_lookup := {}; var targets := meshes()
	var mirror_side := -1.
	if kind=="Mirror weights":
		var selected_rest := KiwiRigMath.globals(armature.bones)[selected_bone]
		mirror_side=signf(selected_rest.origin[symmetry_axis]-symmetry_offset)
		if is_zero_approx(mirror_side): mirror_side=signf(KiwiRigMath.tail(armature.bones[selected_bone],selected_rest)[symmetry_axis]-symmetry_offset)
		if is_zero_approx(mirror_side): mirror_side=-1.
		for item in targets:
			if item.binding==null or not item.binding.rigid_bone_id.is_empty(): continue
			for surface in item.binding.source_mesh.get_surface_count():
				var points: PackedVector3Array=item.binding.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v in points.size():
					var p := item.binding.mesh_to_rig*points[v]; var values := {}
					for b: int in item.binding.vertex(surface,v):
						var id := item.binding.bone_ids[b]
						for bone in armature.bones:
							if str(bone.id)==id: id=str(bone.mirror_id) if not str(bone.mirror_id).is_empty() else id; break
						values[id]=float(item.binding.vertex(surface,v)[b])
					mirror_lookup[Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))]=values
	for item in targets:
		if item.binding==null or not item.binding.rigid_bone_id.is_empty(): continue
		var data := item.binding; var selected := data.bone_ids.find(str(armature.bones[selected_bone].id))
		for surface in data.indices.size():
			var points: PackedVector3Array=data.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in points.size():
				var old := data.vertex(surface,v); var next := data.normalized(old,0,.00001 if kind=="Fix Weights" else 0.)
				if kind=="Clear influence": next=KiwiRigWeighting.corrected(data,surface,v,selected,"Clear",1.)
				elif kind=="Mirror weights":
					var p := data.mesh_to_rig*points[v]
					if (p[symmetry_axis]-symmetry_offset)*mirror_side>=-.0001: continue
					p[symmetry_axis]=2.*symmetry_offset-p[symmetry_axis]
					var key := Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))
					if not mirror_lookup.has(key): continue
					var values := {}
					for id: String in mirror_lookup[key]:
						var b := data.bone_ids.find(id)
						if b>=0: values[b]=mirror_lookup[key][id]
					for b: int in old:
						if data.locked_bones.has(data.bone_ids[b]): values[b]=old[b]
					next=data.normalized(values)
				if next==old: continue
				var key := "%s:%d:%d"%[item.id,surface,v]
				before[key]={"id":item.id,"surface":surface,"vertex":v,"values":old}; after[key]={"id":item.id,"surface":surface,"vertex":v,"values":next}
	if after.is_empty(): return "No weights needed changing."
	apply_weight_patch(session,after); session.custom_action(kind,apply_weight_patch.bind(weakref(session),before),apply_weight_patch.bind(weakref(session),after),before.size()); return ""

func detach() -> void:
	var targets := meshes()
	session.action("Detach rig meshes",func():
		for item in targets: item.binding=null; item.skin=null; item.skin_mesh=null; item.skeleton_id="")
