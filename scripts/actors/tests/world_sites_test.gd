extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Fields=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd")
const Sites=preload("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Cities.create(Worlds.source(world),Vector3.ZERO); source.settlements[0].radius=24.; source=Cities.create(source,Vector3.ZERO); source.settlements[1].radius=16.; source.exclusions.append({"polygon":PackedVector2Array([Vector2(-128,-128),Vector2(0,-128),Vector2(0,128),Vector2(-128,128)]),"protected":true}); source.terrain_field=Fields.capture(session,id,source).field; var first:=Sites.find(source,1); var second:=Sites.find(source,1)
	check(str(first.error).is_empty() and first.position==second.position,"Settlement suitability search is deterministic for the same terrain and seed")
	var point: Vector3=first.position; var footprint:=Rect2(Vector2(point.x,point.z)-Vector2.ONE*16.,Vector2.ONE*32.); check(point.x>=16. and not footprint.grow(6.).intersects(Rect2(-24,-24,48,48).grow(6.)),"A selected site clears existing settlements and protected land by its actual footprint")
	var terrain:=session.environment().terrain(source.terrain_id); terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.ocean_enabled=true; terrain.hydrology.sea_level=1.; terrain.prepare_water(); source.terrain_field=Fields.capture(session,id,source).field; var wet:=Sites.find(source,1); check(not str(wet.error).is_empty(),"Flooded terrain is rejected instead of receiving an underwater settlement")
	var cancelled:=Sites.find(source,1,func(): return true); check(cancelled.get("cancelled",false),"Site analysis responds to cancellation")
	source=source.copy(); source.settlements[1].radius=200.; check(not str(Sites.find(source,1).error).is_empty(),"Oversized settlement footprints report that they cannot fit")
	print("WORLD SITES: %d checks, %d failures"%[checks,failures]); quit(failures)
