extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Layout=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd")
func run() -> void:
	var session:=KiwiModelSession.new(); var root:=Buildings.add(session); var id:=root.id; var authored: Resource=Layout.generate(Buildings.source(root),3).source; Buildings.update(session,id,authored)
	var outside:=StandardMaterial3D.new(); outside.albedo_color=Color.RED; var inside:=StandardMaterial3D.new(); inside.albedo_color=Color.BLUE; var floor:=StandardMaterial3D.new(); floor.albedo_color=Color.GREEN; var ceiling:=StandardMaterial3D.new(); ceiling.albedo_color=Color.YELLOW
	var wall_id:=id+":floor0:wall:wall0"; var mesh:=session.document.component(wall_id).mesh
	for entry in [[0,outside],[5,inside],[1,floor],[6,ceiling]]: Buildings.set_material(session,id,entry[0],entry[1])
	var wall:=session.document.component(wall_id); var positive:=false; var negative:=false
	for face in wall.mesh.faces.size():
		var normal:=wall.mesh.normal(face)
		if normal.z>.9: positive=positive or wall.surface_materials[wall.mesh.materials[face]]==inside
		if normal.z<-.9: negative=negative or wall.surface_materials[wall.mesh.materials[face]]==outside
	check(positive and negative,"Opposite sides of an exterior wall have independent native interior and exterior materials")
	check(wall.mesh==mesh,"Independent finish assignment preserves authored geometry resource identity")
	var partition:=session.document.component(id+":floor0:wall:layout:doorwall0")
	check(partition!=null and partition.surface_materials[0]==inside,"Interior partitions use the interior finish on both sides")
	check(session.document.component(id+":floor0:slab").surface_materials[0]==floor and session.document.component(id+":floor0:ceiling").surface_materials[0]==ceiling,"Floor and ceiling finishes remain independent")
	session.undo(); check(session.document.component(id+":floor0:ceiling").surface_materials[0]!=ceiling and session.document.component(id+":floor0:slab").surface_materials[0]==floor,"Ceiling assignment undoes without changing the floor finish"); session.redo()
	wall=session.document.component(wall_id)
	var native:=wall.render_mesh(); check(native.get_surface_count()==2 and native.surface_get_material(0)==outside and native.surface_get_material(1)==inside,"Actual native render surfaces carry both wall finishes")
	wall.mesh.uv[0][0]+=Vector2(.1,.1); var uv:=wall.mesh.uv.duplicate(true); var next: Resource=Source.copy(Buildings.source(session.document.component(id))); next.roof_pitch=44.; var updated:=Buildings.update(session,id,next)
	check(updated.errors.is_empty() and session.document.component(wall_id).mesh.uv==uv,"Manual UV edits survive unrelated procedural source changes")
	var path:="user://architecture_finishes.res"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and loaded.validate().is_empty() and loaded.component(wall_id).surface_materials[1].albedo_color==Color.BLUE,"Independent finish slots and manual UVs survive native save/reload")
	print("ARCHITECTURE FINISHES: %d checks, %d failures"%[checks,failures]); quit(failures)
