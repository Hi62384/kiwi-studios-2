extends "res://scripts/actors/tests/surface_growth_test.gd"
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
func run() -> void:
	var a:=Generator.generate("Tree / Oak",{"levels":1,"seed":115}); var vertices: PackedVector3Array=a.mesh.vertices.duplicate(); a.mesh.vertices[0]+=Vector3.ONE; a.branches[0].points[0]+=Vector3.ONE
	var begin:=Time.get_ticks_usec(); var b:=Generator.generate("Tree / Oak",{"levels":1,"seed":115}); var elapsed:=(Time.get_ticks_usec()-begin)/1000.
	check(b.mesh.vertices==vertices and b.branches[0].points[0]==Vector3.ZERO,"Cached artifacts own independent mesh and graph data")
	check(Generator._cache_bytes<=Generator.CACHE_BYTES and Generator._cache.size()<=24,"CPU artifact cache obeys its byte and entry limits")
	var surface:=KiwiModelPrimitives.box(Vector3.ONE); var source:={"growth_path":PackedVector3Array([Vector3(0,-.2,1),Vector3(0,.2,1)]),"growth_surface":surface}; var first:=Generator.generate("Plant / Vine",source); var duplicate:=surface.copy_mesh(); source.growth_surface=duplicate; var second:=Generator.generate("Plant / Vine",source)
	check(first.signature==second.signature and first.mesh.vertices==second.mesh.vertices,"Source keys use semantic attachment geometry instead of resource identity")
	var job:=preload("res://Workspaces/ModelWorkspace/natural_job.gd").new(); job.start("Tree / Oak",{"levels":1,"seed":115})
	while not job.complete(): await process_frame
	var result: Dictionary=job.collect(); check(result.mesh.vertices==vertices,"Worker can reuse CPU artifacts without native rendering access")
	print("NATURAL CACHE cached_ms=",elapsed," estimated_bytes=",Generator._cache_bytes)
	print("NATURAL CACHE: %d checks, %d failures"%[checks,failures]); quit(failures)
