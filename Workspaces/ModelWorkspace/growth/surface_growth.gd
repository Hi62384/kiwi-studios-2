class_name KiwiSurfaceGrowth
extends RefCounted
const TYPES:=["Hair","Fur","Feathers"]
const MAX_ROOTS:=20000
const MAX_VERTICES:=1000000
const GROWTH_FORMAT:=(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
static func base_settings(data: KiwiSurfaceGrowthData) -> Dictionary:
	var signature:=hash([data.settings,data.growth_style.values if data.growth_style!=null else {}])
	if data.base_cache.is_empty() or signature!=data.base_signature:
		data.base_signature=signature; data.base_cache=data.settings.duplicate()
		if data.growth_style!=null: data.base_cache.merge(data.growth_style.values,true)
	return data.base_cache
static func prepare_regions(data: KiwiSurfaceGrowthData) -> void:
	if data.region_revision==data.revision and data.region_base==data.base_signature: return
	var base:=base_settings(data)
	data.region_revision=data.revision; data.region_base=data.base_signature; data.root_regions.clear(); data.region_settings.clear(); var signature:=[]
	for index in mini(16,data.regions.size()):
		var region: Dictionary=data.regions[index]
		if not region.get("enabled",true): continue
		var style:=region.get("style") as KiwiGrowthStyle; var settings:=base.duplicate()
		if style!=null: settings.merge(style.values,true)
		data.region_settings[index]=settings
		var ids: PackedInt32Array=region.get("roots",PackedInt32Array()); var faces: PackedInt32Array=region.get("faces",PackedInt32Array())
		for id: int in ids: data.root_regions[id]=index
		if not faces.is_empty() or region.get("all",false):
			for root: Dictionary in data.roots:
				if region.get("all",false) or faces.has(int(root.face)): data.root_regions[int(root.id)]=index
		signature.append([index,ids,faces,region.get("all",false),style.values if style!=null else {}])
	data.region_signature=hash(signature)
static func root_settings(data: KiwiSurfaceGrowthData,root: Dictionary) -> Dictionary:
	prepare_regions(data)
	return data.region_settings.get(int(data.root_regions.get(int(root.id),-1)),data.base_cache)
static func region_material(data: KiwiSurfaceGrowthData,index: int) -> Material:
	if index>=0 and index<data.regions.size() and data.regions[index].get("material") is KiwiGrowthMaterial: return (data.regions[index].material as KiwiGrowthMaterial).material()
	return data.material
static func defaults(kind: int=0) -> Dictionary:
	return {"type":kind,"density":120.0 if kind==1 else (12.0 if kind==2 else 35.0),"length":.12 if kind==1 else (.45 if kind==2 else .65),"thickness":.008 if kind==1 else .012,"seed":31,"quality":1,"shape":0,"curvature":.15,"taper":.9,"variation":.25,"direction":Vector3.DOWN,"direction_mode":0,"direction_blend":.4,"orientation_variation":.15,"width":.14,"feather_type":1,"overlap":.3,"arrangement":0,"rows":4,"spacing":0.0,"guard_hairs":.12,"color":Color(.28,.12,.055),"candidate_multiplier":2.0}
static func add(session: KiwiModelSession,kind: int) -> String:
	var source:=session.primary()
	if source==null or source.mesh==null or source.growth!=null: return "Select a source mesh, then optionally select its faces."
	var data:=KiwiSurfaceGrowthData.new(); data.source_id=source.id; data.settings=defaults(kind); data.faces=session.elements.duplicate() if session.mode=="Face" else PackedInt32Array()
	var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.parent_id=source.id; item.title=TYPES[kind]; item.growth=data; item.mesh=KiwiModelMesh.new()
	var error:=prepare(session.document,item,source)
	if not error.is_empty(): return error
	session.action("Generate "+TYPES[kind],func(): session.document.components.append(item); session.selected.assign([item.id]); session.mode="Object"; session.elements=PackedInt32Array())
	return ""
static func add_layered_fur(session: KiwiModelSession) -> String:
	var source:=session.primary()
	if source!=null and source.growth!=null: source=session.document.component(source.growth.source_id)
	if source==null or source.mesh==null: return "Select a source mesh for the coat."
	var layers: Array[KiwiModelComponent]=[]
	for guard in [false,true]:
		var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.parent_id=source.id; item.title="Guard hairs" if guard else "Undercoat"; item.mesh=KiwiModelMesh.new(); item.growth=KiwiSurfaceGrowthData.new(); item.growth.source_id=source.id; item.growth.settings=defaults(1); item.growth.settings.merge({"density":24. if guard else 240.,"length":.22 if guard else .07,"thickness":.005 if guard else .002,"seed":72 if guard else 31,"guard_hairs":0.,"variation":.35},true)
		if session.mode=="Face": item.growth.faces=session.elements.duplicate()
		var error:=prepare(session.document,item,source)
		if not error.is_empty(): return error
		item.growth.appearance.root_color=Color(.12,.105,.09); item.growth.appearance.tip_color=Color(.22,.19,.15) if guard else Color(.42,.4,.36); item.growth.appearance.roughness=.55 if guard else .8; layers.append(item)
	session.action("Generate layered fur coat",func():
		for item: KiwiModelComponent in layers: session.document.components.append(item)
		session.selected.assign([layers[0].id]); session.mode="Object"; session.elements=PackedInt32Array())
	return ""
static func prepare(document: KiwiModelDocument,item: KiwiModelComponent,source: KiwiModelComponent) -> String:
	var data:=item.growth
	if data==null: return "Missing growth definition."
	if data.appearance==null:
		data.appearance=KiwiGrowthMaterial.new(); data.appearance.root_color=data.settings.get("color",Color(.28,.12,.055)); data.appearance.tip_color=data.appearance.root_color.lightened(.15)
	if source==null or source==item or source.growth!=null: data.source_valid=false; return "The source mesh is missing or is another growth system."
	if int(data.settings.get("direction_mode",0))==1 and data.source_to_rig!=document.world_transform(source): data.source_to_rig=document.world_transform(source); data.revision+=1; data.render_cache=null
	var start:=Time.get_ticks_usec(); var mesh:=KiwiModelModifiers.evaluate(source)
	var editable:=mesh
	var skin_mesh: Mesh=source.skin_mesh if source.skin_mesh!=null else (source.binding.source_mesh if source.binding!=null else null)
	if skin_mesh!=null: mesh=KiwiModelMesh.from_mesh(skin_mesh)
	if mesh.faces.size()>100000 or mesh.vertices.size()>100000: return "Growth sources support up to 100,000 vertices/faces. Use a lower-resolution surface."
	var signature:=hash([mesh.faces,mesh.vertices.size()]); var key:=hash([signature,data.faces,data.settings.get("density"),data.settings.get("seed"),data.settings.get("spacing"),data.settings.get("arrangement"),data.settings.get("rows"),data.settings.get("candidate_multiplier"),source.skin_mesh,source.binding.revision if source.binding!=null else 0])
	if key==data.generation_key and not data.roots.is_empty():
		data.source_valid=true; data.error=""
		if data.source_points!=mesh.vertices:
			data.source_points=mesh.vertices; data.render_cache=null; data.candidate_grid.clear(); data.revision+=1
			for root: Dictionary in data.roots:
				var frame:=point_frame(data,root,mesh.vertices); root.position=frame.origin; root.normal=frame.basis.y
		return ""
	var topology_changed:=data.topology!=0 and data.topology!=signature
	if topology_changed: data.source_valid=false; return "Source topology changed. Regenerate to reset old attachments/groom, then choose the new face region. Existing data is preserved until you confirm regeneration."
	var face_mapping:={}
	if skin_mesh!=null and not data.faces.is_empty():
		var lookup:={}; var transform:=source.binding.mesh_to_rig if source.binding!=null and source.binding.rigid_bone_id.is_empty() else Transform3D.IDENTITY
		for f in editable.faces.size():
			var corners:=editable.triangles(f)
			for i in range(0,corners.size(),3): lookup[triangle_key(transform*editable.vertices[editable.faces[f][corners[i]]],transform*editable.vertices[editable.faces[f][corners[i+1]]],transform*editable.vertices[editable.faces[f][corners[i+2]]])]=f
		for f in mesh.faces.size(): face_mapping[f]=lookup.get(triangle_key(mesh.vertices[mesh.faces[f][0]],mesh.vertices[mesh.faces[f][1]],mesh.vertices[mesh.faces[f][2]]),-1)
	var triangles: Array[Dictionary]=[]; var cumulative:=PackedFloat64Array(); var area:=0.0
	for f in mesh.faces.size():
		var face_id: int=face_mapping.get(f,f)
		if not data.faces.is_empty() and not data.faces.has(face_id): continue
		var corners:=mesh.triangles(f)
		for i in range(0,corners.size(),3):
			var ids:=Vector3i(mesh.faces[f][corners[i]],mesh.faces[f][corners[i+1]],mesh.faces[f][corners[i+2]]); var a:=mesh.vertices[ids.x]; var b:=mesh.vertices[ids.y]; var c:=mesh.vertices[ids.z]; var size: float=(b-a).cross(c-a).length()*.5
			if size<.00000001: continue
			area+=size; cumulative.append(area); triangles.append({"indices":ids,"face":face_id,"normal":mesh.normal(f)})
	if triangles.is_empty(): data.error="The selected surface contains no usable triangles."; return data.error
	var requested:=ceili(area*maxf(0,float(data.settings.get("density",35)))); var candidates:=ceili(requested*clampf(float(data.settings.get("candidate_multiplier",2)),1,4))
	if candidates>MAX_ROOTS: data.error="Requested %d candidate roots; the limit is %d. Lower density or reserve multiplier."%[candidates,MAX_ROOTS]; return data.error
	var rng:=RandomNumberGenerator.new(); rng.seed=int(data.settings.get("seed",31)); var roots: Array[Dictionary]=[]; var spacing:=float(data.settings.get("spacing",0)); var grid:={}
	var ordered:=int(data.settings.get("arrangement",0))==1; var bounds:=mesh.bounds(); var row_normal: Vector3=triangles[0].normal; var depth_axis:=row_normal.abs().max_axis_index(); var u_axis: int=(depth_axis+1)%3; var v_axis: int=(depth_axis+2)%3; var rows:=maxi(1,int(data.settings.get("rows",4))); var columns:=maxi(1,ceili(float(candidates)/rows))
	if ordered and candidates*triangles.size()>2000000: return "Ordered rows exceed the two-million-triangle-query budget. Reduce density or use a smaller face region."
	for i in candidates:
		var sample:=rng.randf()*area; var low:=0; var high:=cumulative.size()-1
		while low<high:
			var middle: int=(low+high)/2
			if cumulative[middle]<sample: low=middle+1
			else: high=middle
		var triangle: Dictionary=triangles[low]; var u:=sqrt(rng.randf()); var v:=rng.randf()
		var bary:=Vector3(1-u,u*(1-v),u*v); var indices: Vector3i=triangle.indices; var point:=mesh.vertices[indices.x]*bary.x+mesh.vertices[indices.y]*bary.y+mesh.vertices[indices.z]*bary.z
		if ordered:
			var origin:=bounds.position; origin[depth_axis]-=maxf(1,bounds.size[depth_axis]); origin[u_axis]+=bounds.size[u_axis]*(float(i%rows)+.5)/rows; origin[v_axis]+=bounds.size[v_axis]*(float(i/rows)+.5)/columns; var direction:=Vector3.ZERO; direction[depth_axis]=1; var nearest:=INF; var found:=false
			for candidate: Dictionary in triangles:
				var ids: Vector3i=candidate.indices; var hit: Variant=Geometry3D.ray_intersects_triangle(origin,direction,mesh.vertices[ids.x],mesh.vertices[ids.y],mesh.vertices[ids.z])
				if hit==null or origin.distance_squared_to(hit)>=nearest: continue
				nearest=origin.distance_squared_to(hit); point=hit; indices=ids; triangle=candidate; found=true
			if not found: continue
			var a:=mesh.vertices[indices.x]; var b:=mesh.vertices[indices.y]-a; var c:=mesh.vertices[indices.z]-a; var offset:=point-a; var denominator:=b.dot(b)*c.dot(c)-b.dot(c)*b.dot(c)
			var y: float=(c.dot(c)*offset.dot(b)-b.dot(c)*offset.dot(c))/denominator; var z: float=(b.dot(b)*offset.dot(c)-b.dot(c)*offset.dot(b))/denominator; bary=Vector3(1-y-z,y,z)
		var allowed:=true
		if spacing>.00001:
			var cell:=Vector3i((point/spacing).floor())
			for x in range(-1,2):
				for y in range(-1,2):
					for z in range(-1,2):
						for other: Vector3 in grid.get(cell+Vector3i(x,y,z),[]):
							if other.distance_squared_to(point)<spacing*spacing: allowed=false
			if allowed:
				if not grid.has(cell): grid[cell]=[]
				grid[cell].append(point)
		var random:=Vector4(rng.randf(),rng.randf(),rng.randf(),rng.randf())
		if allowed: roots.append({"id":i,"triangle":indices,"face":triangle.face,"bary":bary,"normal":triangle.normal,"random":random,"position":point,"density_rank":rng.randf()})
	# Spatially adjacent roots share geometry chunks. Local edits then rebuild
	# nearby chunks instead of random roots spread throughout the entire buffer.
	roots.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var x:=Vector3i((a.position/data.grid_size).floor()); var y:=Vector3i((b.position/data.grid_size).floor())
		if x.x!=y.x: return x.x<y.x
		if x.y!=y.y: return x.y<y.y
		if x.z!=y.z: return x.z<y.z
		return int(a.id)<int(b.id))
	data.surface_triangles=triangles; data.roots=roots; data.topology=signature; data.source_points=mesh.vertices; data.generation_key=key; data.source_skin=source.skin; data.source_to_rig=source.binding.mesh_to_rig if source.binding!=null else document.world_transform(source); data.source_weights=[]
	if skin_mesh!=null:
		var lookup:={}
		for surface in skin_mesh.get_surface_count():
			var arrays:=skin_mesh.surface_get_arrays(surface); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS]!=null else PackedFloat32Array(); var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES]!=null else PackedInt32Array(); var width:=weights.size()/maxi(1,vertices.size())
			for index in vertices.size():
				var influences:={}
				for k in width:
					if weights[index*width+k]>0: influences[bones[index*width+k]]=weights[index*width+k]
				lookup[Vector3i((vertices[index]*100000).round())]=influences
		for point: Vector3 in mesh.vertices: data.source_weights.append(lookup.get(Vector3i((point*100000).round()),{}))
	item.skeleton_id=source.skeleton_id; data.source_valid=true; data.candidate_grid.clear(); data.render_cache=null; data.error=""; data.generated_usec=Time.get_ticks_usec()-start
	data.rigid_bone=-1
	if source.binding!=null and not source.binding.rigid_bone_id.is_empty():
		var armature:=document.component(source.skeleton_id)
		if armature!=null:
			for i in armature.bones.size():
				if str(armature.bones[i].id)==source.binding.rigid_bone_id: data.rigid_bone=i; data.rigid_offset=source.binding.attachment_offset
	return ""
