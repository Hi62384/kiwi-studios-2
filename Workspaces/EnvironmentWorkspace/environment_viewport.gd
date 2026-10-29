class_name KiwiEnvironmentViewport
extends KiwiModelViewport
signal brush_settings_changed
signal asset_placed(path: String,point: Vector3,normal: Vector3)
signal cave_replaced(terrain_id: String,cave: KiwiTerrainCave)
signal water_replaced(terrain_id: String,source: KiwiTerrainHydrology)
signal biomes_replaced(terrain_id: String,source: KiwiTerrainBiomes)
signal world_replaced(world_id: String,source: Resource)
const BRUSH_TOOLS:=["Raise","Lower","Smooth","Flatten","Level to height","Terrace","Noise","Ridge","Valley","Pinch / sharpen","Relax","Erode brush","Stamp"]
var renderer:=KiwiEnvironmentRuntime.new()
var environment_tool:="Select"
var brush_radius:=2.
var brush_strength:=.2
var brush_falloff:=1.
var brush_spacing:=.2
var brush_target_height:=0.
var brush_terrace_step:=.5
var brush_square:=false
var brush_symmetry_x:=false
var brush_symmetry_z:=false
var stamp_path:=""
var stamp_image: Image
var placement_asset:=""
var _painting:=false
var _painting_id:=""
var _last_dab:=Vector2.ZERO
var _flatten_height:=0.
var _brush_hit: Dictionary={}
var _triangles: Dictionary={}
var _drop_preview: Node3D
var _drop_path:=""
var _preview_environment: Environment
var _environment_key:=0
var cave_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_cave_tool.gd").new()
var water_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_water_tool.gd").new()
var biome_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_biome_tool.gd").new()
var road_tool:=preload("res://Workspaces/EnvironmentWorkspace/world/world_road_tool.gd").new()

func _ready() -> void:
	road_tool.canvas=self
	cave_tool.canvas=self; water_tool.canvas=self; biome_tool.canvas=self; super._ready(); renderer.progressive=true; renderer.animate_preview=true; renderer.priority_camera=camera; world.add_child(renderer); grid.hide(); show_edges=false; request_sync()
func capture_state() -> Dictionary:
	var state:=super.capture_state(); state["water_handle"]={"path":water_tool.river_index,"point":water_tool.point_index}; state["biome_id"]=biome_tool.biome_id; return state
func restore_state(state: Dictionary) -> void:
	var settings:=state.duplicate(); settings["grid_visible"]=bool(settings.get("grid_visible",false)); super.restore_state(settings)
	var water: Dictionary=state.get("water_handle",{}); water_tool.river_index=int(water.get("path",0)); water_tool.point_index=int(water.get("point",0))
	biome_tool.biome_id=str(state.get("biome_id",""))
func frame(all: bool=false) -> void:
	super.frame(all); distance*=.65; camera.size*=.7; update_camera()
func environment_session() -> KiwiEnvironmentSession: return session as KiwiEnvironmentSession
func sync() -> void:
	if environment_session()==null: return
	renderer.configure(environment_session().environment()); evaluated.clear()
	_sync_lighting()
	for item in session.document.components: evaluated[item.id]=item.mesh
	_pending_sync=false; overlay.queue_redraw()

func _sync_lighting() -> void:
	var document:=environment_session().environment(); var lights:=world.find_children("*","DirectionalLight3D",false,false)
	var state: Dictionary={}
	if document.climate!=null and document.climate.has_method("evaluate"): state=document.climate.evaluate(camera.global_position,renderer.preview_time)
	if not lights.is_empty():
		var sun:=lights[0] as DirectionalLight3D
		if state.is_empty(): sun.visible=bool(document.sunlight.get("enabled",true)); sun.rotation_degrees=document.sunlight.get("rotation",Vector3(-45,-30,0)); sun.light_color=document.sunlight.get("color",Color.WHITE); sun.light_energy=float(document.sunlight.get("energy",1.5))
		else:
			var direction: Vector3=state.sun_direction; sun.visible=bool(document.sunlight.get("enabled",true)) and state.sun_elevation>deg_to_rad(-10.); sun.basis=Basis.looking_at(-direction.normalized(),Vector3.UP); var authored_color: Color=document.sunlight.get("color",Color.WHITE); sun.light_color=authored_color.lerp(Color(1.,.55,.3),clampf(1.-absf(state.sun_elevation)/.25,0.,1.)*.55); sun.light_energy=float(document.sunlight.get("energy",1.5))*float(state.sunlight_energy)
	if lights.size()>1: lights[1].visible=false
	var key:=KiwiEnvironmentAssets.world_stamp(document)
	if key!=_environment_key:
		_environment_key=key; var environment:=KiwiEnvironmentAssets.world_environment(document)
		if document.climate!=null and document.climate.has_method("make_environment"): environment=environment.duplicate(true) as Environment if environment!=null else document.climate.make_environment(renderer.preview_time)
		for child in world.get_children():
			if child is WorldEnvironment:
				if _preview_environment==null: _preview_environment=child.environment
				child.environment=environment if environment!=null else _preview_environment
	for child in world.get_children():
		if child is WorldEnvironment and document.climate!=null and document.climate.has_method("apply_environment"):
			var position:=camera.global_position; state=document.climate.apply_environment(child.environment,renderer.preview_time,position); renderer.update_weather_particles(state,camera)
