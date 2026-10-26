class_name KiwiAudioAnalysis
extends RefCounted
## Lightweight deterministic analysis. Estimates are labeled and editable.
const MAX_FILE_SOURCE_SECONDS := 86400.0
const MAX_FILE_ANALYSIS_SECONDS := 7200.0
const MAX_FILE_ANALYSIS_BINS := 720000
const MAX_SILENCE_REGIONS := 2048
const MAX_FILE_TRANSIENTS := 65536
const FILE_TEMPO_SECONDS := 60.0

# File-backed dialogue detection reads only the requested source window. Its
# timestamps remain source-relative and duration remains the FULL file length,
# as required by SilencePlan. The legacy stream path below is still available.
static func analyze_source(value: Variant, threshold_db: float = -42, minimum_silence: float = 0.25, job: RefCounted = null, start: float = 0.0, duration: float = -1.0) -> Dictionary:
 if not is_finite(threshold_db) or threshold_db < -120 or threshold_db > 0 or not is_finite(minimum_silence) or minimum_silence <= 0 or minimum_silence > 600: return {"error": "Invalid silence detector settings."}
 if not is_finite(start) or start < 0 or not is_finite(duration) or duration != -1.0 and duration <= 0: return {"error": "Invalid analysis source window."}
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if value is String and value.get_extension().to_lower() == "wav":
  # Unsupported WAV variants must never fall through to a whole-file decoder.
  var info := KiwiAudioPCMFile.inspect(value)
  if not str(info.get("error", "invalid")).is_empty(): return {"error": "Dialogue analysis requires supported mono/stereo PCM WAV. " + str(info.get("error", "Invalid WAV metadata."))}
  return _analyze_pcm_file(value, info, threshold_db, minimum_silence, job, start, duration)
 var problem := silence_source_error(value)
 if not problem.is_empty(): return {"error": problem}
 var signature := _analysis_file_signature(str(value)) if value is String else {}
 if value is String and signature.is_empty(): return {"error": "Missing or unreadable audio source."}
 var stream := ActorAudio.source(value, job)
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if stream == null: return {"error": "Missing or unreadable audio source."}
 problem = silence_source_error(stream)
 if not problem.is_empty(): return {"error": problem}
 if start >= stream.get_length() or duration > 0 and start + duration > stream.get_length() + 0.0001: return {"error": "The selected source window extends beyond the recording."}
 var result := analyze(stream, threshold_db, minimum_silence, job)
 if not str(result.get("error", "")).is_empty(): return result
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if value is String and signature != _analysis_file_signature(str(value)): return {"error": "The source changed during analysis. Analyze it again."}
 if (result.silences as Array).size() > MAX_SILENCE_REGIONS: return {"error": "More than 2048 quiet regions were detected. Increase the minimum pause duration and analyze again."}
 # Other formats retain the existing, bounded whole-short-source behavior.
 # Do not label its measurements or detections as selected-window results.
 result.analyzed_start = 0.0; result.analyzed_end = float(result.duration); result.analyzed_duration = float(result.duration)
 result.envelope_start = 0.0; result.method = "Whole short-source decode"
 result.tempo_limited = false; result.tempo_duration = float(result.duration)
 result.windowed = false; result.source_signature = signature
 return result

static func _analysis_file_signature(path: String) -> Dictionary:
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return {}
 var result := {"file_bytes": file.get_length(), "modified": FileAccess.get_modified_time(path)}
 file.close()
 return result

static func _pcm_file_current(path: String, info: Dictionary, file: FileAccess = null, inspect_header: bool = false) -> bool:
 if file != null and file.get_length() != int(info.file_bytes): return false
 if _analysis_file_signature(path) != {"file_bytes": int(info.file_bytes), "modified": int(info.modified)}: return false
 # Compare every inspected field, not a rounded duration or cached identity.
 return not inspect_header or KiwiAudioPCMFile.inspect(path) == info

