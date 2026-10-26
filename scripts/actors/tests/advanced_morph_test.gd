extends SceneTree
var checks := 0
var failures := 0
var renderer: KiwiTransformationRenderer
var session := KiwiTransformationSession.new()
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
static func drawing(kind: String) -> Image:
	var image := Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var uv := (Vector2(x,y)+Vector2.ONE*.5)/128.; var color := Color(0,0,0,0)
			var center := Vector2(.35,.5) if kind=="a" else Vector2(.65,.5)
			var q := (uv-center)/Vector2(.25,.31 if kind=="a" else .4); var radius := q.length()
			if kind in ["solid","hole","split"]:
				center=Vector2(.5,.5); radius=(uv-center).length()/.36
				if kind=="split": radius=minf(uv.distance_to(Vector2(.25,.5)),uv.distance_to(Vector2(.75,.5)))/.19
			if radius<1.:
				color=Color("172334") if radius>.9 else Color("e26367")
				if kind in ["a","b"]:
					var feature := Vector2(.31,.45) if kind=="a" else Vector2(.60,.35)
					if uv.distance_to(feature)<.06: color=Color("3297ef")
					if uv.distance_to(feature+Vector2(-.015,-.02))<.017: color=Color.WHITE
			if kind=="hole" and uv.distance_to(center)<.17: color=Color(0,0,0,0)
			if kind=="irregular":
				var polygon := PackedVector2Array([Vector2(.08,.45),Vector2(.2,.15),Vector2(.53,.26),Vector2(.94,.09),Vector2(.8,.5),Vector2(.94,.85),Vector2(.4,.72),Vector2(.16,.85)])
				color=Color("e26367") if Geometry2D.is_point_in_polygon(uv,polygon) else Color(0,0,0,0)
			image.set_pixel(x,y,color)
	return image
func pair(a: Image,b: Image) -> KiwiTransformationComponent:
	renderer.clear_views(); var document := KiwiTransformationImage2D.blank(Vector2i(128,128)); document.duration=1.; var item := document.components[0]
	item.states[0].artwork.texture=ImageTexture.create_from_image(a); var target := item.states[0].copy_state(true); target.title="Target"; target.artwork.texture=ImageTexture.create_from_image(b); item.states.append(target)
	KiwiTransformationExamples.key(item,0,item.states[0],"Auto Morph"); KiwiTransformationExamples.key(item,1,target,"Auto Morph"); session.document=document; return item
func prepare(at: float=.5) -> void:
	renderer.sync(session,at); var start := Time.get_ticks_msec()
	while (renderer.cache.worker!=null or not renderer.cache.requests.is_empty()) and Time.get_ticks_msec()-start<15000: await process_frame
	renderer.sync(session,at)
func frame(at: float) -> Image:
	renderer.sync(session,at); for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	return renderer.texture().get_image()
static func centroid(image: Image) -> Vector2:
	var sum := Vector2.ZERO; var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			if c.a>.8 and c.b>.45 and c.b>c.r*1.5 and c.b>c.g*1.15: sum+=Vector2(x+.5,y+.5); count+=1
	return sum/maxi(1,count)
static func white_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			if color.a>.9 and minf(color.r,minf(color.g,color.b))>.8: count+=1
	return count