func geometry() -> Dictionary: return super.geometry() if environment_tool=="Select" else {}
func _process(delta: float) -> void:
	if not environment_tool in ["Paint biome","Erase biome"] and not biome_tool._stroke.is_empty(): biome_tool.cancel()
	super._process(delta)
	_sync_lighting()
	var info:=biome_tool.target() if environment_tool in ["Paint biome","Erase biome"] else {}; var selected:=str(info.get("id","")); var biome:=biome_tool.biome_id if not info.is_empty() else ""
	if selected!=renderer.biome_preview_terrain or biome!=renderer.biome_preview_id: renderer.biome_preview_terrain=selected; renderer.biome_preview_id=biome; request_sync()
	if is_instance_valid(_drop_preview) and not Rect2(Vector2.ZERO,size).has_point(get_local_mouse_position()): _drop_preview.hide()

func _pick(point: Vector2,terrain_only: bool,excluded: Array[String]) -> Dictionary:
	if _pending_sync: sync()
	var ray_data:=ray(point); var best: float=camera.far; var result:={}
	for item in session.document.components:
		if excluded.has(item.id) or not session.document.editable_component(item) or not renderer.nodes.has(item.id): continue
		if terrain_only and environment_session().environment().component_kind(item.id)!="terrain": continue
		var owner: Node3D=renderer.nodes[item.id]
		for visual: Node in owner.find_children("*","MeshInstance3D",true,false):
			var mesh:=visual as MeshInstance3D
			if terrain_only and mesh.get_meta("terrain_water",false): continue
			if mesh.mesh==null or not mesh.is_visible_in_tree() or absf(mesh.global_basis.determinant())<.000001: continue
			if mesh.visibility_range_end>0. and camera.global_position.distance_to(mesh.global_transform*mesh.mesh.get_aabb().get_center())>mesh.visibility_range_end+mesh.visibility_range_end_margin: continue
			var inverse:=mesh.global_transform.affine_inverse(); var origin: Vector3=inverse*ray_data.origin; var direction: Vector3=(inverse.basis*ray_data.direction).normalized()
			if mesh.mesh.get_aabb().intersects_ray(origin,direction)==null: continue
			var key:=mesh.mesh.get_instance_id()
			if not _triangles.has(key):
				if _triangles.size()>=128: _triangles.erase(_triangles.keys()[0])
				_triangles[key]=mesh.mesh.generate_triangle_mesh()
			var triangles:=_triangles[key] as TriangleMesh
			if triangles==null: continue
			var hit:=triangles.intersect_ray(origin,direction)
			if hit.is_empty(): continue
			var world_point: Vector3=mesh.global_transform*hit.position; var distance: float=ray_data.origin.distance_to(world_point)
			if distance<best:
				best=distance; var transform:=session.document.world_transform(item); result={"id":item.id,"point":world_point,"local":transform.affine_inverse()*world_point,"normal":(mesh.global_basis.inverse().transposed()*(hit.normal as Vector3)).normalized()}
	return result
func pick(point: Vector2,excluded: Array[String]=[]) -> Dictionary: return _pick(point,false,excluded)
func pick_terrain(point: Vector2) -> Dictionary: return _pick(point,true,[])

