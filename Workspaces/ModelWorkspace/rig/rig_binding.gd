class_name KiwiRigBinding
extends Resource
## Source surfaces are immutable and shared by history. Only influence arrays
## change during painting; pose changes never rebuild a mesh.
@export var source_mesh: Mesh
@export var mesh_to_rig := Transform3D.IDENTITY
@export var bone_ids := PackedStringArray()
@export var indices: Array[PackedInt32Array]=[]
@export var weights: Array[PackedFloat32Array]=[]
@export var influence_count := 4
@export var locked_bones := PackedStringArray()
@export var rigid_bone_id := ""
@export var attachment_offset := Transform3D.IDENTITY
var revision := 0
var _topology: Dictionary={}

func topology() -> Dictionary:
	if _topology.is_empty():
		_topology=KiwiRigWeighting.geometry(source_mesh,mesh_to_rig)
		var representatives := {}; var mappings: Array=_topology.surfaces
		for surface in mappings.size():
			for v in mappings[surface].size(): representatives[mappings[surface][v]]=Vector2i(surface,v)
		_topology["representatives"]=representatives
	return _topology

func copy_binding() -> KiwiRigBinding:
	var result := KiwiRigBinding.new(); result.source_mesh=source_mesh; result.mesh_to_rig=mesh_to_rig; result.bone_ids=bone_ids.duplicate(); result.influence_count=influence_count
	for array in indices: result.indices.append(array.duplicate())
	for array in weights: result.weights.append(array.duplicate())
	result.locked_bones=locked_bones.duplicate(); result.rigid_bone_id=rigid_bone_id; result.attachment_offset=attachment_offset; result.revision=revision; result._topology=_topology
	return result

func signature() -> int: return hash([source_mesh,mesh_to_rig,bone_ids,indices,weights,locked_bones,rigid_bone_id,attachment_offset])

func vertex(surface: int, index: int) -> Dictionary:
	var result := {}
	for k in influence_count:
		var offset := index*influence_count+k
		var bone := indices[surface][offset]; var weight := weights[surface][offset]
		if weight>0.: result[bone]=float(result.get(bone,0.))+weight
	return result

func assign(surface: int, index: int, values: Dictionary) -> void:
	assign_vertices(surface,{index:values})

func assign_vertices(surface: int, changes: Dictionary) -> void:
	# Packed arrays use copy-on-write. Write a whole changed surface in one pass,
	# not a full-array allocation for every painted vertex.
	var ids := indices[surface]; var amounts := weights[surface]
	for index: int in changes:
		var values: Dictionary=changes[index]; var keys := values.keys()
		keys.sort_custom(func(a: Variant,b: Variant) -> bool: return float(values[a])>float(values[b]))
		for k in influence_count:
			var offset := index*influence_count+k
			ids[offset]=int(keys[k]) if k<keys.size() else 0; amounts[offset]=float(values[keys[k]]) if k<keys.size() else 0.
	indices[surface]=ids; weights[surface]=amounts; revision+=1

func normalized(values: Dictionary, fallback: int=0, cutoff: float=0.) -> Dictionary:
	var fixed := {}; var free := {}; var reserved := 0.
	for key: Variant in values:
		var bone := int(key); var amount := float(values[key])
		if bone<0 or bone>=bone_ids.size() or not is_finite(amount) or amount<=0.: continue
		if locked_bones.has(bone_ids[bone]): fixed[bone]=amount; reserved+=amount
		elif amount>cutoff: free[bone]=amount
	# Impossible lock sets are left unchanged and reported by validation.
	if reserved>1.00001 or fixed.size()>influence_count: return values.duplicate()
	var order := free.keys(); order.sort_custom(func(a: Variant,b: Variant) -> bool: return float(free[a])>float(free[b]))
	order.resize(mini(order.size(),influence_count-fixed.size()))
	var total := 0.
	for key: Variant in order: total+=float(free[key])
	if total<=.0000001 and reserved<.99999:
		if not locked_bones.has(bone_ids[clampi(fallback,0,bone_ids.size()-1)]) and fixed.size()<influence_count: fixed[clampi(fallback,0,bone_ids.size()-1)]=1.-reserved
		else:
			for i in bone_ids.size():
				if not locked_bones.has(bone_ids[i]) and fixed.size()<influence_count: fixed[i]=1.-reserved; break
	else:
		for key: Variant in order: fixed[key]=float(free[key])/total*maxf(0.,1.-reserved)
	return fixed

func remap(rig: KiwiModelComponent, fallback_ids: Dictionary={}) -> void:
	var next_ids := PackedStringArray(); var lookup := {}
	for i in rig.bones.size(): next_ids.append(str(rig.bones[i].id)); lookup[str(rig.bones[i].id)]=i
	var old := bone_ids; bone_ids=next_ids
	var remapped_locks := PackedStringArray()
	for id in locked_bones:
		var mapped := str(fallback_ids.get(id,id))
		if lookup.has(mapped) and not remapped_locks.has(mapped): remapped_locks.append(mapped)
	locked_bones=remapped_locks
	for surface in indices.size():
		var changes := {}
		for v in weights[surface].size()/influence_count:
			var values := {}
			for k in influence_count:
				var offset := v*influence_count+k; var index := indices[surface][offset]
				if index<0 or index>=old.size(): continue
				var id := str(old[index]); id=str(fallback_ids.get(id,id))
				if lookup.has(id): values[lookup[id]]=float(values.get(lookup[id],0.))+weights[surface][offset]
			changes[v]=normalized(values)
		assign_vertices(surface,changes)

