extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Massing=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_massing.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd")
func run() -> void:
	var environment:=KiwiEnvironmentDocument.new(); var source:=preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd").new(); source.world_id="building-world"; source.configure_regions(); var world:=KiwiModelComponent.new(); world.id=source.world_id; world.title="World"; world.parameters.world_source=source; environment.components.append(world); environment.component_settings[world.id]={"kind":"group"}
	var plot:=KiwiModelComponent.new(); plot.id="building-plot"; plot.title="Residential plot"; plot.parent_id=world.id; plot.parameters.world_plot="plot-123"; environment.components.append(plot); environment.component_settings[plot.id]={"kind":"group"}
	var authored: Resource=Buildings.rectangular(8.,10.,2,false); authored.source_id="editable-building"; var item:=KiwiModelComponent.new(); item.id=authored.source_id; item.title="Editable generated building"; item.parent_id=plot.id; item.transform.origin=Vector3(2,1,3); item.mesh=Massing.mesh(authored); item.parameters={"architecture_source":authored,"architecture_type":"building","architecture_owner":item.id,"architecture_key":"","world_lazy_building":true,"world_owner":world.id,"world_generated":true,"world_key":":building:plot-123","world_pose":item.transform,"world_plot":"plot-123","_architecture_mesh":Builder.mesh_key(item.mesh),"_architecture_mesh_format":2,"_architecture_materials":[]}; environment.components.append(item); environment.component_settings[item.id]={"kind":"building","collision":true}
	var session:=KiwiEnvironmentSession.new(); session.document=environment; var original_pose:=environment.world_transform(item); var desired: Resource=authored.duplicate(true); desired.floors[0].height=3.4
	var result: Dictionary=await Edit.request(session,item.id,desired,"Make building editable")
	item=session.document.component("editable-building")
	check(result.errors.is_empty() and item!=null and not item.parameters.has("world_lazy_building") and session.environment().component_kind(item.id)=="asset","Editing a distant generated building atomically expands it into editable native architecture")
	var detached_source: Resource=Worlds.source(session.document.component(world.id))
	check(item.parent_id==plot.id and session.document.world_transform(item).is_equal_approx(original_pose) and detached_source.plot_overrides.get("plot-123",{}).get("reserved",false),"Expansion preserves the plot hierarchy and pose while reserving its generated lot")
	session.undo(); item=session.document.component("editable-building")
	check(item!=null and item.parent_id==plot.id and item.parameters.get("world_lazy_building",false) and session.environment().component_kind(item.id)=="building" and not Worlds.source(session.document.component(world.id)).plot_overrides.has("plot-123"),"One undo restores the original streamed building and releases its plot reservation")
	session.redo(); item=session.document.component("editable-building")
	check(item!=null and not item.parameters.has("world_lazy_building") and session.environment().component_kind(item.id)=="asset" and Worlds.source(session.document.component(world.id)).plot_overrides.get("plot-123",{}).get("reserved",false),"Redo restores the complete editable building and reservation together")
	print("WORLD BUILDING EDIT: %d checks, %d failures"%[checks,failures]); quit(failures)
