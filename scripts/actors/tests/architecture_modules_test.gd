extends "res://scripts/actors/tests/surface_growth_test.gd"
const Modules=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_modules.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
func run() -> void:
	var source:=KiwiModelDocument.new(); var base:=KiwiModelComponent.new(); base.id="base"; base.mesh=KiwiModelPrimitives.box(Vector3.ONE); source.components.append(base); var child:=KiwiModelComponent.new(); child.id="child"; child.parent_id=base.id; child.mesh=KiwiModelPrimitives.box(Vector3.ONE*.2); child.transform.origin=Vector3(0,1,0); child.structural={&"structure_connections":{"parent":KiwiStructure.connection(base.id)}}; source.components.append(child)
	var path:="user://furniture_module.res"; ResourceSaver.save(source,path); var session:=KiwiEnvironmentSession.new(); var root:=Buildings.add(session); root.transform=Transform3D(Basis.from_euler(Vector3(.1,.7,0)).scaled(Vector3(1.5,1.,.8)),Vector3(7,2,-3)); var before:=session.document.components.size(); var placed:=Modules.insert(session,root.id,path,Transform3D(Basis(Vector3.UP,.3),Vector3(2,0,1)))
	check(placed.error.is_empty() and session.document.components.size()==before+3,"Reusable model inserts as a complete ordinary hierarchy")
	var group:=session.document.component(placed.id); var copied_base: KiwiModelComponent; var copied_child: KiwiModelComponent
	for item in session.document.components:
		if item.parent_id==group.id: copied_base=item
	for item in session.document.components:
		if item.parent_id==copied_base.id: copied_child=item
	check(copied_child!=null and copied_child.structural[&"structure_connections"].parent.target==copied_base.id and copied_base.id!="base","Inserted hierarchy remaps structural references and identities")
	var expected:=session.document.world_transform(root)*group.transform*base.transform*child.transform
	check(session.document.world_transform(copied_child).is_equal_approx(expected),"Nested source transforms are preserved under transformed building parents")
	var change: Resource=Source.copy(Buildings.source(root)); change.roof_pitch=42.; Buildings.update(session,root.id,change)
	check(session.document.component(group.id)!=null and session.document.world_transform(session.document.component(copied_child.id)).is_equal_approx(expected),"Procedural building edits preserve attached custom furniture hierarchies")
	var moving_anchor: Transform3D=Modules.anchors(copied_child)[1].pose; var target_anchor: Transform3D=Modules.anchors(copied_base)[2].pose; var previous:=session.document.component(copied_child.id).transform
	var error:=Modules.snap(session,copied_child.id,moving_anchor,copied_base.id,target_anchor)
	var aligned:=session.document.world_transform(session.document.component(copied_child.id))*moving_anchor; var destination:=session.document.world_transform(session.document.component(copied_base.id))*target_anchor*Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)
	check(error.is_empty() and aligned.is_equal_approx(destination),"Anchor mating is exact under rotated and nonuniformly scaled parent hierarchies")
	session.undo(); check(session.document.component(copied_child.id).transform.is_equal_approx(previous),"Module anchor alignment is one undoable transform edit")
	check(not Modules.snap(session,copied_base.id,Transform3D.IDENTITY,copied_child.id,Transform3D.IDENTITY).is_empty(),"Anchor targets cannot belong to the moving component's descendants")
	var save:="user://building_with_furniture.res"; ResourceSaver.save(session.document,save); var loaded:=ResourceLoader.load(save,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded!=null and loaded.validate().is_empty() and loaded.component(copied_child.id)!=null,"Building and editable furniture save through the existing environment resource")
	var count:=session.document.components.size(); var failed:=Modules.insert(session,"missing",path)
	check(not failed.error.is_empty() and session.document.components.size()==count,"Invalid insertion fails without changing document or history")
	print("ARCHITECTURE MODULES: %d checks, %d failures"%[checks,failures]); quit(failures)
