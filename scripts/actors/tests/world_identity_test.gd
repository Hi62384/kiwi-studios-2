extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var ground:=session.add_terrain(); var world:=Worlds.add(session); var world_id:=world.id; var source: Resource=Worlds.source(world).copy(); source.terrain_id=ground.id; source=Worlds.add_road(source,Vector3(-30,0,10),Vector3(30,0,10)); Worlds.update(session,world_id,source)
	check(source.copy().road_material==source.road_material,"World source copies preserve shared authored material identity")
	session.selected=[world_id,ground.id]; session.duplicate_selected(); var copied: KiwiModelComponent; var copied_ground: KiwiModelComponent
	for id in session.selected:
		var item:=session.document.component(id)
		if Worlds.source(item)!=null: copied=item
		if session.environment().terrain(id)!=null: copied_ground=item
	var copied_source:=Worlds.source(copied)
	check(copied!=null and copied_ground!=null and copied_source.world_id==copied.id and copied_source.terrain_id==copied_ground.id,"Duplicating a world and terrain remaps its source identity and terrain dependency")
	var children: Dictionary={}
	for item in session.document.components:
		if item.parent_id==copied.id: children[item.parameters.world_key]=item.id
	var next: Resource=copied_source.copy(); next.roads[0].width=8.; var result:=Worlds.update(session,copied.id,next); var same:=true
	for item in session.document.components:
		if item.parent_id==copied.id: same=same and children.get(item.parameters.world_key)==item.id
	check(result.errors.is_empty() and same and session.environment().validate().is_empty(),"Regenerating a duplicated world retains remapped live component identities")
	var road: KiwiModelComponent
	for item in session.document.components:
		if item.parent_id==world_id and item.parameters.has("world_road"): road=item; break
	session.selected=[road.id]; session.duplicate_selected(); var independent:=session.primary(); var independent_id:=independent.id
	check(not independent.parameters.get("world_generated",false),"Duplicating one generated road detaches it as an independently editable component")
	next=Worlds.source(session.document.component(world_id)).copy(); next.roads[0].width=10.; Worlds.update(session,world_id,next)
	check(session.document.component(independent_id)!=null,"Regenerating the original world preserves independently duplicated geometry")
	session.selected=[world_id]; var reusable:=session.selected_environment(); var other:=KiwiEnvironmentSession.new(); var error:=other.insert_environment(reusable,Vector3(10,0,20)); var valid:=false
	for item in other.document.components:
		var authored:=Worlds.source(item)
		if authored!=null: valid=authored.world_id==item.id and other.environment().terrain(authored.terrain_id)!=null
	check(error.is_empty() and valid and other.environment().validate().is_empty(),"Saving/inserting a selected world retains and remaps the required terrain dependency")
	next=Worlds.source(session.document.component(world_id)).copy()
	for region: Dictionary in next.regions:
		if region.id==next.region_at(Vector2(-15,10)): region.locked=true
	Worlds.update(session,world_id,next); var changed: Resource=next.copy(); changed.roads[0].width=12.; var denied:=Worlds.update(session,world_id,changed)
	check(not denied.errors.is_empty() and Worlds.source(session.document.component(world_id)).roads[0].width==10.,"Locked regions reject conflicting road changes atomically")
	var pending_source: Resource=Worlds.source(session.document.component(world_id)).copy(); pending_source.render_distance=2000.; Edit.request(session,world_id,pending_source); session.undo(); await Edit.flush(session)
	check(Worlds.source(session.document.component(world_id)).render_distance!=2000.,"Undo cancels pending world generation before touching completed history")
	print("WORLD IDENTITY: %d checks, %d failures"%[checks,failures]); quit(failures)
