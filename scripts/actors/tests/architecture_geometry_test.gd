extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
func hits(mesh: KiwiModelMesh,a: Vector3,b: Vector3) -> bool:
	for face in mesh.faces.size():
		var indices:=mesh.triangles(face)
		for i in range(0,indices.size(),3):
			if Geometry3D.segment_intersects_triangle(a,b,mesh.vertices[mesh.faces[face][indices[i]]],mesh.vertices[mesh.faces[face][indices[i+1]]],mesh.vertices[mesh.faces[face][indices[i+2]]])!=null: return true
	return false
func run() -> void:
	var source: Resource=Source.rectangular(6.,8.,2); var built:=Builder.generate(source); var document:=built.document as KiwiModelDocument
	check(document!=null and built.errors.is_empty() and document.validate().is_empty(),"Building produces valid native editable component hierarchy")
	if document==null: quit(1); return
	var north:=document.component(source.source_id+":floor0:wall:wall0")
	check(not hits(north.mesh,Vector3(3,1,-1),Vector3(3,1,1)) and hits(north.mesh,Vector3(1,1,-1),Vector3(1,1,1)),"Door opening is absent solid geometry while adjacent wall remains solid")
	var east:=document.component(source.source_id+":floor0:wall:wall1")
	check(not hits(east.mesh,Vector3(4,1.5,-1),Vector3(4,1.5,1)) and hits(east.mesh,Vector3(4,.5,-1),Vector3(4,.5,1)),"Window opening includes real sill and header clearances")
	var wall: Dictionary=source.floors[0].walls[0]; wall.openings[0].angle=80.; var opened:=Builder.generate(source); var door:=opened.document.component(source.source_id+":floor0:opening:door0:leaf") as KiwiModelComponent
	check(absf(door.transform.basis.get_euler().y-deg_to_rad(80.))<.001 and door.parent_id==north.id,"Door swings around native hinge origin and retains wall parent")
	check(door.structural.structure_connections.hinge.type==1 and door.structural.structure_connections.hinge.target==north.id,"Door metadata reuses existing structural hinge system")
	var arch:=Builder.wall_mesh(6,3,.2,[{"id":"arch","type":"arch","t":.5,"width":2.,"height":2.2}])
	check(arch.validate().is_empty() and not hits(arch,Vector3(3,2.1,-1),Vector3(3,2.1,1)) and hits(arch,Vector3(2.01,2.1,-1),Vector3(2.01,2.1,1)),"Arched opening is shaped by actual curved-boundary solid geometry")
	source.floors[1].cuts=[Rect2(-.6,-1.,1.2,2.)]; var cut:=Builder.generate(source); var slab:=cut.document.component(source.source_id+":floor1:slab") as KiwiModelComponent
	check(not hits(slab.mesh,Vector3(0,-1,0),Vector3(0,1,0)) and hits(slab.mesh,Vector3(2,-1,0),Vector3(2,1,0)),"Stairwell cut removes actual floor slab triangles")
	for roof in 4:
		source.roof_type=roof; var output:=Builder.generate(source); check(output.errors.is_empty() and output.document.component(source.source_id+":roof").mesh.validate().is_empty(),"Roof type %d has valid native solid geometry"%roof)
	source.footprint=PackedVector2Array([Vector2(-3,-4),Vector2(3,-4),Vector2(3,4),Vector2(0,2),Vector2(-3,4)]); source.roof_type=1; var warning:=Builder.generate(source)
	check(not warning.warnings.is_empty() and warning.document.component(source.source_id+":roof")==null,"Unsupported roof topology warns instead of creating invalid geometry")
	source=Source.rectangular(); source.floors[0].walls[0].openings[0].width=100.; check(Builder.generate(source).document==null,"Invalid opening extents reject regeneration without partial building")
	var path:="user://architecture_model.res"; ResourceSaver.save(document,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(reopened!=null and reopened.validate().is_empty() and reopened.components[0].parameters.architecture_source!=null,"Building source and complete model hierarchy survive saving")
	for kind in 4:
		var stair_source: Resource=Source.rectangular(10,12,2); stair_source.stairs.assign([{"id":"main","from":"floor0","to":"floor1","type":kind,"position":Vector2(-2,-3),"width":1.,"length":4.,"steps":16}]); var stairs:=Builder.generate(stair_source)
		check(stairs.document!=null and stairs.errors.is_empty() and stairs.document.component(stair_source.source_id+":stairs:main:treads")!=null,"Stair type %d produces real editable treads and valid geometry"%kind)
		var upper:=stairs.document.component(stair_source.source_id+":floor1:slab") as KiwiModelComponent
		check(not hits(upper.mesh,Vector3(-2,-1,-2),Vector3(-2,1,-2)),"Stair type %d automatically cuts its actual upper-floor shaft"%kind)
		var landing:=stairs.document.component(stair_source.source_id+":stairs:main:landings") as KiwiModelComponent
		check(landing!=null and landing.mesh.validate().is_empty() and absf(landing.mesh.bounds().end.y-3.)<.001,"Stair type %d provides an editable landing at the upper floor elevation"%kind)
		if kind==0: check(hits(landing.mesh,Vector3(0,2.5,4.02),Vector3(0,3.5,4.02)),"Straight stair landing bridges the shaft edge to the upper slab")
		if kind==3: check(hits(landing.mesh,Vector3(.75,2.5,1.3),Vector3(.75,3.5,1.3)),"Spiral landing spans the square shaft's gap rather than ending over empty space")
	var spanning: Resource=Source.rectangular(12,16,3); spanning.stairs.assign([{"id":"long","from":"floor0","to":"floor2","type":0,"position":Vector2(-2,-4),"width":1.,"length":8.,"steps":34}]); var linked:=Builder.generate(spanning)
	check(not hits(linked.document.component(spanning.source_id+":floor1:slab").mesh,Vector3(-2,-1,0),Vector3(-2,1,0)),"Stairs spanning levels cut the intermediate slab instead of running through solid geometry")
	check(not hits(linked.document.component(spanning.source_id+":floor1:ceiling").mesh,Vector3(-2,-1,0),Vector3(-2,1,0)),"Intermediate ceilings preserve headroom through multi-level stair shafts")
	spanning.stairs[0].type=3; spanning.stairs[0].turns=4.; var unsafe:=Builder.generate(spanning)
	check("headroom" in " ".join(unsafe.warnings).to_lower(),"Unsafe spiral pitch reports a specific headroom warning")
	print("ARCHITECTURE GEOMETRY: %d checks, %d failures"%[checks,failures]); quit(failures)
