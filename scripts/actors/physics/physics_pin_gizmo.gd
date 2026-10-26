extends RefCounted
## Editor-only pin picking. No simulation or render geometry lives here.
var spatial: Node
func active() -> bool:
	var runtime: ActorRuntime=spatial.primary()
	return runtime!=null and runtime.actor.get_meta("editor_physics_pin_mode",false) and spatial.editor.physics.prototypes.has(runtime.actor.id) and int(KiwiPhysicsSettings.authored(runtime.actor).type) in [1,4,5]
func points() -> PackedVector3Array:
	return spatial.editor.physics.display_states.get(spatial.primary().actor.id,{}).get("points",PackedVector3Array())
func draw() -> void:
	if not active(): return
	var actor: ActorData=spatial.primary().actor; var config:=KiwiPhysicsSettings.authored(actor)
	var selected:={}
	for pin: Dictionary in config.pins: selected[int(pin.get("point",-1))]=true
	var positions:=points()
	for i in positions.size():
		if spatial.camera().is_position_behind(positions[i]): continue
		var point: Vector2=spatial.project(positions[i])
		spatial.gizmo.draw_circle(point,5,Color("10212d"))
		spatial.gizmo.draw_circle(point,3.5,Color("ffd078") if selected.has(i) else Color("80dbc4"))
		if selected.has(i): spatial.gizmo.draw_string(ThemeDB.fallback_font,point+Vector2(6,-6),str(i),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("ffd078"))
	spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,30),"Point pins · Click to pin · Ctrl-click to remove · Esc to finish",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e3f1f3"))
func handle_event(event: InputEvent) -> bool:
	if not active(): return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		spatial.primary().actor.set_meta("editor_physics_pin_mode",false); spatial.gizmo.queue_redraw(); return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT: return false
	if not event.pressed: return true
	var positions:=points(); var best:=12.0; var chosen:=-1
	for i in positions.size():
		if spatial.camera().is_position_behind(positions[i]): continue
		var distance: float=spatial.project(positions[i]).distance_to(event.position)
		if distance<best: best=distance; chosen=i
	if chosen>=0:
		KiwiPhysicsSettings.pin(spatial.editor,spatial.primary().actor,chosen,positions[chosen],event.ctrl_pressed)
	spatial.gizmo.grab_focus(); spatial.gizmo.queue_redraw(); return true