static func triangle_key(a: Vector3,b: Vector3,c: Vector3) -> String:
	var keys: Array[String]=[str(Vector3i((a*100000).round())),str(Vector3i((b*100000).round())),str(Vector3i((c*100000).round()))]; keys.sort(); return ":".join(keys)
static func point_frame(data: KiwiSurfaceGrowthData,root: Dictionary,positions: PackedVector3Array) -> Transform3D:
	var ids: Vector3i=root.triangle; var bary: Vector3=root.bary; var a:=positions[ids.x]; var b:=positions[ids.y]; var c:=positions[ids.z]; var normal: Vector3=(c-a).cross(b-a).normalized()
	if normal.is_zero_approx(): normal=root.normal
	var tangent: Vector3=(b-a).normalized(); var across:=tangent.cross(normal).normalized()
	return Transform3D(Basis(tangent,normal,across),a*bary.x+b*bary.y+c*bary.z)
static func posed_points(data: KiwiSurfaceGrowthData,skeleton: Skeleton3D) -> PackedVector3Array:
	if skeleton==null or data.source_skin==null or data.source_weights.is_empty(): return data.source_points
	var matrices: Array[Transform3D]=[]
	for i in data.source_skin.get_bind_count():
		var bone:=data.source_skin.get_bind_bone(i); var name:=data.source_skin.get_bind_name(i)
		if not name.is_empty(): bone=skeleton.find_bone(name)
		matrices.append(skeleton.get_bone_global_pose(bone)*data.source_skin.get_bind_pose(i) if bone>=0 and bone<skeleton.get_bone_count() else Transform3D.IDENTITY)
	var result:=PackedVector3Array(); result.resize(data.source_points.size())
	for i in result.size():
		var sum:=0.0; var point:=Vector3.ZERO
		for bone: int in data.source_weights[i]:
			if bone>=0 and bone<matrices.size(): point+=(matrices[bone]*data.source_points[i])*float(data.source_weights[i][bone]); sum+=float(data.source_weights[i][bone])
		result[i]=point/sum if sum>.00001 else data.source_points[i]
	return result
