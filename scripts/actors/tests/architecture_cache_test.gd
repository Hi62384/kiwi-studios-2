extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Cache=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_mesh_cache.gd")
func run() -> void:
	Cache.clear(); var source: Resource=Source.rectangular(8,10,3); var first:=Builder.generate(source); var initial:=Cache.statistics(); var repeat:=Builder.generate(source); var warm:=Cache.statistics()
	check(first.errors.is_empty() and repeat.errors.is_empty() and warm.hits>initial.hits and warm.misses==initial.misses,"Repeated generation reuses bounded derived geometry")
	var id: String=source.source_id+":floor0:wall:wall0"; var original: KiwiModelMesh=repeat.document.component(id).mesh; first.document.component(id).mesh.vertices[0]+=Vector3.ONE
	check(original.vertices!=first.document.component(id).mesh.vertices,"Editable generated meshes do not alias each other or cached topology")
	var next: Resource=Source.copy(source); next.floors[0].walls[0].openings[0].width=1.2; var changed:=Builder.generate(next); var after:=Cache.statistics()
	check(changed.errors.is_empty() and after.misses==warm.misses+1 and after.hits>warm.hits,"Changing one opening rebuilds that wall while reusing unrelated walls and slabs")
	check(after.bytes>0 and after.bytes<=Cache.LIMIT and after.entries<=256,"Derived geometry cache remains within its memory and entry budgets")
	var timer:=Time.get_ticks_usec(); Builder.generate(next); print("ARCHITECTURE WARM GENERATION MS: ",float(Time.get_ticks_usec()-timer)/1000.)
	print("ARCHITECTURE CACHE: %d checks, %d failures"%[checks,failures]); quit(failures)
