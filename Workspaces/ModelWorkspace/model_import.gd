class_name KiwiModelImport
extends RefCounted
## Imports are copies; never mutate imported scenes, shared meshes or materials.
static func load_document(source: Variant) -> KiwiModelDocument:
	if source is KiwiModelDocument: return source.snapshot() if source.validate().is_empty() else KiwiModelDocument.new()
	var resource: Resource=source if source is Resource else null
	var path := str(source) if source is String else ""
	if resource==null and ResourceLoader.exists(path): resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if resource is KiwiModelDocument: return resource.snapshot() if resource.validate().is_empty() else KiwiModelDocument.new()
	var document := KiwiModelDocument.new()
	if resource is Mesh:
		_add_mesh(document,resource,Transform3D.IDENTITY,"Imported mesh")
		return document
	var scene: Node
	if resource is PackedScene: scene=resource.instantiate()
	elif path.get_extension().to_lower() in ["glb","gltf"]:
		var gltf := GLTFDocument.new(); var state := GLTFState.new()
		if gltf.append_from_file(path,state)==OK: scene=gltf.generate_scene(state)
	if scene!=null:
		var bindings := {}
		_walk(document,scene,Transform3D.IDENTITY,"",bindings)
		for node: Node in bindings:
			if node is MeshInstance3D:
				var skeleton := node.get_node_or_null(node.skeleton) as Skeleton3D
				if skeleton!=null and bindings.has(skeleton):
					var item: KiwiModelComponent=bindings[node]
					item.skin=node.skin.duplicate(true) if node.skin!=null else skeleton.create_skin_from_rest_transforms()
					item.skin_mesh=node.mesh.duplicate(true); item.skeleton_id=bindings[skeleton].id
		scene.free()
	return document

static func _walk(document: KiwiModelDocument, node: Node, accumulated: Transform3D, parent_id: String, bindings: Dictionary) -> void:
	var transform: Transform3D = accumulated*(node.transform if node is Node3D else Transform3D.IDENTITY)
	var next_parent := parent_id
	if node is Node3D:
		var item: KiwiModelComponent
		if node is MeshInstance3D and node.mesh!=null:
			item=_add_mesh(document,node.mesh,transform,str(node.name))
			for surface in node.mesh.get_surface_count():
				var material: Material=node.get_active_material(surface)
				if material!=null: item.surface_materials[surface]=material
		else:
			item=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=str(node.name); item.transform=transform; document.components.append(item)
		item.parent_id=parent_id; item.visible=node.visible
		bindings[node]=item
		if node is Skeleton3D:
			item.is_skeleton=true
			for i in node.get_bone_count():
				item.bones.append({"name":node.get_bone_name(i),"parent":node.get_bone_parent(i),"rest":node.get_bone_rest(i),
					"position":node.get_bone_pose_position(i),"rotation":node.get_bone_pose_rotation(i).get_euler()*180./PI,"scale":node.get_bone_pose_scale(i)})
		next_parent=item.id; transform=Transform3D.IDENTITY
	for child in node.get_children(): _walk(document,child,transform,next_parent,bindings)

static func _add_mesh(document: KiwiModelDocument, mesh: Mesh, transform: Transform3D, title: String) -> KiwiModelComponent:
	var item := KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=title; item.mesh=KiwiModelMesh.from_mesh(mesh); item.transform=transform
	item.geometry_source=mesh.duplicate(true); item.geometry_source_hash=hash([item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials])
	for i in mesh.get_surface_count(): item.surface_materials.append(mesh.surface_get_material(i))
	document.components.append(item)
	return item

static func boolean(owner: Node, a: KiwiModelMesh, b: KiwiModelMesh, transform: Transform3D, operation: int, a_materials: Array[Material]=[], b_materials: Array[Material]=[]) -> KiwiModelMesh:
	# Temporary CSG evaluates once, then is discarded. The editable output is
	# polygon data, never a permanent CSG hierarchy in the model or Scene Workspace.
	var root := CSGCombiner3D.new(); root.calculate_tangents=false; root.visible=false
	owner.add_child(root)
	var first := CSGMesh3D.new(); first.mesh=a.render_mesh(a_materials); root.add_child(first)
	var second := CSGMesh3D.new(); second.mesh=b.render_mesh(b_materials); second.transform=transform; second.operation=operation; root.add_child(second)
	for unused in 3:
		if not is_instance_valid(owner) or owner.get_tree()==null: return null
		await owner.get_tree().process_frame
	if not is_instance_valid(root): return null
	var baked := root.bake_static_mesh(); root.queue_free()
	if baked==null or baked.get_surface_count()==0: return null
	var mesh := KiwiModelMesh.from_mesh(baked); var materials: Array[Material]=[]
	for i in baked.get_surface_count(): materials.append(baked.surface_get_material(i))
	mesh.set_meta("boolean_materials",materials)
	return mesh