static func _analyze_pcm_file(path: String, info: Dictionary, threshold_db: float, minimum_silence: float, job: RefCounted, start: float, duration: float) -> Dictionary:
 var source_duration := float(info.duration); var rate := int(info.rate)
 if not is_finite(source_duration) or source_duration <= 0 or source_duration > MAX_FILE_SOURCE_SECONDS: return {"error": "PCM dialogue sources must be nonempty and at most 24 hours long."}
 if start >= source_duration or duration > 0 and start + duration > source_duration + 0.0001: return {"error": "The selected source window extends beyond the recording."}
 var end := source_duration if duration < 0 else minf(source_duration, start + duration)
 if end - start > MAX_FILE_ANALYSIS_SECONDS: return {"error": "Analyze at most two source hours at once. Split or trim the clip to a smaller source window."}
 # Round inward, so detections never include audio outside the requested clip.
 var first := int(ceil(start * rate))
 var last := int(info.frames) if end == source_duration else mini(int(info.frames), int(floor(end * rate)))
 var total := last - first
 if total <= 0: return {"error": "The selected source window contains no complete audio frames."}
 if ceili(float(total) * 100.0 / rate) > MAX_FILE_ANALYSIS_BINS: return {"error": "The selected source window exceeds the dialogue-envelope bound."}
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return {"error": "Could not open the PCM source for analysis."}
 if not _pcm_file_current(path, info, file, true):
  file.close(); return {"error": "The PCM source changed before analysis. Analyze it again."}
 var energies := PackedFloat32Array(); var peak := 0.0; var sum_squared := 0.0
 var cursor := 0; var block_frames := 0; var block_power := 0.0
 var block_end := mini(total, int(round(rate / 100.0)))
 var checked := Time.get_ticks_msec()
 while cursor < total:
  if job != null and job.is_cancelled(): file.close(); return {"error": "Cancelled."}
  if Time.get_ticks_msec() - checked >= 1000:
   checked = Time.get_ticks_msec()
   if not _pcm_file_current(path, info, file): file.close(); return {"error": "The PCM source changed during analysis. Analyze it again."}
  var count := mini(KiwiAudioPCMFile.MAX_READ_FRAMES, total - cursor)
  var samples := KiwiAudioPCMFile.read_frames(file, info, first + cursor, count)
  if samples.size() != count: file.close(); return {"error": "The PCM source ended before its declared analysis window. No partial detections were kept."}
  for sample in samples:
   peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
   block_power += (sample.x * sample.x + sample.y * sample.y) * 0.5
   block_frames += 1; cursor += 1
   if cursor == block_end:
    energies.append(sqrt(block_power / block_frames))
    sum_squared += block_power; block_power = 0.0; block_frames = 0
    block_end = mini(total, int(round(float(energies.size() + 1) * rate / 100.0)))
  if job != null: job.update(float(cursor) / total * 0.8, "Analyzing selected PCM source window")
 if not _pcm_file_current(path, info, file, true):
  file.close(); return {"error": "The PCM source changed during analysis. Analyze it again."}
 file.close()
 var result := _finish_pcm_analysis(energies, first, total, rate, source_duration, peak, sum_squared, threshold_db, minimum_silence, job)
 if not str(result.get("error", "")).is_empty(): return result
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if not _pcm_file_current(path, info, null, true): return {"error": "The PCM source changed during analysis. Analyze it again."}
 result.source_signature = info.duplicate()
 if job != null: job.update(1.0, "PCM dialogue analysis ready for review")
 return result

static func _finish_pcm_analysis(energies: PackedFloat32Array, first: int, total: int, rate: int, source_duration: float, peak: float, sum_squared: float, threshold_db: float, minimum_silence: float, job: RefCounted) -> Dictionary:
 var transients: Array[float] = []; var silences: Array[Dictionary] = []
 var threshold := db_to_linear(threshold_db)
 var silence_start := -1; var previous := 0.0; var average := 0.0; var last_attack := -100
 var analyzed_start := float(first) / rate; var analyzed_end := float(first + total) / rate
 var analyzed_duration := float(total) / rate
 var tempo_limited := analyzed_duration > FILE_TEMPO_SECONDS
 var onset := PackedFloat32Array()
 if not tempo_limited: onset.resize(energies.size())
 for i in energies.size():
  if i % 1024 == 0 and job != null:
   if job.is_cancelled(): return {"error": "Cancelled."}
   job.update(0.8 + float(i) / energies.size() * 0.15, "Finding quiet source intervals")
  var local_frame := int(round(float(i) * rate / 100.0))
  var at := float(first + local_frame) / rate
  var energy := energies[i]
  average = average * 0.92 + energy * 0.08
  var flux := maxf(0, energy - previous)
  if not tempo_limited: onset[i] = flux
  if energy > threshold * 2 and flux > maxf(0.012, average * 0.6) and i - last_attack >= 7:
   if transients.size() >= MAX_FILE_TRANSIENTS: return {"error": "More than 65536 attacks were detected. Analyze a shorter source window."}
   transients.append(at); last_attack = i
  if energy < threshold:
   if silence_start < 0: silence_start = local_frame
  elif silence_start >= 0:
   if float(local_frame - silence_start) / rate >= minimum_silence:
    if silences.size() >= MAX_SILENCE_REGIONS: return {"error": "More than 2048 quiet regions were detected. Increase the minimum pause duration or analyze a shorter source window."}
    silences.append({"start": float(first + silence_start) / rate, "end": at})
   silence_start = -1
  previous = energy
 # The final bin can be shorter than 10 ms. Count only its actual frames.
 if silence_start >= 0 and float(total - silence_start) / rate >= minimum_silence:
  if silences.size() >= MAX_SILENCE_REGIONS: return {"error": "More than 2048 quiet regions were detected. Increase the minimum pause duration or analyze a shorter source window."}
  silences.append({"start": float(first + silence_start) / rate, "end": analyzed_end})
 var best := 0.0; var second := 0.0; var best_lag := 0
 if not tempo_limited:
  for lag in range(33, 101):
   if job != null and job.is_cancelled(): return {"error": "Cancelled."}
   var correlation := 0.0
   for i in range(lag, onset.size()): correlation += onset[i] * onset[i - lag]
   if correlation > best: second = best; best = correlation; best_lag = lag
   elif correlation > second: second = correlation
 var confidence := clampf((best - second) / maxf(0.000001, best) * 8, 0, 1)
 return {"error": "", "transients": transients, "silences": silences,
  "peak_db": linear_to_db(maxf(0.000001, peak)), "rms_db": linear_to_db(maxf(0.000001, sqrt(sum_squared / total))),
  "tempo": 6000.0 / best_lag if best_lag > 0 else 0, "confidence": confidence,
  "duration": source_duration, "envelope": energies, "envelope_rate": 100, "envelope_start": analyzed_start,
  "analyzed_start": analyzed_start, "analyzed_end": analyzed_end, "analyzed_duration": analyzed_duration,
  "windowed": first > 0 or analyzed_end < source_duration, "method": "Selected-window native PCM streaming",
  "tempo_limited": tempo_limited, "tempo_duration": 0.0 if tempo_limited else analyzed_duration}

