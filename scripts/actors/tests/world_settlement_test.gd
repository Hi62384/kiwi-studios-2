extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var owner:=Worlds.add(session); var id:=owner.id; var source: Resource=Cities.create(Worlds.source(owner),Vector3.ZERO,"City"); var layout:=Cities.layout(source); var again:=Cities.layout(source)
	check(layout.blocks.size()==9 and layout.plots.size()==9 and layout.roads.size()==8,"City streets define nine usable blocks with actual road-frontage plots")
	check(hash(layout)==hash(again),"Settlement blocks, road IDs, plots and architectural seeds are deterministic")
	var valid:=true
	for plot: Dictionary in layout.plots:
		for road: Dictionary in layout.roads: valid=valid and not Cities._overlaps_road(plot.polygon,road)
		for other: Dictionary in layout.plots:
			if plot.id!=other.id: valid=valid and Geometry2D.intersect_polygons(plot.polygon,other.polygon).is_empty()
	check(valid,"Generated plots stay separate and leave roads and setbacks clear")
	var village: Resource=Cities.create(Worlds.source(session.document.component(id)),Vector3.ZERO,"Village"); var rural:=Cities.layout(village)
	check(rural.roads.size()==5 and rural.blocks.is_empty() and rural.plots.size()>=4,"Village generation uses irregular connected lanes and roadside clusters rather than a smaller city grid")
	var started:=Time.get_ticks_usec(); var result:=await Edit.request(session,id,source,"Generate city"); var generation_ms:=float(Time.get_ticks_usec()-started)/1000.; var count:=0; var doors:=0; var window_holes:=0; var roofs: Dictionary={}; var building_id:=""; var building_material: Material; var accessible:=true; var staircases:=0
	for item in session.document.components:
		if item.parameters.has("architecture_source"):
			count+=1; building_id=item.id; roofs[int(item.parameters.architecture_source.roof_type)]=true; building_material=item.parameters.architecture_source.materials[0]; var building_source: Resource=item.parameters.architecture_source; accessible=accessible and building_source.stairs.size()==building_source.floors.size()-1; staircases+=building_source.stairs.size()
		if item.parameters.get("architecture_type","")=="door": doors+=1
		if item.parameters.get("architecture_type","")=="window": window_holes+=1
	check(result.errors.is_empty() and count==9 and doors==9 and window_holes>9 and roofs.size()>1,"City generation reuses real editable multi-component buildings, doorways, glass and different roof geometry")
	check(accessible and staircases>0,"Procedural multi-story buildings connect all floors with actual stairs and floor openings")
	check(session.environment().validate().is_empty() and session.document.component(building_id).parameters.architecture_source.source_id==building_id,"Generated architecture and its source ownership remain valid inside the world hierarchy")
	var graph: Dictionary=session.document.component(id).parameters.world_graph; var referenced:=true
	for plot: Dictionary in layout.plots: referenced=referenced and graph.edges.any(func(edge: Dictionary): return edge.source_road_id==plot.frontage)
	check(referenced,"Every building plot retains a valid frontage reference to the actual generated road graph")
	var building:=session.document.component(building_id); building.transform.origin+=Vector3(1.,0.,0.); var pose:=building.transform; var next: Resource=Worlds.source(session.document.component(id)).copy(); next.render_distance=2000.; result=await Edit.request(session,id,next)
	check(result.errors.is_empty() and session.document.component(building_id).transform==pose and session.document.component(building_id).parameters.architecture_source.materials[0]==building_material,"Unrelated world edits preserve customized building transforms and shared material identity")
	var path:="user://world_city.res"; ResourceSaver.save(session.environment(),path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).settlements.size()==1 and loaded.component(building_id).parameters.architecture_source!=null,"Native save/reopen retains world layout, settlement template and all editable building sources")
	session.undo(); check(Worlds.source(session.document.component(id)).render_distance==1000.,"Settlement regeneration participates in ordinary source undo history")
	var building_source: Resource=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").copy(session.document.component(building_id).parameters.architecture_source); building_source.roof_pitch+=1.; preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd").update(session,building_id,building_source)
	next=Worlds.source(session.document.component(id)).copy(); next.render_distance=2000.; result=await Edit.request(session,id,next)
	check(not result.errors.is_empty() and is_equal_approx(session.document.component(building_id).parameters.architecture_source.roof_pitch,building_source.roof_pitch),"Conflicting settlement regeneration preserves a locally customized building source and reports the conflict")
	var detached:=Worlds.keep_independent(session,building_id); result=await Edit.request(session,id,next); var total:=0
	for item in session.document.components: if item.parameters.has("architecture_source"): total+=1
	check(detached.is_empty() and result.errors.is_empty() and total==9 and not session.document.component(building_id).parameters.get("world_generated",false),"Keeping a building independent reserves its generated plot and prevents duplicate regeneration")
	print("WORLD CITY initial_generation_ms=",generation_ms," full_round_trip_ms=",float(Time.get_ticks_usec()-started)/1000.," components=",session.document.components.size()," village_plots=",rural.plots.size()); print("WORLD SETTLEMENT: %d checks, %d failures"%[checks,failures]); quit(failures)
