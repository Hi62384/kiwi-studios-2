extends Node
## One coordinator per viewport. Copies only the Environment resource, retains
## its sky and every unrelated option, and restores the owner when fog ends.
var world: World3D
var source: Environment
var overlay: Environment
var source_dirty:=true
var entries: Array[WeakRef]=[]
var camera_ref: WeakRef
var camera_source: Environment
var camera_overlay: Environment
var camera_dirty:=true
var source_signature: int=0
var camera_signature: int=0
static var environment_keys: PackedStringArray=[]
var lights: Array[WeakRef]=[]
var shadow_signature: int=-1
var resize_frame: int=-1
var original_scale:=1.
var temporary_scale:=1.

func _ready() -> void:
	for light in get_viewport().find_children("*","Light3D",true,false): _light_added(light)
	get_tree().node_added.connect(_light_added)
func _light_added(node: Node) -> void:
	if node is Light3D and node.is_inside_tree() and node.get_world_3d()==world: lights.append(weakref(node))
func _sync_shadow_buffers() -> void:
	var viewport:=get_viewport()
	if resize_frame>=0 and Engine.get_process_frames()>resize_frame:
		if is_equal_approx(viewport.scaling_3d_scale,temporary_scale): viewport.scaling_3d_scale=original_scale
		resize_frame=-1
	var enabled:=PackedInt64Array()
	for index in range(lights.size()-1,-1,-1):
		var light:=lights[index].get_ref() as Light3D
		if light==null: lights.remove_at(index); continue
		if light.shadow_enabled and light.is_visible_in_tree(): enabled.append(light.get_instance_id())
	enabled.sort(); var signature:=hash([enabled,viewport.positional_shadow_atlas_size,viewport.positional_shadow_atlas_16_bits])
	if signature==shadow_signature: return
	shadow_signature=signature
	if enabled.is_empty(): return
	# Godot 4.6 may retain a pre-allocation shadow-atlas binding in existing fog
	# buffers when positional shadows are enabled at runtime (upstream #83685).
	# A one-frame internal resolution change recreates that binding; authored output
	# size and scale are restored. This is never repeated for moving light/caster poses.
	if resize_frame<0:
		original_scale=viewport.scaling_3d_scale; var change:=2./maxf(64.,minf(viewport.size.x,viewport.size.y)); temporary_scale=clampf(original_scale-change if original_scale>.15 else original_scale+change,.1,2.); viewport.scaling_3d_scale=temporary_scale; resize_frame=Engine.get_process_frames()

static func attach(runtime: Node) -> void:
	var viewport:=runtime.get_viewport()
	var coordinator:=viewport.get_node_or_null("KiwiFogEnvironment")
	if coordinator==null:
		coordinator=load("res://scripts/actors/fog/fog_environment.gd").new(); coordinator.name="KiwiFogEnvironment"; coordinator.world=viewport.find_world_3d(); coordinator.process_priority=100; viewport.add_child(coordinator)
	coordinator.entries.append(weakref(runtime))

