extends Node
## Editor overlay only: no collision bodies, actor mutations on selection, or
## renderable scene geometry. Works through the viewport's letterboxed display.
var gizmo:Variant
var editor:ActorTimelineEditor
var mode:="move"
var batch:=ActorPropertyBatch.new()
var before:Array[Dictionary]=[]
var originals:Dictionary={}
var final_values:Dictionary={}
var selection:Array[String]=[]
var sample_time:=0.
var drag_axis:=-1
var start_mouse:=Vector2.ZERO
var pivot:=Vector3.ZERO
var axis:=Vector3.RIGHT
var plane_normal:=Vector3.FORWARD
var start_point:=Vector3.ZERO
var start_vector:=Vector3.RIGHT
var drag_length:=1.
var rig:=preload("res://scripts/actors/core/actor_skeleton_gizmo.gd").new()
var physics_pins:=preload("res://scripts/actors/physics/physics_pin_gizmo.gd").new()
const COLORS=[Color("f27e81"),Color("84dc9e"),Color("80baff")]
const EDGES=[[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]
const PROXIES=[&"point_3d",&"remote_transform",&"light_3d",&"directional_light",&"skeleton_rig"]

func _ready()->void: rig.spatial=self; physics_pins.spatial=self

func camera()->Camera3D:
	return editor.runtime_holder.get_viewport().get_camera_3d() if is_instance_valid(editor) and is_instance_valid(editor.runtime_holder) else null
func enabled()->bool:
	return is_instance_valid(editor) and not editor.exporting and not editor.audio_recorder.recording and not editor.screen_recorder.recording
func primary()->ActorRuntime:
	var clip:=editor.model.selected_clip() if enabled() else null
	var runtime:=editor._runtime_for_clip(clip.id) if clip!=null else null
	if runtime==null or not runtime.active or runtime is ActorUIRuntime or not runtime.supports_remote_transform():return null
	var definition:=editor.registry.get_definition(runtime.actor.type_id)
	return runtime if definition!=null and definition.find_property(&"position")!=null else null
func project(point:Vector3)->Vector2:
	return gizmo.display_transform()*camera().unproject_position(point)
func in_picture(point:Vector2)->bool:
	if not is_instance_valid(editor.runtime_holder):return false
	return Rect2(Vector2.ZERO,Vector2(editor.runtime_holder.get_viewport().get_visible_rect().size)).has_point(gizmo.scene_point(point))
func _visuals(node:Node,result:Array[VisualInstance3D],root:bool=true)->void:
	if not root and node is ActorRuntime:return # Child actors own their bounds.
	if node is VisualInstance3D and node.is_visible_in_tree() and not node is Light3D:
		if (node.layers&camera().cull_mask)!=0:result.append(node)
	for child in node.get_children():_visuals(child,result,false)
func visuals(runtime:ActorRuntime)->Array[VisualInstance3D]:
	var result:Array[VisualInstance3D]=[]
	if runtime!=null and runtime.active and camera()!=null:_visuals(runtime,result)
	return result
func bounds(runtime:ActorRuntime)->Dictionary:
	var result:AABB;var found:=false
	for visual in visuals(runtime):
		var local:=visual.get_aabb()
		if not local.position.is_finite() or not local.size.is_finite():continue
		var box:AABB=visual.global_transform*local
		result=result.merge(box) if found else box;found=true
	if not found and runtime!=null and runtime.actor.type_id in PROXIES:
		var origin:=runtime.remote_transform().origin;result=AABB(origin-Vector3.ONE*.15,Vector3.ONE*.3);found=true
	return {"box":result} if found else {}
func box_lines(runtime:ActorRuntime)->Array[PackedVector2Array]:
	var result:Array[PackedVector2Array]=[];var data:=bounds(runtime);var lens:=camera()
	if data.is_empty() or lens==null:return result
	var box:AABB=data.box;var corners:Array[Vector3]=[]
	for i in 8:corners.append(box.position+box.size*Vector3(i&1,(i>>1)&1,(i>>2)&1))
	var inverse:=lens.global_transform.affine_inverse()
	for edge in EDGES:
		var a:Vector3=corners[edge[0]];var b:Vector3=corners[edge[1]]
		var da:float=-(inverse*a).z;var db:float=-(inverse*b).z;var near:=lens.near+.001
		if da<near and db<near:continue
		if da<near:a=a.lerp(b,(near-da)/(db-da))
		elif db<near:b=b.lerp(a,(near-db)/(da-db))
		result.append(PackedVector2Array([project(a),project(b)]))
	return result
func _ray(point:Vector2)->Dictionary:
	var p:Vector2=gizmo.scene_point(point);var lens:=camera()
	return {"origin":lens.project_ray_origin(p),"direction":lens.project_ray_normal(p)}
func _hit_visual(visual:VisualInstance3D,ray:Dictionary)->Variant:
	var transform:=visual.global_transform
	if absf(transform.basis.determinant())<.0000001:return null
	var inverse:=transform.affine_inverse();var origin:Vector3=inverse*ray.origin;var direction:Vector3=(inverse.basis*ray.direction).normalized()
	var hit:Variant=visual.get_aabb().intersects_ray(origin,direction)
	if hit==null:return null
	if visual is MeshInstance3D and visual.mesh!=null:
		var mesh:Mesh=visual.mesh;var triangles:=mesh is PrimitiveMesh;var vertices:=0
		for i in mesh.get_surface_count():
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(i)==Mesh.PRIMITIVE_TRIANGLES:triangles=true
			var arrays:=mesh.surface_get_arrays(i)
			if arrays.size()>Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]!=null:vertices+=arrays[Mesh.ARRAY_VERTEX].size()
		# Godot caches the triangle BVH on the mesh. Bound a first-click build
		# for unusually large imports; their AABB remains usable for picking.
		if triangles and vertices<=150000:
			var geometry:=mesh.generate_triangle_mesh()
			if geometry!=null:
				var narrow:=geometry.intersect_ray(origin,direction)
				if narrow.is_empty():return null
				hit=narrow.position
	return transform*(hit as Vector3)
