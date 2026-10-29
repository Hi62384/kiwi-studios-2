extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.amplitude=3.; terrain.prepare(); var source:=KiwiEnvironmentScatter.new(); source.palette=[{"source":"tree.tres","weight":1.},{"source":"rock.tres","weight":2.}]; source.slope_range=Vector2(0,90); var a:=source.generate(terrain); var b:=source.generate(terrain)
	check(a.count>20 and a.batches==b.batches,"Weighted scatter rules generate deterministic placements from a saved seed")
	var anchored:=true; var all: Array[Transform3D]=[]; var orientation:=true
	for batch: Array in a.batches.values():
		for transform: Transform3D in batch:
			all.append(transform); var hit:=terrain.sample(Vector2(transform.origin.x,transform.origin.z)); anchored=anchored and absf(float(hit.height)-transform.origin.y)<.00001; orientation=orientation and transform.basis.y.normalized().dot(hit.normal)>.999
	check(anchored and orientation,"Scatter follows actual terrain height and aligns to its surface normals")
	var separated:=true
	for i in all.size():
		for j in i:
			var x:=Vector2(all[i].origin.x,all[i].origin.z); var y:=Vector2(all[j].origin.x,all[j].origin.z); separated=separated and x.distance_to(y)>=source.minimum_distance-.0001
	check(separated,"Spatial rejection enforces the configured minimum spacing")
	source.seed=19; var changed:=source.generate(terrain); check(a.batches!=changed.batches,"Changing the scatter seed changes the generated placements")
	source.paint_regions=[Vector3(0,0,3.)]; source.erase_regions=[Vector3(0,0,1.)]; var masked:=source.generate(terrain); var inside: bool=masked.count>0
	for batch: Array in masked.batches.values():
		for transform: Transform3D in batch:
			var radius:=Vector2(transform.origin.x,transform.origin.z).length(); inside=inside and radius<=3.001 and radius>=.999
	check(inside,"Paint and erase regions remain editable generation masks")
	source.paint_regions.clear(); source.erase_regions.clear(); source.budget=25; source.density=100.
	var bounded:=source.generate(terrain); check(bounded.count<=25,"Scatter generation obeys a real instance budget")
	terrain.edits.fill(2.); terrain.revision+=1; var moved:=source.generate(terrain); var follows:=true
	for key: int in bounded.batches:
		for i in bounded.batches[key].size(): follows=follows and absf(moved.batches[key][i].origin.y-bounded.batches[key][i].origin.y-2.)<.0001
	check(follows,"Reevaluating scatter after terrain editing preserves seed placement and updates elevation")
	var session:=KiwiEnvironmentSession.new(); var item:=session.add_terrain(); var layer:=session.environment().add_group("Painted objects"); source.terrain_id=item.id; session.environment().component_settings[layer.id]={"kind":"scatter","scatter":source}
	check(session.begin_scatter(layer.id),"Scatter region painting begins on an editable scatter layer")
	session.paint_scatter(Vector2.ZERO,3.,false); session.paint_scatter(Vector2.ONE,1.,true); session.finish_scatter()
	check(source.paint_regions.size()==1 and source.erase_regions.size()==1,"A painted stroke stores live editable inclusion and exclusion regions")
	session.undo(); check(source.paint_regions.is_empty() and source.erase_regions.is_empty(),"Multi-dab scatter painting undoes as a single transaction")
	session.redo(); check(source.paint_regions.size()==1 and source.erase_regions.size()==1,"Scatter painting redoes its saved generation masks")
	session.begin_scatter(layer.id); session.paint_scatter(Vector2(5,5),1.,false); session.finish_scatter(true); check(source.paint_regions.size()==1,"Canceling scatter painting restores its previous mask")
	session._undo.clear(); session._redo.clear()
	print("ENVIRONMENT SCATTER count=",a.count," attempts=",a.attempts," generate_ms=",a.milliseconds)
	print("ENVIRONMENT SCATTER: %d checks, %d failures"%[checks,failures]); quit(failures)
