extends RefCounted
const MeshCache=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_mesh_cache.gd")
## CPU polygon generation: openings are absent solid geometry, including colliders.
static func generate(source: Resource,cancel: Callable=Callable()) -> Dictionary:
	var errors: PackedStringArray=source.validate(); var document:=KiwiModelDocument.new(); var warnings:=PackedStringArray()
	if not errors.is_empty(): return {"document":null,"errors":errors,"warnings":warnings}
	var root:=_item(document,source.source_id,source.title,"",null,Transform3D.IDENTITY,source,0,"building"); root.parameters.architecture_source=source
	for floor: Dictionary in source.floors:
		if cancel.is_valid() and cancel.call(): return {"document":null,"errors":PackedStringArray(),"warnings":warnings,"cancelled":true}
		var footprint: PackedVector2Array=floor.get("footprint",source.footprint)
		var parent: String=source.source_id+":"+str(floor.id); var level:=_item(document,parent,str(floor.get("name","Level")),root.id,null,Transform3D(Basis.IDENTITY,Vector3.UP*float(floor.get("elevation",0.))),source,0,"level")
		var cuts:=_floor_cuts(source,floor); var slab:=_cached_slab(footprint,cuts,float(source.slab_thickness)); var slab_node:=_item(document,parent+":slab","Floor slab",level.id,slab,Transform3D(Basis.IDENTITY,Vector3.DOWN*float(source.slab_thickness)*.5),source,1,"slab")
		slab_node.structural[&"structure_role"]=1 if float(floor.get("elevation",0.))==0. else 0
		for room: Dictionary in floor.get("rooms",[]):
			var node:=_item(document,parent+":room:"+str(room.id),str(room.get("name","Room")),level.id,null,Transform3D.IDENTITY,source,0,"room"); node.parameters.polygon=room.get("polygon",source.footprint)
		var seen: Dictionary={}
		for wall: Dictionary in floor.get("walls",[]):
			if cancel.is_valid() and cancel.call(): return {"document":null,"errors":PackedStringArray(),"warnings":warnings,"cancelled":true}
			var a: Vector2=wall.a; var b: Vector2=wall.b; var edge:=str(a)+":"+str(b); var reverse:=str(b)+":"+str(a)
			if seen.has(edge) or seen.has(reverse): continue
			seen[edge]=true; var direction:=b-a; var length:=direction.length(); var height:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").wall_height(source,floor,wall); var pose:=Transform3D(Basis(Vector3.UP,-atan2(direction.y,direction.x)),Vector3(a.x,0.,a.y))
			var mesh:=MeshCache.mesh("wall",[length,height,source.wall_thickness,wall.get("openings",[])],func(): return wall_mesh(length,height,float(source.wall_thickness),wall.get("openings",[]))); var node:=_item(document,parent+":wall:"+str(wall.id),str(wall.get("name","Wall")),level.id,mesh,pose,source,0,"wall")
			_wall_finishes(node,source,floor,wall)
			_interior_trim(document,node,source,floor,wall,length,height)
			node.structural[&"structure_connections"]={"slab":KiwiStructure.connection(slab_node.id,Vector3.ZERO,pose.origin+Vector3.UP*float(source.slab_thickness)*.5)}
			for opening: Dictionary in wall.get("openings",[]): _opening(document,node,opening,length,source)
			var facade:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").facade(source,floor,wall)
			if not facade.faces.is_empty(): _item(document,node.id+":facade","Facade details",node.id,facade,Transform3D.IDENTITY,source,3,"facade")
		var ceiling_cuts:=cuts.duplicate()
		for stair: Dictionary in source.stairs:
			if _stair_crosses(source,stair,float(floor.elevation)+float(floor.get("height",3.))): ceiling_cuts.append(_stair_bounds(stair))
		var ceiling_top:=float(floor.get("height",3.))
		for other: Dictionary in source.floors:
			if is_equal_approx(float(other.elevation),float(floor.elevation)+ceiling_top): ceiling_top-=float(source.slab_thickness); break
		var ceiling:=_cached_slab(footprint,ceiling_cuts,.01); _item(document,parent+":ceiling","Ceiling",level.id,ceiling,Transform3D(Basis.IDENTITY,Vector3.UP*(ceiling_top-.005)),source,6,"ceiling")
	_build_stairs(document,source,warnings)
	if cancel.is_valid() and cancel.call(): return {"document":null,"errors":PackedStringArray(),"warnings":warnings,"cancelled":true}
	var last: Dictionary=source.floors[-1]; var top:=float(last.get("elevation",0.))+float(last.get("height",3.)); var roof_source: Resource=source
	if last.has("footprint"): roof_source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").copy(source); roof_source.footprint=last.footprint
	var roof:=roof_mesh(roof_source,warnings)
	if roof!=null: _item(document,source.source_id+":roof","Roof",root.id,roof,Transform3D(Basis.IDENTITY,Vector3.UP*top),source,2,"roof")
	_build_supports(document,source)
	var navigation:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd").connectivity(source)
	root.parameters.architecture_navigation=navigation; warnings.append_array(navigation.warnings)
	return {"document":document,"errors":document.validate(),"warnings":warnings}
