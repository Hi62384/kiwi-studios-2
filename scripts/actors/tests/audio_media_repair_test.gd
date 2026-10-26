extends SceneTree
const Repair = preload("res://Workspaces/AudioWorkspace/audio_media_repair.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	var directory := "user://media_repair_" + ActorData.new_id(); DirAccess.make_dir_recursive_absolute(directory)
	var samples := PackedVector2Array(); samples.resize(48000)
	var stream := KiwiAudioSourceCache.to_wav(samples,48000)
	var destination := directory.path_join("replacement.wav"); stream.save_to_wav(destination)
	var missing := directory.path_join("missing.wav")
	var session := KiwiAudioEditSession.new(); session.document=KiwiAudioDocument.from_source(stream)
	var document := session.document; var clip := document.clips[0]; var actor := document.actors[0]
	clip.duration=.5; clip.source_offset=.1
	actor.values[&"audio"]=missing; actor.values[&"original_audio"]=missing
	var second := document.add_track("Sampler","instrument"); var sampler_clip := document.insert_source(stream,second.id,0,"Sampler")
	var sampler := document.actor_for_clip(sampler_clip.id)
	sampler.values[&"instrument"]={"kind":"multisample","multisamples":[{"sample":missing,"root_pitch":60,"low":0,"high":127}]}
	document.tracks[0].instrument={"kind":"sampler","sample":missing,"loop_start":.1,"loop_end":.8}
	document.master.effects=[{"id":"ir","type":"convolution","parameters":{"impulse_path":missing}}]
	var scan := Repair.scan(document)
	check(str(scan.error).is_empty() and scan.entries.size()==1,"One review groups active clip, sampler and impulse references")
	check(scan.entries[0].count==4 and bool(scan.entries[0].missing),"Provenance is excluded while all four active references are reported")
	var probe := KiwiAudioEditSession.probe_audio_relink(destination)
	check(str(probe.get("error","")).is_empty(),"Replacement probe accepts a bounded PCM source")
	var problem := Repair.apply(session,document,session.revision,missing,probe)
	check(problem.is_empty(),"Matching references are repaired atomically: " + problem)
	check(actor.id==clip.actor_id and clip.source_offset==.1 and clip.duration==.5,"Relinking preserves actor identity and clip geometry")
	check(sampler.values.instrument.multisamples[0].sample==destination and document.tracks[0].instrument.sample==destination and document.master.effects[0].parameters.impulse_path==destination,"Sampler maps and impulse references retain their editable associations")
	check(actor.values.original_audio==missing,"Original-source provenance remains unchanged")
	session.undo(); document=session.document
	check(document.actors[0].values.audio==missing and document.master.effects[0].parameters.impulse_path==missing,"One Undo restores every repaired reference")
	document.tracks[0].locked=true
	check(not Repair.apply(session,document,session.revision,missing,probe).is_empty() and document.actors[0].values.audio==missing,"Locked owners reject the entire repair")
	document.tracks[0].locked=false; document.tracks[0].instrument.loop_end=4.
	check(not Repair.apply(session,document,session.revision,missing,probe).is_empty(),"A replacement cannot silently truncate a sampler loop")
	document.tracks[0].instrument.loop_end=.8
	check(not Repair.apply(session,document,session.revision-1,missing,probe).is_empty(),"Stale review revisions cannot mutate the composition")
	print("AUDIO_MEDIA_REPAIR checks=%d failures=%d" % [checks,failures]); quit(failures)
