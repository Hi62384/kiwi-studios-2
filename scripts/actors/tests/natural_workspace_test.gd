extends "res://scripts/actors/tests/surface_growth_test.gd"
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
func run() -> void:
	var workspace:=KiwiEnvironmentWorkspace.new(); root.add_child(workspace); await process_frame; await process_frame
	var item:=workspace.session.add("Tree / Birch",{"seed":71,"levels":1}); workspace.canvas.frame(); await process_frame; await process_frame
	check(workspace.session.environment().validate().is_empty(),"Natural source fits ordinary environment document and inspector")
	check(workspace.canvas.renderer.nodes.has(item.id),"Environment renderer displays native procedural model")
	var original:=item.mesh.vertices.duplicate(); var source_material:=item.surface_materials[0]
	workspace.session.action("Material only",func(): item.surface_materials[1]=StandardMaterial3D.new())
	check(item.mesh.vertices==original,"Material edits leave geometry and source distribution unchanged")
	workspace.session.undo(); check(workspace.session.document.component(item.id).surface_materials[0]==source_material,"Native undo retains shared authored material")
	var sources:=[]
	for name in Generator.TREES:
		var result:=Generator.generate("Tree / "+name,{"levels":1}); sources.append(hash(result.mesh.vertices))
	check(sources.size()==17,"All seventeen tree families are available")
	var unique: Dictionary={}
	for value in sources: unique[value]=true
	check(unique.size()==17,"Each tree family changes actual geometry")
	workspace.queue_free(); await process_frame
	print("NATURAL WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
