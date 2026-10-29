extends "res://scripts/actors/tests/environment_generation_test.gd"
func run() -> void:
	var workspace:=Workspace.new(); root.add_child(workspace); var document:=KiwiEnvironmentDocument.new(); var source:=KiwiEnvironmentTerrain.new(); source.resolution=33; source.amplitude=2.; var item:=document.add_terrain(source); workspace.open_source(document); workspace.session.select(item.id); await process_frame
	var history:=workspace.session._undo.size(); var water:=KiwiTerrainHydrology.new(); water.automatic_rivers=false; water.automatic_lakes=false; water.manual_rivers=[{"id":"test-river","points":PackedVector3Array([Vector3(-6,0,-6),Vector3(0,0,0),Vector3(6,0,6)]),"width":2.,"depth":1.}]
	workspace._regenerate_terrain(item.id,{"hydrology":water}); await drain(workspace); var terrain:=workspace.session.environment().terrain(item.id)
	check(terrain.hydrology!=null and terrain.water_valid() and workspace.session._undo.size()==history+1,"Adding river generation commits exactly one undoable source edit")
	var delta:=terrain.water_delta.duplicate(); var heights:=PackedFloat32Array()
	for z in terrain.resolution:
		for x in terrain.resolution: heights.append(terrain.height(x,z))
	workspace.session.undo(); check(workspace.session.environment().terrain(item.id).hydrology==null,"Undo removes the authored river system")
	workspace.session.redo(); terrain=workspace.session.environment().terrain(item.id); check(terrain.water_valid() and terrain.water_delta==delta,"Redo restores both the river source and complete derived water")
	var index:=16+16*terrain.resolution; var before:=terrain.height(16,16); history=workspace.session._undo.size(); workspace.session.begin_terrain(item.id); workspace.session.sculpt(Vector2.ZERO,1.,.2,1.,0); workspace.session.finish_terrain(); var edited:=workspace.session.environment().terrain(item.id)
	check(edited.edits[index]!=0. and edited.height(16,16)>before+.1,"Sculpting on a carved channel changes authored height without applying its existing water offset twice")
	workspace._regenerate_terrain(item.id,{},false,true); await drain(workspace); check(workspace.session._undo.size()==history+1 and workspace.session.environment().terrain(item.id).water_valid(),"Automatic water regeneration adds no extra undo action after sculpting")
	workspace.session.undo(); terrain=workspace.session.environment().terrain(item.id)
	workspace._regenerate_terrain(item.id,{},false,true); await drain(workspace); var restored:=true
	for z in terrain.resolution:
		for x in terrain.resolution: restored=restored and absf(workspace.session.environment().terrain(item.id).height(x,z)-heights[x+z*terrain.resolution])<.00001
	check(restored,"Undoing a sculpt and regenerating drainage restores the exact original carved surface")
	var current_mesh:=workspace.session.document.component(item.id).mesh; history=workspace.session._undo.size(); workspace._edit_water(item.id,func(next: KiwiTerrainHydrology): next.water_color=Color.CORAL)
	check(workspace._generation_jobs.is_empty() and workspace.session.document.component(item.id).mesh==current_mesh and workspace.session._undo.size()==history+1,"Water appearance changes are immediate and undoable without a CPU generation job")
	workspace._regenerate_terrain(item.id,{"hydrology":null}); await drain(workspace); check(workspace.session.environment().terrain(item.id).hydrology==null and workspace.session.environment().terrain(item.id).water_delta.is_empty(),"Removing the water system clears its saved channel delta")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("TERRAIN WATER WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
