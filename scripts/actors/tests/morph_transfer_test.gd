extends SceneTree
var checks := 0
var failures := 0
var workspace: KiwiTransformationWorkspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle() -> void:
	for i in 7: await process_frame
func frame(at: float) -> Image:
	workspace.seek(at); await settle(); await RenderingServer.frame_post_draw
	return workspace.animation_renderer.texture().get_image()
func run() -> void:
	root.size=Vector2i(1440,960); root.gui_embed_subwindows=true; workspace=KiwiTransformationWorkspace.new(); root.add_child(workspace); await settle()
	var document := KiwiTransformationImage2D.blank(Vector2i(128,128)); var item := document.components[0]; var image := Image.create(128,128,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0)); image.fill_rect(Rect2i(20,25,80,70),Color(.8,.2,.4,.7)); item.states[0].artwork.texture=ImageTexture.create_from_image(image); item.states[0].artwork.opacity=.7
	workspace.open_source(document); var session := workspace.session; var source_id := session.primary().id; var original := session.active_state().artwork.texture.get_image().get_data(); var before := await frame(.4)
	var mask := Image.create(128,128,false,Image.FORMAT_RGBA8); mask.fill(Color(0,0,0,0)); mask.fill_rect(Rect2i(60,0,68,128),Color(1,1,1,.5)); session.playhead=.5
	check(KiwiMorphComponentEvents.detach(session,mask).is_empty(),"Explicit detach creates a component transfer without changing the source state")
	check(session.document.component(source_id).states[0].artwork.texture.get_image().get_data()==original,"Region transfer preserves original source pixels, including alpha")
	var child_id := session.primary().id; var after := await frame(.5)
	var pixel_before := before.get_pixel(80,60); var pixel_after := after.get_pixel(80,60)
	check(absf(pixel_before.a-pixel_after.a)<.015 and absf(pixel_before.r-pixel_after.r)<.015,"Fractional masks preserve the composited appearance at separation, including actor opacity")
	check((await frame(.4)).get_data()==before.get_data(),"The detached component is absent before its exact timeline event")
	session.action("Animate detached component",func(): session.primary().states[0].artwork.position.x+=20); var moved := await frame(.6)
	check(moved.get_data()!=after.get_data(),"Detached region transforms independently after the event")
	session.undo(); await settle(); check((await frame(.6)).get_data()==after.get_data(),"Independent detached movement supports exact undo")
	check((await frame(.2)).get_data()==before.get_data() and (await frame(.6)).get_data()==after.get_data(),"Region visibility transfers scrub backward and forward deterministically")
	check(session.document.validate().is_empty(),"Timed split resources and references validate")
	var saved := "user://Morph Transfers.tres"; check(await workspace.save_to(saved)==OK,"Split masks and event times serialize with the native document")
	workspace.open_source(saved); session=workspace.session; check(session.document.component_events.size()==1 and (await frame(.6)).get_data()==after.get_data(),"Saved component transfers reconstruct identical rendered pixels")
	session.selected.assign([source_id,child_id]); session.playhead=.8; await workspace.merge_at_playhead(); await settle()
	check(session.document.component_events.size()==2 and session.document.component_events[1].kind=="Merge","Adjacent components can merge explicitly at the playhead")
	var merged := await frame(.8); check(absf(merged.get_pixel(80,60).a-after.get_pixel(80,60).a)<.015,"Merge preserves the source composite at the event boundary")
	check((await frame(.7)).get_data()==after.get_data(),"Merging leaves all earlier split animation intact")
	session.undo(); await settle(); check(session.document.component_events.size()==1 and session.document.components.size()==2,"One undo removes the entire merge, not the original drawings")
	session.redo(); await settle(); check(session.document.validate().is_empty(),"Redo restores a valid non-destructive merge event")
	var doc := session.document.snapshot(); var ids := PackedStringArray([source_id,child_id]); var result := KiwiMorphComponentEvents.merge(session,ids,merged,.1)
	check(not result.is_empty() or not session.document.validate().is_empty(),"A merge cannot silently create a transfer before its source component is born")
	if session.document.validate().size()>0: session.undo()
	var malformed := session.document.snapshot(); malformed.component_events=[{"id":"a","kind":"Split","time":0.,"sources":PackedStringArray([source_id]),"target":child_id,"mask":ImageTexture.create_from_image(mask)},{"id":"b","kind":"Split","time":0.,"sources":PackedStringArray([child_id]),"target":source_id,"mask":ImageTexture.create_from_image(mask)}]
	check("Cyclic component transfers are not valid." in malformed.validate(),"Cyclic visibility transfers are rejected before native data can render")
	workspace.queue_free(); await settle(); print("MORPH_TRANSFERS checks=%d failures=%d"%[checks,failures]); quit(failures)
