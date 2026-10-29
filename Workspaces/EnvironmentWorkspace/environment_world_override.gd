extends Node
## One explicit scene-world owner. Cooperates with the fog coordinator's temporary
## overlay and restores the original world rather than adding conflicting nodes.
var entries: Array[WeakRef]=[]
var world: World3D
var original: Environment
var owned: Environment
var owner_key:=0
static func attach(runtime: Node3D) -> void:
	var viewport:=runtime.get_viewport(); var coordinator:=viewport.get_node_or_null("KiwiEnvironmentWorld")
	if coordinator==null:
		coordinator=load("res://Workspaces/EnvironmentWorkspace/environment_world_override.gd").new(); coordinator.name="KiwiEnvironmentWorld"; coordinator.world=viewport.find_world_3d(); coordinator.process_priority=90; viewport.add_child(coordinator)
	coordinator.entries.append(weakref(runtime))
func underlying() -> Environment:
	var fog:=get_viewport().get_node_or_null("KiwiFogEnvironment")
	if fog!=null and world.environment==fog.overlay: return fog.source
	return world.environment
func _process(_delta: float) -> void:
	if world==null: return
	var active: Array[Node]=[]
	for index in range(entries.size()-1,-1,-1):
		var runtime: Node=entries[index].get_ref()
		if runtime==null: entries.remove_at(index); continue
		if runtime.active and runtime.content!=null and runtime.content.include_atmosphere and runtime.source_document!=null: active.append(runtime)
	active.sort_custom(func(a: Node,b: Node): return str(a.actor.id)<str(b.actor.id))
	if active.is_empty():
		for entry: WeakRef in entries:
			var inactive: Node=entry.get_ref()
			if inactive!=null and inactive.content!=null: inactive.content.update_weather_particles({},null)
		if owner_key!=0:
			if underlying()==owned: world.environment=original
			owner_key=0; owned=null; original=null
		return
	var runtime: Node=active[0]
	for entry: WeakRef in entries:
		var candidate: Node=entry.get_ref()
		if candidate!=null and candidate!=runtime and candidate.content!=null: candidate.content.update_weather_particles({},null)
	var document: KiwiEnvironmentDocument=runtime.source_document; var key:=hash([runtime.actor.id,document.get_instance_id(),KiwiEnvironmentAssets.world_stamp(document)])
	if key==owner_key: _sync_sky_time(runtime); return
	var next:=KiwiEnvironmentAssets.world_environment(document)
	if document.climate!=null and document.climate.has_method("make_environment"):
		next=next.duplicate(true) as Environment if next!=null else document.climate.make_environment(runtime.shader_time)
	if next==null:
		if owner_key!=0:
			if underlying()==owned: world.environment=original
			owner_key=0; owned=null; original=null
		return
	if owner_key==0: original=underlying()
	owner_key=key; owned=next; world.environment=owned
	_sync_sky_time(runtime)
func _sync_sky_time(runtime: Node) -> void:
	if owned==null: return
	var time:=float(runtime.get("shader_time")) if runtime.get("shader_time") is float or runtime.get("shader_time") is int else 0.
	if owned.sky!=null and owned.sky.sky_material is ShaderMaterial:
		var material:=owned.sky.sky_material as ShaderMaterial; var uniform:=str(material.get_meta("kiwi_time_uniform",""))
		if not uniform.is_empty(): material.set_shader_parameter(uniform,time)
	var climate: Resource=runtime.source_document.climate if runtime.source_document!=null else null
	if runtime.content==null: return
	if climate==null:
		runtime.content.update_weather_particles({},null); return
	var position:=Vector3.ZERO; var camera:=runtime.get_viewport().get_camera_3d()
	if camera!=null: position=runtime.content.global_transform.affine_inverse()*camera.global_position
	var overrides: Dictionary=runtime.get("climate_overrides") if runtime.get("climate_overrides") is Dictionary else {}
	var state: Dictionary=climate.call("apply_environment",owned,time,position,overrides)
	runtime.content.update_weather_particles(state,camera)
	var sun:=runtime.content.sun as DirectionalLight3D
	if sun!=null:
		var direction: Vector3=state.get("sun_direction",Vector3.DOWN); sun.visible=bool(runtime.source_document.sunlight.get("enabled",true)) and float(state.get("sun_elevation",0.))>deg_to_rad(-10.)
		if direction.length_squared()>.0001: sun.basis=Basis.looking_at(-direction.normalized(),Vector3.UP)
		var authored_energy:=float(runtime.source_document.sunlight.get("energy",1.5)); sun.light_energy=authored_energy*float(state.get("sunlight_energy",1.))
		var warmth:=clampf(1.-absf(float(state.get("sun_elevation",0.)))/.25,0.,1.); var authored_color: Color=runtime.source_document.sunlight.get("color",Color.WHITE); sun.light_color=authored_color.lerp(Color(1.,.55,.3),warmth*.55)
func _exit_tree() -> void:
	if world!=null and owner_key!=0 and underlying()==owned: world.environment=original

