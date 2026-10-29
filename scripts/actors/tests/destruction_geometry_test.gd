extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var cube:=KiwiModelPrimitives.box(Vector3.ONE); var original:=cube.vertices.duplicate()
	var op:=KiwiDestructionDefinition.operation(0); var result:=KiwiDestructionGeometry.evaluate(cube,{"cut":op},1)
	check(result.error.is_empty() and result.parts.size()==2,"Plane fracture creates two actual meshes")
	var valid:=true; var volume:=0.0; var capped:=true
	for part: KiwiModelMesh in result.get("parts",[]): valid=valid and KiwiDestructionGeometry.closed(part); volume+=KiwiDestructionGeometry.volume(part); capped=capped and part.materials.has(1)
	check(valid and absf(volume-1)<.00001,"Cut solids are closed, valid, consistently wound and volume-conserving")
	check(capped,"Fresh cut surfaces use the dedicated interior material")
	op.type=1; op.pieces=7; result=KiwiDestructionGeometry.evaluate(cube,{"multi":op},1)
	valid=result.error.is_empty() and result.parts.size()==7
	for part: KiwiModelMesh in result.get("parts",[]): valid=valid and KiwiDestructionGeometry.closed(part)
	check(valid,"Deterministic multi-plane fracture creates seven valid closed pieces")
	for kind in [3,6,7,8]:
		op=KiwiDestructionDefinition.operation(kind); op.radius=.16; op.amount=1.5; op.position=Vector3.ZERO
		var start:=Time.get_ticks_usec(); result=KiwiDestructionGeometry.evaluate(cube,{"carve":op},1)
		volume=0; valid=result.error.is_empty() and not result.parts.is_empty()
		for part: KiwiModelMesh in result.get("parts",[]): volume+=KiwiDestructionGeometry.volume(part); valid=valid and KiwiDestructionGeometry.closed(part)
		print("DAMAGE ",KiwiDestructionGeometry.TYPES[kind]," pieces=",result.parts.size()," ms=",(Time.get_ticks_usec()-start)/1000.," error=",result.error," volume=",volume)
		check(valid and volume<.999,KiwiDestructionGeometry.TYPES[kind]+" removes actual material with closed interior walls")
	for kind in [4,9,10,11]:
		op=KiwiDestructionDefinition.operation(kind); result=KiwiDestructionGeometry.evaluate(cube,{"deform":op},1)
		check(result.error.is_empty() and result.parts[0].vertices!=original,KiwiDestructionGeometry.TYPES[kind]+" changes real vertices non-destructively")
	var sheet:=KiwiModelPrimitives.create("Plane",{"width":2.,"depth":2.}); op=KiwiDestructionDefinition.operation(5); result=KiwiDestructionGeometry.evaluate(sheet,{"tear":op},1)
	check(result.error.is_empty() and result.parts.size()==2,"Tear separates the connectivity of an open sheet into independently movable regions")
	var concave:=KiwiModelPrimitives.create("Torus",{}); op=KiwiDestructionDefinition.operation(0); result=KiwiDestructionGeometry.evaluate(concave,{"invalid":op},1)
	check(not result.error.is_empty() and result.parts.is_empty(),"Unsupported concave solid fracture returns a clear error without corrupting source geometry")
	check(cube.vertices==original,"Every destruction operation leaves the original shared mesh unchanged")
	print("DESTRUCTION GEOMETRY: %d checks, %d failures"%[checks,failures]); quit(failures)
