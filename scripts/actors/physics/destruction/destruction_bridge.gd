class_name KiwiDestructionBridge
extends RefCounted
## Extends the existing timeline/query world. Geometry is immutable and cached;
## only fragment transforms/velocities live in checkpoint state.
var cache: Dictionary={}
var nodes: Dictionary={}
var collider_keys: Dictionary={}
var builds:=0
var elapsed_usec:=0
var interiors: Dictionary={}
var sources: Dictionary={}
var cache_bytes:=0
func reset(keep_prepared: bool=false) -> void:
	for list: Array in nodes.values():
		for node: Node in list:
			if is_instance_valid(node): node.free()
	nodes.clear(); collider_keys.clear(); interiors.clear(); sources.clear()
	if not keep_prepared: cache.clear(); cache_bytes=0
func source(controller: KiwiTimelinePhysics,id: String,state: Dictionary) -> Dictionary:
	if sources.has(id): return sources[id]
	var mesh:=KiwiModelMesh.new(); var materials: Array[Material]=[]
	if controller.prototypes[id].geometry.meshes.is_empty() and controller._runtime(id)!=null:
		controller.prototypes[id].geometry=KiwiPhysicsGeometry.capture(controller._runtime(id),controller.prototypes)
	for item: Dictionary in controller._simulation_geometry(id,state).meshes:
		if item.get("skin")!=null: return {"error":"Topology-changing rigged destruction is not supported yet. Make a static posed copy before cutting; skin weights were preserved on the original."}
		if item.get("polygon") is KiwiModelMesh:
			mesh.append_mesh(item.polygon,item.local,materials.size())
			for material: Variant in item.materials: materials.append(material)
			continue
		var render:=ArrayMesh.new()
		for surface: Array in item.surfaces:
			if surface[Mesh.ARRAY_COLOR] is PackedColorArray:
				for color: Color in surface[Mesh.ARRAY_COLOR]:
					if not color.is_equal_approx(Color.WHITE): return {"error":"Vertex-colored destruction is not supported by the polygon converter yet. Bake vertex colors to a texture first; the original was preserved."}
			if surface[Mesh.ARRAY_BONES]!=null and not (surface[Mesh.ARRAY_BONES] as PackedInt32Array).is_empty(): return {"error":"Use an unskinned/posed static copy for destructive topology edits."}
			render.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
		mesh.append_mesh(KiwiModelMesh.from_mesh(render),item.local,materials.size())
		for material: Variant in item.materials: materials.append(material)
	if mesh.vertices.is_empty(): return {"error":"Source geometry is not ready. Retry after the actor has loaded."}
	if mesh.vertices.size()>KiwiDestructionGeometry.MAX_VERTICES: return {"error":"Source exceeds the 20,000-vertex destruction limit. Simplify or split its components."}
	var result:={"error":"","mesh":mesh,"materials":materials}; sources[id]=result; return result
func synchronize(controller: KiwiTimelinePhysics,time: float) -> void:
	var keep:={}
	for id: String in controller.prototypes:
		var state: Dictionary=controller.states[id]
		for fragment: Dictionary in state.get("destruction_fragments",[]): keep[fragment.id]=true
		if state.has("destruction_geometry"): sync_actor_world(controller,id,state,time)
		elif collider_keys.has(id):
			var config:=KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time)); var shape:=KiwiPhysicsGeometry.collider(controller.prototypes[id].geometry,config)
			controller.world.remove(id); controller.world.add(id,shape.shape,shape.offset,int(config.layer),int(config.mask)); controller.world.place(id,state.pose,config.collision and state.active); collider_keys.erase(id)
	for key: String in collider_keys.keys():
		if key.contains(":fragment:") and not keep.has(key): controller.world.remove(key); collider_keys.erase(key)
