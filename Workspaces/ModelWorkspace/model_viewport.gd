class_name KiwiModelViewport
extends Control
signal command_requested(command: String)
signal gesture_finished
signal notice(message: String)
var session: KiwiModelSession
var viewport := SubViewport.new()
var world := Node3D.new()
var camera := Camera3D.new()
var display := TextureRect.new()
var overlay := Control.new()
var grid := MeshInstance3D.new()
var visuals: Dictionary = {}
var evaluated: Dictionary = {}
var signatures: Dictionary = {}
var tool := "Move"
var local_axes := false
var xray := false
var wireframe := false
var show_normals := false
var show_edges := true
var grid_step := .25
var snap := false
var snap_kind := "Grid"
var align_surface := false
var proportional := false
var radius := 1.5
var strength := .3
var sculpt := ""
var push_pull := false
var _extruding := false
var _extrude_amount := 0.
var _extrude_numeric := ""
var target := Vector3.ZERO
var distance := 7.
var yaw := .65
var pitch := -.4
var fly_speed := 4.
var _pending_sync := true
var _navigating := false
var _panning := false
var _orbiting := false
var _pressed := false
var _box := false
var _start := Vector2.ZERO
var _mouse := Vector2.ZERO
var _drag := false
var _modal := false
var _axis := -1
var _plane := false
var _pivot := Vector3.ZERO
var _axes: Array[Vector3] = []
var _start_world := Vector3.ZERO
var _source: KiwiModelDocument
var _numeric := ""
var _create := ""
var _create_phase := 0
var _create_origin := Vector3.ZERO
var _create_component: KiwiModelComponent
var _selected_vertices := PackedInt32Array()
var _selected_lookup: Dictionary = {}
var _weights := PackedFloat32Array()
var _weights_radius := -1.
var rig_tool: KiwiRigViewport
const COLORS := [Color("f3848c"),Color("8bddae"),Color("85bdff")]

func _ready() -> void:
	rig_tool=KiwiRigViewport.new(); rig_tool.canvas=self; rig_tool.editor=KiwiRigEditor.new(session)
	focus_mode=Control.FOCUS_ALL; clip_contents=true; custom_minimum_size=Vector2(220,200)
	viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; viewport.msaa_3d=Viewport.MSAA_2X
	add_child(viewport); viewport.add_child(world); world.add_child(camera); camera.current=true; camera.near=.02; camera.far=2000
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); display.mouse_filter=Control.MOUSE_FILTER_IGNORE; display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; display.texture=viewport.get_texture(); add_child(display)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(overlay); overlay.draw.connect(_draw_overlay)
	var environment := WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("18232e")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color("c7dbed"); environment.environment.ambient_light_energy=.55; world.add_child(environment)
	for i in 2:
		var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-35 if i==0 else 130,0); light.light_energy=1.1 if i==0 else .45; world.add_child(light)
	world.add_child(grid); rebuild_grid(); resized.connect(_resize); _resize(); update_camera()
	if session!=null: session.changed.connect(request_sync)

func _resize() -> void: viewport.size=Vector2i(maxi(64,int(size.x)),maxi(64,int(size.y)))
func request_sync() -> void: _pending_sync=true; overlay.queue_redraw()
func update_camera() -> void:
	var basis := Basis.from_euler(Vector3(pitch,yaw,0)); camera.position=target+basis.z*distance; camera.basis=basis
	overlay.queue_redraw()
func set_view(view: String) -> void:
	match view:
		"Front": yaw=0; pitch=0
		"Back": yaw=PI; pitch=0
		"Left": yaw=-PI/2; pitch=0
		"Right": yaw=PI/2; pitch=0
		"Top": yaw=0; pitch=-PI/2+.0001
		"Bottom": yaw=0; pitch=PI/2-.0001
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; update_camera()
func frame(all: bool=false) -> void:
	var points := PackedVector3Array()
	for item in session.document.components:
		var included := all or session.selected.has(item.id)
		for id in session.selected:
			if session.document.is_descendant(item.id,id): included=true; break
		if not included: continue
		if item.mesh==null: continue
		var transform := session.document.world_transform(item)
		for vertex in item.mesh.vertices: points.append(transform*vertex)
	if points.is_empty(): target=Vector3.ZERO; distance=7; camera.size=6; update_camera(); return
	var box := AABB(points[0],Vector3.ZERO)
	for point in points: box=box.expand(point)
	target=box.get_center(); distance=maxf(1.,box.size.length()*1.5); camera.size=maxf(.3,box.size.length()*1.25); update_camera()
func rebuild_grid() -> void:
	var mesh := ImmediateMesh.new(); var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo=true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for i in range(-40,41):
		mesh.surface_set_color(Color("593d49") if i==0 else Color(.025,.04,.055)); mesh.surface_add_vertex(Vector3(-40*grid_step,0,i*grid_step)); mesh.surface_add_vertex(Vector3(40*grid_step,0,i*grid_step))
		mesh.surface_set_color(Color("325368") if i==0 else Color(.025,.04,.055)); mesh.surface_add_vertex(Vector3(i*grid_step,0,-40*grid_step)); mesh.surface_add_vertex(Vector3(i*grid_step,0,40*grid_step))
	mesh.surface_end(); grid.mesh=mesh
