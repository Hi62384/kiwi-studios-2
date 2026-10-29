extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var inspector:=ActorInspector.new(); root.add_child(inspector); inspector.setup(editor.model,editor.registry); editor.inspector=inspector
	var path:="user://powder_shared_"+ActorData.new_id()+".tres"; ResourceSaver.save(KiwiPowderMaterial.preset(0),path)
	var definition:=editor.registry.get_definition(&"powder"); var clip:=editor.model.create_actor(definition,0,{&"powder_simulate":false,&"powder_dimensions":Vector3(.4,.4,.4)}); clip.start_time=0
	var actor:=editor.model.selected_actor(); KiwiPowderMaterial.apply(editor.model,[actor],ActorObjectReference.from_asset(path,&"powder_material")); await seek(0)
	var reference: ActorObjectReference=actor.values.powder_material; var inspector_object:=editor.inspector._resolve_object(reference)
	check(inspector_object==ActorAnimation.resolve_reference(reference),"Saved material inspector and renderer share the same authoritative resource")
	editor.model.edit_object_property(actor,inspector_object,editor.registry.get_object_definition(&"powder_material"),&"powder_roughness",.12); await seek(0)
	var runtime:=editor._runtime_for_clip(clip.id) as KiwiPowderRuntime
	check(is_equal_approx(runtime.grain_material.get_shader_parameter("roughness"),.12),"Inspector edits to a saved shared material update live grains immediately")
	editor.inspector.inspect_file_resource(path)
	var name_field:=editor.inspector.find_child("material_name_text",true,false) as LineEdit
	check(name_field!=null,"The project resource inspector can rename custom material files")
	name_field.text="Wet beach sand"; name_field.text_submitted.emit(name_field.text)
	var saved:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(saved.values.material_name=="Wet beach sand","File-inspector text editing persists to the original material resource")
	editor.model.undo(); check(ActorAnimation.resolve_reference(reference).values.material_name=="Sand","File-inspector material edits undo through the shared scene history")
	editor.model.redo(); check(ActorAnimation.resolve_reference(reference).values.material_name=="Wet beach sand","File-inspector material edits redo")
	var image:=editor.registry.get_object_definition(&"noise_image").create_object(); inspector_object.set_value(&"powder_texture",ActorObjectReference.from_object(image)); ResourceSaver.save(inspector_object,path)
	editor.inspector.inspect_file_resource(path); check(editor.inspector.find_child("seed_value",true,false)!=null,"Saved powder materials expose embedded noise-image fields instead of an empty reference")
	await seek(0); var snapshot:=preload("res://scripts/actors/physics/physics_mesh_snapshot.gd").capture(editor,actor,false)
	check(snapshot.error.is_empty() and snapshot.mesh.get_surface_count()>0,"Actual instanced grain geometry converts into an ordinary mesh resource")
	var mesh_path:="user://powder_mesh_"+ActorData.new_id()+".tres"; check(ResourceSaver.save(snapshot.mesh,mesh_path)==OK and ResourceLoader.load(mesh_path) is ArrayMesh,"Converted grain geometry saves as a reusable mesh")
	var old:=runtime.instance_count(); check(old==editor.physics.display_states[actor.id].points.size(),"Mesh conversion leaves the simulated grain inventory unchanged")
	DirAccess.remove_absolute(path); DirAccess.remove_absolute(mesh_path); editor.physics.dispose(); editor.model.history.clear_history(); inspector.queue_free(); editor.queue_free(); view.queue_free(); await process_frame
	print("POWDER MATERIAL FILES: %d checks, %d failures"%[checks,failures]); quit(failures)