func prepare(controller: KiwiTimelinePhysics,id: String,state: Dictionary,values: Dictionary,ops: Dictionary) -> Dictionary:
	var data:=source(controller,id,state)
	if not data.error.is_empty(): return data
	var seen:={}
	for operation_id: String in ops:
		for dependency: String in ops[operation_id].get("depends_on",[]):
			if not seen.has(dependency): return {"error":"Operation "+operation_id+" requires an earlier active operation "+dependency+". Restore it or adjust the dependency/timing."}
		if ops[operation_id].get("enabled",true): seen[operation_id]=true
	var budget:=clampi(int(values.get(&"debris_budget",96)),2,256); ops=KiwiDestructionAuthoring.geometry_operations(ops)
	for op: Dictionary in ops.values():
		if int(op.get("type",0)) in [1,2]: op.pieces=mini(int(op.get("pieces",6)),budget)
	var key:=hash([data.mesh.vertices,data.mesh.faces,data.mesh.uv,data.mesh.materials,ops,budget])
	if cache.has(key): return cache[key]
	var start:=Time.get_ticks_usec(); var output:=KiwiDestructionGeometry.evaluate(data.mesh,ops,data.materials.size()); builds+=1
	if not output.error.is_empty(): return output
	if output.detached and output.parts.size()>budget: return {"error":"Fracture exceeds the actor's physical debris budget. Use fewer cuts/pieces or increase the budget; source geometry was preserved."}
	var rows:=[]
	for i in output.parts.size():
		var mesh: KiwiModelMesh=output.parts[i]; var center:=mesh.bounds().get_center(); var local:=mesh.copy_mesh()
		for j in local.vertices.size(): local.vertices[j]-=center
		rows.append({"id":str(key)+":"+str(i),"mesh":local,"center":center,"volume":maxf(.00001,KiwiDestructionGeometry.volume(local))})
	var bytes:=0
	for row: Dictionary in rows:
		bytes+=row.mesh.vertices.size()*12
		for face: PackedInt32Array in row.mesh.faces: bytes+=face.size()*16+64
	if bytes>33554432: return {"error":"Prepared destruction exceeds the 32 MiB geometry budget. Lower mesh/fracture resolution."}
	output={"error":"","rows":rows,"materials":data.materials,"detached":output.detached,"key":key,"bytes":bytes}
	while not cache.is_empty() and (cache.size()>=24 or cache_bytes+bytes>33554432):
		var oldest: Variant=cache.keys()[0]; cache_bytes-=int(cache[oldest].get("bytes",0)); cache.erase(oldest)
	cache_bytes+=bytes
	cache[key]=output; elapsed_usec=Time.get_ticks_usec()-start
	return output
func mass(controller: KiwiTimelinePhysics,id: String,state: Dictionary,values: Dictionary,fallback: float) -> float:
	if not values.get(&"destruction_use_density",false): return fallback
	var material:=KiwiDestructionMaterial.resolve(values)
	if material==null: return fallback
	var data:=source(controller,id,state)
	if not data.error.is_empty(): return fallback
	return maxf(.0001,KiwiDestructionGeometry.volume(data.mesh)*absf((state.pose as Transform3D).basis.determinant())*float(material.get_value(&"density",1000)))
