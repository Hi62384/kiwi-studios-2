class_name KiwiRigViewport
extends RefCounted
var canvas: KiwiModelViewport
var editor: KiwiRigEditor
var nodes: Dictionary={}
var signatures: Dictionary={}
var heat_signature: Dictionary={}
var construction := "Inside mesh"
var depth := 0.
var brush_radius := .3
var brush_strength := .25
var brush_value := 1.
var brush_mode := "Add"
var paint_hidden := false
var chain: Variant=null
var chain_parent := -1
var placing := false
var cursor := Vector3.ZERO
var mouse := Vector2.ZERO
var drag := ""
var drag_end := false
var drag_axis := -1
var drag_origin := Vector3.ZERO
var drag_point := Vector3.ZERO
var drag_mouse := Vector2.ZERO
var drag_normal := Vector3.FORWARD
var drag_before: Array[Dictionary]=[]
var drag_axes: Array[Vector3]=[]
var drag_length := 1.
var weight_before: Dictionary={}
var weight_after: Dictionary={}
var touched: Dictionary={}
var geometry_cache: Dictionary={}
var stroke_geometry: Dictionary={}
var last_paint := 0
var hover_hit: Dictionary={}
var compare_rest := false
var stroke_session: KiwiModelSession
var weight_tool := "Brush"
var selected_only := false
var region: Dictionary={}
var region_start := Vector2.ZERO
var region_additive := false

func sync() -> void:
	var live := {}; var document := canvas.session.document
	var active := editor.rig() if editor.enabled else null
	if active!=null and chain_parent>=active.bones.size(): chain=null; chain_parent=-1; placing=false
	for armature in document.components:
		if not armature.is_skeleton: continue
		KiwiRigMath.ensure(armature); live[armature.id]=true
		var rest_hash := hash(armature.bones.map(func(bone: Dictionary): return [bone.name,bone.parent,bone.rest]))
		if not nodes.has(armature.id) or signatures.get(armature.id)!=rest_hash:
			if nodes.has(armature.id): nodes[armature.id].free()
			var skeleton := ActorSkeletonRigRuntime.create_skeleton(armature.bones); canvas.world.add_child(skeleton); nodes[armature.id]=skeleton; signatures[armature.id]=rest_hash
		var skeleton: Skeleton3D=nodes[armature.id]; skeleton.transform=document.world_transform(armature)
		var rest_mode := compare_rest or (editor.enabled and editor.rig_id==armature.id and editor.mode in ["Edit","Draw","Envelope"])
		for i in armature.bones.size():
			var bone := armature.bones[i]; var rest: Transform3D=bone.rest
			skeleton.set_bone_pose_position(i,rest.origin if rest_mode else bone.position)
			skeleton.set_bone_pose_rotation(i,rest.basis.get_rotation_quaternion() if rest_mode else Quaternion.from_euler((bone.rotation as Vector3)*PI/180.))
			skeleton.set_bone_pose_scale(i,rest.basis.get_scale() if rest_mode else bone.scale)
		skeleton.force_update_all_bone_transforms()
	for id in nodes.keys():
		if not live.has(id): nodes[id].free(); nodes.erase(id); signatures.erase(id)
	for item in document.components:
		if not canvas.visuals.has(item.id): continue
		var visual: MeshInstance3D=canvas.visuals[item.id]
		if visual is KiwiSurfaceGrowthInstance:
			visual.growth_skeleton=nodes.get(item.skeleton_id); visual.update_growth(); continue
		if not nodes.has(item.skeleton_id):
			visual.skin=null; visual.skeleton=NodePath(); visual.material_override=null; heat_signature.erase(item.id); continue
		var armature := document.component(item.skeleton_id); var skeleton: Skeleton3D=nodes[item.skeleton_id]
		if item.binding==null:
			visual.material_override=null; heat_signature.erase(item.id)
			if item.skin_mesh!=null: visual.skin=item.skin; visual.skeleton=visual.get_path_to(skeleton)
			continue
		if not item.binding.rigid_bone_id.is_empty():
			visual.skin=null; visual.skeleton=NodePath(); visual.material_override=null; heat_signature.erase(item.id)
			for i in armature.bones.size():
				if str(armature.bones[i].id)==item.binding.rigid_bone_id: visual.transform=skeleton.transform*skeleton.get_bone_global_pose(i)*item.binding.attachment_offset
			continue
		visual.transform=skeleton.transform; visual.skin=item.skin; visual.skeleton=visual.get_path_to(skeleton)
		var heat := editor.enabled and editor.mode=="Weight" and item.skeleton_id==editor.rig_id
		var bone := item.binding.bone_ids.find(str(armature.bones[editor.selected_bone].id)) if heat and not armature.bones.is_empty() else -1
		var signature := hash([item.skin_mesh,item.binding.revision,bone])
		if heat_signature.get(item.id)!=signature:
			visual.mesh=item.binding.render_mesh(bone) if heat else item.skin_mesh; heat_signature[item.id]=signature
		if heat:
			var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo=true; visual.material_override=material
		else: visual.material_override=null
	for id in geometry_cache.keys():
		if not canvas.visuals.has(id): geometry_cache.erase(id)

