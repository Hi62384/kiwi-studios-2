extends SceneTree
var failures := 0
var checks := 0
var editor: ActorTimelineEditor
var gizmo: ActorUIGizmo
var viewport: SubViewport
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func settle() -> void:
	for unused in 5: await process_frame
func actor_named(title: String) -> ActorData:
	for actor in editor.model.actors:
		if actor.display_name==title: return actor
	return null
func click(point: Vector2, pressed: bool=true) -> void:
	var event := InputEventMouseButton.new(); event.position=gizmo.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position=gizmo.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(event,true)
func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true; root.push_input(event,true)
	event=event.duplicate(); event.pressed=false; root.push_input(event,true)
func rig_fixture() -> PackedScene:
	var source := Node3D.new(); source.name="Character"
	var group := Node3D.new(); group.name="ModelGroup"; source.add_child(group); group.owner=source
	var rig := Skeleton3D.new(); rig.name="Rig"; group.add_child(rig); rig.owner=source
	rig.add_bone("Root"); rig.set_bone_rest(0,Transform3D.IDENTITY)
	rig.add_bone("Arm"); rig.set_bone_parent(1,0); rig.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3.UP)); rig.set_bone_pose_position(1,Vector3.UP)
	var mesh := MeshInstance3D.new(); mesh.name="Body"; rig.add_child(mesh); mesh.owner=source
	var arrays := BoxMesh.new().surface_get_arrays(0); var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array(); var weights := PackedFloat32Array()
	for i in points.size(): indices.append_array(PackedInt32Array([1,0,0,0])); weights.append_array(PackedFloat32Array([1.,0.,0.,0.]))
	arrays[Mesh.ARRAY_BONES]=indices; arrays[Mesh.ARRAY_WEIGHTS]=weights
	var geometry := ArrayMesh.new(); geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var paint := StandardMaterial3D.new(); paint.albedo_color=Color("f49d5b"); geometry.surface_set_material(0,paint)
	mesh.mesh=geometry; mesh.skin=rig.create_skin_from_rest_transforms(); mesh.skeleton=NodePath("..")
	var packed := PackedScene.new(); packed.pack(source); source.free(); return packed