static func style(data: KiwiSurfaceGrowthData,root: Dictionary) -> Dictionary:
	if data.effective_revision!=data.revision:
		data.effective=data.groom.duplicate(true)
		for layer: Dictionary in data.groom_layers:
			if not layer.get("enabled",true): continue
			for id: String in layer.changes:
				if not data.effective.has(id): data.effective[id]={}
				data.effective[id].merge(layer.changes[id],true)
		for id: String in data.pending:
			if not data.effective.has(id): data.effective[id]={}
			data.effective[id].merge(data.pending[id],true)
		data.effective_revision=data.revision
	var result: Dictionary=data.effective.get(str(root.id),{}).duplicate(true) if data.groom_enabled else {}; var base:=root_settings(data,root)
	result.merge(data.individual.get(str(root.id),{}),true)
	result.length=maxf(0,float(result.get("length",base.get("length",.5))))
	result.density=clampf(float(result.get("density",1.0/float(base.get("candidate_multiplier",2)))),0,1)
	return result
static func curve(data: KiwiSurfaceGrowthData,root: Dictionary,segments: int=-1) -> PackedVector3Array:
	var base:=root_settings(data,root); var edit:=style(data,root); var count: int=[3,6,10,16][clampi(int(base.get("quality",1)),0,3)]; var length: float=edit.length*(1+(float(root.random.x)*2-1)*float(base.get("variation",.25))); var direction: Vector3=edit.get("direction",Vector3.UP)
	if int(base.get("type",0))==2: length*=.45 if int(base.get("feather_type",1))==0 else (1.5 if int(base.get("feather_type",1))==2 else 1.)
	if int(base.get("type",0))==1 and float(root.random.w)<float(base.get("guard_hairs",.12)): length*=1.6
	if segments>0: count=segments
	elif data.render_final: count=16
	elif data.lod_detail>0: count=maxi(2,count/(data.lod_detail+1))
	if not edit.has("direction"):
		var frame:=point_frame(data,root,data.source_points); var preferred: Vector3=base.get("direction",Vector3.DOWN)
		if int(base.get("direction_mode",0))==0: direction=Vector3.UP
		else:
			if int(base.get("direction_mode",0))==1: preferred=data.source_to_rig.basis.inverse()*preferred
			if int(base.get("direction_mode",0))==3: preferred-=frame.basis.y*preferred.dot(frame.basis.y)
			direction=Vector3.UP.lerp(frame.basis.inverse()*preferred,clampf(float(base.get("direction_blend",.4)),0,1)).normalized()
	var random: Vector4=root.random; direction=(direction+Vector3(random.y-.5,0,random.z-.5)*float(base.get("orientation_variation",.15))).normalized()
	var result:=PackedVector3Array(); var curl:=float(edit.get("curl",base.get("curl",1.0 if int(base.get("shape",0)) in [2,3] else 0.0))); var frequency:=float(edit.get("frequency",base.get("frequency",3))); var bend:=float(base.get("curvature",.15)); var offset: Vector3=edit.get("offset",Vector3.ZERO)
	var frizz:=float(edit.get("frizz",base.get("frizz",0.))); var frizz_frequency:=float(base.get("frizz_frequency",8.))
	if segments<=0 and (absf(curl)>.0001 or frizz>.0001):
		var quality:=3 if data.render_final else clampi(int(base.get("quality",1))-data.lod_detail,0,3)
		count=maxi(count,mini([12,32,64,96][quality],ceili(maxf(frequency,frizz_frequency if frizz>0. else 0.)*[3.,6.,8.,12.][quality])))
	for i in count+1:
		var t:=float(i)/count; var point:=direction*length*t+Vector3(0,-bend*length*t*t,0)+offset*t*t
		if int(base.get("shape",0))==1: point.x+=sin(t*PI)*length*bend
		if curl!=0: point+=Vector3(sin(t*TAU*frequency),0,(1-cos(t*TAU*frequency)) if int(base.get("shape",0))==3 else 0.0)*length*.12*curl*t
		if frizz>0.:
			var phase:=random.z*TAU; var wave:=t*TAU*frizz_frequency+phase
			point+=Vector3(sin(wave)-sin(phase),0,cos(wave*.83)-cos(phase*.83))*length*frizz*.1*t
		if edit.has("clump_target"):
			var clumping:=smoothstep(float(edit.get("clump_start",0)),maxf(.001+float(edit.get("clump_start",0)),float(edit.get("clump_end",1))),t)
			clumping*=clampf(float(edit.get("clump",0))*(1.-float(edit.get("clump_variation",0))*random.y),0,1)
			point=point.lerp((edit.clump_target as Vector3)*t,clumping)
		result.append(point)
	if not is_zero_approx(curl) or frizz>0.:
		for i in range(1,result.size()): result[i]=result[i-1]+(result[i]-result[i-1]).normalized()*length/count
	var weights: Dictionary=edit.get("guide_weights",{}).duplicate()
	if weights.is_empty() and edit.get("guide","")!="": weights[str(edit.guide)]=1.
	var total:=0.; var blended:=PackedVector3Array(); blended.resize(result.size()); var influence:=0.
	for id: String in weights:
		if not data.guides.has(id): continue
		var guide: Dictionary=data.guides[id]; var points: PackedVector3Array=guide.points; var weight:=maxf(0,float(weights[id]))
		if points.size()<2 or weight<=0: continue
		total+=weight; influence+=weight*clampf(float(guide.get("influence",1)),0,1)
		var rotation:=Basis.from_euler(guide.get("rotation",Vector3.ZERO)); var scale:=maxf(.001,float(guide.get("length_scale",1)))
		for i in result.size():
			var at: float=float(i)/(result.size()-1)*(points.size()-1); var index:=mini(int(at),points.size()-2)
			blended[i]+=rotation*(points[index].lerp(points[index+1],at-index)-points[0])*scale*weight
	if total>0:
		for i in range(1,result.size()): result[i]=result[i].lerp(blended[i]/total,influence/total)
	if edit.get("trim_curve",PackedVector3Array()).size()>1:
		var trimmed: PackedVector3Array=edit.trim_curve; var scaled:=PackedVector3Array()
		for point: Vector3 in trimmed: scaled.append(point*float(edit.length)/maxf(.00001,float(edit.get("trim_length",edit.length))))
		result=resample_curve(scaled,count+1)
	if not data.gpu_motion and not data.motion_guides.is_empty():
		for i in range(1,result.size()): result[i]+=motion_delta(data,root,float(i)/(result.size()-1))*data.motion_influence
	return result
