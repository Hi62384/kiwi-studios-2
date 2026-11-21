class_name KiwiModelImport
extends RefCounted
## Imports are copies; never mutate imported scenes, shared meshes or materials.
static func load_document(source: Variant) -> KiwiModelDocument:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_import").load_document(source)
static func _add_mesh(document: KiwiModelDocument,mesh: Mesh,transform: Transform3D,title: String) -> KiwiModelComponent:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_import")._add_mesh(document,mesh,transform,title)

static func boolean(owner: Node,a: KiwiModelMesh,b: KiwiModelMesh,transform: Transform3D,operation: int,a_materials: Array[Material]=[],b_materials: Array[Material]=[]) -> KiwiModelMesh:
	if not is_instance_valid(owner) or not owner.is_inside_tree(): return null
	var job: Node=preload("res://Workspaces/ModelWorkspace/ModelBooleanOperation.cs").new()
	owner.add_child(job)
	if not job.call("start",a,b,transform,operation,a_materials,b_materials): job.queue_free(); return null
	await job.completed
	var result: KiwiModelMesh=job.get("result") if is_instance_valid(job) else null
	if is_instance_valid(job): job.queue_free()
	return result