func pick(point:Vector2)->String:
	if not enabled() or camera()==null or not in_picture(point):return ""
	var ray:=_ray(point);var best:=INF;var chosen:="";var lens:=camera()
	for clip in editor.model.clips:
		var runtime:=editor._runtime_for_clip(clip.id)
		if runtime==null or not runtime.active or runtime is ActorUIRuntime:continue
		var owned:=visuals(runtime)
		for visual in owned:
			var hit:Variant=_hit_visual(visual,ray)
			if hit==null or lens.is_position_behind(hit):continue
			var depth:float=(lens.global_transform.affine_inverse()*(hit as Vector3)).z
			if -depth<lens.near or -depth>lens.far:continue
			var distance:float=ray.origin.distance_to(hit)
			if distance<best:best=distance;chosen=clip.id
		if owned.is_empty() and runtime.actor.type_id in PROXIES:
			var origin:=runtime.remote_transform().origin
			if lens.is_position_behind(origin):continue
			if project(origin).distance_to(point)<12 and ray.origin.distance_to(origin)<best:best=ray.origin.distance_to(origin);chosen=clip.id
	return chosen
func geometry()->Dictionary:
	var runtime:=primary();var lens:=camera()
	if runtime==null or lens==null:return {}
	var origin:=runtime.remote_transform().origin
	if rig.active(): origin=rig.transform().origin
	if lens.is_position_behind(origin):return {}
	var depth:float=-(lens.global_transform.affine_inverse()*origin).z
	if depth<lens.near:return {}
	var ratio:float=gizmo.display_transform().get_scale().x
	var length:float=lens.project_position(lens.unproject_position(origin)+Vector2(0,88/maxf(.001,ratio)),depth).distance_to(origin)
	var axes:Array[Vector3]=[Vector3.RIGHT,Vector3.UP,Vector3.BACK]
	if mode=="scale":
		var basis:=runtime.remote_transform().basis
		if rig.active(): basis=rig.transform().basis
		basis=basis.orthonormalized() if absf(basis.determinant())>.0000001 else Basis.IDENTITY
		axes=[basis.x,basis.y,basis.z]
	var rings:Array[PackedVector2Array]=[];var endpoints:PackedVector2Array=[]
	for i in 3:
		endpoints.append(project(origin+axes[i]*length))
		var points:=PackedVector2Array();var u:Vector3=axes[(i+1)%3];var v:Vector3=axes[(i+2)%3]
		for j in 65:points.append(project(origin+(u*cos(TAU*j/64.)+v*sin(TAU*j/64.))*length*.8))
		rings.append(points)
	return {"origin":origin,"center":project(origin),"length":length,"axes":axes,"ends":endpoints,"rings":rings}
