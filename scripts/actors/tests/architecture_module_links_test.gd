extends "res://scripts/actors/tests/surface_growth_test.gd"
const Modules=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_modules.gd")
const Links=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd")
const Files=preload("res://Workspaces/ModelWorkspace/model_source_link.gd")
func part(session: KiwiModelSession,group: String) -> KiwiModelComponent:
	for item in session.document.components:
		if item.parameters.get("_module_bindings",{}).has(group) and item.mesh!=null: return item
	return null
func save_model(model: KiwiModelSession,path: String) -> void:
	ResourceSaver.save(model.document,path); Files.invalidate(path); KiwiEnvironmentAssets.invalidate(path)
func run() -> void:
	var original:=KiwiModelSession.new(); var box:=original.add("Box"); var source:="user://linked_piece.res"; save_model(original,source)
	var session:=KiwiModelSession.new(); var root:=session.add("Box"); var one:=Modules.insert(session,root.id,source); var two:=Modules.insert(session,root.id,source,Transform3D(Basis.IDENTITY,Vector3(3,0,0))); var first:=part(session,one.id); var second:=part(session,two.id); var first_id:=first.id; var second_id:=second.id; var old:=second.mesh.vertices.duplicate(); first.transform.origin=Vector3(0,2,0)
	box.mesh.vertices[0].x-=.5; save_model(original,source); var error:=Links.refresh_changed(session,source)
	check(error.is_empty() and part(session,one.id).id==first_id and part(session,two.id).id==second_id and part(session,two.id).mesh.vertices!=old,"Linked copies update real source geometry while retaining stable component identities")
	check(part(session,one.id).transform.origin==Vector3(0,2,0),"Source updates preserve a manually positioned instance component")
	session.undo(); check(part(session,two.id).mesh.vertices==old,"Refreshing all instances of one source undoes as one transaction"); session.redo()
	var changed:=part(session,two.id); changed.mesh.vertices[0].z+=.2; var private_mesh:=changed.mesh.vertices.duplicate(); box.mesh.vertices[1].x+=.2; save_model(original,source); error=Links.refresh_changed(session,source)
	check(error.is_empty() and part(session,two.id).mesh.vertices==private_mesh,"An editable mesh override survives later linked source updates")
	error=Links.refresh(session,two.id,true); check(error.is_empty() and part(session,two.id).mesh.vertices==box.mesh.vertices,"Reset source overrides explicitly restores the current source mesh")
	var container:=KiwiModelSession.new(); var parent:=container.add("Box"); var nested:=Modules.insert(container,parent.id,source); var nested_path:="user://nested_pieces.res"; save_model(container,nested_path); var outer:=Modules.insert(session,root.id,nested_path)
	box.mesh.vertices[2].y+=.3; save_model(original,source); error=Links.refresh_changed(session,source); var inherited:=false
	for item in session.document.components:
		if session.document.is_descendant(item.id,outer.id) and item.mesh!=null and item.mesh.vertices==box.mesh.vertices: inherited=true
	check(error.is_empty() and inherited,"Nested linked libraries resolve current source geometry without rewriting the parent asset file")
	check(Links.depends_on(nested_path,source) and Modules.insert(session,root.id,nested_path,Transform3D.IDENTITY,source).id.is_empty(),"Dependency cycles are rejected before inserting a linked asset")
	Links.make_unique(session,one.id); var frozen:=session.document.component(first_id).mesh.vertices.duplicate(); box.mesh.vertices[3].y+=.2; save_model(original,source); Links.refresh_changed(session,source)
	check(session.document.component(first_id).mesh.vertices==frozen and not session.document.component(one.id).parameters.has("architecture_module_source"),"Making an instance unique retains its editable snapshot and stops source updates")
	var asset:=KiwiEnvironmentAssets.load_parts(nested_path); var before: int=asset.key; box.mesh.vertices[4].x+=.2; save_model(original,source); var refreshed:=KiwiEnvironmentAssets.load_parts(nested_path)
	check(refreshed.key!=before and not refreshed.parts.is_empty(),"Shared renderer caches invalidate dependent linked assets when a nested source changes")
	print("ARCHITECTURE MODULE LINKS: %d checks, %d failures"%[checks,failures]); quit(failures)
