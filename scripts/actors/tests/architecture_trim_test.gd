extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
func run() -> void:
	var source: Resource=Source.rectangular(6,8,1); source.baseboard_height=.12; source.crown_height=.09
	var result:=Builder.generate(source); var wall_id: String=source.source_id+":floor0:wall:wall0"; var base: KiwiModelComponent=result.document.component(wall_id+":baseboard"); var crown: KiwiModelComponent=result.document.component(wall_id+":crown")
	check(result.errors.is_empty() and base!=null and crown!=null,"Optional interior finishes generate actual native profile geometry")
	var clear:=true; var interior:=true
	for face: PackedInt32Array in base.mesh.faces:
		var low:=INF; var high:=-INF
		for vertex in face: var point: Vector3=base.mesh.vertices[vertex]; low=minf(low,point.x); high=maxf(high,point.x); interior=interior and point.z>0.
		if low<3.5-.0001 and high>2.5+.0001: clear=false
	check(clear and interior,"Baseboards stop at doorway edges and remain on the interior face")
	check(crown.mesh.bounds().size.x>5.9 and base.surface_materials[0]==source.materials[3],"Crown spans above the doorway and uses the independent trim finish")
	var session:=KiwiModelSession.new(); var root:=Buildings.add(session); var id:=root.id; var next: Resource=Source.copy(Buildings.source(root)); next.baseboard_height=.12; next.crown_height=.09; Buildings.update(session,id,next)
	check(session.document.component(id+":floor0:wall:wall0:baseboard")!=null,"Parametric source changes install trim with stable component identities")
	session.undo(); check(session.document.component(id+":floor0:wall:wall0:baseboard")==null,"Undo removes the generated finish with its source change"); session.redo()
	var path:="user://architecture_trim.res"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and is_equal_approx(Buildings.source(loaded.component(id)).baseboard_height,.12) and loaded.validate().is_empty(),"Native save/reload retains editable trim dimensions and generated geometry")
	source.baseboard_height=-1.; check(not source.validate().is_empty(),"Invalid interior trim dimensions are rejected before generation")
	print("ARCHITECTURE TRIM: %d checks, %d failures"%[checks,failures]); quit(failures)