func toolbar_rect(index:int)->Rect2:return Rect2(10+index*78,10,74,27)
func handle_at(point:Vector2,data:Dictionary)->int:
	if data.is_empty():return -2
	if mode!="rotate" and point.distance_to(data.center)<10:return -1
	var best:=9.;var chosen:=-2
	for i in 3:
		if mode=="rotate":
			var points:PackedVector2Array=data.rings[i]
			for j in points.size()-1:
				var distance:=Geometry2D.get_closest_point_to_segment(point,points[j],points[j+1]).distance_to(point)
				if distance<best:best=distance;chosen=i
		else:
			var a:Vector2=data.center;var b:Vector2=data.ends[i]
			if a.distance_to(b)<14:continue
			var distance:=Geometry2D.get_closest_point_to_segment(point,a.lerp(b,.25),b).distance_to(point)
			if distance<best:best=distance;chosen=i
	return chosen
func draw()->void:
	if not enabled() or camera()==null:return
	if physics_pins.active(): physics_pins.draw(); return
	for clip in editor.model.clips:
		var runtime:=editor._runtime_for_clip(clip.id)
		if runtime==null or not runtime.active or runtime is ActorUIRuntime:continue
		if editor.model.is_selected(clip.id):
			var color:=Color("ffd078") if clip.id==editor.model.selected_id else Color("80bdff")
			for line in box_lines(runtime):
				gizmo.draw_line(line[0],line[1],Color(0,0,0,.65),4,true);gizmo.draw_line(line[0],line[1],color,1.6,true)
		elif runtime.actor.type_id in PROXIES and not camera().is_position_behind(runtime.remote_transform().origin):
			var p:=project(runtime.remote_transform().origin)
			gizmo.draw_line(p-Vector2(5,0),p+Vector2(5,0),Color("8dacc0"),2,true);gizmo.draw_line(p-Vector2(0,5),p+Vector2(0,5),Color("8dacc0"),2,true)
	var data:=geometry()
	if data.is_empty():
		rig.draw()
		return
	for i in 3:
		var rect:=toolbar_rect(i);var selected:bool=mode==["move","rotate","scale"][i]
		gizmo.draw_rect(rect,Color("285c57") if selected else Color("152430"));gizmo.draw_rect(rect,Color("71d8be") if selected else Color("456172"),false,1)
		gizmo.draw_string(ThemeDB.fallback_font,rect.position+Vector2(6,18),["Move  W","Rotate  E","Scale  R"][i],HORIZONTAL_ALIGNMENT_LEFT,66,11,Color("e3f1f3"))
	for i in 3:
		var color:Color=COLORS[i]
		if mode=="rotate":gizmo.draw_polyline(data.rings[i],color,2.5,true)
		else:
			var a:Vector2=data.center;var b:Vector2=data.ends[i]
			if a.distance_to(b)<14:continue
			gizmo.draw_line(a,b,Color("10212d"),5,true);gizmo.draw_line(a,b,color,2.5,true)
			if mode=="scale":gizmo.draw_rect(Rect2(b-Vector2(5,5),Vector2(10,10)),color)
			else:
				var direction:Vector2=(b-a).normalized();var side:=direction.orthogonal()
				gizmo.draw_colored_polygon(PackedVector2Array([b+direction*4,b-direction*10+side*5,b-direction*10-side*5]),color)
			gizmo.draw_string(ThemeDB.fallback_font,b+Vector2(7,-5),["X","Y","Z"][i],HORIZONTAL_ALIGNMENT_LEFT,14,12,color)
	if mode!="rotate":gizmo.draw_rect(Rect2(data.center-Vector2(5,5),Vector2(10,10)),Color("f6db9a"))
	if not before.is_empty():gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,57),"Ctrl: snap  ·  Esc: cancel",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("f6db9a"))
	rig.draw()
