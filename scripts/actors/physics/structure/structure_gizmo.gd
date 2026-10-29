extends RefCounted
var spatial: Node
var actor: ActorData
var before: Dictionary={}
var field:="pivot"
var selected:=""
var plane:=Plane()
var offset:=Vector3.ZERO
func enabled(data: ActorData) -> bool:
	return bool(ActorAnimation.sampled_value(data,PackedStringArray(["structure_enabled"]),spatial.editor.physics._local(data,spatial.editor.canvas.playhead),data.get_value(&"structure_enabled",false)))
func physical_point(controller: KiwiTimelinePhysics,owner: String,point: Vector3,fallback: Transform3D) -> Vector3:
	var endpoint:=controller.structure.endpoint(owner,point)
	if not endpoint.is_empty():
		for fragment: Dictionary in controller.display_states.get(owner,{}).get("destruction_fragments",[]):
			if fragment.id==endpoint.id: return fragment.pose*endpoint.local
	return fallback*point
func active() -> bool:
	var runtime:=spatial.primary() as ActorRuntime
	return runtime!=null and enabled(runtime.actor) and runtime.actor.get_meta("structure_tool",false)
func draw() -> void:
	var primary:=spatial.primary() as ActorRuntime
	if primary==null: return
	var rect: Rect2=spatial.toolbar_rect(4)
	if enabled(primary.actor):
		spatial.gizmo.draw_rect(rect,Color("285c57") if active() else Color("152430")); spatial.gizmo.draw_string(ThemeDB.fallback_font,rect.position+Vector2(6,18),"Joints J",HORIZONTAL_ALIGNMENT_LEFT,68,11,Color("85d5c4"))
	for owner: ActorData in spatial.editor.model.actors:
		if not enabled(owner) or not owner.get_value(&"structure_overlay",true): continue
		var controller: KiwiTimelinePhysics=spatial.editor.physics; var state: Dictionary=controller.display_states.get(owner.id,{})
		var pose: Transform3D=state.get("pose",controller.animated_world(owner.id,spatial.editor.canvas.playhead))
		if not spatial.camera().is_position_behind(pose.origin):
			var color:=Color("83ddaa") if state.get("structural",{}).get("supported",false) else Color("ffad68")
			var point: Vector2=spatial.project(pose.origin)
			if int(owner.get_value(&"structure_role",0))!=0: spatial.gizmo.draw_rect(Rect2(point-Vector2(5,5),Vector2(10,10)),color,false,2)
			else: spatial.gizmo.draw_circle(point,4,color,false,1.5)
		var links: Dictionary=ActorAnimation.sampled_values(owner,controller._local(owner,spatial.editor.canvas.playhead)).get(&"structure_connections",{})
		for id: String in links:
			var link: Dictionary=links[id]; var target: ActorData=spatial.editor.model.actor_for_id(str(link.target))
			if target==null: continue
			var a:=physical_point(controller,owner.id,link.pivot,pose); var other: Transform3D=controller.display_states.get(target.id,{}).get("pose",controller.animated_world(target.id,spatial.editor.canvas.playhead)); var b:=physical_point(controller,target.id,link.target_pivot,other)
			if spatial.camera().is_position_behind(a) or spatial.camera().is_position_behind(b): continue
			var runtime: Dictionary=state.get("structural",{}).get("links",{}).get(id,{}); var used:=clampf(float(runtime.get("utilization",0)),0,1)
			var color:=Color("78dba7").lerp(Color("ff685e"),used)
			if runtime.get("broken",false) or not link.get("enabled",true): color=Color("ff685e"); spatial.gizmo.draw_dashed_line(spatial.project(a),spatial.project(b),color,1.5,5)
			else: spatial.gizmo.draw_line(spatial.project(a),spatial.project(b),color,2,true)
			var center: Vector2=spatial.project((a+b)*.5); spatial.gizmo.draw_circle(center,5,color)
			if active() and owner==primary.actor and id==str(owner.get_meta("structure_selected","")):
				spatial.gizmo.draw_circle(spatial.project(a),8,Color("ffd078"),false,2); spatial.gizmo.draw_circle(spatial.project(b),6,Color("80bdff"),false,2)
				var direction: Vector3=pose.basis*Basis.from_euler(link.orientation*PI/180)*Vector3.UP*.35
				spatial.gizmo.draw_line(spatial.project(a),spatial.project(a+direction),Color("90d3ff"),2,true); spatial.gizmo.draw_circle(spatial.project(a+direction),5,Color("90d3ff"))
	if active(): spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,78),"Approximate loads · Drag endpoints / direction · Ctrl: snap · Esc: exit",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("85d5c4"))
