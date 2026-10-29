extends SceneTree
var checks:=0
var failures:=0
var solver:=KiwiPowderSolver.new()
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func batch(points: PackedVector3Array,extra: Dictionary={},radius: float=.05,density: float=1600) -> Dictionary:
	var values:=KiwiPowderDefinition.create().create_actor().values; values.merge(extra,true); values.powder_radius=radius; values.powder_density=density; values.powder_air_drag=0.0
	var state:={"v":Vector3.ZERO,"powder_time":0.0}; KiwiPowderSource.initialize(state); state.powder_time=0.0
	for p in points: KiwiPowderSource.append(state,p,Vector3.ZERO,values,Transform3D.IDENTITY,0,0)
	return {"id":ActorData.new_id(),"state":state,"settings":KiwiPowderSettings.effective(values),"config":KiwiPhysicsSettings.DEFAULTS.duplicate(true),"h":1.0/60,"moving":true,"gravity":Vector3.DOWN*9.8,"wind":Vector3.ZERO,"force":Vector3.ZERO,"impulse":Vector3.ZERO}
func empty_collision(_id: String,_from: Vector3,to: Vector3,_radius: float,_h: float) -> Dictionary: return {"position":to,"hits":[]}
func plane(normal: Vector3=Vector3.UP,friction: float=1.0) -> Callable:
	return func(_id: String,_from: Vector3,to: Vector3,radius: float,_h: float) -> Dictionary:
		var depth:=radius-normal.dot(to)
		if depth<-.002: return {"position":to,"hits":[]}
		return {"position":to+normal*maxf(0,depth),"hits":[{"normal":normal,"point":to-normal*normal.dot(to),"actor":"floor","friction":friction,"velocity":Vector3.ZERO,"restitution":1.0}]}
func advance(items: Array[Dictionary],steps: int,collision: Callable) -> void:
	for step in steps:
		for item in items: item.state.powder_time+=item.h
		solver.solve(items,collision,Callable())