static func _cached_slab(footprint: PackedVector2Array,cuts: Array,thickness: float) -> KiwiModelMesh:
	return MeshCache.mesh("slab",[footprint,cuts,thickness],func(): return _slab(footprint,cuts,thickness))
static func _item(document: KiwiModelDocument,id: String,title: String,parent: String,mesh: KiwiModelMesh,pose: Transform3D,source: Resource,material: int,type: String) -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=id; item.title=title; item.parent_id=parent; item.mesh=mesh; item.transform=pose; item.parameters={"architecture_type":type,"architecture_owner":source.source_id,"architecture_key":id.trim_prefix(str(source.source_id)),"architecture_material_slot":material}
	item.parameters._architecture_generated_mesh=mesh_key(mesh); item.parameters._architecture_mesh_format=2
	item.parameters._architecture_generated_name=title
	if mesh!=null:
		var fallback: int=1 if material==6 else (0 if material==5 else material)
		if material<source.materials.size(): item.surface_materials=[source.materials[material]]
		elif fallback<source.materials.size(): item.surface_materials=[source.materials[fallback]]
	item.structural={&"structure_enabled":source.physics_enabled and mesh!=null and type in ["wall","slab","roof","door","stair treads","landing","railing","foundation"],&"structure_role":0,&"structure_assembly":source.source_id}; document.components.append(item); return item
static func mesh_key(mesh: KiwiModelMesh,format: int=2) -> int:
	if mesh==null: return 0
	return hash([mesh.vertices,mesh.faces,mesh.uv,mesh.materials]) if format>=2 else hash([mesh.vertices,mesh.faces])
static func _interior_trim(document: KiwiModelDocument,wall_node: KiwiModelComponent,source: Resource,floor: Dictionary,wall: Dictionary,length: float,height: float) -> void:
	if source.baseboard_height<=0. and source.crown_height<=0.: return
	var a: Vector2=wall.a; var b: Vector2=wall.b; var direction: Vector2=(b-a).normalized(); var normal:=Vector2(-direction.y,direction.x); var polygon: PackedVector2Array=floor.get("footprint",source.footprint)
	for spec in [["baseboard",float(source.baseboard_height),0.],["crown",float(source.crown_height),height-float(source.crown_height)]]:
		var trim_height: float=spec[1]; var bottom: float=spec[2]
		if trim_height<=0. or trim_height>height: continue
		var cuts: Array=[]
		for opening: Dictionary in wall.get("openings",[]):
			var center:=float(opening.get("t",.5))*length; var half:=float(opening.get("width",1.))*.5
			if float(opening.get("bottom",0.))<bottom+trim_height and float(opening.get("bottom",0.))+float(opening.get("height",2.))>bottom: cuts.append(Vector2(maxf(0.,center-half),minf(length,center+half)))
		cuts.sort_custom(func(left: Vector2,right: Vector2): return left.x<right.x)
		var spans: Array=[]; var cursor:=0.
		for cut: Vector2 in cuts:
			if cut.x>cursor: spans.append(Vector2(cursor,cut.x))
			cursor=maxf(cursor,cut.y)
		if cursor<length: spans.append(Vector2(cursor,length))
		var mesh:=KiwiModelMesh.new()
		for side in [-1.,1.]:
			if not Geometry2D.is_point_in_polygon((a+b)*.5+normal*.05*side,polygon): continue
			for span: Vector2 in spans:
				var center:=Vector3((span.x+span.y)*.5,bottom+trim_height*.5,side*(float(source.wall_thickness)+float(source.interior_trim_depth))*.5)
				mesh.append_mesh(KiwiModelPrimitives.box(Vector3(span.y-span.x,trim_height,float(source.interior_trim_depth))),Transform3D(Basis.IDENTITY,center))
		if not mesh.faces.is_empty(): _item(document,wall_node.id+":"+str(spec[0]),str(spec[0]).capitalize(),wall_node.id,mesh,Transform3D.IDENTITY,source,3,"interior trim")