func sync() -> void:
	var live := {}
	for item in session.document.components:
		live[item.id]=true
		if not visuals.has(item.id):
			var visual := MeshInstance3D.new(); world.add_child(visual); visuals[item.id]=visual
		var visual: MeshInstance3D=visuals[item.id]; visual.transform=session.document.world_transform(item); visual.visible=session.document.visible_component(item)
		if item.mesh==null: visual.mesh=null; continue
		var signature := hash([item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials,item.mesh.smooth,item.modifiers,item.surface_materials,item.skin_mesh,item.binding.revision if item.binding!=null else 0])
		if signatures.get(item.id,0)!=signature:
			var mesh := KiwiModelModifiers.evaluate(item); evaluated[item.id]=mesh
			visual.mesh=item.skin_mesh if item.skin_mesh!=null else (item.binding.source_mesh if item.binding!=null else mesh.render_mesh(item.surface_materials)); signatures[item.id]=signature
		visual.transparency=1. if wireframe else (.65 if xray else 0.)
	for id in visuals.keys():
		if not live.has(id): visuals[id].queue_free(); visuals.erase(id); evaluated.erase(id); signatures.erase(id)
	if rig_tool!=null: rig_tool.editor.session=session; rig_tool.sync()
	_pending_sync=false; overlay.queue_redraw()
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if _pending_sync: sync()
	if _navigating:
		var velocity := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): velocity-=camera.basis.z
		if Input.is_physical_key_pressed(KEY_S): velocity+=camera.basis.z
		if Input.is_physical_key_pressed(KEY_A): velocity-=camera.basis.x
		if Input.is_physical_key_pressed(KEY_D): velocity+=camera.basis.x
		if Input.is_physical_key_pressed(KEY_Q): velocity-=Vector3.UP
		if Input.is_physical_key_pressed(KEY_E): velocity+=Vector3.UP
		target+=velocity*delta*fly_speed; update_camera()

func project(point: Vector3) -> Vector2: return camera.unproject_position(point)*size/Vector2(viewport.size)
func ray(point: Vector2) -> Dictionary:
	var p := point*Vector2(viewport.size)/size
	return {"origin":camera.project_ray_origin(p),"direction":camera.project_ray_normal(p)}
func pick(point: Vector2, excluded: Array[String]=[]) -> Dictionary:
	if _pending_sync and (visuals.is_empty() or (not _pressed and not _drag and not _extruding)): sync()
	var r := ray(point); var best := INF; var result := {}
	for item in session.document.components:
		if excluded.has(item.id) or not session.document.editable_component(item) or not visuals.has(item.id): continue
		var visual: MeshInstance3D=visuals[item.id]
		if visual.mesh==null or visual.mesh.get_surface_count()==0 or absf(visual.transform.basis.determinant())<.000001: continue
		var inverse := visual.transform.affine_inverse(); var origin: Vector3=inverse*r.origin; var direction: Vector3=(inverse.basis*r.direction).normalized()
		if visual.mesh.get_aabb().intersects_ray(origin,direction)==null: continue
		var triangle_mesh := visual.mesh.generate_triangle_mesh()
		if triangle_mesh==null: continue
		var hit := triangle_mesh.intersect_ray(origin,direction)
		if hit.is_empty(): continue
		var world_point: Vector3=visual.transform*hit.position; var length: float=r.origin.distance_to(world_point)
		if length<best:
			best=length; result={"id":item.id,"point":world_point,"normal":(visual.transform.basis.inverse().transposed()*hit.normal).normalized(),"local":hit.position}
	return result