func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	for id: String in controller.prototypes:
		var state: Dictionary=controller.states[id]; var actor: ActorData=controller.prototypes[id].actor
		var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time))
		if not state.active or not values.get(&"destruction_enabled",false):
			for key in ["destruction_geometry","destruction_fragments","destruction_detached"]: state.erase(key)
			continue
		var frozen_config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
		if not controller.is_baking(id) and int(frozen_config.mode) in [3,4]: sync_actor_world(controller,id,state,time); continue
		var mode:=int(values.get(&"destruction_mode",0)); var operations: Dictionary={}
		var event_energy:=0.0; var event_point: Vector3=state.pose.origin; var event_normal:=Vector3.UP
		for hit: Dictionary in state.get("destruction_impacts",[]):
			if float(hit.energy)>event_energy: event_energy=float(hit.energy); event_point=hit.point; event_normal=hit.normal
		if mode!=1:
			for op_id: String in values.get(&"destruction_operations",{}):
				var op: Dictionary=values.destruction_operations[op_id]
				if float(op.get("time",0))<=controller._local(actor,time)+1e-8:
					var copy:=op.duplicate(true); var physical:=KiwiDestructionMaterial.resolve(values,copy.get("position",Vector3.ZERO))
					if copy.get("physical",false) and physical!=null:
						var needed:=float(physical.get_value(&"hardness",12))+float(physical.get_value(&"toughness",3))
						var fraction:=clampf(float(copy.get("energy",20))/maxf(.01,needed),0,1)
						if fraction<.05: continue
						copy.amount*=fraction; copy.radius*=sqrt(fraction)
					operations[op_id]=copy
		var regions: Dictionary=operations.duplicate()
		for op_id: String in regions:
			var op: Dictionary=regions[op_id]
			if not op.get("enabled",true) or int(op.get("type",0))!=14: continue
			var done: Dictionary=state.get("directed_impacts",{})
			if not done.has(op_id):
				done[op_id]=true; state.directed_impacts=done; state.v+=(state.pose.basis*(op.get("direction",Vector3.RIGHT) as Vector3).normalized())*float(op.get("impulse",1))/maxf(.001,float(frozen_config.mass))
				if state.get("destruction_detached",false):
					for fragment: Dictionary in state.get("destruction_fragments",[]):
						var distance: float=(fragment.get("structure_origin",Vector3.ZERO) as Vector3).distance_to(op.get("position",Vector3.ZERO)); var weight:=pow(clampf(1-distance/maxf(.001,float(op.get("radius",.5))),0,1),maxf(.1,float(op.get("falloff",2))))
						fragment.v+=(state.pose.basis*(op.get("direction",Vector3.RIGHT) as Vector3).normalized())*float(op.get("impulse",1))*weight/maxf(.001,float(fragment.mass)); fragment.sleep=0.0
				state.destruction_impacts=state.get("destruction_impacts",[]); state.destruction_impacts.append({"point":state.pose*op.get("position",Vector3.ZERO),"normal":-(state.pose.basis*(op.get("direction",Vector3.RIGHT) as Vector3).normalized()),"energy":float(op.get("energy",20))})
		if mode!=0:
			var dynamic: Dictionary=state.get("destruction_damage",{}).duplicate(true)
			for hit: Dictionary in state.get("destruction_impacts",[]):
				if dynamic.size()>=8: break
				var local: Vector3=(state.pose as Transform3D).affine_inverse()*hit.point
				var resistance:=KiwiDestructionAuthoring.resistance(regions,local)
				if is_inf(resistance): continue
				hit=hit.duplicate(); hit.energy=float(hit.energy)/resistance
				var physical:=KiwiDestructionMaterial.resolve(values,local); var op: Dictionary
				if physical!=null:
					var cells: Dictionary=state.get("destruction_damage_cells",{}); var key:=str(Vector3i((local/.25).floor())); var cell: Dictionary=cells.get(key,{"damage":0.0})
					var event:=hit.duplicate(); event.local_point=local; event.normal=(state.pose as Transform3D).basis.inverse()*(-hit.normal as Vector3)
					var bounds: AABB=controller.prototypes[id].geometry.bounds; var thickness:=minf(bounds.size.x,minf(bounds.size.y,bounds.size.z))
					op=KiwiDestructionMaterial.response(physical,event,cell,thickness); cells[key]=cell; state.destruction_damage_cells=cells
					if op.is_empty(): continue
				else:
					if float(hit.energy)<maxf(.01,float(values.get(&"destruction_resistance",5))): continue
					op=KiwiDestructionDefinition.operation(int(values.get(&"destruction_impact_type",9)))
					op.position=local; op.direction=(state.pose as Transform3D).basis.inverse()*(-hit.normal as Vector3); op.amount=minf(2,float(values.get(&"destruction_strength",.2))*sqrt(hit.energy/maxf(.01,float(values.get(&"destruction_resistance",5)))))
					op.pieces=int(values.get(&"destruction_detail",6)); op.radius=maxf(.1,controller.prototypes[id].geometry.bounds.size.length()*.4)
				op.age=0.0
				# Escalating physical failure evaluates a fresh closed source, not a
				# previously dented concave surface unsupported by the convex cutter.
				# Local accumulated damage remains; manual operation order is unchanged.
				if int(op.type) in [0,2,3]: dynamic.clear()
				var serial:=int(state.get("destruction_damage_serial",0)); state.destruction_damage_serial=serial+1
				dynamic["impact:"+str(serial)]=op; controller.mesh_damage.emit(id,time,hit)
			for key: String in dynamic.keys():
				var op: Dictionary=dynamic[key]; op.age=float(op.get("age",0))+dt
				if (op.get("elastic",false) or not values.get(&"destruction_permanent",true)) and int(op.type) in [4,9,10,11]:
					op.amount*=exp(-float(values.get(&"destruction_recovery",3))*dt)
					if absf(float(op.amount))<.0001: dynamic.erase(key)
			state.destruction_damage=dynamic; operations.merge(dynamic)
		state.destruction_impacts=[]
		if not state.get("destruction_detached",false):
			var output:=prepare(controller,id,state,values,operations)
			state.destruction_error=output.error
			if not output.error.is_empty(): controller._warn(actor.display_name+": "+str(output.error)); continue
			if operations.is_empty(): state.erase("destruction_geometry"); continue
			state.destruction_geometry=output; state.destruction_detached=output.detached
			if output.detached:
				var active_count:=0
				for inventory: Dictionary in controller.states.values(): active_count+=inventory.get("destruction_fragments",[]).size()
				if active_count+output.rows.size()>256:
					state.erase("destruction_geometry"); state.destruction_detached=false; state.destruction_error="Scene physical debris limit (256) reached. Simplify fractures or split the scene."; controller._warn(state.destruction_error); continue
				var fragments:=[]; var total:=0.0
				for row: Dictionary in output.rows: total+=float(row.volume)
				var impulse:=0.0
				for op: Dictionary in operations.values(): impulse=maxf(impulse,float(op.get("impulse",1)))
				impulse*=float(values.get(&"debris_impulse",1))
				var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
				config.mass=mass(controller,id,state,values,float(config.mass))
				for row: Dictionary in output.rows:
					var pose: Transform3D=state.pose*Transform3D(Basis.IDENTITY,row.center)
					var offset: Vector3=pose.origin-state.pose.origin; var direction:=offset.normalized()
					for op: Dictionary in operations.values():
						if not op.get("enabled",true) or int(op.get("type",0)) in KiwiDestructionAuthoring.NON_GEOMETRY: continue
						direction=direction.lerp((state.pose.basis*(op.get("direction",Vector3.RIGHT) as Vector3)).normalized(),clampf(float(op.get("direction_bias",0)),0,1))
					fragments.append({"id":id+":fragment:"+str(row.id),"mesh":row.mesh,"pose":pose,"v":state.v+state.w.cross(offset)+direction*impulse,"w":state.w,"mass":maxf(.0001,float(config.mass)*float(row.volume)/maxf(.00001,total)),"sleep":0.0,"structure_origin":row.center})
				state.destruction_fragments=fragments; controller.mesh_fractured.emit(id,time,fragments.size())
				controller.debris.emit(controller,id,id,"fracture",time,event_point,event_normal,state.v,event_energy if event_energy>0 else 20.0)
		sync_actor_world(controller,id,state,time)
	controller.debris.step(controller,time,dt)
	# Rewinding may remove whole fragment inventories. Retire stale query bodies.
	var keep:={}
	for state: Dictionary in controller.states.values():
		for fragment: Dictionary in state.get("destruction_fragments",[]): keep[fragment.id]=true
	for key: String in collider_keys.keys():
		if key.contains(":fragment:") and not keep.has(key): controller.world.remove(key); collider_keys.erase(key)

