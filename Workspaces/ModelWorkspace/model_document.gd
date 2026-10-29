class_name KiwiModelDocument
extends Resource
@export var version := 1
@export var components: Array[KiwiModelComponent] = []
@export var workspace_state: Dictionary = {}
@export var preview: Texture2D
@export var preview_png := PackedByteArray()
var _thumbnail: Texture2D

func thumbnail() -> Texture2D:
	if _thumbnail!=null: return _thumbnail
	if not preview_png.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(preview_png)==OK: _thumbnail=ImageTexture.create_from_image(image)
	return _thumbnail if _thumbnail!=null else preview

func validate() -> PackedStringArray:
	var errors := PackedStringArray(); var ids := {}
	for item in components:
		if item.id.is_empty() or ids.has(item.id): errors.append("Missing or duplicate component identity")
		ids[item.id]=true
		if not item.transform.origin.is_finite() or not item.transform.basis.is_finite() or absf(item.transform.basis.determinant())<.0000001: errors.append("Invalid component transform")
		if item.mesh!=null: errors.append_array(_component_geometry_errors(item))
		if item.is_skeleton: errors.append_array(KiwiRigMath.validate(item.bones))
	for item in components:
		if item.growth!=null and (component(item.growth.source_id)==null or component(item.growth.source_id).growth!=null): errors.append("Missing or invalid surface-growth source")
		if not item.parent_id.is_empty() and (not ids.has(item.parent_id) or is_descendant(item.parent_id,item.id) or item.parent_id==item.id): errors.append("Invalid component hierarchy")
		if item.binding!=null:
			var armature := component(item.skeleton_id)
			if armature==null or not armature.is_skeleton: errors.append("Missing bound armature")
			else: errors.append_array(item.binding.validate(armature))
	return errors
func _component_geometry_errors(item: KiwiModelComponent) -> PackedStringArray: return item.mesh.validate()

func component(id: String) -> KiwiModelComponent:
	for item in components:
		if item.id==id: return item
	return null

func snapshot() -> KiwiModelDocument:
	var result := KiwiModelDocument.new(); result.version=version; result.preview=preview; result.preview_png=preview_png; result.workspace_state=workspace_state.duplicate(true)
	var shared:={}
	for item in components:
		var copy:=item.copy_component()
		if item.growth!=null:
			if item.growth.appearance!=null:
				var id:=item.growth.appearance.get_instance_id()
				if shared.has(id): copy.growth.appearance=shared[id]
				else: shared[id]=copy.growth.appearance
			for index in item.growth.regions.size():
				var material:=item.growth.regions[index].get("material") as KiwiGrowthMaterial
				if material==null: continue
				var id:=material.get_instance_id()
				if shared.has(id): copy.growth.regions[index].material=shared[id]
				else: shared[id]=copy.growth.regions[index].material
		result.components.append(copy)
	return result

func world_transform(item: KiwiModelComponent) -> Transform3D:
	var result := item.transform; var seen := {item.id:true}; var ancestor := component(item.parent_id)
	while ancestor!=null and not seen.has(ancestor.id):
		seen[ancestor.id]=true; result=ancestor.transform*result; ancestor=component(ancestor.parent_id)
	return result
func hierarchy_state(chosen: Array[String]=[]) -> Dictionary:
	# One indexed traversal for whole-document previews, rather than searching the
	# full component array again for every ancestor of every rendered component.
	var lookup: Dictionary={}; var poses: Dictionary={}; var visible: Dictionary={}; var selected: Dictionary={}; var chosen_ids: Dictionary={}
	for item in components: lookup[item.id]=item
	for id in chosen: chosen_ids[id]=true
	for item in components:
		if poses.has(item.id): continue
		var chain: Array[KiwiModelComponent]=[]; var seen: Dictionary={}; var current: KiwiModelComponent=item
		while current!=null and not poses.has(current.id) and not seen.has(current.id):
			seen[current.id]=true; chain.append(current); current=lookup.get(current.parent_id)
		var pose: Transform3D=poses.get(current.id,Transform3D.IDENTITY) if current!=null else Transform3D.IDENTITY; var shown: bool=visible.get(current.id,true) if current!=null else true; var included: bool=selected.get(current.id,false) if current!=null else false
		for index in range(chain.size()-1,-1,-1):
			var part:=chain[index]; pose*=part.transform; shown=shown and part.visible; included=included or chosen_ids.has(part.id); poses[part.id]=pose; visible[part.id]=shown; selected[part.id]=included
	return {"poses":poses,"visible":visible,"selected":selected}