func world_bones() -> Array[Transform3D]:
	var armature := editor.rig()
	if armature==null: return []
	var pose := editor.mode in ["Pose","Weight"] and not compare_rest
	var result := KiwiRigMath.globals(armature.bones,pose); var transform := canvas.session.document.world_transform(armature)
	for i in result.size(): result[i]=transform*result[i]
	return result

func pick_bone(point: Vector2, joints_only: bool=false) -> Dictionary:
	if not editor.show_bones and editor.mode!="Draw": return {}
	var armature := editor.rig()
	if armature==null: return {}
	var world := world_bones(); var best := 11.; var result := {}
	for i in world.size():
		var end := KiwiRigMath.tail(armature.bones[i],world[i])
		for endpoint in [false,true]:
			var p := end if endpoint else world[i].origin
			if canvas.camera.is_position_behind(p): continue
			var distance := canvas.project(p).distance_to(point)
			if distance<best: best=distance; result={"bone":i,"end":endpoint}
	if not result.is_empty() or joints_only: return result
	for i in world.size():
		var end := KiwiRigMath.tail(armature.bones[i],world[i])
		if canvas.camera.is_position_behind(world[i].origin) or canvas.camera.is_position_behind(end): continue
		var distance := Geometry2D.get_closest_point_to_segment(point,canvas.project(world[i].origin),canvas.project(end)).distance_to(point)
		if distance<best: best=distance; result={"bone":i,"end":false,"line":true}
	return result

func plane_hit(point: Vector2, origin: Vector3, normal: Vector3) -> Variant:
	var ray := canvas.ray(point); var denominator := normal.dot(ray.direction)
	if absf(denominator)<.000001: return null
	var t: float=normal.dot(origin-ray.origin)/denominator
	return ray.origin+ray.direction*t if t>=0. else null

func placement(point: Vector2) -> Vector3:
	var snap := pick_bone(point,true)
	if not snap.is_empty():
		var world := world_bones(); return KiwiRigMath.tail(editor.rig().bones[snap.bone],world[snap.bone]) if snap.end else world[snap.bone].origin
	var anchor := editor.bounds().get_center(); var normal := canvas.camera.basis.z
	if construction in ["Inside mesh","Surface"]:
		var hit := canvas.pick(point)
		if not hit.is_empty():
			if construction=="Surface": return hit.point
			var visual: MeshInstance3D=canvas.visuals[hit.id]; var ray := canvas.ray(point); var inverse := visual.transform.affine_inverse()
			var geometry := visual.mesh.generate_triangle_mesh()
			var far: Vector3=hit.point+ray.direction*(visual.get_aabb().size.length()*visual.global_basis.get_scale().length()+1.)
			var exit := geometry.intersect_ray(inverse*far,(-(inverse.basis*ray.direction)).normalized())
			if not exit.is_empty(): return (hit.point as Vector3).lerp(visual.transform*exit.position,.5)
			return hit.point
	elif construction=="XY": normal=Vector3.BACK; anchor.z=depth
	elif construction=="YZ": normal=Vector3.RIGHT; anchor.x=depth
	elif construction=="XZ": normal=Vector3.UP; anchor.y=depth
	if construction=="View plane": anchor+=normal*depth
	var value: Variant=plane_hit(point,anchor,normal)
	return value if value is Vector3 else anchor