func run() -> void:
	renderer=KiwiTransformationRenderer.new(); root.add_child(renderer); await process_frame
	var a := drawing("a"); var b := drawing("b"); var original_a := a.get_data(); var item := pair(a,b); await prepare()
	var prepared: Dictionary=renderer.views[item.id].prepared
	print("MESH method=",prepared.method," vertices=",prepared.uv_a.size()," landmarks=",prepared.get("landmarks",[]).size()," prepare_ms=",prepared.analysis_us/1000.)
	check(prepared.valid and not prepared.topology and prepared.uv_a!=prepared.uv_b,"Multicolor drawings use a genuine paired contour mesh, not implicit dissolve")
	check(prepared.get("landmarks",[]).size()>0,"Distinctive internal color regions create automatic correspondence landmarks")
	check(KiwiMorphDeformation.validate(prepared.uv_a,prepared.uv_b,prepared.indices).valid,"All deformation triangles remain positive throughout the entire interpolation")
	var middle := await frame(.5); var expected := centroid(a).lerp(centroid(b),.5)
	check(centroid(middle).distance_to(expected)<7.,"The blue marking follows its matched geometric path to the intermediate location")
	check(middle.get_pixelv(Vector2i(expected)).a>.9,"Warped interior markings remain opaque rather than ghosting through the background")
	item.keys[0].mode="Crossfade"; var dissolve := await frame(.5); check(dissolve.get_data()!=middle.get_data(),"Geometric morph pixels differ from direct stationary crossfade")
	check(a.get_data()==original_a,"Preparation and playback never alter the source raster")
	item.keys[0].mode="Auto Morph"; var repeat := await frame(.5); check(repeat.get_data()==middle.get_data(),"Repeated scrubbing produces deterministic identical pixels")
	var first := await frame(0.); var final := await frame(1.)
	check(centroid(first).distance_to(centroid(a))<1. and centroid(final).distance_to(centroid(b))<1.,"Both exact endpoint drawings retain the original color landmark positions")
	var counts := renderer.cache.field_analysis_count; item.keys[0].points_a=PackedVector2Array([Vector2(.31,.45)]); item.keys[0].points_b=PackedVector2Array([Vector2(.61,.35)]); await prepare()
	check(renderer.cache.field_analysis_count==counts,"Editing corrections reuses image analysis and distance fields instead of rebuilding them")
	item=pair(a,b); session.document.canvas_size=Vector2i(256,256); var pose_a := item.states[0]; var pose_b := item.states[1]
	pose_a.artwork.position=Vector2(5,8); pose_a.artwork.dimensions=Vector2(100,90); pose_a.artwork.rotation=-.2; pose_a.pivot=Vector2(.2,.8)
	pose_b.artwork.position=Vector2(60,50); pose_b.artwork.dimensions=Vector2(140,70); pose_b.artwork.rotation=.7; pose_b.pivot=Vector2(.65,.25)
	await prepare(); var transformed := await frame(.5); var settings := KiwiTransformationRenderer.transform_at(pose_a,pose_b,.5)
	var pivot := pose_a.pivot.lerp(pose_b.pivot,.5); var actual: Vector2=renderer.views[item.id].node.transform*(settings.dimensions*pivot)
	check(actual.is_equal_approx(pose_a.anchor().lerp(pose_b.anchor(),.5)),"Position, rotation, scale and drawing morph share the exact interpolated pivot")
	var expected_mark: Vector2=settings.transform*(settings.dimensions*Vector2(.455,.4))
	check(centroid(transformed).distance_to(expected_mark)<8.,"The warped color landmark follows the simultaneous world transform without cropping-induced jumps · %s / %s"%[centroid(transformed),expected_mark])
	item=pair(drawing("solid"),drawing("irregular")); await prepare(); var shaped := await frame(.5); item.keys[0].mode="Crossfade"; var overlay := await frame(.5)
	check(shaped.get_data()!=overlay.get_data(),"Circle-to-elongated concave artwork changes the actual intermediate silhouette")
	item=pair(drawing("solid"),drawing("hole")); await prepare(); prepared=renderer.views[item.id].prepared
	check(prepared.topology and prepared.holes_b==1,"An appearing interior hole chooses the topology-aware signed-distance method")
	var field: Image=prepared.field_b.get_image(); check(field.get_pixel(64,64).r<0 and field.get_pixel(64,30).r>0,"Signed distances distinguish the hole from occupied ring pixels")
	var ring := await frame(.9); check(ring.get_pixel(64,64).a<.1 and ring.get_pixel(64,30).a>.8,"The hole opens spatially while the surrounding colored shape remains solid")
	var occupied := await frame(.5); item.keys[0].topology_bias=-.1; var biased := await frame(.5)
	check(occupied.get_pixel(64,64).a>.8 and biased.get_pixel(64,64).a<.2,"Topology expansion bias controls when an interior opening appears")
	item=pair(drawing("solid"),drawing("split")); item.keys[0].alignment="Local"; await prepare(); var split := await frame(.9)
	check(split.get_pixel(64,64).a<.1 and split.get_pixel(32,64).a>.9 and split.get_pixel(96,64).a>.9,"One connected shape separates into two visible islands without losing either region")
	var split_repeat := await frame(.2); split_repeat=await frame(.9); check(split_repeat.get_data()==split.get_data(),"Topology changes scrub backward and forward without simulation state")
	var empty := Image.create(128,128,false,Image.FORMAT_RGBA8); empty.fill(Color(0,0,0,0))
	item=pair(empty,drawing("solid")); item.keys[0].mode="Grow / Reveal"; item.keys[0].reveal_mode="Directional"; item.keys[0].direction=90; await prepare(.5); var growing := await frame(.5)
	check(growing.get_pixel(64,40).a>.8 and growing.get_pixel(64,90).a<.1,"Directional growth reveals the shape in the chosen direction rather than fading it")
	item.keys[0].reveal_mode="Shape expansion"; var expansion := await frame(.4); var full := await frame(1.)
	check(expansion.get_used_rect().size.x<full.get_used_rect().size.x and expansion.get_pixel(64,64).a>.9,"Shape expansion grows opaque artwork geometrically from the origin: %s / %s alpha %.3f"%[expansion.get_used_rect(),full.get_used_rect(),expansion.get_pixel(64,64).a])
	var path := PackedVector2Array([Vector2(.15,.15),Vector2(.45,.2),Vector2(.4,.55),Vector2(.85,.85)]); var stream := Image.create(128,128,false,Image.FORMAT_RGBA8); stream.fill(Color(0,0,0,0))
	for y in 128:
		for x in 128:
			var uv := (Vector2(x,y)+Vector2.ONE*.5)/128.
			for i in range(1,path.size()):
				if uv.distance_to(Geometry2D.get_closest_point_to_segment(uv,path[i-1],path[i]))<.035: stream.set_pixel(x,y,Color("d93853")); break
	item=pair(empty,stream); item.keys[0].mode="Grow / Reveal"; item.keys[0].reveal_mode="Path"; item.keys[0].reveal_path=path; await prepare(); var early := await frame(.3); var late := await frame(.95)
	check(early.get_pixel(20,20).a>.8 and early.get_pixel(108,108).a<.1 and late.get_pixel(108,108).a>.8,"A bent blood stream grows along the ordered artist path from beginning to end")
	var dirty := drawing("solid")
	for y in 128:
		for x in 128:
			if dirty.get_pixel(x,y).a==0.: dirty.set_pixel(x,y,Color(0,1,0,0))
	item=pair(dirty,dirty); await prepare(); var filtered := await frame(.5); var fringe := false
	for y in 128:
		for x in 128:
			var color := filtered.get_pixel(x,y)
			if color.a>.01 and color.g>color.r+.03 and color.g>color.b+.03: fringe=true
	check(not fringe,"Premultiplied filtering prevents transparent green RGB contaminating visible shape edges")
	var doc := KiwiTransformationExamples.create("Talking mouth"); renderer.clear_views(); session.document=doc; await prepare(.3); var mouth := await frame(.3)
	var mouth_pair: Dictionary=renderer.views[doc.components[0].id].prepared
	check(mouth.get_used_rect().has_area() and mouth_pair.valid,"Closed/open mouth with new teeth and tongue produces a valid prepared transition · "+str([mouth_pair.get("empty_a"),mouth_pair.get("empty_b"),mouth_pair.get("method")]))
	var open_mouth := await frame(.6)
	check(white_pixels(mouth)>20 and white_pixels(mouth)<white_pixels(open_mouth),"New teeth appear as opaque interior detail in the opening mouth, not as a ghosted overlay")
	doc.components[0].keys[0].mode="Guided Morph"; var key := doc.components[0].keys[0]; key.points_a=PackedVector2Array([Vector2(.4,.5)]); key.points_b=PackedVector2Array([Vector2(.38,.5)]); key.origin_enabled=true; key.morph_origin=Vector2(.3,.6); key.preservation=.6; key.quality="High"; key.reveal_mode="Directional"; key.direction=-90; key.topology_bias=.02; await prepare(.3); var before := await frame(.3)
	check(ResourceSaver.save(doc,"user://Advanced Morph.tres")==OK,"Advanced morph parameters save in the existing native asset format")
	var reloaded := ResourceLoader.load("user://Advanced Morph.tres","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTransformationImage2D; renderer.clear_views(); session.document=reloaded; await prepare(.3); var after := await frame(.3)
	check(before.get_data()==after.get_data() and reloaded.validate().is_empty(),"Reloaded manual corrections and advanced morph settings reconstruct identical pixels")
	var invalid := KiwiTransformationMorph.prepare(a,b,PackedVector2Array([Vector2(.3,.3),Vector2(.3,.3)]),PackedVector2Array([Vector2(.4,.4),Vector2(.6,.6)]))
	check(not invalid.valid and invalid.reason.contains("Conflicting"),"Contradictory correction pairs are diagnosed rather than silently discarded")
	# Warm eight simultaneous independently timed components, then measure only
	# playback submission and real rendered frame intervals, not preparation.
	renderer.clear_views(); session.document=KiwiTransformationExamples.create("Blinking eye"); session.document.canvas_size=Vector2i(640,400)
	for i in 7:
		var copy := session.document.components[0].copy_component(true); copy.states[0].artwork.position=Vector2((i%4)*145,(i/4)*180); copy.states[1].artwork.position=copy.states[0].artwork.position; copy.states[0].artwork.dimensions=Vector2(140,110); copy.states[1].artwork.dimensions=Vector2(140,110); session.document.components.append(copy)
	await prepare(.85); var open_eye := await frame(.75); var blinking := await frame(.875)
	check(blinking.get_used_rect().size.y<open_eye.get_used_rect().size.y,"Blinking eyes narrow their silhouettes instead of just reducing opacity")
	var analyses := renderer.cache.analysis_count; var started := Time.get_ticks_usec()
	for i in 120: renderer.sync(session,.80+float(i%20)*.002)
	var cpu_us := (Time.get_ticks_usec()-started)/120.; var intervals: Array[float]=[]
	for i in 30:
		var now := Time.get_ticks_usec(); renderer.sync(session,.85); await RenderingServer.frame_post_draw; intervals.append(float(Time.get_ticks_usec()-now)/1000.)
	intervals.sort(); print("MORPH_BENCH components=8 canvas=640x400 sync_cpu_ms=",cpu_us/1000.," median_rendered_interval_ms=",intervals[15]," analyses_before=",analyses," analyses_after=",renderer.cache.analysis_count," preparation_total_ms=",renderer.cache.preparation_usec/1000.," field_analyses=",renderer.cache.field_analysis_count)
	check(renderer.cache.analysis_count==analyses,"Eight-component playback never reruns correspondence after warmup")
	renderer.queue_free(); for i in 5: await process_frame
	print("ADVANCED_MORPH checks=%d failures=%d"%[checks,failures]); quit(failures)