func is_descendant(id: String, ancestor_id: String) -> bool:
	var item := component(id); var seen := {}
	while item!=null and not seen.has(item.id):
		seen[item.id]=true
		if item.parent_id==ancestor_id: return true
		item=component(item.parent_id)
	return false

func visible_component(item: KiwiModelComponent) -> bool:
	var seen := {}
	while item!=null and not seen.has(item.id):
		if not item.visible: return false
		seen[item.id]=true; item=component(item.parent_id)
	return true

func editable_component(item: KiwiModelComponent) -> bool:
	var seen := {}
	while item!=null and not seen.has(item.id):
		if item.locked or not item.visible: return false
		seen[item.id]=true; item=component(item.parent_id)
	return true

func instantiate_model() -> Node3D:
	prepare_growth()
	var root := KiwiRigModelRuntime.new(); root.name="KiwiModel"
	var nodes := {}
	var material_scope: Dictionary={}
	for item in components:
		var node := ActorSkeletonRigRuntime.create_skeleton(item.bones) if item.is_skeleton else Node3D.new(); node.name=item.title.validate_node_name(); node.transform=item.transform; node.visible=item.visible; node.set_meta("kiwi_component_id",item.id); node.set_meta("kiwi_component_pivot",item.pivot)
		root.add_child(node); nodes[item.id]=node
		if item.growth!=null:
			var visual:=KiwiSurfaceGrowthInstance.new(); visual.configure(item); node.add_child(visual)
		elif item.mesh!=null and item.mesh.validate().is_empty():
			var visual := MeshInstance3D.new(); visual.mesh=item.skin_mesh if item.skin_mesh!=null else (item.binding.source_mesh if item.binding!=null else item.render_mesh(material_scope)); visual.skin=item.skin; visual.layers=1; node.add_child(visual)
	for item in components:
		if nodes.has(item.parent_id) and item.parent_id!=item.id and not (nodes[item.id] as Node).is_ancestor_of(nodes[item.parent_id]):
			var node: Node3D=nodes[item.id]; root.remove_child(node); nodes[item.parent_id].add_child(node)
	for item in components:
		if not item.skeleton_id.is_empty() and nodes.has(item.skeleton_id):
			if item.growth!=null:
				for child in nodes[item.id].get_children():
					if child is KiwiSurfaceGrowthInstance: child.growth_skeleton=nodes[item.skeleton_id]
				continue
			if item.binding!=null and not item.binding.rigid_bone_id.is_empty():
				var armature := component(item.skeleton_id)
				for i in armature.bones.size():
					if str(armature.bones[i].id)==item.binding.rigid_bone_id: root.attachments.append({"target":nodes[item.id],"skeleton":nodes[item.skeleton_id],"bone":i,"offset":item.binding.attachment_offset})
				continue
			for child in nodes[item.id].get_children():
				if child is MeshInstance3D:
					child.skeleton=child.get_path_to(nodes[item.skeleton_id])
					if item.binding!=null and item.binding.rigid_bone_id.is_empty(): child.transform=world_transform(item).affine_inverse()*world_transform(component(item.skeleton_id))
	return root