func face_at(item: KiwiModelComponent, point: Vector2) -> int:
	var r := ray(point); var inverse := session.document.world_transform(item).affine_inverse(); var origin: Vector3=inverse*r.origin; var direction: Vector3=(inverse.basis*r.direction).normalized()
	var best := INF; var chosen := -1
	for f in item.mesh.faces.size():
		var triangles := item.mesh.triangles(f)
		for i in range(0,triangles.size(),3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(origin,direction,item.mesh.vertices[item.mesh.faces[f][triangles[i]]],item.mesh.vertices[item.mesh.faces[f][triangles[i+1]]],item.mesh.vertices[item.mesh.faces[f][triangles[i+2]]])
			if hit!=null and origin.distance_to(hit)<best: best=origin.distance_to(hit); chosen=f
	return chosen
func visible_point(point: Vector3) -> bool:
	if camera.is_position_behind(point): return false
	if xray: return true
	var hit := pick(project(point))
	return hit.is_empty() or camera.global_position.distance_to(point)<=camera.global_position.distance_to(hit.point)+.025
func element_at(point: Vector2) -> int:
	var item := session.primary()
	if item==null or item.mesh==null: return -1
	if session.mode=="Face": return face_at(item,point)
	var transform := session.document.world_transform(item); var best := 11.; var chosen := -1
	if session.mode=="Vertex":
		for i in item.mesh.vertices.size():
			var p := transform*item.mesh.vertices[i]; var d := project(p).distance_to(point)
			if d<best and visible_point(p): best=d; chosen=i
	else:
		var edges := item.mesh.edges()
		for i in edges.size():
			var a := transform*item.mesh.vertices[edges[i].a]; var b := transform*item.mesh.vertices[edges[i].b]
			var p := Geometry2D.get_closest_point_to_segment(point,project(a),project(b)); var d := p.distance_to(point)
			if d<best and visible_point((a+b)*.5): best=d; chosen=i
	return chosen
func select_at(point: Vector2, additive: bool) -> void:
	if session.mode=="Object":
		var hit := pick(point); session.select(str(hit.get("id","")),additive); return
	var index := element_at(point)
	if not additive: session.elements=PackedInt32Array()
	if index>=0:
		if session.elements.has(index): session.elements.remove_at(session.elements.find(index))
		else: session.elements.append(index)
	session.changed.emit()
func box_select(rect: Rect2, additive: bool) -> void:
	if session.mode=="Object":
		if not additive: session.selected.clear()
		for item in session.document.components:
			if item.locked or not session.document.visible_component(item) or item.mesh==null: continue
			var p := session.document.world_transform(item)*item.mesh.bounds().get_center()
			if rect.has_point(project(p)) and visible_point(p) and not session.selected.has(item.id): session.selected.append(item.id)
	else:
		var item := session.primary()
		if item==null or item.mesh==null: return
		if not additive: session.elements=PackedInt32Array()
		var transform := session.document.world_transform(item); var points := PackedVector3Array()
		var selected_set := {}
		for index in session.elements: selected_set[index]=true
		match session.mode:
			"Vertex": points=item.mesh.vertices
			"Edge":
				for edge in item.mesh.edges(): points.append((item.mesh.vertices[edge.a]+item.mesh.vertices[edge.b])*.5)
			"Face":
				for f in item.mesh.faces.size(): points.append(item.mesh.center(f))
		for i in points.size():
			var p := transform*points[i]
			if rect.has_point(project(p)) and visible_point(p) and not selected_set.has(i): session.elements.append(i); selected_set[i]=true
	session.changed.emit()

func geometry() -> Dictionary:
	var item := session.primary()
	if item==null or not session.document.editable_component(item) or not sculpt.is_empty(): return {}
	var transform := session.document.world_transform(item); var pivot := transform*item.pivot
	if session.mode!="Object" and item.mesh!=null:
		var indices := session.selected_vertices()
		if indices.is_empty(): return {}
		pivot=Vector3.ZERO
		for index in indices: pivot+=transform*item.mesh.vertices[index]/indices.size()
	if camera.is_position_behind(pivot): return {}
	var depth := -(camera.transform.affine_inverse()*pivot).z
	var length := camera.project_position(camera.unproject_position(pivot)+Vector2(85,0),depth).distance_to(pivot)
	var basis := transform.basis.orthonormalized() if local_axes else Basis.IDENTITY
	var axes: Array[Vector3]=[basis.x,basis.y,basis.z]; var ends := PackedVector2Array(); var rings: Array[PackedVector2Array]=[]
	for i in 3:
		ends.append(project(pivot+axes[i]*length)); var ring := PackedVector2Array()
		for j in 65: ring.append(project(pivot+(axes[(i+1)%3]*cos(TAU*j/64.)+axes[(i+2)%3]*sin(TAU*j/64.))*length))
		rings.append(ring)
	return {"pivot":pivot,"center":project(pivot),"length":length,"axes":axes,"ends":ends,"rings":rings}
func handle_at(point: Vector2, data: Dictionary) -> int:
	if data.is_empty(): return -2
	if tool!="Rotate" and point.distance_to(data.center)<9: return -1
	var best := 9.; var index := -2
	for i in 3:
		if tool=="Rotate":
			var ring: PackedVector2Array=data.rings[i]
			for j in ring.size()-1:
				var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point,ring[j],ring[j+1]))
				if d<best: best=d; index=i
		else:
			if data.center.distance_to(data.ends[i])<15: continue
			var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point,data.center.lerp(data.ends[i],.25),data.ends[i]))
			if d<best: best=d; index=i
	return index
func begin_transform(index: int, point: Vector2, modal: bool=false) -> bool:
	if session.mode=="Object":
		for id in session.selected:
			var item := session.document.component(id)
			if item!=null and item.binding!=null:
				notice.emit("Move the armature or its parent to place a rig. Detach this mesh before changing its component rest transform."); return false
	var data := geometry()
	if data.is_empty(): return false
	_selected_vertices=session.selected_vertices(); _selected_lookup.clear(); _weights_radius=-1.
	for vertex in _selected_vertices: _selected_lookup[vertex]=true
	if proportional and session.mode!="Object" and (session.primary().mesh.vertices.size()-_selected_vertices.size())*_selected_vertices.size()>2000000:
		notice.emit("Proportional neighborhood is too large. Select fewer points or disable Proportional."); return false
	_axis=index; _pivot=data.pivot; _axes.assign(data.axes); _start=point; _source=session.document.snapshot(); _numeric=""; _plane=false
	_start_world=screen_plane(point,_pivot); session.begin(); _drag=true; _modal=modal; grab_focus(); return true
func screen_plane(point: Vector2, pivot: Vector3, normal: Vector3=Vector3.ZERO) -> Vector3:
	var r := ray(point); var n := camera.basis.z if normal==Vector3.ZERO else normal; var denominator: float=n.dot(r.direction)
	if absf(denominator)<.000001: return pivot
	return r.origin+r.direction*n.dot(pivot-r.origin)/denominator
