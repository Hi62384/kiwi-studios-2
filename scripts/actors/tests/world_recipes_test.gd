extends "res://scripts/actors/tests/surface_growth_test.gd"
const Recipes=preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var source: Resource=Worlds.source(world); var valid:=true; var distinct: Dictionary={}
	for name in Recipes.NAMES:
		var recipe:=Recipes.configure(source,name); valid=valid and recipe.error.is_empty() and recipe.source.validate().is_empty() and recipe.terrain_settings.generation.validate().is_empty(); var settlement: Dictionary=recipe.source.settlements[0]; distinct[name]=[recipe.terrain_settings.generation.profile,recipe.source.settlements.size(),settlement.profile,settlement.blocks,settlement.template.style,recipe.source.forests.size()]
	check(valid and distinct.size()==7,"All seven world presets produce valid native terrain, settlement and vegetation source settings")
	var modern:=Recipes.configure(source,"Modern City"); var medieval:=Recipes.configure(source,"Medieval Village"); var island:=Recipes.configure(source,"Tropical Island"); var rural:=Recipes.configure(source,"Rural Countryside"); var mountain:=Recipes.configure(source,"Mountain Region")
	check(modern.source.settlements[0].districts.size()==2 and modern.source.settlements[0].blocks==4 and medieval.source.settlements[0].template.style=="Medieval" and medieval.source.settlements[0].road_type=="Dirt Road","Urban and medieval presets change topology, actual district/building rules and road surfaces")
	check(island.terrain_settings.hydrology.ocean_enabled and island.source.forests[0].profile=="Tropical Jungle" and rural.source.settlements.size()==2 and mountain.terrain_settings.generation.profile==2 and not mountain.terrain_settings.generation.layers.is_empty(),"Natural presets include real ocean, vegetation, multiple villages and mountain clearing modifiers")
	var layout:=Cities.layout(medieval.source); var road: Dictionary=layout.roads[0]; check(road.type=="Dirt Road" or road.get("section","")=="Dirt Road","Preset settlement streets inherit their authored road cross-section")
	var first:=Recipes.configure(source,"Rural Countryside"); var second:=Recipes.configure(source,"Rural Countryside"); var other: Resource=source.copy(); other.seed+=7; var changed:=Recipes.configure(other,"Rural Countryside")
	check(first.source.settlements[0].center==second.source.settlements[0].center and first.source.settlements[0].seed==second.source.settlements[0].seed and first.source.settlements[0].center!=changed.source.settlements[0].center,"Recipe layout seeds reproduce structure and changing the seed changes settlement geography")
	check(Recipes.empty(source) and source.settlements.is_empty() and not Recipes.configure(modern.source,"Modern City").error.is_empty(),"Preset configuration preserves its input and rejects replacing an authored world")
	var canceled:=preload("res://Workspaces/EnvironmentWorkspace/world/world_recipe_job.gd").new(); canceled.cancel(); canceled.start(modern.source); while not canceled.complete(): await process_frame
	check(canceled.collect().get("cancelled",false),"Recipe layout generation honors cancellation without partial native output")
	print("WORLD RECIPES: %d checks, %d failures"%[checks,failures]); quit(failures)