func handles() -> Dictionary:
	var world := world_bones()
	if world.is_empty(): return {}
	var origin := world[editor.selected_bone].origin
	if canvas.camera.is_position_behind(origin): return {}
	var distance := maxf(.001,-(canvas.camera.global_transform.affine_inverse()*origin).z)
	var point := canvas.camera.unproject_position(origin); var length := canvas.camera.project_position(point+Vector2(75,0),distance).distance_to(origin)
	var axes: Array[Vector3]=[Vector3.RIGHT,Vector3.UP,Vector3.BACK]; var rings: Array[PackedVector2Array]=[]; var ends := PackedVector2Array()
	if canvas.tool=="Scale":
		var basis := world[editor.selected_bone].basis.orthonormalized(); axes.assign([basis.x,basis.y,basis.z])
	for i in 3:
		ends.append(canvas.project(origin+axes[i]*length)); var ring := PackedVector2Array()
		for j in 65: ring.append(canvas.project(origin+(axes[(i+1)%3]*cos(j*TAU/64.)+axes[(i+2)%3]*sin(j*TAU/64.))*length*.8))
		rings.append(ring)
	return {"origin":origin,"center":canvas.project(origin),"length":length,"axes":axes,"ends":ends,"rings":rings}

func handle_at(point: Vector2, geometry: Dictionary) -> int:
	if geometry.is_empty(): return -2
	if canvas.tool!="Rotate" and point.distance_to(geometry.center)<8.: return -1
	var best := 8.; var result := -2
	for i in 3:
		if canvas.tool=="Rotate":
			for j in 64:
				var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,geometry.rings[i][j],geometry.rings[i][j+1]))
				if distance<best: best=distance; result=i
		else:
			var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,geometry.center.lerp(geometry.ends[i],.3),geometry.ends[i]))
			if distance<best: best=distance; result=i
	return result

