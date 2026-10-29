extends RefCounted
## Screen-space editor overlay, never included in rendered video.
static func draw(spatial: Node,runtime: KiwiPowderRuntime) -> void:
	var actor:=runtime.actor; var time: float=spatial.editor.canvas.playhead
	var values:=ActorAnimation.sampled_values(actor,spatial.editor.model.clip_for_actor_id(actor.id).local_time(time))
	if not values.powder_show_source: return
	var config:=KiwiPhysicsSettings.sample(actor,actor.animation_time)
	var pose:=KiwiPowderBridge.source(spatial.editor.physics,actor.id,config,time)
	var lines: Array[PackedVector3Array]=[]
	if int(values.powder_source_mode)!=1:
		if int(values.powder_shape)==3:
			var source: ActorRuntime=spatial.editor.physics._runtime(str(values.powder_mesh_actor))
			if source!=null:
				var bounds: Dictionary=spatial.bounds(source)
				if not bounds.is_empty(): box(lines,bounds.box,Transform3D.IDENTITY)
		elif int(values.powder_shape)==0: box(lines,AABB(-values.powder_dimensions*.5,values.powder_dimensions),pose)
		else:
			var half: Vector3=values.powder_dimensions*.5
			if int(values.powder_shape)==1:
				for axis in 3: ring(lines,pose,half,axis)
			else:
				for y in [-half.y,half.y]: ring(lines,pose*Transform3D(Basis.IDENTITY,Vector3(0,y,0)),Vector3(half.x,0,half.z),1)
				for angle in [0.0,PI*.5,PI,PI*1.5]: lines.append(PackedVector3Array([pose*Vector3(half.x*cos(angle),-half.y,half.z*sin(angle)),pose*Vector3(half.x*cos(angle),half.y,half.z*sin(angle))]))
	if int(values.powder_source_mode)!=0:
		var radius:=float(values.powder_emit_radius); var direction: Vector3=(values.powder_emit_direction as Vector3).normalized()
		if direction.is_zero_approx(): direction=Vector3.DOWN
		var frame:=Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>.9 else Vector3.UP)
		match int(values.powder_emit_shape):
			0: box(lines,AABB(-Vector3.ONE*.025,Vector3.ONE*.05),pose)
			1: ring(lines,pose*Transform3D(frame,Vector3.ZERO),Vector3.ONE*radius,2)
			2: box(lines,AABB(-values.powder_emit_dimensions*.5,values.powder_emit_dimensions),pose)
			3:
				for axis in 3: ring(lines,pose,Vector3.ONE*radius,axis)
		var tip: Vector3=direction*maxf(.4,radius*2)
		lines.append(PackedVector3Array([pose.origin,pose*tip]))
		for sign_value in [-1,1]: lines.append(PackedVector3Array([pose*tip,pose*(tip-direction*.1+frame.x*.06*sign_value)]))
	for line in lines:
		for i in line.size()-1:
			if spatial.camera().is_position_behind(line[i]) or spatial.camera().is_position_behind(line[i+1]): continue
			spatial.gizmo.draw_line(spatial.project(line[i]),spatial.project(line[i+1]),Color("d9b477"),1.2,true)
static func box(lines: Array[PackedVector3Array],bounds: AABB,pose: Transform3D) -> void:
	for i in 8:
		var a:=bounds.position+bounds.size*Vector3(i&1,(i>>1)&1,(i>>2)&1)
		for axis in 3:
			if (i&(1<<axis))==0:
				var b:=a; b[axis]+=bounds.size[axis]; lines.append(PackedVector3Array([pose*a,pose*b]))
static func ring(lines: Array[PackedVector3Array],pose: Transform3D,half: Vector3,axis: int) -> void:
	var points:=PackedVector3Array()
	for i in 49:
		var point:=Vector3.ZERO; point[(axis+1)%3]=cos(TAU*i/48)*half[(axis+1)%3]; point[(axis+2)%3]=sin(TAU*i/48)*half[(axis+2)%3]; points.append(pose*point)
	lines.append(points)
