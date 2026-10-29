extends "res://scripts/actors/tests/world_blocks_test.gd"
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var id:=world.id; var polygon:=PackedVector2Array([Vector2(-40,-40),Vector2(40,-40),Vector2(40,40),Vector2(-40,40)]); var source: Resource=closed_roads(Worlds.source(world),polygon); source=Worlds.add_road(source,Vector3(0,.03,-40),Vector3(0,.03,40)); source=Cities.create(source,Vector3.ZERO); var settlement: Dictionary=source.settlements[0]; settlement.layout_mode="Road network"; settlement.radius=64.
	var left:=Districts.create("Industrial",PackedVector2Array([Vector2(-64,-64),Vector2(0,-64),Vector2(0,64),Vector2(-64,64)])); var right:=Districts.create("Downtown",PackedVector2Array([Vector2(0,-64),Vector2(64,-64),Vector2(64,64),Vector2(0,64)])); right.height_min=3; right.height_max=3; left.lot_size=64.; right.lot_size=64.; settlement.districts=[left,right]
	check(source.validate().is_empty() and Districts.CATEGORIES.size()==10,"Ten district presets create valid editable native source settings")
	var layout:=Cities.layout(source); var block_left: Dictionary={}; var block_right: Dictionary={}
	for block: Dictionary in layout.blocks:
		if block.district=="Industrial": block_left=block
		if block.district=="Downtown": block_right=block
	check(not block_left.is_empty() and not block_right.is_empty() and layout.plots.size()>=2,"District polygons classify real road blocks and retain frontage parcels")
	var result:=await Edit.request(session,id,source); var owner:=session.document.component(id); var valid:=true; var industrial:=0; var downtown:=0
	for item in session.document.components:
		if not item.parameters.has("architecture_source"): continue
		for plot: Dictionary in owner.parameters.world_plots:
			if plot.id!=item.parameters.world_plot: continue
			var building: Resource=item.parameters.architecture_source
			if plot.district=="Industrial": industrial+=1; valid=valid and building.floors.size()==1 and building.style=="Industrial" and building.roof_type==2
			if plot.district=="Downtown": downtown+=1; valid=valid and building.floors.size()==3 and building.roof_type==0
	check(result.errors.is_empty() and valid and industrial>0 and downtown>0,"Native district buildings have different real floor counts, roof geometry and material styles")
	var next: Resource=Worlds.source(owner).copy(); next.settlements[0].block_overrides={str(block_left.id):{"district_id":right.id},str(block_right.id):{"density":0.}}; result=await Edit.request(session,id,next); owner=session.document.component(id); valid=true
	for plot: Dictionary in owner.parameters.world_plots: valid=valid and plot.block==block_left.id and plot.district=="Downtown"
	check(result.errors.is_empty() and valid and owner.parameters.world_plots.size()>0,"Per-block district assignments override boundaries and open blocks contain no generated buildings")
	session.undo(); owner=session.document.component(id); check(Worlds.source(owner).settlements[0].get("block_overrides",{}).is_empty() and owner.parameters.world_plots.size()==layout.plots.size(),"Undo restores district rules and the original native parcels")
	session.redo(); var saved:=ResourceSaver.save(session.environment(),"user://world_districts_test.res"); var loaded:=ResourceLoader.load("user://world_districts_test.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).settlements[0].districts[0].template.style=="Industrial" and Worlds.source(loaded.component(id)).settlements[0].block_overrides.size()==2,"District geometry, native templates and block overrides survive resource save/reopen and redo")
	var sparse: Dictionary={"id":"sparse","density":.4,"seed":7}; var count:=0; var stable:=true
	for i in 100:
		var plot: Dictionary={"id":str(i)}; var accepted:=Districts.accept(plot,sparse); count+=int(accepted); stable=stable and accepted==Districts.accept(plot,sparse)
	check(stable and count>15 and count<70,"District density is stable by parcel identity rather than generation order")
	var invalid: Resource=source.copy(); invalid.settlements[0].districts[0].height_min=8; invalid.settlements[0].districts[0].height_max=1; check(not invalid.validate().is_empty(),"Invalid district height ranges are rejected before generation")
	var park:=Districts.create("Park/Green Space",polygon); var rules:=Districts.rules({"id":"park","polygon":polygon},{"districts":[park]}); check(not Districts.accept({"id":"park-lot"},rules),"Park districts reserve open land instead of producing ordinary buildings")
	print("WORLD DISTRICTS: %d checks, %d failures"%[checks,failures]); quit(failures)
