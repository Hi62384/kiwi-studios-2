extends RefCounted
## Ordinary model hierarchy placement, not a second asset or transform system.
static func insert(session: KiwiModelSession,parent_id: String,path: String,pose: Transform3D=Transform3D.IDENTITY,own_path: String="") -> Dictionary:
	var parent:=session.document.component(parent_id)
	if parent==null or not session.document.editable_component(parent): return {"id":"","error":"Choose an editable parent component."}
	var source:=KiwiModelImport.load_document(path)
	if source is KiwiEnvironmentDocument: return {"id":"","error":"Use reusable environment insertion for terrain and scattering."}
	if source==null or source.components.is_empty() or not source.validate().is_empty(): return {"id":"","error":"Choose a valid model, mesh or imported 3D scene."}
	if not own_path.is_empty() and preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").depends_on(path,own_path): return {"id":"","error":"This source would create a linked model dependency cycle."}
	var group:=KiwiModelComponent.new(); group.id=ActorData.new_id(); group.title=path.get_file().get_basename(); group.parent_id=parent_id; group.transform=pose; group.parameters.architecture_module_source=path; group.parameters.module_linked=preload("res://Workspaces/ModelWorkspace/model_source_link.gd").load_resource(path) is KiwiModelDocument
	var remap: Dictionary={}; var parts: Array[KiwiModelComponent]=[]
	for component in source.components: remap[component.id]=ActorData.new_id()
	for component in source.components:
		var copy:=component.copy_component(); copy.id=remap[component.id]; copy.parent_id=remap.get(component.parent_id,group.id)
		preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").component(copy,remap)
		preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").bind(copy,group.id,component.id)
		parts.append(copy)
	session.action("Insert model module",func():
		session.document.components.append(group)
		if session.document is KiwiEnvironmentDocument: (session.document as KiwiEnvironmentDocument).component_settings[group.id]={"kind":"group"}
		for part in parts:
			session.document.components.append(part)
			if session.document is KiwiEnvironmentDocument: (session.document as KiwiEnvironmentDocument).component_settings[part.id]={"kind":"asset","collision":part.mesh!=null}
		session.selected=[group.id])
	return {"id":group.id,"error":""}
static func anchors(item: KiwiModelComponent) -> Array[Dictionary]:
	var result: Array[Dictionary]=[{"name":"Origin","pose":Transform3D.IDENTITY}]
	for anchor: Dictionary in item.parameters.get("module_anchors",[]):
		if anchor.get("pose") is Transform3D: result.append(anchor.duplicate())
	if item.mesh==null or item.mesh.vertices.is_empty(): return result
	var bounds:=item.mesh.bounds(); var center:=bounds.get_center()
	for axis in 3:
		for sign in [-1.,1.]:
			var normal:=Vector3.ZERO; normal[axis]=sign; var point:=center; point[axis]=(bounds.end if sign>0. else bounds.position)[axis]
			result.append({"name":["X","Y","Z"][axis]+("+" if sign>0. else "−"),"pose":Transform3D(Basis.looking_at(-normal,Vector3.FORWARD if axis==1 else Vector3.UP),point)})
	return result
static func snap(session: KiwiModelSession,id: String,anchor: Transform3D,target_id: String,target_anchor: Transform3D,mate: bool=true) -> String:
	var item:=session.document.component(id); var target:=session.document.component(target_id)
	if item==null or target==null or id==target_id or session.document.is_descendant(target_id,id): return "Choose a target outside the moving component's hierarchy."
	if not session.document.editable_component(item): return "This component is locked."
	var parent:=session.document.component(item.parent_id); var parent_pose:=session.document.world_transform(parent) if parent!=null else Transform3D.IDENTITY
	if absf(parent_pose.basis.determinant())<.000001 or absf(anchor.basis.determinant())<.000001: return "A zero-size transform cannot be aligned."
	var facing:=Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO) if mate else Transform3D.IDENTITY
	var pose:=parent_pose.affine_inverse()*session.document.world_transform(target)*target_anchor*facing*anchor.affine_inverse()
	if not pose.origin.is_finite() or not pose.basis.is_finite(): return "The alignment produced an invalid transform."
	session.action("Align module anchors",func(): item.transform=pose); return ""