func sync_actor_world(controller: KiwiTimelinePhysics,id: String,state: Dictionary,time: float) -> void:
	if not state.has("destruction_geometry"): return
	var config:=KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time))
	var values:=ActorAnimation.sampled_values(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time))
	if state.get("destruction_detached",false):
		controller.world.place(id,state.pose,false)
		for fragment: Dictionary in state.get("destruction_fragments",[]):
			if not controller.world.bodies.has(fragment.id):
				var shape: Shape3D; var bounds: AABB=fragment.mesh.bounds()
				if bounds.size.length()<float(values.get(&"debris_small_size",.08)):
					var sphere:=SphereShape3D.new(); sphere.radius=maxf(.005,bounds.size.length()*.5); shape=sphere
				else:
					var hull:=ConvexPolygonShape3D.new(); hull.points=fragment.mesh.vertices; shape=hull
				controller.world.add(fragment.id,shape,Transform3D.IDENTITY,int(config.layer),int(config.mask)); collider_keys[fragment.id]=true
			var rule: Dictionary=values.get(&"destruction_fragments",{}).get(KiwiDestructionAuthoring.fragment_key(id,fragment.id),{})
			controller.world.place(fragment.id,fragment.pose,config.collision and state.active and values.get(&"debris_collision",true) and rule.get("collision",true))
	else:
		var output: Dictionary=state.destruction_geometry
		if collider_keys.get(id)!=output.key:
			var shapes:=[]
			for row: Dictionary in output.rows:
				var mesh: KiwiModelMesh=row.mesh
				if not KiwiModelGeometry.convex(mesh):
					if int(config.body_mode)!=1: state.destruction_error="Deformed dynamic collision uses a convex proxy; concave holes require a static surface."
					var render:=mesh.render_mesh(); var shape: Shape3D=render.create_trimesh_shape() if int(config.body_mode)==1 else render.create_convex_shape()
					shapes.append({"shape":shape,"offset":Transform3D(Basis.IDENTITY,row.center)})
				else:
					var hull:=ConvexPolygonShape3D.new(); hull.points=mesh.vertices; shapes.append({"shape":hull,"offset":Transform3D(Basis.IDENTITY,row.center)})
			controller.world.remove(id); controller.world.add_compound(id,shapes,int(config.layer),int(config.mask)); collider_keys[id]=output.key
		controller.world.place(id,state.pose,config.collision and state.active)

