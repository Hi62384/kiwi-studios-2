extends RefCounted
const TYPES=["Wall segment","Wall corner","Column","Pillar","Beam","Door","Window","Stairs","Railing","Floor","Roof section","Arch","Balcony","Porch","Foundation","Decorative trim"]
static func kinds() -> Array:
	var result: Array=[]
	for kind in TYPES: result.append("Architecture / "+kind)
	return result
static func accepts(kind: String) -> bool: return kind.begins_with("Architecture / ") and TYPES.has(kind.get_slice(" / ",1))
static func defaults(kind: String) -> Dictionary:
	var name:=kind.get_slice(" / ",1)
	return {"length":4. if name in ["Wall segment","Stairs","Railing","Beam","Floor","Roof section"] else 2.,"height":3. if name in ["Wall segment","Wall corner","Column","Pillar","Stairs"] else (2.2 if name in ["Door","Window","Arch"] else (1. if name=="Railing" else .2)),"width":.4 if name in ["Column","Pillar"] else 1.2,"depth":.2,"trim":.07,"spacing":.6,"rails":2,"steps":16,"shape":0,"base":.1,"capital":.12,"angle":0.,"architectural_component":name,"architecture_type":"architectural component"}
static func _box(mesh: KiwiModelMesh,size: Vector3,center: Vector3,material: int=0) -> void:
	mesh.append_mesh(KiwiModelPrimitives.box(size.max(Vector3.ONE*.005)),Transform3D(Basis.IDENTITY,center),material)
static func normalize(parameters: Dictionary) -> Dictionary:
	var result:=parameters.duplicate(true)
	for key in ["length","height","width","depth","trim","spacing","base","capital","angle"]:
		var value:=float(result.get(key,0.))
		if not is_finite(value): value=0.
		result[key]=clampf(value,-170.,170.) if key=="angle" else clampf(value,0. if key in ["base","capital"] else .02,50.)
	result.width=clampf(float(result.width),.1,10.); result.height=clampf(float(result.height),.05,20.); result.length=clampf(float(result.length),.1,50.); result.depth=clampf(float(result.depth),.02,2.); result.base=clampf(float(result.base),0.,float(result.height)*.25); result.capital=clampf(float(result.capital),0.,float(result.height)*.25); result.trim=clampf(float(result.trim),.01,minf(float(result.width),float(result.height))*.3); result.shape=clampi(int(result.get("shape",0)),0,2); result.steps=clampi(int(result.get("steps",16)),2,80); result.rails=clampi(int(result.get("rails",2)),1,6)
	return result
static func generate(kind: String,p: Dictionary) -> KiwiModelMesh:
	var mesh:=KiwiModelMesh.new(); var name:=kind.get_slice(" / ",1); var length:=clampf(float(p.get("length",2.)),.1,50.); var height:=clampf(float(p.get("height",2.)),.05,20.); var width:=clampf(float(p.get("width",1.2)),.1,10.); var depth:=clampf(float(p.get("depth",.2)),.02,2.)
	match name:
		"Column","Pillar":
			var radius:=width*.5; var base:=clampf(float(p.get("base",.1)),0.,height*.25); var capital:=clampf(float(p.get("capital",.12)),0.,height*.25); var body:=height-base-capital; var shape:=int(p.get("shape",0))
			if shape==1: _box(mesh,Vector3(width,body,width),Vector3.UP*(base+body*.5))
			else: mesh.append_mesh(KiwiModelPrimitives.create("Cylinder",{"radius":radius,"height":body,"segments":8 if shape==2 else 24}),Transform3D(Basis.IDENTITY,Vector3.UP*(base+body*.5)))
			if base>0.: _box(mesh,Vector3(width*1.3,base,width*1.3),Vector3.UP*base*.5)
			if capital>0.: _box(mesh,Vector3(width*1.4,capital,width*1.4),Vector3.UP*(height-capital*.5))
		"Wall segment": _box(mesh,Vector3(length,height,depth),Vector3(length*.5,height*.5,0))
		"Wall corner": _box(mesh,Vector3(length,height,depth),Vector3(length*.5,height*.5,0)); _box(mesh,Vector3(depth,height,length),Vector3(0,height*.5,length*.5))
		"Door","Window":
			var trim:=clampf(float(p.get("trim",.07)),.01,minf(width,height)*.3)
			for x in [-1.,1.]: _box(mesh,Vector3(trim,height,depth),Vector3(x*(width-trim)*.5,height*.5,0.))
			_box(mesh,Vector3(width,trim,depth),Vector3(0,height-trim*.5,0))
			if name=="Window":
				_box(mesh,Vector3(width,trim,depth),Vector3(0,trim*.5,0))
		"Railing": _railing(mesh,length,height,depth,float(p.get("spacing",.6)),int(p.get("rails",2)))
		"Stairs":
			var steps:=clampi(int(p.get("steps",16)),2,80)
			for step in steps: var y:=height*(step+1)/steps; _box(mesh,Vector3(width,y,length/steps),Vector3(0,y*.5,(step+.5)*length/steps))
		"Arch": mesh=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd").wall_mesh(width,height,depth,[{"id":"arch","type":"arch","t":.5,"width":maxf(.05,width-depth*2.),"height":maxf(.1,height-depth),"bottom":0.}])
		"Balcony","Porch":
			_box(mesh,Vector3(width,depth,length),Vector3(0,-depth*.5,length*.5)); var railing:=KiwiModelMesh.new(); _railing(railing,width,1.,depth*.4,float(p.get("spacing",.6)),int(p.get("rails",2))); mesh.append_mesh(railing,Transform3D(Basis.IDENTITY,Vector3(0,0,length)))
			if name=="Porch":
				for sign in [-1.,1.]: _box(mesh,Vector3(depth,2.5,depth),Vector3(sign*(width-depth)*.5,1.25,length-depth*.5))
				_box(mesh,Vector3(width+depth,.12,length+depth),Vector3(0,2.56,length*.5))
		"Floor","Roof section","Foundation": _box(mesh,Vector3(width,height,length),Vector3(0,-height*.5,0))
		_: _box(mesh,Vector3(length,height,depth),Vector3(length*.5,height*.5,0))
	return mesh