static func _wall_finishes(item: KiwiModelComponent,source: Resource,floor: Dictionary,wall: Dictionary) -> void:
	var a: Vector2=wall.a; var b: Vector2=wall.b; var direction: Vector2=(b-a).normalized(); var normal:=Vector2(-direction.y,direction.x); var polygon: PackedVector2Array=floor.get("footprint",source.footprint)
	var plus:=Geometry2D.is_point_in_polygon((a+b)*.5+normal*.05,polygon); var minus:=Geometry2D.is_point_in_polygon((a+b)*.5-normal*.05,polygon); var interior: Material=source.materials[5] if source.materials.size()>5 else (source.materials[0] if not source.materials.is_empty() else null)
	if plus and minus:
		item.parameters.architecture_material_slot=5; item.surface_materials.assign([interior])
	elif plus!=minus:
		var exterior: Material=source.materials[0] if not source.materials.is_empty() else null; item.surface_materials.assign([exterior,interior]); item.parameters.architecture_material_slots=PackedInt32Array([0,5]); var sign: float=1. if plus else -1.
		for face in item.mesh.faces.size(): item.mesh.materials[face]=1 if item.mesh.normal(face).z*sign>.5 else 0
	item.parameters._architecture_generated_mesh=mesh_key(item.mesh)
static func wall_mesh(length: float,height: float,thickness: float,openings: Array) -> KiwiModelMesh:
	var mesh:=KiwiModelMesh.new(); var xs: Array[float]=[0.,length]
	for opening: Dictionary in openings:
		var width:=float(opening.get("width",1.)); var center:=float(opening.get("t",.5))*length
		for step in (13 if opening.get("type","")=="arch" else 2): xs.append(center-width*.5+width*step/(12. if opening.get("type","")=="arch" else 1.))
	xs.sort(); var unique: Array[float]=[]
	for x in xs:
		if unique.is_empty() or absf(unique[-1]-x)>.00001: unique.append(x)
	for index in unique.size()-1:
		var left:=unique[index]; var right:=unique[index+1]; var middle: float=(left+right)*.5; var intervals: Array=[]
		for opening: Dictionary in openings:
			var center:=float(opening.get("t",.5))*length; var width:=float(opening.get("width",1.))
			if absf(middle-center)>width*.5+.00001: continue
			intervals.append({"bottom":float(opening.get("bottom",0.)),"top":Vector2(_opening_top(opening,left,length),_opening_top(opening,right,length))})
		intervals.sort_custom(func(a: Dictionary,b: Dictionary): return a.bottom<b.bottom); var bottom:=Vector2.ZERO
		for hole: Dictionary in intervals:
			if hole.bottom>maxf(bottom.x,bottom.y)+.00001: _panel(mesh,left,right,bottom,Vector2.ONE*hole.bottom,thickness)
			bottom=bottom.max(hole.top)
		if minf(bottom.x,bottom.y)<height-.00001: _panel(mesh,left,right,bottom,Vector2.ONE*height,thickness)
	return mesh

static func _floor_cuts(source: Resource,floor: Dictionary) -> Array:
	var cuts: Array=floor.get("cuts",[]).duplicate()
	for stair: Dictionary in source.stairs:
		if _stair_crosses(source,stair,float(floor.elevation)): cuts.append(_stair_bounds(stair))
	return cuts
static func _stair_crosses(source: Resource,stair: Dictionary,elevation: float) -> bool:
	var low:=INF; var high:=-INF
	for floor: Dictionary in source.floors:
		if str(floor.id)==str(stair.get("from","")): low=float(floor.elevation)
		if str(floor.id)==str(stair.get("to","")): high=float(floor.elevation)
	return high>low and elevation>low+.001 and elevation<=high+.001
