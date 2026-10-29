extends "res://scripts/actors/tests/surface_growth_test.gd"
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
func run() -> void:
	var signatures: Dictionary={}
	for kind: String in Generator.kinds():
		var a:=Generator.generate(kind,{}); var b:=Generator.generate(kind,{})
		var errors: PackedStringArray=a.mesh.validate()
		check(errors.is_empty() and not a.mesh.faces.is_empty(),kind+" has valid editable topology "+str(errors))
		check(a.mesh.vertices==b.mesh.vertices and a.mesh.faces==b.mesh.faces,kind+" is deterministic")
		signatures[kind]=hash([a.mesh.vertices,a.mesh.faces])
		if kind.begins_with("Tree"):
			var ids: Dictionary={}
			for branch: Dictionary in a.branches: ids[branch.id]=branch
			var attached:=true
			for leaf: Dictionary in a.attachments:
				attached=attached and ids.has(leaf.branch) and (ids[leaf.branch].points as PackedVector3Array).has(leaf.position)
			check(attached,kind+" leaves have actual twig attachment metadata")
	var session:=KiwiModelSession.new(); var item:=session.add("Tree / Oak",{"seed":42,"branches":4,"levels":1}); var id:=item.id; var original:=item.mesh.vertices.duplicate()
	check(item.surface_materials.size()==3,"Natural generators use native material slots")
	session.action("Regenerate source",func(): item.parameters.seed=43; item.mesh=Generator.generate(item.generator,item.parameters).mesh)
	check(item.mesh.vertices!=original,"Seed changes actual geometry")
	session.undo(); check(session.document.component(id).mesh.vertices==original and session.document.component(id).parameters.seed==42,"Undo restores source and mesh")
	session.redo(); check(session.document.component(id).parameters.seed==43,"Redo restores generator change")
	var path:="user://natural_generator_test.res"; check(ResourceSaver.save(session.document,path)==OK,"Procedural natural model saves normally")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded!=null and loaded.validate().is_empty() and loaded.component(id).generator=="Tree / Oak","Source and editable geometry survive reopening")
	var instance:=loaded.instantiate_model(); check(instance.get_child_count()>0,"Normal model renderer instantiates natural geometry"); instance.free()
	var base:=Generator.generate("Tree / Oak",{}); var pruned:=Generator.generate("Tree / Oak",{"branch_overrides":{"b0":{"pruned":true}}}); var before: Dictionary={}; var after: Dictionary={}
	for branch: Dictionary in base.branches: before[branch.id]=branch.points
	for branch: Dictionary in pruned.branches: after[branch.id]=branch.points
	var stable:=not after.has("b0") and after.has("b1")
	for key: String in after: stable=stable and after[key]==before[key]
	check(stable,"Pruning one branch preserves all surviving branch geometry and identities")
	var joined:=0
	for branch: Dictionary in base.branches: joined+=1 if branch.get("joined",false) else 0
	check(joined==base.branches.size()-1,"Every limb has an actual stitched parent-surface junction")
	var wood:=KiwiModelMesh.new(); wood.vertices=base.mesh.vertices
	for f in base.mesh.faces.size():
		if base.mesh.materials[f]==0: wood.add_face(base.mesh.faces[f],base.mesh.uv[f])
	var closed:=true
	for edge: Dictionary in wood.edges(): closed=closed and edge.faces.size()==2
	check(closed,"Wood junctions remain closed manifold edges")
	print("NATURAL GENERATOR: %d checks, %d failures"%[checks,failures]); quit(failures)
