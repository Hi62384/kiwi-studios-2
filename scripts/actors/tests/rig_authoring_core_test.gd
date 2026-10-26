extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	for category: String in KiwiRigTemplates.CATEGORIES:
		for kind: String in KiwiRigTemplates.CATEGORIES[category]:
			var rig := KiwiRigTemplates.create(kind,AABB(Vector3(-1,-2,-1),Vector3(2,4,2)),8)
			check(not rig.bones.is_empty() and KiwiRigMath.validate(rig.bones).is_empty(),"Editable valid template: "+kind)
	var session := KiwiModelSession.new(); var component := session.add("Cylinder",{"height":4.,"radius":.3,"segments":16}); component.title="Tentacle"
	var editor := KiwiRigEditor.new(session); var rig := editor.create("Tentacle",6); var id := rig.id; var mesh_id := component.id
	check(rig.bones.size()==6 and KiwiRigMath.validate(rig.bones).is_empty(),"Generated chain is independent of anatomical bone names")
	for method: String in ["Distance","Envelope","Smooth"]:
		check(editor.bind(method).is_empty(),"Functional "+method+" binding")
		component=session.document.component(mesh_id); rig=session.document.component(id)
		check(component.binding!=null and component.binding.validate(rig).is_empty(),method+" weights are finite, nonnegative, normalized and use valid indices")
		check(component.skin_mesh.get_surface_count()==component.binding.source_mesh.get_surface_count(),method+" preserves mesh surfaces")
	var binding := component.binding; var source := binding.source_mesh; var original := source.surface_get_arrays(0)
	var rendered := binding.render_mesh().surface_get_arrays(0)
	check(rendered[Mesh.ARRAY_TEX_UV]==original[Mesh.ARRAY_TEX_UV],"Binding preserves UVs")
	check((rendered[Mesh.ARRAY_BONES] as PackedInt32Array).size()==(rendered[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()*4,"Generated mesh has actual four-bone skin arrays")
	var before := binding.deformed_points(rig,0); editor.selected_bone=2; var rotation: Vector3=rig.bones[2].rotation; rotation.z+=55.; editor.pose("rotation",rotation)
	component=session.document.component(mesh_id); rig=session.document.component(id); var posed := component.binding.deformed_points(rig,0)
	check(before!=posed,"Bone posing genuinely deforms bound vertices")
	var rendered_mesh := component.skin_mesh; editor.pose("rotation",rotation+Vector3(10,0,0)); check(component.skin_mesh==rendered_mesh,"Posing does not rebuild the weighted mesh")
	session.undo(); session.undo(); component=session.document.component(mesh_id); rig=session.document.component(id)
	check(component.binding.deformed_points(rig,0)==before,"Pose undo restores the original deformation")
	var stable_ids := PackedStringArray()
	for bone in rig.bones: stable_ids.append(str(bone.id))
	editor.selected_bone=1; editor.insert_joint(); rig=session.document.component(id); component=session.document.component(mesh_id)
	check(rig.bones.size()==7 and component.binding.validate(rig).is_empty(),"Inserting a joint remaps valid skin data")
	check(str(rig.bones[1].id)==stable_ids[1],"Existing bone authoring identities survive insertion")
	session.undo(); rig=session.document.component(id); component=session.document.component(mesh_id)
	editor.selected_bone=2; editor.delete_bone(); rig=session.document.component(id); component=session.document.component(mesh_id)
	check(rig.bones.size()==5 and component.binding.validate(rig).is_empty(),"Deleting a weighted bone safely remaps its influences")
	session.undo(); rig=session.document.component(id); component=session.document.component(mesh_id)
	check(rig.bones.size()==6 and component.binding.validate(rig).is_empty(),"Bone deletion and all affected weights undo together")
	var old_rest := component.binding.deformed_points(rig,0)
	session.begin(); editor.move_joint(2,true,KiwiRigMath.tail(rig.bones[2],KiwiRigMath.globals(rig.bones)[2])+Vector3(.1,0,0)); session.commit("Edit rest joint")
	component=session.document.component(mesh_id); rig=session.document.component(id)
	var new_rest := component.binding.deformed_points(rig,0); var stable := true
	for i in old_rest.size():
		if old_rest[i].distance_to(new_rest[i])>.0001: stable=false; break
	check(stable and component.binding.validate(rig).is_empty(),"Editing a bound rest joint updates inverse binds without changing rest geometry")
	session.undo(); component=session.document.component(mesh_id); rig=session.document.component(id); binding=component.binding
	var old := binding.vertex(0,0); var bone := int(old.keys()[0]); binding.locked_bones.append(binding.bone_ids[bone])
	var corrected := KiwiRigWeighting.corrected(binding,0,0,(bone+1)%rig.bones.size(),"Add",.4)
	check(is_equal_approx(float(corrected.get(bone,0.)),float(old[bone])),"Painting respects locked influence values")
	var sum := 0.
	for value: float in corrected.values(): sum+=value
	check(is_equal_approx(sum,1.),"Painting normalizes the remaining unlocked influence budget")
	binding.locked_bones.clear()
	var weak: WeakRef=weakref(session); var patch_before := {"v":{"id":mesh_id,"surface":0,"vertex":0,"values":binding.vertex(0,0)}}
	var patch_after := {"v":{"id":mesh_id,"surface":0,"vertex":0,"values":{0:1.}}}
	KiwiRigEditor.apply_weight_patch(session,patch_after); session.custom_action("Sparse weight edit",KiwiRigEditor.apply_weight_patch.bind(weak,patch_before),KiwiRigEditor.apply_weight_patch.bind(weak,patch_after),1)
	check(session._undo.back().has("custom") and not session._undo.back().has("document"),"Weight history stores sparse vertex deltas, not whole mesh snapshots")
	session.undo(); check(session.document.component(mesh_id).binding.vertex(0,0)==patch_before.v.values,"Sparse weight painting undo restores the exact previous weights")
	session.redo(); check(session.document.component(mesh_id).binding.vertex(0,0)=={0:1.},"Sparse weight painting redo restores the correction")
	var path := "user://Authored Rig.tres"; check(ResourceSaver.save(session.document,path)==OK,"Authored weighted model saves")
	var saved := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(saved!=null and saved.validate().is_empty() and saved.component(mesh_id).binding!=null,"Weighted model reload preserves editable binding data")
	var preset := editor.preset(); var preset_path := "user://Custom Rig.tres"; ResourceSaver.save(preset,preset_path)
	check(ResourceLoader.load(preset_path,"",ResourceLoader.CACHE_MODE_IGNORE) is KiwiRigPreset,"Armatures save as standalone reusable preset assets")
	var reuse := KiwiRigEditor.new(session); check(reuse.load_preset(preset),"Saved armature fits another target without replacing the original rig")
	var original_bones := rig.bones.size(); editor.rig_id=id; editor.selected_bone=2; editor.duplicate_chain(true); rig=session.document.component(id)
	check(rig.bones.size()>original_bones and KiwiRigMath.validate(rig.bones).is_empty(),"Mirrored chains preserve valid branching and predictable names")
	session.undo(); rig=session.document.component(id); component=session.document.component(mesh_id)
	var mechanical := session.add("Gear",{},Vector3(2,0,0)); var mechanical_id := mechanical.id; editor.rig_id=id; editor.selected_bone=3
	check(editor.bind("Rigid").is_empty(),"Separate mechanical components attach to one bone")
	mechanical=session.document.component(mechanical_id)
	check(mechanical.binding!=null and not mechanical.binding.rigid_bone_id.is_empty() and mechanical.skin==null,"Rigid attachment does not require soft skin weights")
	var normal_mesh := KiwiModelMesh.from_mesh(source); var immutable: PackedVector3Array=source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(normal_mesh.validate().is_empty() and source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==immutable,"Binding leaves its immutable source geometry untouched")
	var job := KiwiRigWeightJob.new(); job.cancel(); check(job.run().is_empty(),"Canceled auto-weight jobs produce no partial bindings")
	# Independent islands should not inherit weights from an adjacent part's bone.
	var pair := KiwiModelMesh.new(); var cube := KiwiModelPrimitives.create("Box",{"size":Vector3(.2,1.,.2)})
	pair.append_mesh(cube,Transform3D(Basis.IDENTITY,Vector3(-.3,0,0))); pair.append_mesh(cube,Transform3D(Basis.IDENTITY,Vector3(.3,0,0)))
	var islands := KiwiModelComponent.new(); islands.id=ActorData.new_id(); islands.is_skeleton=true
	KiwiRigMath.add_bone(islands,Vector3(-.3,-.5,0),Vector3(-.3,.5,0),-1,"part_L"); KiwiRigMath.add_bone(islands,Vector3(.3,-.5,0),Vector3(.3,.5,0),-1,"part_R")
	var island_skin := KiwiRigWeighting.compute(pair.render_mesh(),islands.bones,Transform3D.IDENTITY,"Smooth"); var disconnected := true
	for surface in island_skin.indices.size():
		var points: PackedVector3Array=island_skin.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v in points.size():
			if float(island_skin.vertex(surface,v).get(0 if points[v].x<0 else 1,0.))<.999: disconnected=false
	check(disconnected,"Smooth weighting prevents leakage between nearby disconnected components")
	for envelope_bone in islands.bones: envelope_bone.radius=.0001
	var tiny_envelopes := KiwiRigWeighting.compute(pair.render_mesh(),islands.bones,Transform3D.IDENTITY,"Envelope"); var nearest_fallback := true
	for surface in tiny_envelopes.indices.size():
		var points: PackedVector3Array=tiny_envelopes.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v in points.size():
			if float(tiny_envelopes.vertex(surface,v).get(0 if points[v].x<0 else 1,0.))<.999: nearest_fallback=false
	check(nearest_fallback,"Vertices outside all tiny envelopes fall back to the nearest bone, never arbitrarily to the root")
	var eight := KiwiRigWeighting.compute(pair.render_mesh(),islands.bones,Transform3D.IDENTITY,"Distance",8)
	check(eight.validate(islands).is_empty() and (eight.render_mesh().surface_get_arrays(0)[Mesh.ARRAY_BONES] as PackedInt32Array).size()==(eight.source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()*8,"The reusable binding backend also supports renderer-compatible eight-influence skins")
	var wire := ArrayMesh.new(); var line := []; line.resize(Mesh.ARRAY_MAX); line[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ONE]); wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,line)
	check(KiwiRigWeighting.compute(wire,islands.bones,Transform3D.IDENTITY)==null,"Unsupported soft-bound line geometry is refused rather than converted into an invisible invalid triangle mesh")
	var unrelated := KiwiRigMath.add_bone(islands,Vector3(3,0,0),Vector3(3,1,0),-1,"Unrelated")
	KiwiRigMath.set_rest(islands.bones[unrelated],Transform3D(Basis(Vector3.UP,.7)*Basis.from_scale(Vector3(1.4,1.,.8)),Vector3(3,0,0)),false)
	var untouched: Transform3D=islands.bones[unrelated].rest; KiwiRigMath.move_joint(islands,0,true,Vector3(-.3,.7,0))
	check((islands.bones[unrelated].rest as Transform3D).is_equal_approx(untouched),"Editing one joint never resets an unrelated branch's roll or scale")
	islands.bones[0].mirror_id=islands.bones[1].id; islands.bones[1].mirror_id=islands.bones[0].id
	var symmetry_session := KiwiModelSession.new(); var mirrored_mesh := KiwiModelComponent.new(); mirrored_mesh.id=ActorData.new_id(); mirrored_mesh.mesh=pair; mirrored_mesh.binding=island_skin; mirrored_mesh.skeleton_id=islands.id; symmetry_session.document.components.assign([islands,mirrored_mesh]); symmetry_session.selected.assign([mirrored_mesh.id])
	for surface in island_skin.indices.size():
		var points: PackedVector3Array=island_skin.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]; var changes := {}
		for v in points.size():
			if points[v].x>0.: changes[v]={0:1.}
		island_skin.assign_vertices(surface,changes)
	var symmetry_editor := KiwiRigEditor.new(symmetry_session); symmetry_editor.rig_id=islands.id; symmetry_editor.selected_bone=0; symmetry_editor.cleanup("Mirror weights"); var mirrored_weights := true
	for surface in island_skin.indices.size():
		var points: PackedVector3Array=island_skin.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v in points.size():
			if float(island_skin.vertex(surface,v).get(0 if points[v].x<0 else 1,0.))<.999: mirrored_weights=false
	check(mirrored_weights,"Mirror weights copies to the opposite side without destroying the artist's source-side weights")
	# Surface attributes and relative morph deltas survive actual generated skin arrays.
	var attribute_mesh := ArrayMesh.new(); attribute_mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_RELATIVE; attribute_mesh.add_blend_shape("Expression")
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP]); arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK]); arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]); arrays[Mesh.ARRAY_TEX_UV2]=arrays[Mesh.ARRAY_TEX_UV]
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.RED,Color.GREEN,Color.BLUE]); arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var expression := []; expression.resize(Mesh.ARRAY_MAX); expression[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(.1,0,0),Vector3(.1,0,0),Vector3(.1,0,0)]); expression[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	for surface in 2:
		attribute_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[expression]); attribute_mesh.surface_set_name(surface,"Original surface "+str(surface)); attribute_mesh.surface_set_material(surface,StandardMaterial3D.new())
	var attribute_skin := KiwiRigWeighting.compute(attribute_mesh,islands.bones,Transform3D(Basis.from_scale(Vector3.ONE*2.),Vector3(3,1,2)),"Distance"); var preserved := attribute_skin.render_mesh()
	var output := preserved.surface_get_arrays(0); var original_attributes := attribute_mesh.surface_get_arrays(0)
	check(preserved.get_surface_count()==2 and preserved.surface_get_material(1)==attribute_mesh.surface_get_material(1) and preserved.surface_get_name(1)==attribute_mesh.surface_get_name(1),"Binding preserves separate surfaces, names and original material objects")
	check(output[Mesh.ARRAY_COLOR]==original_attributes[Mesh.ARRAY_COLOR] and output[Mesh.ARRAY_TEX_UV2]==original_attributes[Mesh.ARRAY_TEX_UV2],"Binding preserves vertex colors and secondary UVs")
	check(preserved.get_blend_shape_count()==1 and (preserved.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX] as PackedVector3Array)[0].distance_to(Vector3(.2,0,0))<.0001,"Relative morph targets preserve names and transform as deltas, not translated positions")
	# Imported weights are adopted only when their original bind convention is safe.
	var imported_session := KiwiModelSession.new(); var imported_body := imported_session.add("Cylinder",{"height":3.}); var imported_editor := KiwiRigEditor.new(imported_session); var imported_rig := imported_editor.create("Flexible chain",3); imported_editor.bind("Distance")
	var original_weights: PackedFloat32Array=imported_body.skin_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]; imported_body.binding=null
	check(not imported_editor.can_edit_rest(),"Rest editing blocks unadopted imported custom skin conventions")
	check(imported_editor.adopt_imported().is_empty() and imported_body.binding.weights[0]==original_weights,"Canonical imported weights become editable without discarding their authored values")
	imported_session.undo(); imported_body=imported_session.primary(); imported_rig=imported_editor.rig(); imported_body.skin=imported_body.skin.duplicate(); imported_body.skin.set_bind_pose(0,Transform3D(Basis.IDENTITY,Vector3(7,0,0)))
	check(not imported_editor.adopt_imported().is_empty() and imported_body.binding==null,"Unknown imported custom bind matrices are retained rather than silently corrupted")
	imported_body.skin.set_bind_pose(0,KiwiRigMath.globals(imported_rig.bones)[0].affine_inverse()); imported_editor.adopt_imported()
	imported_body.binding.locked_bones.append(imported_body.binding.bone_ids[0]); var locked_before := float(imported_body.binding.vertex(0,0).get(0,0.))
	check(imported_editor.bind("Envelope").is_empty() and is_equal_approx(float(imported_body.binding.vertex(0,0).get(0,0.)),float(locked_before)),"Rebinding preserves locked influences and normalizes only the free budget")
	imported_session.select(imported_rig.id); var history_count := imported_session._undo.size()
	check(not imported_session.delete_selected().is_empty() and imported_session._undo.size()==history_count and imported_session.document.validate().is_empty(),"Deleting an armature with dependent meshes is safely refused without an undo entry")
	imported_session.select(imported_body.id); var bound_copy := imported_body.binding.signature(); check(not imported_session.edit_mesh("Subdivide").is_empty() and imported_body.binding.signature()==bound_copy,"Unsafe topology edits preserve weighted geometry and report why they are blocked")
	var bone_name := str(imported_editor.rig().bones[imported_editor.selected_bone].name); imported_editor.rename("Invalid/bone")
	check(str(imported_editor.rig().bones[imported_editor.selected_bone].name)==bone_name,"Invalid bone names are refused before reaching the engine skeleton")
	print("RIG_AUTHORING_CORE checks=%d failures=%d"%[checks,failures]); quit(failures)
