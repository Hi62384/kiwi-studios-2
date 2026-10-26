extends RefCounted
## All bone guides are drawn in the editor overlay, never into the render.
var spatial: Node
var before: Dictionary={}
var original := Vector3.ZERO
var final := Vector3.ZERO
var drag_rig: ActorSkeletonRigRuntime
var drag_bone := -1
var channel := "position"
var parent_basis := Basis.IDENTITY
var selection := ""
var time := 0.

func runtime() -> ActorSkeletonRigRuntime:
	return spatial.primary() as ActorSkeletonRigRuntime
func active() -> bool:
	var rig := runtime()
	return rig!=null and rig.actor.get_meta("editor_bone_mode",false) and rig.skeleton.get_bone_count()>0
func selected() -> int:
	var rig := runtime()
	return clampi(int(rig.actor.get_meta("editor_selected_bone",0)),0,rig.skeleton.get_bone_count()-1) if rig!=null else -1
func transform() -> Transform3D:
	var rig := runtime()
	return rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(selected())
func select_bone(index: int) -> void:
	var rig := runtime(); rig.actor.set_meta("editor_selected_bone",index)
	if is_instance_valid(spatial.editor.inspector): spatial.editor.inspector.call_deferred("_rebuild_selected")
	spatial.gizmo.queue_redraw()
func toolbar_rect(index: int) -> Rect2:
	return Rect2(248+index*88,10,84,27)
func draw() -> void:
	var rig := runtime()
	if rig==null: return
	var mode: bool=rig.actor.get_meta("editor_bone_mode",false)
	for i in (3 if mode and rig.skeleton.get_bone_count()>0 else 1):
		var rect := toolbar_rect(i)
		spatial.gizmo.draw_rect(rect,Color("285c57") if mode and i==0 else Color("152430"))
		spatial.gizmo.draw_rect(rect,Color("71d8be"),false,1)
		spatial.gizmo.draw_string(ThemeDB.fallback_font,rect.position+Vector2(6,18),["Bones  B","◆ Pose  I","↺ Rest"][i],HORIZONTAL_ALIGNMENT_LEFT,78,11,Color("e3f1f3"))
	if not active(): return
	var lens: Camera3D=spatial.camera(); var skeleton := rig.skeleton
	for i in skeleton.get_bone_count():
		var point: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(i).origin
		if lens.is_position_behind(point): continue
		var screen: Vector2=spatial.project(point); var parent := skeleton.get_bone_parent(i)
		var color := Color("ffd078") if i==selected() else Color("8bded5")
		if parent>=0:
			var from: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(parent).origin
			if not lens.is_position_behind(from):
				var a: Vector2=spatial.project(from)
				spatial.gizmo.draw_line(a,screen,Color("10212d"),7,true); spatial.gizmo.draw_line(a,screen,color,3,true)
		spatial.gizmo.draw_circle(screen,7,Color("10212d")); spatial.gizmo.draw_circle(screen,4.5,color)
	spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,78),"Bone: "+skeleton.get_bone_name(selected())+" · W/E/R: transform · I: key pose",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffd078"))
func pick(point: Vector2, joints_only: bool=false) -> int:
	var rig := runtime(); var best := 12.; var result := -1
	for i in rig.skeleton.get_bone_count():
		var world: Vector3=rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(i).origin
		if spatial.camera().is_position_behind(world): continue
		var screen: Vector2=spatial.project(world); var distance := point.distance_to(screen)
		if distance<best: best=distance; result=i
	if result>=0: return result
	if joints_only: return -1
	for i in rig.skeleton.get_bone_count():
		var parent := rig.skeleton.get_bone_parent(i)
		if parent<0: continue
		var a: Vector3=rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(parent).origin
		var b: Vector3=rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(i).origin
		if spatial.camera().is_position_behind(a) or spatial.camera().is_position_behind(b): continue
		var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,spatial.project(a),spatial.project(b)))
		if distance<best: best=distance; result=i
	return result
func begin() -> bool:
	drag_rig=runtime(); drag_bone=selected(); channel={"move":"position","rotate":"rotation","scale":"scale"}[spatial.mode]
	original=ActorSkeletonPose.value(drag_rig.actor,drag_bone,channel); final=original
	before=ActorSkeletonPose.capture(spatial.editor.model,drag_rig.actor)
	var parent := drag_rig.skeleton.get_bone_parent(drag_bone)
	parent_basis=drag_rig.skeleton.global_basis
	if parent>=0: parent_basis*=drag_rig.skeleton.get_bone_global_pose(parent).basis
	selection=drag_rig.actor.id; time=spatial.editor.canvas.playhead
	spatial.gizmo.grab_focus(); return true
