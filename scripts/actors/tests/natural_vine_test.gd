extends "res://scripts/actors/tests/surface_growth_test.gd"
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
func run() -> void:
	var surface:=KiwiModelPrimitives.box(Vector3(4,4,.2)); var original:=surface.vertices.duplicate(); var path:=PackedVector3Array([Vector3(-.5,-1,.7),Vector3(.2,0,.5),Vector3(.5,1.5,.6)]); var source:={"growth_path":path,"growth_surface":surface,"branches":6,"radius":.2}
	var generated:=Generator.generate("Plant / Vine",source); var attached: bool=generated.mesh!=null and generated.mesh.validate().is_empty()
	for point: Vector3 in generated.branches[0].points: attached=attached and absf(point.z-.115)<.001
	check(attached,"Vine path projects onto actual transformed surface triangles with clearance")
	check(surface.vertices==original and path==source.growth_path,"Attachment preserves the source mesh and authored path")
	check(not generated.attachments.is_empty(),"Surface-attached vine has real stem and leaf attachment geometry")
	var session:=KiwiModelSession.new(); var item:=session.add("Plant / Vine",source); var save_path:="user://natural_vine.res"; ResourceSaver.save(session.document,save_path); var loaded:=ResourceLoader.load(save_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and loaded.validate().is_empty() and Generator.generate(loaded.components[0].generator,loaded.components[0].parameters).mesh.vertices==item.mesh.vertices,"Attachment source and path regenerate identically after saving")
	var invalid:=Generator.generate("Plant / Vine",{"growth_path":PackedVector3Array([Vector3.ONE,Vector3.ONE])}); check(invalid.mesh==null and not str(invalid.error).is_empty(),"Collapsed paths fail safely without installing degenerate geometry")
	print("NATURAL VINE: %d checks, %d failures"%[checks,failures]); quit(failures)
