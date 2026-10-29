extends RefCounted
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd")
const TYPES=["Highway","Major Road","Secondary Road","Residential Street","Rural Road","Dirt Road","Forest Track","Pedestrian Path","Mountain Road","Custom Road"]
static func defaults(type: String="Residential Street") -> Dictionary:
	var source: Dictionary={"type":type,"section":true,"width":6.,"thickness":.12,"shoulder":.3,"sidewalk":1.5,"curb_height":.15,"curb_width":.14,"lanes":2,"markings":true,"speed_limit":30.,"one_way":false,"surface":"asphalt"}
	var profiles: Dictionary={"Highway":{"width":20.,"shoulder":2.5,"sidewalk":0.,"curb_height":0.,"lanes":6,"speed_limit":100.},"Major Road":{"width":12.,"shoulder":.5,"lanes":4,"speed_limit":60.},"Secondary Road":{"width":8.,"lanes":2,"speed_limit":50.},"Rural Road":{"width":5.,"shoulder":.75,"sidewalk":0.,"curb_height":0.,"speed_limit":60.},"Dirt Road":{"width":4.,"shoulder":.4,"sidewalk":0.,"curb_height":0.,"thickness":.04,"markings":false,"surface":"dirt","speed_limit":25.},"Forest Track":{"width":2.5,"shoulder":.2,"sidewalk":0.,"curb_height":0.,"thickness":.02,"markings":false,"surface":"gravel","speed_limit":15.},"Pedestrian Path":{"width":2.,"shoulder":.1,"sidewalk":0.,"curb_height":0.,"thickness":.06,"markings":false,"surface":"path","lanes":1,"speed_limit":0.},"Mountain Road":{"width":5.,"shoulder":.5,"sidewalk":0.,"curb_height":0.,"speed_limit":35.}}
	source.merge(profiles.get(type,{}),true); return source
static func prepare(source: Resource) -> void:
	for entry in [["gravel",Color("77756c")],["dirt",Color("786147")],["path",Color("aaa594")],["concrete",Color("a7aaa4")],["paint",Color("eae5c7")]]:
		if source.road_materials.has(entry[0]): continue
		var material:=StandardMaterial3D.new(); material.albedo_color=entry[1]; material.roughness=.95; source.road_materials[entry[0]]=material
static func outer_half(road: Dictionary) -> float:
	return float(road.width)*.5+(float(road.get("shoulder",0.))+float(road.get("sidewalk",0.))+(float(road.get("curb_width",.14)) if float(road.get("curb_height",0.))>0. else 0.) if road.get("section",false) else 0.)
static func material(source: Resource,road: Dictionary,part: String="surface") -> Material:
	if part=="surface":
		if road.get("material") is Material: return road.material
		return source.road_material if str(road.get("surface","asphalt"))=="asphalt" else source.road_materials.get(str(road.surface),source.road_material)
	if part=="markings": return source.road_materials.get("paint",source.road_material)
	if part=="shoulders": return source.shoulder_material if source.shoulder_material!=null else source.road_materials.get("gravel",source.road_material)
	return source.road_materials.get("concrete",source.road_material)
static func validate(road: Dictionary) -> PackedStringArray:
	var errors:=PackedStringArray()
	if not road.get("section",false): return errors
	for spec in [["thickness",0.,2.],["shoulder",0.,8.],["sidewalk",0.,8.],["curb_height",0.,.5],["curb_width",.05,1.],["speed_limit",0.,200.]]:
		var value:=float(road.get(spec[0],0.))
		if not is_finite(value) or value<float(spec[1]) or value>float(spec[2]): errors.append("Road "+str(spec[0])+" is outside its supported range.")
	if int(road.get("lanes",2))<1 or int(road.get("lanes",2))>12: errors.append("Roads support one to twelve lanes.")
	return errors
