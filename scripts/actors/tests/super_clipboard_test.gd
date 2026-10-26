extends SceneTree
var checks:=0
var failures:=0
const TEST_ROOT="res://.godot/verification/clipboard_fixture"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var store:=KiwiClipboardStore.new(TEST_ROOT+"/library_"+ActorData.new_id())
	check(store.folder_valid("default") and store.data.entries.is_empty(),"Clipboard starts with one independent Default folder")
	var source:=store.root.path_join("source.png"); var image:=Image.create(8,6,false,Image.FORMAT_RGBA8); image.fill(Color(.2,.7,.4,.8)); image.save_png(source)
	var texture:=ActorObjectData.new(); texture.type_id=&"image"; texture.values={&"source":source}
	var material:=ActorObjectData.new(); material.type_id=&"material"; material.values={&"albedo_texture":ActorObjectReference.from_object(texture),&"roughness":.35}
	var id:=store.save(material,"Leaf material")
	check(not id.is_empty() and str(store.data.default_slot)==id,"Saving an embedded material creates a real Default Slot snapshot")
	var snapshot:=ResourceLoader.load(store.entry_path(id),"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(snapshot!=null and snapshot.type_id==&"material","Stored resource retains its native editable type")
	var stored_image:=((snapshot.values.albedo_texture as ActorObjectReference).embedded as ActorObjectData).values.source as String
	check(stored_image!=source and FileAccess.file_exists(stored_image),"Material texture dependencies are copied into persistent storage")
	DirAccess.remove_absolute(source)
	check(absf(Image.load_from_file(stored_image).get_pixel(0,0).g-.7)<.005,"Deleting the original image does not break the stored material")
	var folder:=store.create_folder("Materials",""); var nested:=store.create_folder("Plants",folder)
	check(store.move(PackedStringArray([id]),nested) and store.rename(id,"Fresh leaf"),"Resources can be moved into nested folders and renamed")
	check(store.entry_path(id)==snapshot.resource_path or not store.entry_path(id).is_empty(),"Renaming and moving keep stable IDs and stored payloads")
	var reloaded:=KiwiClipboardStore.new(store.root)
	check(reloaded.data.entries[id].name=="Fresh leaf" and reloaded.data.entries[id].folder==nested,"A fresh service restores persistent names and nested folders")
	check(not store.move(PackedStringArray([folder]),nested) and store.folder_valid(folder),"Folder cycles are rejected without changing the hierarchy")
	store.set_default(id); store.delete(PackedStringArray([id]))
	check(store.entry_path(id).is_empty() and not store.entry_path(id,true).is_empty(),"Delete is recoverable and never destroys stored resource bytes")
	store.history.undo(); check(not store.entry_path(id).is_empty(),"Clipboard deletion undoes independently of scene history")
	store.history.redo(); store.delete(PackedStringArray([id]),true)
	check(not store.entry_path(id).is_empty(),"Resources can be restored after deletion")
	var project_a:=store.root.path_join("Project A"); var project_b:=store.root.path_join("Project B"); DirAccess.make_dir_recursive_absolute(project_a); DirAccess.make_dir_recursive_absolute(project_b)
	var imported_a:=store.materialize(id,project_a); var imported_b:=store.materialize(id,project_b)
	check(not imported_a.is_empty() and not imported_b.is_empty() and imported_a!=imported_b,"Different projects receive their own portable resource copies")
	check(store.materialize(id,project_b)==imported_b,"Repeated imports reuse the project-local copy")
	var local_copy:=ResourceLoader.load(imported_b,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	var local_texture: String=(local_copy.values.albedo_texture as ActorObjectReference).embedded.values.source
	check(FileOperations.is_path_inside(project_b,local_texture),"Imported material points to dependencies inside the destination project")
	local_copy.values.roughness=.9; ResourceSaver.save(local_copy,imported_b)
	var original:=ResourceLoader.load(store.entry_path(id),"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(is_equal_approx(float(original.values.roughness),.35),"Editing the project copy never modifies the stored snapshot")
	var id2:=store.save(material,"Another material")
	check(id2.is_empty() and store.data.entries.size()==1,"Missing dependencies fail clearly rather than storing a broken shortcut")
	id2=store.save(original,"Another material")
	check(not id2.is_empty() and store.data.entries.size()==2 and store.data.default_slot==id2,"Quick saves retain old resources and update only the Default Slot pointer")
	store.set_default(id); reloaded=KiwiClipboardStore.new(store.root)
	check(reloaded.data.default_slot==id,"Manual Default Slot selection survives a service restart")
	var count: int=store.data.entries.size(); store.move(PackedStringArray([id]),nested,true)
	check(store.data.entries.size()==count+1,"Duplicating creates an independent stable entry without replacing the original")
	var actor:=ActorData.new(); actor.type_id=&"basic_shape"; actor.id=ActorData.new_id(); actor.values={&"position":Vector3(1,2,3),&"material":ActorObjectReference.from_object(original)}
	var key:=ActorAnimationTrack.new(); key.path=PackedStringArray(["position"]); actor.animation_tracks.append(key)
	var scene:=ActorSceneData.new(); scene.actors.append(actor)
	var scene_id:=store.save(scene,"Reusable scene")
	check(not scene_id.is_empty() and (ResourceLoader.load(store.entry_path(scene_id),"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData).actors[0].animation_tracks.size()==1,"Scene snapshots preserve actor trees and animation resources")
	var document:=KiwiImageDocument.new(); var layer:=KiwiImageLayer.new(); layer.label="Editable"; document.layers.append(layer)
	check(not store.save(document,"Editable image").is_empty(),"Editable image documents save without flattening their layers")
	var before:=store.data.duplicate(true); var corrupt:=FileAccess.open(store.root.path_join("index.json"),FileAccess.WRITE); corrupt.store_string("interrupted metadata"); corrupt.close()
	reloaded=KiwiClipboardStore.new(store.root)
	check(not reloaded.data.entries.is_empty() and reloaded.error.contains("Recovered"),"Damaged metadata recovers from a validated backup")
	var saved:=FileAccess.open("res://.godot/verification/clipboard_restart_path.txt",FileAccess.WRITE); saved.store_string(store.root); saved.close()
	check(not store.save("user://missing_clipboard_media.png","Broken").is_empty()==false,"Missing source files report an error without crashing")
	var future_root:=store.root.path_join("newer-version"); DirAccess.make_dir_recursive_absolute(future_root)
	var future: Dictionary=before.duplicate(true); future.version=999; var payload:=JSON.stringify(future); var future_path:=future_root.path_join("index.json"); var future_file:=FileAccess.open(future_path,FileAccess.WRITE); var future_bytes:=JSON.stringify({"payload":payload,"checksum":payload.sha256_text()}); future_file.store_string(future_bytes); future_file.close()
	var protected_store:=KiwiClipboardStore.new(future_root)
	check(protected_store.read_only and protected_store.save(original,"No overwrite").is_empty() and FileAccess.get_file_as_string(future_path)==future_bytes,"Unknown future metadata versions are preserved read-only")
	protected_store.close()
	store.close(); reloaded.close()
	print("SUPER CLIPBOARD: %d checks, %d failures"%[checks,failures]); quit(failures)
