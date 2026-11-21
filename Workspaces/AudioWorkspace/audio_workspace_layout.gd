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

	return _native().menu(self,parent,label,items)

func header(parent:Node)->void:

	var w:Variant=workspace()

	var sections:Array=[]

	sections.append(["File",["COMPOSITION",["Open composition…",w.open_dialog],["Save composition",w.save],["Save to Super Clipboard",func(): w.capture_state(); KiwiSuperClipboardService.instance.quick_save(w.session.document.snapshot(),w.session.document.title)],["Collect portable copy…",w.review_portable_copy],"AUDIO",["Import audio…",w.import_audio],["Export audio…",w.export_dialog],["Use audio in Scene",w.send_to_scene],"SAFETY",["Recovery checkpoints…",w.review_recovery],["Recover recorded takes…",w.recover_disk_takes],["Repair missing media…",w.missing_media_dialog]]])

	sections.append(["Edit",[["Undo · Ctrl+Z",w.undo],["Redo · Ctrl+Shift+Z",w.redo],"CLIPS",["Copy · Ctrl+C",func():w.session.copy()],["Paste at playhead · Ctrl+V",func():w.session.paste(w.playback.position,w.session.selected_track)],["Duplicate · Ctrl+D",func():w.session.duplicate_selected()],["Delete · Delete",func():w.session.delete_selected()],["Split at playhead · S",func():w.session.split_selected(w.playback.position)],["Crossfade selected clips",func():w.session.crossfade_selected()]]])

	sections.append(["Add",[["Import audio file…",w.import_audio],["Track…",w.add_track_dialog],["Instrument pattern",w.new_pattern.bind(false)],["Drum pattern",w.new_pattern.bind(true)],["Generate music…",w.music_dialog],["Marker at playhead",w.add_marker]]])

	sections.append(["Tools",["PROJECT",["Tempo & time signature…",w.conductor_dialog],["Arrangement…",w.arrangement_dialog],"PROCESSING",["Add effect…",w.add_effect_dialog],["Effect chain presets…",w.effect_chain_dialog],["Review dialogue cleanup…",w.review_dialogue_batch],["Modulation matrix…",w.modulation_matrix_dialog],"OPTIONAL SPEECH",["Transcribe selected clip locally",func():w._optional_tools.transcribe()],["Review saved transcript",func():w._optional_tools.review_saved_transcript()],["Generate cloud speech (opt-in)…",func():w._optional_tools.speech()],["Speech tool setup…",w.provider_status],"MORE",["Search all commands… · Ctrl+K",w.command_palette],["Customize shortcuts…",w.customize_shortcuts]]])

	sections.append(["View",[["Sounds library",func():w.library.visible=not w.library.visible],["Inspector",func():inspector_scroll.visible=not inspector_scroll.visible],"EDITORS",["Audio / waveform",show_detail.bind(0)],["Notes / piano roll",show_detail.bind(1)],["Drums / step sequencer",show_detail.bind(2)],["Effects",show_detail.bind(3)],["Mixer",show_detail.bind(4)],["Cleanup & analysis",show_detail.bind(5)],["Hide editor",func():w.bottom.hide()],"ADVANCED",["Automation controls",toggle_automation],["Fit timeline",w.fit_timeline]]])

	_native().header(self,parent,sections)

func group(parent:Node)->HBoxContainer:

	return _native().group(self,parent)

func toggle_automation()->void:

	_native().toggle_automation(self)

func show_detail(index:int)->void:

	_native().show_detail(self,index)

func detail_controls(parent:Node)->void:

	_native().detail_controls(self,parent)

func install_empty_state()->void:

	var w:Variant=workspace()

	_native().install_empty_state(self,[["Instrument pattern",w.new_pattern.bind(false)],["Drum pattern",w.new_pattern.bind(true)],["Generate music…",w.music_dialog]])

func fold(parent:Node,key:String,label:String,open:bool=false)->VBoxContainer:

	return _native().fold(self,parent,key,label,open)

func organize_inspector()->void:

	_native().organize_inspector(self)

func selected()->void:

	_native().selected(self)

func sync()->void:

	_native().sync(self)



func _native()->Variant:

	return Engine.get_singleton("KiwiNativeServices").service("audio_workspace_layout")

func _dispatch_menu(callbacks:Dictionary,id:int)->void:

	if callbacks.has(id):callbacks[id].call()

