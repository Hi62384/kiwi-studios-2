extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Foundation=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_foundation.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var terrain:=session.add_terrain(); var root:=Buildings.add(session); Foundation.set_modifier(session,root.id,terrain.id); session.selected=[root.id,terrain.id]; session.duplicate_selected(); var copied_root: KiwiModelComponent; var copied_terrain: KiwiModelComponent
	for id in session.selected:
		var component:=session.document.component(id)
		if Buildings.source(component)!=null: copied_root=component
		if session.environment().terrain(id)!=null: copied_terrain=component
	check(copied_root!=null and copied_terrain!=null and Buildings.source(copied_root).source_id==copied_root.id,"Duplicated environment remaps native building source identity")
	check(session.environment().terrain(copied_terrain.id).generation.layers[0].foundation_owner==copied_root.id and session.environment().terrain(terrain.id).generation.layers[0].foundation_owner==root.id,"Copied foundation dependencies point to copied buildings without mutating originals")
	var coherent:=true
	for item in session.document.components:
		if not session.document.is_descendant(item.id,copied_root.id): continue
		coherent=coherent and item.parameters.get("architecture_owner","")==copied_root.id
		for connection: Dictionary in item.structural.get(&"structure_connections",{}).values(): coherent=coherent and session.document.is_descendant(str(connection.target),copied_root.id)
	check(coherent,"Copied structural connections and generated owner metadata stay within their new assembly")
	var next: Resource=Source.copy(Buildings.source(copied_root)); next.roof_pitch=47.; var changed:=Buildings.update(session,copied_root.id,next)
	check(changed.errors.is_empty() and Buildings.source(session.document.component(root.id)).roof_pitch==30.,"Copied buildings remain independently procedural")
	var source:=session.environment(); var store:=KiwiClipboardStore.new("user://architecture_clipboard_"+ActorData.new_id()); var clipboard_id:=store.save(source,"Editable architecture"); var restored:=ResourceLoader.load(store.entry_path(clipboard_id),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(not clipboard_id.is_empty() and restored!=null and restored.validate().is_empty(),"Super Clipboard packages complete editable architecture and terrain source resources")
	var destination:=KiwiEnvironmentSession.new(); var error:=destination.insert_environment(restored,Vector3(20,0,0)); var foundations_ok:=true; var count:=0
	for item in destination.document.components:
		var ground:=destination.environment().terrain(item.id)
		if ground==null or ground.generation==null: continue
		for layer in ground.generation.layers:
			if layer.get("type","")!="Foundation": continue
			count+=1; foundations_ok=foundations_ok and Buildings.source(destination.document.component(str(layer.foundation_owner)))!=null and destination.document.component(str(layer.foundation_owner))!=session.document.component(str(layer.foundation_owner))
	check(error.is_empty() and count==2 and foundations_ok,"Portable insertion remaps both terrain foundation links under its new movable hierarchy")
	var model:=KiwiModelSession.new(); var building:=Buildings.add(model); var wall:=model.document.component(building.id+":floor0:wall:wall0"); model.selected=[wall.id]; model.duplicate_selected(); var extra_id:=model.selected[0]; var extra:=model.document.component(extra_id); var settings: Resource=Source.copy(Buildings.source(building)); settings.roof_pitch=42.; Buildings.update(model,building.id,settings)
	check(not extra.parameters.has("architecture_key") and model.document.component(extra_id)!=null and model.document.component(wall.id)!=null,"Copying one generated wall detaches its procedural key and preserves both walls on regeneration")
	store.close(); print("ARCHITECTURE PORTABILITY: %d checks, %d failures"%[checks,failures]); quit(failures)
