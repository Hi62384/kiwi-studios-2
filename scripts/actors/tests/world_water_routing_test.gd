extends "res://scripts/actors/tests/surface_growth_test.gd"
const Routing=preload("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Fields=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd")
func run() -> void:
	var bounds:=Rect2(-30,-30,60,60); var surface:=func(point: Vector2): return {"height":0.,"water":absf(point.x)<2.,"water_level":.2}
	var dry:=func(_point: Vector2): return {"height":0.}
	var blocked:=Routing.route(Vector3(-20,0,0),Vector3(20,0,0),bounds,surface,[],17); check(not blocked.error.is_empty(),"Ground routing does not jump over a water barrier")
	var bridge:=Routing.route(Vector3(-20,0,0),Vector3(20,0,0),bounds,surface,[],17,Callable(),true); check(bridge.error.is_empty() and (bridge.points as PackedVector3Array).size()>2,"Bridge-enabled routing can cross the same water barrier")
	var barrier:=PackedVector2Array([Vector2(1,-30),Vector2(1.1,-30),Vector2(1.1,30),Vector2(1,30)]); blocked=Routing.route(Vector3(-20,0,0),Vector3(20,0,0),bounds,dry,[barrier],17); check(not blocked.error.is_empty(),"Grid edges cannot tunnel through a protected strip thinner than a routing cell")
	blocked=Routing.route(Vector3(1.05,0,0),Vector3(20,0,0),bounds,dry,[barrier],17); check(not blocked.error.is_empty(),"An endpoint inside protected land cannot snap across its boundary")
	var cancelled:=Routing.route(Vector3(-20,0,0),Vector3(20,0,0),bounds,dry,[],17,func(): return true); check(cancelled.get("cancelled",false),"Routing responds to background-generation cancellation")
	var session:=KiwiEnvironmentSession.new(); var ground:=session.add_terrain(); var terrain:=session.environment().terrain(ground.id); terrain.resolution=257; terrain.dimensions=Vector2(256,256); terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.manual_rivers=[{"id":"narrow","points":PackedVector3Array([Vector3(1,0,-128),Vector3(1,0,128)]),"width":2.,"depth":1.,"follow_terrain":false}]; terrain.prepare_water(); var world:=Worlds.add(session,Vector3.ZERO,true); var source: Resource=Worlds.source(world).copy(); var captured:=Fields.capture(session,world.id,source); var field: RefCounted=captured.field; var point:=Vector2(1.,3.); var native: Dictionary=terrain.sample(point); var sample: Dictionary=field.sample(point)
	check(captured.error.is_empty() and field.resolution==129 and field.water_resolution==257 and absf(float(native.height)-float(sample.height))<.00001,"Bounded world height snapshots retain native riverbed detail for narrow high-resolution channels")
	var model:=KiwiModelDocument.new(); var item:=KiwiModelComponent.new(); item.id="water-probe"; item.mesh=KiwiModelPrimitives.box(Vector3.ONE); model.components.append(item); var rules:=KiwiEnvironmentScatter.new(); rules.palette=[{"source":model}]; rules.region=Rect2(-10,-10,20,20); rules.density=.4; rules.budget=100; rules.water_depth_range=Vector2(0,.03); var placed:=rules.generate(terrain); var clear:=true
	for placement: Dictionary in placed.placements.values(): clear=clear and float(terrain.water_at((placement.transform as Transform3D).origin+Vector3.UP*.001).get("depth",0.))<=.03
	check(placed.count==100 and clear,"Dry-object placement uses actual interpolated shoreline water depth rather than a nearest-pixel guess")
	terrain.hydrology.manual_rivers[0].width=3.; captured=Fields.capture(session,world.id,source); check(not str(captured.error).is_empty() and captured.field==null,"World jobs cannot silently consume stale hydrology after a water source changes")
	print("WORLD WATER ROUTING: %d checks, %d failures"%[checks,failures]); quit(failures)