static func transform_values(transform: Transform3D) -> Dictionary:
	var rotation := transform.basis.get_rotation_quaternion().get_euler()
	var scale := transform.basis.get_scale()
	var basis := Basis.from_euler(rotation)*Basis.from_scale(scale)
	# Keep affine/sheared transforms exact, while exposing ordinary editable TRS.
	return {&"position":transform.origin,&"rotation":Vector3(rad_to_deg(rotation.x),rad_to_deg(rotation.y),rad_to_deg(rotation.z)),&"scale":scale,
		&"model_basis_residual":basis.inverse()*transform.basis}

func actor_scene(registry: ActorRegistry, source_path: String) -> ActorSceneData:
	prepare_growth()
	var scene := ActorSceneData.new()
	if not validate().is_empty(): return scene
	var native := source_path.get_extension().to_lower() in ["tres","res"] and ResourceLoader.load(source_path) is KiwiModelDocument
	for item in components:
		var definition := registry.get_definition(&"skeleton_rig" if item.is_skeleton else (&"basic_mesh" if item.mesh!=null else &"point_3d"))
		if definition==null: return ActorSceneData.new()
		var actor := definition.create_actor()
		actor.id=item.id; actor.parent_id=item.parent_id; actor.display_name=item.title
		actor.values.merge(transform_values(item.transform),true)
		actor.values.merge(item.structural.duplicate(true),true)
		actor.values[&"model_component_source"]=source_path; actor.values[&"model_component_id"]=item.id; actor.values[&"model_component_bind_transform"]=item.transform; actor.values[&"model_component_bind_parent"]=item.parent_id; actor.values[&"model_component_bind_structure"]=item.structural.duplicate(true)
		actor.show_timeline_children=true; actor.link_timeline_children=true
		if item.is_skeleton:
			actor.values[&"rig_bones"]=item.bones.duplicate(true)
			var poses := {}
			for i in item.bones.size():
				var bone := item.bones[i]; poses[str(i)]={"position":bone.position,"rotation":bone.rotation,"scale":bone.scale}
			actor.values[&"bone_poses"]=poses
		if item.mesh!=null:
			actor.values[&"mesh_path"]=source_path
			actor.values[&"model_component_source"]=source_path
			actor.values[&"model_component_id"]=item.id
			if not item.skeleton_id.is_empty():
				actor.values[&"model_skeleton_actor"]=item.skeleton_id
				var armature := component(item.skeleton_id)
				if armature!=null:
					# Scene rigs own their pose tracks. Keep a compatible skin snapshot
					# rather than mixing newly edited source rests with old scene bones.
					actor.values[&"model_rig_bind_signature"]=KiwiRigMath.bind_signature(armature.bones)
					actor.values[&"model_component_data"]=item.copy_component()
			if item.binding!=null:
				actor.values[&"model_skin_in_rig_space"]=item.binding.rigid_bone_id.is_empty()
				if not item.binding.rigid_bone_id.is_empty():
					var armature := component(item.skeleton_id)
					for i in armature.bones.size():
						if str(armature.bones[i].id)==item.binding.rigid_bone_id:
							actor.values[&"model_rigid_bone"]=i; actor.values[&"model_rigid_rest_inverse"]=KiwiRigMath.globals(armature.bones)[i].affine_inverse()
			# Imported GLTF/PackedScene component IDs are generated during import,
			# so embed independent editable mesh data rather than relying on IDs
			# from a second import. Native models stay linked by their stable ID.
			if not native or item.growth!=null: actor.values[&"model_component_data"]=item.copy_component()
			if item.growth!=null: KiwiGrowthActor.initialize(actor,item.growth)
		if not visible_component(item): actor.values[&"model_component_hidden"]=true
		scene.actors.append(actor)
		var clip := ActorClip.create(actor,0.,5.); clip.layer=scene.clips.size(); scene.clips.append(clip)
	return scene
func prepare_growth() -> void:
	for item: KiwiModelComponent in components:
		if item.growth!=null:
			var error:=KiwiSurfaceGrowth.prepare(self,item,component(item.growth.source_id))
			if not error.is_empty(): item.growth.error=error
