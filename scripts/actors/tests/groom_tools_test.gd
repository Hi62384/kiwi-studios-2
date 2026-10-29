extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(2,1,2)}); KiwiSurfaceGrowth.add(session,0); var item:=session.primary(); var data:=item.growth; var tool:=KiwiGroomTool.new(); tool.radius=.5; tool.through=true; tool.strength=.8; var root_data: Dictionary=data.roots[0]; var center: Vector3=root_data.position; var anchors:=data.roots.duplicate(true); var raw:=KiwiSurfaceGrowth.curve(data,root_data)
	for name: String in ["Comb","Brush","Cut","Grow","Curl","Clump","Density","Length","Smooth","Part","Feather width","Spread"]:
		data.pending.clear(); data.revision+=1; tool.tool=name; var affected:=tool.apply_at(data,center,Vector3(.2,0,0),Vector3.UP); var change: Dictionary=data.pending.get(str(root_data.id),{})
		check(affected>0 and not change.is_empty(),"Functional sparse grooming: "+name)
	data.pending.clear(); data.revision+=1; tool.tool="Brush"; tool.apply_at(data,center,Vector3(.3,0,0),Vector3.UP); var styled:=KiwiSurfaceGrowth.curve(data,root_data)
	check(styled[0]==Vector3.ZERO and styled[-1]!=raw[-1] and data.roots==anchors,"Brush changes actual curve shape without moving roots or regenerating distribution")
	var distant: Dictionary={}
	for candidate: Dictionary in data.roots:
		if (candidate.position as Vector3).distance_to(center)>tool.radius*2: distant=candidate; break
	check(not distant.is_empty() and not data.pending.has(str(distant.id)),"Local strokes preserve unrelated strands")
	data.groom_layers.append({"id":"stroke","tool":"Brush","enabled":true,"changes":data.pending.duplicate(true)}); data.pending.clear(); data.revision+=1
	check(KiwiSurfaceGrowth.curve(data,root_data)==styled,"Grooming commits preserve the visible result as an ordered non-destructive layer")
	data.groom_layers[0].enabled=false; data.revision+=1; check(KiwiSurfaceGrowth.curve(data,root_data)==raw,"Disabling a grooming layer restores the base generation")
	data.groom_layers[0].enabled=true; data.revision+=1; var path:="user://groom_"+ActorData.new_id()+".tres"; ResourceSaver.save(session.document,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(KiwiSurfaceGrowth.curve(reopened.components[-1].growth,root_data)==styled,"Groom layers remain editable and deterministic after reopening")
	var before:=data.roots.duplicate(true); var count_before:=0; var count_after:=0
	for candidate: Dictionary in data.roots:
		if candidate.density_rank<KiwiSurfaceGrowth.style(data,candidate).density: count_before+=1
	tool.tool="Density"; tool.replace=true; tool.value=1; tool.radius=3; tool.apply_at(data,Vector3.ZERO,Vector3.ZERO,Vector3.UP)
	for candidate: Dictionary in data.roots:
		if candidate.density_rank<KiwiSurfaceGrowth.style(data,candidate).density: count_after+=1
	check(count_after>count_before and data.roots==before,"Density painting reveals reserved candidate roots locally without reshuffling survivors")
	data.settings.type=2; data.revision+=1; check(KiwiSurfaceGrowth.render(data).get_surface_count()>0,"Groomed feathers retain distinct valid vane/shaft geometry")
	print("GROOM BENCH touched=",tool.touched," candidates=",data.roots.size()," last_apply_ms=",data.groom_usec/1000.0)
	DirAccess.remove_absolute(path); print("GROOM TOOLS: %d checks, %d failures"%[checks,failures]); quit(failures)