func validate(rig: KiwiModelComponent) -> PackedStringArray:
	var errors := PackedStringArray()
	if source_mesh==null: errors.append("Missing binding source mesh"); return errors
	if not mesh_to_rig.is_finite() or absf(mesh_to_rig.basis.determinant())<.0000001: errors.append("Invalid binding transform")
	if influence_count not in [4,8]: errors.append("Unsupported influence count"); return errors
	if not rigid_bone_id.is_empty():
		if not bone_ids.has(rigid_bone_id) or not rig.bones.any(func(bone: Dictionary): return str(bone.id)==rigid_bone_id): errors.append("Missing rigid attachment bone")
		return errors
	if indices.size()!=source_mesh.get_surface_count() or weights.size()!=indices.size(): errors.append("Missing weight surfaces"); return errors
	var available := {}
	for bone in rig.bones: available[str(bone.id)]=true
	for id in bone_ids:
		if not available.has(id): errors.append("Stale bone influence identity")
	for surface in indices.size():
		var arrays := source_mesh.surface_get_arrays(surface); var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		if indices[surface].size()!=points.size()*influence_count or weights[surface].size()!=indices[surface].size(): errors.append("Invalid weight array size"); continue
		for v in points.size():
			var sum := 0.
			for k in influence_count:
				var i := v*influence_count+k; var amount := weights[surface][i]
				if indices[surface][i]<0 or indices[surface][i]>=bone_ids.size(): errors.append("Invalid bone index"); break
				if amount<0. or not is_finite(amount): errors.append("Invalid influence weight"); break
				sum+=amount
			if absf(sum-1.)>.001: errors.append("Unweighted or non-normalized vertex"); break
	return errors

func make_skin(rig: KiwiModelComponent) -> Skin:
	var result := Skin.new(); var rest := KiwiRigMath.globals(rig.bones); var lookup := {}
	for i in rig.bones.size(): lookup[str(rig.bones[i].id)]=i
	for id in bone_ids:
		var i := int(lookup.get(id,0)); result.add_bind(i,rest[i].affine_inverse())
	return result

func render_mesh(heat_bone: int=-1) -> ArrayMesh:
	var result := ArrayMesh.new()
	if source_mesh is ArrayMesh:
		result.blend_shape_mode=source_mesh.blend_shape_mode
		for i in source_mesh.get_blend_shape_count(): result.add_blend_shape(source_mesh.get_blend_shape_name(i))
	for surface in source_mesh.get_surface_count():
		var arrays := source_mesh.surface_get_arrays(surface).duplicate(true)
		_transform_arrays(arrays,false)
		arrays[Mesh.ARRAY_BONES]=indices[surface]; arrays[Mesh.ARRAY_WEIGHTS]=weights[surface]
		if heat_bone>=0:
			var colors := PackedColorArray()
			for v in weights[surface].size()/influence_count: colors.append(Color.from_hsv((1.-float(vertex(surface,v).get(heat_bone,0.)))*.66,1.,1.))
			arrays[Mesh.ARRAY_COLOR]=colors
		var shapes: Array[Array]=[]; var lods := {}; var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if influence_count==8 else 0
		if source_mesh is ArrayMesh:
			for original in source_mesh.surface_get_blend_shape_arrays(surface):
				var shape: Array=original.duplicate(true); _transform_arrays(shape,source_mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_RELATIVE); shapes.append(shape)
			# Preserve custom channel formats and all non-bone source flags.
			flags|=source_mesh.surface_get_format(surface)&~(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS|Mesh.ARRAY_FORMAT_BONES|Mesh.ARRAY_FORMAT_WEIGHTS)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,shapes,lods,flags)
		result.surface_set_material(surface,source_mesh.surface_get_material(surface))
		if source_mesh is ArrayMesh: result.surface_set_name(surface,source_mesh.surface_get_name(surface))
	return result

func _transform_arrays(arrays: Array, relative: bool) -> void:
	if arrays.size()!=Mesh.ARRAY_MAX: return
	var normal_basis := mesh_to_rig.basis.inverse().transposed()
	if arrays[Mesh.ARRAY_VERTEX]!=null:
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in points.size(): points[i]=mesh_to_rig.basis*points[i] if relative else mesh_to_rig*points[i]
		arrays[Mesh.ARRAY_VERTEX]=points
	if arrays[Mesh.ARRAY_NORMAL]!=null:
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size(): normals[i]=normal_basis*normals[i] if relative else (normal_basis*normals[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL]=normals
	if arrays[Mesh.ARRAY_TANGENT]!=null:
		var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
		for i in tangents.size()/4:
			var next := (mesh_to_rig.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
			tangents[i*4]=next.x; tangents[i*4+1]=next.y; tangents[i*4+2]=next.z
		arrays[Mesh.ARRAY_TANGENT]=tangents

func deformed_points(rig: KiwiModelComponent, surface: int) -> PackedVector3Array:
	var rest := KiwiRigMath.globals(rig.bones); var pose := KiwiRigMath.globals(rig.bones,true); var transforms: Array[Transform3D]=[]; var lookup := {}
	for i in rig.bones.size(): lookup[str(rig.bones[i].id)]=i
	for id in bone_ids:
		var i := int(lookup.get(id,0)); transforms.append(pose[i]*rest[i].affine_inverse())
	var points: PackedVector3Array=source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]; var result := PackedVector3Array(); result.resize(points.size())
	for v in points.size():
		var point := mesh_to_rig*points[v]; var value := Vector3.ZERO
		for k in influence_count:
			var offset := v*influence_count+k; value+=transforms[indices[surface][offset]]*point*weights[surface][offset]
		result[v]=value
	return result
