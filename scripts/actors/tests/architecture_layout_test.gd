extends "res://scripts/actors/tests/surface_growth_test.gd"
const Layout=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
func run() -> void:
	var source: Resource=Source.rectangular(8,12); source.seed=42; var result:=Layout.generate(source,5,1.2); check(result.errors.is_empty(),"Constrained house layout generates valid rooms and real door walls")
	var authored: Resource=result.source; var graph:=Layout.connectivity(authored)
	check(authored.floors[0].rooms.size()==6 and graph.warnings.is_empty() and graph.reachable.size()==7,"Five rooms and a central hall all connect to the exterior")
	var total:=0.; var overlap:=false; var rooms: Array=authored.floors[0].rooms
	for index in rooms.size():
		var polygon: PackedVector2Array=rooms[index].polygon; total+=_area(polygon)
		for other in range(index+1,rooms.size()):
			for intersection in Geometry2D.intersect_polygons(polygon,rooms[other].polygon): overlap=overlap or _area(intersection)>.0001
	check(not overlap and is_equal_approx(total,96.),"Room regions partition the footprint without gaps or overlap")
	var repeat:=Layout.generate(source,5,1.2); check(repeat.source.floors==authored.floors and source.floors[0].rooms.size()==1,"Same seed reproduces the source without mutating the previous plan")
	var changed: Resource=Source.copy(source); changed.seed=43; check(Layout.generate(changed,5,1.2).source.floors!=authored.floors,"Changing the seed changes room proportions")
	var blocked: Resource=Source.copy(authored)
	for wall: Dictionary in blocked.floors[0].walls:
		if str(wall.id).begins_with("layout:doorwall"): wall.openings=[]; break
	check(not Layout.connectivity(blocked).warnings.is_empty(),"Removing a connecting door reports inaccessible rooms")
	var building:=Builder.generate(authored); check(building.errors.is_empty() and building.document.components[0].parameters.architecture_navigation.reachable.size()==7,"Native editable hierarchy carries circulation metadata")
	var invalid: Resource=Source.rectangular(); invalid.footprint=PackedVector2Array([Vector2.ZERO,Vector2(5,0),Vector2(4,4),Vector2(0,4)])
	check(not Layout.generate(invalid).errors.is_empty(),"Unsupported footprints are rejected instead of generating overlapping rooms")
	var path:="user://connected_building.res"; ResourceSaver.save(building.document,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(reopened!=null and reopened.components[0].parameters.architecture_navigation.connections==building.document.components[0].parameters.architecture_navigation.connections,"Room graph survives native save and reload")
	var session:=KiwiModelSession.new(); var root:=Buildings.add(session); var before: Resource=Buildings.source(root); var next:=Layout.generate(before,4,1.2); Buildings.update(session,root.id,next.source,"Generate rooms"); session.undo()
	check(Buildings.source(session.document.component(root.id)).floors==before.floors,"Layout generation is one undoable source and geometry edit")
	print("ARCHITECTURE LAYOUT: %d checks, %d failures"%[checks,failures]); quit(failures)
func _area(polygon: PackedVector2Array) -> float:
	var area:=0.
	for index in polygon.size(): area+=polygon[index].cross(polygon[(index+1)%polygon.size()])
	return absf(area)*.5