func cancel() -> void:
	if actor!=null and not before.is_empty(): actor.values=ActorData.copy_value(before); actor.animation_previews.clear(); actor.emit_changed(); spatial.editor.model.changed.emit()
	before={}
func handle_event(event: InputEvent) -> bool:
	var runtime:=spatial.primary() as ActorRuntime
	if runtime==null or not enabled(runtime.actor): return false
	var data: ActorData=runtime.actor
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_J and spatial.gizmo.has_focus()) or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and spatial.toolbar_rect(4).has_point(event.position)):
		data.set_meta("structure_tool",not active()); spatial.gizmo.grab_focus(); return true
	if not active(): return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: cancel(); data.set_meta("structure_tool",false); return true
	var id:=str(data.get_meta("structure_selected","")); var values:=ActorAnimation.sampled_values(data,data.animation_time if not is_nan(data.animation_time) else 0); var link: Dictionary=values.get(&"structure_connections",{}).get(id,{})
	if event is InputEventMouseButton and event.shift_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not link.is_empty():
		KiwiStructure.set_value(spatial.editor.model,data,id,"strength",maxf(.001,float(link.strength)*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.1))); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var best:=14.0; var chosen:={}; var pose:=runtime.remote_transform()
			for key: String in values.get(&"structure_connections",{}):
				var candidate: Dictionary=values.structure_connections[key]; var target: ActorData=spatial.editor.model.actor_for_id(str(candidate.target))
				if target==null: continue
				var other:=spatial.editor.physics.display_states.get(target.id,{}).get("pose",spatial.editor.physics.animated_world(target.id,spatial.editor.canvas.playhead)) as Transform3D
				var a: Vector3=pose*candidate.pivot; var points:={"pivot":a,"target_pivot":other*candidate.target_pivot,"orientation":a+pose.basis*Basis.from_euler(candidate.orientation*PI/180)*Vector3.UP*.35}
				for name: String in points:
					var distance: float=spatial.project(points[name]).distance_to(event.position)
					if distance<best: best=distance; chosen={"id":key,"field":name,"point":points[name]}
			if chosen.is_empty(): return false
			actor=data; selected=chosen.id; field=chosen.field; actor.set_meta("structure_selected",selected); before=ActorData.copy_value(actor.values); plane=Plane(spatial.camera().global_basis.z,chosen.point); var ray: Dictionary=spatial._ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction); offset=chosen.point-hit if hit!=null else Vector3.ZERO; spatial.gizmo.grab_focus(); return true
		elif not before.is_empty():
			var path:=PackedStringArray(["structure_connections",selected,field]); var final: Variant=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path)); actor.values=before; before={}; KiwiStructure.set_value(spatial.editor.model,actor,selected,field,final); return true
	if event is InputEventMouseMotion and not before.is_empty():
		var ray: Dictionary=spatial._ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction)
		if hit!=null:
			var pose:=spatial.primary().remote_transform() as Transform3D; var value: Vector3=pose.affine_inverse()*(hit+offset)
			if field=="target_pivot":
				var target:=str(actor.values.structure_connections[selected].target); pose=spatial.editor.physics.display_states.get(target,{}).get("pose",spatial.editor.physics.animated_world(target,spatial.editor.canvas.playhead)); value=pose.affine_inverse()*(hit+offset)
			elif field=="orientation":
				var direction: Vector3=(value-actor.values.structure_connections[selected].pivot).normalized()
				value=Quaternion(Vector3.UP,direction).get_euler()*180/PI if not direction.is_zero_approx() else Vector3.ZERO
			if event.ctrl_pressed: value=value.snapped(Vector3.ONE*(15 if field=="orientation" else .1))
			KiwiStructure.set_value(spatial.editor.model,actor,selected,field,value,true)
		return true
	return false
