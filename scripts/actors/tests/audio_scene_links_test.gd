extends SceneTree
class AudioTabs extends ActorSceneTabs:
	func _initialize_tabs() -> void: pass

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1; push_error(message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1440, 960); root.gui_embed_subwindows = true
	var layout := VBoxContainer.new(); root.add_child(layout)
	var tabs := AudioTabs.new(); layout.add_child(tabs)
	var scene := Control.new(); layout.add_child(scene)
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	scene.add_child(editor)
	var audio := KiwiAudioWorkspace.new(); layout.add_child(audio)
	await process_frame
	tabs.timeline = editor; tabs.scene_workspace = scene; tabs.audio_workspace = audio
	audio.document_changed.connect(tabs._active_audio_changed)
	audio.background_document_changed.connect(tabs._background_audio_changed)
	audio.audio_saved.connect(tabs._audio_saved)
	editor.model.changed.connect(tabs._active_scene_changed)
	tabs._add_document(editor.capture_scene_data(false), "", "Original scene", editor.model.history)
	tabs._active_index = 0; tabs._open_index(0)
	var directory := "user://audio_scene_links_" + ActorData.new_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var first_path := directory.path_join("first.tres")
	var second_path := directory.path_join("second.tres")
	var audio_path := directory.path_join("composition.tres")
	var wrong_path := directory.path_join("material.tres")
	var pcm := PackedVector2Array(); pcm.resize(4410); pcm.fill(Vector2(0.1, -0.1))
	var source := KiwiAudioSourceCache.to_wav(pcm)
	var clip := editor.model.create_actor(editor.registry.get_definition(&"audio"), 1.25, {&"audio": source, &"volume_db": -7.0, &"pan": 0.3})
	var actor_id := clip.actor_id
	check(tabs.save_current(first_path) == OK, "Scene saves its stable identity")
	var scene_id := str(tabs.documents[0].id)
	var uid := str(tabs.documents[0].persistent_id)
	check(tabs.open_audio_actor(editor.model.actor_for_id(actor_id)), "Scene Edit Audio opens the actor source")
	var session := audio.session
	check(session.document.scene_binding.actor_id == actor_id and session.document.scene_binding.scene_uid == uid, "Audio composition binds to the exact scene and actor")
	audio.document_path = audio_path
	await audio.save()
	check(FileAccess.file_exists(audio_path) and not session.dirty, "Associated editable composition saves separately")
	var original_session := audio.session
	var original_save_path := audio.document_path
	check(ResourceSaver.save(StandardMaterial3D.new(), wrong_path) == OK, "Non-audio resource fixture saves")
	var original_bytes := FileAccess.get_file_as_bytes(wrong_path)
	audio.open_source(wrong_path)
	check(audio.session == original_session and audio.document_path == original_save_path, "Invalid composition preserves the active session and save destination")
	var count := tabs.documents.size()
	check(not tabs.open_audio(wrong_path) and tabs.documents.size() == count, "Invalid composition creates no blank tab")
	var invalid := KiwiAudioDocument.from_source(null); invalid.version = 999
	audio.open_source(invalid)
	check(audio.session == original_session and audio.document_path == original_save_path, "Unsupported composition version preserves the active document")
	check(FileAccess.get_file_as_bytes(wrong_path) == original_bytes, "Failed opens preserve unrelated resource bytes")
	for child in audio.get_children():
		if child is AcceptDialog: child.queue_free()
	# Send a rendered replacement through the real scene return path.
	tabs._audio_to_scene(source, "Updated render")
	var updated := editor.model.actor_for_id(actor_id)
	print("SCENE_RETURN_MIX ",updated.values.get(&"volume_db")," ",updated.values.get(&"pan"))
	check(updated != null and is_equal_approx(float(updated.values.get(&"volume_db", 0)), -7.0) and is_equal_approx(float(updated.values.get(&"pan", 0)), 0.3), "Scene return preserves original actor identity and mix properties")
	check(updated != null and ActorSceneTabs._association_path(str(updated.values.get(&"audio_workspace_document", ""))) == ActorSceneTabs._association_path(audio_path), "Scene actor links back to the saved editable composition")
	check(tabs.save_current(second_path) == OK, "Scene Save As succeeds")
	check(ActorSceneTabs._association_path(str(session.document.scene_binding.scene_path)) == ActorSceneTabs._association_path(second_path) and session.dirty, "Save As updates open audio association and marks it unsaved")
	session.undo()
	check(ActorSceneTabs._association_path(str(session.document.scene_binding.scene_path)) == ActorSceneTabs._association_path(first_path), "Scene association relocation is Undoable")
	session.redo()
	check(ActorSceneTabs._association_path(str(session.document.scene_binding.scene_path)) == ActorSceneTabs._association_path(second_path), "Scene association relocation can be redone")
	check(KiwiAudioWorkspace.save_document(session.document.snapshot(), audio_path) == OK, "Updated audio association persists on explicit save")
	var loaded := ResourceLoader.load(audio_path, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioDocument
	check(loaded != null and loaded.scene_binding == session.document.scene_binding, "Audio composition reopens with its exact durable scene association")
	check(tabs.open_scene(first_path), "Original scene copy can be opened beside Save As destination")
	check(tabs._scene_index_for_association(session.document.scene_binding) == tabs._audio_scene_index_for_id(scene_id), "Saved path disambiguates scenes with the same persistent identity")
	var destination := tabs._audio_scene_index_for_id(scene_id)
	tabs.close_scene(destination, true)
	check(tabs._scene_index_for_association(session.document.scene_binding) < 0, "Closed destination does not resolve to a copied scene sharing its identity")
	check(tabs.open_scene(second_path) and tabs._scene_index_for_association(session.document.scene_binding) >= 0, "Reopened saved destination resolves its durable association")
	if OS.get_name() == "Windows":
		check(tabs._audio_identity(ProjectSettings.globalize_path(audio_path).to_upper()) == tabs._audio_identity(audio_path), "Windows case variants share one audio document identity")
	layout.queue_free(); await process_frame; await process_frame
	for name in DirAccess.open(directory).get_files(): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("AUDIO_SCENE_LINKS checks=%d failures=%d" % [checks, failures])
	quit(failures)