func apply(controller: KiwiTimelinePhysics,time: float) -> void:
	for id: String in controller.prototypes:
		var state: Dictionary=controller.display_states.get(id,{})
		if not state.has("destruction_geometry"): continue
		var runtime:=controller._runtime(id)
		if runtime==null: continue
		var output: Dictionary=state.destruction_geometry; var rows: Array=state.get("destruction_fragments",[]) if state.get("destruction_detached",false) else output.rows
		if not nodes.has(id): nodes[id]=[]
		var list: Array=nodes[id]
		while list.size()<rows.size():
			var visual:=MeshInstance3D.new(); visual.name="DamagePiece"+str(list.size()); runtime.add_child(visual); visual.set_as_top_level(true); list.append(visual)
		var actor: ActorData=controller.prototypes[id].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var materials: Array[Material]=[]
		for item: Dictionary in controller.prototypes[id].geometry.meshes:
			for surface in item.surfaces.size(): materials.append(item.node.get_active_material(surface) if is_instance_valid(item.node) else item.materials[surface])
		if materials.is_empty():
			for material: Variant in output.materials: materials.append(material)
		var reference: Variant=values.get(&"destruction_interior"); var object:=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
		if object==null:
			var damage_material:=KiwiDestructionMaterial.resolve(values)
			if damage_material!=null and damage_material.get_value(&"interior") is ActorObjectReference: object=ActorAnimation.resolve_reference(damage_material.get_value(&"interior"))
		var material_key:=hash([values.get(&"destruction_interior_color"),object.values if object!=null else {}])
		if not interiors.has(id) or interiors[id].key!=material_key:
			var inside:=StandardMaterial3D.new(); inside.albedo_color=values.get(&"destruction_interior_color",Color(.24,.19,.13)); inside.roughness=.8
			var interior: Material=inside
			if object!=null:
				if object.type_id==&"shader_material":
					var candidate: ShaderMaterial=runtime._create_shader_material(object)
					if candidate.shader!=null and candidate.shader.get_mode()==Shader.MODE_SPATIAL: interior=candidate
					else: controller._warn("Destruction interiors require a spatial shader; using the interior color instead.")
				elif object.type_id==&"natural_material": interior=preload("res://scripts/materials/natural_material_engine.gd").create_spatial_material(object.get_value(&"material_settings",{}))
				else: inside.albedo_color=object.get_value(&"tint",inside.albedo_color); inside.roughness=object.get_value(&"roughness",.8); inside.albedo_texture=runtime._texture_for_value(object.get_value(&"albedo_map"))
			interiors[id]={"key":material_key,"material":interior}
		materials.append(interiors[id].material)
		for i in list.size():
			var node: MeshInstance3D=list[i]; node.visible=i<rows.size() and runtime.active
			if i>=rows.size(): continue
			var row: Dictionary=rows[i]; var signature:=hash([row.mesh,materials])
			if node.get_meta("damage_mesh_key",-1)!=signature: node.mesh=row.mesh.render_mesh(materials); node.set_meta("damage_mesh_key",signature)
			node.global_transform=row.pose if state.get("destruction_detached",false) else state.pose*Transform3D(Basis.IDENTITY,row.center)
		for item: Dictionary in controller.prototypes[id].geometry.meshes:
			if is_instance_valid(item.node): item.node.set_meta("kiwi_physics_hidden",true); item.node.hide()
func hide() -> void:
	for list: Array in nodes.values():
		for node: MeshInstance3D in list:
			if is_instance_valid(node): node.hide()
static func interpolate(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	if left.get("destruction_detached",false)!=right.get("destruction_detached",false):
		for key in ["destruction_geometry","destruction_detached","destruction_fragments"]:
			if left.has(key): result[key]=left[key].duplicate(true) if left[key] is Array or left[key] is Dictionary else left[key]
			else: result.erase(key)
		return
	var a: Array=left.get("destruction_fragments",[]); var b: Array=right.get("destruction_fragments",[])
	var same:=a.size()==b.size()
	if same:
		for i in a.size():
			if a[i].id!=b[i].id: same=false; break
	if not same:
		result.destruction_fragments=a.duplicate(true); return
	for i in a.size():
		if a[i].id==b[i].id: result.destruction_fragments[i].pose=a[i].pose.interpolate_with(b[i].pose,fraction)