static func analyze(stream: AudioStream, threshold_db: float = -42, minimum_silence: float = 0.25, job: RefCounted = null) -> Dictionary:
 if not is_finite(threshold_db) or threshold_db < -120 or threshold_db > 0 or not is_finite(minimum_silence) or minimum_silence <= 0 or minimum_silence > 600: return {"error": "Invalid silence detector settings."}
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 var problem := silence_source_error(stream)
 if not problem.is_empty(): return {"error": problem}
 var result := KiwiAudioSourceCache.decode(stream, 12000, 0, -1, 600)
 if not str(result.error).is_empty(): return result
 var samples: PackedVector2Array = result.samples
 if samples.is_empty(): return {"error": "Empty recording.", "transients": [], "silences": [], "peak_db": -120, "rms_db": -120, "tempo": 0, "confidence": 0}
 var rate := 12000
 var block := 120
 var energies := PackedFloat32Array()
 var peak := 0.0
 var sum_squared := 0.0
 var total := 0
 for start in range(0, samples.size(), block):
  var power := 0.0
  var count := mini(block, samples.size() - start)
  for i in range(start, start + count):
   var sample := samples[i]
   peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
   power += (sample.x * sample.x + sample.y * sample.y) * 0.5
  energies.append(sqrt(power / maxi(1, count)))
  sum_squared += power; total += count
  if job != null and start % 120000 == 0:
   if job.is_cancelled(): return {"error": "Cancelled."}
   job.update(float(start) / samples.size(), "Analyzing audio")
 var transients: Array[float] = []
 var silences: Array[Dictionary] = []
 var threshold := db_to_linear(threshold_db)
 var silence_start := -1
 var previous := 0.0
 var average := 0.0
 var last_attack := -100
 var onset := PackedFloat32Array(); onset.resize(energies.size())
 for i in energies.size():
  var energy := energies[i]
  average = average * 0.92 + energy * 0.08
  var flux := maxf(0, energy - previous)
  onset[i] = flux
  if energy > threshold * 2 and flux > maxf(0.012, average * 0.6) and i - last_attack >= 7:
   transients.append(i * 0.01); last_attack = i
  if energy < threshold:
   if silence_start < 0: silence_start = i
  elif silence_start >= 0:
   if (i - silence_start) * 0.01 >= minimum_silence: silences.append({"start": silence_start * 0.01, "end": i * 0.01})
   silence_start = -1
  previous = energy
 if silence_start >= 0 and (energies.size() - silence_start) * 0.01 >= minimum_silence:
  silences.append({"start": silence_start * 0.01, "end": float(samples.size()) / rate})
 var best := 0.0; var second := 0.0; var best_lag := 0
 for lag in range(33, 101):
  var correlation := 0.0
  for i in range(lag, onset.size()): correlation += onset[i] * onset[i-lag]
  if correlation > best:
   second = best; best = correlation; best_lag = lag
  elif correlation > second: second = correlation
 var confidence := clampf((best-second) / maxf(0.000001, best) * 8, 0, 1)
 return {"error": "", "transients": transients, "silences": silences, "peak_db": linear_to_db(maxf(0.000001, peak)), "rms_db": linear_to_db(maxf(0.000001, sqrt(sum_squared/maxi(1,total)))), "tempo": 6000.0/best_lag if best_lag > 0 else 0, "confidence": confidence, "duration": float(samples.size())/rate, "envelope": energies, "envelope_rate": 100}