static func _stair_bounds(stair: Dictionary) -> Rect2:
	var width:=maxf(.3,float(stair.get("width",1.))); var length:=maxf(.5,float(stair.get("length",4.))); var type:=int(stair.get("type",0)); var bounds:=Rect2(-width*.5,-.05,width,length+.1)
	if type==1: bounds=Rect2(-width*.5,-.05,length*.5+width,length*.5+width+.1)
	if type==2: bounds=Rect2(-width*.5,-.05,width*3.,length*.5+width+.1)
	if type==3: bounds=Rect2(-Vector2.ONE*width*1.4,Vector2.ONE*width*2.8)
	var position: Vector2=stair.get("position",Vector2.ZERO); var angle:=deg_to_rad(float(stair.get("yaw",0.))); var result:=Rect2(); var first:=true
	for corner in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		var point: Vector2=(corner as Vector2).rotated(-angle)+position
		result=Rect2(point,Vector2.ZERO) if first else result.expand(point); first=false
	return result
static func _build_stairs(document: KiwiModelDocument,source: Resource,warnings: PackedStringArray) -> void:
	for stair: Dictionary in source.stairs:
		var from: Dictionary={}; var to: Dictionary={}
		for floor: Dictionary in source.floors:
			if str(floor.id)==str(stair.get("from","")): from=floor
			if str(floor.id)==str(stair.get("to","")): to=floor
		if from.is_empty() or to.is_empty(): warnings.append("A staircase references a missing level."); continue
		var height:=float(to.elevation)-float(from.elevation); var width:=maxf(.3,float(stair.get("width",1.))); var length:=maxf(.5,float(stair.get("length",4.))); var steps:=clampi(int(stair.get("steps",ceili(height/.18))),2,80); var type:=clampi(int(stair.get("type",0)),0,3)
		if height<=0.: warnings.append("A staircase must rise to a higher level."); continue
		if height/length>.8 and type!=3: warnings.append("This staircase is steep. Increase its run for easier access.")
		if height/steps>.22: warnings.append("Stair risers exceed 0.22 m; add steps for easier access.")
		if width<.8: warnings.append("This staircase is narrower than 0.8 m.")
		if type==3 and height/maxf(.5,float(stair.get("turns",1.)))<2.1: warnings.append("Spiral stair headroom is below 2.1 m per turn; reduce turns or increase the rise.")
		if type!=3 and length/steps<.22: warnings.append("Stair treads are shallower than 0.22 m; increase the run or reduce steps.")
		var position: Vector2=stair.get("position",Vector2.ZERO); var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(stair.get("yaw",0.)))),Vector3(position.x,float(from.elevation),position.y)); var id: String=source.source_id+":stairs:"+str(stair.get("id","stairs")); var parent:=_item(document,id,"Staircase",source.source_id,null,pose,source,3,"stairs")
		var mesh:=KiwiModelMesh.new(); var rails:=KiwiModelMesh.new(); var landings:=KiwiModelMesh.new()
		if type==3:
			var radius:=width*1.3; var inner:=width*.2; var turns:=maxf(.5,float(stair.get("turns",1.))); var previous:=Vector3.ZERO
			for step in steps:
				var a:=TAU*turns*step/steps; var b:=TAU*turns*(step+1)/steps; var y:=height*(step+1)/steps; var profile:=PackedVector2Array([Vector2(cos(a),sin(a))*inner,Vector2(cos(a),sin(a))*radius,Vector2(cos(b),sin(b))*radius,Vector2(cos(b),sin(b))*inner]); mesh.append_mesh(KiwiModelPrimitives.prism(profile,.1),Transform3D(Basis.IDENTITY,Vector3.UP*(y-.05)))
				var point:=Vector3(cos(b)*radius,y,sin(b)*radius); _post(rails,point)
				if step>0: _beam(rails,previous+Vector3.UP,point+Vector3.UP,.05)
				previous=point
			mesh.append_mesh(KiwiModelPrimitives.create("Cylinder",{"radius":.12,"height":height,"segments":12}),Transform3D(Basis.IDENTITY,Vector3.UP*height*.5))
		else:
			var flights: Array=[]
			if type==0: flights=[{"a":Vector2.ZERO,"b":Vector2(0,length),"low":0.,"high":height}]
			elif type==1:
				flights=[{"a":Vector2.ZERO,"b":Vector2(0,length*.5),"low":0.,"high":height*.5},{"a":Vector2(width*.5,length*.5+width*.5),"b":Vector2(length*.5+width*.5,length*.5+width*.5),"low":height*.5,"high":height}]; landings.append_mesh(KiwiModelPrimitives.box(Vector3(width,height*.5,width)),Transform3D(Basis.IDENTITY,Vector3(0,height*.25,length*.5+width*.5)))
			else:
				flights=[{"a":Vector2.ZERO,"b":Vector2(0,length*.5),"low":0.,"high":height*.5},{"a":Vector2(width*2.,length*.5),"b":Vector2(width*2.,0),"low":height*.5,"high":height}]; landings.append_mesh(KiwiModelPrimitives.box(Vector3(width*3.,height*.5,width)),Transform3D(Basis.IDENTITY,Vector3(width,height*.25,length*.5+width*.5)))
			for flight: Dictionary in flights:
				var a: Vector2=flight.a; var b: Vector2=flight.b; var delta:=b-a; var count:=maxi(2,ceili(float(steps)/flights.size())); var direction:=delta.normalized(); var basis:=Basis(Vector3.UP,-atan2(direction.y,direction.x)+PI*.5); var previous: Array[Vector3]=[]
				for step in count:
					var t: float=(step+.5)/count; var p:=a.lerp(b,t); var y:=lerpf(flight.low,flight.high,float(step+1)/count); var center:=Vector3(p.x,y*.5,p.y); mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width,y,delta.length()/count+.002)),Transform3D(basis,center))
					var current: Array[Vector3]=[]
					for sign in [-1.,1.]:
						var point: Vector3=Vector3(p.x,y,p.y)+basis.x*width*.48*sign; current.append(point); _post(rails,point)
						if not previous.is_empty(): _beam(rails,previous[current.size()-1]+Vector3.UP,point+Vector3.UP,.05)
					previous=current
		landings.append_mesh(_upper_landing(stair,height))
		var treads:=_item(document,id+":treads","Steps",parent.id,mesh,Transform3D.IDENTITY,source,3,"stair treads"); var floor_slab:=document.component(str(source.source_id)+":"+str(from.id)+":slab")
		if floor_slab!=null: _connect_support(document,treads,floor_slab,document.world_transform(treads).origin,"base")
		if not landings.faces.is_empty():
			var landing:=_item(document,id+":landings","Landing",parent.id,landings,Transform3D.IDENTITY,source,1,"landing"); _connect_support(document,landing,treads,document.world_transform(treads).origin,"steps")
			var upper_slab:=document.component(str(source.source_id)+":"+str(to.id)+":slab")
			if upper_slab!=null: _connect_support(document,landing,upper_slab,document.world_transform(landing)*Vector3(0,height,0),"upper floor")
		if bool(stair.get("railings",true)):
			var railing:=_item(document,id+":rails","Railings",parent.id,rails,Transform3D.IDENTITY,source,3,"railing"); _connect_support(document,railing,treads,document.world_transform(treads).origin,"steps")
