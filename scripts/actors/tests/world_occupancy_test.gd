extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Occupancy=preload("res://Workspaces/EnvironmentWorkspace/world/world_occupancy.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3(10,2,7),true); var id:=world.id; var house:=Buildings.add(session,Vector3(15,2,7)); var house_id:=house.id; var source: Resource=Forests.create(Worlds.source(world),Vector3.ZERO); source.forests[0].budget=200; var result:=await Edit.request(session,id,source); source=Worlds.source(session.document.component(id))
	check(result.errors.is_empty() and source.occupied.size()==1 and source.occupied[0].owner==house_id,"An independent building contributes one native footprint rather than one mask per wall")
	var polygon: PackedVector2Array=source.occupied[0].polygon; var center:=Vector2.ZERO
	for point in polygon: center+=point/polygon.size()
	check(center.distance_to(Vector2(5,0))<.01,"Existing-object masks use the owning world's coordinate system")
	var clear:=true; var count:=0
	for settings: Dictionary in session.environment().component_settings.values():
		var rules:=settings.get("scatter") as KiwiEnvironmentScatter
		if rules==null: continue
		var placed:=rules.generate(session.environment().terrain(rules.terrain_id)); count+=int(placed.count)
		for placement: Dictionary in placed.placements.values(): var point: Vector3=placement.transform.origin; clear=clear and not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),polygon)
	check(count>100 and clear,"All forest layers avoid the actual independent building footprint")
	house=session.document.component(house_id); house.transform.origin.x+=20.; source=source.copy(); result=await Edit.request(session,id,source); var moved: PackedVector2Array=Worlds.source(session.document.component(id)).occupied[0].polygon; check(result.errors.is_empty() and moved!=polygon,"Moving existing architecture invalidates placement masks on the next world update")
	session.undo(); check(Worlds.source(session.document.component(id)).occupied[0].polygon==polygon,"Updating occupancy masks and generated sources is undoable")
	source=Worlds.source(session.document.component(id)).copy(); source.respect_existing_objects=false; result=await Edit.request(session,id,source); check(result.errors.is_empty() and Worlds.source(session.document.component(id)).occupied.is_empty(),"The existing-structure option explicitly controls automatic reservation")
	var town: Resource=Cities.create(Worlds.source(session.document.component(id)),Vector3.ZERO); town.respect_existing_objects=true; result=await Edit.request(session,id,town); var generated: KiwiModelComponent
	for item in session.document.components:
		if item.parameters.has("architecture_source") and str(item.parameters.get("world_owner",""))==id: generated=item; break
	check(result.errors.is_empty() and generated!=null,"Procedural settlements coexist with reserved independent structures")
	if generated!=null:
		var building_id:=generated.id; generated.transform.origin.x+=.25; var updated: Resource=Worlds.source(session.document.component(id)).copy(); result=await Edit.request(session,id,updated); check(result.errors.is_empty() and session.document.component(building_id)!=null,"A manually moved generated building is reserved without excluding and deleting its own plot")
	var loaded_path:="user://world_occupancy.res"; var saved:=ResourceSaver.save(session.environment(),loaded_path); var loaded:=ResourceLoader.load(loaded_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; check(saved==OK and loaded!=null and not Worlds.source(loaded.component(id)).occupied.is_empty(),"Native saves retain editable occupancy rules and their captured footprint state")
	print("WORLD OCCUPANCY: %d checks, %d failures"%[checks,failures]); quit(failures)