func _plane_hit(point:Vector2)->Variant:
	var ray:=_ray(point);var denominator:float=plane_normal.dot(ray.direction)
	if absf(denominator)<.00001:return null
	var distance:float=plane_normal.dot(pivot-ray.origin)/denominator
	return ray.origin+ray.direction*distance if distance>=0 else null
func begin(index:int,point:Vector2)->bool:
	var data:=geometry()
	if data.is_empty():return false
	if editor.playing:editor.toggle_playback()
	pivot=data.origin;drag_length=data.length;drag_axis=index;start_mouse=point;sample_time=editor.canvas.playhead
	axis=data.axes[index] if index>=0 else Vector3.ZERO
	plane_normal=axis if mode=="rotate" else -camera().global_basis.z
	if mode=="move" and index>=0:
		plane_normal=(camera().global_position-pivot);plane_normal-=axis*plane_normal.dot(axis)
		if plane_normal.length()<.0001:return false
		plane_normal=plane_normal.normalized()
	var hit:Variant=_plane_hit(point)
	if hit==null:return false
	start_point=hit;start_vector=(start_point-pivot).normalized()
	if rig.active(): return rig.begin()
	batch.model=editor.model;batch.registry=editor.registry;originals.clear();final_values.clear();before.clear()
	var actors:Array[ActorData]=[];var selected:=editor.model.selected_actors()
	for actor in selected:
		var clip:=editor.model.clip_for_actor_id(actor.id);var runtime:=editor._runtime_for_clip(clip.id) if clip!=null else null
		if runtime==null or not runtime.active or runtime is ActorUIRuntime or not runtime.supports_remote_transform():continue
		var ancestor:=editor.model.actor_for_id(actor.parent_id);var nested:=false
		while ancestor!=null:
			var ancestor_clip:=editor.model.clip_for_actor_id(ancestor.id)
			var ancestor_runtime:=editor._runtime_for_clip(ancestor_clip.id) if ancestor_clip!=null else null
			if selected.has(ancestor) and ancestor_runtime!=null and ancestor_runtime.active and ancestor_runtime.supports_remote_transform():nested=true;break
			ancestor=editor.model.actor_for_id(ancestor.parent_id)
		if nested or absf(runtime.global_basis.determinant())<.0000001:continue
		var values:=ActorAnimation.sampled_values(actor,actor.animation_time)
		originals[actor.id]={"parent":runtime.global_transform,"position":values.get(&"position",Vector3.ZERO),"rotation":values.get(&"rotation",Vector3.ZERO),"scale":values.get(&"scale",Vector3.ONE),"world":runtime.remote_transform().origin}
		actors.append(actor)
	var keys:Array[StringName]=[&"position"]
	if mode=="rotate":keys.append(&"rotation")
	elif mode=="scale":keys.append(&"scale")
	for key in keys:before.append_array(batch.capture(actors,key))
	selection=editor.model.selected_ids.duplicate()
	if before.is_empty():return false
	gizmo.grab_focus();editor.hints.begin(gizmo,"Drag "+mode+" handle · Ctrl snaps · Esc cancels");return true
func update(point:Vector2,snap:bool=false)->void:
	if before.is_empty():return
	var hit:Variant=_plane_hit(point)
	if hit==null:return
	var delta:Vector3=hit-start_point
	if drag_axis>=0:delta=axis*delta.dot(axis)
	if snap:
		if drag_axis>=0:delta=axis*snappedf(delta.dot(axis),.1)
		else:delta=delta.snapped(Vector3.ONE*.1)
	var angle:=start_vector.signed_angle_to((hit-pivot).normalized(),axis) if mode=="rotate" else 0.
	if snap:angle=snappedf(angle,deg_to_rad(15))
	var amount:float=1.+(point.x-start_mouse.x-point.y+start_mouse.y)/140. if drag_axis<0 else 1.+(hit-start_point).dot(axis)/drag_length
	if snap:amount=snappedf(amount,.1)
	amount=maxf(.01,amount)
	for state in before:
		var origin:Dictionary=originals[state.actor.id];var parent:Transform3D=origin.parent;var value:Vector3=origin[state.key]
		if mode=="move":value=parent.affine_inverse()*(origin.world+delta)
		elif mode=="rotate":
			if state.key==&"position":value=parent.affine_inverse()*(pivot+Basis(axis,angle)*(origin.world-pivot))
			else:value=(parent.basis.inverse()*Basis(axis,angle)*parent.basis*Basis.from_euler((origin.rotation as Vector3)*PI/180.)).orthonormalized().get_euler()*180./PI
		elif state.key==&"position":
			var offset:Vector3=origin.world-pivot
			value=parent.affine_inverse()*(pivot+(offset*amount if drag_axis<0 else offset+axis*offset.dot(axis)*(amount-1)))
		else:
			if drag_axis<0:value*=amount
			else:value[drag_axis]*=amount
		final_values[str(state.actor.id)+":"+str(state.key)]=value
		editor.model.preview_property(state.actor,editor.registry.get_definition(state.actor.type_id),state.key,value)