func update_transform(point: Vector2, ctrl: bool=false) -> void:
	if not _drag: return
	var plane_normal := camera.basis.z
	if _axis>=0:
		if _plane: plane_normal=_axes[_axis]
		else:
			var normal := (camera.position-_pivot).slide(_axes[_axis])
			if normal.length()>.00001: plane_normal=normal.normalized()
	var delta := screen_plane(point,_pivot,plane_normal)-screen_plane(_start,_pivot,plane_normal)
	if _axis>=0: delta=delta-_axes[_axis]*delta.dot(_axes[_axis]) if _plane else _axes[_axis]*delta.dot(_axes[_axis])
	var snapping := snap!=ctrl
	if snapping: delta=delta.snapped(Vector3.ONE*grid_step)
	var angle := (_start-_source_screen()).angle_to(point-_source_screen())
	var factor := maxf(.01,1.+(point.x-_start.x-point.y+_start.y)/140.)
	if _axis>=0:
		var data := geometry(); var projected: Vector2=data.ends[_axis]-data.center if not data.is_empty() else Vector2.ZERO
		if projected.length_squared()>100: factor=maxf(.01,1.+(point-_start).dot(projected)/projected.length_squared())
		if tool=="Rotate" and absf(camera.basis.z.dot(_axes[_axis]))>.03:
			var a := screen_plane(_start,_pivot,_axes[_axis])-_pivot; var b := screen_plane(point,_pivot,_axes[_axis])-_pivot
			if a.length()>.00001 and b.length()>.00001: angle=a.signed_angle_to(b,_axes[_axis])
	if snapping: angle=snappedf(angle,deg_to_rad(15)); factor=snappedf(factor,.1)
	if not _numeric.is_empty() and _numeric.is_valid_float():
		var number := float(_numeric)
		if tool=="Move": delta=(_axes[_axis] if _axis>=0 else camera.basis.x)*number
		elif tool=="Rotate": angle=deg_to_rad(number)
		else: factor=number
	var rotation_axis := _axes[_axis] if _axis>=0 else camera.basis.z; var rotation := Basis(rotation_axis,angle)
	var placement_rotation := Basis.IDENTITY
	if tool=="Move" and snapping and snap_kind!="Grid":
		var hit := snap_target(point)
		if not hit.is_empty():
			delta=hit.point-_pivot
			if snap_kind=="Surface" and session.mode=="Object":
				var item := _source.component(session.primary().id); var transform := _source.world_transform(item)
				if align_surface: placement_rotation=Basis(Quaternion(transform.basis.y.normalized(),hit.normal))
				if item.mesh!=null:
					var support := INF; var box := item.mesh.bounds()
					for i in 8: support=minf(support,(placement_rotation*(transform*box.get_endpoint(i)-_pivot)).dot(hit.normal))
					delta-=hit.normal*support
	if session.mode=="Object":
		for id in session.selected:
			var original := _source.component(id); var item := session.document.component(id)
			if original==null or item==null or not session.document.editable_component(item): continue
			var nested := false
			for parent_id in session.selected:
				if _source.is_descendant(id,parent_id): nested=true; break
			if nested: continue
			var world_transform := _source.world_transform(original); var parent := _source.component(original.parent_id); var parent_transform := _source.world_transform(parent) if parent!=null else Transform3D.IDENTITY
			if tool=="Move": world_transform=Transform3D(placement_rotation*world_transform.basis,_pivot+placement_rotation*(world_transform.origin-_pivot)+delta)
			elif tool=="Rotate": world_transform=Transform3D(rotation*world_transform.basis,_pivot+rotation*(world_transform.origin-_pivot))
			else:
				var scale := Vector3.ONE*factor
				if _axis>=0: scale=Vector3.ONE; scale[_axis]=factor
				var basis := Basis(_axes[0],_axes[1],_axes[2]); var scaling := basis*Basis.from_scale(scale)*basis.inverse()
				world_transform=Transform3D(scaling*world_transform.basis,_pivot+scaling*(world_transform.origin-_pivot))
			item.transform=parent_transform.affine_inverse()*world_transform
	else:
		var item := session.primary(); var original := _source.component(item.id); var transform := _source.world_transform(original); var inverse := transform.affine_inverse()
		item.generator=""
		if proportional and not is_equal_approx(_weights_radius,radius):
			_weights.resize(item.mesh.vertices.size())
			for i in original.mesh.vertices.size():
				var closest := INF; var p := transform*original.mesh.vertices[i]
				if _selected_lookup.has(i): _weights[i]=1.; continue
				for index in _selected_vertices: closest=minf(closest,p.distance_to(transform*original.mesh.vertices[index]))
				_weights[i]=smoothstep(radius,0.,closest)
			_weights_radius=radius
		for i in item.mesh.vertices.size():
			var p := transform*original.mesh.vertices[i]; var weight := _weights[i] if proportional else (1. if _selected_lookup.has(i) else 0.)
			if weight<=0.: item.mesh.vertices[i]=original.mesh.vertices[i]; continue
			var moved := p+delta
			if tool=="Rotate": moved=_pivot+rotation*(p-_pivot)
			elif tool=="Scale":
				var offset := p-_pivot
				moved=_pivot+(offset*factor if _axis<0 else offset+_axes[_axis]*offset.dot(_axes[_axis])*(factor-1))
			item.mesh.vertices[i]=inverse*p.lerp(moved,weight)
	session.changed.emit()