static func _upper_landing(stair: Dictionary,height: float) -> KiwiModelMesh:
	var width:=maxf(.3,float(stair.get("width",1.))); var kind:=int(stair.get("type",0)); var length:=maxf(.5,float(stair.get("length",4.))); var end:=Vector2(0,length); var direction:=Vector2.DOWN
	if kind==1: end=Vector2(length*.5+width*.5,length*.5+width*.5); direction=Vector2.RIGHT
	elif kind==2: end=Vector2(width*2.,0); direction=Vector2.UP
	elif kind==3:
		var angle:=TAU*maxf(.5,float(stair.get("turns",1.))); end=Vector2(cos(angle),sin(angle))*width*.75; direction=Vector2(-sin(angle),cos(angle))
	var yaw:=deg_to_rad(float(stair.get("yaw",0.))); var position: Vector2=stair.get("position",Vector2.ZERO); var start:=end-direction*.08; var world:=start.rotated(-yaw)+position; var forward:=direction.rotated(-yaw); var bounds:=_stair_bounds(stair); var distance:=INF
	for axis in 2:
		if absf(forward[axis])<.00001: continue
		var edge: float=bounds.end[axis] if forward[axis]>0. else bounds.position[axis]; var travel: float=(edge-world[axis])/forward[axis]
		if travel>=0.: distance=minf(distance,travel)
	if not is_finite(distance): distance=.2
	var run:=maxf(.12,distance+.01); var center:=start+direction*run*.5; var basis:=Basis(Vector3.UP,-atan2(direction.y,direction.x)+PI*.5); var result:=KiwiModelMesh.new()
	result.append_mesh(KiwiModelPrimitives.box(Vector3(width,.1,run)),Transform3D(basis,Vector3(center.x,height-.05,center.y))); return result
