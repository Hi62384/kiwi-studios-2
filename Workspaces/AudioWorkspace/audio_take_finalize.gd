extends RefCounted
## Called through the existing bounded job queue. Never loads an entire take.
const ROOT := "user://audio_workspace/takes"
const MAX_BYTES := 2 * 1024 * 1024 * 1024 - 44

static func finalize(capture: Dictionary, job: RefCounted = null) -> Dictionary:
	var directory := str(capture.get("directory","")).replace("\\","/").simplify_path()
	var root := ProjectSettings.globalize_path(ROOT).replace("\\","/").simplify_path()
	if directory.get_base_dir() != root: return {"error":"Invalid take folder.","path":""}
	var paths: Array[String] = []; var warnings := PackedStringArray()
	if not str(capture.get("error","")).is_empty(): warnings.append(str(capture.error))
	var seconds := 0.
	for source in capture.get("paths",[]):
		var path := str(source).replace("\\","/").simplify_path()
		if path.get_base_dir() != directory: warnings.append("A take source was outside its owned folder."); continue
		var info := KiwiAudioPCMFile.inspect(path)
		if not str(info.get("error","invalid")).is_empty(): warnings.append(path.get_file() + ": " + str(info.get("error","Unreadable take"))); continue
		if int(info.file_bytes) > MAX_BYTES + 44: warnings.append("Take input exceeded 2 GiB. Original retained: " + path); continue
		paths.append(path); seconds = maxf(seconds, float(info.duration))
	var output := paths[0] if paths.size() == 1 else ""
	if not paths.is_empty() and (paths.size() > 1 or (bool(capture.get("mono",false)) and int(KiwiAudioPCMFile.inspect(paths[0]).get("channels",1)) == 2)):
		var encoder := ActorVideo.executable("ffmpeg")
		if encoder.is_empty(): warnings.append("FFmpeg is required to combine recording sources. Import the retained source WAVs separately.")
		elif seconds * 48000 * (2 if bool(capture.get("mono",false)) else 4) > MAX_BYTES:
			warnings.append("Combined take would exceed the 2 GiB output limit; all separate source files were retained.")
		else:
			output = directory.path_join("mix.wav")
			if FileAccess.file_exists(output):
				warnings.append("A finalized mix already exists; it was not overwritten."); output = ""
			else:
				var args := PackedStringArray(["-nostdin","-hide_banner","-v","error","-n","-threads","1","-filter_complex_threads","1"])
				var inputs := ""; var graph := ""
				for index in paths.size():
					args.append_array(PackedStringArray(["-i",paths[index]]))
					# FFmpeg's default mono-to-stereo rematrix attenuates by 3 dB.
					# Captured mono is already an amplitude average: duplicate it
					# explicitly so adding a mono source does not change its gain.
					var channel_map := "pan=stereo|c0=c0|c1=c0," if int(KiwiAudioPCMFile.inspect(paths[index]).get("channels",2)) == 1 else ""
					graph += "[%d:a]%saresample=48000,aformat=sample_fmts=flt:channel_layouts=stereo[s%d];" % [index,channel_map,index]; inputs += "[s%d]" % index
				graph += inputs + "amix=inputs=%d:normalize=0:dropout_transition=0:duration=longest[out]" % paths.size()
				args.append_array(PackedStringArray(["-filter_complex",graph,"-map","[out]","-ar","48000","-ac","1" if bool(capture.get("mono",false)) else "2","-c:a","pcm_s16le",output]))
				var result := KiwiAudioRenderer.execute(encoder,args,seconds,job)
				if not bool(result.get("success",false)):
					warnings.append(str(result.get("error","Take mixing failed."))); output = ""
	if job != null and job.is_cancelled(): warnings.append("Take finalization was cancelled. Separate captures remain recoverable."); output = ""
	if not output.is_empty() and not str(KiwiAudioPCMFile.inspect(output).get("error","invalid")).is_empty(): warnings.append("The finalized take could not be read."); output = ""
	var result := {"error":"" if not output.is_empty() else "No combined take is available. Inputs were preserved in " + directory,"path":output,"directory":directory,"sources":paths,"warning":"; ".join(warnings)}
	var journal := ConfigFile.new(); journal.load(directory.path_join("take.cfg"))
	journal.set_value("take","state","ready" if not output.is_empty() else "needs_review"); journal.set_value("take","result",result)
	var saved := journal.save(directory.path_join("take.cfg"))
	if saved != OK: result.warning += " Recovery journal could not be updated: " + error_string(saved)
	return result

static func recoverable() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var root := ProjectSettings.globalize_path(ROOT)
	var folder := DirAccess.open(root)
	if folder == null: return result
	folder.list_dir_begin(); var name := folder.get_next(); var visited := 0
	while not name.is_empty() and visited < 512:
		visited += 1
		if folder.current_is_dir() and name.is_valid_hex_number(false) and name.length() == 32:
			var directory := root.path_join(name); var journal := ConfigFile.new()
			if ActorAudioRecorder.active_take_directories.has(directory.replace("\\","/").simplify_path()): name = folder.get_next(); continue
			if journal.load(directory.path_join("take.cfg")) == OK:
				var entry: Dictionary = journal.get_value("take","result",{}).duplicate(true)
				entry.directory = directory; entry.state = journal.get_value("take","state","unknown"); entry.paths = []
				for file in ["mix.wav","microphone.wav","system.wav","timeline.wav"]:
					var path := directory.path_join(file); var info := KiwiAudioPCMFile.inspect(path)
					if str(info.get("error","invalid")).is_empty(): entry.paths.append(path)
				if not entry.paths.is_empty(): result.append(entry)
		name = folder.get_next()
	folder.list_dir_end()
	return result
