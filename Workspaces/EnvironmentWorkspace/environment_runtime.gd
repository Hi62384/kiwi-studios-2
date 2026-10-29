class_name KiwiEnvironmentRuntime
extends Node3D
## Shared by preview and Scene actor. Terrain chunks and repeated native meshes
## are renderer data, not thousands of independently authored scene actors.
var document: KiwiEnvironmentDocument
var nodes: Dictionary={}
var component_index: Dictionary={}
var preview_hidden: Dictionary={}
var signatures: Dictionary={}
var errors:=PackedStringArray()
var warnings:=PackedStringArray()
var chunks_rebuilt:=0
var instances:=0
var default_ground:=StandardMaterial3D.new()
var include_lighting:=false
var include_atmosphere:=false
var sun: DirectionalLight3D
var progressive:=false
var cave_cutaway:=false
var upload_budget_usec:=4000
var pending_chunks: Dictionary={}
var pending_assets: Dictionary={}
var _material_scope: Dictionary={}
var _scatter_mesh_scope: Dictionary={}
var _asset_lod_scope: Dictionary={}
var priority_camera: Camera3D
var preview_time:=0.
var animate_preview:=false
var biome_preview_id:=""
var biome_preview_terrain:=""
var scatter_jobs: Dictionary={}
var _retired_scatter: Array[RefCounted]=[]
var _stream_time:=0.
var stream_nodes: Dictionary={}
var _stream_camera: Camera3D
var _stream_pose:=Transform3D.IDENTITY
var _stream_root:=Transform3D.IDENTITY
var _stream_visible:=false
var building_stream:=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_stream.gd").new()
var weather_particles: Dictionary={}
func _init() -> void: building_stream.runtime=self; default_ground.albedo_color=Color("718365"); default_ground.roughness=1.
func _ready() -> void: building_stream.runtime=self; add_to_group("environment_runtimes")

func update_weather_particles(state: Dictionary,camera: Camera3D) -> void:
	if camera==null or not is_instance_valid(camera):
		for particle: GPUParticles3D in weather_particles.values():
			if is_instance_valid(particle): particle.emitting=false
		return
	for kind in ["rain","snow"]:
		var amount:=clampf(float(state.get(kind,0.)),0.,1.)
		var particles: GPUParticles3D=weather_particles.get(kind)
		if amount<=.015:
			if is_instance_valid(particles): particles.emitting=false; particles.visible=false
			continue
		if not is_instance_valid(particles):
			particles=_make_weather_particles(kind)
			weather_particles[kind]=particles
			add_child(particles)
		particles.global_position=camera.global_position
		particles.emitting=amount>.015
		particles.amount_ratio=amount
		particles.visible=amount>.015

func _make_weather_particles(kind: String) -> GPUParticles3D:
	var particles:=GPUParticles3D.new()
	particles.name="Climate "+kind.capitalize()
	particles.amount=1800 if kind=="rain" else 900
	particles.lifetime=1.35 if kind=="rain" else 7.0
	particles.local_coords=false
	particles.visibility_aabb=AABB(Vector3(-35.,-35.,-35.),Vector3(70.,70.,70.))
	var process:=ParticleProcessMaterial.new()
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=Vector3(24.,14.,24.)
	process.direction=Vector3.DOWN
	process.spread=2. if kind=="rain" else 32.
	if kind=="rain":
		process.gravity=Vector3(0.,-34.,0.); process.initial_velocity_min=18.; process.initial_velocity_max=27.
		process.particle_flag_align_y=true
		var drop:=CapsuleMesh.new(); drop.radius=.012; drop.height=.18
		var material:=StandardMaterial3D.new(); material.albedo_color=Color(.58,.74,.92,.58); material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.roughness=.2; drop.material=material
		particles.draw_pass_1=drop
	else:
		process.gravity=Vector3(0.,-1.2,0.); process.initial_velocity_min=.35; process.initial_velocity_max=1.4
		process.turbulence_enabled=true; process.turbulence_noise_scale=1.8; process.turbulence_influence_min=.15; process.turbulence_influence_max=.55
		var flake:=SphereMesh.new(); flake.radius=.035; flake.height=.07
		var material:=StandardMaterial3D.new(); material.albedo_color=Color(.88,.94,1.,.9); material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.roughness=.9; flake.material=material
		particles.draw_pass_1=flake
	particles.process_material=process
	return particles