static func motion_delta(data: KiwiSurfaceGrowthData,root: Dictionary,t: float) -> Vector3:
	var result:=Vector3.ZERO; var total:=0.
	for id: String in data.motion_weights.get(str(root.id),{}):
		if not data.motion_guides.has(id): continue
		var points: PackedVector3Array=data.motion_guides[id].get("delta_points",PackedVector3Array())
		if points.size()<2: continue
		var weight:=maxf(0,float(data.motion_weights[str(root.id)][id])); var at:=clampf(t,0,1)*(points.size()-1); var index:=mini(int(at),points.size()-2)
		result+=points[index].lerp(points[index+1],at-index)*weight; total+=weight
	return result/maxf(.00001,total)
static func resample_curve(points: PackedVector3Array,count: int) -> PackedVector3Array:
	var distances:=PackedFloat32Array([0.]); var length:=0.
	for i in range(1,points.size()): length+=points[i].distance_to(points[i-1]); distances.append(length)
	var result:=PackedVector3Array(); var segment:=0
	for i in count:
		var target:=length*float(i)/maxi(1,count-1)
		while segment<points.size()-2 and distances[segment+1]<target: segment+=1
		result.append(points[segment].lerp(points[segment+1],clampf((target-distances[segment])/maxf(.000001,distances[segment+1]-distances[segment]),0,1)))
	return result