func _source_screen() -> Vector2: return project(_pivot)
func finish_transform(cancel: bool=false) -> void:
	if not _drag: return
	_drag=false; _modal=false
	if cancel: session.cancel()
	else: session.commit(tool+" "+session.mode.to_lower())
	_source=null; _numeric=""; gesture_finished.emit()

func begin_extrusion(point: Vector2) -> bool:
	if session.mode!="Face" or session.primary()==null or session.primary().locked: return false
	if session.primary().skin_mesh!=null or session.primary().binding!=null: notice.emit("Detach the mesh in Rigging before editing topology."); return false
	if session.elements.is_empty(): select_at(point,false)
	if session.elements.is_empty(): return false
	_start=point; _source=session.document.snapshot(); session.begin(); _extruding=true; _extrude_amount=0.; _extrude_numeric=""; return true
func update_extrusion(point: Vector2, ctrl: bool=false) -> void:
	var original := _source.component(session.primary().id); var transform := _source.world_transform(original)
	var n := (transform.basis.inverse().transposed()*original.mesh.normal(session.elements[0])).normalized()
	var center := transform*original.mesh.center(session.elements[0]); var axis := project(center+n)-project(center)
	var pixels := point-_start
	var amount := pixels.dot(axis)/axis.length_squared() if axis.length()>12 else -pixels.y*distance*.002
	amount/=maxf(.0001,(transform.basis*original.mesh.normal(session.elements[0])).length())
	if snap!=ctrl: amount=snappedf(amount,grid_step)
	if _extrude_numeric.is_valid_float(): amount=float(_extrude_numeric)
	_extrude_amount=amount
	if absf(amount)<.00001: session.primary().mesh=original.mesh.copy_mesh()
	else: session.primary().mesh=KiwiModelGeometry.extrude(original.mesh,session.elements,amount).mesh
	session.primary().generator=""; session.changed.emit()
func finish_extrusion(cancel: bool=false) -> void:
	if not _extruding: return
	_extruding=false
	if cancel or absf(_extrude_amount)<.00001: session.cancel()
	else: session.commit("Push/pull faces")
	_source=null; gesture_finished.emit()
func snap_target(point: Vector2) -> Dictionary:
	var hit := pick(point,session.selected)
	if hit.is_empty(): return {}
	if snap_kind=="Surface": return hit
	var item := session.document.component(hit.id); var transform := session.document.world_transform(item)
	if snap_kind=="Origin": hit.point=transform.origin; return hit
	var closest := INF; var best: Vector3=hit.point
	if snap_kind=="Vertex":
		for p in item.mesh.vertices:
			var world_point := transform*p; var d := project(world_point).distance_to(point)
			if d<closest: closest=d; best=world_point
	else:
		for edge in item.mesh.edges():
			var a := transform*item.mesh.vertices[edge.a]; var b := transform*item.mesh.vertices[edge.b]
			var p := Geometry3D.get_closest_point_to_segment(hit.point,a,b); var d := project(p).distance_to(point)
			if d<closest: closest=d; best=p
	hit.point=best; return hit

