extends "res://scripts/actors/tests/environment_generation_test.gd"
func run() -> void:
	var workspace:=Workspace.new(); root.add_child(workspace); var document:=KiwiEnvironmentDocument.new(); var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; var item:=document.add_terrain(terrain); workspace.open_source(document); workspace.session.select(item.id); await process_frame
	var history:=workspace.session._undo.size(); workspace._edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions=[KiwiTerrainBiomes.starter(0),KiwiTerrainBiomes.starter(1)]); await drain(workspace); terrain=workspace.session.environment().terrain(item.id)
	check(terrain.biomes_valid() and terrain.biomes.definitions.size()==2 and workspace.session._undo.size()==history+1,"Biome rules and complete derived fields commit together as one undoable edit")
	workspace._expanded_landforms["forest"]=true; workspace._refresh_properties(); check(workspace.properties.get_child_count()>25,"Selected terrain builds expanded climate and biome rule controls")
	var weights: Dictionary=terrain.biome_data.weights.duplicate(true); workspace.session.undo(); check(workspace.session.environment().terrain(item.id).biomes==null,"Undo removes biome sources and their generated field")
	workspace.session.redo(); terrain=workspace.session.environment().terrain(item.id); check(terrain.biomes_valid() and terrain.biome_data.weights==weights,"Redo restores exact shared suitability fields")
	var path:="user://biome-workspace.tres"; check(await workspace.save_to(path)==OK,"Normal workspace save accepts completed biome data")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; check(loaded.terrain(item.id).biomes_valid(),"Saved environment reopens with valid editable biome sources and fields")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("TERRAIN BIOMES WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
