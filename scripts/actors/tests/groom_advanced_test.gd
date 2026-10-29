extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(1,1,1)}); KiwiSurfaceGrowth.add(session,0); var data:=session.primary().growth
	data.settings.length=1.; data.settings.curvature=0.; data.settings.variation=0.; data.settings.orientation_variation=0.; var root: Dictionary=data.roots[0]; var id:=str(root.id)
	data.guides={"a":{"root":root.id,"points":PackedVector3Array([Vector3.ZERO,Vector3(1,1,0)]),"influence":1.},"b":{"root":root.id,"points":PackedVector3Array([Vector3.ZERO,Vector3(-1,1,0)]),"influence":1.}}
	data.groom[id]={"guide_weights":{"a":1.,"b":1.}}; data.revision+=1
	var curve:=KiwiSurfaceGrowth.curve(data,root)
	check(curve[-1].is_equal_approx(Vector3.UP) and curve[0]==Vector3.ZERO,"Multiple guide weights blend actual curves while preserving the root")
	data.groom[id].guide_weights={"a":1.}; data.guides.a.rotation=Vector3(0,0,PI/2); data.guides.a.length_scale=2.; data.revision+=1
	check(KiwiSurfaceGrowth.curve(data,root)[-1].is_equal_approx(Vector3(-2,2,0)),"Guide rotation and length alter the real interpolated shape")
	data.groom.clear(); data.guides.clear(); data.revision+=1
	var before:=data.roots.duplicate(true); var changed:=KiwiSurfaceGrowth.cut_plane(data,Plane(Vector3.UP,.25))
	check(changed>0 and data.roots==before,"A plane cut preserves stable surface roots")
	var plane_ok:=true
	for candidate: Dictionary in data.roots:
		var shape:=KiwiSurfaceGrowth.curve(data,candidate); var tip: Vector3=KiwiSurfaceGrowth.point_frame(data,candidate,data.source_points)*shape[-1]
		plane_ok=plane_ok and absf(tip.y-.25)<.0001
	check(plane_ok,"Plane cuts trim actual curve intersections rather than approximating a length multiplier")
	data.groom_layers.append({"id":"test","enabled":true,"changes":{id:{"length":2.}}}); data.revision+=1
	check(is_equal_approx(float(KiwiSurfaceGrowth.style(data,root).length),.25),"Individual strand overrides retain precedence over groom layers")
	var tool:=KiwiGroomTool.new(); tool.tool="Color paint"; tool.paint_color=Color.RED; tool.through=true; tool.radius=3.; tool.strength=1.; tool.falloff=0.; tool.apply_at(data,root.position,Vector3.ZERO,Vector3.UP)
	check(KiwiSurfaceGrowth.style(data,root).get("color",Color.WHITE).r==1. and KiwiSurfaceGrowth.style(data,root).color.g<1.,"Color paint affects strand appearance without moving roots")
	check(KiwiPhysicsSettings.physical_groom({id:{"color":Color.RED,"density":.8}}).is_empty(),"Appearance-only groom edits do not invalidate physics")
	data.brush_presets.append({"tool":"Comb","radius":.3,"strength":.6,"falloff":.4,"paint_color":Color.GREEN})
	var path:="user://groom advanced.tres"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded.components[-1].growth.brush_presets.size()==1 and not loaded.components[-1].growth.individual.is_empty(),"Brush presets and direct strand edits survive native save/load")
	DirAccess.remove_absolute(path); print("ADVANCED GROOM: %d checks, %d failures"%[checks,failures]); quit(failures)