func _draw_overlay() -> void:
	if session==null: return
	if rig_tool!=null and rig_tool.editor.enabled: rig_tool.draw(); return
	for item in session.document.components:
		if item.mesh==null or not session.document.visible_component(item): continue
		var selected := session.selected.has(item.id); var primary := item==session.primary(); var transform := session.document.world_transform(item)
		var mesh: KiwiModelMesh=evaluated.get(item.id,item.mesh)
		var front := {}; var normal_basis := transform.basis.inverse().transposed()
		if not xray and not wireframe:
			for f in mesh.faces.size(): front[f]=(normal_basis*mesh.normal(f)).dot(camera.position-transform*mesh.center(f))>0.
		if show_edges or wireframe or selected:
			for edge in mesh.edges():
				if not xray and not wireframe:
					var facing := false
					for f in edge.faces:
						if front.get(f,false): facing=true; break
					if not facing: continue
				var a := transform*mesh.vertices[edge.a]; var b := transform*mesh.vertices[edge.b]
				if camera.is_position_behind(a) or camera.is_position_behind(b): continue
				overlay.draw_line(project(a),project(b),(Color("e8b86f") if primary else Color("83bdf0")) if selected else Color(0.5,.65,.75,.3),1.2 if selected else .6,true)
		if not primary: continue
		if session.mode=="Face":
			for f in session.elements:
				if f>=item.mesh.faces.size(): continue
				if not xray and (normal_basis*item.mesh.normal(f)).dot(camera.position-transform*item.mesh.center(f))<=0.: continue
				var points := PackedVector2Array()
				for vertex in item.mesh.faces[f]: points.append(project(transform*item.mesh.vertices[vertex]))
				if points.size()>=3 and not Geometry2D.triangulate_polygon(points).is_empty(): overlay.draw_colored_polygon(points,Color(1.,.65,.25,.32))
		elif session.mode=="Vertex":
			var chosen := {}
			for index in session.elements: chosen[index]=true
			for i in item.mesh.vertices.size():
				var p := transform*item.mesh.vertices[i]
				if not camera.is_position_behind(p): overlay.draw_circle(project(p),4 if chosen.has(i) else 2.5,Color("ffcf83") if chosen.has(i) else Color("91b0c5"))
		elif session.mode=="Edge":
			var edges := item.mesh.edges()
			for index in session.elements:
				if index<edges.size(): overlay.draw_line(project(transform*item.mesh.vertices[edges[index].a]),project(transform*item.mesh.vertices[edges[index].b]),Color("ffce80"),3,true)
		if show_normals:
			for f in item.mesh.faces.size():
				var p := transform*item.mesh.center(f); overlay.draw_line(project(p),project(p+transform.basis*item.mesh.normal(f)*.15),Color("85ccf1"),1,true)
	var data := geometry()
	if not data.is_empty():
		for i in 3:
			if tool=="Rotate": overlay.draw_polyline(data.rings[i],COLORS[i],2,true)
			elif data.center.distance_to(data.ends[i])>15:
				overlay.draw_line(data.center,data.ends[i],Color("0b1520"),5,true); overlay.draw_line(data.center,data.ends[i],COLORS[i],2.4,true)
				if tool=="Scale": overlay.draw_rect(Rect2(data.ends[i]-Vector2(5,5),Vector2(10,10)),COLORS[i])
				else:
					var direction: Vector2=(data.ends[i]-data.center).normalized(); var side := direction.orthogonal(); var tip: Vector2=data.ends[i]
					overlay.draw_colored_polygon(PackedVector2Array([tip+direction*4,tip-direction*9+side*5,tip-direction*9-side*5]),COLORS[i])
				overlay.draw_string(ThemeDB.fallback_font,data.ends[i]+Vector2(7,-4),["X","Y","Z"][i],HORIZONTAL_ALIGNMENT_LEFT,-1,12,COLORS[i])
		if tool!="Rotate": overlay.draw_rect(Rect2(data.center-Vector2(5,5),Vector2(10,10)),Color("ffe1a0"))
	if _box: overlay.draw_rect(Rect2(_start,_mouse-_start).abs(),Color(.3,.8,.7,.12)); overlay.draw_rect(Rect2(_start,_mouse-_start).abs(),Color("76e2c2"),false,1)
	var compass := Vector2(size.x-42,38)
	for i in 3:
		var direction: Vector3=camera.basis.inverse()*[Vector3.RIGHT,Vector3.UP,Vector3.BACK][i]
		var end: Vector2=compass+Vector2(direction.x,-direction.y)*22
		overlay.draw_line(compass,end,COLORS[i],2,true); overlay.draw_circle(end,3,COLORS[i]); overlay.draw_string(ThemeDB.fallback_font,end+Vector2(4,-4),["X","Y","Z"][i],HORIZONTAL_ALIGNMENT_LEFT,-1,11,COLORS[i])
	if not sculpt.is_empty():
		var hit := pick(_mouse)
		if not hit.is_empty():
			var pixel_radius := project(hit.point+camera.basis.x*radius).distance_to(project(hit.point)); overlay.draw_arc(_mouse,pixel_radius,0,TAU,64,Color("84e6ca"),1.5,true)
	var hint := "RMB fly · MMB orbit · Shift+MMB pan · Wheel zoom · F frame · 1–4 selection · W/E/R transform"
	if _drag: hint=tool+"  "+_numeric+"  · X/Y/Z constrain · Shift+axis plane · Ctrl snap · Enter confirm · Esc cancel"
	elif _extruding: hint="Push/pull %.3f · Type a distance · Ctrl snap · Enter confirm · Esc cancel"%_extrude_amount
	elif _create_phase>0: hint="Drag footprint, release, then set height · Click confirms · Esc cancels"
	overlay.draw_string(ThemeDB.fallback_font,Vector2(12,size.y-14),hint,HORIZONTAL_ALIGNMENT_LEFT,size.x-24,11,Color("91acbc"))