func run() -> void:
	var points:=PackedVector3Array()
	for x in 4:
		for y in 4:
			for z in 4: points.append(Vector3(x*.105-.1575,1+y*.105,z*.105-.1575))
	var sand:=batch(points); advance([sand],180,plane())
	var lowest:=INF; var highest:=-INF; var overlap:=0.0
	for i in sand.state.points.size():
		var p: Vector3=sand.state.points[i]; lowest=minf(lowest,p.y); highest=maxf(highest,p.y)
		for j in range(i+1,sand.state.points.size()): overlap=maxf(overlap,.1-p.distance_to(sand.state.points[j]))
	check(lowest>=.049 and highest>.14 and highest<1,"Grains fall, collide with a floor and support a multi-grain pile")
	check(overlap<.012,"Dense pile resolves grain contacts without severe interpenetration")
	var settled: PackedVector3Array=sand.state.points.duplicate(); advance([sand],60,plane()); var drift:=0.0
	for i in settled.size(): drift=maxf(drift,settled[i].distance_to(sand.state.points[i]))
	print("PILE height=",highest," overlap=",overlap," drift_1s=",drift)
	check(drift<.08,"Stopped pile remains approximately stable rather than spreading indefinitely")
	var supported_y: float=sand.state.points[0].y; advance([sand],15,empty_collision)
	check(sand.state.points[0].y<supported_y-.03,"Sleeping grains wake and fall when their support is removed")
	var slope:=Vector3(.57,.82,0).normalized(); var loose:=batch(PackedVector3Array([slope*.06]),{&"powder_friction":.01}); var rough:=batch(PackedVector3Array([slope*.06]),{&"powder_friction":2.0})
	advance([loose],90,plane(slope)); advance([rough],90,plane(slope))
	check(loose.state.points[0].distance_to(slope*.06)>rough.state.points[0].distance_to(slope*.06)+.3,"Static/dynamic Coulomb friction meaningfully changes sliding on slopes")
	var low_flow:=batch(PackedVector3Array([slope*.06]),{&"powder_friction":.4,&"powder_flowability":0.0}); var high_flow:=batch(PackedVector3Array([slope*.06]),{&"powder_friction":.4,&"powder_flowability":1.0})
	advance([low_flow],90,plane(slope)); advance([high_flow],90,plane(slope))
	print("FLOW low=",low_flow.state.points[0]," high=",high_flow.state.points[0])
	check(high_flow.state.points[0].distance_to(slope*.06)>low_flow.state.points[0].distance_to(slope*.06)+.2,"Simple Flowability derives a measurable change in contact flow without overwriting base friction")
	var loose_pair:=batch(PackedVector3Array([Vector3(-.05,0,0),Vector3(.05,0,0)])); var cohesive:=batch(loose_pair.state.points,{&"powder_cohesion":2.0})
	for item in [loose_pair,cohesive]: item.gravity=Vector3.ZERO; item.state.velocities=PackedVector3Array([Vector3.LEFT*.1,Vector3.RIGHT*.1])
	advance([loose_pair],30,empty_collision); advance([cohesive],30,empty_collision)
	print("COHESION loose=",loose_pair.state.points," cohesive=",cohesive.state.points," bonds=",cohesive.state.powder_bonds)
	check(cohesive.state.points[0].distance_to(cohesive.state.points[1])<loose_pair.state.points[0].distance_to(loose_pair.state.points[1])-.04 and not cohesive.state.powder_bonds.is_empty(),"Cohesion creates real breakable tensile contacts, not just damping")
	cohesive.state.velocities=PackedVector3Array([Vector3.LEFT*15,Vector3.RIGHT*15]); advance([cohesive],15,empty_collision)
	check(cohesive.state.powder_bonds.is_empty(),"Strong separation breaks cohesive grain bonds")
	var soft:=batch(PackedVector3Array([Vector3.ZERO,Vector3(.07,0,0)]),{&"powder_compaction":.05}); var hard:=batch(soft.state.points,{&"powder_compaction":1.0})
	soft.gravity=Vector3.ZERO; hard.gravity=Vector3.ZERO; advance([soft],1,empty_collision); advance([hard],1,empty_collision)
	check(hard.state.points[0].distance_to(hard.state.points[1])>soft.state.points[0].distance_to(soft.state.points[1])+.001 and hard.state.powder_radii[0]==soft.state.powder_radii[0],"Compaction changes contact stiffness without shrinking solid grains")
	var light:=batch(PackedVector3Array([Vector3.ZERO]),{},.05,500); var heavy:=batch(PackedVector3Array([Vector3.ZERO]),{},.05,5000)
	light.force=Vector3.RIGHT*.01; heavy.force=light.force; advance([light],12,empty_collision); advance([heavy],12,empty_collision)
	check(light.state.velocities[0].x>heavy.state.velocities[0].x*8 and absf(light.state.velocities[0].y-heavy.state.velocities[0].y)<.0001,"Density changes force acceleration, not gravitational acceleration in vacuum")
	var small:=batch(PackedVector3Array([Vector3.ZERO]),{},.02); var large:=batch(PackedVector3Array([Vector3.ZERO]),{},.08)
	for item in [small,large]: item.settings.air_drag=.47; item.wind=Vector3.RIGHT*8; item.gravity=Vector3.ZERO
	advance([small],30,empty_collision); advance([large],30,empty_collision)
	check(small.state.velocities[0].x>large.state.velocities[0].x*2,"Aerodynamic acceleration depends on area/mass so fine grains respond more to wind")
	var bounce:=batch(PackedVector3Array([Vector3(0,.07,0)]),{&"powder_restitution":.9}); var dead:=batch(bounce.state.points,{&"powder_restitution":0.0})
	for item in [bounce,dead]: item.state.velocities[0]=Vector3.DOWN*3
	advance([bounce],1,plane()); advance([dead],1,plane())
	check(bounce.state.velocities[0].y>dead.state.velocities[0].y+.3,"Restitution changes actual impact rebound speed")
	var bouncy_pair:=batch(PackedVector3Array([Vector3(-.055,0,0),Vector3(.055,0,0)]),{&"powder_restitution":.8})
	bouncy_pair.gravity=Vector3.ZERO; bouncy_pair.state.velocities=PackedVector3Array([Vector3.RIGHT,Vector3.LEFT]); advance([bouncy_pair],1,empty_collision)
	check(bouncy_pair.state.velocities[0].x<-.2 and bouncy_pair.state.velocities[1].x>.2,"Grain-to-grain restitution uses pre-projection impact speed, not already-cancelled velocities")
	var one:=batch(PackedVector3Array([Vector3.ZERO])); var two:=batch(PackedVector3Array([Vector3(.05,0,0)])); one.gravity=Vector3.ZERO; two.gravity=Vector3.ZERO
	advance([one,two],1,empty_collision); check(one.state.points[0].distance_to(two.state.points[0])>.095,"Separate Powder Actors exchange contact corrections")
	one.state.points[0]=Vector3.ZERO; two.state.points[0]=Vector3(.05,0,0); one.state.velocities[0]=Vector3.ZERO; two.state.velocities[0]=Vector3.ZERO; one.config.mask=2; advance([one,two],1,empty_collision)
	check(one.state.points[0].distance_to(two.state.points[0])<.06,"Cross-actor collision masks suppress disallowed grain contacts")
	var dense_points:=PackedVector3Array()
	for x in 8:
		for y in 8:
			for z in 8: dense_points.append(Vector3(x,y,z)*.105)
	var moderate:=batch(dense_points); moderate.gravity=Vector3.ZERO; var started:=Time.get_ticks_usec(); advance([moderate],3,empty_collision)
	print("GRANULAR CPU: grains=512 mean_step_ms=",(Time.get_ticks_usec()-started)/3000.0," neighbor_checks=",solver.checks)
	check(solver.error.is_empty() and solver.checks<512*512,"Broadphase uses spatial neighborhoods rather than every grain pair")
	print("POWDER SOLVER: %d checks, %d failures"%[checks,failures]); quit(failures)
