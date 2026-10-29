extends "res://scripts/actors/tests/surface_growth_test.gd"
const Components=preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd")
func run() -> void:
	var session:=KiwiModelSession.new()
	for kind: String in Components.kinds():
		var item:=session.add(kind); var id:=item.id
		check(item.mesh!=null and not item.mesh.faces.is_empty() and session.document.validate().is_empty(),kind+" creates valid editable native geometry")
		var count:=session.document.components.size(); session.undo(); var absent:=session.document.component(id)==null; session.redo()
		check(absent and session.document.components.size()==count,"Undo/redo restores complete "+kind+" hierarchy")
	var door:=session.add("Architecture / Door"); var id:=door.id; var leaf_id:=id+":leaf"; var leaf:=session.document.component(leaf_id); var initial:=leaf.transform
	Components.set_parameter(session,id,"angle",75.)
	check(session.document.component(leaf_id).transform.basis!=initial.basis and session.document.component(leaf_id).parent_id==id,"Door leaf rotates independently around its hinge")
	session.undo(); check(session.document.component(leaf_id).transform==initial,"Door parameter edit undoes leaf and frame atomically")
	var window:=session.add("Architecture / Window"); var pane:=session.document.component(window.id+":glass")
	check(pane!=null and pane.surface_materials[0] is StandardMaterial3D and (pane.surface_materials[0] as StandardMaterial3D).transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"Window has a separately editable transparent glass child")
	var path:="user://architectural_components.res"; var error:=ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(error==OK and loaded!=null and loaded.validate().is_empty() and loaded.component(leaf_id)!=null,"Native save/reload preserves parametric components and child hierarchy")
	var profile:=PackedVector2Array([Vector2(2.,1.),Vector2(5.,1.),Vector2(5.,3.),Vector2(2.,3.)]); var solid:=KiwiModelPrimitives.prism(profile,.2)
	check(KiwiDestructionGeometry.closed(solid) and KiwiModelGeometry.convex(solid),"Offset prism profiles keep outward normals on every closed solid face")
	Components.set_parameter(session,window.id,"width",.01); var tiny:=session.document.component(window.id+":glass")
	check(tiny.mesh.validate().is_empty() and tiny.mesh.bounds().size.x>0.,"Minimum window dimensions cannot invert the separate glass geometry")
	print("ARCHITECTURAL COMPONENTS: %d checks, %d failures"%[checks,failures]); quit(failures)