func _draw_overlay() -> void:
	if session==null: return
	for id in session.selected:
		var item:=session.document.component(id)
		if item==null or item.mesh==null or not session.document.visible_component(item): continue
		var transform:=session.document.world_transform(item); var box:=item.mesh.bounds(); var points:=PackedVector3Array()
		for corner in 8: points.append(transform*(box.position+box.size*Vector3(corner&1,(corner>>1)&1,(corner>>2)&1)))
		for corner in 8:
			for axis in 3:
				var other:=corner^(1<<axis)
				if other<corner or camera.is_position_behind(points[corner]) or camera.is_position_behind(points[other]): continue
				overlay.draw_line(project(points[corner]),project(points[other]),Color("ffca7d") if item==session.primary() else Color("6bbfee"),1.5,true)
	_draw_handles_and_navigation("RMB fly · MMB orbit · Shift+MMB pan · F frame · W/E/R transform")
	cave_tool.draw()
	water_tool.draw()
	road_tool.draw()
	if (environment_tool in BRUSH_TOOLS or environment_tool in ["Paint material","Paint biome","Erase biome","Paint scatter","Erase scatter"]) and not _brush_hit.is_empty():
		var item:=session.document.component(str(_brush_hit.id)); var terrain:=environment_session().environment().terrain(item.id); var local: Vector3=_brush_hit.local; var transform:=session.document.world_transform(item); var ring:=PackedVector2Array()
		for i in 49:
			var direction:=Vector2(cos(i*TAU/48.),sin(i*TAU/48.))
			if brush_square: direction/=maxf(absf(direction.x),absf(direction.y))
			var point:=Vector2(local.x,local.z)+direction*brush_radius; var surface:=terrain.sample(point)
			if not surface.is_empty(): ring.append(project(transform*Vector3(point.x,float(surface.height)+.025,point.y)))
		if ring.size()>1: overlay.draw_polyline(ring,Color("7de3c5"),2.,true)

func _dab(point: Vector2,subtract: bool) -> void:
	if environment_tool in ["Paint scatter","Erase scatter"]:
		environment_session().paint_scatter(point,brush_radius,(environment_tool=="Erase scatter")!=subtract); request_sync(); return
	var operation: int=maxi(0,BRUSH_TOOLS.find(environment_tool))
	if subtract and operation in [0,1]: operation=1-operation
	var strength: float=-brush_strength if subtract and operation in [6,7,8,12] else brush_strength; var options:={"target":brush_target_height,"terrace_step":brush_terrace_step,"square":brush_square,"stamp":stamp_image}; var points: Array[Vector2]=[point]
	if brush_symmetry_x: points.append(Vector2(-point.x,point.y))
	if brush_symmetry_z:
		var existing:=points.duplicate()
		for sample in existing: points.append(Vector2(sample.x,-sample.y))
	var seen:={}
	for sample in points:
		if seen.has(sample): continue
		seen[sample]=true; environment_session().sculpt(sample,brush_radius,strength,brush_falloff,operation,_flatten_height,options)
	request_sync()
