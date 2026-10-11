extends SceneTree
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func run() -> void:
	var engine:=KiwiPixelSelectionEngine.new(); root.add_child(engine)
	var image:=Image.create(1920,1080,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	image.fill_rect(Rect2i(400,220,1000,640),Color.BLACK); image.fill_rect(Rect2i(410,230,980,620),Color.BLUE)
	image.fill_rect(Rect2i(700,230,100,620),Color.RED)
	var result: Array=[]; engine.proposed.connect(func(mask: Image,kind: String,id: int): result.append([mask,kind,id]))
	var started:=Time.get_ticks_msec(); var frames:=0
	engine.prepare(image,Rect2i(Vector2i.ZERO,image.get_size()))
	# Request before analysis starts: it must be queued, never erase analysis.
	engine.request("object",Vector2(500,400),.1)
	var latest:=engine.request("object",Vector2(500,400),.5)
	while result.is_empty() and Time.get_ticks_msec()-started<20000:
		await process_frame; frames+=1
	check(not result.is_empty(),"1920×1080 object selection completes asynchronously")
	if not result.is_empty():
		check(result[0][2]==latest and result.size()==1,"Only the newest queued request is delivered")
		check(result[0][0]!=null and result[0][0].get_pixel(750,400).a>.5,"Large-image selection includes multicolored foreground")
	check(frames>5,"Main-thread processing continues during source analysis")
	var analyzed:=engine.edges; var cached:=engine.objects
	result.clear(); started=Time.get_ticks_msec()
	engine.request("object",Vector2(500,400),.4)
	while result.is_empty() and Time.get_ticks_msec()-started<10000: await process_frame
	check(engine.edges==analyzed and engine.objects==cached,"Threshold adjustments reuse edge and region caches")
	print("Cached 1080p proposal: %d ms" % (Time.get_ticks_msec()-started))
	result.clear(); engine.request("object",Vector2(500,400),.5); engine.invalidate()
	for i in 10: await process_frame
	check(result.is_empty(),"Changing the source prevents stale worker results from being delivered")
	engine.free(); print("Pixel selection worker checks: %d failures" % failures); quit(failures)
