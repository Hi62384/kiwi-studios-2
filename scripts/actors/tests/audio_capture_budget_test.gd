extends SceneTree
const Writer=preload("res://scripts/actors/core/audio_take_writer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	if not value:failures+=1;push_error(message)
func run()->void:
	var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
	var writer:=Writer.new();check(writer.start(directory.path_join("two_minutes.wav"),48000,false).is_empty(),"Budget writer starts")
	var block:=PackedVector2Array();block.resize(8192);block.fill(Vector2(.125,-.125))
	var seconds:=clampi(int(OS.get_environment("KIWI_CAPTURE_STRESS_SECONDS")),120,7200)
	var target_frames:=48000*seconds
	var memory_start:=OS.get_static_memory_usage();var peak_memory:=memory_start;var peak_queue:=0;var written:=0;var deadline:=Time.get_ticks_msec()+maxi(60000,seconds*300)
	while written<target_frames and Time.get_ticks_msec()<deadline:
		while writer.pending_bytes()>512*1024:await process_frame
		var count:=mini(block.size(),target_frames-written);writer.append_frames(block if count==block.size() else block.slice(0,count));written+=count
		peak_queue=maxi(peak_queue,writer.pending_bytes());peak_memory=maxi(peak_memory,OS.get_static_memory_usage())
		if not writer.error().is_empty():break
	writer.request_finish()
	while writer.busy():await process_frame
	var result:=writer.finish();check(written==target_frames and str(result.error).is_empty(),"Long equivalent capture finalizes without loading it")
	var info:=KiwiAudioPCMFile.inspect(result.path);check(int(info.get("frames",0))==target_frames,"Long capture keeps all frames")
	check(peak_queue<=Writer.MAX_PENDING_BYTES,"Capture queue stays within two MiB")
	check(peak_memory-memory_start<16*1024*1024,"Writer working memory does not grow with the take")
	# Reusing an inactive writer must reset its counters and closure state.
	check(writer.start(directory.path_join("reused.wav"),48000,false).is_empty(),"Writer can be reused after Stop");writer.append_frames(block);writer.request_finish()
	while writer.busy():await process_frame
	check(int(writer.finish().frames)==block.size(),"Reused writer starts a fresh frame count")
	KiwiAudioRenderer._remove_owned(directory)
	print("AUDIO_CAPTURE_BUDGET failures=%d audio_seconds=%d peak_queue=%d delta_static_bytes=%d"%[failures,seconds,peak_queue,peak_memory-memory_start]);quit(failures)