func _gui_input(event: InputEvent) -> void:
	if road_tool.input(event): accept_event(); return
	if biome_tool.input(event): accept_event(); return
	if water_tool.input(event): accept_event(); return
	if cave_tool.input(event): accept_event(); return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE and _painting: _finish_brush(true); request_sync(); accept_event(); return
		if event.keycode in [KEY_TAB,KEY_1,KEY_2,KEY_3,KEY_4]: accept_event(); return
		if event.keycode in [KEY_W,KEY_E,KEY_R,KEY_G,KEY_S] and not _navigating and not event.ctrl_pressed: environment_tool="Select"
	if event is InputEventMouseButton and event.pressed and event.shift_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and environment_tool!="Select":
		brush_radius=clampf(brush_radius*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1./1.15),.05,1000.); brush_settings_changed.emit(); overlay.queue_redraw(); accept_event(); return
	if (environment_tool in BRUSH_TOOLS or environment_tool in ["Paint material","Paint scatter","Erase scatter"]) and not _navigating and not _panning and not _orbiting:
		if event is InputEventMouseMotion:
			_mouse=event.position; _brush_hit=pick_terrain(event.position)
			if _painting and not _brush_hit.is_empty() and str(_brush_hit.id)==_painting_id:
				var current:=Vector2((_brush_hit.local as Vector3).x,(_brush_hit.local as Vector3).z); var count:=clampi(ceili(current.distance_to(_last_dab)/maxf(.05,brush_radius*brush_spacing)),1,64)
				for i in range(1,count+1): _dab(_last_dab.lerp(current,float(i)/count),event.ctrl_pressed)
				_last_dab=current
			overlay.queue_redraw(); accept_event(); return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			grab_focus()
			if event.pressed:
				_brush_hit=pick_terrain(event.position)
				if not _brush_hit.is_empty():
					var scatter_mode:=environment_tool in ["Paint scatter","Erase scatter"]; var valid:=false
					if scatter_mode:
						var selected:=session.primary(); var scatter:=environment_session().environment().component_settings.get(selected.id,{}).get("scatter") as KiwiEnvironmentScatter if selected!=null else null
						valid=scatter!=null and scatter.terrain_id==str(_brush_hit.id) and environment_session().begin_scatter(selected.id)
					else: valid=environment_session().begin_terrain(str(_brush_hit.id),environment_tool=="Paint material")
					if valid:
						_painting=true; _painting_id=str(_brush_hit.id)
						if not scatter_mode: session.select(_painting_id)
						var local: Vector3=_brush_hit.local; _last_dab=Vector2(local.x,local.z); _flatten_height=local.y; _dab(_last_dab,event.ctrl_pressed)
			elif _painting: _finish_brush(); gesture_finished.emit()
			accept_event(); return
	if environment_tool=="Place" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var hit:=pick_terrain(event.position)
		if not hit.is_empty() and not placement_asset.is_empty(): asset_placed.emit(placement_asset,_placement_point(hit.point,str(hit.id)),hit.normal)
		accept_event(); return
	super._gui_input(event)

func _can_drop_data(point: Vector2,data: Variant) -> bool:
	var paths:=ActorTimelineCanvas.dropped_paths(data)
	if paths.size()!=1: return false
	var path:=paths[0]
	if not path.get_extension().to_lower() in ["tres","res","mesh","obj","gltf","glb"]: return false
	var source:=KiwiEnvironmentAssets.load_parts(path)
	if not str(source.error).is_empty(): return false
	var hit:=pick_terrain(point)
	if hit.is_empty(): return false
	if _drop_preview==null or path!=_drop_path:
		_clear_preview(); _drop_preview=Node3D.new(); world.add_child(_drop_preview); _drop_path=path
		for part: Dictionary in source.parts:
			var visual:=MeshInstance3D.new(); visual.mesh=part.mesh; visual.transform=part.transform; visual.transparency=.45; _drop_preview.add_child(visual)
	_drop_preview.show(); _drop_preview.position=_placement_point(hit.point,str(hit.id)); _drop_preview.basis=Basis(Quaternion(Vector3.UP,(hit.normal as Vector3).normalized())) if align_surface else Basis.IDENTITY; return true
func _drop_data(point: Vector2,data: Variant) -> void:
	if not _can_drop_data(point,data): return
	var hit:=pick_terrain(point); var path:=_drop_path; _clear_preview(); asset_placed.emit(path,_placement_point(hit.point,str(hit.id)),hit.normal)
func _placement_point(point: Vector3,terrain_id: String="") -> Vector3:
	if snap!=Input.is_physical_key_pressed(KEY_CTRL):
		point.x=snappedf(point.x,grid_step); point.z=snappedf(point.z,grid_step); var terrain:=environment_session().environment().terrain(terrain_id); var item:=session.document.component(terrain_id)
		if terrain!=null and item!=null:
			var transform:=session.document.world_transform(item); var local:=transform.affine_inverse()*point; var surface:=terrain.sample(Vector2(local.x,local.z))
			if not surface.is_empty(): point=transform*Vector3(local.x,float(surface.height),local.z)
	return point
func _clear_preview() -> void:
	if is_instance_valid(_drop_preview): _drop_preview.queue_free()
	_drop_preview=null; _drop_path=""
func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END: _clear_preview()
func cancel_all() -> void:
	if road_tool.canvas!=null: road_tool.cancel()
	if cave_tool.canvas!=null: cave_tool.cancel()
	if water_tool.canvas!=null: water_tool.cancel()
	if biome_tool.canvas!=null: biome_tool.cancel()
	if _painting: _finish_brush(true)
	_clear_preview(); super.cancel_all()
func _finish_brush(cancelled: bool=false) -> void:
	environment_session().finish_terrain(cancelled); environment_session().finish_scatter(cancelled); _painting=false