static func nearest_zero(samples: PackedVector2Array, at: int, radius: int = 256, channel: int = -1) -> int:
 if samples.is_empty(): return 0
 at = clampi(at, 0, samples.size()-1)
 var best := at; var score := INF
 for i in range(maxi(1, at-radius), mini(samples.size(), at+radius+1)):
  var a := samples[i-1].x if channel == 0 else (samples[i-1].y if channel == 1 else (samples[i-1].x+samples[i-1].y)*0.5)
  var b := samples[i].x if channel == 0 else (samples[i].y if channel == 1 else (samples[i].x+samples[i].y)*0.5)
  var crossing := a*b <= 0
  var value := absf(b) + absf(i-at) * 0.00002 + (0.0 if crossing else 1.0)
  if value < score: score = value; best = i
 return best

static func edit(samples: PackedVector2Array, operation: String, first: int, last: int, amount: float = 1.0, channel: int = -1, clipboard: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
 first = clampi(first, 0, samples.size()); last = clampi(last, first, samples.size())
 if operation == "trim": return samples.slice(first, last)
 if operation == "cut":
  var remaining := samples.slice(0, first); remaining.append_array(samples.slice(last)); return remaining
 if operation == "paste":
  var pasted := samples.slice(0, first); pasted.append_array(clipboard); pasted.append_array(samples.slice(last)); return pasted
 var output := samples.duplicate()
 var count := last-first
 if count <= 0: return output
 var normalization := 1.0
 if operation == "normalize":
  var peak := 0.0
  for i in range(first,last):
   peak = maxf(peak, absf(samples[i].x) if channel == 0 else (absf(samples[i].y) if channel == 1 else maxf(absf(samples[i].x),absf(samples[i].y))))
  normalization = db_to_linear(amount) / maxf(0.000001, peak)
 for i in range(first,last):
  var old := samples[i]; var value := old
  var ratio := float(i-first)/maxi(1,count-1)
  match operation:
   "set_amplitude": value = Vector2.ONE * clampf(amount,-1.,1.)
   "silence": value = Vector2.ZERO
   "amplify": value *= db_to_linear(amount)
   "normalize": value *= normalization
   "reverse": value = samples[last-1-(i-first)]
   "fade_in": value *= sin(ratio*PI*0.5)
   "fade_out": value *= cos(ratio*PI*0.5)
   "repair":
    var left := samples[maxi(0,first-1)]; var right := samples[mini(samples.size()-1,last)]
    value = left.lerp(right, smoothstep(0,1,ratio))
   "invert": value = -value
   "mono": value = Vector2.ONE * (value.x+value.y)*0.5
  if channel == 0: value.y = old.y
  elif channel == 1: value.x = old.x
  output[i] = value
 return output

static func alignment(reference: PackedVector2Array, candidate: PackedVector2Array, rate: int, max_offset: float = 2.0) -> Dictionary:
 var step := maxi(1, rate/1000)
 var a := PackedFloat32Array(); var b := PackedFloat32Array()
 for i in range(0,mini(reference.size(),rate*20),step): a.append((reference[i].x+reference[i].y)*0.5)
 for i in range(0,mini(candidate.size(),rate*20),step): b.append((candidate[i].x+candidate[i].y)*0.5)
 var bound := mini(2000, int(max_offset*rate/step))
 var best := -INF; var lag_best := 0
 for lag in range(-bound,bound+1):
  var cross := 0.0; var aa := 0.0; var bb := 0.0; var count := 0
  for i in range(maxi(0,-lag),mini(a.size(),b.size()-lag),4):
   cross += a[i]*b[i+lag]; aa += a[i]*a[i]; bb += b[i+lag]*b[i+lag]; count += 1
  var score := cross/sqrt(maxf(0.000000001,aa*bb)) if count > 30 else -INF
  if score > best: best = score; lag_best = lag
 return {"offset": -float(lag_best)*step/rate, "confidence": maxf(0,best)}

static func spectrum(samples: PackedVector2Array, first: int = 0, size: int = 1024) -> PackedFloat32Array:
 size = 1 << clampi(int(round(log(float(maxi(32,size)))/log(2.0))),5,13)
 var real := PackedFloat64Array(); var imaginary := PackedFloat64Array(); real.resize(size); imaginary.resize(size)
 for i in size:
  if first+i < samples.size() and first+i >= 0: real[i] = (samples[first+i].x+samples[first+i].y)*0.5*(0.5-0.5*cos(TAU*i/(size-1)))
 var j := 0
 for i in range(1,size):
  var bit := size >> 1
  while j & bit: j ^= bit; bit >>= 1
  j ^= bit
  if i < j:
   var x := real[i]; real[i]=real[j]; real[j]=x
 var length := 2
 while length <= size:
  var angle := -TAU/length
  var wr_step := cos(angle); var wi_step := sin(angle)
  for start in range(0,size,length):
   var wr := 1.0; var wi := 0.0
   for k in length/2:
    var even := start+k; var odd := even+length/2
    var tr := wr*real[odd]-wi*imaginary[odd]; var ti := wr*imaginary[odd]+wi*real[odd]
    real[odd]=real[even]-tr; imaginary[odd]=imaginary[even]-ti
    real[even]+=tr; imaginary[even]+=ti
    var next := wr*wr_step-wi*wi_step; wi=wr*wi_step+wi*wr_step; wr=next
  length <<= 1
 var magnitudes := PackedFloat32Array(); magnitudes.resize(size/2)
 for i in magnitudes.size(): magnitudes[i]=sqrt(real[i]*real[i]+imaginary[i]*imaginary[i])*4.0/size
 return magnitudes

static func spectrogram(stream: AudioStream, start: float, duration: float, columns: int = 256, rows: int = 128, job: RefCounted = null) -> Dictionary:
 var rate := 12000
 var decoded := KiwiAudioSourceCache.decode(stream,rate,start,minf(duration,60),60)
 if not str(decoded.error).is_empty(): return decoded
 var samples: PackedVector2Array = decoded.samples
 var image := Image.create(columns,rows,false,Image.FORMAT_RGB8)
 for x in columns:
  if job != null and job.is_cancelled(): return {"error": "Cancelled."}
  var magnitudes := spectrum(samples,int(float(x)/columns*samples.size()),1024)
  for y in rows:
   var hz := 30.0*pow(200.0,float(rows-1-y)/maxi(1,rows-1))
   var bin := clampi(int(hz*1024/rate),0,magnitudes.size()-1)
   var value := clampf((linear_to_db(maxf(0.000001,magnitudes[bin]))+85)/85,0,1)
   image.set_pixel(x,y,Color.from_hsv(0.68-value*0.62,0.9,clampf(value*1.4,0,1)))
  if job != null: job.update(float(x)/columns,"Building spectrogram")
 return {"image": image, "error": "", "start": start, "duration": minf(duration,60), "rate": rate}

static func remap_edit_boundary(position:float,first:float,last:float,inserted:float)->float:
 if position<=first:return position
 if position>=last:return position+inserted-(last-first)
 return first+(position-first)/maxf(1,last-first)*inserted

static func loudness(source:Variant,job:RefCounted=null)->Dictionary:
 var encoder:=ActorVideo.executable("ffmpeg")
 if encoder.is_empty():return {"error":"FFmpeg is required for integrated loudness analysis."}
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 var path:=ProjectSettings.globalize_path(str(source)) if source is String else directory.path_join("source.wav")
 var stream:=ActorAudio.source(source,job)
 if stream==null:KiwiAudioRenderer._remove_owned(directory);return {"error":"Missing or unreadable audio."}
 if not source is String:
  var wav:AudioStreamWAV=stream as AudioStreamWAV
  if wav==null:
   var decoded:=KiwiAudioSourceCache.decode(stream,48000)
   if not str(decoded.get("error","")).is_empty():KiwiAudioRenderer._remove_owned(directory);return decoded
   wav=KiwiAudioSourceCache.to_wav(decoded.samples,48000)
  if wav.save_to_wav(path)!=OK:KiwiAudioRenderer._remove_owned(directory);return {"error":"Could not create the temporary analysis source."}
 var result:=KiwiAudioRenderer.execute(encoder,PackedStringArray(["-nostdin","-hide_banner","-v","info","-threads","1","-i",path,"-af","loudnorm=I=-16:TP=-1:LRA=11:print_format=json","-f","null","-"]),stream.get_length(),job)
 KiwiAudioRenderer.finish_process_files(result,directory)
 if not bool(result.get("success",false)):return result
 var log:=str(result.get("diagnostics",""));var first:=log.rfind("{");var last:=log.rfind("}")
 if first<0 or last<first:return {"error":"The encoder did not return loudness measurements."}
 var values:Variant=JSON.parse_string(log.substr(first,last-first+1))
 if not values is Dictionary:return {"error":"Invalid loudness measurement response."}
 var integrated:=str(values.get("input_i","-inf"));var peak:=str(values.get("input_tp","-inf"))
 return {"error":"","integrated_lufs":float(integrated) if integrated not in ["-inf","inf","nan"] else -120.0,"true_peak_db":float(peak) if peak not in ["-inf","inf","nan"] else -120.0,"loudness_range":float(values.get("input_lra",0)),"silent":integrated=="-inf","method":"FFmpeg loudnorm / EBU R128"}

static func transform_selection(samples:PackedVector2Array,operation:String,first:int,last:int,amount:float,channel:int,rate:int,job:RefCounted=null)->Dictionary:
 first=clampi(first,0,samples.size());last=clampi(last,first,samples.size())
 if last<=first:return {"error":"Select audio to process."}
 if operation not in ["time_stretch","pitch_shift"]:return {"error":"Unknown time/pitch operation."}
 if operation=="time_stretch" and channel!=-1:return {"error":"Choose Stereo for duration-changing edits so the channels remain aligned."}
 var encoder:=ActorVideo.executable("ffmpeg")
 if encoder.is_empty():return {"error":"FFmpeg is required for sample-selection pitch and time processing."}
 var factor:=clampf(amount,0.25,4) if operation=="time_stretch" else 1.0
 var count:=maxi(1,int(round((last-first)*factor)))
 if (samples.size()-(last-first)+count)*8>KiwiAudioSourceCache.MAX_DECODE_BYTES:return {"error":"The stretched selection would exceed the 128 MiB working-buffer limit."}
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 var input:=directory.path_join("selection.wav");var output:=directory.path_join("processed.wav")
 var stream:=KiwiAudioSourceCache.to_wav(samples.slice(first,last),rate,true)
 if stream.save_to_wav(input)!=OK:KiwiAudioRenderer._remove_owned(directory);return {"error":"Could not prepare the selected audio."}
 var filter:=KiwiAudioEffects.tempo_filter(1.0/factor)
 if operation=="pitch_shift":
  var effect:=KiwiAudioEffects.create("pitch");effect.parameters.semitones=clampf(amount,-24,24);filter=KiwiAudioEffects.offline_filter(effect,rate)
 filter+=",apad,atrim=end_sample=%d,asetpts=PTS-STARTPTS"%count
 var result:=KiwiAudioRenderer.execute(encoder,PackedStringArray(["-nostdin","-hide_banner","-v","error","-threads","1","-i",input,"-af",filter,"-ar",str(rate),"-ac","2","-c:a","pcm_s16le","-y",output]),float(count)/rate,job)
 if not bool(result.get("success",false)):
  KiwiAudioRenderer.finish_process_files(result,directory)
  return result
 var transformed:=AudioStreamWAV.load_from_file(output)
 if transformed==null:KiwiAudioRenderer._remove_owned(directory);return {"error":"Could not decode the processed selection."}
 var decoded:=KiwiAudioSourceCache.decode(transformed,rate)
 KiwiAudioRenderer._remove_owned(directory)
 if not str(decoded.get("error","")).is_empty():return decoded
 var segment:PackedVector2Array=decoded.samples;segment.resize(count)
 if channel>=0:
  for i in segment.size():
   if channel==0:segment[i].y=samples[first+i].y
   else:segment[i].x=samples[first+i].x
 # Blend a short boundary guard against the original endpoints to avoid introducing a hard splice.
 var guard:=mini(segment.size()/2,maxi(1,int(rate*0.001)))
 for i in guard:
  var blend:=float(i+1)/(guard+1)
  var left:=samples[first+i].lerp(segment[i],blend)
  var right:=samples[last-1-i].lerp(segment[segment.size()-1-i],blend)
  segment[i]=left;segment[segment.size()-1-i]=right
 var merged:=samples.slice(0,first);merged.append_array(segment);merged.append_array(samples.slice(last))
 return {"error":"","samples":merged,"inserted_frames":count}

static func noise_profile(stream:AudioStream,start:float,seconds:float,job:RefCounted=null)->Dictionary:
 if stream==null or seconds<0.05:return {"error":"Select at least 50 ms of noise without speech or music."}
 var encoder:=ActorVideo.executable("ffmpeg")
 if encoder.is_empty():return {"error":"FFmpeg is required for learning a spectral noise profile."}
 seconds=minf(seconds,10.0)
 var decoded:=KiwiAudioSourceCache.decode(stream,48000,start,seconds,10)
 if not str(decoded.get("error","")).is_empty():return decoded
 var samples:PackedVector2Array=decoded.samples
 if samples.size()<2400:return {"error":"The selected noise region is too short."}
 var sum:=0.0
 for value in samples:sum+=value.length_squared()*0.5
 var rms:=sqrt(sum/samples.size())
 if rms<0.000001:return {"error":"The selected region is effectively silent; there is no usable noise profile."}
 var measured_seconds:=samples.size()/48000.0
 samples.resize(samples.size()+4800)
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 var path:=directory.path_join("noise.wav")
 if KiwiAudioSourceCache.to_wav(samples,48000).save_to_wav(path)!=OK:KiwiAudioRenderer._remove_owned(directory);return {"error":"Could not prepare the noise selection."}
 var filter:="asendcmd=c='0 afftdn sn start;%s afftdn sn stop',afftdn"%KiwiAudioEffects.number(measured_seconds)
 var result:=KiwiAudioRenderer.execute(encoder,PackedStringArray(["-nostdin","-hide_banner","-v","info","-threads","1","-i",path,"-af",filter,"-f","null","-"]),measured_seconds,job)
 KiwiAudioRenderer.finish_process_files(result,directory)
 if not bool(result.get("success",false)):return result
 var profiles:Array=[]
 for line in str(result.get("diagnostics","")).split("\n"):
  var index:=line.find("bn=")
  if index<0:continue
  var values:Array=[]
  for text in line.substr(index+3).split(" ",false):
   if text.is_valid_float():values.append(clampf(float(text),-24,24))
  if values.size()==15:profiles.append(values)
 if profiles.is_empty():return {"error":"This FFmpeg build did not return a learned spectral noise profile."}
 var bands:Array=[]
 for i in 15:
  var value:=0.0
  for profile in profiles:value+=float(profile[i])
  bands.append(value/profiles.size())
 return {"error":"","noise_profile":bands,"floor":clampf(linear_to_db(rms),-80,-20),"rms_db":linear_to_db(rms),"seconds":measured_seconds,"start":start}

# Short, isolated source-join audition only. No timeline render or source write.
# The player uses speed; these source-rate fades match the new seam envelopes.
# Pass the ORIGINAL source value, not ActorAudio.source(long_pcm_path).
static func silence_boundary_audio(value: Variant, boundary: Dictionary, job: RefCounted = null) -> Dictionary:
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 var speed := float(boundary.get("speed", 0.0))
 if not is_finite(speed) or speed <= 0 or speed > 16: return {"error": "Unsupported audition speed."}
 var prepared := _silence_audition_windows(boundary, speed)
 if not str(prepared.get("error", "")).is_empty(): return prepared
 if value is String and value.get_extension().to_lower() == "wav":
  var info := KiwiAudioPCMFile.inspect(value)
  if not str(info.get("error", "invalid")).is_empty(): return {"error": "Boundary audition requires supported mono/stereo PCM WAV. " + str(info.get("error", "Invalid WAV metadata."))}
  return _pcm_silence_boundary(value, info, prepared.windows, speed, str(boundary.get("fade_curve", "linear")), job)
 var problem := silence_source_error(value)
 if not problem.is_empty(): return {"error": problem}
 var signature := _analysis_file_signature(str(value)) if value is String else {}
 if value is String and signature.is_empty(): return {"error": "The source is unavailable for audition."}
 var stream := ActorAudio.source(value, job)
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if stream == null: return {"error": "The source is unavailable for audition."}
 problem = silence_source_error(stream)
 if not problem.is_empty(): return {"error": problem}
 var output := PackedVector2Array(); var rate := 12000
 for window: Dictionary in prepared.windows:
  var first := float(window.start); var end := float(window.end)
  if end <= first: continue
  if end > stream.get_length() + 0.0001: return {"error": "The source ended before the audition boundary."}
  if job != null and job.is_cancelled(): return {"error": "Cancelled."}
  var decoded := KiwiAudioSourceCache.decode(stream, rate, first, end - first, 6.0)
  if not str(decoded.get("error", "")).is_empty(): return decoded
  var samples: PackedVector2Array = decoded.samples
  if samples.size() != int(round((end - first) * rate)): return {"error": "The source ended before the audition boundary."}
  var fade := float(window.fade) * rate
  for i in samples.size():
   if i % 16384 == 0 and job != null and job.is_cancelled(): return {"error": "Cancelled."}
   var distance := float(samples.size() - 1 - i) if bool(window.left) else float(i)
   if fade > 0 and distance < fade:
    var gain := clampf(distance / fade, 0.0, 1.0)
    samples[i] *= sin(gain * PI * 0.5) if str(boundary.get("fade_curve", "linear")) == "equal_power" else gain
  output.append_array(samples)
 if output.is_empty(): return {"error": "No retained audio borders this removal."}
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if value is String and signature != _analysis_file_signature(str(value)): return {"error": "The source changed during audition preparation. Analyze it again."}
 return {"error": "", "stream": KiwiAudioSourceCache.to_wav(output, rate, true), "speed": speed, "seconds": float(output.size()) / rate / speed}

static func _silence_audition_windows(boundary: Dictionary, speed: float) -> Dictionary:
 var windows: Array[Dictionary] = []
 for side in ["left", "right"]:
  var interval: Variant = boundary.get(side, Vector2.ZERO)
  var first := 0.0; var end := 0.0
  if interval is Vector2:
   first = interval.x; end = interval.y
  elif interval is Dictionary:
   var a: Variant = interval.get("start"); var b: Variant = interval.get("end")
   if not (a is float or a is int) or not (b is float or b is int): return {"error": "Invalid audition window."}
   first = float(a); end = float(b)
  else: return {"error": "Invalid audition window."}
  if not is_finite(first) or not is_finite(end) or first < 0 or end < first or end - first > 0.35 * speed + 0.000001: return {"error": "Invalid audition window."}
  var fade := float(boundary.get("fade_out" if side == "left" else "fade_in", 0.0)) * speed
  if not is_finite(fade) or fade < 0 or fade > 1.0: return {"error": "Invalid audition fade."}
  windows.append({"start": first, "end": end, "fade": fade, "left": side == "left"})
 return {"error": "", "windows": windows}

static func _pcm_silence_boundary(path: String, info: Dictionary, windows: Array, speed: float, curve: String, job: RefCounted) -> Dictionary:
 var rate := int(info.rate); var source_duration := float(info.duration)
 if not is_finite(source_duration) or source_duration <= 0 or source_duration > MAX_FILE_SOURCE_SECONDS: return {"error": "PCM dialogue sources must be nonempty and at most 24 hours long."}
 var total := 0
 for window: Dictionary in windows:
  if float(window.end) > source_duration + 0.000001: return {"error": "The source ended before the audition boundary."}
  window.first_frame = int(round(float(window.start) * rate))
  window.frames = int(round(float(window.end) * rate)) - int(window.first_frame)
  if int(window.first_frame) < 0 or int(window.frames) < 0 or int(window.first_frame) + int(window.frames) > int(info.frames): return {"error": "Invalid PCM audition frame window."}
  total += int(window.frames)
 # Two 0.35-second playback windows at speed <=16 and rate <=192 kHz.
 # Keep an independent allocation bound even if window validation changes.
 if total <= 0: return {"error": "No retained audio borders this removal."}
 if total > 2150402 or total * 8 > KiwiAudioSourceCache.MAX_DECODE_BYTES: return {"error": "The PCM audition exceeds its short-window memory bound."}
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return {"error": "Could not open the PCM source for audition."}
 if not _pcm_file_current(path, info, file, true): file.close(); return {"error": "The PCM source changed before audition preparation. Analyze it again."}
 # Encode the bounded audition directly; do not allocate another full float
 # buffer or defer cancellation through a multi-million-frame conversion.
 var output := PackedByteArray(); output.resize(total * 4)
 var written := 0; var checked := Time.get_ticks_msec()
 for window: Dictionary in windows:
  var cursor := 0; var frames := int(window.frames); var fade := float(window.fade) * rate
  while cursor < frames:
   if job != null and job.is_cancelled(): file.close(); return {"error": "Cancelled."}
   if Time.get_ticks_msec() - checked >= 1000:
    checked = Time.get_ticks_msec()
    if not _pcm_file_current(path, info, file): file.close(); return {"error": "The PCM source changed during audition preparation. Analyze it again."}
   var count := mini(KiwiAudioPCMFile.MAX_READ_FRAMES, frames - cursor)
   var samples := KiwiAudioPCMFile.read_frames(file, info, int(window.first_frame) + cursor, count)
   if samples.size() != count: file.close(); return {"error": "The PCM source ended before the audition boundary."}
   for i in samples.size():
    var distance := float(frames - 1 - cursor - i) if bool(window.left) else float(cursor + i)
    var gain := clampf(distance / fade, 0.0, 1.0) if fade > 0 else 1.0
    if curve == "equal_power": gain = sin(gain * PI * 0.5)
    var sample := samples[i] * gain
    output.encode_s16((written + i) * 4, clampi(int(round(clampf(sample.x, -1.0, 1.0) * 32768.0)), -32768, 32767))
    output.encode_s16((written + i) * 4 + 2, clampi(int(round(clampf(sample.y, -1.0, 1.0) * 32768.0)), -32768, 32767))
   cursor += count; written += count
   if job != null: job.update(float(written) / total, "Preparing bounded PCM boundary audition")
 if not _pcm_file_current(path, info, file, true): file.close(); return {"error": "The PCM source changed during audition preparation. Analyze it again."}
 file.close()
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 var stream := AudioStreamWAV.new()
 stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = rate; stream.stereo = true; stream.data = output
 if job != null and job.is_cancelled(): return {"error": "Cancelled."}
 if not _pcm_file_current(path, info, null, true): return {"error": "The PCM source changed during audition preparation. Analyze it again."}
 return {"error": "", "stream": stream, "speed": speed, "seconds": float(total) / rate / speed, "source_signature": info.duplicate()}

static func silence_source_error(value: Variant) -> String:
 if value is AudioStream:
  if not is_finite(value.get_length()) or value.get_length() <= 0 or value.get_length() > 600.0: return "Dialogue analysis requires a nonempty source of at most 600 seconds. Render or split it to a shorter source first."
  return ""
 if not value is String or value.is_empty(): return "Missing audio source."
 if value.get_extension().to_lower() == "wav":
  var info := KiwiAudioPCMFile.inspect(value)
  if not str(info.get("error", "invalid")).is_empty(): return "Dialogue analysis requires supported mono/stereo PCM WAV. " + str(info.get("error", "Invalid WAV metadata."))
  var seconds := float(info.duration)
  if not is_finite(seconds) or seconds <= 0 or seconds > MAX_FILE_SOURCE_SECONDS: return "PCM dialogue sources must be nonempty and at most 24 hours long."
  return ""
 var file := FileAccess.open(value, FileAccess.READ)
 if file == null: return "Missing or unreadable audio source."
 var bytes := file.get_length(); file.close()
 if bytes <= 0 or bytes > 64 * 1024 * 1024: return "Non-PCM dialogue analysis requires a source file of at most 64 MiB and at most 600 seconds. Use mono/stereo PCM WAV for bounded long-source analysis."
 return ""