static func _railing(mesh: KiwiModelMesh,length: float,height: float,depth: float,spacing: float,rails: int) -> void:
	var posts:=clampi(ceili(length/maxf(.1,spacing)),1,128)
	for index in posts+1: _box(mesh,Vector3(depth,height,depth),Vector3(-length*.5+length*index/posts,height*.5,0))
	for rail in clampi(rails,1,6): _box(mesh,Vector3(length,depth,depth),Vector3(0,height*(rail+1)/clampi(rails,1,6),0))
static func add(session: KiwiModelSession,kind: String,parameters: Dictionary,position: Vector3) -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=kind.get_slice(" / ",1); item.generator=kind; item.parameters=defaults(kind); item.parameters.merge(parameters,true); item.parameters=normalize(item.parameters); item.mesh=generate(kind,item.parameters); item.transform.origin=position; item.structural={&"structure_enabled":false,&"structure_role":0}; var material:=StandardMaterial3D.new(); material.albedo_color=Color("b8b5a8"); item.surface_materials=[material]
	if item.title=="Window": var glass:=StandardMaterial3D.new(); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glass.albedo_color=Color(.6,.8,.9,.3); glass.roughness=.12; item.surface_materials.append(glass)
	session.action("Add "+item.title,func():
		session.document.components.append(item); session.selected=[item.id]
		if item.title=="Door": _door_leaf(session,item)
		elif item.title=="Window": _window_glass(session,item))
	return item
static func _door_leaf(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	var id:=item.id+":leaf"; var leaf:=session.document.component(id); var fresh:=leaf==null
	if fresh: leaf=KiwiModelComponent.new(); leaf.id=id; leaf.title="Door leaf"; leaf.parent_id=item.id; session.document.components.append(leaf)
	var width:=float(item.parameters.width); var height:=float(item.parameters.height); var trim:=clampf(float(item.parameters.get("trim",.07)),.01,minf(width,height)*.3); var mesh:=KiwiModelPrimitives.box(Vector3(width-trim*2.,height-trim,.05))
	for index in mesh.vertices.size(): mesh.vertices[index]+=Vector3((width-trim*2.)*.5,(height-trim)*.5,0)
	var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(item.parameters.get("angle",0.)))),Vector3(-width*.5+trim,0,0))
	if fresh or leaf.transform==leaf.parameters.get("_door_pose",leaf.transform): leaf.transform=pose
	leaf.parameters._door_pose=pose; leaf.parameters.architecture_type="door leaf"; leaf.mesh=mesh; leaf.surface_materials=item.surface_materials.duplicate(); leaf.structural={&"structure_enabled":false,&"structure_role":0,&"structure_connections":{"hinge":KiwiStructure.connection(item.id,Vector3.ZERO,pose.origin,1)}}
static func _window_glass(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	var id:=item.id+":glass"; var glass:=session.document.component(id)
	if glass==null: glass=KiwiModelComponent.new(); glass.id=id; glass.title="Glass pane"; glass.parent_id=item.id; session.document.components.append(glass)
	var width:=float(item.parameters.width); var height:=float(item.parameters.height); var trim:=clampf(float(item.parameters.get("trim",.07)),.01,minf(width,height)*.3)
	glass.mesh=KiwiModelPrimitives.box(Vector3(width-trim*2.,height-trim*2.,.015)); glass.transform.origin=Vector3(0,height*.5,0); glass.surface_materials=[item.surface_materials[1]]; glass.parameters.architecture_type="glass pane"
static func set_parameter(session: KiwiModelSession,id: String,key: String,value: Variant) -> void:
	var item:=session.document.component(id)
	if item==null or not accepts(item.generator): return
	session.action("Change "+item.title,func():
		item.parameters[key]=value; item.parameters=normalize(item.parameters); item.mesh=generate(item.generator,item.parameters)
		if item.title=="Door": _door_leaf(session,item)
		if item.title=="Window": _window_glass(session,item))