static func cut_plane(data: KiwiSurfaceGrowthData,plane: Plane) -> int:
	var changed:=0
	for root: Dictionary in data.roots:
		var edit:=style(data,root)
		if edit.get("locked",false): continue
		var frame:=point_frame(data,root,data.source_points); var points:=curve(data,root); var clipped:=PackedVector3Array([Vector3.ZERO]); var length:=0.
		for i in range(1,points.size()):
			var a:=frame*points[i-1]; var b:=frame*points[i]; var hit: Variant=plane.intersects_segment(a,b)
			if hit!=null:
				var point: Vector3=frame.affine_inverse()*hit; length+=clipped[-1].distance_to(point); clipped.append(point)
				var id:=str(root.id)
				if not data.individual.has(id): data.individual[id]={}
				data.individual[id].merge({"trim_curve":clipped,"trim_length":length,"length":length},true); changed+=1; break
			length+=points[i-1].distance_to(points[i]); clipped.append(points[i])
	data.revision+=1; return changed
static func render(data: KiwiSurfaceGrowthData,positions: PackedVector3Array=PackedVector3Array()) -> ArrayMesh:
	if not data.source_valid: return ArrayMesh.new()
	if data.appearance==null:
		data.appearance=KiwiGrowthMaterial.new(); data.appearance.root_color=data.settings.get("color",Color(.28,.12,.055)); data.appearance.tip_color=data.appearance.root_color.lightened(.15)
	var next_material:=data.appearance.material()
	data.material=next_material; base_settings(data); prepare_regions(data)
	for region: Dictionary in data.regions:
		if region.get("material") is KiwiGrowthMaterial: region.material.material()
	if data.render_cache!=null:
		for surface in data.render_cache.get_surface_count(): data.render_cache.surface_set_material(surface,region_material(data,int(data.surface_regions.get(surface,-1))))
	var geometry_settings:=base_settings(data).duplicate(); geometry_settings.erase("color")
	var motion: Dictionary={} if data.gpu_motion else data.motion_guides
	var key:=hash([data.generation_key,geometry_settings,data.region_signature,data.revision,data.groom_enabled,data.guides,motion,data.gpu_motion,data.lod_upper,data.lod_detail,data.render_final])
	if positions.is_empty() and data.render_cache!=null and data.render_key==key: return data.render_cache
	var deformed:=not positions.is_empty()
	if positions.is_empty(): positions=data.source_points
	var base:=hash([data.generation_key,geometry_settings,data.region_signature,data.groom_enabled,data.guides,motion,data.gpu_motion,data.lod_upper,data.lod_detail,data.render_final,positions if deformed else data.source_points])
	var rebuild:=deformed or data.render_cache==null or data.chunk_signature!=base or (data.chunk_revision!=data.revision and data.dirty_chunks.is_empty())
	if rebuild: data.chunks.clear(); data.surface_chunks.clear(); data.surface_regions.clear()
	data.chunk_signature=base
	var result:=ArrayMesh.new() if rebuild else data.render_cache; var vertices:=0
	for chunk in ceili(float(data.roots.size())/128):
		var changed:=not data.chunks.has(chunk) or data.dirty_chunks.has(chunk)
		if changed:
			data.chunk_builds+=1
			data.chunks[chunk]=render_chunk(data,positions,chunk*128,mini((chunk+1)*128,data.roots.size()))
			if data.surface_chunks.has(chunk):
				var removals: Array=data.surface_chunks[chunk].duplicate(); removals.sort(); removals.reverse(); data.surface_chunks.erase(chunk)
				for removed: int in removals:
					result.surface_remove(removed)
					for other: int in data.surface_chunks:
						for i in data.surface_chunks[other].size():
							if int(data.surface_chunks[other][i])>removed: data.surface_chunks[other][i]-=1
					var shifted:={}
					for index: int in data.surface_regions:
						if index!=removed: shifted[index-1 if index>removed else index]=data.surface_regions[index]
					data.surface_regions=shifted
		var mesh: ArrayMesh=data.chunks[chunk]
		if mesh.get_surface_count()==0: continue
		for surface in mesh.get_surface_count(): vertices+=mesh.surface_get_array_len(surface)
		if vertices>MAX_VERTICES: data.error="Growth exceeds the one-million-vertex budget. Reduce quality/density."; return ArrayMesh.new()
		if changed:
			data.surface_chunks[chunk]=[]
			for surface in mesh.get_surface_count():
				var index:=result.get_surface_count(); var region: int=mesh.get_meta("growth_regions")[surface]; data.surface_chunks[chunk].append(index); data.surface_regions[index]=region
				result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(surface),[],{},GROWTH_FORMAT); result.surface_set_material(index,region_material(data,region))
	data.dirty_chunks.clear(); data.chunk_revision=data.revision
	if not deformed: data.render_cache=result; data.render_key=key
	return result