func update(point: Vector2, snap: bool) -> void:
	var hit: Variant=spatial._plane_hit(point)
	if hit==null: return
	var delta: Vector3=hit-spatial.start_point
	if spatial.drag_axis>=0: delta=spatial.axis*delta.dot(spatial.axis)
	match spatial.mode:
		"move":
			if snap: delta=delta.snapped(Vector3.ONE*.1)
			final=original+parent_basis.inverse()*delta
		"rotate":
			var angle: float=spatial.start_vector.signed_angle_to((hit-spatial.pivot).normalized(),spatial.axis)
			if snap: angle=snappedf(angle,PI/12.)
			var axis: Vector3=(parent_basis.inverse()*spatial.axis).normalized()
			final=(Basis(axis,angle)*Basis.from_euler(original*PI/180.)).get_euler()*180./PI
		"scale":
			var amount: float=1.+(point.x-spatial.start_mouse.x-point.y+spatial.start_mouse.y)/140. if spatial.drag_axis<0 else 1.+delta.dot(spatial.axis)/spatial.drag_length
			if snap: amount=snappedf(amount,.1)
			final=original
			if spatial.drag_axis<0: final*=maxf(.01,amount)
			else: final[spatial.drag_axis]*=maxf(.01,amount)
	ActorSkeletonPose.preview(spatial.editor.model,drag_rig.actor,drag_bone,channel,final)
func finish(cancel: bool=false) -> void:
	if before.is_empty(): return
	if cancel: ActorSkeletonPose.restore(spatial.editor.model,before)
	else: ActorSkeletonPose.commit(spatial.editor.model,before,drag_bone,{channel:final})
	before={}; drag_rig=null
func sync() -> void:
	if not before.is_empty() and (not spatial.enabled() or spatial.editor.model.selected_actor()==null or spatial.editor.model.selected_actor().id!=selection or selected()!=drag_bone or not is_equal_approx(time,spatial.editor.canvas.playhead)): finish(true)
func reset() -> void:
	var rig := runtime(); var index := selected(); var rest := rig.skeleton.get_bone_rest(index)
	ActorSkeletonPose.commit(spatial.editor.model,ActorSkeletonPose.capture(spatial.editor.model,rig.actor),index,{"position":rest.origin,"rotation":rest.basis.get_rotation_quaternion().get_euler()*180./PI,"scale":rest.basis.get_scale()})
func handle_event(event: InputEvent) -> bool:
	if not before.is_empty():
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: finish(true); return true
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT: finish(true); return true
		if event is InputEventMouseMotion: update(event.position,event.ctrl_pressed); return true
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed: finish(); return true
		if event is InputEventKey and not event.ctrl_pressed: return true
		return false
	var rig := runtime()
	if rig==null or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT): return false
	if event is InputEventKey and event.pressed and not event.echo and spatial.gizmo.has_focus() and not event.ctrl_pressed and not event.alt_pressed:
		if event.keycode==KEY_B: rig.actor.set_meta("editor_bone_mode",not bool(rig.actor.get_meta("editor_bone_mode",false))); return true
		if active() and event.keycode==KEY_I: ActorSkeletonPose.key_pose(spatial.editor.model,rig.actor,selected()); return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed: return false
	for i in (3 if active() else 1):
		if not toolbar_rect(i).has_point(event.position): continue
		if i==0: rig.actor.set_meta("editor_bone_mode",not bool(rig.actor.get_meta("editor_bone_mode",false)))
		elif i==1: ActorSkeletonPose.key_pose(spatial.editor.model,rig.actor,selected())
		else: reset()
		spatial.gizmo.grab_focus(); return true
	if active():
		# A joint is a direct selection target even where an axis handle crosses
		# it. Keep the selected joint's center available for free translation.
		var joint := pick(event.position,true)
		if joint>=0 and joint!=selected(): select_bone(joint); spatial.gizmo.grab_focus(); return true
		if spatial.handle_at(event.position,spatial.geometry())!=-2: return false
		var index := pick(event.position)
		if index>=0: select_bone(index); spatial.gizmo.grab_focus(); return true
	return false
