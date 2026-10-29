extends RefCounted
var spatial: Node
var before: Dictionary={}
var tracks: Array[ActorAnimationTrack]=[]
var actor: ActorData
var selected:=""
var plane:=Plane()
var offset:=Vector3.ZERO
var fragment_drag:=false
var fragment_origin:=Vector3.ZERO
var fragment_rule_before: Dictionary={}
func available() -> bool:
	var runtime: ActorRuntime=spatial.primary()
	return runtime!=null and runtime.actor.get_value(&"destruction_enabled",false) and not runtime.actor.get_value(&"destruction_operations",{}).is_empty()
func active() -> bool: return available() and spatial.primary().actor.get_meta("damage_viewport_tool",false)
func selected_operation() -> Dictionary:
	if not available(): return {}
	var data: ActorData=spatial.primary().actor; var operations: Dictionary=ActorAnimation.sampled_values(data,data.animation_time if not is_nan(data.animation_time) else 0).get(&"destruction_operations",{})
	return operations.get(str(data.get_meta("damage_selected_operation",operations.keys()[0])),{})
func draw() -> void:
	if not available(): return
	var rect: Rect2=spatial.toolbar_rect(3)
	spatial.gizmo.draw_rect(rect,Color("285c57") if active() else Color("152430")); spatial.gizmo.draw_string(ThemeDB.fallback_font,rect.position+Vector2(6,18),"Damage D",HORIZONTAL_ALIGNMENT_LEFT,66,11,Color("ffd078"))
	if not active(): return
	if spatial.primary().actor.get_meta("damage_pattern_preview",false) and not spatial.editor.playing: draw_pattern()
	if spatial.primary().actor.get_meta("damage_fragment_tool",false): draw_fragments(); return
	var op:=selected_operation()
	if op.is_empty(): return
	var pose: Transform3D=spatial.primary().remote_transform(); var point: Vector3=pose*op.get("position",Vector3.ZERO)
	if spatial.camera().is_position_behind(point): return
	var center: Vector2=spatial.project(point); var edge: Vector2=spatial.project(point+spatial.camera().global_basis.x*maxf(.001,float(op.get("radius",.5))))
	spatial.gizmo.draw_arc(center,maxf(8,center.distance_to(edge)),0,TAU,64,Color("ffd078"),1.5,true)
	spatial.gizmo.draw_circle(center,7,Color("ffd078")); spatial.gizmo.draw_circle(center,3,Color("152430"))
	spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,58),"Drag damage center · Shift-wheel: radius · Ctrl: snap · Esc: exit",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffd078"))
func draw_pattern() -> void:
	var data: ActorData=spatial.primary().actor; var controller: KiwiTimelinePhysics=spatial.editor.physics
	if not controller.states.has(data.id): return
	var output:=controller.destruction.prepare(controller,data.id,controller.states[data.id],data.values,data.get_value(&"destruction_operations",{}))
	if not output.get("error","").is_empty(): return
	var pose: Transform3D=controller.states[data.id].pose; var lines:=0
	for row: Dictionary in output.rows:
		for edge: Dictionary in row.mesh.edges():
			var cap:=false
			for face: int in edge.faces:
				if row.mesh.materials[face]==output.materials.size(): cap=true
			if not cap: continue
			var a: Vector3=pose*(row.mesh.vertices[edge.a]+row.center); var b: Vector3=pose*(row.mesh.vertices[edge.b]+row.center)
			if not spatial.camera().is_position_behind(a) and not spatial.camera().is_position_behind(b): spatial.gizmo.draw_line(spatial.project(a),spatial.project(b),Color("ffcf70"),1.5,true)
			lines+=1
			if lines>4000: return