static func build(points: PackedVector3Array,road: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var width:=float(road.width); var sections: Dictionary=road.get("_cross_sections",{}); var result: Dictionary={"surface":Geometry.strip(points,width,0.,sections),"errors":PackedStringArray()}
	if not road.get("section",false): return result
	var thickness:=float(road.get("thickness",.12))
	if thickness>0.: result.surface=_solid(result.surface,thickness)
	var shoulder:=float(road.get("shoulder",0.)); var walk:=float(road.get("sidewalk",0.)); var curb:=float(road.get("curb_height",0.)); var curb_width:=float(road.get("curb_width",.14)) if curb>0. else 0.
	for side: float in [-1.,1.]:
		if shoulder>0.: _append(result,"shoulders",_band(points,shoulder,side*(width+shoulder)*.5,0.,maxf(.04,thickness),sections))
		if curb>0.: _append(result,"curbs",_band(points,curb_width,side*(width*.5+shoulder+curb_width*.5),curb,curb+maxf(.04,thickness),sections))
		if walk>0.: _append(result,"sidewalks",_band(points,walk,side*(width*.5+shoulder+curb_width+walk*.5),curb,maxf(.06,thickness),sections))
	if bool(road.get("markings",false)):
		var lanes:=clampi(int(road.get("lanes",2)),1,12); var paint:=KiwiModelMesh.new(); var cumulative:=PackedFloat32Array([0.])
		for index in points.size()-1: cumulative.append(cumulative[-1]+points[index].distance_to(points[index+1]))
		var length:=float(cumulative[-1]); var phase:=fposmod(float(road.get("distance_start",0.)),6.); var marks:=0
		for lane in range(1,lanes):
			var start:=-phase
			while start<length:
				if cancel.is_valid() and cancel.call(): return {"cancelled":true}
				var path:=_slice(points,cumulative,maxf(0.,start),minf(length,start+3.))
				if path.size()>1:
					var strip:=Geometry.strip(path,minf(.12,width/lanes*.2),-width*.5+width*lane/lanes)
					for index in strip.vertices.size(): strip.vertices[index].y+=.008
					paint.append_mesh(strip); marks+=1
				if marks>32768: return {"errors":PackedStringArray(["Lane-marking budget exceeded. Split this road into smaller generated regions."])}
				start+=6.
		if not paint.faces.is_empty(): result.markings=paint
	return result
static func _band(points: PackedVector3Array,width: float,offset: float,height: float,depth: float,sections: Dictionary={}) -> KiwiModelMesh:
	var mesh:=Geometry.strip(points,width,offset,sections)
	for index in mesh.vertices.size(): mesh.vertices[index].y+=height
	return _solid(mesh,depth)
static func _solid(mesh: KiwiModelMesh,depth: float) -> KiwiModelMesh: return KiwiModelModifiers.apply(mesh,{"type":"Solidify","amount":depth})
static func junction_details(ends: Array) -> Dictionary:
	var result: Dictionary={}; var profile:=PackedVector2Array(); var vertices: Dictionary={}
	for index in ends.size():
		var end: Dictionary=ends[index]; var p: Vector3=end.point; var direction: Vector3=end.direction; var side:=Vector3(-direction.z,0.,direction.x).normalized()
		for sign: float in [-1.,1.]:
			var point:=p+side*float(end.width)*.5*sign; var key:=Vector2(point.x,point.z); profile.append(key); vertices[key]={"point":point,"out":side*sign,"end":index,"road":end.get("road",{})}
	profile=Geometry2D.convex_hull(profile)
	if profile.size()>1 and profile[0].is_equal_approx(profile[-1]): profile.remove_at(profile.size()-1)
	for index in profile.size():
		var a: Dictionary=vertices[profile[index]]; var b: Dictionary=vertices[profile[(index+1)%profile.size()]]
		if a.end==b.end: continue # Leave each road mouth open.
		var inner_a:=0.; var inner_b:=0.
		for part: String in ["shoulders","curbs","sidewalks"]:
			var width_a:=0.; var width_b:=0.; var height_a:=0.; var height_b:=0.
			for pair in [[a,true],[b,false]]:
				var road: Dictionary=pair[0].road; var enabled: bool=bool(road.get("section",false)) and str(road.get("mode","Ground"))=="Ground"; var curb:=float(road.get("curb_height",0.)) if enabled else 0.; var width:=0.; var height:=0.
				if enabled:
					width=float(road.get("shoulder",0.)) if part=="shoulders" else (float(road.get("curb_width",.14)) if part=="curbs" and curb>0. else (float(road.get("sidewalk",0.)) if part=="sidewalks" else 0.)); height=curb if part!="shoulders" else 0.
				if pair[1]: width_a=width; height_a=height
				else: width_b=width; height_b=height
			if width_a>0. or width_b>0.:
				var points: Array[Vector3]=[a.point+a.out*inner_a+Vector3.UP*height_a,b.point+b.out*inner_b+Vector3.UP*height_b,b.point+b.out*(inner_b+width_b)+Vector3.UP*height_b,a.point+a.out*(inner_a+width_a)+Vector3.UP*height_a]; var mesh:=KiwiModelMesh.new()
				for point in points:
					if mesh.vertices.is_empty() or not mesh.vertices[-1].is_equal_approx(point): mesh.vertices.append(point)
				if mesh.vertices.size()>2 and mesh.vertices[0].is_equal_approx(mesh.vertices[-1]): mesh.vertices.remove_at(mesh.vertices.size()-1)
				if mesh.vertices.size()>=3:
					var face:=PackedInt32Array()
					for vertex in mesh.vertices.size(): face.append(vertex)
					mesh.add_face(face)
					if mesh.normal(0).y<0.: mesh.faces[0].reverse(); mesh.uv[0].reverse()
					if mesh.normal(0).y>.01: _append(result,part,_solid(mesh,.12+maxf(height_a,height_b)))
			inner_a+=width_a; inner_b+=width_b
	return result
static func _append(result: Dictionary,key: String,mesh: KiwiModelMesh) -> void:
	if not result.has(key): result[key]=KiwiModelMesh.new()
	result[key].append_mesh(mesh)
static func _slice(points: PackedVector3Array,cumulative: PackedFloat32Array,start: float,end: float) -> PackedVector3Array:
	var result:=PackedVector3Array()
	if end-start<.01: return result
	for index in points.size()-1:
		var a:=float(cumulative[index]); var b:=float(cumulative[index+1])
		if b<=start or a>=end or b-a<.00001: continue
		var first:=points[index].lerp(points[index+1],clampf((start-a)/(b-a),0.,1.)); var last:=points[index].lerp(points[index+1],clampf((end-a)/(b-a),0.,1.))
		if result.is_empty() or not result[-1].is_equal_approx(first): result.append(first)
		if not result[-1].is_equal_approx(last): result.append(last)
	return result
