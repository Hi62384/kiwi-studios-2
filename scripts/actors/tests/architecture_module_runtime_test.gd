extends "res://scripts/actors/tests/surface_growth_test.gd"
const Modules=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_modules.gd")
const Links=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd")
const Files=preload("res://Workspaces/ModelWorkspace/model_source_link.gd")
func run() -> void:
	var library:=KiwiModelSession.new(); var box:=library.add("Box"); var source:="user://runtime_library.res"; ResourceSaver.save(library.document,source); Files.invalidate(source)
	var environment:=KiwiEnvironmentSession.new(); var parent:=environment.add_group("Building room"); var first:=Modules.insert(environment,parent.id,source); environment.selected=[first.id]; environment.duplicate_selected(); var second_id:=environment.selected[0]; var root_path:="user://runtime_linked_environment.res"; ResourceSaver.save(environment.document,root_path)
	box.mesh.vertices[0].x-=.4; ResourceSaver.save(library.document,source); Files.invalidate(source); KiwiEnvironmentAssets.invalidate(source); var error:=Links.refresh_changed(environment,source); var parts:=0; var valid:=true
	for item in environment.document.components:
		if item.parameters.get("_module_bindings",{}).has(first.id) or item.parameters.get("_module_bindings",{}).has(second_id): parts+=1; valid=valid and item.mesh.vertices==box.mesh.vertices
	check(error.is_empty() and parts==2 and valid,"Duplicated linked instances remap source bindings and remain independently refreshable")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var actor:=registry.get_definition(&"environment_asset").create_actor(); actor.set_value(&"environment_path",root_path); var runtime:=registry.get_definition(&"environment_asset").create_runtime(actor); root.add_child(runtime); runtime.evaluate_clip(ActorClip.create(actor),0.)
	var linked_geometry:=0
	for item in runtime.source_document.components:
		if item.mesh!=null and item.mesh.vertices==box.mesh.vertices: linked_geometry+=1
	check(linked_geometry==2 and runtime.source_document.references_asset(source),"Saved environments resolve current linked module geometry and retain its dependency relationship")
	var original: Resource=Files.load_resource(source); box.mesh.vertices[1].z+=.2; ResourceSaver.save(library.document,source); Files.invalidate(source); runtime.refresh_saved_model(source); linked_geometry=0
	for item in runtime.source_document.components:
		if item.mesh!=null and item.mesh.vertices==box.mesh.vertices: linked_geometry+=1
	check(linked_geometry==2 and runtime.physics_geometry_ready(),"Source refresh replaces actual scene environment geometry and collision from linked modules")
	var snapshot: KiwiModelDocument=runtime.source_document.snapshot(); runtime.queue_free(); await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source)); Files.invalidate(source); var fallback:=registry.get_definition(&"environment_asset").create_runtime(actor); root.add_child(fallback); fallback.evaluate_clip(ActorClip.create(actor),0.)
	check(not fallback.linked_source_warning.is_empty() and fallback.source_document!=null and fallback.physics_geometry_ready(),"A missing linked source reports its warning while retaining the saved editable geometry and physics")
	check(snapshot.validate().is_empty() and original!=null,"Runtime link resolution preserves valid source snapshots")
	fallback.queue_free(); await process_frame; print("ARCHITECTURE MODULE RUNTIME: %d checks, %d failures"%[checks,failures]); quit(failures)
