extends SceneTree
var checks := 0
var failures := 0
var renderer: KiwiTransformationRenderer
var session: KiwiTransformationSession
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func frame(at: float) -> Image:
	renderer.sync(session,at)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	return renderer.texture().get_image()
func prepare(at: float) -> void:
	renderer.sync(session,at)
	for i in 240:
		await process_frame
		if renderer.cache.worker==null and renderer.cache.requests.is_empty() and renderer.cache.analysis_count>0: break
	renderer.sync(session,at)
func run() -> void:
	renderer=KiwiTransformationRenderer.new(); root.add_child(renderer); await process_frame
	session=KiwiTransformationSession.new(); session.document=KiwiTransformationExamples.create("Blinking eye"); var item := session.document.components[0]
	await prepare(.85); var morph := await frame(.85)
	check(morph.get_used_rect().has_area(),"GPU morph produces visible transparent artwork")
	item.keys[1].mode="Crossfade"; var dissolve := await frame(.85)
	check(morph.get_data()!=dissolve.get_data(),"Real rendered mesh deformation is visually different from crossfade")
	var open := await frame(0.); check(open.get_pixel(320,200).a>.9,"Multicolored artwork retains its opaque interior")
	item.keys[1].mode="Step"; var step := await frame(.85)
	check(step.get_data()==open.get_data(),"Step mode holds exact previous artwork instead of blending")
	item.visible=false; var hidden := await frame(.85); check(not hidden.get_used_rect().has_area(),"Hidden components are excluded from the transparent composite"); item.visible=true
	session.document=KiwiTransformationExamples.create("Bleeding cut"); var blood := session.document.components[1]
	for component in session.document.components: component.visible=component==blood
	await prepare(.12); var blank := await frame(0.); var growing := await frame(.12); var full := await frame(.7)
	check(not blank.get_used_rect().has_area() and growing.get_used_rect().has_area(),"Empty artwork grows from its configured origin instead of appearing fully formed")
	check(growing.get_used_rect().size.x<full.get_used_rect().size.x or growing.get_used_rect().size.y<full.get_used_rect().size.y,"Growth changes the visible footprint, not merely overall opacity")
	await prepare(.701); var first := await frame(.7)
	check(first.get_data()==full.get_data(),"A nonempty Reveal begins with the complete outgoing drawing")
	var path := await frame(1.2); check(path.get_used_rect().has_area() and path.get_data()!=first.get_data(),"Artist reveal path changes the rendered result over time")
	var end := await frame(1.7); check(end.get_used_rect().has_area(),"Path reveal reaches complete target artwork")
	check(renderer.cache.entries.size()<=24 and renderer.cache.requests.size()<=8,"Morph preparation and cache queues stay bounded")
	renderer.queue_free(); for i in 5: await process_frame
	print("TRANSFORMATION_RENDER checks=%d failures=%d"%[checks,failures]); quit(failures)
