extends "res://scripts/actors/tests/surface_growth_test.gd"
const Cluster=preload("res://Workspaces/ModelWorkspace/natural_cluster.gd")
func run() -> void:
	var session:=KiwiModelSession.new(); var group:=session.add("Cluster / River stones",{"count":5,"seed":34},Vector3(3,0,2)); var id:=group.id; var child:=session.document.components[1]; var child_id:=child.id; var original:=child.mesh.vertices.duplicate(); var pose:=child.transform
	check(session.document.components.size()==6 and session.document.validate().is_empty(),"Procedural cluster creates actual editable parented source components")
	session.action("Change cluster",func(): group.parameters.seed=35; Cluster.regenerate(session,group))
	check(session.document.component(child_id)!=null and session.document.component(child_id).mesh.vertices!=original,"Changing cluster seed preserves child identity and changes real geometry")
	session.undo(); check(session.document.component(child_id).mesh.vertices==original and session.document.component(child_id).transform==pose,"Cluster regeneration undoes source, geometry and placement together")
	group=session.document.component(id); child=session.document.component(child_id); child.transform.origin+=Vector3(1,2,3); var edited:=child.transform; child.mesh.vertices[0]+=Vector3(.3,0,0); var manual:=child.mesh.vertices.duplicate()
	session.action("Regenerate with edits",func(): group.parameters.seed=71; Cluster.regenerate(session,group)); session.action("Regenerate again",func(): group.parameters.seed=72; Cluster.regenerate(session,group))
	check(session.document.component(child_id).transform==edited and session.document.component(child_id).mesh.vertices==manual,"Repeated regeneration preserves manual child pose and geometry overrides")
	var path:="user://natural_cluster.res"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and loaded.validate().is_empty() and loaded.component(child_id).parent_id==id,"Reusable cluster source and exact hierarchy survive reopening")
	var constrained:=KiwiModelSession.new(); var dense:=constrained.add("Cluster / Boulder field",{"count":20,"spread":.1,"spacing":5.})
	check(constrained.document.components.size()==2 and not str(dense.parameters._cluster_warning).is_empty(),"Impossible spacing warns and avoids overlapping procedural placements")
	print("NATURAL CLUSTER: %d checks, %d failures"%[checks,failures]); quit(failures)
