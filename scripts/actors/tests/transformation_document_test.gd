extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var session := KiwiTransformationSession.new(); var item := session.document.components[0]; session.selected.assign([item.id])
	check(session.document.validate().is_empty() and item.states.size()==1,"New document starts with a valid empty drawing component")
	var original := session.active_state(); var original_pixels := original.artwork.texture.get_image().get_data(); var variant := session.add_state(); variant.title="Open"
	var image := KiwiTransformationExamples.image("mouth"); session.action("Paint state",func(): variant.artwork.texture=ImageTexture.create_from_image(image); variant.revision+=1)
	check(original.artwork.texture.get_image().get_data()==original_pixels and variant.artwork.texture!=original.artwork.texture,"Painting a duplicated state never changes the source drawing")
	session.undo(); check(session.active_state().artwork.texture.get_image().get_data()==original_pixels,"Artwork editing undo restores exact pixels")
	session.redo(); check(session.active_state().artwork.texture.get_image().get_data()!=original_pixels,"Artwork editing redo restores its independent drawing")
	item=session.primary(); original=item.states[0]; variant=session.active_state(); session.playhead=0; session.insert_key(); var first := item.keys[0]
	session.edit_states[item.id]=original.id; session.playhead=2.; session.insert_key(); var id := first.state_id
	session.action("Rename state",func(): variant.title="Wide open")
	check(first.state_id==id and session.document.validate().is_empty(),"Renaming a state never breaks stable keyframe references")
	var sample := session.sampled(item,1.); check(sample.a.id==variant.id and sample.b.id==original.id and is_equal_approx(sample.t,.5),"State track evaluates a reusable outgoing transition")
	first.mode="Linear morph"; var linear := float(session.sampled(item,.5).t); first.mode="Smooth morph"
	check(not is_equal_approx(session.sampled(item,.5).t,linear),"Smooth and linear modes evaluate different temporal interpolation")
	first.mode="Step"; first.curve=Curve.new(); first.curve.add_point(Vector2(0,.5)); first.curve.add_point(Vector2(1,1))
	check(is_zero_approx(session.sampled(item,1.).t),"Step holds the outgoing state even when a previous custom curve exists")
	first.mode="Smooth morph"; first.curve=null
	var other := session.add_component(); var other_default := other.states[0].id; session.selected.assign([item.id]); session.playhead=1.; session.insert_key()
	check(other.keys.is_empty() and other.default_state_id==other_default,"Component tracks and source states are independent")
	session.copy_components(); session.paste_components(); var copy := session.primary()
	check(copy.id!=item.id and copy.states[0].id!=item.states[0].id and copy.keys[0].state_id!=item.keys[0].state_id and session.document.validate().is_empty(),"Component paste remaps all component, state and key identities")
	session.undo(); session.redo(); check(session.document.validate().is_empty(),"Component paste supports undo and redo")
	var a := KiwiTransformationState.new(); a.id=ActorData.new_id(); a.artwork=KiwiImageLayer.create("basic",Vector2i(160,120)); a.artwork.rotation=deg_to_rad(170); var b := a.copy_state(true); b.artwork.rotation=deg_to_rad(-170)
	var transform := KiwiTransformationRenderer.transform_at(a,b,.5)
	check(absf(absf((transform.transform as Transform2D).get_rotation())-PI)<.001,"Rotation interpolates through the shortest angular path")
	check(KiwiTransformationRenderer.transform_at(a,b,.5,1).transform!=transform.transform,"Outgoing keys can request explicit extra full turns")
	a.pivot=Vector2(.2,.8); var pivot := a.anchor(); a.pivot=Vector2(.8,.2); check(a.artwork.position==Vector2.ZERO and pivot!=a.anchor(),"Changing the pivot does not move the artwork")
	a.artwork.properties.basis_x=Vector2(1.2,.1); a.artwork.properties.basis_y=Vector2(.2,.8); a.artwork.properties.flip_x=true
	check(KiwiTransformationRenderer.transform_at(a,a,0.).transform.is_equal_approx(a.artwork.local_transform()),"Animation preserves affine transforms and flips produced by group resizing")
	check(KiwiTransformationRenderer.transform_at(b,a,1.).transform.is_equal_approx(a.artwork.local_transform()),"Animated transform reaches the exact edited target state without a visual jump")
	var prepared := KiwiTransformationMorph.prepare(KiwiTransformationExamples.image("eye",.2),KiwiTransformationExamples.image("eye",1.))
	check(prepared.valid,"Compatible eye silhouettes prepare a genuine deformation mesh")
	check(prepared.uv_a!=prepared.uv_b and prepared.indices.size()>6,"Morphing contains a cached non-identity warp, not only crossfade")
	var empty := Image.create(160,120,false,Image.FORMAT_RGBA8); empty.fill(Color(0,0,0,0)); var reveal := KiwiTransformationMorph.prepare(empty,image)
	check(reveal.empty_a and not reveal.empty_b,"Empty states are classified for genuine growth/reveal")
	var complex := empty.duplicate() as Image; complex.fill_rect(Rect2i(10,10,20,20),Color.RED); complex.fill_rect(Rect2i(90,70,20,20),Color.BLUE)
	check(KiwiTransformationMorph.prepare(complex,image).get("topology",false),"Disconnected drawings choose the signed-distance topology method")
	var pa := PackedVector2Array([Vector2(.3,.3),Vector2(.7,.7)]); var pb := PackedVector2Array([Vector2(.2,.4),Vector2(.8,.6)])
	check(KiwiTransformationMorph.mapped(pa[0],pa,pb).is_equal_approx(pb[0]),"Artist correspondence points are exact mapping constraints")
	for title: String in KiwiTransformationExamples.NAMES:
		var document := KiwiTransformationExamples.create(title); check(document.validate().is_empty(),"Valid worked example: "+title)
		var file := "user://Transformation "+title+".tres"; check(ResourceSaver.save(document,file)==OK,"Native editable example saves: "+title)
		var reloaded := ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTransformationImage2D
		check(reloaded!=null and reloaded.validate().is_empty() and reloaded.components.size()==document.components.size(),"Example reload preserves components, states and animation: "+title)
		for i in document.components.size():
			var exact := reloaded.components[i].states.size()==document.components[i].states.size()
			for j in document.components[i].states.size(): exact=exact and reloaded.components[i].states[j].artwork.texture.get_image().get_data()==document.components[i].states[j].artwork.texture.get_image().get_data()
			check(exact,"Reload preserves every state's exact multicolored pixels: "+document.components[i].title)
	var controls := KiwiTransformationExamples.create("Talking mouth"); var frame := controls.components[0].keys[0]; frame.curve=ActorValueCurve.preset("Smoothstep"); frame.points_a=pa; frame.points_b=pb; frame.reveal_path=PackedVector2Array([Vector2(.2,.2),Vector2(.7,.8)]); frame.reveal_width=.15; frame.turns=2
	controls.components[0].locked=true; controls.components[0].states[2].pivot=Vector2(.2,.8)
	check(ResourceSaver.save(controls,"user://Transformation Controls.res")==OK,"Native save preserves custom transition controls")
	var loaded := ResourceLoader.load("user://Transformation Controls.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTransformationImage2D; var loaded_key := loaded.components[0].keys[0]
	check(loaded_key.points_a==pa and loaded_key.points_b==pb and loaded_key.reveal_path==frame.reveal_path and loaded_key.turns==2 and is_equal_approx(loaded_key.reveal_width,.15) and loaded_key.curve!=null,"Correspondence pairs, reveal paths, width, turns and timing curves survive reload")
	check(loaded.components[0].locked and loaded.components[0].states[2].pivot==Vector2(.2,.8),"Component locks and per-state pivots survive reload")
	var bad := session.document.snapshot(); bad.components[0].keys[0].state_id="missing"
	check(not bad.validate().is_empty(),"Corrupt state references are reported, not silently discarded")
	print("TRANSFORMATION_DOCUMENT checks=%d failures=%d"%[checks,failures]); quit(failures)
