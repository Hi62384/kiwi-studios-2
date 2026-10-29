extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Fields=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd")
const Terrain=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var ground:=session.add_terrain(); var terrain:=session.environment().terrain(ground.id); terrain.resolution=257; terrain.dimensions=Vector2(64,64); terrain.amplitude=2.; terrain.prepare(); var world:=Worlds.add(session); var source: Resource=Worlds.source(world).copy(); source.terrain_id=ground.id; var result:=Fields.capture(session,world.id,source); var field: RefCounted=result.field; var info:=Terrain.context(session,world.id,source)
	check(result.error.is_empty() and field.resolution==129 and field.heights.size()==129*129,"World terrain snapshots keep a bounded shared CPU height field")
	check(absf(field.sample(Vector2.ZERO).height-(Terrain.sample(info,Vector2.ZERO).height-.03))<.0001,"Snapshot heights agree with the actual referenced terrain coordinate system")
	check(Fields.capture(session,world.id,source).field==field and field.valid(session),"Unchanged world jobs reuse the same immutable terrain snapshot")
	var old_height: float=field.sample(Vector2.ZERO).height; terrain.edits[128+128*257]+=2.; terrain.revision+=1
	check(not field.valid(session) and absf(field.sample(Vector2.ZERO).height-old_height)<.0001,"A sculpt edit invalidates dependency state without mutating an active worker snapshot")
	var fresh: RefCounted=Fields.capture(session,world.id,source).field; check(fresh!=field and absf(fresh.sample(Vector2.ZERO).height-old_height-2.)<.0001,"Recapturing terrain observes the changed sculpt sample")
	world.transform.origin=Vector3(5.,3.,7.); var moved: RefCounted=Fields.capture(session,world.id,source).field; var direct:=Terrain.sample(Terrain.context(session,world.id,source),Vector2.ZERO)
	check(not fresh.valid(session) and absf(moved.sample(Vector2.ZERO).height-(direct.height-.03))<.0001,"World-relative snapshot transforms remain correct after moving the world group")
	check(moved.sample(Vector2(10000,10000)).is_empty(),"Sampling outside the terrain returns an explicit missing surface")
	print("WORLD TERRAIN FIELD: %d checks, %d failures"%[checks,failures]); quit(failures)
