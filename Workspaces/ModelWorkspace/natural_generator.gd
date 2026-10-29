extends RefCounted
## CPU-only editable geometry. Source settings live in normal component parameters;
## native material slots, hierarchy, history and scene import remain authoritative.
const TREES=["Oak","Maple","Birch","Willow","Pine","Spruce","Fir","Palm","Tropical","Mangrove","Acacia","Desert","Twisted","Dead","Wind-shaped","Ancient","Fantasy"]
const PLANTS=["Bush","Grass","Flower","Fern","Vine","Reed","Succulent","Mushroom","Cactus"]
const ROCKS=["Granite","Basalt","Limestone","Sandstone","Slate","River stone","Volcanic"]
const PROPS=["Log","Stump","Driftwood","Root","Stalactite","Stalagmite"]
const MAX_VERTICES=200000
const CACHE_BYTES=67108864
static var _cache: Dictionary={}
static var _cache_bytes:=0
static var _cache_mutex:=Mutex.new()
static func kinds() -> Array:
	var result: Array=[]
	for pair in [["Tree",TREES],["Plant",PLANTS],["Rock",ROCKS],["Prop",PROPS]]:
		for name: String in pair[1]: result.append(pair[0]+" / "+name)
	return result
static func accepts(kind: String) -> bool: return kind in kinds()
static func defaults(kind: String) -> Dictionary:
	var tree:=kind.begins_with("Tree"); var name:=kind.get_slice(" / ",1)
	var result: Dictionary={"seed":1,"height":6. if tree else 1.,"radius":.23 if tree else .5,"segments":8,"levels":2,"branches":8,"length":.46,"angle":.9,"curve":.2,"droop":.65 if name=="Willow" else .05,"lean":.3 if name in ["Wind-shaped","Twisted"] else 0.,"taper":.8,"foliage":0. if name=="Dead" else 1.,"leaf_size":.28,"roots":5,"irregularity":.3,"detail":12}
	var profiles: Dictionary={"Maple":{"branches":10,"leaf_size":.23,"angle":1.2},"Birch":{"height":8.,"radius":.13,"length":.3,"angle":.7},"Pine":{"branches":12,"height":9.,"length":.4,"levels":1},"Spruce":{"branches":16,"height":7.,"length":.55,"droop":.22,"levels":1},"Fir":{"branches":14,"height":10.,"length":.32,"angle":1.3,"levels":1},"Palm":{"height":8.,"radius":.16,"branches":10,"roots":0,"lean":.13},"Tropical":{"height":10.,"radius":.4,"branches":12,"leaf_size":.4,"roots":8},"Mangrove":{"height":4.,"radius":.18,"roots":10,"lean":.15},"Acacia":{"height":5.,"length":.7,"radius":.18,"branches":6,"angle":1.6},"Desert":{"height":3.,"branches":4,"foliage":.2,"curve":.45},"Twisted":{"height":4.,"lean":.45,"curve":.7,"branches":6},"Ancient":{"height":8.,"radius":.7,"roots":12,"branches":5,"curve":.5},"Fantasy":{"height":12.,"radius":.6,"lean":-.2,"curve":.8,"leaf_size":.65,"branches":9},"Wind-shaped":{"lean":.6,"droop":.3,"branches":7,"angle":.5}}
	result.merge(profiles.get(name,{}),true)
	result.season=0; result.wind_strength=0.
	if name=="Stalactite": result.height=2.; result.radius=.2
	if name=="Stalagmite": result.height=1.4; result.radius=.4
	if name=="Cactus": result.branches=3
	return result