func configure(source: KiwiEnvironmentDocument) -> void:
	if document!=source:
		pending_chunks.clear()
		pending_assets.clear(); _material_scope.clear(); _scatter_mesh_scope.clear(); _asset_lod_scope.clear(); stream_nodes.clear()
		for entry: Dictionary in scatter_jobs.values(): entry.job.cancel(); _retired_scatter.append(entry.job)
		scatter_jobs.clear()
	document=source; sync()
func _process(_delta: float) -> void:
	if not building_stream.entries.is_empty(): building_stream.process()
	_stream_time+=_delta
	var stream_camera:=get_viewport().get_camera_3d()
	if stream_camera==null and is_instance_valid(priority_camera): stream_camera=priority_camera
	var stream_pose:=stream_camera.global_transform if stream_camera!=null else Transform3D.IDENTITY
	if _stream_time>=.2 or stream_camera!=_stream_camera or stream_pose!=_stream_pose or global_transform!=_stream_root or is_visible_in_tree()!=_stream_visible:
		_stream_time=0.
		_stream_camera=stream_camera; _stream_pose=stream_pose; _stream_root=global_transform; _stream_visible=is_visible_in_tree()
		for identity in stream_nodes.keys():
			var node: Node3D=stream_nodes[identity]
			if not is_instance_valid(node) or not node.has_meta("scatter_stream"): stream_nodes.erase(identity); continue
			preload("res://Workspaces/EnvironmentWorkspace/world/world_instance_stream.gd").refresh(self,node)
	if animate_preview and is_visible_in_tree():
		preview_time+=_delta
		preload("res://Workspaces/ModelWorkspace/natural_render.gd").time(self,preview_time)
		for owner: Node3D in nodes.values():
			var water:=owner.get_node_or_null("Water") as MeshInstance3D
			if water!=null and water.material_override is ShaderMaterial and water.material_override.get_meta("terrain_water",false): (water.material_override as ShaderMaterial).set_shader_parameter("liquid_time",preview_time)
			if water!=null:
				var spray:=water.get_node_or_null("Spray") as MultiMeshInstance3D
				if spray!=null and spray.material_override is ShaderMaterial: (spray.material_override as ShaderMaterial).set_shader_parameter("liquid_time",preview_time)
	_poll_scatter()
	var started:=Time.get_ticks_usec(); var processed:=false
	while not pending_chunks.is_empty() and (not processed or Time.get_ticks_usec()-started<upload_budget_usec):
		var id:=_next_chunk(); var task: Dictionary=pending_chunks[id]; pending_chunks.erase(id)
		if not is_instance_valid(task.node) or not is_instance_valid(task.chunk) or nodes.get(task.id)!=task.node or document==null or document.terrain(task.id)!=task.terrain: continue
		_build_chunk(task.terrain,task.coordinate,task.chunk,task.key)
		_assign_chunk_materials(task.chunk,task.material,task.paint,task.collision)
		processed=true
	while not pending_assets.is_empty() and (not processed or Time.get_ticks_usec()-started<upload_budget_usec):
		var id: String=pending_assets.keys()[0]; var task: Dictionary=pending_assets[id]; pending_assets.erase(id)
		if document==null or not is_instance_valid(task.node) or nodes.get(id)!=task.node or component_index.get(id)!=task.item: continue
		var metadata: Dictionary=document.component_settings.get(id,{"kind":"asset"})
		if metadata.get("kind","asset")!="asset": continue
		_asset(task.item,task.node,metadata); _world_render(task.item,task.node); processed=true
func _next_chunk() -> String:
	var chosen: String=pending_chunks.keys()[0]
	if priority_camera==null or not is_instance_valid(priority_camera): return chosen
	var best:=INF
	for key: String in pending_chunks:
		var task: Dictionary=pending_chunks[key]
		if not is_instance_valid(task.node): continue
		var source:=task.terrain as KiwiEnvironmentTerrain; var cell: Vector2i=task.coordinate*source.CHUNK_CELLS+Vector2i.ONE*(source.CHUNK_CELLS/2); var point: Vector3=(task.node as Node3D).global_transform*source.position(mini(cell.x,source.resolution-1),mini(cell.y,source.resolution-1)); var distance:=point.distance_squared_to(priority_camera.global_position)
		if distance<best: best=distance; chosen=key
	return chosen
