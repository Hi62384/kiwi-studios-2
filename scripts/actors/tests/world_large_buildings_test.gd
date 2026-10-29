extends "res://scripts/actors/tests/surface_growth_test.gd"
const Settlements=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
func run() -> void:
	var source:=preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd").new(); source.dimensions=Vector2(2048,2048); source.configure_regions(); source.max_building_plots=512; source.eager_building_limit=0; source.connect_settlements=false
	var template: Resource=Buildings.rectangular(8.,8.,1,false)
	for index in 8:
		var x:=float(index%4)*240.-360.; var z:=float(index/4)*240.-120.
		source.settlements.append({"id":"large-settlement-"+str(index),"name":"District "+str(index),"profile":"Town","center":Vector3(x,0.,z),"radius":72.,"blocks":6,"seed":100+index,"enabled":true,"locked":false,"template":template,"height_min":1,"height_max":2,"setback":2.})
	var generated:=Settlements.layout(source)
	check(not generated.get("errors",PackedStringArray()).size() and generated.plots.size()>128,"Broad-phase settlement layout supports more than 128 valid building plots")
	var document:=KiwiEnvironmentDocument.new(); var world:=KiwiModelComponent.new(); world.id=source.world_id; world.title="World"; world.parameters.world_source=source; document.components.append(world); document.component_settings[world.id]={"kind":"group"}; var output:=Settlements.build(document,source,generated); document.component_settings.merge(output.settings,true); var lazy_count:=0; var bounded:=true
	for item: KiwiModelComponent in document.components:
		if not bool(item.parameters.get("world_lazy_building",false)): continue
		lazy_count+=1; bounded=bounded and document.component_settings[item.id].kind=="building" and item.mesh!=null and item.mesh.validate().is_empty()
	check(output.errors.is_empty() and lazy_count>128 and lazy_count==generated.plots.size() and bounded,"Large settlement generation stores every building as saved low-detail massing plus a validated authored plan")
	var saved: String="user://large_buildings_"+ActorData.new_id()+".tres"; var status:=ResourceSaver.save(document,saved); var reopened:=ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(status==OK and reopened!=null and reopened.validate().is_empty() and reopened.components.size()==document.components.size(),"Large streamed settlement hierarchy saves and reopens with valid source metadata")
	DirAccess.remove_absolute(saved); print("WORLD LARGE BUILDINGS: %d checks, %d failures; plots=%d buildings=%d"%[checks,failures,generated.plots.size(),lazy_count]); quit(failures)
