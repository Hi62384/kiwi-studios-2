extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(128,128); terrain.amplitude=15.; terrain.prepare(); var source:=KiwiTerrainBiomes.new(); source.definitions=[KiwiTerrainBiomes.starter(0),KiwiTerrainBiomes.starter(1),KiwiTerrainBiomes.starter(2),KiwiTerrainBiomes.starter(7)]; terrain.biomes=source
	var started:=Time.get_ticks_usec(); check(terrain.prepare_biomes() and terrain.biomes_valid(),"Climate generation produces a valid derived biome field")
	var original:=terrain.biome_data.duplicate(true); var normalized:=true; var mixed:=false
	for index in 33*33:
		var total:=0.; var positive:=0
		for values: PackedFloat32Array in terrain.biome_data.weights.values(): total+=values[index]; positive+=1 if values[index]>.01 else 0; normalized=normalized and values[index]>=0. and values[index]<=1.
		normalized=normalized and absf(total-1.)<.00001; mixed=mixed or positive>1
	check(normalized and mixed,"Suitability weights normalize to one and blend several biomes continuously")
	terrain.biome_key=0; terrain.prepare_biomes(); check(terrain.biome_data==original,"Identical terrain, seed and climate regenerate exactly the same biome fields")
	var sample:=terrain.biome_at(Vector2(.27,.83)); var sum:=0.
	for value: float in sample.values(): sum+=value
	check(absf(sum-1.)<.00001 and terrain.biome_at(Vector2(1000,1000)).is_empty(),"Spatial queries interpolate continuous normalized weights and reject points outside terrain")
	source.sea_temperature=-35.; terrain.prepare_biomes(); var cold:=terrain.biome_at(Vector2.ZERO); check(float(cold.get("snow",0.))>.95,"Cold climates favor the actual snow suitability rule")
	for definition in source.definitions: definition.temperature=Vector2(1000,2000)
	terrain.prepare_biomes(); check(terrain.biome_at(Vector2.ZERO).grassland==1.,"An explicit fallback biome covers locations where all suitability rules fail")
	var mask:=PackedFloat32Array(); mask.resize(33*33); mask.fill(1.); source.paint_masks["forest"]=mask; terrain.prepare_biomes(); check(terrain.biome_at(Vector2.ZERO).forest==1.,"Authored biome masks participate in normalized suitability rather than replacing IDs")
	var path:="user://terrain-biomes.tres"; ResourceSaver.save(terrain,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentTerrain
	check(loaded.biomes_valid() and loaded.biome_at(Vector2.ZERO)==terrain.biome_at(Vector2.ZERO),"Save and reopen preserve valid climate fields, rules, stable IDs and painted masks")
	loaded.resolution=65; loaded.prepare(); loaded.prepare_biomes(); check(loaded.biome_at(Vector2.ZERO).forest==1.,"Changing terrain resolution retains authored biome mask coverage")
	var scatter:=KiwiEnvironmentScatter.new(); scatter.palette=[{"source":"fixture"}]; scatter.region=Rect2(-8,-8,16,16); scatter.density=.1; scatter.biome_ids=PackedStringArray(["forest"]); var allowed:=scatter.generate(terrain); scatter.biome_ids=PackedStringArray(["desert"]); var rejected:=scatter.generate(terrain)
	check(allowed.count>0 and rejected.count==0,"The actual scatter generator obeys shared continuous biome suitability")
	check(source.generate(terrain,1,func(): return true).get("cancelled",false),"Biome generation cancels without publishing partial arrays")
	var sculpted:=KiwiEnvironmentTerrain.new(); sculpted.resolution=33; sculpted.dimensions=Vector2(32,32); sculpted.biomes=KiwiTerrainBiomes.new(); sculpted.biomes.definitions=[KiwiTerrainBiomes.starter(0)]; sculpted.biomes.definitions[0].landforms=[{"type":"Dunes","height":4.,"width":4.,"length":16.}]; sculpted.prepare(); sculpted.prepare_biomes(); var peak:=sculpted.height(16,16); var stable:=sculpted.signature(); sculpted.prepare(); sculpted.prepare_biomes()
	check(peak>.5 and sculpted.height(16,16)==peak and sculpted.signature()==stable and sculpted.derived_fields.has("initial_biomes"),"Frozen preliminary biome weights modify actual terrain geometry without a regeneration feedback cycle")
	sculpted.biomes.definitions[0].landforms=[]; sculpted.prepare(); check(absf(sculpted.height(16,16))<.00001,"Removing a biome landform restores the original procedural base")
	for index in KiwiTerrainBiomes.NAMES.size(): var definition:=KiwiTerrainBiomes.starter(index); check(definition.name==KiwiTerrainBiomes.NAMES[index] and not str(definition.id).is_empty(),"Starter biome has editable identity: "+str(definition.name))
	DirAccess.remove_absolute(path); print("TERRAIN BIOMES elapsed_ms=",float(Time.get_ticks_usec()-started)/1000.); print("TERRAIN BIOMES: %d checks, %d failures"%[checks,failures]); quit(failures)