func _poll_scatter() -> void:
	for index in range(_retired_scatter.size()-1,-1,-1):
		var job:=_retired_scatter[index]
		if job.complete(): job.collect(); _retired_scatter.remove_at(index)
	for id: String in scatter_jobs.keys():
		var entry: Dictionary=scatter_jobs[id]; var job: RefCounted=entry.job
		if not job.complete(): continue
		job.collect(); scatter_jobs.erase(id)
		if job.cancelled() or not is_instance_valid(entry.node) or nodes.get(id)!=entry.node or document==null: continue
		var rules:=document.component_settings.get(id,{}).get("scatter") as KiwiEnvironmentScatter; var terrain:=document.terrain(entry.terrain_id)
		if rules==null or terrain==null or rules.signature()!=int(entry.rules_key) or terrain.signature()!=int(entry.terrain_key): continue
		var result: Dictionary=job.result; entry.node.set_meta("scatter_result",result); signatures[id]=entry.key; _install_scatter(entry.node,result,rules)
		if not str(result.get("error","")).is_empty(): errors.append(str(result.error))
		if not str(result.get("warning","")).is_empty(): warnings.append(str(result.warning))
		instances=0
		for node: Node3D in nodes.values(): instances+=int(node.get_meta("scatter_result",{}).get("count",0))
func _exit_tree() -> void:
	building_stream.dispose()
	for entry: Dictionary in scatter_jobs.values(): entry.job.cancel(); _retired_scatter.append(entry.job)
	for job in _retired_scatter: job.cancel(); job.collect()
	scatter_jobs.clear(); _retired_scatter.clear()
func cancel_scatter_generation() -> void:
	for entry: Dictionary in scatter_jobs.values(): entry.job.cancel(); _retired_scatter.append(entry.job)
	scatter_jobs.clear()
func sync() -> void:
	if document==null: return
	sync_lighting()
	errors.clear(); warnings.clear(); chunks_rebuilt=0; instances=0; var live:={}; var hierarchy:=document.hierarchy_state()
	component_index.clear()
	for item in document.components: component_index[item.id]=item
	for item in document.components:
		live[item.id]=true; var metadata: Dictionary=document.component_settings.get(item.id,{"kind":"asset"}); var kind:=str(metadata.get("kind","asset")); var node: Node3D=nodes.get(item.id)
		if node==null: node=Node3D.new(); node.name=item.title.validate_node_name(); add_child(node); nodes[item.id]=node
		if str(node.get_meta("environment_kind",""))!=kind:
			if node.has_meta("scatter_stream"): node.remove_meta("scatter_stream"); stream_nodes.erase(node.get_instance_id())
			for child in node.get_children(): child.free()
			node.set_meta("environment_kind",kind); signatures.erase(item.id)
		node.transform=hierarchy.poses[item.id]; node.visible=hierarchy.visible[item.id] and not preview_hidden.has(item.id)
		node.set_meta("kiwi_physics_excluded",not node.visible or not bool(metadata.get("collision",true)))
		match kind:
			"terrain": _terrain(item,node,metadata)
			"scatter": _scatter(item,node,metadata)
			"building": building_stream.sync(item,node,metadata)
			"asset":
				if progressive and item.mesh!=null and str(metadata.get("source","")).is_empty():
					if signatures.get(item.id,-1)!=_native_asset_key(item): pending_assets[item.id]={"item":item,"node":node}
				else: pending_assets.erase(item.id); _asset(item,node,metadata)
		_world_render(item,node)
	for id: String in nodes.keys():
		if not live.has(id): nodes[id].queue_free(); nodes.erase(id); signatures.erase(id); pending_assets.erase(id)
	if _material_scope.size()>256: _material_scope.clear()
func geometry_ready(physics_full: bool=false) -> bool:
	return building_stream.ready(physics_full) and pending_assets.is_empty() and pending_chunks.is_empty()

func sync_lighting() -> void:
	if document==null: return
	if include_lighting and sun==null: sun=DirectionalLight3D.new(); sun.name="EnvironmentSun"; add_child(sun)
	if sun!=null:
		sun.visible=include_lighting and bool(document.sunlight.get("enabled",true)); sun.rotation_degrees=document.sunlight.get("rotation",Vector3(-45,-30,0)); sun.light_color=document.sunlight.get("color",Color.WHITE); sun.light_energy=float(document.sunlight.get("energy",1.5)); sun.shadow_enabled=bool(document.sunlight.get("shadows",true))