static func generate(kind: String, settings: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var p:=defaults(kind); p.merge(settings,true)
	if cancel.is_valid() and cancel.call(): return {"mesh":null,"cancelled":true,"error":"Generation cancelled."}
	p._cancel=cancel
	# Clamp the source at its public boundary, including scripts and loaded files.
	p.height=clampf(float(p.height),.02,200.); p.radius=clampf(float(p.radius),.005,30.); p.segments=clampi(int(p.segments),4,16); p.levels=clampi(int(p.levels),0,3); p.branches=clampi(int(p.branches),1,16); p.detail=clampi(int(p.detail),6,32); p.roots=clampi(int(p.roots),0,16)
	var semantic:=p.duplicate(); semantic.erase("_cancel"); var key: int=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([kind,semantic]); _cache_mutex.lock(); var cached: Dictionary=_cache.get(key,{}); _cache_mutex.unlock()
	if not cached.is_empty():
		var copy:=_copy_result(cached.result)
		if cancel.is_valid() and cancel.call(): return {"mesh":null,"cancelled":true,"error":"Generation cancelled."}
		return copy
	var rng:=RandomNumberGenerator.new(); rng.seed=int(p.seed)
	var mesh:=KiwiModelMesh.new(); mesh.smooth=true
	var graph: Array[Dictionary]=[]; var leaves: Array[Dictionary]=[]
	var name:=kind.get_slice(" / ",1)
	if kind.begins_with("Rock") or name in ["Stalactite","Stalagmite"]: _rock(mesh,name,p,rng)
	elif kind.begins_with("Plant"): _plant(mesh,name,p,rng,graph,leaves)
	else: _tree(mesh,name,p,rng,graph,leaves)
	if p.has("_error"): return {"mesh":null,"cancelled":false,"error":p._error}
	if cancel.is_valid() and cancel.call(): return {"mesh":null,"cancelled":true,"error":"Generation cancelled."}
	if mesh.vertices.size()>MAX_VERTICES: return {"mesh":null,"cancelled":false,"error":"Natural geometry budget exceeded. Reduce branch levels, density or detail."}
	var faces: Array[PackedInt32Array]=[]; var uv: Array[PackedVector2Array]=[]; var materials:=PackedInt32Array()
	for f in mesh.faces.size():
		if mesh.faces[f].is_empty(): continue
		faces.append(mesh.faces[f]); uv.append(mesh.uv[f]); materials.append(mesh.materials[f])
	mesh.faces=faces; mesh.uv=uv; mesh.materials=materials; p.erase("_cancel")
	var result:={"mesh":mesh,"branches":graph,"attachments":leaves,"settings":p,"signature":key,"version":1}; var bytes:=mesh.vertices.size()*12+mesh.materials.size()*4+leaves.size()*96+graph.size()*512
	for f in mesh.faces.size(): bytes+=mesh.faces[f].size()*12
	if bytes<=CACHE_BYTES:
		var stored:=_copy_result(result); _cache_mutex.lock()
		if _cache.has(key): _cache_bytes-=int(_cache[key].bytes); _cache.erase(key)
		while not _cache.is_empty() and (_cache_bytes+bytes>CACHE_BYTES or _cache.size()>=24):
			var oldest: int=_cache.keys()[0]; _cache_bytes-=int(_cache[oldest].bytes); _cache.erase(oldest)
		_cache[key]={"result":stored,"bytes":bytes}; _cache_bytes+=bytes; _cache_mutex.unlock()
	return result
static func _copy_result(source: Dictionary) -> Dictionary:
	var result:=source.duplicate(true); result.mesh=(source.mesh as KiwiModelMesh).copy_mesh(); return result
static func _tube(mesh: KiwiModelMesh, points: PackedVector3Array, radii: PackedFloat32Array, sides: int, slot: int=0) -> Dictionary:
	if points.size()<2: return {}
	var start:=mesh.vertices.size(); var first_face:=mesh.faces.size(); var distance:=0.; var previous_u:=Vector3.ZERO
	for i in points.size():
		var tangent: Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		var u: Vector3=(previous_u-tangent*previous_u.dot(tangent)).normalized() if previous_u!=Vector3.ZERO else tangent.cross(Vector3.FORWARD if absf(tangent.z)<.9 else Vector3.RIGHT).normalized(); var v:=tangent.cross(u); previous_u=u
		var previous_distance:=distance
		if i>0: distance+=points[i].distance_to(points[i-1])
		for j in sides: mesh.vertices.append(points[i]+(u*cos(TAU*j/sides)+v*sin(TAU*j/sides))*radii[i])
		if i==0: continue
		for j in sides:
			var a:=start+(i-1)*sides+j; var b:=start+(i-1)*sides+(j+1)%sides; var c:=start+i*sides+(j+1)%sides; var d:=start+i*sides+j
			mesh.add_face(PackedInt32Array([a,c,b]),PackedVector2Array([Vector2(float(j)/sides,previous_distance),Vector2(float(j+1)/sides,distance),Vector2(float(j+1)/sides,previous_distance)]),slot)
			mesh.add_face(PackedInt32Array([a,d,c]),PackedVector2Array([Vector2(float(j)/sides,previous_distance),Vector2(float(j)/sides,distance),Vector2(float(j+1)/sides,distance)]),slot)
	var first:=PackedInt32Array(); var last:=PackedInt32Array()
	for j in sides: first.append(start+j); last.append(start+(points.size()-1)*sides+sides-1-j)
	var cap:=mesh.add_face(first,PackedVector2Array(),slot); mesh.add_face(last,PackedVector2Array(),slot)
	return {"start":start,"face_start":first_face,"face_end":mesh.faces.size(),"cap":cap,"sides":sides}

static func _junction(mesh: KiwiModelMesh,graph: Array[Dictionary],parent: String,origin: Vector3,direction: Vector3,length: float) -> Dictionary:
	var found: Dictionary={}; var fallback: Dictionary={}; var nearest:=INF; var fallback_distance:=INF
	for branch: Dictionary in graph:
		if branch.id!=parent or not branch.has("topology"): continue
		var topology: Dictionary=branch.topology
		for f in range(topology.face_start,topology.face_end):
			var face: PackedInt32Array=mesh.faces[f]
			if face.size()!=3: continue
			var alignment:=mesh.normal(f).dot(direction)
			if alignment>.15:
				var center:=mesh.center(f); var score:=origin.distance_squared_to(center)/maxf(.2,alignment)
				if score<fallback_distance: fallback_distance=score; fallback={"point":center,"face":f,"indices":face.duplicate()}
			var hit: Variant=Geometry3D.segment_intersects_triangle(origin,origin+direction*maxf(.1,length),mesh.vertices[face[0]],mesh.vertices[face[1]],mesh.vertices[face[2]])
			if hit==null or alignment<.15: continue
			var distance: float=origin.distance_squared_to(hit)
			if distance<nearest: nearest=distance; found={"point":hit,"face":f,"indices":face.duplicate()}
		break
	return fallback if found.is_empty() else found

static func _stitch(mesh: KiwiModelMesh,junction: Dictionary,tube: Dictionary,axis: Vector3) -> void:
	if junction.is_empty() or tube.is_empty(): return
	var center: Vector3=junction.point; var u:=axis.cross(Vector3.FORWARD if absf(axis.z)<.9 else Vector3.RIGHT).normalized(); var v:=axis.cross(u)
	var rings: Array=[]
	for indices: PackedInt32Array in [junction.indices,PackedInt32Array(range(int(tube.start),int(tube.start)+int(tube.sides)))]:
		var entries: Array=[]
		for index in indices:
			var offset:=mesh.vertices[index]-center; entries.append({"index":index,"angle":fposmod(atan2(offset.dot(v),offset.dot(u)),TAU)})
		entries.sort_custom(func(a: Dictionary,b: Dictionary): return a.angle<b.angle); rings.append(entries)
	var a: Array=rings[0]; var b: Array=rings[1]; var ai:=0; var bi:=0
	for step in a.size()+b.size():
		var next_a: float=float(a[(ai+1)%a.size()].angle)+(TAU if ai+1>=a.size() else 0.)
		var next_b: float=float(b[(bi+1)%b.size()].angle)+(TAU if bi+1>=b.size() else 0.)
		if ai>=a.size(): next_a=INF
		if bi>=b.size(): next_b=INF
		var face:=PackedInt32Array([a[ai%a.size()].index,a[(ai+1)%a.size()].index,b[bi%b.size()].index]) if next_a<next_b else PackedInt32Array([a[ai%a.size()].index,b[(bi+1)%b.size()].index,b[bi%b.size()].index])
		var index:=mesh.add_face(face); var c:=mesh.center(index)-center; var radial:=c-axis*c.dot(axis)
		if mesh.normal(index).dot(radial)<0.: mesh.faces[index].reverse(); mesh.uv[index].reverse()
		if next_a<next_b: ai+=1
		else: bi+=1
	mesh.faces[int(junction.face)]=PackedInt32Array(); mesh.faces[int(tube.cap)]=PackedInt32Array()
static func _leaf(mesh: KiwiModelMesh, origin: Vector3, direction: Vector3, size: float, width: float, slot: int=1,style: int=0) -> void:
	var d:=direction.normalized(); var side:=d.cross(Vector3.UP if absf(d.y)<.95 else Vector3.RIGHT).normalized()*size*width; var at:=mesh.vertices.size()
	if style>0:
		var outline:=PackedVector2Array()
		if style==1: outline=PackedVector2Array([Vector2(0,0),Vector2(-.35,.3),Vector2(-1,.45),Vector2(-.5,.57),Vector2(-.75,.85),Vector2(-.2,.72),Vector2(0,1),Vector2(.2,.72),Vector2(.75,.85),Vector2(.5,.57),Vector2(1,.45),Vector2(.35,.3)])
		else:
			for i in 20:
				var a:=TAU*i/20.; var t: float=(1.-cos(a))*.5; var w:=sin(a)*(1.+.2*sin(t*PI*8.) if style==2 else 1.)
				outline.append(Vector2(w,t))
		for point in outline: mesh.vertices.append(origin+d*size*point.y+side*point.x)
		mesh.vertices.append(origin+d*size*.5+Vector3.UP*size*.06)
		for index in outline.size(): mesh.add_face(PackedInt32Array([at+index,at+(index+1)%outline.size(),at+outline.size()]),PackedVector2Array([Vector2(outline[index].x*.5+.5,outline[index].y),Vector2(outline[(index+1)%outline.size()].x*.5+.5,outline[(index+1)%outline.size()].y),Vector2(.5,.5)]),slot)
		return
	# Folded lanceolate leaf; actual base stays attached to its supporting twig.
	mesh.vertices.append_array(PackedVector3Array([origin,origin+d*size*.45+side,origin+d*size+Vector3.UP*size*.1,origin+d*size*.45-side,origin+d*size*.5+Vector3.UP*size*.09]))
	for f in [[0,1,4],[1,2,4],[2,3,4],[3,0,4]]:
		var ids:=PackedInt32Array(); var corners:=PackedVector2Array(); var mapping: Array=[Vector2(.5,0),Vector2(0,.45),Vector2(.5,1),Vector2(1,.45),Vector2(.5,.5)]
		for index: int in f: ids.append(at+index); corners.append(mapping[index])
		mesh.add_face(ids,corners,slot)
static func _branch(mesh: KiwiModelMesh, p: Dictionary, rng: RandomNumberGenerator, graph: Array[Dictionary], leaves: Array[Dictionary], id: String, parent: String, origin: Vector3, direction: Vector3, length: float, radius: float, level: int, name: String) -> void:
	if _stop(mesh,p): return
	# Independent path streams keep edits to one limb from changing its siblings.
	rng=RandomNumberGenerator.new(); rng.seed=hash([p.seed,id])
	var override: Dictionary=p.get("branch_overrides",{}).get(id,{})
	if override.get("pruned",false): return
	direction=Basis.from_euler((override.get("rotation",Vector3.ZERO) as Vector3)*PI/180.)*direction
	length*=clampf(float(override.get("length",1.)),.05,3.); radius*=clampf(float(override.get("radius",1.)),.1,2.)
	var junction:=_junction(mesh,graph,parent,origin,direction,length)
	if not junction.is_empty(): origin=junction.point+direction*radius*.3
	var path:=PackedVector3Array(); var radii:=PackedFloat32Array(); var steps:=8; var sideways:=direction.cross(Vector3.UP).normalized()
	for i in steps+1:
		var t:=float(i)/steps; var bend: float=float(p.curve)*length*sin(t*PI*.5)
		path.append(origin+direction*length*t+sideways*bend+Vector3.UP*(length*.22*sin(t*PI)-float(p.droop)*length*t*t))
		radii.append(maxf(.001,radius*(1.-float(p.taper)*t)))
	var topology:=_tube(mesh,path,radii,int(p.segments)); _stitch(mesh,junction,topology,(path[1]-path[0]).normalized())
	graph.append({"id":id,"parent":parent,"points":path,"radii":radii,"level":level,"topology":topology,"joined":not junction.is_empty()})
	if level<int(p.levels):
		var count:=maxi(2,int(p.branches)/int(pow(2,level+1)))
		for j in count:
			if _stop(mesh,p): return
			var index:=clampi(3+int(float(j)/count*5.),1,7); var angle:=TAU*j/count+rng.randf_range(-.3,.3)
			var d: Vector3=(direction*.35+Vector3(cos(angle),.4,sin(angle))*float(p.angle)).normalized()
			_branch(mesh,p,rng,graph,leaves,id+"/"+str(j),id,path[index],d,length*.58,radius*.4,level+1,name)
	elif float(p.foliage)>0.:
		var conifer:=name in ["Pine","Spruce","Fir"]
		for j in maxi(1,int((72. if conifer else 36.)*float(p.foliage))):
			if _stop(mesh,p): return
			var index:=clampi(2+j%7,1,8); var a:=j*2.39996; var d:=Vector3(cos(a),rng.randf_range(-.15,.55),sin(a)).normalized()
			var size: float=float(p.leaf_size)*rng.randf_range(.75,1.25)
			if conifer: size*=.8
			_leaf(mesh,path[index],d,size,.09 if conifer else (.12 if name=="Willow" else .45),1,1 if name=="Maple" else (2 if name=="Oak" else (3 if name=="Birch" else 0)))
			leaves.append({"branch":id,"t":float(index)/steps,"position":path[index]})
static func _tree(mesh: KiwiModelMesh, name: String, p: Dictionary, rng: RandomNumberGenerator, graph: Array[Dictionary], leaves: Array[Dictionary]) -> void:
	var height: float=p.height; var radius: float=p.radius
	var path:=PackedVector3Array(); var radii:=PackedFloat32Array()
	var fallen:=name in ["Log","Driftwood","Root"]; var stump:=name=="Stump"
	if stump: height*=.2
	for i in 17:
		var t:=i/16.; var phase:=float(p.seed)*.713; var lean:=Vector3(float(p.lean)*height*t*t,0.,sin(t*3.)*float(p.curve)*height*.15+(sin(t*6.+phase)-sin(phase))*height*.03*float(p.irregularity))
		path.append(Vector3(0.,height*t,0.)+lean if not fallen else Vector3(height*t,radius+(sin(t*3.+phase)-sin(phase))*radius*.12,(sin(t*4.+phase)-sin(phase))*height*float(p.curve)*.4))
		radii.append(radius*(1.-float(p.taper)*t)* (1.+.7*pow(1.-t,8.)))
	var topology:=_tube(mesh,path,radii,int(p.segments)); graph.append({"id":"trunk","parent":"","points":path,"radii":radii,"level":0,"topology":topology})
	if fallen or stump: return
	for root in int(p.roots):
		var angle:=TAU*root/maxi(1,int(p.roots)); var d:=Vector3(cos(angle),0.,sin(angle)); var reach:=radius*(6. if name=="Mangrove" else 3.)
		var points:=PackedVector3Array([path[1],d*reach*.45+Vector3.UP*radius*.3,d*reach+Vector3.DOWN*radius*.5]); var direction: Vector3=(points[1]-points[0]).normalized(); var junction:=_junction(mesh,graph,"trunk",points[0],direction,reach)
		if not junction.is_empty(): points[0]=junction.point+direction*radius*.1
		var root_topology:=_tube(mesh,points,PackedFloat32Array([radius*.8,radius*.35,.005]),int(p.segments)); _stitch(mesh,junction,root_topology,(points[1]-points[0]).normalized())
	for j in int(p.branches):
		if _stop(mesh,p): return
		var conifer:=name in ["Pine","Spruce","Fir"]; var palm:=name=="Palm"; var acacia:=name=="Acacia"
		var t:=.2+.7*float(j/3)/maxi(1,ceili(float(p.branches)/3.)-1) if conifer else rng.randf_range(.4,.88)
		if palm: t=.95
		if acacia: t=.7+rng.randf()*.15
		var index:=clampi(roundi(t*16.),1,16); var angle:=j*2.39996+rng.randf_range(-.2,.2)
		var direction:=Vector3(cos(angle)*float(p.angle),.1 if palm or acacia else .6,sin(angle)*float(p.angle)).normalized()
		var length: float=height*float(p.length)*((1.-t)*1.5 if conifer else rng.randf_range(.65,1.))
		var q:=p.duplicate(); q.levels=0 if palm else p.levels
		if palm: q.droop=.5; q.foliage=0.
		if acacia: q.droop=0.; q.curve=.1
		_branch(mesh,q,rng,graph,leaves,"b"+str(j),"trunk",path[index],direction,length,radius*.32,0,name)
		if palm and graph[-1].id=="b"+str(j):
			var frond: Dictionary=graph[-1]; var points: PackedVector3Array=frond.points
			for k in range(1,8):
				var tangent: Vector3=(points[k+1]-points[k-1]).normalized(); var side:=tangent.cross(Vector3.UP).normalized()
				for sign in [-1.,1.]:
					_leaf(mesh,points[k],side*sign+tangent*.4+Vector3.DOWN*.2,length*.3*sin(PI*k/9.),.07)
					leaves.append({"branch":frond.id,"t":k/8.,"position":points[k]})
static func _plant(mesh: KiwiModelMesh, name: String, p: Dictionary, rng: RandomNumberGenerator, graph: Array[Dictionary], leaves: Array[Dictionary]) -> void:
	if name=="Cactus": _cactus(mesh,p,graph); return
	if name=="Vine" and (p.get("growth_path",PackedVector3Array()) as PackedVector3Array).size()>=2:
		_vine(mesh,p,graph,leaves); return
	if name=="Bush":
		var q:=p.duplicate(); q.height=float(p.height)*.8; q.radius=float(p.radius)*.12; q.levels=1; q.leaf_size=float(p.height)*.15; q.branches=12; _tree(mesh,"Oak",q,rng,graph,leaves); return
	for j in int(p.branches):
		if _stop(mesh,p): return
		var angle:=j*2.39996; var d:=Vector3(cos(angle),0.,sin(angle)); var origin:=d*rng.randf()*float(p.radius)*.4; var h: float=float(p.height)*rng.randf_range(.6,1.)
		var path:=PackedVector3Array([origin,origin+Vector3.UP*h*.5+d*h*.1,origin+Vector3.UP*h+d*h*.25]); var radii:=PackedFloat32Array([h*.015,h*.009,.001])
		if name=="Grass": _blade(mesh,origin,d,h,float(p.curve)); continue
		if name=="Succulent": _leaf(mesh,origin,(Vector3.UP+d*.4),h,.17); continue
		if name=="Vine": path=PackedVector3Array([origin,origin+Vector3.UP*h*.3+d*h*.2,origin+Vector3.UP*h*.7-d*h*.2,origin+Vector3.UP*h]); radii=PackedFloat32Array([h*.012,h*.01,h*.008,.002])
		_tube(mesh,path,radii,6)
		if name=="Mushroom":
			var q:=p.duplicate(); q.radius=h*.35; q.height=h*.25
			var cap:=KiwiModelMesh.new(); _rock(cap,"Mushroom",q,rng)
			var offset:=mesh.vertices.size()
			for point in cap.vertices: mesh.vertices.append(point+path[-1])
			for face in cap.faces:
				var ids:=PackedInt32Array()
				for v in face: ids.append(v+offset)
				mesh.add_face(ids,PackedVector2Array(),1)
		elif name=="Flower":
			for petal in 7: _leaf(mesh,path[-1],Vector3(cos(TAU*petal/7.),.1,sin(TAU*petal/7.)),h*.23,.6,2)
		elif name!="Reed":
			for k in 12:
				var t:=float(k+1)/13.; var center:=path[0].lerp(path[-1],t); var width:=sin(t*PI)*h*.3
				for sign in [-1.,1.]: _leaf(mesh,center,(d*sign+Vector3.UP*.2),width,.13 if name=="Fern" else .4)
static func _blade(mesh: KiwiModelMesh,origin: Vector3,direction: Vector3,height: float,curve: float) -> void:
	var start:=mesh.vertices.size(); var width:=height*.025; var side:=direction.cross(Vector3.UP).normalized()
	for i in 7:
		var t:=i/6.; var center:=origin+Vector3.UP*height*t+direction*height*(.08*t+curve*t*t); var w:=maxf(.00005,sin(PI*(t*.9+.05))*width*(1.-t*.9))
		mesh.vertices.append(center-side*w); mesh.vertices.append(center+side*w)
		if i>0:
			var a:=start+(i-1)*2; mesh.add_face(PackedInt32Array([a,a+1,a+3,a+2]),PackedVector2Array([Vector2(0,(i-1)/6.),Vector2(1,(i-1)/6.),Vector2(1,t),Vector2(0,t)]),1)
static func _cactus(mesh: KiwiModelMesh,p: Dictionary,graph: Array[Dictionary]) -> void:
	var h: float=p.height; var r: float=float(p.radius)*.35; var path:=PackedVector3Array(); var radii:=PackedFloat32Array()
	for i in 13: path.append(Vector3.UP*h*i/12.); radii.append(maxf(.002,r*sqrt(maxf(.001,1.-pow(float(i)/12.,8.)))))
	var topology:=_tube(mesh,path,radii,12); graph.append({"id":"trunk","parent":"","points":path,"radii":radii,"level":0,"topology":topology})
	for index in mini(5,int(p.branches)):
		var a:=index*2.39996+float(p.seed)*.713; var d:=Vector3(cos(a),0.,sin(a)); var origin:=path[3+index%6]; var junction:=_junction(mesh,graph,"trunk",origin,d,r*4.)
		if not junction.is_empty(): origin=junction.point+d*r*.1
		var arm:=PackedVector3Array([origin,origin+d*h*.2,origin+d*h*.3+Vector3.UP*h*.1,origin+d*h*.3+Vector3.UP*h*.4]); var tube:=_tube(mesh,arm,PackedFloat32Array([r*.65,r*.65,r*.55,.002]),10); _stitch(mesh,junction,tube,(arm[1]-arm[0]).normalized())
	for ring in 13:
		for index in 12:
			var at:=ring*12+index; var point:=mesh.vertices[at]; var scale:=1.+.12*cos(TAU*index/12.*6.); point.x*=scale; point.z*=scale; mesh.vertices[at]=point
static func _rock(mesh: KiwiModelMesh, name: String, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var sides:=int(p.detail); var rings:=maxi(4,sides/2); var noise:=FastNoiseLite.new(); noise.seed=int(p.seed); noise.frequency=2.3
	var h: float=p.height; var radius: float=p.radius; var phase:=rng.randf()*TAU
	# No duplicated pole positions or zero-area pole faces.
	mesh.vertices.append(Vector3(0.,h,0.))
	for i in range(1,rings):
		if _stop(mesh,p): return
		var phi:=PI*i/rings
		for j in sides:
			var a:=TAU*j/sides; var direction:=Vector3(sin(phi)*cos(a),cos(phi),sin(phi)*sin(a)); var n:=noise.get_noise_3dv(direction*2.)
			var r:=1.+n*float(p.irregularity)
			var point:=direction*Vector3(radius,h,radius)*r
			if name in ["Sandstone","Slate","Limestone"]:
				var frequency:=7. if name=="Limestone" else (16. if name=="Slate" else 12.)
				point.x+=sin(point.y*frequency+phase)*radius*.12; point.z+=sin(point.y*(frequency-.7))*radius*.1
			if name=="Slate": point.y*=.23
			if name=="Basalt": point.y*=1.6; point.x=snappedf(point.x,radius*.15); point.z=snappedf(point.z,radius*.15)
			if name=="River stone": point.y*=.55
			if name=="Volcanic": point*=1.+absf(n)*.7
			if name=="Mushroom": point.y=maxf(-h*.12,point.y)
			if name in ["Stalactite","Stalagmite"]:
				var t:=1.-float(i)/rings; point=Vector3(cos(a)*radius*(1.-t)*r,h*t,sin(a)*radius*(1.-t)*r)
			mesh.vertices.append(point)
	var bottom:=mesh.vertices.size(); mesh.vertices.append(Vector3.ZERO if name in ["Stalactite","Stalagmite"] else Vector3(0.,-h*.12 if name=="Mushroom" else -h,0.))
	for j in sides:
		mesh.add_face(PackedInt32Array([0,1+j,1+(j+1)%sides]))
		for i in rings-2:
			var a:=1+i*sides+j; var b:=1+i*sides+(j+1)%sides; mesh.add_face(PackedInt32Array([a,a+sides,b+sides,b]))
		mesh.add_face(PackedInt32Array([bottom,1+(rings-2)*sides+(j+1)%sides,1+(rings-2)*sides+j]))
static func _vine(mesh: KiwiModelMesh,p: Dictionary,graph: Array[Dictionary],leaves: Array[Dictionary]) -> void:
	var path: PackedVector3Array=p.growth_path.duplicate(); var source:=p.get("growth_surface") as KiwiModelMesh; var triangles: Array=[]
	if path.size()>256 or (source!=null and source.faces.size()>50000): p._error="Vine attachment budget exceeded. Use up to 256 path points and a simpler surface model."; return
	if source!=null:
		for f in source.faces.size():
			var indices:=source.triangles(f)
			for i in range(0,indices.size(),3): triangles.append([source.vertices[source.faces[f][indices[i]]],source.vertices[source.faces[f][indices[i+1]]],source.vertices[source.faces[f][indices[i+2]]]])
	for index in path.size():
		if _stop(mesh,p): return
		var nearest:=INF; var hit:=path[index]
		for triangle: Array in triangles:
			var point:=_triangle_point(path[index],triangle[0],triangle[1],triangle[2]); var distance:=point.distance_squared_to(path[index])
			if distance<nearest: nearest=distance; hit=point+(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()*.015
		path[index]=hit
	var cleaned:=PackedVector3Array()
	for point in path:
		if cleaned.is_empty() or cleaned[-1].distance_squared_to(point)>.000001: cleaned.append(point)
	path=cleaned
	if path.size()<2: p._error="The vine needs two different attachment points."; return
	var radii:=PackedFloat32Array(); radii.resize(path.size()); radii.fill(float(p.radius)*.04); var topology:=_tube(mesh,path,radii,6); graph.append({"id":"vine","parent":"","points":path,"radii":radii,"level":0,"topology":topology})
	for segment in path.size()-1:
		for index in int(p.branches):
			var t: float=(index+.5)/int(p.branches); var point:=path[segment].lerp(path[segment+1],t); var tangent: Vector3=(path[segment+1]-path[segment]).normalized(); var side:=tangent.cross(Vector3.FORWARD if absf(tangent.z)<.9 else Vector3.UP).normalized()
			_leaf(mesh,point,side*(-1. if index%2 else 1.)+tangent*.2,float(p.leaf_size),.45); leaves.append({"branch":"vine","t":float(segment)+t,"position":point})
static func _triangle_point(p: Vector3,a: Vector3,b: Vector3,c: Vector3) -> Vector3:
	var ab:=b-a; var ac:=c-a; var ap:=p-a; var d1:=ab.dot(ap); var d2:=ac.dot(ap)
	if d1<=0. and d2<=0.: return a
	var bp:=p-b; var d3:=ab.dot(bp); var d4:=ac.dot(bp)
	if d3>=0. and d4<=d3: return b
	var vc:=d1*d4-d3*d2
	if vc<=0. and d1>=0. and d3<=0.: return a+ab*(d1/maxf(.000000001,d1-d3))
	var cp:=p-c; var d5:=ab.dot(cp); var d6:=ac.dot(cp)
	if d6>=0. and d5<=d6: return c
	var vb:=d5*d2-d1*d6
	if vb<=0. and d2>=0. and d6<=0.: return a+ac*(d2/maxf(.000000001,d2-d6))
	var va:=d3*d6-d5*d4
	if va<=0. and d4-d3>=0. and d5-d6>=0.: return b+(c-b)*((d4-d3)/maxf(.000000001,d4-d3+d5-d6))
	var denominator:=maxf(.000000001,va+vb+vc); return a+ab*(vb/denominator)+ac*(vc/denominator)
static func _stop(mesh: KiwiModelMesh,p: Dictionary) -> bool:
	var cancel: Callable=p.get("_cancel",Callable())
	return mesh.vertices.size()>MAX_VERTICES or (cancel.is_valid() and cancel.call())
static func materials(kind: String,settings: Dictionary={}) -> Array[Material]:
	var engine=preload("res://scripts/materials/natural_material_engine.gd")
	var bark: Material=engine.create_spatial_material(engine.defaults("wood/tree_bark"))
	if kind.begins_with("Rock"):
		var name:=kind.get_slice(" / ",1).to_lower().replace(" ","_")
		name="granite" if name not in ["granite","limestone","sandstone","slate"] else name
		var rock_settings: Dictionary=engine.defaults("stone/"+name); rock_settings.mapping="triplanar"; bark=engine.create_spatial_material(rock_settings)
	var leaf:=StandardMaterial3D.new(); leaf.albedo_color=Color(.14,.38,.055); leaf.cull_mode=BaseMaterial3D.CULL_DISABLED; leaf.roughness=.85; leaf.backlight_enabled=true; leaf.backlight=Color(.25,.5,.1)
	if kind.begins_with("Plant") and kind!="Plant / Bush":
		var stem:=StandardMaterial3D.new(); stem.albedo_color=Color(.14,.3,.06); stem.roughness=.8; bark=stem
		if kind=="Plant / Mushroom": stem.albedo_color=Color(.75,.67,.5); leaf.albedo_color=Color(.55,.18,.035)
	var flower:=StandardMaterial3D.new(); flower.albedo_color=Color(.9,.22,.45); flower.cull_mode=BaseMaterial3D.CULL_DISABLED
	var foliage:=ShaderMaterial.new(); foliage.shader=preload("res://Workspaces/ModelWorkspace/natural_leaf.gdshader"); foliage.set_shader_parameter("leaf_color",leaf.albedo_color)
	foliage.set_meta("kiwi_natural_foliage",true)
	var season:=clampi(int(settings.get("season",0)),0,3)
	if season>0: foliage.set_shader_parameter("leaf_color",[leaf.albedo_color,Color(.45,.65,.12),Color(.72,.22,.025),Color(.52,.43,.24)][season])
	foliage.set_shader_parameter("wind_strength",clampf(float(settings.get("wind_strength",0.)),0.,1.))
	return [bark,foliage,flower]