static func _connect_support(document: KiwiModelDocument,item: KiwiModelComponent,target: KiwiModelComponent,point: Vector3,key: String) -> void:
	if not item.structural.has(&"structure_connections"): item.structural[&"structure_connections"]={}
	item.structural[&"structure_connections"][key]=KiwiStructure.connection(target.id,document.world_transform(item).affine_inverse()*point,document.world_transform(target).affine_inverse()*point)
static func _build_supports(document: KiwiModelDocument,source: Resource) -> void:
	if source.foundation_depth>0.:
		var first: Dictionary=source.floors[0]; var foundation:=_item(document,str(source.source_id)+":foundation","Foundation",source.source_id,_convex_slab(first.get("footprint",source.footprint),float(source.foundation_depth)),Transform3D(Basis.IDENTITY,Vector3.UP*(float(first.get("elevation",0.))-float(source.slab_thickness)-float(source.foundation_depth)*.5)),source,0,"foundation"); foundation.structural[&"structure_role"]=1
		var base:=document.component(str(source.source_id)+":"+str(first.id)+":slab")
		if base!=null: _connect_support(document,base,foundation,Vector3(0,float(first.get("elevation",0.))-float(source.slab_thickness),0),"foundation")
	for index in (source.floors as Array).size():
		var floor: Dictionary=source.floors[index]; var target: KiwiModelComponent=document.component(str(source.source_id)+":roof") if index==source.floors.size()-1 else document.component(str(source.source_id)+":"+str(source.floors[index+1].id)+":slab")
		if target==null: continue
		for wall: Dictionary in floor.walls:
			var part:=document.component(str(source.source_id)+":"+str(floor.id)+":wall:"+str(wall.id))
			if part==null or part.mesh==null: continue
			var bounds:=part.mesh.bounds(); var point: Vector3=document.world_transform(part)*Vector3(bounds.get_center().x,bounds.end.y,0.); _connect_support(document,target,part,point,str(wall.id))
static func _post(mesh: KiwiModelMesh,point: Vector3) -> void:
	mesh.append_mesh(KiwiModelPrimitives.create("Cylinder",{"radius":.025,"height":1.,"segments":6}),Transform3D(Basis.IDENTITY,point+Vector3.UP*.5))
static func _beam(mesh: KiwiModelMesh,a: Vector3,b: Vector3,width: float) -> void:
	var direction:=b-a
	if direction.length()<.0001: return
	mesh.append_mesh(KiwiModelPrimitives.box(Vector3(width,width,direction.length())),Transform3D(Basis.looking_at(-direction.normalized(),Vector3.UP),(a+b)*.5))
static func _opening_top(opening: Dictionary,x: float,length: float) -> float:
	var top:=float(opening.get("bottom",0.))+float(opening.get("height",2.))
	if opening.get("type","")!="arch": return top
	var width:=float(opening.get("width",1.)); var rise:=minf(width*.5,float(opening.get("height",2.))*.4); var t: float=(x-float(opening.get("t",.5))*length)/maxf(.001,width*.5)
	return top-rise+rise*sqrt(maxf(0.,1.-t*t))
