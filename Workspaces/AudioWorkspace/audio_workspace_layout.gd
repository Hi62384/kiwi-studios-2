extends Node
## Presentation/navigation only. Document edits remain in the existing session.
var automation_panel:VBoxContainer
var clip_actions:HFlowContainer
var empty_state:CenterContainer
var detail_button:Button
var busy_button:Button
var inspector_scroll:ScrollContainer
var inspector_view:=""
var folds:Dictionary={}
var _menus:Dictionary={}
func workspace()->Variant:return get_parent()
func menu(parent:Node,label:String,items:Array)->MenuButton:
	var w:Variant=workspace();var button:=MenuButton.new();button.text=label+" ▾";parent.add_child(button)
	var popup:=button.get_popup();popup.add_theme_stylebox_override("panel",w._box(Color("162430"),Color("3c5868"),8));popup.add_theme_font_size_override("font_size",12)
	popup.add_theme_constant_override("v_separation",10)
	var callbacks:Dictionary={}
	for entry in items:
		if entry is String:popup.add_separator(entry);continue
		var id:=popup.item_count;popup.add_item(str(entry[0]),id);callbacks[id]=entry[1]
	popup.id_pressed.connect(func(id:int):if callbacks.has(id):callbacks[id].call())
	return button
func header(parent:Node)->void:
	var w:Variant=workspace();var row:=HBoxContainer.new();row.add_theme_constant_override("separation",5);parent.add_child(row)
	w.title_label.text="Audio";w.title_label.custom_minimum_size.x=120;w.title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;w.title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	w.title_label.add_theme_font_size_override("font_size",17);w.title_label.add_theme_color_override("font_color",Color("7bdcc4"));row.add_child(w.title_label)
	menu(row,"File",["COMPOSITION",["Open composition…",w.open_dialog],["Save composition",w.save],["Save to Super Clipboard",func(): w.capture_state(); KiwiSuperClipboardService.instance.quick_save(w.session.document.snapshot(),w.session.document.title)],["Collect portable copy…",w.review_portable_copy],"AUDIO",["Import audio…",w.import_audio],["Export audio…",w.export_dialog],["Use audio in Scene",w.send_to_scene],"SAFETY",["Recovery checkpoints…",w.review_recovery],["Recover recorded takes…",w.recover_disk_takes],["Repair missing media…",w.missing_media_dialog]])
	menu(row,"Edit",[["Undo · Ctrl+Z",w.undo],["Redo · Ctrl+Shift+Z",w.redo],"CLIPS",["Copy · Ctrl+C",func():w.session.copy()],["Paste at playhead · Ctrl+V",func():w.session.paste(w.playback.position,w.session.selected_track)],["Duplicate · Ctrl+D",func():w.session.duplicate_selected()],["Delete · Delete",func():w.session.delete_selected()],["Split at playhead · S",func():w.session.split_selected(w.playback.position)],["Crossfade selected clips",func():w.session.crossfade_selected()]])
	menu(row,"Add",[["Import audio file…",w.import_audio],["Track…",w.add_track_dialog],["Instrument pattern",w.new_pattern.bind(false)],["Drum pattern",w.new_pattern.bind(true)],["Generate music…",w.music_dialog],["Marker at playhead",w.add_marker]])
	menu(row,"Tools",["PROJECT",["Tempo & time signature…",w.conductor_dialog],["Arrangement…",w.arrangement_dialog],"PROCESSING",["Add effect…",w.add_effect_dialog],["Effect chain presets…",w.effect_chain_dialog],["Review dialogue cleanup…",w.review_dialogue_batch],["Modulation matrix…",w.modulation_matrix_dialog],"OPTIONAL SPEECH",["Transcribe selected clip locally",func():w._optional_tools.transcribe()],["Review saved transcript",func():w._optional_tools.review_saved_transcript()],["Generate cloud speech (opt-in)…",func():w._optional_tools.speech()],["Speech tool setup…",w.provider_status],"MORE",["Search all commands… · Ctrl+K",w.command_palette],["Customize shortcuts…",w.customize_shortcuts]])
	var view:=menu(row,"View",[["Sounds library",func():w.library.visible=not w.library.visible],["Inspector",func():inspector_scroll.visible=not inspector_scroll.visible],"EDITORS",["Audio / waveform",show_detail.bind(0)],["Notes / piano roll",show_detail.bind(1)],["Drums / step sequencer",show_detail.bind(2)],["Effects",show_detail.bind(3)],["Mixer",show_detail.bind(4)],["Cleanup & analysis",show_detail.bind(5)],["Hide editor",func():w.bottom.hide()],"ADVANCED",["Automation controls",toggle_automation],["Fit timeline",w.fit_timeline]])
	_menus.view=view
	w._button(row,"Save",w.save,"Save composition · Ctrl+S")
	# Keep the established Scene integration endpoint; it is now a File action.
	w.send_scene_button=Button.new();w.send_scene_button.hide();add_child(w.send_scene_button)
	w.send_scene_button.pressed.connect(w.send_to_scene)
	w._recovery_status.hide();add_child(w._recovery_status)
