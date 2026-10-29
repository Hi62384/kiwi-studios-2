extends "res://scripts/actors/tests/surface_growth_test.gd"
const Solver=preload("res://scripts/actors/fog/fog_transport_solver.gd")
func seed_state() -> Dictionary:
	var state:=Solver.initialize(8,Vector3.ONE*4.); state.fog_density[2+8*(4+8*4)]=1.; return state
func centroid(state: Dictionary) -> Vector3:
	var points: PackedVector3Array=Solver.grid(int(state.fog_n)).positions; var sum:=Vector3.ZERO; var weight:=0.
	for i in points.size(): sum+=points[i]*state.fog_size*state.fog_density[i]; weight+=state.fog_density[i]
	return sum/maxf(.000001,weight)
func right_mass(state: Dictionary) -> float:
	var total:=0.
	for i in state.fog_density.size():
		if i%8>4: total+=state.fog_density[i]
	return total
func run() -> void:
	var state:=seed_state(); var original:=Solver.total_mass(state); var from:=centroid(state); state.fog_velocity.fill(Vector3.RIGHT)
	var config:={"wind":Vector3.RIGHT,"damping":0.,"wind_response":10.,"pressure_iterations":4}
	var started:=Time.get_ticks_usec()
	for i in 30: Solver.step(state,config,1./30.)
	print("FOG SOLVER n=8 steps=30 ms=",float(Time.get_ticks_usec()-started)/1000.," centroid=",centroid(state)," mass=",Solver.total_mass(state)," lost=",state.fog_lost)
	check(centroid(state).x>from.x+.7,"Wind transports actual persistent concentration across the three-dimensional grid")
	check(absf(Solver.total_mass(state)+float(state.fog_lost)-original)<.00001,"Open-boundary outflow is accounted for rather than silently losing concentration")
	var a:=seed_state(); var b:=seed_state(); var closed:={"closed":true,"turbulence":.5,"turbulence_scale":.7,"seed":19,"diffusion":.05,"expansion":.5,"pressure_iterations":4}; var initial:=Solver.total_mass(a)
	for i in 20: Solver.step(a,closed,.05); Solver.step(b,closed,.05)
	check(a.fog_density==b.fog_density and a.fog_velocity==b.fog_velocity,"Fixed steps and seeded coherent turbulence reproduce density and velocity exactly")
	check(absf(Solver.total_mass(a)-initial)<.00001,"Closed-domain expansion/mixing/transport conserve represented concentration")
	var occupied:=0
	for value: float in a.fog_density:
		if value>.0001: occupied+=1
	check(occupied>5 and a.fog_velocity!=seed_state().fog_velocity,"Mixing and turbulent velocity produce a genuinely evolving cloud")
	var decay:=seed_state()
	for i in 20: Solver.step(decay,{"closed":true,"dissipation":1.,"pressure_iterations":0},.05)
	check(absf(Solver.total_mass(decay)-original*exp(-1.))<.00001,"Dissipation is a calibrated exponential concentration sink")
	var wall:=seed_state(); var mask:=PackedByteArray(); mask.resize(512); var boundary:=PackedVector3Array(); boundary.resize(512)
	for z in 8:
		for y in 8: mask[4+8*(y+8*z)]=1
	Solver.set_obstacles(wall,mask,boundary); wall.fog_velocity.fill(Vector3.RIGHT)
	for i in 30: Solver.step(wall,config,1./30.)
	check(right_mass(wall)==0.,"Face transport cannot cross a complete solid wall")
	mask[4+8*(4+8*4)]=0; Solver.set_obstacles(wall,mask,boundary)
	for i in 45: Solver.step(wall,config,1./30.)
	check(right_mass(wall)>.0001,"Opening a real occupancy passage permits transported fog to cross the barrier")
	var moving:=seed_state(); mask.fill(0); var center:=2+8*(4+8*4); mask[center]=1; boundary[center]=Vector3.RIGHT*2.; Solver.set_obstacles(moving,mask,boundary)
	check(moving.fog_density[center]==0. and absf(Solver.total_mass(moving)-original)<.00001,"Moving solids redistribute displaced fog instead of deleting it")
	Solver.step(moving,{"closed":true,"pressure_iterations":4},1./30.); var motion:=0.
	for value: Vector3 in moving.fog_velocity: motion+=value.length()
	check(motion>.1,"Moving obstacle boundary velocity influences surrounding airflow")
	var emitted:=Solver.initialize(8,Vector3.ONE*4.)
	for i in 30:
		Solver.inject(emitted,PackedInt32Array([center]),PackedFloat32Array([1.]),1./30.,Vector3.RIGHT); Solver.step(emitted,config,1./30.)
	check(absf(Solver.total_mass(emitted)+float(emitted.fog_lost)-1.)<.0001 and centroid(emitted).x>from.x,"Continuous sources add real moving concentration with accounted mass")
	var vortex:=seed_state(); vortex.fog_density.fill(0.); vortex.fog_density[6+8*(4+8*4)]=1.; var old:=centroid(vortex)
	for i in 15: Solver.step(vortex,{"fields":[{"type":3,"direction":Vector3.UP,"center":Vector3.ZERO,"radius":3.,"strength":4.,"falloff":0.}],"pressure_iterations":4},.05)
	check(centroid(vortex).z<old.z-.01,"An authored vortex accelerates real concentration around its axis")
	print("FOG TRANSPORT SOLVER: %d checks, %d failures"%[checks,failures]); quit(failures)