static func _panel(mesh: KiwiModelMesh,left: float,right: float,bottom: Vector2,top: Vector2,thickness: float) -> void:
	var profile:=PackedVector2Array([Vector2(left,bottom.x),Vector2(right,bottom.y),Vector2(right,top.y),Vector2(left,top.x)])
	var panel:=KiwiModelPrimitives.prism(profile,thickness)
	for index in panel.vertices.size(): var p:=panel.vertices[index]; panel.vertices[index]=Vector3(p.x,p.z,p.y)
	for index in panel.faces.size(): panel.faces[index].reverse(); panel.uv[index].reverse()
	mesh.append_mesh(panel)
static func _slab(footprint: PackedVector2Array,cuts: Array,thickness: float) -> KiwiModelMesh:
	if cuts.is_empty(): return _convex_slab(footprint,thickness)
	var xs: Array[float]=[]; var zs: Array[float]=[]; var mesh:=KiwiModelMesh.new()
	for p in footprint: xs.append(p.x); zs.append(p.y)
	for value: Variant in cuts:
		if value is Rect2: xs.append(value.position.x); xs.append(value.end.x); zs.append(value.position.y); zs.append(value.end.y)
	xs.sort(); zs.sort()
	for x in xs.size()-1:
		for z in zs.size()-1:
			if xs[x+1]-xs[x]<.00001 or zs[z+1]-zs[z]<.00001: continue
			var center:=Vector2((xs[x]+xs[x+1])*.5,(zs[z]+zs[z+1])*.5); var remove:=false
			for cut: Variant in cuts:
				if cut is Rect2 and cut.has_point(center): remove=true; break
			if remove: continue
			var cell:=PackedVector2Array([Vector2(xs[x],zs[z]),Vector2(xs[x+1],zs[z]),Vector2(xs[x+1],zs[z+1]),Vector2(xs[x],zs[z+1])])
			for polygon in Geometry2D.intersect_polygons(footprint,cell):
				if polygon.size()>=3 and not Geometry2D.triangulate_polygon(polygon).is_empty(): mesh.append_mesh(_convex_slab(polygon,thickness))
	return mesh
static func _convex_slab(polygon: PackedVector2Array,thickness: float) -> KiwiModelMesh:
	var result:=KiwiModelMesh.new(); var triangles:=Geometry2D.triangulate_polygon(polygon)
	for index in range(0,triangles.size(),3): result.append_mesh(KiwiModelPrimitives.prism(PackedVector2Array([polygon[triangles[index]],polygon[triangles[index+1]],polygon[triangles[index+2]]]),thickness))
	return result
static func _opening(document: KiwiModelDocument,wall: KiwiModelComponent,opening: Dictionary,length: float,source: Resource) -> void:
	var width:=float(opening.get("width",1.)); var height:=float(opening.get("height",2.)); var bottom:=float(opening.get("bottom",0.)); var center:=float(opening.get("t",.5))*length; var id:=wall.parent_id+":opening:"+str(opening.get("id","opening")); var type:=str(opening.get("type","door"))
	if type=="arch": return
	var frame:=KiwiModelMesh.new(); var trim:=.07
	for part in [[Vector3(trim,height,source.wall_thickness+.06),Vector3(center-width*.5+trim*.5,bottom+height*.5,0)],[Vector3(trim,height,source.wall_thickness+.06),Vector3(center+width*.5-trim*.5,bottom+height*.5,0)],[Vector3(width,trim,source.wall_thickness+.06),Vector3(center,bottom+height-trim*.5,0)]]:
		frame.append_mesh(KiwiModelPrimitives.box(part[0]),Transform3D(Basis.IDENTITY,part[1]))
	_item(document,id+":frame","Window frame" if type=="window" else "Door frame",wall.id,frame,Transform3D.IDENTITY,source,3,"trim")
	if type=="window":
		frame.append_mesh(KiwiModelPrimitives.box(Vector3(width,.07,source.wall_thickness+.06)),Transform3D(Basis.IDENTITY,Vector3(center,bottom+.035,0.)))
		_item(document,id+":glass","Glass",wall.id,KiwiModelPrimitives.box(Vector3(width-trim*2.,height-trim*2.,.015)),Transform3D(Basis.IDENTITY,Vector3(center,bottom+height*.5,0)),source,4,"window"); return
	var leaf:=KiwiModelPrimitives.box(Vector3(width-trim*2.,height-trim,.05))
	for index in leaf.vertices.size(): leaf.vertices[index]+=Vector3(width*.5,(height-trim)*.5,0.)
	var hinge:=Vector3(center-width*.5,bottom,0); var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(opening.get("angle",0.)))),hinge)
	if type=="slider": pose=Transform3D(Basis.IDENTITY,hinge+Vector3.RIGHT*float(opening.get("slide",0.))*width)
	var door:=_item(document,id+":leaf","Sliding door" if type=="slider" else "Door",wall.id,leaf,pose,source,3,"door"); door.structural[&"structure_connections"]={"hinge":KiwiStructure.connection(wall.id,Vector3.ZERO,hinge,2 if type=="slider" else 1)}
	if type=="slider": door.structural[&"structure_connections"].hinge.orientation=Vector3(0,0,-90); door.structural[&"structure_connections"].hinge.limit=width