func finish(cancel:bool=false)->void:
	if before.is_empty():return
	if cancel:batch.restore(before)
	elif not final_values.is_empty():
		var after:Array[Dictionary]=[];var modified:=false;editor.model.property_batch_active=true
		for state in before:
			var value:Variant=final_values.get(str(state.actor.id)+":"+str(state.key),originals[state.actor.id][state.key])
			if not (value as Vector3).is_equal_approx(originals[state.actor.id][state.key]):
				modified=true
				editor.model.commit_property_preview(state.actor,editor.registry.get_definition(state.actor.type_id),state.key,state.value,value)
			state.actor.animation_previews.erase(state.key)
			editor.model._audio_preview_before.erase(state.actor.id)
		editor.model.property_batch_active=false
		for state in before:after.append_array(batch.capture([state.actor],state.key))
		if modified:batch.commit(before,after,&"position" if mode=="move" else (&"rotation" if mode=="rotate" else &"scale"))
		else:batch.restore(before)
	# History owns the snapshot array after commit; do not clear it in place.
	before=[];originals.clear();final_values.clear();editor.hints.end(gizmo)
func sync()->void:
	rig.sync()
	if not before.is_empty() and (not enabled() or editor.model.selected_ids!=selection or not is_equal_approx(editor.canvas.playhead,sample_time)):finish(true)
func handle_event(event:InputEvent)->bool:
	if not enabled():return false
	if physics_pins.handle_event(event):return true
	if rig.handle_event(event):return true
	if not before.is_empty():
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:finish(true);return true
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:finish(true);return true
		if event is InputEventMouseMotion:update(event.position,event.ctrl_pressed);return true
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:finish();return true
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):return false
	var data:=geometry()
	if data.is_empty():return false
	if event is InputEventKey and event.pressed and not event.echo and gizmo.has_focus() and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var keys:Dictionary={KEY_W:"move",KEY_E:"rotate",KEY_R:"scale"}
		if keys.has(event.keycode):mode=keys[event.keycode];gizmo.queue_redraw();return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed:return false
	for i in 3:
		if toolbar_rect(i).has_point(event.position):mode=["move","rotate","scale"][i];gizmo.grab_focus();gizmo.queue_redraw();return true
	if event.ctrl_pressed or event.shift_pressed:return false
	var handle:=handle_at(event.position,data)
	return begin(handle,event.position) if handle!=-2 else false
func hover(point:Vector2)->void:
	var data:=geometry()
	if data.is_empty():return
	for i in 3:
		if toolbar_rect(i).has_point(point):gizmo.tooltip_text=["Move · W","Rotate · E","Scale · R"][i];return
	var handle:=handle_at(point,data)
	if handle!=-2:
		gizmo.tooltip_text=mode.capitalize()+(" freely" if handle<0 else " "+["X","Y","Z"][handle])+" · Ctrl snaps · Esc cancels"
		gizmo.mouse_default_cursor_shape=Control.CURSOR_MOVE if mode=="move" else Control.CURSOR_CROSS
func _exit_tree()->void:
	if not rig.before.is_empty() and is_instance_valid(editor):rig.finish(true)
	if not before.is_empty() and is_instance_valid(editor):finish(true)