func start_creation(kind: String) -> void: _create=kind; _create_phase=0; sculpt=""; grab_focus()
func _creation_input(event: InputEvent) -> bool:
	if _create.is_empty(): return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if _create_phase>0: session.cancel()
		_create=""; _create_phase=0; gesture_finished.emit(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and _create_phase==0:
			session.begin(); _start=event.position; _create_origin=screen_plane(_start,Vector3.ZERO,Vector3.UP)
			_create_component=KiwiModelComponent.new(); _create_component.id=ActorData.new_id(); _create_component.title=_create; _create_component.generator=_create; _create_component.mesh=KiwiModelPrimitives.create(_create)
			session.document.components.append(_create_component); session.selected.assign([_create_component.id]); _create_phase=1
		elif not event.pressed and _create_phase==1: _create_phase=2; _start=event.position
		elif event.pressed and _create_phase==2:
			session.commit("Draw "+_create); _create=""; _create_phase=0; gesture_finished.emit()
		return true
	if event is InputEventMouseMotion and _create_phase>0:
		var params := _create_component.parameters.duplicate(); var height := maxf(.05,absf((_start.y-event.position.y)*.02))
		if _create_phase==1:
			var end := screen_plane(event.position,Vector3.ZERO,Vector3.UP); var size := (end-_create_origin).abs().max(Vector3(.05,.05,.05)); size.y=1
			params={"size":size,"radius":maxf(size.x,size.z)*.5,"height":1.}
			_create_component.transform.origin=(_create_origin+end)*.5+Vector3.UP*.5
		else:
			params["height"]=height; var dims: Vector3=params.get("size",Vector3.ONE); dims.y=height; params.size=dims; _create_component.transform.origin.y=height*.5
		_create_component.parameters=params; _create_component.mesh=KiwiModelPrimitives.create(_create,params); session.changed.emit(); return true
	return true

func sculpt_at(point: Vector2, previous: Vector2, erase: bool=false) -> void:
	var item := session.primary(); var hit := pick(point)
	if item==null or item.mesh==null or item.locked or item.skin_mesh!=null or item.binding!=null or hit.get("id","")!=item.id: return
	var transform := session.document.world_transform(item); var inverse := transform.affine_inverse(); var center: Vector3=hit.point; var normal: Vector3=hit.normal
	var mesh := item.mesh; var relaxed := KiwiModelGeometry.smooth_mesh(mesh,strength) if sculpt=="Smooth" else null
	var delta := screen_plane(point,center)-screen_plane(previous,center); var sign := -1. if erase else 1.
	for i in mesh.vertices.size():
		var p := transform*mesh.vertices[i]; var weight := smoothstep(radius,0.,p.distance_to(center))*strength
		if weight<=0.: continue
		match sculpt:
			"Grab": p+=delta*weight*3
			"Inflate": p+=normal*weight*.05*sign
			"Smooth": p=p.lerp(transform*relaxed.vertices[i],weight)
			"Flatten": p-=normal*(p-center).dot(normal)*weight
			"Pinch": p=p.lerp(center,weight*.15)
		mesh.vertices[i]=inverse*p
	item.mesh=mesh; item.generator=""; session.changed.emit()

func _gui_input(event: InputEvent) -> void:
	if rig_tool!=null and not _navigating and not _panning and not _orbiting and rig_tool.handle_event(event): overlay.queue_redraw(); accept_event(); return
	if event is InputEventMouseMotion:
		var previous := _mouse; _mouse=event.position
		if _navigating or _orbiting: yaw-=event.relative.x*.006; pitch=clampf(pitch-event.relative.y*.006,-PI*.495,PI*.495); update_camera()
		elif _panning: target+=(-camera.basis.x*event.relative.x+camera.basis.y*event.relative.y)*distance*.0015; update_camera()
		elif _creation_input(event): pass
		elif _extruding: update_extrusion(event.position,event.ctrl_pressed)
		elif _drag: update_transform(event.position,event.ctrl_pressed)
		elif _pressed and not sculpt.is_empty(): sculpt_at(event.position,previous,event.ctrl_pressed)
		elif _pressed and event.position.distance_to(_start)>5: _box=true
		overlay.queue_redraw(); accept_event(); return
	if event is InputEventMouseButton:
		grab_focus()
		if event.button_index==MOUSE_BUTTON_RIGHT:
			if _extruding: finish_extrusion(true)
			elif _drag: finish_transform(true)
			else: _navigating=event.pressed
			accept_event(); return
		if event.button_index==MOUSE_BUTTON_MIDDLE: _panning=event.pressed and event.shift_pressed; _orbiting=event.pressed and not event.shift_pressed; accept_event(); return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var factor := 1.12 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else 1./1.12
			if _navigating: fly_speed=clampf(fly_speed/factor,.1,100)
			elif event.shift_pressed and (not sculpt.is_empty() or proportional): radius=clampf(radius/factor,.02,100)
			else: distance=clampf(distance*factor,.1,1000); camera.size=clampf(camera.size*factor,.05,1000); update_camera()
			accept_event(); return
		if _creation_input(event): accept_event(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		if event.pressed:
			var compass := Vector2(size.x-42,38)
			for i in 3:
				var direction: Vector3=camera.basis.inverse()*[Vector3.RIGHT,Vector3.UP,Vector3.BACK][i]
				if event.position.distance_to(compass+Vector2(direction.x,-direction.y)*22)<9:
					set_view((["Left","Bottom","Back"] if event.shift_pressed else ["Right","Top","Front"])[i]); accept_event(); return
			if _modal: finish_transform(); accept_event(); return
			_start=event.position; _mouse=event.position
			if (push_pull or event.alt_pressed) and session.mode=="Face": begin_extrusion(event.position)
			elif not sculpt.is_empty(): session.begin(); _pressed=true; sculpt_at(event.position,event.position,event.ctrl_pressed)
			else:
				var handle := handle_at(event.position,geometry()) if not event.shift_pressed and not event.ctrl_pressed else -2
				if handle!=-2: begin_transform(handle,event.position)
				else: _pressed=true
		else:
			if _extruding: finish_extrusion()
			elif _drag: finish_transform()
			elif _pressed and not sculpt.is_empty(): session.commit(sculpt+" deformation"); gesture_finished.emit()
			elif _box: box_select(Rect2(_start,event.position-_start).abs(),event.shift_pressed or event.ctrl_pressed)
			elif _pressed: select_at(event.position,event.shift_pressed or event.ctrl_pressed)
			_pressed=false; _box=false
		accept_event(); return
	if not event is InputEventKey or not event.pressed or event.echo or _navigating: return
	if _creation_input(event): accept_event(); return
	if _extruding:
		if event.keycode==KEY_ESCAPE: finish_extrusion(true)
		elif event.keycode==KEY_ENTER: finish_extrusion()
		elif event.keycode==KEY_BACKSPACE: _extrude_numeric=_extrude_numeric.left(-1)
		elif event.unicode>=32 and char(event.unicode) in "0123456789.-": _extrude_numeric+=char(event.unicode)
		if _extruding: update_extrusion(_mouse,event.ctrl_pressed)
		accept_event(); return
	if _drag:
		if event.keycode==KEY_ESCAPE: finish_transform(true)
		elif event.keycode==KEY_ENTER: finish_transform()
		elif event.keycode in [KEY_X,KEY_Y,KEY_Z]: _axis=[KEY_X,KEY_Y,KEY_Z].find(event.keycode); _plane=event.shift_pressed
		elif event.keycode==KEY_BACKSPACE: _numeric=_numeric.left(-1)
		elif event.unicode>=32 and char(event.unicode) in "0123456789.-": _numeric+=char(event.unicode)
		update_transform(_mouse,event.ctrl_pressed); accept_event(); return
	if event.ctrl_pressed:
		if event.keycode==KEY_Z: session.redo() if event.shift_pressed else session.undo()
		elif event.keycode==KEY_Y: session.redo()
		elif event.keycode==KEY_D:
			session.duplicate_selected(true); tool="Move"
			if not begin_transform(-1,_mouse,true): session.cancel()
		elif event.keycode==KEY_A: command_requested.emit("Select all")
		elif event.keycode==KEY_I: command_requested.emit("Invert selection")
		else: return
	elif event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]: session.mode=["Object","Vertex","Edge","Face"][event.keycode-KEY_1]; session.elements=PackedInt32Array(); session.changed.emit()
	elif event.keycode in [KEY_W,KEY_E,KEY_R]: tool={KEY_W:"Move",KEY_E:"Rotate",KEY_R:"Scale"}[event.keycode]; sculpt=""; overlay.queue_redraw(); gesture_finished.emit()
	elif event.keycode==KEY_G: tool="Move"; begin_transform(-1,_mouse,true)
	elif event.keycode==KEY_S: tool="Scale"; begin_transform(-1,_mouse,true)
	elif event.keycode==KEY_F: frame(event.shift_pressed)
	elif event.keycode==KEY_TAB: session.mode="Face" if session.mode=="Object" else "Object"; session.elements=PackedInt32Array(); session.changed.emit()
	elif event.keycode in [KEY_DELETE,KEY_BACKSPACE]: notice.emit(session.delete_selected())
	elif event.keycode==KEY_SPACE: command_requested.emit("Search")
	elif event.keycode==KEY_ESCAPE: sculpt=""; session.cancel(); overlay.queue_redraw()
	else: return
	accept_event()

func capture_state() -> Dictionary:
	return {"target":target,"distance":distance,"yaw":yaw,"pitch":pitch,"orthographic":camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"camera_size":camera.size,"grid_step":grid_step,"snap":snap,"xray":xray,"show_edges":show_edges,"tool":tool,"local_axes":local_axes,"wireframe":wireframe,"normals":show_normals,"grid_visible":grid.visible,"snap_kind":snap_kind,"align_surface":align_surface,"proportional":proportional,"radius":radius,"strength":strength,"sculpt":sculpt,"push_pull":push_pull,"fly_speed":fly_speed}
func cancel_all() -> void:
	if rig_tool!=null: rig_tool.finish(true); rig_tool.chain=null; rig_tool.placing=false
	finish_transform(true); finish_extrusion(true)
	if not session._gesture.is_empty(): session.cancel()
	_pressed=false; _box=false; _navigating=false; _panning=false; _orbiting=false; _create=""; _create_phase=0
func restore_state(state: Dictionary) -> void:
	target=state.get("target",Vector3.ZERO); distance=state.get("distance",7.); yaw=state.get("yaw",.65); pitch=state.get("pitch",-.4)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL if state.get("orthographic",false) else Camera3D.PROJECTION_PERSPECTIVE; camera.size=state.get("camera_size",6.)
	grid_step=state.get("grid_step",.25); snap=state.get("snap",false); xray=state.get("xray",false); show_edges=state.get("show_edges",true); tool=state.get("tool","Move"); local_axes=state.get("local_axes",false)
	wireframe=state.get("wireframe",false); show_normals=state.get("normals",false); grid.visible=state.get("grid_visible",true); snap_kind=state.get("snap_kind","Grid"); align_surface=state.get("align_surface",false)
	proportional=state.get("proportional",false); radius=state.get("radius",1.5); strength=state.get("strength",.3); sculpt=state.get("sculpt",""); push_pull=state.get("push_pull",false); fly_speed=state.get("fly_speed",4.)
	rebuild_grid(); update_camera(); request_sync()