static func roof_mesh(source: Resource,warnings: PackedStringArray) -> KiwiModelMesh:
	var footprint: PackedVector2Array=source.footprint
	if source.roof_type==0: return KiwiModelPrimitives.prism(footprint,float(source.slab_thickness))
	var bounds:=Rect2(footprint[0],Vector2.ZERO)
	for point in footprint: bounds=bounds.expand(point)
	if footprint.size()!=4:
		warnings.append("Sloped roofs currently require a rectangular footprint. Use a flat roof for this plan."); return null
	for point in footprint:
		if not (is_equal_approx(point.x,bounds.position.x) or is_equal_approx(point.x,bounds.end.x)) or not (is_equal_approx(point.y,bounds.position.y) or is_equal_approx(point.y,bounds.end.y)):
			warnings.append("Sloped roofs require an axis-aligned rectangular plan."); return null
	var width:=bounds.size.x+float(source.roof_overhang)*2.; var depth:=bounds.size.y+float(source.roof_overhang)*2.; var rise:=tan(deg_to_rad(clampf(float(source.roof_pitch),1.,75.)))*(minf(width,depth) if source.roof_type==3 else width)*.5; var mesh:=KiwiModelMesh.new()
	if source.roof_type in [1,2]:
		var profile:=PackedVector2Array([Vector2(-width*.5,0),Vector2(width*.5,0),Vector2(0,rise)]) if source.roof_type==1 else PackedVector2Array([Vector2(-width*.5,0),Vector2(width*.5,0),Vector2(width*.5,rise)])
		mesh=KiwiModelPrimitives.prism(profile,depth)
		for index in mesh.vertices.size(): var p:=mesh.vertices[index]; mesh.vertices[index]=Vector3(p.x,p.z,p.y)
		for index in mesh.faces.size(): mesh.faces[index].reverse(); mesh.uv[index].reverse()
	else:
		mesh.vertices=PackedVector3Array([Vector3(-width*.5,0,-depth*.5),Vector3(width*.5,0,-depth*.5),Vector3(width*.5,0,depth*.5),Vector3(-width*.5,0,depth*.5)])
		var faces: Array=[]
		if is_equal_approx(width,depth):
			mesh.vertices.append(Vector3(0,rise,0)); faces=[[0,1,4],[1,2,4],[2,3,4],[3,0,4],[3,2,1,0]]
		elif depth>width:
			mesh.vertices.append(Vector3(0,rise,-(depth-width)*.5)); mesh.vertices.append(Vector3(0,rise,(depth-width)*.5)); faces=[[0,1,4],[1,2,5,4],[2,3,5],[3,0,4,5],[3,2,1,0]]
		else:
			mesh.vertices.append(Vector3(-(width-depth)*.5,rise,0)); mesh.vertices.append(Vector3((width-depth)*.5,rise,0)); faces=[[0,1,5,4],[1,2,5],[2,3,4,5],[3,0,4],[3,2,1,0]]
		for face: Array in faces: mesh.add_face(PackedInt32Array(face))
		for f in mesh.faces.size():
			if mesh.normal(f).dot(mesh.center(f)-Vector3(0,rise*.3,0))<0.: mesh.faces[f].reverse(); mesh.uv[f].reverse()
	for index in mesh.vertices.size(): mesh.vertices[index]+=Vector3(bounds.get_center().x,0.,bounds.get_center().y)
	return mesh
