class_name KiwiDestructionVFX
extends RefCounted
## Render-only adapter from saved physical events to Godot particle draw meshes.
## Analytic event age replaces free-running GPU process time, so seeks/export FPS
## cannot change emission. No second physics or volumetric solver runs here.
const LIMIT:=8192
var nodes: Dictionary={}
var resources: Dictionary={}
var particle_count:=0
func reset() -> void:
	for node: Node in nodes.values():
		if is_instance_valid(node): node.free()
	nodes.clear(); resources.clear()
static func rules(values: Dictionary) -> Array[Dictionary]:
	var material:=KiwiDestructionMaterial.resolve(values); var raw: Variant=material.get_value(&"vfx_family",0) if material!=null else 0; var family:=int(raw) if raw is int or raw is float else 0
	if family==0 and material!=null:
		var title:=str(material.get_value(&"material_name","")).to_lower()
		if "glass" in title or "ceramic" in title: family=1
		elif "steel" in title or "aluminum" in title or "metal" in title: family=2
		elif "wood" in title: family=3
		else: family=4
	var result: Array[Dictionary]=[]
	match family:
		1: result.append({"style":1,"color":Color(.7,.9,1,.8),"particle_size":.025,"velocity":2.0,"gravity":Vector3(0,-9.8,0),"amount":1.0,"lifetime":1.0})
		2: result.append({"style":3,"color":Color(1,.65,.15),"particle_size":.03,"velocity":4.0,"gravity":Vector3(0,-5,0),"amount":.7,"lifetime":.6})
		3:
			result.append({"style":2,"color":Color(.5,.25,.09),"particle_size":.04,"velocity":2.0,"gravity":Vector3(0,-9.8,0),"amount":.7,"lifetime":1.0}); result.append({"style":0,"color":Color(.6,.4,.2,.25),"particle_size":.12,"velocity":.8,"gravity":Vector3(0,-.2,0),"amount":.3,"lifetime":1.0})
		_:
			result.append({"style":0,"color":Color(.55,.52,.46,.28),"particle_size":.18,"velocity":.8,"gravity":Vector3(0,.2,0),"amount":1.0,"lifetime":1.0}); result.append({"style":1,"color":Color(.4,.38,.34),"particle_size":.035,"velocity":2.0,"gravity":Vector3(0,-9.8,0),"amount":.35,"lifetime":.8})
	var reference: Variant=values.get(&"debris_vfx_preset")
	if reference==null and material!=null: reference=material.get_value(&"vfx_preset")
	var preset:=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
	if preset!=null:
		if int(values.get(&"debris_vfx_mode",0))==0: result.clear()
		result.append(preset.values.duplicate())
	return result
static func particles(event: Dictionary,rule: Dictionary,values: Dictionary,time: float,limit: int=512) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var age: float=(time-float(event.time))*float(event.get("age_scale",1.)); var life:=clampf(float(values.get(&"debris_lifetime",2))*float(rule.get("lifetime",1)),.05,10)
	if age<0 or age>life or not values.get(&"debris_vfx_enabled",true): return result
	var style:=int(rule.get("style",0)); var energy:=float(event.energy)
	if style==3 and (energy<2 or event.type in ["fracture","secondary"]): return result # cold metal separation is not a spark event.
	if style==0 and energy<.5: return result
	var intensity:=clampf(log(1+energy)*.3*float(values.get(&"debris_intensity",1)),0,6)
	var amount:=clampi(roundi(float(values.get(&"debris_particles",48))*float(rule.get("amount",1))*intensity*float(values.get(&"debris_dust" if style==0 else &"debris_chips",1))),0,limit)
	var rng:=RandomNumberGenerator.new(); rng.seed=int(event.seed)+style*7919
	for i in amount:
		var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(.1,1),rng.randf_range(-1,1)).normalized(); var speed:=float(rule.get("velocity",2))*rng.randf_range(.35,1.2)*minf(3,sqrt(maxf(.01,energy))*.3)
		var velocity: Vector3=(direction+(event.normal as Vector3)*.6).normalized()*speed+(event.velocity as Vector3)*.08
		var size:=maxf(.001,float(rule.get("particle_size",.05)))*rng.randf_range(.6,1.4)*(1+age*.8 if style==0 else 1.0)
		var basis:=Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())*TAU).scaled(Vector3.ONE*size)
		if style in [2,3]: basis=basis.scaled(Vector3(3,.4,.4))
		var color: Color=rule.get("color",Color.WHITE); color.a*=pow(clampf(1-age/life,0,1),.7)
		result.append({"pose":Transform3D(basis,event.point+velocity*age+(rule.get("gravity",Vector3.DOWN) as Vector3)*age*age*.5),"color":color})
	return result
func mesh(style: int) -> Mesh:
	if resources.has(style): return resources[style]
	var geometry: Mesh; var material:=StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.roughness=.5
	if style==0:
		var quad:=QuadMesh.new(); quad.size=Vector2.ONE; geometry=quad; material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED; material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test=false
		var image:=Image.create(32,32,false,Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32: image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-Vector2((x-15.5)/15.5,(y-15.5)/15.5).length()),1.5)))
		material.albedo_texture=ImageTexture.create_from_image(image)
	elif style in [2,3]: geometry=BoxMesh.new()
	else:
		var sphere:=SphereMesh.new(); sphere.radius=.5; sphere.height=1; sphere.radial_segments=5; sphere.rings=2; geometry=sphere; material.metallic=.5
	if style==3: material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	geometry.surface_set_material(0,material); resources[style]=geometry; return geometry
func apply(controller: KiwiTimelinePhysics,time: float) -> void:
	particle_count=0; var used:={}
	for owner: String in controller.display_states:
		if particle_count>=LIMIT: break
		var events: Array=controller.display_states[owner].get("destruction_events",[])
		if events.is_empty(): continue
		var actor: ActorData=controller.prototypes[owner].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var runtime:=controller._runtime(owner)
		if runtime==null or not runtime.active or not values.get(&"debris_vfx_enabled",true): continue
		var rules:=rules(values)
		for index in rules.size():
			var rule: Dictionary=rules[index]; var points: Array[Dictionary]=[]
			for event: Dictionary in events:
				points.append_array(particles(event,rule,values,time,maxi(0,mini(512,LIMIT-particle_count-points.size()))))
				if points.size()+particle_count>=LIMIT: break
			if points.is_empty(): continue
			var key:=owner+":"+str(index); used[key]=true
			if not nodes.has(key):
				var node:=MultiMeshInstance3D.new(); node.name="DestructionEventParticles"; runtime.add_child(node); node.set_as_top_level(true); node.global_transform=Transform3D.IDENTITY; node.layers=1; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; node.multimesh=MultiMesh.new(); node.multimesh.transform_format=MultiMesh.TRANSFORM_3D; node.multimesh.use_colors=true; nodes[key]=node
			var node: MultiMeshInstance3D=nodes[key]; node.multimesh.mesh=mesh(int(rule.get("style",0))); node.multimesh.instance_count=points.size(); node.show()
			for i in points.size(): node.multimesh.set_instance_transform(i,points[i].pose); node.multimesh.set_instance_color(i,points[i].color)
			particle_count+=points.size()
	for key: String in nodes:
		if not used.has(key): nodes[key].hide()