func draw_fragments() -> void:
	var data: ActorData=spatial.primary().actor; var chosen: Array=data.get_meta("damage_selected_fragments",[]); var fragments: Array=spatial.editor.physics.display_states.get(data.id,{}).get("destruction_fragments",[])
	for i in fragments.size():
		var fragment: Dictionary=fragments[i]; var key:=KiwiDestructionAuthoring.fragment_key(data.id,fragment.id); var point: Vector3=fragment.pose.origin
		if spatial.camera().is_position_behind(point): continue
		var selected_piece:=chosen.has(key); var color:=Color("ffcf70") if selected_piece else Color("78ddd1"); var center: Vector2=spatial.project(point)
		spatial.gizmo.draw_circle(center,5,color); spatial.gizmo.draw_string(ThemeDB.fallback_font,center+Vector2(8,-5),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
		if selected_piece:
			var target: Vector3=data.get_value(&"destruction_fragments",{}).get(key,{}).get("target",point)
			if fragment_drag: target=offset
			if not spatial.camera().is_position_behind(target): spatial.gizmo.draw_line(center,spatial.project(target),color,1.5,true); spatial.gizmo.draw_circle(spatial.project(target),8,color,false,2,true)
	spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,58),"Pick pieces · Shift: group · Drag gold target: force guidance",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffd078"))
func restore(values: Dictionary,animation: Array[ActorAnimationTrack]) -> void:
	actor.values[&"destruction_operations"]=ActorData.copy_value(values); actor.animation_previews.clear(); spatial.editor.model.restore_animation(actor,animation)
func cancel() -> void:
	if not before.is_empty(): restore(before,tracks); before={}
	fragment_drag=false
func handle_event(event: InputEvent) -> bool:
	if not available(): return false
	var data: ActorData=spatial.primary().actor
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_D and spatial.gizmo.has_focus(): data.set_meta("damage_viewport_tool",not active()); spatial.gizmo.queue_redraw(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and spatial.toolbar_rect(3).has_point(event.position): data.set_meta("damage_viewport_tool",not active()); spatial.gizmo.grab_focus(); return true
	if not active(): return false
	if data.get_meta("damage_fragment_tool",false): return fragment_event(event,data)
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if not before.is_empty(): restore(before,tracks); before={}
		data.set_meta("damage_viewport_tool",false); return true
	var op:=selected_operation()
	if op.is_empty(): return false
	var pose: Transform3D=spatial.primary().remote_transform(); var point: Vector3=pose*op.get("position",Vector3.ZERO)
	if data.get_meta("damage_path_tool",false) and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT: data.set_meta("damage_path_tool",false); return true
		if event.button_index==MOUSE_BUTTON_LEFT:
			var ray: Dictionary=spatial._ray(event.position); var hit: Variant=null
			for visual: VisualInstance3D in spatial.visuals(spatial.primary()):
				var candidate: Variant=spatial._hit_visual(visual,ray)
				if candidate!=null and (hit==null or ray.origin.distance_squared_to(candidate)<ray.origin.distance_squared_to(hit)): hit=candidate
			if hit!=null:
				var operations: Dictionary=data.get_value(&"destruction_operations",{}).duplicate(true); var id:=str(data.get_meta("damage_selected_operation",operations.keys()[0])); var path: PackedVector3Array=operations[id].get("path",PackedVector3Array())
				if path.size()<33: path.append(pose.affine_inverse()*hit); operations[id].path=path; operations[id].direction=pose.basis.inverse()*spatial.camera().global_basis.z; KiwiDestructionDefinition.edit(spatial.editor.model,data,operations,"Place fracture path point")
			return true
	if event is InputEventMouseButton and event.shift_pressed and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var operations: Dictionary=data.get_value(&"destruction_operations",{}).duplicate(true); var id:=str(data.get_meta("damage_selected_operation",operations.keys()[0])); var radius:=maxf(.001,float(op.get("radius",.5))* (1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.1)); var path:=PackedStringArray(["destruction_operations",id,"radius"])
		if data.animation_track(path)!=null: spatial.editor.model.commit_animation_value(data,path,radius)
		else:
			operations[id].radius=radius; KiwiDestructionDefinition.edit(spatial.editor.model,data,operations,"Damage radius")
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if spatial.project(point).distance_to(event.position)>12: return false
			actor=data; before=ActorData.copy_value(actor.get_value(&"destruction_operations",{})); tracks=spatial.editor.model.animation_snapshot(actor); selected=str(actor.get_meta("damage_selected_operation",before.keys()[0])); plane=Plane(spatial.camera().global_basis.z,point)
			var ray: Dictionary=spatial._ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction); offset=point-hit if hit!=null else Vector3.ZERO; spatial.gizmo.grab_focus(); return true
		elif not before.is_empty():
			var after: Dictionary=ActorData.copy_value(actor.get_value(&"destruction_operations",{})); var after_tracks: Array[ActorAnimationTrack]=spatial.editor.model.animation_snapshot(actor)
			var model: ActorTimeline=spatial.editor.model; var path:=PackedStringArray(["destruction_operations",selected,"position"])
			if actor.animation_track(path)!=null:
				var value: Variant=ActorAnimation.sampled_value(actor,path,actor.animation_time,after[selected].position); restore(before,tracks); model.commit_animation_value(actor,path,value)
			else:
				model.history.create_action("Move damage operation"); model.history.add_do_method(KiwiDestructionDefinition.restore_animation.bind(weakref(model),actor,after,after_tracks)); model.history.add_undo_method(KiwiDestructionDefinition.restore_animation.bind(weakref(model),actor,before,tracks)); model.history.commit_action()
			before={}; return true
	if event is InputEventMouseMotion and not before.is_empty():
		var ray: Dictionary=spatial._ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction)
		if hit!=null:
			var local: Vector3=pose.affine_inverse()*(hit+offset)
			if event.ctrl_pressed: local=local.snapped(Vector3.ONE*.1)
			var path:=PackedStringArray(["destruction_operations",selected,"position"])
			if actor.animation_track(path)!=null: spatial.editor.model.preview_animation_value(actor,path,local)
			else:
				var operations: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true); operations[selected].position=local; actor.values[&"destruction_operations"]=operations; spatial.editor.model.changed.emit()
		return true
	return false