func group(parent:Node)->HBoxContainer:
	var w:Variant=workspace();var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",w._box(Color("16232e"),Color("293f50"),6));parent.add_child(panel)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",4);panel.add_child(row);return row
func toggle_automation()->void:
	if automation_panel.visible:
		workspace()._finish_automation_pass("Automation controls closed")
		automation_panel.hide()
	else:automation_panel.show()
func show_detail(index:int)->void:
	var w:Variant=workspace()
	if index==0 and w.session.primary_clip()!=null:w.edit_clip(w.session.primary_clip().id)
	w.bottom.show();w.bottom.current_tab=index
func detail_controls(parent:Node)->void:
	var w:Variant=workspace();var row:=HBoxContainer.new();parent.add_child(row)
	var caption:Label=w._label(row,"TIMELINE");caption.add_theme_color_override("font_color",Color("7bdfc6"));caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	w._button(row,"+ Track",w.add_track_dialog,"Add an audio, instrument or automation track")
	detail_button=w._button(row,"Open editor",func():
		if w.bottom.visible:w.bottom.hide()
		elif w.session.primary_actor()!=null and KiwiAudioEditSession.is_note_source(w.session.primary_actor()):show_detail(1)
		else:show_detail(0),"Double-click an audio clip to edit its waveform. View opens every other editor.")
	w._button(row,"Fit",w.fit_timeline,"Fit clips in the visible timeline")
func install_empty_state()->void:
	var w:Variant=workspace();empty_state=CenterContainer.new();empty_state.mouse_filter=Control.MOUSE_FILTER_IGNORE;empty_state.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);empty_state.offset_left=KiwiAudioTimelineCanvas.LABEL_WIDTH;empty_state.offset_top=70;w.canvas.add_child(empty_state)
	var content:=VBoxContainer.new();content.mouse_filter=Control.MOUSE_FILTER_IGNORE;content.add_theme_constant_override("separation",10);empty_state.add_child(content)
	var title:Label=w._label(content,"Start with a sound");title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",21)
	var hint:Label=w._label(content,"Import a file, or drag a sound from the library onto this timeline.");hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hint.custom_minimum_size.x=240;hint.add_theme_color_override("font_color",Color("91a6b5"))
	var actions:=HBoxContainer.new();actions.alignment=BoxContainer.ALIGNMENT_CENTER;content.add_child(actions)
	w._button(actions,"+ Import audio",w.import_audio)
	menu(actions,"Create",[["Instrument pattern",w.new_pattern.bind(false)],["Drum pattern",w.new_pattern.bind(true)],["Generate music…",w.music_dialog]])
func fold(parent:Node,key:String,label:String,open:bool=false)->VBoxContainer:
	var w:Variant=workspace();var box:=VBoxContainer.new();parent.add_child(box)
	var button:=Button.new();button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.toggle_mode=true;button.button_pressed=bool(folds.get(key,open));box.add_child(button)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",6);box.add_child(body);body.visible=button.button_pressed
	var update:=func(enabled:bool):button.text=("▾  " if enabled else "▸  ")+label;body.visible=enabled;folds[key]=enabled
	button.toggled.connect(update);update.call(button.button_pressed);return body
