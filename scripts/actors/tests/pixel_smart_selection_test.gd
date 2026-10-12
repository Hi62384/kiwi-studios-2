extends SceneTree
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; push_error(message)
func run() -> void:
	var image:=Image.create(128,96,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	image.fill_rect(Rect2i(20,20,60,56),Color.BLACK); image.fill_rect(Rect2i(24,24,52,48),Color.BLUE)
	image.fill_rect(Rect2i(36,24,10,48),Color.RED); image.fill_rect(Rect2i(53,36,10,12),Color.WHITE)
	image.fill_rect(Rect2i(100,20,8,56),Color.BLACK)
	var field:=KiwiPixelEdgeField.new(); field.build(image,Rect2i(Vector2i.ZERO,image.get_size()))
	var magnet:=KiwiPixelEdgeMagnet.new(); magnet.field=field
	var start:=magnet.follow(Vector2(17,35),.4,Vector2.DOWN)
	var next:=magnet.follow(Vector2(17,55),.4,Vector2.DOWN)
	check(not start.is_empty() and not next.is_empty(),"Brush follows a nearby continuous edge")
	var reacquired:=magnet.follow(Vector2(98,55),.4,Vector2.RIGHT)
	check(reacquired.size()==1 and reacquired[0].distance_to(Vector2(98,55))<16,"Brush immediately reacquires a disconnected edge without drawing across the gap")
	check(not magnet.follow(Vector2(98,58),.4,Vector2.DOWN).is_empty(),"Brush reacquires after losing a contour instead of staying stuck until release")
	var parallel:=Image.create(64,128,false,Image.FORMAT_RGBA8); parallel.fill(Color.WHITE)
	parallel.fill_rect(Rect2i(20,0,3,128),Color.BLACK); parallel.fill_rect(Rect2i(32,0,3,128),Color.BLACK)
	var parallel_field:=KiwiPixelEdgeField.new(); parallel_field.build(parallel,Rect2i(0,0,64,128))
	var responsive:=KiwiPixelEdgeMagnet.new(); responsive.field=parallel_field
	responsive.follow(Vector2(19,30),.4,Vector2.DOWN)
	var switched:=responsive.follow(Vector2(31,31),.4,Vector2.DOWN)
	check(switched.size()==1 and switched[0].x>29,"A nearby reachable old edge cannot pin the brush when the cursor moves to another contour")
	var worst_usec:=0
	for sample in 80:
		var cursor:=Vector2(19 if sample%2==0 else 31,32+sample)
		var began:=Time.get_ticks_usec()
		var tracked:=responsive.follow(cursor,.4,Vector2.DOWN)
		worst_usec=maxi(worst_usec,Time.get_ticks_usec()-began)
		check(not tracked.is_empty() and absf(tracked[-1].x-cursor.x)<3,"Repeated contour changes stay with the current cursor")
	check(worst_usec<50000,"Magnetic tracking does not accumulate slow input events")
	print("Worst contour-switch tracking sample: %d us" % worst_usec)
	check(field.nearest(Vector2(5,90),.4)<0,"No arbitrary magnetic paint when there is no edge")
	var circle:=Image.create(64,64,false,Image.FORMAT_RGBA8); circle.fill(Color.WHITE)
	for y in 64:
		for x in 64:
			var radius:=Vector2(x+.5-32,y+.5-32).length()
			if radius<22: circle.set_pixel(x,y,Color.BLACK if radius>17 else Color.BLUE)
	var curved:=KiwiPixelEdgeField.new(); curved.build(circle,Rect2i(0,0,64,64))
	var curve_magnet:=KiwiPixelEdgeMagnet.new(); curve_magnet.field=curved
	for i in 16:
		var angle:=PI+i/15.0*PI*.5
		var snapped:=curve_magnet.follow(Vector2(32,32)+Vector2(cos(angle),sin(angle))*25,.4,Vector2(-sin(angle),cos(angle)))
		check(not snapped.is_empty(),"Magnetic brush remains continuous around a curved outline")
	var contour:=curve_magnet.connected(Vector2(9,32),.4)
	check(contour.size()>90,"Magnetic bucket follows a complete curved boundary")
	var thin:=Image.create(128,96,false,Image.FORMAT_RGBA8); var thick:=thin.duplicate()
	var edge:=magnet.connected(Vector2(19,35),.4)
	KiwiPixelEdgeMagnet.paint_band(thin,edge,2,field.domain,Color.WHITE,false)
	KiwiPixelEdgeMagnet.paint_band(thick,edge,10,field.domain,Color.WHITE,false)
	check(thin.get_used_rect().has_area() and thick.get_used_rect().get_area()>thin.get_used_rect().get_area(),"Bucket edge thickness follows brush size")
	check(thick.get_pixel(50,50).a==0 and thick.get_pixel(104,50).a==0,"Edge bucket does not fill the interior or select disconnected objects")
	var weak:=Image.create(32,32,false,Image.FORMAT_RGBA8); weak.fill(Color(.3,.3,.3)); weak.fill_rect(Rect2i(16,0,16,32),Color(.45,.45,.45))
	var weak_field:=KiwiPixelEdgeField.new(); weak_field.build(weak,Rect2i(0,0,32,32))
	check(weak_field.nearest(Vector2(16,16),.05)>=0 and weak_field.nearest(Vector2(16,16),.9)<0,"Edge threshold accepts weak boundaries only at low settings")
	var objects:=KiwiPixelObjectSegmenter.new(); objects.build(image,field.domain)
	var low:=objects.propose(Vector2(29,40),.1); var medium:=objects.propose(Vector2(29,40),.5)
	check(medium!=null,"Object selector finds an outlined multicolored object")
	if medium!=null:
		check(medium.get_pixel(40,40).a>.5 and medium.get_pixel(58,40).a>.5,"Object selection includes red stripes and white highlights from a blue seed")
		check(medium.get_pixel(5,40).a==0 and medium.get_pixel(104,40).a==0,"Object selection excludes background and unrelated objects")
		check(low!=null and low.get_pixel(40,40).a<medium.get_pixel(40,40).a,"Object threshold changes inclusiveness using the original seed")
	var transparent:=Image.create(64,64,false,Image.FORMAT_RGBA8); transparent.fill_rect(Rect2i(10,10,40,40),Color.RED)
	var alpha_objects:=KiwiPixelObjectSegmenter.new(); alpha_objects.build(transparent,Rect2i(0,0,64,64))
	var alpha_mask:=alpha_objects.propose(Vector2(20,20),.5)
	check(alpha_mask!=null and alpha_mask.get_pixel(20,20).a>.5 and alpha_mask.get_pixel(5,5).a==0,"Transparent artwork is separated using alpha boundaries")
	# Soft boundary against a textured, similarly colored background. The old
	# absolute threshold flood selected almost the entire canvas here.
	var subtle:=Image.create(128,96,false,Image.FORMAT_RGBA8)
	for y in 96:
		for x in 128:
			var value:=.72+sin(x*.2)*.018+cos(y*.3)*.012
			subtle.set_pixel(x,y,Color(value,value,value))
	subtle.fill_rect(Rect2i(25,20,42,52),Color(.57,.58,.6))
	subtle.fill_rect(Rect2i(94,25,20,35),Color(.57,.58,.6))
	var subtle_objects:=KiwiPixelObjectSegmenter.new(); subtle_objects.build(subtle,Rect2i(0,0,128,96))
	for threshold in [.25,.5,1.0]:
		var proposal:=subtle_objects.propose(Vector2(40,40),threshold)
		check(proposal!=null,"Soft object boundary produces a usable selection")
		if proposal!=null:
			check(proposal.get_pixel(50,50).a>.5 and proposal.get_pixel(80,40).a==0 and proposal.get_pixel(100,40).a==0,"Background competition excludes texture and disconnected lookalikes even at maximum threshold")
	var subtle_edges:=KiwiPixelEdgeField.new(); subtle_edges.build(subtle,Rect2i(0,0,128,96))
	check(subtle_edges.nearest(Vector2(24,40),.4)>=0,"Default edge sensitivity detects soft object boundaries")
	check(subtle_edges.nearest(Vector2(5,45),.4)<0,"Smooth background texture is not a magnetic boundary")
	var cropped_subject:=Image.create(80,80,false,Image.FORMAT_RGBA8); cropped_subject.fill(Color.WHITE)
	cropped_subject.fill_rect(Rect2i(0,15,40,50),Color.RED)
	var cropped_objects:=KiwiPixelObjectSegmenter.new(); cropped_objects.build(cropped_subject,Rect2i(0,0,80,80))
	var cropped_mask:=cropped_objects.propose(Vector2(20,35),.5)
	check(cropped_mask!=null and cropped_mask.get_pixel(1,40).a>.5 and cropped_mask.get_pixel(60,40).a==0,"Subjects touching the image border are not mistaken for background")
	var ramp:=Image.create(96,80,false,Image.FORMAT_RGBA8); ramp.fill(Color.WHITE)
	for y in range(12,68):
		for x in range(12,84):
			var value:=.2+.35*pow(float(x-12)/72,2)
			ramp.set_pixel(x,y,Color(value,value,value))
	var ramp_objects:=KiwiPixelObjectSegmenter.new(); ramp_objects.build(ramp,Rect2i(0,0,96,80))
	var tight:=ramp_objects.propose(Vector2(20,35),.05); var loose:=ramp_objects.propose(Vector2(20,35),.9)
	check(tight!=null and loose!=null and tight.get_used_rect().size.x<loose.get_used_rect().size.x,"Threshold visibly changes extent on a low-contrast shaded subject")
	var ring:=Image.create(128,128,false,Image.FORMAT_RGBA8); ring.fill(Color.WHITE)
	ring.fill_rect(Rect2i(12,12,104,104),Color.RED); ring.fill_rect(Rect2i(18,18,92,92),Color.WHITE)
	var ring_objects:=KiwiPixelObjectSegmenter.new(); ring_objects.build(ring,Rect2i(0,0,128,128))
	var ring_mask:=ring_objects.propose(Vector2(14,60),.8)
	check(ring_mask!=null and ring_mask.get_pixel(14,60).a>.5 and ring_mask.get_pixel(60,60).a==0,"An enclosing shape does not automatically select the large background inside it")
	var branches:=Image.create(80,80,false,Image.FORMAT_RGBA8); branches.fill(Color.WHITE)
	branches.fill_rect(Rect2i(38,8,4,64),Color.BLACK); branches.fill_rect(Rect2i(10,38,60,4),Color.BLACK)
	var branch_field:=KiwiPixelEdgeField.new(); branch_field.build(branches,Rect2i(0,0,80,80))
	var branch_magnet:=KiwiPixelEdgeMagnet.new(); branch_magnet.field=branch_field
	var branch_mask:=Image.create(80,80,false,Image.FORMAT_RGBA8)
	KiwiPixelEdgeMagnet.paint_band(branch_mask,branch_magnet.connected(Vector2(37,15),.4),3,Rect2i(0,0,80,80),Color.WHITE,false)
	check(branch_mask.get_pixel(10,39).a>.5 and branch_mask.get_pixel(69,39).a>.5 and branch_mask.get_pixel(39,71).a>.5,"Edge bucket reaches all arms of a branched outline")
	var large_mask:=Image.create(2048,2048,false,Image.FORMAT_RGBA8)
	var dense_path:=PackedVector2Array()
	for i in 200: dense_path.append(Vector2(800+i,900+sin(i*.02)*20))
	var paint_started:=Time.get_ticks_usec()
	KiwiPixelEdgeMagnet.paint_band(large_mask,dense_path,500,Rect2i(0,0,2048,2048),Color.WHITE)
	var paint_usec:=Time.get_ticks_usec()-paint_started
	check(paint_usec<100000,"A maximum-size brush does not stamp hundreds of redundant circles along a short edge")
	check(large_mask.get_pixel(800,900).a>.5 and large_mask.get_pixel(999,900).a>.5,"Spaced stamps preserve both ends of the edge stroke")
	print("500px edge brush on a 2048px mask: %d us" % paint_usec)
	print("Smart pixel selection checks: %d failures" % failures); quit(failures)