static func render_chunk(data: KiwiSurfaceGrowthData,positions: PackedVector3Array,first: int,last: int) -> ArrayMesh:
	var groups:={}; var result:=ArrayMesh.new(); var regions:=PackedInt32Array()
	for index in range(first,last): groups[int(data.root_regions.get(int(data.roots[index].id),-1))]=true
	if groups.size()==1:
		var region: int=groups.keys()[0]; var geometry:=render_roots(data,positions,first,last,region); geometry.set_meta("growth_regions",PackedInt32Array([region])); return geometry
	for region: int in groups:
		var geometry:=render_roots(data,positions,first,last,region)
		if geometry.get_surface_count()==0: continue
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,geometry.surface_get_arrays(0),[],{},GROWTH_FORMAT); result.surface_set_material(result.get_surface_count()-1,region_material(data,region)); regions.append(region)
	result.set_meta("growth_regions",regions); return result
static func render_roots(data: KiwiSurfaceGrowthData,positions: PackedVector3Array,first: int,last: int,region: int) -> ArrayMesh:
	var vertices:=PackedVector3Array(); var normals:=PackedVector3Array(); var uv:=PackedVector2Array(); var colors:=PackedColorArray(); var indices:=PackedInt32Array()
	var tangents:=PackedFloat32Array(); var attributes:=PackedFloat32Array(); var centers:=PackedFloat32Array(); var attachments:=PackedFloat32Array()
	var settings:=base_settings(data); var kind:=int(settings.get("type",0)); var feather:=kind==2
	for index in range(first,last):
		var root: Dictionary=data.roots[index]
		if int(data.root_regions.get(int(root.id),-1))!=region: continue
		settings=root_settings(data,root)
		if float(root.random.z)>data.lod_upper: continue
		var edit:=style(data,root)
		if root.density_rank>float(edit.density) or float(edit.length)<.0001: continue
		var frame:=point_frame(data,root,positions); var points:=curve(data,root); var width:=float(edit.get("width",settings.get("width",.14))) if feather else float(edit.get("thickness",settings.get("thickness",.012))); width*=lerpf(.8,1.2,root.random.w)
		if feather:
			width*=1+float(settings.get("overlap",.3))
			var type:=int(settings.get("feather_type",1))
			if type==0:
				width*=1.3
		var offset:=vertices.size()
		var section:=int(settings.get("cross_section",0)); var sides:=2 if feather or section==0 else (4 if section==1 else (6 if section==2 else 8)); var side_direction:=Vector3.RIGHT
		for i in points.size():
			var t:=float(i)/(points.size()-1); var tip_ratio:=float(settings.get("tip_thickness",-1.))/maxf(.00001,width)
			if tip_ratio<0.: tip_ratio=1.-float(settings.get("taper",.9))
			var profile:=pow(maxf(0,sin(pow(t,.65)*PI)),float(settings.get("feather_tip",1.)))*.5 if feather else maxf(.001,lerpf(1.,tip_ratio,t))*.5
			var tangent: Vector3=(points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
			side_direction-=tangent*side_direction.dot(tangent)
			if side_direction.length_squared()<.00001: side_direction=Vector3.FORWARD-tangent*tangent.z
			side_direction=side_direction.normalized()
			var rotated_side:=side_direction.rotated(tangent,float(settings.get("twist",0.))*t+deg_to_rad(float(edit.get("roll",0.)))); var binormal:=rotated_side.cross(tangent).normalized()
			var side:=rotated_side*width*maxf(.01,profile); var color: Color=edit.get("color",Color.WHITE)
			var world_tangent: Vector3=(frame.basis*tangent).normalized(); var normal: Vector3=(frame.basis*side_direction.cross(tangent)).normalized()
			for edge in sides:
				var sign: float=-1. if edge==0 else 1.; var radial:=rotated_side*cos(float(edge)/sides*TAU)+binormal*sin(float(edge)/sides*TAU)*float(settings.get("flatten",.6))
				var displacement:=side*sign*(1.+sign*float(settings.get("feather_asymmetry",0.))) if sides==2 else radial*width*maxf(.01,profile)
				vertices.append(frame*(points[i]+displacement)); normals.append(normal if sides==2 else (frame.basis*radial).normalized()); uv.append(Vector2(float(edge)/maxi(1,sides-1),t)); colors.append(color)
				tangents.append_array(PackedFloat32Array([world_tangent.x,world_tangent.y,world_tangent.z,1.])); attributes.append_array(PackedFloat32Array([root.position.x,root.position.y,root.position.z,float(root.random.z)+(1.0 if feather else 0.0)]))
				var center: Vector3=frame*points[i]; centers.append_array(PackedFloat32Array([center.x,center.y,center.z,1.]))
				attachments.append_array(PackedFloat32Array([root.bary.x,root.bary.y,root.bary.z,float(index)]))
		for i in points.size()-1:
			for edge in (1 if sides==2 else sides):
				var at:=offset+i*sides+edge; var next:=offset+i*sides+(edge+1)%sides; indices.append_array(PackedInt32Array([at,at+sides,next,next,at+sides,next+sides]))
		if feather:
			# A separate narrow raised rachis runs down the vane.
			var shaft:=vertices.size()
			for i in points.size():
				var tangent: Vector3=(frame.basis*(points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)])).normalized()
				for sign in [-1.0,1.0]:
					vertices.append(frame*(points[i]+Vector3(sign*width*.025,0,.002))); normals.append(frame.basis.z); uv.append(Vector2((sign+1)*.5,float(i)/(points.size()-1))); colors.append(Color.WHITE)
					tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,1.])); attributes.append_array(PackedFloat32Array([root.position.x,root.position.y,root.position.z,-1.0-float(root.random.z)]))
					var center: Vector3=frame*points[i]; centers.append_array(PackedFloat32Array([center.x,center.y,center.z,1.]))
					attachments.append_array(PackedFloat32Array([root.bary.x,root.bary.y,root.bary.z,float(index)]))
			for i in points.size()-1:
				var at:=shaft+i*2; indices.append_array(PackedInt32Array([at,at+2,at+1,at+1,at+2,at+3]))
		if vertices.size()>MAX_VERTICES: data.error="Growth exceeded the one-million-vertex budget. Reduce quality or density."; return ArrayMesh.new()
	var result:=ArrayMesh.new()
	if not vertices.is_empty():
		var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TANGENT]=tangents; arrays[Mesh.ARRAY_CUSTOM0]=attributes; arrays[Mesh.ARRAY_CUSTOM1]=centers; arrays[Mesh.ARRAY_CUSTOM2]=attachments; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices; result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},GROWTH_FORMAT)
	return result
