extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func geometry(mesh: Mesh) -> Dictionary:
	var surfaces:=[]
	for i in mesh.get_surface_count(): surfaces.append(mesh.surface_get_arrays(i))
	return {"meshes":[{"local":Transform3D.IDENTITY,"surfaces":surfaces}]}
func run() -> void:
	var definition:=KiwiPowderDefinition.create(); var values:=definition.create_actor().values
	check(definition.type_id==&"powder" and definition.category=="Simulation" and definition.icon!=null,"Powder is a distinct Simulation actor with its own icon")
	var pose:=Transform3D(Basis.from_euler(Vector3(.2,.5,0))*Basis.from_scale(Vector3(2,1,.8)),Vector3(3,2,-1))
	for shape in 3:
		values.powder_shape=shape; var volume:=KiwiPowderSource.volume(values,pose); var valid: bool=str(volume.error).is_empty() and volume.points.size()>20
		for world: Vector3 in volume.points:
			var p:=pose.affine_inverse()*world; var q: Vector3=p/(values.powder_dimensions*.5)
			valid=valid and p.abs().x<=.5 and p.abs().y<=.5 and p.abs().z<=.5
			if shape==1: valid=valid and q.length_squared()<=1.00001
			if shape==2: valid=valid and Vector2(q.x,q.z).length_squared()<=1.00001
		check(valid,"Volume shape %d fills its actual transformed interior"%shape)
		check(volume.points==KiwiPowderSource.volume(values,pose).points,"Volume jitter is deterministic for shape %d"%shape)
	values.powder_shape=3; var torus:=TorusMesh.new(); torus.inner_radius=.35; torus.outer_radius=.85; torus.rings=24; torus.ring_segments=16
	var data:=geometry(torus); var volume:=KiwiPowderSource.volume(values,Transform3D.IDENTITY,data); var valid: bool=str(volume.error).is_empty() and volume.points.size()>5
	for p: Vector3 in volume.points: valid=valid and Vector2(p.x,p.z).length()>.3
	check(valid,"Closed indexed torus is filled inside the tube, never its bounding-box hole")
	check(not str(KiwiPowderSource.volume(values,Transform3D.IDENTITY,geometry(PlaneMesh.new())).error).is_empty(),"Open mesh is rejected with an actionable error")
	var degenerate:=[]; degenerate.resize(Mesh.ARRAY_MAX); degenerate[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.RIGHT*2])
	check(KiwiVolumeSampler.closed_mesh({"meshes":[{"local":Transform3D.IDENTITY,"surfaces":[degenerate]}]}).error.contains("degenerate"),"Degenerate triangles are rejected")
	var box:=geometry(BoxMesh.new()); box.meshes.append(box.meshes[0]); check(not KiwiVolumeSampler.closed_mesh(box).error.is_empty(),"Duplicate/nonmanifold surfaces are rejected")
	values.powder_shape=0; values.powder_dimensions=Vector3(3,3,3); values.powder_budget=10
	var rejected:=KiwiPowderSource.volume(values,Transform3D.IDENTITY)
	check(rejected.points.is_empty() and rejected.error.contains("budget"),"Budget rejection never displays a partial volume")
	values.powder_dimensions=Vector3(0,1,1); check(not KiwiPowderSource.volume(values,Transform3D.IDENTITY).error.is_empty(),"Zero dimensions are rejected")
	var variant_values:=definition.create_actor({&"powder_size_variation":.3,&"powder_radius":.04}).values
	var grains:={"v":Vector3.ZERO}; KiwiPowderSource.initialize(grains)
	for i in 20: KiwiPowderSource.append(grains,Vector3(i,0,0),Vector3.ZERO,variant_values,Transform3D.IDENTITY,0,0)
	var smallest:=INF; var largest:=0.0; var valid_mass:=true
	for i in grains.points.size():
		var radius:=float(grains.powder_radii[i]); smallest=minf(smallest,radius); largest=maxf(largest,radius)
		valid_mass=valid_mass and absf(float(grains.powder_masses[i])-1600.0*4.0/3.0*PI*pow(radius,3))<.00001
	check(largest>smallest*1.2 and smallest>=.028 and largest<=.052 and valid_mass,"Seeded size distribution changes real radius and density-derived mass consistently")
	variant_values.powder_density=-1.0; check(not KiwiPowderSource.validate(variant_values).is_empty(),"Invalid negative grain masses cannot enter source data")
	values.powder_dimensions=Vector3(3,3,3); values.powder_spacing=.1; values.powder_radius=.035; values.powder_budget=40000
	var start:=Time.get_ticks_usec(); var moderate:=KiwiPowderSource.volume(values,Transform3D.IDENTITY); var elapsed:=Time.get_ticks_usec()-start
	check(moderate.points.size()==27000 and moderate.error.is_empty(),"Moderate 27,000-grain source is generated without one node per grain")
	print("POWDER GENERATION: grains=",moderate.points.size()," milliseconds=",elapsed/1000.0)
	var preview:=definition.create_runtime(definition.create_actor()) as KiwiPowderRuntime; root.add_child(preview)
	var radii:=PackedFloat32Array(); radii.resize(moderate.points.size()); radii.fill(.035)
	start=Time.get_ticks_usec(); preview.show_state({"points":moderate.points,"powder_radii":radii}); elapsed=Time.get_ticks_usec()-start
	check(preview.instance_count()==27000 and preview.grains.get_child_count()==0 and preview.get_child_count()<10,"Moderate preview uses 27,000 GPU instances with constant scene-node count")
	print("POWDER PREVIEW: grains=27000 CPU_buffer_upload_ms=",elapsed/1000.0)
	preview.queue_free(); await process_frame
	print("POWDER SOURCE: %d checks, %d failures"%[checks,failures]); quit(failures)