func _terrain(_item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void:
	var terrain:=metadata.get("terrain") as KiwiEnvironmentTerrain
	if terrain==null: return
	terrain.prepare(); var material:=KiwiEnvironmentAssets.material(metadata.get("material")); var paint:=KiwiEnvironmentAssets.material(metadata.get("paint_material")); var live:={}
	terrain.prepare_geometry_keys()
	if material==null: material=default_ground
	var blended:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_render.gd").material(node,terrain,material,paint)
	errors.append_array(node.get_meta("biome_material_warnings",PackedStringArray()))
	if blended==null: blended=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint_render.gd").material(node,terrain,material,paint)
	if blended!=null: material=blended; paint=blended
	var overlay:=_biome_overlay(node,terrain) if _item.id==biome_preview_terrain else null
	for z in ceili(float(terrain.resolution-1)/terrain.CHUNK_CELLS):
		for x in ceili(float(terrain.resolution-1)/terrain.CHUNK_CELLS):
			var coordinate:=Vector2i(x,z); var name:="Chunk_%d_%d"%[x,z]; live[name]=true; var chunk:=node.get_node_or_null(name) as MeshInstance3D
			if chunk==null: chunk=MeshInstance3D.new(); chunk.name=name; node.add_child(chunk)
			chunk.set_meta("smooth_paint",blended!=null)
			chunk.material_overlay=overlay
			chunk.lod_bias=maxf(.01,terrain.lod_bias); chunk.visibility_range_end=maxf(0.,terrain.render_distance); chunk.visibility_range_end_margin=terrain.render_distance*.15; chunk.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if terrain.render_distance>0. else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			chunk.visible=not cave_cutaway or terrain.needs_volume(coordinate)
			var key:=hash([terrain.chunk_geometry_key(coordinate,blended==null),cave_cutaway,blended!=null])
			if terrain.needs_volume(coordinate) and (not terrain.volume_chunks.has(coordinate) or int(terrain.volume_chunks[coordinate].get("key",-1))!=terrain.volume_key(coordinate)):
				errors.append("Cave geometry needs generation."); continue
			if int(chunk.get_meta("terrain_key",-1))!=key:
				if progressive: pending_chunks[_item.id+":"+name]={"id":_item.id,"node":node,"chunk":chunk,"terrain":terrain,"coordinate":coordinate,"key":key,"material":material,"paint":paint,"collision":bool(metadata.get("collision",true)) and node.visible}
				else: _build_chunk(terrain,coordinate,chunk,key)
			if chunk.mesh!=null: _assign_chunk_materials(chunk,material,paint,bool(metadata.get("collision",true)) and node.visible)
	preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_water_render.gd").sync(node,terrain); live["Water"]=true
	for child in node.get_children():
		if not live.has(str(child.name)): child.queue_free()

func _build_chunk(terrain: KiwiEnvironmentTerrain,coordinate: Vector2i,chunk: MeshInstance3D,key: int) -> void:
	chunk.mesh=terrain.chunk_mesh(coordinate,cave_cutaway,chunk.get_meta("smooth_paint",false)); chunk.set_meta("terrain_key",key); chunks_rebuilt+=1
	if chunk.mesh.get_surface_count()==0: return
	var body:=chunk.get_node_or_null("Collision") as StaticBody3D
	if body==null:
		body=StaticBody3D.new(); body.name="Collision"; chunk.add_child(body); var collider:=CollisionShape3D.new(); collider.name="Shape"; body.add_child(collider)
	var shape:=chunk.mesh.get_meta("kiwi_terrain_collision") as ConcavePolygonShape3D if chunk.mesh.has_meta("kiwi_terrain_collision") else null
	if shape==null: shape=ConcavePolygonShape3D.new(); shape.set_faces(chunk.mesh.get_faces()); chunk.mesh.set_meta("kiwi_terrain_collision",shape)
	(body.get_node("Shape") as CollisionShape3D).shape=shape
func _biome_overlay(owner: Node3D,terrain: KiwiEnvironmentTerrain) -> Material:
	var weights: PackedFloat32Array=terrain.biome_data.get("weights",{}).get(biome_preview_id,PackedFloat32Array())
	if weights.size()!=terrain.resolution*terrain.resolution: return null
	var key:=hash([biome_preview_id,terrain.biome_key,terrain.biome_data.get("preview_revision",0),terrain.resolution]); var material:=owner.get_meta("biome_overlay") as ShaderMaterial if owner.has_meta("biome_overlay") else null
	if material==null: material=ShaderMaterial.new(); material.shader=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_overlay.gdshader"); owner.set_meta("biome_overlay",material)
	if owner.get_meta("biome_overlay_key",-1)!=key:
		var image:=Image.create_from_data(terrain.resolution,terrain.resolution,false,Image.FORMAT_RF,weights.to_byte_array()); image.generate_mipmaps(); var texture:=material.get_shader_parameter("weights") as ImageTexture
		if texture!=null and texture.get_size()==Vector2(terrain.resolution,terrain.resolution): texture.update(image)
		else: texture=ImageTexture.create_from_image(image)
		material.set_shader_parameter("weights",texture); material.set_shader_parameter("terrain_size",terrain.dimensions); material.set_shader_parameter("tint",Color.from_hsv(float(hash(biome_preview_id)%360)/360.,.65,1.)); owner.set_meta("biome_overlay_key",key)
	return material
func _assign_chunk_materials(chunk: MeshInstance3D,material: Material,paint: Material,collision: bool) -> void:
	chunk.material_override=null; var slots: PackedInt32Array=chunk.mesh.get_meta("environment_material_slots",PackedInt32Array())
	for surface in chunk.mesh.get_surface_count(): chunk.set_surface_override_material(surface,paint if surface<slots.size() and slots[surface]==1 and paint!=null else material)
	var body:=chunk.get_node_or_null("Collision") as StaticBody3D
	if body!=null: body.collision_layer=1 if collision and chunk.visible and chunk.mesh.get_surface_count()>0 else 0

func _asset(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void:
	var path:=str(metadata.get("source","")); var loaded:={"parts":[],"error":"","key":0}
	if not path.is_empty(): loaded=KiwiEnvironmentAssets.load_parts(path)
	elif item.mesh!=null:
		loaded.key=_native_asset_key(item)
		if signatures.get(item.id,-1)==loaded.key: _sync_asset_collision(node,bool(metadata.get("collision",false))); return
		loaded.parts=[{"mesh":item.render_mesh(_material_scope),"transform":Transform3D.IDENTITY,"name":item.title}]
	if not str(loaded.error).is_empty(): errors.append(str(loaded.error))
	if signatures.get(item.id,-1)==loaded.key: _sync_asset_collision(node,bool(metadata.get("collision",false))); return
	signatures[item.id]=loaded.key
	for child in node.get_children(): child.free()
	for part: Dictionary in loaded.parts:
		var mesh:=MeshInstance3D.new(); mesh.name=str(part.name).validate_node_name(); mesh.mesh=part.mesh; mesh.transform=part.transform; node.add_child(mesh)
		if item.parameters.has("world_owner"): mesh.mesh=_lod_mesh(mesh.mesh,_asset_lod_scope)
		if not path.is_empty():
			for surface in mesh.mesh.get_surface_count():
				var authored:=mesh.mesh.surface_get_material(surface)
				if not authored is ShaderMaterial: continue
				var identity:=authored.get_instance_id()
				if not _material_scope.has(identity): _material_scope[identity]=KiwiEnvironmentAssets.timeline_material(authored,true)
				mesh.set_surface_override_material(surface,_material_scope[identity])
	_sync_asset_collision(node,bool(metadata.get("collision",false)))
	preload("res://Workspaces/ModelWorkspace/natural_render.gd").time(node,preview_time)
static func _native_asset_key(item: KiwiModelComponent) -> int:
	return hash([item.mesh.vertices,item.mesh.faces,item.mesh.uv,item.mesh.materials,item.mesh.smooth,item.modifiers,item.surface_materials])
func _world_render(item: KiwiModelComponent,node: Node3D) -> void:
	var owner:=component_index.get(str(item.parameters.get("world_owner",""))) as KiwiModelComponent
	if owner==null: return
	var source: Variant=owner.parameters.get("world_source")
	if not source is Resource: return
	for child in node.get_children():
		if child is GeometryInstance3D and not child is MultiMeshInstance3D:
			child.visibility_range_end=maxf(0.,float(source.render_distance)); child.visibility_range_end_margin=child.visibility_range_end*.1
			child.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if child.visibility_range_end>0. else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
static func _lod_mesh(source: Mesh,cache: Dictionary) -> Mesh:
	if not source is ArrayMesh or source.get_surface_count()==0: return source
	var key:=source.get_instance_id()
	if cache.has(key): return cache[key]
	var indices:=0
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: return source
		indices+=source.surface_get_array_index_len(surface) if source.surface_get_array_index_len(surface)>0 else source.surface_get_array_len(surface)
	if indices<768: return source
	var result: ArrayMesh=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_lod.gd").prepare(source)
	if cache.size()>=256: cache.clear()
	cache[key]=result; return result

func _sync_asset_collision(node: Node3D,enabled: bool) -> void:
	for child in node.get_children():
		if not child is MeshInstance3D: continue
		var body:=child.get_node_or_null("Collision") as StaticBody3D
		if enabled and body==null and child.mesh!=null:
			var faces: PackedVector3Array=child.mesh.get_meta("kiwi_collision_faces",child.mesh.get_faces())
			if faces.is_empty(): continue
			body=StaticBody3D.new(); body.name="Collision"; child.add_child(body); var collider:=CollisionShape3D.new(); var shape:=ConcavePolygonShape3D.new(); shape.set_faces(faces); collider.shape=shape; body.add_child(collider)
		if body!=null: body.collision_layer=1 if enabled and node.visible else 0

func _scatter(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void:
	var source:=metadata.get("scatter") as KiwiEnvironmentScatter
	if source==null: return
	node.set_meta("scatter_rules",source)
	if node.has_meta("scatter_stream"):
		stream_nodes[node.get_instance_id()]=node; var stream: Dictionary=node.get_meta("scatter_stream"); stream.rules=source
	node.set_meta("kiwi_physics_excluded",not source.collisions or not node.visible)
	var terrain:=document.terrain(source.terrain_id)
	if terrain==null: errors.append("Scatter layer has no valid terrain."); return
	var asset_keys:=[]
	for entry in source.palette:
		var asset:=KiwiEnvironmentAssets.load_scatter_parts(entry.get("source","")); asset_keys.append(asset.key)
		if not str(asset.error).is_empty(): errors.append(str(asset.error))
	var key:=hash([source.signature(),terrain.signature(),asset_keys]); var result: Dictionary=node.get_meta("scatter_result",{})
	if signatures.get(item.id,-1)!=key:
		var candidates:=source.anchor_points.size() if source.use_anchors else mini(source.budget,roundi(source.region.get_area()*source.density))
		if progressive and candidates>1000:
			if not scatter_jobs.has(item.id) or int(scatter_jobs[item.id].key)!=key:
				if scatter_jobs.has(item.id): scatter_jobs[item.id].job.cancel(); _retired_scatter.append(scatter_jobs[item.id].job)
				var job:=preload("res://Workspaces/EnvironmentWorkspace/environment_scatter_job.gd").new(); scatter_jobs[item.id]={"job":job,"node":node,"key":key,"rules_key":source.signature(),"terrain_key":terrain.signature(),"terrain_id":source.terrain_id}; job.start(source,terrain)
		else:
			if scatter_jobs.has(item.id): scatter_jobs[item.id].job.cancel(); _retired_scatter.append(scatter_jobs[item.id].job); scatter_jobs.erase(item.id)
			result=source.generate(terrain); node.set_meta("scatter_result",result); signatures[item.id]=key; _install_scatter(node,result,source)
	elif int(node.get_meta("scatter_render_key",-1))!=source.render_signature(): _install_scatter(node,result,source)
	var collision:=node.get_node_or_null("ScatterCollision") as MeshInstance3D
	if collision!=null:
		var body:=collision.get_node("Collision") as StaticBody3D; body.collision_layer=1 if node.visible else 0
	instances+=int(result.get("count",0))
	if not str(result.get("error","")).is_empty(): errors.append(str(result.error))
	if not str(result.get("warning","")).is_empty(): warnings.append(str(result.warning))
func _install_scatter(node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void:
	for child in node.get_children(): child.free()
	node.set_meta("scatter_render_key",source.render_signature())
	if node.has_meta("scatter_stream"): node.remove_meta("scatter_stream")
	stream_nodes.erase(node.get_instance_id())
	if source.stream_instances and source.render_cluster_size>0. and source.render_distance>0.:
		preload("res://Workspaces/EnvironmentWorkspace/world/world_instance_stream.gd").install(self,node,result,source)
		if source.collisions: _scatter_collision(node,result,source)
		return
	for index: int in result.batches:
		var asset:=KiwiEnvironmentAssets.load_scatter_parts(source.palette[index].get("source",""))
		if not str(asset.error).is_empty(): errors.append(str(asset.error)); continue
		for part: Dictionary in asset.parts:
			var clusters: Dictionary={}
			for pose: Transform3D in result.batches[index]:
				var cell:=Vector2i(floori(pose.origin.x/source.render_cluster_size),floori(pose.origin.z/source.render_cluster_size)) if source.render_cluster_size>0. else Vector2i.ZERO
				if not clusters.has(cell): clusters[cell]=[]
				clusters[cell].append(pose)
			for cell: Vector2i in clusters:
				var batch:=MultiMeshInstance3D.new(); var mesh:=MultiMesh.new(); mesh.transform_format=MultiMesh.TRANSFORM_3D; mesh.mesh=_scatter_mesh(part.mesh,source.lod_enabled); var poses: Array=clusters[cell]; mesh.instance_count=poses.size(); var center:=Vector3((cell.x+.5)*source.render_cluster_size,0.,(cell.y+.5)*source.render_cluster_size) if source.render_cluster_size>0. else Vector3.ZERO
				for i in poses.size():
					var pose: Transform3D=(poses[i] as Transform3D)*(part.transform as Transform3D); pose.origin-=center; mesh.set_instance_transform(i,pose)
				batch.position=center; batch.multimesh=mesh; batch.lod_bias=source.lod_bias; batch.visibility_range_end=source.render_distance; batch.visibility_range_end_margin=source.render_distance*.15; batch.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if source.render_distance>0. else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED; node.add_child(batch)
	if source.collisions: _scatter_collision(node,result,source)
	preload("res://Workspaces/ModelWorkspace/natural_render.gd").time(node,preview_time)
func _scatter_mesh(source: Mesh,lod: bool=false) -> Mesh:
	var key:=str(source.get_instance_id())+":"+str(lod)
	if _scatter_mesh_scope.has(key): return _scatter_mesh_scope[key]
	if _scatter_mesh_scope.size()>=128: _scatter_mesh_scope.clear()
	var result:=(_lod_mesh(source,_asset_lod_scope) if lod else source).duplicate(false) as Mesh
	for surface in result.get_surface_count():
		var material:=source.surface_get_material(surface)
		if not material is ShaderMaterial: continue
		var identity:=material.get_instance_id()
		if not _material_scope.has(identity): _material_scope[identity]=KiwiEnvironmentAssets.timeline_material(material,true)
		result.surface_set_material(surface,_material_scope[identity])
	_scatter_mesh_scope[key]=result; return result

func _scatter_collision(node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void:
	# One bounded native collider and one mesh capture for Kiwi's offline physics.
	# Rendering remains instanced; decorative scatter has no collider at all.
	var faces:=PackedVector3Array(); const MAX_FACES_VERTICES:=600000
	var exhausted:=false
	for index: int in result.batches:
		var asset:=KiwiEnvironmentAssets.load_scatter_parts(source.palette[index].get("source",""))
		for part: Dictionary in asset.parts:
			var triangles: PackedVector3Array=part.mesh.get_meta("kiwi_collision_faces",part.mesh.get_faces())
			for pose: Transform3D in result.batches[index]:
				if faces.size()+triangles.size()>MAX_FACES_VERTICES: exhausted=true; break
				var transform:=pose*(part.transform as Transform3D)
				for point in triangles: faces.append(transform*point)
			if exhausted: break
		if exhausted: break
	if exhausted: errors.append("Scatter collision limit reached. Reduce the collision-enabled layer's budget or use a simpler source mesh.")
	if faces.is_empty(): return
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=faces; var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var proxy:=MeshInstance3D.new(); proxy.name="ScatterCollision"; proxy.mesh=mesh; proxy.visible=false; node.add_child(proxy)
	var body:=StaticBody3D.new(); body.name="Collision"; proxy.add_child(body); var collider:=CollisionShape3D.new(); var shape:=ConcavePolygonShape3D.new(); shape.set_faces(faces); collider.shape=shape; body.add_child(collider)
