extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func closed(mesh: KiwiModelMesh) -> bool:
	for edge in mesh.edges():
		if edge.faces.size()!=2: return false
	return true
func run() -> void:
	for kind in KiwiModelPrimitives.SHAPES:
		var mesh := KiwiModelPrimitives.create(kind)
		check(not mesh.faces.is_empty() and mesh.validate().is_empty(),"Valid editable primitive: "+kind)
		check(mesh.render_mesh().get_surface_count()>0,"Primitive renders: "+kind)
	var box := KiwiModelPrimitives.box(Vector3.ONE*2)
	var native_arrays := BoxMesh.new().surface_get_arrays(0); var native_points: PackedVector3Array=native_arrays[Mesh.ARRAY_VERTEX]; var native_indices: PackedInt32Array=native_arrays[Mesh.ARRAY_INDEX]; var native_normals: PackedVector3Array=native_arrays[Mesh.ARRAY_NORMAL]
	var native_winding := (native_points[native_indices[1]]-native_points[native_indices[0]]).cross(native_points[native_indices[2]]-native_points[native_indices[0]]).dot(native_normals[native_indices[0]])
	var triangles := box.triangles(0); var face := box.faces[0]
	var model_winding := (box.vertices[face[triangles[1]]]-box.vertices[face[triangles[0]]]).cross(box.vertices[face[triangles[2]]]-box.vertices[face[triangles[0]]]).dot(box.normal(0))
	check(signf(native_winding)==signf(model_winding),"Generated triangle winding matches Godot native BoxMesh")
	check(box.vertices.size()==8 and box.faces.size()==6 and closed(box),"Box has shared vertices and six connected polygon faces")
	for f in box.faces.size(): check(box.normal(f).dot(box.center(f))>0,"Box winding points outwards")
	var inset: KiwiModelMesh=KiwiModelGeometry.inset(box,PackedInt32Array([0]),.2).mesh
	check(inset.validate().is_empty() and closed(inset) and inset.faces.size()==10,"Inset makes four connected rim faces")
	var recess: KiwiModelMesh=KiwiModelGeometry.extrude(inset,PackedInt32Array([0]),-.5).mesh
	check(recess.validate().is_empty() and closed(recess) and recess.faces.size()==14,"Negative face extrusion creates a closed cabinet recess")
	var bevel := KiwiModelGeometry.bevel(box,PackedInt32Array(),.1)
	check(bevel!=null and bevel.validate().is_empty() and closed(bevel) and bevel.faces.size()>6,"Convex edge bevel cuts real chamfer faces")
	var subdivided := KiwiModelGeometry.subdivide(box)
	check(subdivided.faces.size()==24 and closed(subdivided) and subdivided.validate().is_empty(),"Subdivision produces connected quads")
	var partial := KiwiModelGeometry.subdivide(box,PackedInt32Array([0]))
	check(partial.faces.size()==9 and closed(partial) and partial.validate().is_empty(),"Selected-face subdivision updates adjacent faces without T-junctions")
	var edge_split := KiwiModelGeometry.subdivide_edges(box,PackedInt32Array([0]))
	check(edge_split.vertices.size()==9 and closed(edge_split) and edge_split.validate().is_empty(),"Edge subdivision inserts a shared editable midpoint, not unrelated faces")
	for kind in KiwiModelModifiers.TYPES:
		var result := KiwiModelModifiers.apply(box,{"type":kind,"amount":.1,"axis":0,"count":2})
		check(not result.faces.is_empty() and result.validate().is_empty(),"Functional modifier: "+kind)
	var mirrored := KiwiModelModifiers.apply(box,{"type":"Mirror","axis":0})
	check(closed(mirrored),"Bisected mirror welds the seam without overlapping internal faces")
	var radial := KiwiModelModifiers.apply(box,{"type":"Radial array","axis":1,"count":4,"amount":3.})
	var ring := true
	for copy in 4:
		var center := Vector3.ZERO
		for i in box.vertices.size(): center+=radial.vertices[copy*box.vertices.size()+i]/box.vertices.size()
		if absf(center.length()-3.)>.0001: ring=false
	check(ring,"Every radial array copy lies on the radius, with no stray center copy")
	var session := KiwiModelSession.new(); var item := session.add("Box")
	var id := item.id; session.mode="Face"; session.elements=PackedInt32Array([0])
	check(session.edit_mesh("Extrude",.4).is_empty(),"Session applies real extrusion")
	session.undo(); check(session.primary().mesh.faces.size()==6 and session.elements==PackedInt32Array([0]),"Undo restores geometry and selection")
	session.redo(); check(session.primary().mesh.faces.size()==10,"Redo restores extrusion")
	session.duplicate_selected(); check(session.document.components.size()==2 and session.primary().id!=id,"Duplicate owns independent mesh and stable new identity")
	var copy_id := session.primary().id
	session.select(id,true); session.parent_selected(); check(session.document.component(copy_id).parent_id==session.primary().id,"Parenting links components")
	session.undo(); check(session.document.component(id).parent_id.is_empty(),"Hierarchy edit is undoable")
	var path := "user://model_geometry_roundtrip.tres"
	check(ResourceSaver.save(session.document,path)==OK,"Native model saves")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and loaded.components.size()==2 and loaded.components[0].id==id and loaded.components[0].mesh.validate().is_empty(),"Native model preserves editable topology and component identity")
	var instance := loaded.instantiate_model(); check(instance.get_child_count()==2,"Saved model instantiates as conventional 3D component hierarchy"); instance.free()
	var sphere := SphereMesh.new(); var original := sphere.get_faces(); var imported := KiwiModelImport.load_document(sphere)
	imported.components[0].mesh.vertices[0]+=Vector3.ONE
	check(sphere.get_faces()==original,"Import conversion leaves original shared source unchanged")
	var invalid := box.copy_mesh(); invalid.faces[0][0]=999
	check(not invalid.validate().is_empty(),"Invalid imported indices are detected without accessing out-of-bounds geometry")
	var graph := preload("res://Workspaces/ModelWorkspace/model_selection.gd")
	var grown := graph.expand(box,"Face",PackedInt32Array([0]),"Grow selection")
	check(grown.size()==5,"Grow advances one adjacent-face ring, not the entire connected object")
	check(graph.expand(box,"Face",grown,"Shrink selection")==PackedInt32Array([0]),"Shrink removes boundary faces rather than growing selection")
	check(graph.expand(box,"Vertex",PackedInt32Array([0]),"Select connected").size()==8,"Connected selection traverses actual vertex adjacency")
	var groups := KiwiModelSession.new(); var one := groups.add("Box",{},Vector3(1,0,0)); var two := groups.add("Box",{},Vector3(-1,0,0)); groups.select(one.id,true); groups.group_selected()
	check(groups.document.components.size()==3 and groups.document.validate().is_empty(),"Grouping preserves valid component hierarchy")
	groups.duplicate_selected(); check(groups.document.components.size()==6 and groups.document.validate().is_empty(),"Duplicating a group includes its independently editable descendants")
	groups.undo(); var root_id := groups.primary().id; groups.select(one.id,true); groups.join_selected()
	check(groups.document.validate().is_empty() and groups.primary().parent_id.is_empty(),"Joining a parent and child cannot leave a self-parent or dangling parent")
	print("MODEL_GEOMETRY checks=%d failures=%d"%[checks,failures]); quit(failures)