func draw() -> void:
	if not editor.enabled: return
	var overlay := canvas.overlay; var armature := editor.rig(); var world := world_bones()
	if armature!=null and editor.show_bones:
		var chain_set := KiwiRigMath.descendants(armature,editor.selected_bone) if not armature.bones.is_empty() else PackedInt32Array()
		for i in world.size():
			if editor.only_chain and not chain_set.has(i): continue
			var end := KiwiRigMath.tail(armature.bones[i],world[i]); var start := world[i].origin
			if canvas.camera.is_position_behind(start) or canvas.camera.is_position_behind(end): continue
			var a := canvas.project(start); var b := canvas.project(end); var color := Color("ffce80") if i==editor.selected_bone else Color("79dfc5")
			overlay.draw_line(a,b,Color("0c1721"),7,true); overlay.draw_line(a,b,color,3,true)
			for p in [a,b]: overlay.draw_circle(p,6,Color("0c1721")); overlay.draw_circle(p,3.5,color)
			if i==editor.selected_bone:
				overlay.draw_string(ThemeDB.fallback_font,b+Vector2(8,-8),str(armature.bones[i].name),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
				if editor.mode=="Envelope":
					var radius := float(armature.bones[i].radius); var center := start.lerp(end,.5); var pixels := canvas.project(center+canvas.camera.basis.x*radius).distance_to(canvas.project(center))
					overlay.draw_arc(canvas.project(center),pixels,0,TAU,48,Color("7bc8ff"),2,true)
		var geometry := handles()
		if not geometry.is_empty() and editor.mode in ["Pose","Weight"]:
			for i in 3:
				var color: Color=canvas.COLORS[i]
				if canvas.tool=="Rotate": overlay.draw_polyline(geometry.rings[i],color,2.,true)
				else: overlay.draw_line(geometry.center,geometry.ends[i],color,2.5,true); overlay.draw_circle(geometry.ends[i],5,color)
	if editor.mode=="Draw":
		var p := canvas.project(cursor); overlay.draw_circle(p,5,Color("ffce80")); overlay.draw_arc(p,8,0,TAU,24,Color("0c1721"),2,true)
		if chain is Vector3:
			overlay.draw_line(canvas.project(chain),p,Color("ffce80"),2,true)
		overlay.draw_string(ThemeDB.fallback_font,Vector2(12,24),"Draw: "+construction+" · click / release joints · Enter ends chain · RMB cancels point",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffe0a1"))
	elif editor.mode=="Weight":
		var radius := brush_radius*75./maxf(.0001,float(handles().get("length",1.)))
		overlay.draw_arc(mouse,clampf(radius,3.,600.),0,TAU,64,Color("f3f5ff"),1.5,true)
		overlay.draw_string(ThemeDB.fallback_font,Vector2(12,24),"Weight: "+brush_mode+" · Shift+wheel radius · Ctrl subtracts · W/E/R pose handles",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("b7e5ff"))
		var region_geometry := {}; var rig_transform := canvas.session.document.world_transform(armature) if armature!=null else Transform3D.IDENTITY
		for key: String in region:
			var entry: Dictionary=region[key]; var item := canvas.session.document.component(str(entry.id))
			if item==null or item.binding==null or armature==null or item.skeleton_id!=armature.id: continue
			if not region_geometry.has(item.id): region_geometry[item.id]=_paint_geometry(item)
			var geometry: Dictionary=region_geometry[item.id]; var point: Vector3=rig_transform*geometry.points[entry.surface][entry.vertex]
			if not canvas.camera.is_position_behind(point): overlay.draw_circle(canvas.project(point),3,Color.WHITE)
		if drag=="region":
			var rect := Rect2(region_start,mouse-region_start).abs(); overlay.draw_rect(rect,Color(.3,.7,1,.15)); overlay.draw_rect(rect,Color("9bdcff"),false,1.)
	else: overlay.draw_string(ThemeDB.fallback_font,Vector2(12,24),"Rig "+editor.mode+" · drag joints · W/E/R pose tools · Esc cancels · Delete bone",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("b7e5ff"))

func begin_joint(index: int, end: bool, point: Vector2) -> void:
	if not editor.can_edit_rest(): canvas.gesture_finished.emit(); return
	editor.selected_bone=index; var world := world_bones(); var armature := editor.rig()
	drag="joint"; drag_end=end; drag_origin=KiwiRigMath.tail(armature.bones[index],world[index]) if end else world[index].origin
	drag_normal=canvas.camera.basis.z; drag_point=plane_hit(point,drag_origin,drag_normal); drag_mouse=point; canvas.session.begin(); canvas._pressed=true

func begin_pose(index: int, point: Vector2) -> bool:
	var geometry := handles()
	if geometry.is_empty(): return false
	drag="pose"; drag_axis=index; drag_origin=geometry.origin; drag_length=geometry.length; drag_mouse=point
	drag_axes.assign(geometry.axes)
	drag_normal=geometry.axes[index] if canvas.tool=="Rotate" and index>=0 else canvas.camera.basis.z
	var value: Variant=plane_hit(point,drag_origin,drag_normal)
	if value==null: drag=""; return false
	drag_point=value; drag_before=editor.rig().bones.duplicate(true); canvas.session.begin(); canvas._pressed=true; return true

func update_drag(point: Vector2, snap: bool=false) -> void:
	var armature := editor.rig(); var value: Variant=plane_hit(point,drag_origin,drag_normal)
	if value==null or armature==null: return
	if drag=="joint":
		var next: Vector3=drag_origin+value-drag_point
		if snap: next=next.snapped(Vector3.ONE*canvas.grid_step)
		editor.move_joint(editor.selected_bone,drag_end,canvas.session.document.world_transform(armature).affine_inverse()*next)
	elif drag=="envelope":
		var inverse := canvas.session.document.world_transform(armature).affine_inverse()
		armature.bones[editor.selected_bone].radius=maxf(.001,(inverse*value).distance_to(inverse*drag_origin)); canvas.session.changed.emit()
	elif drag=="pose":
		var bone := armature.bones[editor.selected_bone]; var original: Dictionary=drag_before[editor.selected_bone]; var world := KiwiRigMath.globals(drag_before,true)
		var parent := canvas.session.document.world_transform(armature)
		if int(bone.parent)>=0: parent*=world[int(bone.parent)]
		var axis: Vector3=drag_axes[maxi(0,drag_axis)]
		if canvas.tool=="Move":
			var delta: Vector3=value-drag_point
			if drag_axis>=0: delta=axis*delta.dot(axis)
			if snap: delta=delta.snapped(Vector3.ONE*.1)
			bone.position=(original.position as Vector3)+parent.basis.inverse()*delta
		elif canvas.tool=="Rotate":
			var angle := (drag_point-drag_origin).normalized().signed_angle_to((value-drag_origin).normalized(),axis)
			if snap: angle=snappedf(angle,PI/12.)
			bone.rotation=(Basis((parent.basis.inverse()*axis).normalized(),angle)*Basis.from_euler((original.rotation as Vector3)*PI/180.)).get_euler()*180./PI
		else:
			var factor := maxf(.01,1.+(point.x-drag_mouse.x-point.y+drag_mouse.y)/140.)
			if drag_axis>=0:
				var projected := canvas.project(drag_origin+axis*drag_length)-canvas.project(drag_origin)
				if projected.length_squared()>100.: factor=maxf(.01,1.+(point-drag_mouse).dot(projected)/projected.length_squared())
			if snap: factor=maxf(.01,snappedf(factor,.1))
			var scaling := Vector3.ONE*factor
			if drag_axis>=0: scaling=Vector3.ONE; scaling[drag_axis]=factor
			bone.scale=original.scale*scaling
		canvas.session.changed.emit()

func _paint_geometry(item: KiwiModelComponent) -> Dictionary:
	if drag=="weight" and stroke_geometry.has(item.id): return stroke_geometry[item.id]
	var armature := editor.rig(); var key := hash([item.binding,item.binding.revision,compare_rest,armature.bones.map(func(bone: Dictionary): return [bone.rest,bone.position,bone.rotation,bone.scale])])
	if geometry_cache.has(item.id) and geometry_cache[item.id].key==key:
		if drag=="weight": stroke_geometry[item.id]=geometry_cache[item.id]
		return geometry_cache[item.id]
	var surfaces: Array[PackedVector3Array]=[]; var triangles := PackedVector3Array(); var faces: Array[Dictionary]=[]
	for surface in item.binding.source_mesh.get_surface_count():
		var points: PackedVector3Array=item.binding.mesh_to_rig*(item.binding.source_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array) if compare_rest else item.binding.deformed_points(armature,surface); surfaces.append(points)
		var arrays := item.binding.source_mesh.surface_get_arrays(surface); var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		for i in (ids.size() if not ids.is_empty() else points.size()): triangles.append(points[ids[i] if not ids.is_empty() else i])
		for i in range(0,ids.size() if not ids.is_empty() else points.size(),3):
			faces.append({"surface":surface,"vertices":PackedInt32Array([ids[i],ids[i+1],ids[i+2]]) if not ids.is_empty() else PackedInt32Array([i,i+1,i+2])})
	var mesh := TriangleMesh.new(); mesh.create_from_faces(triangles)
	var value := {"key":key,"points":surfaces,"mesh":mesh,"faces":faces}; geometry_cache[item.id]=value
	if drag=="weight": stroke_geometry[item.id]=value
	return value

func paint(point: Vector2, subtract: bool=false, force: bool=false) -> void:
	if compare_rest: editor.message="Turn off Compare rest before painting the posed mesh."; return
	if not force and Time.get_ticks_msec()-last_paint<33: return
	last_paint=Time.get_ticks_msec(); var armature := editor.rig()
	if armature==null or armature.bones.is_empty(): return
	var transform := canvas.session.document.world_transform(armature); var inverse := transform.affine_inverse(); var ray := canvas.ray(point); var best := INF; var chosen: KiwiModelComponent; var hitpoint := Vector3.ZERO
	for item in editor.meshes():
		if item.binding==null or item.skeleton_id!=armature.id or not item.binding.rigid_bone_id.is_empty(): continue
		var geometry := _paint_geometry(item); var hit: Dictionary=geometry.mesh.intersect_ray(inverse*ray.origin,(inverse.basis*ray.direction).normalized())
		if not hit.is_empty() and (transform*hit.position).distance_to(ray.origin)<best: chosen=item; hitpoint=transform*hit.position; best=hitpoint.distance_to(ray.origin)
	if chosen==null: return
	hover_hit={"point":hitpoint}; var data := _paint_geometry(chosen); var binding := chosen.binding; var index := binding.bone_ids.find(str(armature.bones[editor.selected_bone].id))
	if index<0: return
	for surface in data.points.size():
		var changes := {}
		for v in (data.points[surface] as PackedVector3Array).size():
			var position: Vector3=transform*data.points[surface][v]; var distance := position.distance_to(hitpoint)
			if distance>brush_radius or (not paint_hidden and position.distance_to(ray.origin)>best+brush_radius*.15): continue
			var key := "%s:%d:%d"%[chosen.id,surface,v]; var old := binding.vertex(surface,v)
			if selected_only and not region.has(key): continue
			var falloff := smoothstep(1.,0.,distance/brush_radius); var amount := brush_strength*falloff
			if brush_mode=="Replace": amount=lerpf(float(old.get(index,0.)),brush_value,amount)
			var average := {}
			if brush_mode=="Smooth":
				var graph := binding.topology(); var welded: int=graph.surfaces[surface][v]
				for u: int in graph.neighbors[welded]:
					var representative: Vector2i=graph.representatives[u]; var nearby := binding.vertex(representative.x,representative.y)
					for b: int in nearby: average[b]=float(average.get(b,0.))+float(nearby[b])
				average=binding.normalized(average)
			var next := KiwiRigWeighting.corrected(binding,surface,v,index,"Subtract" if subtract else brush_mode,amount,average)
			if next==old: continue
			if not weight_before.has(key): weight_before[key]={"id":chosen.id,"surface":surface,"vertex":v,"values":old}
			changes[v]=next; weight_after[key]={"id":chosen.id,"surface":surface,"vertex":v,"values":next}; touched[chosen.id]=true
		if not changes.is_empty(): binding.assign_vertices(surface,changes)
	canvas.session.changed.emit()

func finish(cancel: bool=false) -> void:
	if drag.is_empty(): return
	if drag=="region":
		if not cancel: select_region(Rect2(region_start,mouse-region_start).abs(),region_additive)
	elif drag=="weight":
		if cancel: KiwiRigEditor.apply_weight_patch(stroke_session,weight_before)
		elif not weight_before.is_empty():
			for id in touched:
				var item := stroke_session.document.component(id); item.skin_mesh=item.binding.render_mesh()
			stroke_session.custom_action("Paint skin weights",KiwiRigEditor.apply_weight_patch.bind(weakref(stroke_session),weight_before.duplicate(true)),KiwiRigEditor.apply_weight_patch.bind(weakref(stroke_session),weight_after.duplicate(true)),weight_before.size())
		weight_before={}; weight_after={}; touched={}; stroke_session=null; stroke_geometry.clear()
	elif not drag.is_empty():
		if cancel: canvas.session.cancel()
		else: canvas.session.commit("Pose bone" if drag=="pose" else ("Resize bone envelope" if drag=="envelope" else "Move rig joint"))
	drag=""; canvas._pressed=false; canvas.gesture_finished.emit(); canvas.request_sync()

func handle_event(event: InputEvent) -> bool:
	if not editor.enabled: return false
	if event is InputEventMouseMotion:
		mouse=event.position
		if not drag.is_empty():
			if drag=="region": pass
			elif drag=="weight": paint(mouse,event.ctrl_pressed)
			else: update_drag(mouse,canvas.snap!=event.ctrl_pressed)
			return true
		if editor.mode=="Draw": cursor=placement(mouse)
		return false
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			if not drag.is_empty(): finish(true); return true
			if placing: placing=false; return true
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and event.shift_pressed and editor.mode=="Weight":
			brush_radius=clampf(brush_radius*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1./1.15),.005,100.); canvas.gesture_finished.emit(); return true
		if event.button_index!=MOUSE_BUTTON_LEFT: return false
		canvas.grab_focus()
		if editor.mode=="Draw":
			if event.pressed: placing=true; cursor=placement(event.position)
			elif placing:
				placing=false; var endpoint := placement(event.position); var armature := editor.rig()
				if chain is Vector3 and (chain as Vector3).distance_to(endpoint)>.005:
					var inverse := canvas.session.document.world_transform(armature).affine_inverse()
					editor.add(inverse*chain,inverse*endpoint,chain_parent); chain_parent=editor.selected_bone
				else:
					var joint := pick_bone(event.position,true); chain_parent=int(joint.bone) if not joint.is_empty() and joint.end else (int(armature.bones[joint.bone].parent) if not joint.is_empty() else -1)
				chain=endpoint; canvas.gesture_finished.emit()
			return true
		if not event.pressed:
			mouse=event.position
			if not drag.is_empty(): finish(); return true
			return true
		var selected := pick_bone(event.position,true)
		if not selected.is_empty() and int(selected.bone)!=editor.selected_bone:
			editor.selected_bone=int(selected.bone); canvas.gesture_finished.emit(); return true
		if editor.show_bones and editor.mode in ["Pose","Weight"]:
			var handle := handle_at(event.position,handles())
			if handle!=-2: begin_pose(handle,event.position); return true
		if editor.mode=="Weight":
			if weight_tool!="Brush": drag="region"; region_start=event.position; mouse=event.position; region_additive=event.ctrl_pressed or event.shift_pressed; canvas._pressed=true; return true
			drag="weight"; stroke_session=canvas.session; canvas._pressed=true; paint(event.position,event.ctrl_pressed,true); return true
		if editor.mode=="Envelope" and not handles().is_empty():
			var world := world_bones(); var armature := editor.rig(); var center := world[editor.selected_bone].origin.lerp(KiwiRigMath.tail(armature.bones[editor.selected_bone],world[editor.selected_bone]),.5)
			var pixels := canvas.project(center+canvas.camera.basis.x*float(armature.bones[editor.selected_bone].radius)).distance_to(canvas.project(center))
			if absf(event.position.distance_to(canvas.project(center))-pixels)<10.:
				drag="envelope"; drag_origin=center; drag_normal=canvas.camera.basis.z; canvas.session.begin(); canvas._pressed=true; return true
		selected=pick_bone(event.position)
		if not selected.is_empty():
			editor.selected_bone=int(selected.bone)
			if editor.mode=="Edit" and not selected.get("line",false): begin_joint(editor.selected_bone,bool(selected.end),event.position)
			canvas.gesture_finished.emit(); return true
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if not drag.is_empty(): finish(true)
			else: chain=null; placing=false
			return true
		if event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y]:
			chain=null; chain_parent=-1; placing=false
			if not drag.is_empty(): finish(true)
			elif event.keycode==KEY_Y or event.shift_pressed: canvas.session.redo()
			else: canvas.session.undo()
			return true
		if event.keycode==KEY_ENTER and editor.mode=="Draw": chain=null; placing=false; return true
		if not drag.is_empty(): return true
		if event.keycode in [KEY_DELETE,KEY_BACKSPACE]: editor.delete_bone(); canvas.gesture_finished.emit(); return true
	return false

