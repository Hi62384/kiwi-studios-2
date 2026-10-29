extends "res://scripts/actors/tests/surface_growth_test.gd"
const Section=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var path:=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd").sample(PackedVector3Array([Vector3(-25,0,0),Vector3(0,1,8),Vector3(25,2,0)]))
	for type: String in Section.TYPES:
		var road:=Section.defaults(type); var output:=Section.build(path,road); var valid: bool=output.errors.is_empty() and Section.validate(road).is_empty()
		for part in output:
			if output[part] is KiwiModelMesh: valid=valid and output[part].validate().is_empty() and (part=="markings" or KiwiDestructionGeometry.closed(output[part]))
		check(valid,"Native "+type+" cross-sections contain valid solid geometry and UVs")
	var standard:=Section.build(path,Section.defaults()); check(standard.has("sidewalks") and standard.has("curbs") and standard.has("shoulders") and standard.has("markings") and standard.surface.bounds().size.y>2.,"Residential roads include real thickness, shoulder, curb, sidewalk and lane meshes")
	var highway:=Section.build(path,Section.defaults("Highway")); check(not highway.has("sidewalks") and not highway.has("curbs") and highway.has("markings"),"Highways use their own cross-section instead of residential pavements")
	var dirt:=Section.build(path,Section.defaults("Dirt Road")); check(not dirt.has("markings") and not dirt.has("sidewalks"),"Unpaved road profiles omit painted traffic lanes and city sidewalks")
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-40,0,0),Vector3(40,0,0)); source=Worlds.add_road(source,Vector3(0,0,-40),Vector3(0,0,40)); var result:=await Edit.request(session,world.id,source); var corners:=0; var valid:=true
	for item in session.document.components:
		if item.title.begins_with("Junction "): corners+=1; valid=valid and item.mesh.validate().is_empty() and KiwiDestructionGeometry.closed(item.mesh)
	check(result.errors.is_empty() and corners>=3 and valid,"Junction curb, shoulder and sidewalk corners are native closed solids with open road mouths")
	var original:=session.document.components.size(); session.undo(); var undone:=session.document.components.size()==1; session.redo(); check(undone and session.document.components.size()==original,"Road cross-sections and junction details share the same undo transaction")
	var material:=Section.material(Worlds.source(session.document.component(world.id)),Section.defaults("Dirt Road")); check(material is StandardMaterial3D and material.albedo_color==Color("786147"),"Road profiles resolve their authored surface materials rather than sharing one gray material")
	var invalid:=Section.defaults(); invalid.shoulder=INF; check(not Section.validate(invalid).is_empty(),"Non-finite cross-section settings are rejected before generation")
	print("ROAD SECTIONS: %d checks, %d failures"%[checks,failures]); quit(failures)