func organize_inspector()->void:
	var w:Variant=workspace();var parent:VBoxContainer=w.inspector;var children:=parent.get_children()
	var tabs:=HBoxContainer.new();parent.add_child(tabs);parent.move_child(tabs,0)
	var groups:Dictionary={}
	for key in ["clip","track","project"]:
		var body:=VBoxContainer.new();body.add_theme_constant_override("separation",8);parent.add_child(body);groups[key]=body
	var key:="clip" if w.session.primary_clip()!=null else "track"
	for child in children:
		if child is Label:
			if child.text.begins_with("CLIP ·"):key="clip"
			elif child.text.begins_with("TRACK ·"):key="track"
			elif child.text=="PROJECT":key="project"
		child.reparent(groups[key])
	if inspector_view.is_empty() or groups.get(inspector_view,groups.project).get_child_count()==0:inspector_view="clip" if groups.clip.get_child_count()>0 else ("track" if groups.track.get_child_count()>0 else "project")
	for id in groups:
		var body:VBoxContainer=groups[id];body.visible=id==inspector_view
		if body.get_child_count()==0:continue
		var button:=Button.new();button.text=str(id).capitalize();button.toggle_mode=true;button.button_pressed=id==inspector_view;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;tabs.add_child(button)
		button.pressed.connect(func():inspector_view=id;w._refresh_inspector())
	var clip_rows:Array=groups.clip.get_children();var timing:VBoxContainer;var instrument:VBoxContainer;var instrument_rows:=false
	for child in clip_rows:
		if child is Label and child.text=="INSTRUMENT":
			instrument=fold(groups.clip,"clip_instrument","Instrument settings");instrument_rows=true
		elif child is Label and child.text=="SELECTED NOTE":instrument_rows=false
		if instrument_rows:child.reparent(instrument);continue
		var label:=""
		if child is HBoxContainer and child.get_child_count()>0 and child.get_child(0) is Label:label=child.get_child(0).text
		if label in ["Start (s)","Duration (s)","Source offset","Speed","Pitch (semi)"] or (child is CheckBox and child.text in ["Loop source","Reverse (rendered)"]):
			if timing==null:timing=fold(groups.clip,"clip_timing","Timing & playback")
			child.reparent(timing)
	var tools:VBoxContainer
	for child in groups.track.get_children():
		var advanced:=child is Button and not child is ColorPickerButton
		if child is HBoxContainer and child.get_child_count()>0 and child.get_child(0) is Label:advanced=child.get_child(0).text=="Output"
		if advanced:
			if tools==null:tools=fold(groups.track,"track_tools","Routing & track tools")
			child.reparent(tools)
func selected()->void:
	inspector_view=""
	if clip_actions!=null:clip_actions.visible=not workspace().session.selected_ids.is_empty()
func sync()->void:
	var w:Variant=workspace()
	if empty_state!=null:empty_state.visible=w.session.document.clips.is_empty()
	if clip_actions!=null:clip_actions.visible=not w.session.selected_ids.is_empty()
	if detail_button!=null:
		detail_button.text="Close editor" if w.bottom.visible else "Open editor"
		detail_button.disabled=not w.bottom.visible and w.session.primary_clip()==null
		detail_button.tooltip_text="Select a clip to open its editor. View opens the mixer and other editors." if detail_button.disabled else "Double-click a clip to edit. Close editor returns the space to the timeline."
	var busy:bool=w.jobs.busy() or w._optional_tools.jobs.busy() or w._record_busy or w._portable_jobs.busy() or w._recovery_jobs.busy()
	w.progress.visible=busy
	if busy_button!=null:busy_button.visible=busy
	if automation_panel!=null and w.automation_recording.mode!="Read":automation_panel.show()