func select_region(rect: Rect2, additive: bool=false) -> void:
	if not additive: region.clear()
	var armature := editor.rig()
	if armature==null: return
	var transform := canvas.session.document.world_transform(armature); var inverse := transform.affine_inverse(); var click := rect.size.length()<5.
	for item in editor.meshes():
		if item.binding==null or not item.binding.rigid_bone_id.is_empty() or item.skeleton_id!=armature.id: continue
		var geometry := _paint_geometry(item)
		if weight_tool=="Select faces" and click:
			var ray := canvas.ray(rect.position); var hit: Dictionary=geometry.mesh.intersect_ray(inverse*ray.origin,(inverse.basis*ray.direction).normalized())
			if hit.is_empty() or not hit.has("face_index"): continue
			var face: Dictionary=geometry.faces[int(hit.face_index)]
			for v: int in face.vertices: region["%s:%d:%d"%[item.id,int(face.surface),v]]={"id":item.id,"surface":int(face.surface),"vertex":v}
			continue
		for surface in geometry.points.size():
			for v in (geometry.points[surface] as PackedVector3Array).size():
				var point: Vector3=transform*geometry.points[surface][v]
				if canvas.camera.is_position_behind(point): continue
				var projected := canvas.project(point)
				var included := projected.distance_to(rect.position)<10. if click else rect.has_point(projected)
				if included: region["%s:%d:%d"%[item.id,surface,v]]={"id":item.id,"surface":surface,"vertex":v}
	canvas.overlay.queue_redraw()

func fill_region() -> void:
	var armature := editor.rig(); var before := {}; var after := {}
	if armature==null or armature.bones.is_empty(): return
	if region.is_empty(): editor.message="Select vertices or faces before assigning weights."; return
	for key: String in region:
		var entry: Dictionary=region[key]; var item := canvas.session.document.component(str(entry.id))
		if item==null or item.binding==null or item.skeleton_id!=armature.id: continue
		var bone := item.binding.bone_ids.find(str(armature.bones[editor.selected_bone].id)); var old := item.binding.vertex(entry.surface,entry.vertex)
		var next := KiwiRigWeighting.corrected(item.binding,entry.surface,entry.vertex,bone,"Replace",brush_value)
		if old==next: continue
		before[key]={"id":item.id,"surface":entry.surface,"vertex":entry.vertex,"values":old}; after[key]={"id":item.id,"surface":entry.surface,"vertex":entry.vertex,"values":next}
	if after.is_empty(): return
	KiwiRigEditor.apply_weight_patch(canvas.session,after)
	canvas.session.custom_action("Assign selected vertex weights",KiwiRigEditor.apply_weight_patch.bind(weakref(canvas.session),before),KiwiRigEditor.apply_weight_patch.bind(weakref(canvas.session),after),before.size())
