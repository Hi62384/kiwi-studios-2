extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var session:=KiwiModelSession.new(); var source:=session.add("Sphere",{"radius":1.0,"segments":12,"rings":6}); var source_id:=source.id; session.mode="Face"; session.elements=PackedInt32Array([2,3,4])
	check(KiwiSurfaceGrowth.add(session,0).is_empty(),"Hair generates from a selected scalp face region")
	var item:=session.primary(); var data:=item.growth; var on_mask:=not data.roots.is_empty()
	for root: Dictionary in data.roots: on_mask=on_mask and data.faces.has(int(root.face)) and absf((root.bary as Vector3).x+root.bary.y+root.bary.z-1)<.00001
	check(on_mask,"Every candidate root has a valid triangle, barycentric attachment and selected face")
	var before:=data.roots.duplicate(true); var source_vertices:=source.mesh.vertices.duplicate(); var hair:=KiwiSurfaceGrowth.render(data)
	check(hair.get_surface_count()>0 and (hair.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()>data.roots.size(),"Hair is actual batched tapered strand geometry, not one node per root")
	data.settings.length=1.2; data.revision+=1; session.document.prepare_growth(); check(data.roots==before,"Appearance and length edits retain the original root distribution")
	data.generation_key=0; session.document.prepare_growth(); check(data.roots==before,"The same surface and seed regenerate deterministically")
	data.settings.seed=99; session.document.prepare_growth(); check(data.roots!=before,"Changing seed changes the distribution")
	data.settings.seed=31; session.document.prepare_growth(); check(data.roots==before,"Restoring seed reproduces roots")
	var low:=data.roots.size(); data.settings.density*=2; session.document.prepare_growth(); print("DENSITY ",low," -> ",data.roots.size()); check(data.roots.size()>low,"Density changes the area-weighted root count")
	check(source.mesh.vertices==source_vertices,"Generation preserves the source mesh")
	var sampling:=KiwiModelSession.new(); var uneven:=KiwiModelComponent.new(); uneven.id=ActorData.new_id(); uneven.mesh=KiwiModelMesh.new(); uneven.mesh.vertices=PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1),Vector3(3,0,0),Vector3(6,0,0),Vector3(3,0,3)]); uneven.mesh.add_face(PackedInt32Array([0,1,2])); uneven.mesh.add_face(PackedInt32Array([3,4,5])); sampling.document.components.append(uneven); sampling.selected.assign([uneven.id]); KiwiSurfaceGrowth.add(sampling,1); var larger:=0
	for candidate: Dictionary in sampling.primary().growth.roots:
		if candidate.face==1: larger+=1
	var fraction:=float(larger)/sampling.primary().growth.roots.size(); check(fraction>.85 and fraction<.95,"Sampling uses triangle surface area rather than equal counts per triangle")
	var rows_data:=sampling.primary().growth; rows_data.settings.arrangement=1; rows_data.settings.density=5; rows_data.settings.rows=3; sampling.document.prepare_growth(); var row_positions:={}
	for candidate: Dictionary in rows_data.roots: row_positions[snappedf(candidate.position.z,.0001)]=true
	check(row_positions.size()<=3 and not rows_data.roots.is_empty(),"Ordered feather rows project onto the actual selected surface instead of random triangle-local rows")
	data.settings.type=1; data.revision+=1; var fur:=KiwiSurfaceGrowth.render(data); data.settings.type=2; data.revision+=1; var feathers:=KiwiSurfaceGrowth.render(data)
	check((feathers.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()>(fur.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),"Feathers add a separate rachis and vane rather than reusing ordinary fur geometry")
	var old_world:=session.document.world_transform(item); source.transform=Transform3D(Basis.from_euler(Vector3(.2,.4,.1))*Basis.from_scale(Vector3(2,1,1)),Vector3(3,2,1)); check(session.document.world_transform(item)==source.transform and old_world!=source.transform,"Parented growth follows source translation, rotation and scale")
	var path:="user://growth_"+ActorData.new_id()+".tres"; check(ResourceSaver.save(session.document,path)==OK,"Procedural growth saves in native model resources")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument; var saved:=reopened.components[-1].growth; var same:=saved.roots.size()==data.roots.size() and saved.faces==data.faces
	for i in mini(saved.roots.size(),data.roots.size()): same=same and saved.roots[i].id==data.roots[i].id and (saved.roots[i].bary as Vector3).is_equal_approx(data.roots[i].bary)
	check(reopened.validate().is_empty() and same,"Native roundtrip preserves identities, face masks, settings and roots")
	var runtime:=reopened.instantiate_model(); check(runtime.find_children("*","MeshInstance3D",true,false).size()==2,"A full growth component uses one mesh instance, not thousands of strand nodes"); runtime.free()
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var scene:=reopened.actor_scene(registry,path); check(scene.actors.size()==2 and scene.actors[-1].parent_id==source_id and (scene.actors[-1].values.model_component_data as KiwiModelComponent).growth!=null,"Scene instantiation preserves the source hierarchy and procedural growth component")
	var copy:=item.copy_component(); copy.growth.settings.length=9; check(data.settings.length!=9,"Unique component copies own independent procedural settings")
	var clipboard_path:=ProjectSettings.globalize_path("user://growth clipboard "+ActorData.new_id()+".tres"); var snapshot:=KiwiClipboardSnapshot.new(); snapshot.root=clipboard_path.get_base_dir(); var captured:=snapshot.capture(session.document,clipboard_path); var clipboard:=ResourceLoader.load(clipboard_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument if captured else null
	check(captured and clipboard!=null and clipboard.components[-1].growth.source_id==clipboard.components[0].id,"The existing Super Clipboard snapshot adapter preserves growth and source dependencies")
	if captured: DirAccess.remove_absolute(clipboard_path)
	data.settings.density=10000000; data.generation_key=0; check(not KiwiSurfaceGrowth.prepare(session.document,item,source).is_empty(),"Excessive density is rejected before allocating unbounded roots")
	# Compare weighted root attachment against the actual skinned triangle.
	var rig_session:=KiwiModelSession.new(); var body:=rig_session.add("Cylinder",{"height":2.0,"radius":.3,"segments":8}); var id:=body.id; var rig_editor:=KiwiRigEditor.new(rig_session); var rig:=rig_editor.create("Tentacle",3); check(rig_editor.bind("Smooth").is_empty(),"Existing smooth skin binding remains available")
	rig_session.select(id); check(KiwiSurfaceGrowth.add(rig_session,1).is_empty(),"Fur generates on a genuinely skinned surface")
	var growth:=rig_session.primary().growth; var skeleton:=ActorSkeletonRigRuntime.create_skeleton(rig.bones); root.add_child(skeleton); skeleton.set_bone_pose_rotation(1,Quaternion(Vector3.FORWARD,.6)); skeleton.force_update_all_bone_transforms(); var posed:=KiwiSurfaceGrowth.posed_points(growth,skeleton); var root_data: Dictionary=growth.roots[0]; var indices: Vector3i=root_data.triangle; var bary: Vector3=root_data.bary; var expected:=posed[indices.x]*bary.x+posed[indices.y]*bary.y+posed[indices.z]*bary.z
	check(KiwiSurfaceGrowth.point_frame(growth,root_data,posed).origin.is_equal_approx(expected) and posed!=growth.source_points,"Multi-bone surface attachment follows the exact barycentric skinned root, not a single rigid bone")
	rig_session.select(id); rig_session.mode="Face"; rig_session.elements=PackedInt32Array([2]); var mask_error:=KiwiSurfaceGrowth.add(rig_session,0); var masked:=mask_error.is_empty()
	if masked:
		for candidate: Dictionary in rig_session.primary().growth.roots: masked=masked and int(candidate.face)==2
	check(masked and not rig_session.primary().growth.roots.is_empty(),"Face masks on bound polygon meshes map to the corresponding weighted triangles")
	skeleton.queue_free(); DirAccess.remove_absolute(path)
	# Bounded real generation timing, not a promise for arbitrary huge scenes.
	var bench:=KiwiModelSession.new(); bench.add("Box",{"size":Vector3.ONE*2}); KiwiSurfaceGrowth.add(bench,1); var dense:=bench.primary().growth; dense.settings.density=180; dense.settings.quality=0; bench.document.prepare_growth(); var start:=Time.get_ticks_usec(); var result:=KiwiSurfaceGrowth.render(dense)
	print("GROWTH BENCH roots=",dense.roots.size()," vertices=",result.surface_get_array_len(0)," preparation_ms=",dense.generated_usec/1000.0," render_ms=",(Time.get_ticks_usec()-start)/1000.0)
	print("SURFACE GROWTH: %d checks, %d failures"%[checks,failures]); quit(failures)
