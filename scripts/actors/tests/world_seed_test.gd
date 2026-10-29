extends "res://scripts/actors/tests/surface_growth_test.gd"
const Recipes=preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd")
const Seed=preload("res://Workspaces/EnvironmentWorkspace/world/world_seed.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var root_world:=Worlds.add(session); var recipe:=Recipes.configure(Worlds.source(root_world),"Rural Countryside"); var source: Resource=recipe.source; var before:=Cities.layout(source); var next: Resource=Seed.apply(source,987); var after:=Cities.layout(next)
	check(source.seed==1 and next.seed==987 and next.settlements[0].center==source.settlements[0].center and before.roads[0].points!=after.roads[0].points,"Reseeding linked village defaults changes organic streets while retaining authored settlement placement")
	check(next.forests[0].seed==987 and next.forests[0].variants[0].settings.seed!=source.forests[0].variants[0].settings.seed and next.prop_rules[0].seed==987,"Layout seed changes linked vegetation geometry, placement and prop random streams")
	var custom: Resource=source.copy(); custom.settlements[0].seed=42; custom.forests[0].seed=55; custom.prop_rules[0].seed=66; var retained: Resource=Seed.apply(custom,123)
	check(retained.settlements[0].seed==42 and retained.forests[0].seed==55 and retained.prop_rules[0].seed==66,"Explicit local seed overrides survive global layout reseeding")
	var replay: Resource=Seed.apply(source,987); check(Cities.layout(replay).roads[0].points==after.roads[0].points,"Reapplying the same seed reproduces the same street geometry")
	print("WORLD SEED: %d checks, %d failures"%[checks,failures]); quit(failures)
