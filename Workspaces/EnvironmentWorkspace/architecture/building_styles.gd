extends RefCounted
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const PRESETS={
	"Modern":[0,15.,.15,5,"stone/concrete","metal/brushed_steel"],
	"Traditional":[1,35.,.2,0,"stone/brick","wood/oak"],
	"Cottage":[1,50.,.25,1,"stone/limestone","wood/dark_aged_wood"],
	"Cabin":[1,35.,.24,2,"wood/rough_timber","wood/pine"],
	"Industrial":[2,12.,.18,6,"stone/rough_concrete","metal/rough_iron"],
	"Medieval":[3,48.,.35,1,"stone/stone_bricks","wood/dark_aged_wood"],
	"Gothic-Inspired":[1,65.,.4,3,"stone/limestone","stone/limestone"],
	"Classical-Inspired":[0,15.,.3,4,"stone/marble","stone/marble"],
	"Minimalist":[0,10.,.12,0,"stone/concrete","metal/aluminum"],
	"Stylized/Cartoon":[3,45.,.3,2,"stone/brick","wood/painted_wood"],
	"Fantasy":[3,65.,.3,7,"stone/sandstone","metal/copper"],
	"Futuristic":[2,18.,.16,5,"metal/brushed_steel","metal/aluminum"]}
static func apply(authored: Resource,name: String) -> Resource:
	if not PRESETS.has(name): return null
	var source: Resource=Source.copy(authored); var settings: Array=PRESETS[name]; source.style=name; source.roof_type=settings[0]; source.roof_pitch=settings[1]; source.wall_thickness=settings[2]; source.facade_detail=settings[3]; source.detail_width=.22 if name=="Stylized/Cartoon" else .12
	var engine=preload("res://scripts/materials/natural_material_engine.gd")
	while source.materials.size()<5: source.materials.append(null)
	source.materials[0]=engine.create_spatial_material(engine.defaults(settings[4])); source.materials[3]=engine.create_spatial_material(engine.defaults(settings[5]))
	for floor: Dictionary in source.floors:
		for wall: Dictionary in floor.walls:
			var length: float=(wall.b as Vector2).distance_to(wall.a); var height:=Source.wall_height(source,floor,wall)
			for opening: Dictionary in wall.get("openings",[]):
				if str(opening.id).begins_with("layout:door"): continue
				if opening.get("type","")=="window":
					var desired_width:=2.4 if name in ["Modern","Minimalist","Futuristic"] else (1. if name in ["Medieval","Gothic-Inspired"] else 1.4)
					var available:=2.*minf(float(opening.get("t",.5)),1.-float(opening.get("t",.5)))*length-.1
					opening.width=minf(float(opening.get("width",desired_width)),minf(desired_width,maxf(.1,available)))
					opening.height=minf(1.65 if name in ["Modern","Futuristic"] else 1.2,height-.4); opening.bottom=maxf(.1,minf(float(opening.get("bottom",1.)),height-float(opening.height)-.1))
				elif name=="Gothic-Inspired": opening.type="arch"
				elif name in ["Modern","Minimalist","Futuristic"] and opening.get("type","")!="arch": opening.type="slider"
	return source
static func facade(source: Resource,floor: Dictionary,wall: Dictionary) -> KiwiModelMesh:
	var mesh:=KiwiModelMesh.new(); var kind:=int(source.facade_detail)
	if kind==0: return mesh
	var a: Vector2=wall.a; var b: Vector2=wall.b; var height:=Source.wall_height(source,floor,wall); var length:=a.distance_to(b); var width:=clampf(float(source.detail_width),.04,.5); var direction: Vector2=(b-a).normalized(); var normal:=Vector2(-direction.y,direction.x); var polygon: PackedVector2Array=floor.get("footprint",source.footprint)
	var plus:=Geometry2D.is_point_in_polygon((a+b)*.5+normal*.05,polygon); var minus:=Geometry2D.is_point_in_polygon((a+b)*.5-normal*.05,polygon)
	if plus==minus: return mesh
	var sign: float=-1. if plus else 1.; var z: float=(float(source.wall_thickness)*.5+width*.5)*sign
	if kind in [1,3,4,5,6,7]:
		for x in [0.,length]:
			var depth:=width*4. if kind==3 else width
			mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width,height,depth)),Transform3D(Basis.IDENTITY,Vector3(x,height*.5,z)))
		mesh.append_mesh(KiwiModelPrimitives.box(Vector3(length+width,width,width)),Transform3D(Basis.IDENTITY,Vector3(length*.5,height-width*.5,z)))
	if kind in [1,6]:
		# Diagonal framing stops at opening margins instead of covering doors/windows.
		var spans: Array[Vector2]=[]; var cursor:=0.; var holes: Array=wall.get("openings",[]).duplicate(); holes.sort_custom(func(one: Dictionary,two: Dictionary): return float(one.get("t",.5))<float(two.get("t",.5)))
		for opening: Dictionary in holes:
			var center:=float(opening.get("t",.5))*length; var radius:=float(opening.get("width",1.))*.5+width
			if center-radius>cursor: spans.append(Vector2(cursor,center-radius))
			cursor=maxf(cursor,center+radius)
		if cursor<length: spans.append(Vector2(cursor,length))
		for span in spans:
			if span.y-span.x<.35: continue
			_beam(mesh,Vector3(span.x,width,z),Vector3(span.y,height-width,z),width)
			if kind==6: _beam(mesh,Vector3(span.y,width,z),Vector3(span.x,height-width,z),width)
	elif kind==2:
		for opening: Dictionary in wall.get("openings",[]):
			if opening.get("type","") not in ["door","slider","arch"]: continue
			var x:=float(opening.get("t",.5))*length; var extent:=float(opening.get("width",1.))*.5+.4
			for side in [-1.,1.]: mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width,height-.2,width)),Transform3D(Basis.IDENTITY,Vector3(x+side*extent,(height-.2)*.5,z+sign*.9)))
			mesh.append_mesh(KiwiModelPrimitives.box(Vector3(extent*2.+width,.12,1.2)),Transform3D(Basis.IDENTITY,Vector3(x,height-.14,z+sign*.45)))
	elif kind==5:
		for index in maxi(1,int(length/.5)):
			var x: float=(index+.5)*length/maxi(1,int(length/.5)); var blocked:=false
			for opening: Dictionary in wall.get("openings",[]): blocked=blocked or absf(x-float(opening.get("t",.5))*length)<float(opening.get("width",1.))*.5+width
			if not blocked: mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width*.5,height,width*3.)),Transform3D(Basis.IDENTITY,Vector3(x,height*.5,z)))
	elif kind==7:
		for x in [0.,length]: mesh.append_mesh(KiwiModelPrimitives.create("Cone",{"radius":width*3.,"height":.9,"segments":8}),Transform3D(Basis.IDENTITY,Vector3(x,height+.45,z)))
	return mesh
static func _beam(mesh: KiwiModelMesh,a: Vector3,b: Vector3,width: float) -> void:
	var direction:=b-a
	if direction.length()<.001: return
	mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width,width,direction.length())),Transform3D(Basis.looking_at(-direction.normalized(),Vector3.FORWARD),(a+b)*.5))
