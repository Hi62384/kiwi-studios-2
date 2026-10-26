extends SceneTree
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
	print("PASS " if value else "FAIL ",label)
func settle()->void:
	for index in 12:await process_frame
func screenshot(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://.godot/verification/audio_layout");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"Layout screenshot saves: "+label)
func run()->void:
	root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
	var w:=KiwiAudioWorkspace.new();root.add_child(w);await settle()
	check(not w.bottom.visible and not w._layout.automation_panel.visible,"Editors and automation are closed on a fresh workspace")
	check(w._layout.empty_state.visible and not w._layout.clip_actions.visible,"Empty timeline gives a clear starting action instead of irrelevant clip tools")
	check(not w.library._filters.visible and not w.library._folders.visible,"Advanced library filters and folder indexing start collapsed")
	check(w.canvas.size.y>w.get_viewport_rect().size.y*.65,"The arrangement receives most of the empty workspace height")
	check(w._layout.inspector_view=="track","Empty workspace shows basic track controls, not every panel")
	check(not w.progress.visible and not w._layout.busy_button.visible,"Idle workspace hides job progress and cancellation clutter")
	await screenshot("empty_1440")
	root.size=Vector2i(960,720);await settle()
	check(w.get_global_rect().end.x<=w.get_viewport_rect().end.x+.1 and w.canvas.get_global_rect().end.x<=w.get_viewport_rect().end.x+.1,"Narrow layout keeps its timeline inside the window")
	await screenshot("empty_960")
	root.size=Vector2i(1440,900);await settle()
	var samples:=PackedVector2Array();samples.resize(48000)
	for index in samples.size():samples[index]=Vector2.ONE*.2*sin(TAU*220.*index/48000.)
	var clip:=w.session.insert_source(KiwiAudioSourceCache.to_wav(samples,48000),0,w.session.selected_track,"Voice take")
	w.session.select(clip.id);await settle()
	check(not w._layout.empty_state.visible and w._layout.clip_actions.visible,"Selected clips show only their relevant timeline actions")
	check(w._layout.inspector_view=="clip","Clip selection switches inspector to clip controls")
	w.inspector.get_child(0).get_child(1).pressed.emit();await settle()
	check(w._layout.inspector_view=="track","Inspector Track tab opens only track properties")
	w.inspector.get_child(0).get_child(2).pressed.emit();await settle()
	check(w._layout.inspector_view=="project","Inspector Project tab exposes project properties without mixing clip tools")
	w.inspector.get_child(0).get_child(0).pressed.emit();await settle()
	check(not bool(w._layout.folds.get("clip_timing",true)),"Detailed timing/playback controls start collapsed")
	await screenshot("clip_selected")
	w._layout.show_detail(0);await settle()
	check(w.bottom.visible and w.bottom.current_tab==0 and w.waveform.stream!=null,"Audio editor opens with the selected clip")
	await screenshot("audio_editor")
	w._layout.inspector_view="project";w._refresh_inspector();w._layout.automation_panel.show();w._layout.folds.clip_timing=true
	var state:=w.capture_state();var old_session:=w.session
	w.open_source(KiwiAudioDocument.from_source(null,"Other tab"));await settle()
	w.open_source(old_session.document,state);await settle()
	check(w.session==old_session and w.bottom.visible and w._layout.automation_panel.visible and w._layout.inspector_view=="project" and bool(w._layout.folds.clip_timing),"Editor, automation and inspector navigation restore independently per tab")
	w._layout.show_detail(4);await settle();check(w.bottom.current_tab==4,"Advanced mixer remains reachable through View")
	w._layout.toggle_automation();check(not w._layout.automation_panel.visible,"Read-mode automation can be collapsed")
	w._choose_automation_record_target({"owner_kind":"master","owner_id":"","effect_id":"","parameter":"volume_db"})
	check(w._layout.automation_panel.visible,"Choosing an automation target reveals its controls")
	var view:MenuButton=w._layout._menus.view
	view.get_popup().id_pressed.emit(0);check(not w.library.visible,"View menu can collapse the sounds library")
	view.get_popup().id_pressed.emit(0);check(w.library.visible,"View menu restores the sounds library")
	w.queue_free();await process_frame
	print("AUDIO_WORKSPACE_LAYOUT failures=",failures);quit(failures)