func _process(_delta: float) -> void:
	if world==null: return
	var active: Array[Node]=[]; var globals: Array[Node]=[]
	for index in range(entries.size()-1,-1,-1):
		var runtime: Node=entries[index].get_ref()
		if runtime==null: entries.remove_at(index); continue
		if not runtime.active:
			var shadow:=runtime.content.get_node_or_null("KiwiCloudShadow") as Decal
			if shadow!=null: shadow.hide()
		if not runtime.active: continue
		active.append(runtime)
		# Legacy World-shaped Fog Volumes (including subtractive custom shaders)
		# retain additive native behavior. Only explicit Global Fog owns atmosphere.
		if runtime.actor.type_id==&"global_fog": globals.append(runtime)
	globals.sort_custom(func(a: Node,b: Node): return str(a.actor.id)<str(b.actor.id))
	var sun: DirectionalLight3D; var energy:=0.
	for reference in lights:
		var candidate:=reference.get_ref() as DirectionalLight3D
		if candidate!=null and candidate.is_visible_in_tree() and candidate.light_energy*candidate.light_volumetric_fog_energy>energy:
			sun=candidate; energy=candidate.light_energy*candidate.light_volumetric_fog_energy
	var camera:=get_viewport().get_camera_3d()
	for runtime in active:
		var material:=runtime.content.material as ShaderMaterial
		preload("res://scripts/actors/fog/fog_cloud_shadow.gd").sync(runtime,sun,runtime.actor.animation_time if not is_nan(runtime.actor.animation_time) else 0.,get_viewport().get_meta("kiwi_scene_frame_capture",false))
		if material==null or material.shader!=preload("res://scripts/actors/fog/fog_surface.gdshader"): continue
		preload("res://scripts/actors/fog/fog_ground_sampler.gd").sync(runtime,material)
		material.set_shader_parameter("sun_direction",sun.global_basis.z.normalized() if sun!=null else Vector3.UP); material.set_shader_parameter("sun_color",sun.light_color*energy if sun!=null else Color.BLACK); material.set_shader_parameter("viewer_position",camera.global_position if camera!=null else Vector3.ZERO)
	for index in globals.size(): globals[index].content.visible=index==0
	if active.is_empty():
		if resize_frame>=0:
			if is_equal_approx(get_viewport().scaling_3d_scale,temporary_scale): get_viewport().scaling_3d_scale=original_scale
			resize_frame=-1
		_restore_camera()
		if world.environment==overlay: world.environment=source
		return
	if world.environment!=overlay:
		if source!=world.environment:
			if source!=null and source.changed.is_connected(_dirty): source.changed.disconnect(_dirty)
			source=world.environment
			if source!=null: source.changed.connect(_dirty)
			source_dirty=true
	var signature:=environment_signature(source)
	if signature!=source_signature: source_signature=signature; source_dirty=true
	if source_dirty or overlay==null:
		overlay=source.duplicate() as Environment if source!=null else Environment.new(); source_dirty=false
	overlay.volumetric_fog_enabled=true
	overlay.volumetric_fog_temporal_reprojection_enabled=false if get_viewport().get_meta("kiwi_scene_frame_capture",false) else (source.volumetric_fog_temporal_reprojection_enabled if source!=null else true)
	# A global actor replaces the environment's background density; local actors
	# remain additive to intentional environment fog.
	overlay.volumetric_fog_density=0. if not globals.is_empty() else (source.volumetric_fog_density if source!=null else 0.)
	world.environment=overlay
	_sync_camera(not globals.is_empty())
	_sync_shadow_buffers()

func _sync_camera(global_fog: bool) -> void:
	var camera:=get_viewport().get_camera_3d()
	var previous:=camera_ref.get_ref() as Camera3D if camera_ref!=null else null
	if camera!=previous: _restore_camera()
	if camera==null or camera.environment==null: return
	if camera_ref==null: camera_ref=weakref(camera)
	if camera.environment!=camera_overlay and camera_source!=camera.environment:
		if camera_source!=null and camera_source.changed.is_connected(_camera_changed): camera_source.changed.disconnect(_camera_changed)
		camera_source=camera.environment; camera_source.changed.connect(_camera_changed); camera_dirty=true
	var signature:=environment_signature(camera_source)
	if signature!=camera_signature: camera_signature=signature; camera_dirty=true
	if camera_dirty or camera_overlay==null:
		camera_overlay=camera_source.duplicate() as Environment; camera_dirty=false
	camera_overlay.volumetric_fog_enabled=true; camera_overlay.volumetric_fog_density=0. if global_fog else camera_source.volumetric_fog_density; camera.environment=camera_overlay
	camera_overlay.volumetric_fog_temporal_reprojection_enabled=false if get_viewport().get_meta("kiwi_scene_frame_capture",false) else camera_source.volumetric_fog_temporal_reprojection_enabled

func _camera_changed() -> void: camera_dirty=true
func _restore_camera() -> void:
	var camera:=camera_ref.get_ref() as Camera3D if camera_ref!=null else null
	if camera!=null and camera.environment==camera_overlay: camera.environment=camera_source
	if camera_source!=null and camera_source.changed.is_connected(_camera_changed): camera_source.changed.disconnect(_camera_changed)
	camera_ref=null; camera_source=null; camera_overlay=null; camera_dirty=true
	camera_signature=0

static func environment_signature(environment: Environment) -> int:
	if environment==null: return 0
	# Native Environment setters do not consistently emit Resource.changed. A
	# cached property layout detects animated/native edits without stale overlays.
	if environment_keys.is_empty():
		for info: Dictionary in environment.get_property_list():
			if int(info.usage)&PROPERTY_USAGE_STORAGE and not str(info.name).begins_with("resource_"): environment_keys.append(str(info.name))
	var values: Array=[]
	for key in environment_keys: values.append(environment.get(key))
	return hash(values)

func _dirty() -> void: source_dirty=true
func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_light_added): get_tree().node_added.disconnect(_light_added)
	if resize_frame>=0 and is_equal_approx(get_viewport().scaling_3d_scale,temporary_scale): get_viewport().scaling_3d_scale=original_scale
	_restore_camera()
	if world!=null and world.environment==overlay: world.environment=source
	if source!=null and source.changed.is_connected(_dirty): source.changed.disconnect(_dirty)
