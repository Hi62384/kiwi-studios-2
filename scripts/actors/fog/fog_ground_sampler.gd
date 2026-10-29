extends RefCounted
## Bounded height cache over the existing offline timeline collision world.
static var cache: Dictionary={}
static func prepare(controller: RefCounted,pose: Transform3D,size: Vector3,settings: Dictionary) -> Dictionary:
	if controller==null or not controller.world.space.is_valid(): return {"error":"Enable the terrain's normal physics collider to sample its surface."}
	if absf(pose.basis.orthonormalized().y.dot(Vector3.UP))<.99: return {"error":"Terrain-following mist needs an upright domain. Use world elevation for a tilted volume."}
	var rows:=[]
	for id: String in controller.world.bodies:
		if id.begins_with("@probe:"): continue
		var entry: Dictionary=controller.world.bodies[id]
		rows.append([id,entry.get("pose",Transform3D.IDENTITY),entry.get("enabled",false),entry.shape.get_rid()])
	var fallback:=float(settings.get(&"cloud_ground_height",0.)); var reach:=maxf(1.,float(settings.get(&"cloud_ground_search",1000.))); var mask:=int(settings.get(&"cloud_ground_mask",1)); var key:=hash([pose,size,rows,fallback,reach,mask])
	if cache.has(key): return cache[key]
	var started:=Time.get_ticks_usec(); var n:=16; var image:=Image.create(n,n,false,Image.FORMAT_RF); var hits:=0
	var space: PhysicsDirectSpaceState3D=PhysicsServer3D.space_get_direct_state(controller.world.space)
	for y in n:
		for x in n:
			var point:=pose*(Vector3((x+.5)/n-.5,0.,(y+.5)/n-.5)*size); var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*reach,point-Vector3.UP*reach,mask); query.collide_with_areas=false
			var hit:=space.intersect_ray(query); var height:=fallback
			if not hit.is_empty(): height=(hit.position as Vector3).y; hits+=1
			image.set_pixel(x,y,Color(height,0,0,1.))
	var result:={"image":image,"texture":ImageTexture.create_from_image(image),"key":key,"hits":hits,"milliseconds":float(Time.get_ticks_usec()-started)/1000.,"error":"" if hits>0 else "No collision surface was found; using the configured ground elevation."}
	if cache.size()>=16: cache.erase(cache.keys()[0])
	cache[key]=result; return result

static func sample_height(image: Image,unit: Vector3) -> float:
	var p:=Vector2(unit.x,unit.z)*Vector2(image.get_size())-Vector2.ONE*.5; var base:=Vector2i(p.floor()); var f:=p-Vector2(base); var height:=0.
	for y in 2:
		for x in 2:
			var cell: Vector2i=(base+Vector2i(x,y)).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE); height+=image.get_pixelv(cell).r*(f.x if x else 1.-f.x)*(f.y if y else 1.-f.y)
	return height

static func sync(runtime: Node,material: ShaderMaterial) -> void:
	material.set_shader_parameter("scene_ground",false); runtime.content.set_meta("fog_ground_error","")
	var values:=ActorAnimation.sampled_values(runtime.actor,runtime.actor.animation_time if not is_nan(runtime.actor.animation_time) else 0.); var field:=ActorAnimation.resolve_reference(values.get(&"field")) if values.get(&"field") is ActorObjectReference else null
	if field==null or int(field.values.get(&"mode",0))!=8 or not field.values.get(&"cloud_follow_ground",false): return
	var controller: RefCounted
	for editor in runtime.get_tree().get_nodes_in_group("actor_timeline_editors"):
		if editor.model.actor_for_id(runtime.actor.id)==runtime.actor: controller=editor.physics; break
	var result:=prepare(controller,runtime.content.global_transform,runtime.content.size,field.values)
	runtime.content.set_meta("fog_ground_error",result.get("error",""))
	if result.get("texture") is Texture2D:
		material.set_shader_parameter("scene_ground",true); material.set_shader_parameter("scene_ground_height",result.texture)