func run() -> void:
	root.size=Vector2i(1400,850); root.gui_embed_subwindows=true
	var session := KiwiModelSession.new()
	var a := session.add("Box",{},Vector3(1,0,0)); a.title="ParentMesh"; a.transform.basis=Basis.from_euler(Vector3(.1,.5,.2))*Basis.from_scale(Vector3(1.5,.8,1.))
	var b := session.add("Box",{},Vector3(-1,1,0)); b.title="ChildMesh"; var b_world := b.transform
	session.reparent_components([b.id],a.id)
	check(session.document.world_transform(b).is_equal_approx(b_world),"Parenting under a rotated, nonuniformly scaled mesh preserves world pose")
	var c := session.add("Cylinder",{},Vector3(0,2,0)); c.title="Grandchild"; var c_world := c.transform
	session.reparent_components([c.id],b.id)
	check(c.parent_id==b.id and session.document.world_transform(c).is_equal_approx(c_world),"Meshes can form multiple parenting levels")
	var history := session._undo.size(); session.reparent_components([a.id],c.id)
	check(session._undo.size()==history and a.parent_id.is_empty(),"Cyclic parenting is rejected without an undo entry")
	session.undo(); check(session.document.component(c.id).parent_id.is_empty(),"Undo restores the previous hierarchy")
	session.redo(); check(session.document.component(c.id).parent_id==b.id,"Redo restores nested parenting")
	var workspace := KiwiModelWorkspace.new(); workspace.session=session; root.add_child(workspace); await settle()
	var row := workspace.hierarchy.get_root().get_first_child()
	var data := {"kiwi_model_tree":workspace.hierarchy.get_instance_id(),"ids":[] as Array[String]}; data.ids.assign([b.id,c.id])
	var empty := Vector2(30,workspace.hierarchy.size.y-20)
	check(workspace.hierarchy._can_drop_data(empty,data),"Model hierarchy accepts drag-to-empty unparenting")
	workspace.hierarchy._drop_data(empty,data); await settle()
	check(session.document.component(b.id).parent_id.is_empty() and session.document.component(c.id).parent_id==b.id,"Dragging a selected subtree preserves its internal parent links")
	check(session.document.world_transform(session.document.component(c.id)).is_equal_approx(c_world),"Drag/drop parenting preserves descendant world transforms")
	session.undo(); await settle()
	row=workspace.hierarchy.get_root().get_first_child().get_first_child()
	var onto := workspace.hierarchy.get_item_area_rect(row).get_center()
	data.ids.assign([a.id])
	check(not workspace.hierarchy._can_drop_data(onto,data),"Hierarchy drag/drop rejects a parent dropped onto its child")
	var parent_row := workspace.hierarchy.get_root().get_first_child(); parent_row.select(0); row.select(0); workspace._tree_selected(parent_row,0,true)
	check(session.primary().id==a.id,"The last-clicked tree item is the parenting target, not whichever row is lowest")
	var path := ProjectSettings.globalize_path("user://Nested Model.tres")
	check(ResourceSaver.save(session.document,path)==OK,"Nested mesh document saves")
	workspace.hide()
	editor=ActorTimelineEditor.new(); root.add_child(editor); editor.hide()
	editor.inspector=ActorInspector.new(); editor.inspector.position=Vector2(1040,20); editor.inspector.size=Vector2(340,780); root.add_child(editor.inspector); editor.inspector.setup(editor.model,editor.registry,editor.inspector_ui_state)
	viewport=SubViewport.new(); viewport.size=Vector2i(1000,700); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; viewport.own_world_3d=true; root.add_child(viewport)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,.3,5); camera.make_current()
	var environment := WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("172330"); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; viewport.add_child(environment)
	editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var display := TextureRect.new(); display.position=Vector2(20,20); display.size=Vector2(1000,700); display.texture=viewport.get_texture(); display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; root.add_child(display)
	gizmo=ActorUIGizmo.new(); gizmo.editor=editor; gizmo.display=display; display.add_child(gizmo)
	var root_clip := editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); await settle()
	check(editor.model.actors.size()==4,"Adding a model creates a parent actor and separate component actors")
	var aa := actor_named("ParentMesh"); var bb := actor_named("ChildMesh"); var cc := actor_named("Grandchild")
	check(bb.parent_id==aa.id and cc.parent_id==bb.id and aa.parent_id==root_clip.actor_id,"Scene actors preserve the model's exact parent hierarchy")
	check(editor.model.world_transform_for(cc.id).is_equal_approx(c_world),"Scene transform data preserves affine transforms without changing the model's shape")
	var runtime := editor._runtime_for_clip(editor.model.clip_for_actor_id(cc.id).id)
	check(runtime.remote_transform().is_equal_approx(c_world),"Rendered nested meshes match their saved world transforms")
	check(editor.runtime_holder.find_children("*","MeshInstance3D",true,false).size()==3,"Each model component renders once, without duplicated child meshes")
	var reduced := session.document.snapshot(); reduced.components.remove_at(2); ResourceSaver.save(reduced,path)
	call_group("actor_shader_runtimes","refresh_saved_model",path); editor._evaluate_runtimes(); await settle()
	check(editor.runtime_holder.find_children("*","MeshInstance3D",true,false).size()==2,"A removed shared component does not incorrectly render the entire model in its place")
	ResourceSaver.save(session.document,path); call_group("actor_shader_runtimes","refresh_saved_model",path); editor._evaluate_runtimes(); await settle()
	check(editor.runtime_holder.find_children("*","MeshInstance3D",true,false).size()==3,"Restoring a shared component refreshes its own mesh")
	check(editor.model.selected_actor().link_timeline_children and not editor.model.selected_actor().show_timeline_children,"Instanced model root links and initially folds its child clips")
	var saved_ids := editor.model.actors.map(func(actor: ActorData): return actor.id)
	editor.model.history.undo(); await settle(); check(editor.model.actors.is_empty(),"One undo removes the complete imported model hierarchy")
	editor.model.history.redo(); await settle(); check(editor.model.actors.map(func(actor: ActorData): return actor.id)==saved_ids,"One redo restores all model nodes with stable IDs")
	editor.model.unparent(cc.id); await settle(); check(editor._runtime_for_clip(editor.model.clip_for_actor_id(cc.id).id).remote_transform().is_equal_approx(c_world),"Scene unparenting preserves imported shear and world pose")
	editor.model.history.undo(); await settle()
	var scene_path := "user://Nested Scene.tres"; ResourceSaver.save(editor.capture_scene_data(),scene_path)
	editor.restore_scene_data(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE)); await settle()
	check(actor_named("Grandchild").parent_id==actor_named("ChildMesh").id,"Scene roundtrip preserves individual editable mesh parents")
	var fixture := rig_fixture(); var imported := KiwiModelImport.load_document(fixture)
	check(imported.components.size()==4 and imported.components[0].title=="Character" and imported.components[1].title=="ModelGroup","Model import retains non-mesh group nodes instead of flattening them")
	var rig_data := imported.components[2]; var body_data := imported.components[3]
	check(rig_data.is_skeleton and rig_data.bones.size()==2 and rig_data.bones[1].parent==0,"Import recognizes Skeleton3D and preserves its bone names, parents and rest poses")
	check(body_data.skeleton_id==rig_data.id and body_data.skin!=null and body_data.skin_mesh!=null,"Import preserves skin bindings and weighted source geometry")
	var gltf_source := fixture.instantiate(); var gltf := GLTFDocument.new(); var state := GLTFState.new(); var glb_path := ProjectSettings.globalize_path("user://Rigged Model.glb")
	var wrote := gltf.append_from_scene(gltf_source,state)==OK and gltf.write_to_filesystem(state,glb_path)==OK; gltf_source.free()
	check(wrote,"Generated a real rigged GLB test fixture")
	if wrote:
		var glb := KiwiModelImport.load_document(glb_path); var rigs := glb.components.filter(func(item: KiwiModelComponent): return item.is_skeleton)
		check(rigs.size()==1 and rigs[0].bones.size()==2,"Runtime GLB import retains the skeleton rig")
	var rig_path := ProjectSettings.globalize_path("user://Rigged Native.tres"); ResourceSaver.save(imported,rig_path)
	var reloaded := ResourceLoader.load(rig_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(reloaded.components[3].skin_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS].size()>0,"Native model roundtrip retains original skin weights")
	editor.restore_scene_data(ActorSceneData.new()); await settle()
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":rig_path}); await settle()
	var rig_actor := actor_named("Rig"); var body_actor := actor_named("Body")
	check(rig_actor.type_id==&"skeleton_rig" and body_actor.parent_id==rig_actor.id,"Adding a rigged model creates a Skeleton Rig actor in the correct hierarchy")
	check(str(body_actor.values[&"model_skeleton_actor"])==rig_actor.id,"Skin references are remapped to the newly instantiated rig, not the source ID")
	var rig_runtime := editor._runtime_for_clip(editor.model.clip_for_actor_id(rig_actor.id).id) as ActorSkeletonRigRuntime
	var body_runtime := editor._runtime_for_clip(editor.model.clip_for_actor_id(body_actor.id).id)
	var visual := body_runtime.content.get_child(0) as MeshInstance3D
	check(visual.skin!=null and visual.get_node(visual.skeleton)==rig_runtime.skeleton,"Scene mesh resolves its actual runtime Skeleton3D for GPU skinning")
	editor.model.select(editor.model.clip_for_actor_id(rig_actor.id).id); await settle()
	check(editor.inspector.find_child("RigBonePicker",true,false)!=null and editor.inspector.find_child("KeyBonePose",true,false)!=null,"Rig inspector exposes bone selection, numeric transforms and pose keyframes")
	click(gizmo.spatial.rig.toolbar_rect(0).get_center()); click(gizmo.spatial.rig.toolbar_rect(0).get_center(),false); await settle()
	check(gizmo.spatial.rig.active(),"Selecting the viewport Bones tool enables bone guides")
	var joint := gizmo.spatial.project(rig_runtime.skeleton.global_transform*rig_runtime.skeleton.get_bone_global_pose(1).origin)
	click(joint); click(joint,false); await settle(); check(gizmo.spatial.rig.selected()==1,"Clicking a visible bone selects it in the viewport")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
	var before_image := viewport.get_texture().get_image()
	var history_before := editor.model.history.get_version(); gizmo.spatial.mode="move"
	var handles := gizmo.spatial.geometry(); var handle: Vector2=handles.center.lerp(handles.ends[0],.65)
	click(handle); motion(handle+Vector2(50,0)); await settle(); click(handle+Vector2(50,0),false); await settle()
	check(rig_runtime.skeleton.get_bone_pose_position(1).x>.1,"Viewport move handles modify the selected bone, not the entire rig")
	check(rig_actor.get_value(&"position")==Vector3.ZERO and editor.model.history.get_version()==history_before+1,"Bone drag commits one undoable gesture without moving the actor")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(before_image.get_data()!=viewport.get_texture().get_image().get_data(),"Moving the bound bone visibly deforms the rendered mesh")
	editor.model.history.undo(); await settle(); check(rig_runtime.skeleton.get_bone_pose_position(1).is_equal_approx(Vector3.UP),"Bone gesture undo restores the original pose")
	editor.model.history.redo(); await settle(); check(rig_runtime.skeleton.get_bone_pose_position(1).x>.1,"Bone gesture redo restores deformation")
	key(KEY_E); handles=gizmo.spatial.geometry(); var ring: PackedVector2Array=handles.rings[2]
	check(gizmo.spatial.begin(2,ring[0]),"Bone rotation uses the viewport's visible rotation ring")
	gizmo.spatial.rig.update(ring[12],false); gizmo.spatial.rig.finish(); await settle()
	check(absf(rig_runtime.skeleton.get_bone_pose_rotation(1).get_euler().z)>.3,"Rotation rings rotate the selected bone")
	editor.model.history.undo(); await settle(); check(rig_runtime.skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY),"Bone rotation is undoable")
	key(KEY_R); handles=gizmo.spatial.geometry(); click(handles.center); motion(handles.center+Vector2(70,0)); click(handles.center+Vector2(70,0),false); await settle()
	check(rig_runtime.skeleton.get_bone_pose_scale(1).is_equal_approx(Vector3.ONE*1.5),"Bone scale handles scale the selected bone")
	editor.model.history.undo(); await settle()
	key(KEY_W); handles=gizmo.spatial.geometry(); handle=handles.center.lerp(handles.ends[0],.65)
	var prior := rig_runtime.skeleton.get_bone_pose_position(1); history_before=editor.model.history.get_version()
	click(handle); motion(handle+Vector2(25,0)); key(KEY_ESCAPE); click(handle+Vector2(25,0),false); await settle()
	check(rig_runtime.skeleton.get_bone_pose_position(1).is_equal_approx(prior) and rig_actor.animation_previews.is_empty() and editor.model.history.get_version()==history_before,"Escape cancels a bone transform without an undo entry or stale preview")
	key(KEY_I); await settle(); check(rig_actor.animation_tracks.size()==3,"I inserts position, rotation and scale keys for the selected bone")
	var base_pose: Vector3=ActorSkeletonPose.value(rig_actor,1,"position")
	editor.canvas.playhead=2.; editor._evaluate_runtimes(); await settle()
	ActorSkeletonPose.commit(editor.model,ActorSkeletonPose.capture(editor.model,rig_actor),1,{"position":base_pose+Vector3.RIGHT,"rotation":Vector3(0,0,90)})
	await settle()
	check(rig_actor.animation_track(ActorSkeletonPose.path(1,"position")).keys.size()==2,"Editing an animated bone inserts a key at the current playhead")
	editor.model.history.undo(); await settle(); check(rig_actor.animation_track(ActorSkeletonPose.path(1,"position")).keys.size()==1,"Undo removes the complete multi-channel pose edit's keys")
	editor.model.history.redo(); await settle(); check(rig_actor.animation_track(ActorSkeletonPose.path(1,"rotation")).keys.size()==2,"Redo restores all channels of the animated pose edit")
	editor.canvas.playhead=1.; editor._evaluate_runtimes(); await settle()
	check(is_equal_approx(rig_runtime.skeleton.get_bone_pose_position(1).x,base_pose.x+.5),"Scrubbing interpolates bone positions through the normal actor animation system")
	check(absf(rig_runtime.skeleton.get_bone_pose_rotation(1).get_euler().z-PI/4.)<.001,"Scrubbing interpolates bone rotations")
	var bone_scene := "user://Bone Animation Scene.tres"; ResourceSaver.save(editor.capture_scene_data(),bone_scene)
	editor.restore_scene_data(ResourceLoader.load(bone_scene,"",ResourceLoader.CACHE_MODE_IGNORE)); await settle()
	rig_actor=actor_named("Rig"); rig_runtime=editor._runtime_for_clip(editor.model.clip_for_actor_id(rig_actor.id).id) as ActorSkeletonRigRuntime
	check(rig_actor.animation_tracks.size()==3 and is_equal_approx(rig_runtime.skeleton.get_bone_pose_position(1).x,base_pose.x+.5),"Saving and reopening a scene preserves rig poses, bone animation and playhead")
	var turning := ActorAnimationTrack.new(); turning.path=ActorSkeletonPose.path(1,"rotation")
	for i in 2:
		var frame := ActorKeyframe.new(); frame.time=i; frame.value=Vector3(0,170. if i==0 else -170.,0); turning.keys.append(frame)
	check(absf(Quaternion.from_euler(turning.sample(.5)*PI/180.).dot(Quaternion.from_euler(Vector3(0,PI,0))))>.999,"Bone rotation animation follows the shortest arc across the Euler wrap")
	var output := ProjectSettings.globalize_path("res://.godot/verification/model_workspace/rig_pose_tools.png"); DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; check(root.get_texture().get_image().save_png(output)==OK,"Rig viewport screenshot")
	var original_x := rig_runtime.skeleton.get_bone_pose_position(1).x
	var original_count := editor.model.actors.size()
	var ids: Array[String]=[]
	for clip in editor.model.clips: ids.append(clip.id)
	editor.model.set_selection(ids); editor.duplicate_selected(); await settle()
	var copied_rig := actor_named("Rig Copy"); var copied_body := actor_named("Body Copy")
	var copied_runtime := editor._runtime_for_clip(editor.model.clip_for_actor_id(copied_rig.id).id) as ActorSkeletonRigRuntime
	var copied_mesh := editor._runtime_for_clip(editor.model.clip_for_actor_id(copied_body.id).id).content.get_child(0) as MeshInstance3D
	check(copied_body.values[&"model_skeleton_actor"]==copied_rig.id and copied_mesh.get_node(copied_mesh.skeleton)==copied_runtime.skeleton,"Duplicating a hierarchy remaps skin bindings to the copied rig")
	ActorSkeletonPose.commit(editor.model,ActorSkeletonPose.capture(editor.model,copied_rig),1,{"position":Vector3(3,1,0)}); await settle()
	check(is_equal_approx(rig_runtime.skeleton.get_bone_pose_position(1).x,original_x) and copied_runtime.skeleton.get_bone_pose_position(1).x>2.9,"Copied rig animation is independent of the original")
	editor.model.history.undo(); editor.model.history.undo(); await settle(); check(editor.model.actors.size()==original_count,"Copied rig poses and the copied model hierarchy undo cleanly")
	display.queue_free(); editor.inspector.queue_free(); editor.queue_free(); viewport.queue_free(); workspace.queue_free(); await settle()
	print("MODEL_HIERARCHY_RIG checks=%d failures=%d"%[checks,failures]); quit(failures)
