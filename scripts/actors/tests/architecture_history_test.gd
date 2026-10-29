extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var building:=Buildings.add(session,Vector3(5,0,3),2); var id:=building.id; var wall_id:=id+":floor0:wall:wall0"; var wall:=session.document.component(wall_id); var vertices:=wall.mesh.vertices.duplicate(); var material:=wall.surface_materials[0]; var source:=Buildings.source(building)
	check(session.document.validate().is_empty() and session.document.world_transform(building).origin==Vector3(5,0,3),"Building integrates into the shared environment hierarchy at its placed pose")
	var neighbor_id:=id+":floor0:wall:wall1"; var neighbor_mesh:=session.document.component(neighbor_id).mesh
	var changed: Resource=Source.copy(source); changed.floors[0].walls[0].openings[0].width=1.6; var update:=Buildings.update(session,id,changed,"Resize opening")
	check(session.document.component(neighbor_id).mesh==neighbor_mesh,"Opening changes preserve unrelated authored mesh resource identities")
	check(update.errors.is_empty() and session.document.component(wall_id).mesh.vertices!=vertices and session.document.component(wall_id).surface_materials[0]==material,"Opening edits preserve component identity and native material resources")
	check(source.floors[0].walls[0].openings[0].width==1.,"Source snapshots stay immutable during editing")
	session.undo(); check(session.document.component(wall_id).mesh.vertices==vertices and Buildings.source(session.document.component(id)).floors[0].walls[0].openings[0].width==1.,"One undo restores plan source and derived geometry exactly")
	session.redo(); check(Buildings.source(session.document.component(id)).floors[0].walls[0].openings[0].width==1.6,"Redo restores the edited source")
	wall=session.document.component(wall_id); wall.mesh.vertices[0]+=Vector3(0,.05,0); var authored:=wall.mesh.vertices.duplicate(); wall.transform.origin.y+=.2; var pose:=wall.transform
	changed=Source.copy(Buildings.source(session.document.component(id))); changed.roof_pitch=40.; Buildings.update(session,id,changed); changed.roof_pitch=45.; Buildings.update(session,id,changed)
	check(session.document.component(wall_id).mesh.vertices==authored and session.document.component(wall_id).transform==pose,"Repeated procedural edits preserve manual geometry and transform overrides")
	var path:="user://architecture_environment.res"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded!=null and loaded.validate().is_empty() and Buildings.source(loaded.component(id)).roof_pitch==45.,"Complete source, hierarchy, overrides and environment settings survive saving")
	var invalid: Resource=Source.copy(Buildings.source(session.document.component(id))); invalid.floors[0].walls[0].openings[0].width=100.; var before:=session.document.components.size(); var error:=Buildings.update(session,id,invalid)
	check(not error.errors.is_empty() and session.document.components.size()==before and session.document.component(wall_id).mesh.vertices==authored,"Failed regeneration leaves the complete previous building intact")
	var object:=session.document.component(wall_id).mesh; var replacement:=StandardMaterial3D.new(); replacement.albedo_color=Color(.3,.2,.1); Buildings.set_material(session,id,0,replacement)
	check(session.document.component(wall_id).mesh==object and session.document.component(wall_id).surface_materials[0]==replacement,"Material changes preserve actual authored mesh objects")
	session.undo(); check(session.document.component(wall_id).surface_materials[0]==material,"Global material changes undo through the shared history")
	print("ARCHITECTURE HISTORY: %d checks, %d failures"%[checks,failures]); quit(failures)
