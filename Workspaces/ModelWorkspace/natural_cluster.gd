extends RefCounted
## Editable ordinary component groups; generated children retain stable IDs and
## manually edited child geometry/poses across procedural regeneration.
const Generator=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
const PRESETS={"Boulder field":"Rock / Granite","River stones":"Rock / River stone","Rockfall":"Rock / Slate","Forest grove":"Tree / Oak","Grass patch":"Plant / Grass","Deadwood":"Prop / Driftwood"}
static func kinds() -> Array:
	var result: Array=[]
	for title: String in PRESETS: result.append("Cluster / "+title)
	return result
static func accepts(item: Resource) -> bool: return item!=null and item.parameters.has("natural_cluster")
static func add(session: KiwiModelSession,kind: String,parameters: Dictionary,position: Vector3) -> KiwiModelComponent:
	var root:=KiwiModelComponent.new(); root.id=ActorData.new_id(); root.title=kind.get_slice(" / ",1); root.transform.origin=position; root.parameters={"natural_cluster":kind,"seed":1,"count":8,"spread":4.,"spacing":.5,"scale_variation":.4}; root.parameters.merge(parameters,true)
	session.action("Add natural cluster",func(): session.document.components.append(root); regenerate(session,root); session.selected=[root.id])
	return root
static func regenerate(session: KiwiModelSession,root: KiwiModelComponent) -> void:
	var p:=root.parameters; var kind: String=PRESETS.get(str(p.natural_cluster).get_slice(" / ",1),"Rock / Granite"); var old: Dictionary={}; var taken:=PackedVector2Array()
	for item in session.document.components:
		if item.parent_id==root.id and item.parameters.has("_cluster_index"): old[int(item.parameters._cluster_index)]=item
	var count:=clampi(int(p.get("count",8)),1,64); var materials:=Generator.materials(kind); var source:=Generator.defaults(kind); var live: Dictionary={}; var constrained:=0
	if kind.begins_with("Tree"): source.levels=1
	for index in count:
		var rng:=RandomNumberGenerator.new(); rng.seed=hash([int(p.get("seed",1)),index]); var point:=Vector2.ZERO; var clear:=false
		for attempt in 100:
			point=Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*maxf(.01,float(p.get("spread",4.))); clear=true
			for other in taken:
				if point.distance_to(other)<float(p.get("spacing",.5)): clear=false; break
			if clear: break
		if not clear: constrained+=1; continue
		live[index]=true
		var item:=old.get(index) as KiwiModelComponent; var fresh:=item==null
		if fresh:
			item=KiwiModelComponent.new(); item.id=root.id+":natural:"+str(index); item.parent_id=root.id; item.title=kind.get_slice(" / ",1)+" "+str(index+1); session.document.components.append(item)
		var previous: Dictionary=item.parameters.duplicate(true); var old_pose: Transform3D=previous.get("_cluster_pose",item.transform); var manual_pose: bool=not fresh and not item.transform.is_equal_approx(old_pose)
		var old_hash: int=int(previous.get("_cluster_mesh",0)); var manual_mesh: bool=bool(previous.get("_cluster_manual_mesh",false)) or (not fresh and (item.generator.is_empty() or (item.mesh!=null and hash([item.mesh.vertices,item.mesh.faces])!=old_hash)))
		var variation:=clampf(float(p.get("scale_variation",.4)),0.,.9); var size:=rng.randf_range(1.-variation,1.+variation); var pose:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(point.x,0.,point.y))
		if not manual_pose: item.transform=pose
		taken.append(Vector2(item.transform.origin.x,item.transform.origin.z))
		if not manual_mesh:
			var settings:=source.duplicate(true); settings.seed=rng.randi_range(0,2147483647); var generated:=Generator.generate(kind,settings)
			if generated.mesh!=null: item.generator=kind; item.mesh=generated.mesh; item.parameters=settings; item.surface_materials=materials if fresh else item.surface_materials
		item.parameters._cluster_index=index; item.parameters._cluster_pose=pose; item.parameters._cluster_mesh=hash([item.mesh.vertices,item.mesh.faces]) if item.mesh!=null else 0
		item.parameters._cluster_manual_mesh=manual_mesh
	for index: int in old:
		if live.has(index): continue
		var item:=old[index] as KiwiModelComponent; var has_children:=false
		for child in session.document.components:
			if child.parent_id==item.id: has_children=true; break
		# Preserve authored descendants instead of silently deleting their parent.
		if has_children: item.parameters.erase("_cluster_index"); continue
		session.document.components.erase(item)
	p._cluster_warning="Placed %d / %d: increase spread or reduce spacing."%[count-constrained,count] if constrained>0 else ""
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> void:
	var heading:=Label.new(); heading.text="NATURAL CLUSTER · "+item.title; parent.add_child(heading)
	if not str(item.parameters.get("_cluster_warning","")).is_empty(): var warning:=Label.new(); warning.text=str(item.parameters._cluster_warning); warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(warning)
	for spec in [["Seed","seed",0.,2147483647.,1.],["Count","count",1.,64.,1.],["Spread (m)","spread",.01,100.,.1],["Spacing (m)","spacing",0.,20.,.1],["Scale variation","scale_variation",0.,.9,.01]]:
		var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text=spec[0]; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label); var number:=DragNumber.new(); number.min_value=spec[2]; number.max_value=spec[3]; number.step=spec[4]; number.set_value_no_signal(float(item.parameters.get(spec[1],0.))); row.add_child(number)
		var write:=func(value: float): workspace.session.action("Change natural cluster",func(): var current: KiwiModelComponent=workspace.session.document.component(item.id); current.parameters[spec[1]]=value; regenerate(workspace.session,current))
		number.value_changed.connect(write); number.drag_committed.connect(write)