func fragment_event(event: InputEvent,data: ActorData) -> bool:
	var model: ActorTimeline=spatial.editor.model; var chosen: Array=data.get_meta("damage_selected_fragments",[]); var pieces: Array=spatial.editor.physics.display_states.get(data.id,{}).get("destruction_fragments",[])
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: fragment_drag=false; data.set_meta("damage_fragment_tool",false); data.set_meta("damage_viewport_tool",false); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			for fragment: Dictionary in pieces:
				var key:=KiwiDestructionAuthoring.fragment_key(data.id,fragment.id)
				if not chosen.has(key): continue
				var target: Vector3=data.get_value(&"destruction_fragments",{}).get(key,{}).get("target",fragment.pose.origin)
				if spatial.project(target).distance_to(event.position)<10: fragment_drag=true; fragment_origin=target; offset=target; plane=Plane(spatial.camera().global_basis.z,target); spatial.gizmo.grab_focus(); return true
			var nodes: Array=spatial.editor.physics.destruction.nodes.get(data.id,[]); var best:=INF; var id:=""; var ray: Dictionary=spatial._ray(event.position)
			for i in mini(nodes.size(),pieces.size()):
				var hit: Variant=spatial._hit_visual(nodes[i],ray)
				if hit!=null and ray.origin.distance_squared_to(hit)<best: best=ray.origin.distance_squared_to(hit); id=KiwiDestructionAuthoring.fragment_key(data.id,pieces[i].id)
			if not event.shift_pressed: chosen=[]
			if not id.is_empty() and not chosen.has(id): chosen.append(id)
			data.set_meta("damage_selected_fragments",chosen); spatial.gizmo.grab_focus(); return true
		elif fragment_drag:
			fragment_drag=false
			KiwiDestructionAuthoring.edit_fragments(model,data,&"destruction_fragments",chosen,"guided_target",offset); return true
	if event is InputEventMouseMotion and fragment_drag:
		var ray: Dictionary=spatial._ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction)
		if hit!=null: offset=hit.snapped(Vector3.ONE*.1) if event.ctrl_pressed else hit
		return true
	return false
