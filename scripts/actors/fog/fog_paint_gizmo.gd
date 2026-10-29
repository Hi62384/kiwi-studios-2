extends RefCounted
const Field=preload("res://scripts/actors/fog/fog_field.gd")
var spatial: Node
var owner_actor: ActorData
var object: ActorObjectData
var before: Dictionary={}
var painting:=false
var last:=Vector3.INF
var cursor:=Vector3.INF

func active() -> bool:
	var runtime: ActorRuntime=spatial.primary()
	return runtime!=null and runtime.actor.type_id in [&"fog_volume",&"global_fog"] and runtime.actor.has_meta("editor_fog_field") and runtime.actor.get_meta("editor_fog_field") is ActorObjectData and runtime.content is FogVolume
func field() -> ActorObjectData:
	return spatial.primary().actor.get_meta("editor_fog_field") if active() else null
func tick() -> void:
	if painting and (not active() or field()!=object or spatial.primary().actor!=owner_actor): finish(true)
func point(screen: Vector2) -> Vector3:
	if not active() or not spatial.in_picture(screen): return Vector3.INF
	var runtime: ActorRuntime=spatial.primary(); var fog: FogVolume=runtime.content; var transform:=fog.global_transform
	if absf(transform.basis.determinant())<.000001: return Vector3.INF
	var inverse:=transform.affine_inverse(); var ray: Dictionary=spatial._ray(screen); var origin: Vector3=inverse*ray.origin; var direction: Vector3=inverse.basis*ray.direction; var v:=field().values
	var axis:=int(v.get(&"paint_plane",0)); var normal: Vector3=(inverse.basis*spatial.camera().global_basis.z).normalized() if axis==0 else [Vector3.RIGHT,Vector3.UP,Vector3.BACK][axis-1]
	var center:=normal*(float(v.get(&"paint_depth",.5))-.5)*(fog.size.length() if axis==0 else fog.size[axis-1]); var plane:=Plane(normal,normal.dot(center)); var hit: Variant=plane.intersects_ray(origin,direction)
	if hit==null or not AABB(-fog.size*.5,fog.size).has_point(hit): return Vector3.INF
	return hit/fog.size+Vector3.ONE*.5
func draw() -> void:
	if not active(): return
	cursor=point(spatial.gizmo.get_local_mouse_position())
	if cursor==Vector3.INF: return
	var fog: FogVolume=spatial.primary().content; var world: Vector3=fog.global_transform*((cursor-Vector3.ONE*.5)*fog.size); var center: Vector2=spatial.project(world)
	# Intersect the normalized spherical brush with the editing plane, then project
	# that ring. Nonuniform volume size/scale therefore produces the correct ellipse.
	var axis:=int(field().get_value(&"paint_plane",0)); var normal: Vector3=(fog.global_transform.basis.inverse()*spatial.camera().global_basis.z*fog.size).normalized() if axis==0 else [Vector3.RIGHT,Vector3.UP,Vector3.BACK][axis-1]
	var tangent:=normal.cross(Vector3.UP).normalized()
	if tangent.length_squared()<.1: tangent=normal.cross(Vector3.RIGHT).normalized()
	var bitangent:=normal.cross(tangent).normalized(); var radius:=float(field().get_value(&"brush_radius",3.))/Field.PAINT_SIZE; var ring:=PackedVector2Array()
	for index in 65:
		var angle:=TAU*index/64.; var p:=cursor+(tangent*cos(angle)+bitangent*sin(angle))*radius; ring.append(spatial.project(fog.global_transform*((p-Vector3.ONE*.5)*fog.size)))
	spatial.gizmo.draw_polyline(ring,Color("80e8cb"),2.,true)
	spatial.gizmo.draw_circle(center,3.,Color("ffda8b")); spatial.gizmo.draw_string(ThemeDB.fallback_font,Vector2(12,30),"3D fog paint · Ctrl subtracts · Esc cancels / exits",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d4eee9"))
func handle_event(event: InputEvent) -> bool:
	if not active(): return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if painting: finish(true)
		else: spatial.primary().actor.remove_meta("editor_fog_field")
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if painting: finish(true); return true
		return false
	if event is InputEventMouseMotion:
		if painting: dab(event.position,event.ctrl_pressed)
		return painting
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p:=point(event.position)
			if p==Vector3.INF: return false
			owner_actor=spatial.primary().actor; object=field(); before=ActorData.copy_value(object.get_value(&"paint",{})); painting=true; last=Vector3.INF; spatial.gizmo.grab_focus(); dab(event.position,event.ctrl_pressed)
		else: finish()
		return true
	return false
func dab(screen: Vector2,subtract: bool=false) -> void:
	var p:=point(screen)
	if p==Vector3.INF: last=Vector3.INF; return
	var radius:=float(object.get_value(&"brush_radius",3.)); var from:=last if last!=Vector3.INF else p; var steps:=clampi(ceili(from.distance_to(p)*Field.PAINT_SIZE/maxf(.5,radius*.25)),1,128); var voxels: Dictionary=object.get_value(&"paint",{})
	for index in range(1,steps+1):
		var center:=Vector3i((from.lerp(p,float(index)/steps)*Field.PAINT_SIZE).floor()); var centers: Array[Vector3i]=[center]
		for axis in 3:
			if not object.get_value(StringName("symmetry_"+["x","y","z"][axis]),false): continue
			var count:=centers.size()
			for i in count: var mirrored:=centers[i]; mirrored[axis]=Field.PAINT_SIZE-1-mirrored[axis]; centers.append(mirrored)
		for at in centers: voxels=Field.paint_dab(voxels,at,radius,float(object.get_value(&"brush_strength",.5)),float(object.get_value(&"brush_falloff",1.)),1 if subtract else int(object.get_value(&"brush_tool",0)))
	last=p; object.set_value(&"paint",voxels); spatial.editor.model.changed.emit(); spatial.gizmo.queue_redraw()
func finish(cancel: bool=false) -> void:
	if not painting: return
	painting=false; var after: Dictionary=ActorData.copy_value(object.get_value(&"paint",{})); object.set_value(&"paint",before)
	if not cancel: spatial.editor.model.edit_object_property(owner_actor,object,Field.definition(),&"paint",after)
	else: spatial.editor.model.changed.emit()
	before={}; object=null; owner_actor=null; last=Vector3.INF
