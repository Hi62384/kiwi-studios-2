extends RefCounted
## Conservative, offline multiband decay suppression. Not blind source
## separation or a reconstruction of a dry room. Can attenuate musical tails.
const MAX_BYTES:=64*1024*1024
const BLOCK:=256
const CROSSOVERS:=[200.,500.,1200.,3000.,7000.]

static func process_f32(input_path:String,output_path:String,effect:Dictionary,rate:int,job:RefCounted=null)->Dictionary:
	if input_path==output_path or FileAccess.file_exists(output_path):return {"success":false,"error":"Restoration requires a new temporary output."}
	var file:=FileAccess.open(input_path,FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES or file.get_length()%8!=0:return {"success":false,"error":"Decay suppression supports stereo float stages up to 64 MiB. Split/bake a shorter region."}
	for curve in effect.get("automation",{}).values():
		if not curve.is_empty():file.close();return {"success":false,"error":"Decay suppression currently uses static controls; remove its parameter automation."}
	var frames:=file.get_length()/8;var output:=FileAccess.open(output_path,FileAccess.WRITE)
	if output==null:file.close();return {"success":false,"error":"Could not open the restoration output."}
	var p:Dictionary=effect.get("parameters",{});var strength:=clampf(float(p.get("strength",.6)),0,1);var decay:=clampf(float(p.get("decay",.6)),.05,2.);var floor_gain:=db_to_linear(clampf(float(p.get("floor",-12)),-30,0))
	var states:Array[Vector2]=[];var peaks:Array[float]=[];var gains:Array[float]=[];var alphas:Array[float]=[]
	for hz in CROSSOVERS:states.append(Vector2.ZERO);alphas.append(1.-exp(-TAU*minf(float(hz),rate*.4)/rate))
	for band in CROSSOVERS.size()+1:peaks.append(0.);gains.append(1.)
	var cursor:=0;var started:=Time.get_ticks_msec();var error:=""
	while cursor<frames:
		if Time.get_ticks_msec()-started>60000:error="Decay suppression exceeded its 60-second processing budget. Split a shorter region.";break
		if job!=null and job.is_cancelled():error="Cancelled.";break
		var count:=mini(BLOCK,frames-cursor);var bytes:=file.get_buffer(count*8)
		if bytes.size()!=count*8:error="The staged audio ended unexpectedly.";break
		var bands:Array[PackedVector2Array]=[];var energy:Array[float]=[]
		for band in CROSSOVERS.size()+1:
			var values:=PackedVector2Array();values.resize(count);bands.append(values);energy.append(0.)
		for i in count:
			var value:=Vector2(bytes.decode_float(i*8),bytes.decode_float(i*8+4))
			if not is_finite(value.x) or not is_finite(value.y):error="Non-finite staged restoration audio.";break
			var previous:=Vector2.ZERO
			for band in CROSSOVERS.size():
				states[band]=states[band].lerp(value,alphas[band]);var component:=states[band]-previous;previous=states[band];bands[band][i]=component;energy[band]+=component.length_squared()*.5
			bands.back()[i]=value-previous;energy[energy.size()-1]+=(value-previous).length_squared()*.5
		if not error.is_empty():break
		var targets:Array[float]=[]
		for band in energy.size():
			var rms:=sqrt(energy[band]/count);peaks[band]=maxf(rms,peaks[band]*exp(-6.907755*float(count)/rate/decay))
			var fall:=clampf((1.-rms/maxf(.00000001,peaks[band]))/.65,0,1)
			targets.append(maxf(floor_gain,1.-strength*fall))
		for i in count:
			var value:=Vector2.ZERO
			for band in bands.size():value+=bands[band][i]*lerpf(gains[band],targets[band],float(i+1)/count)
			bytes.encode_float(i*8,value.x);bytes.encode_float(i*8+4,value.y)
		gains=targets;output.store_buffer(bytes)
		if output.get_error()!=OK:error="Could not write the restoration output.";break
		cursor+=count
		if job!=null:job.update(float(cursor)/maxi(1,frames),"Suppressing diffuse decay (multiband)")
	file.close();output.close()
	if not error.is_empty():DirAccess.remove_absolute(output_path);return {"success":false,"error":error}
	return {"success":true,"error":"","duration":float(frames)/rate}

static func breath_candidates(source:Variant,start:float,duration:float,job:RefCounted=null)->Dictionary:
	if duration<=0 or duration>60:return {"error":"Breath review supports a source window up to 60 seconds; split a shorter dialogue clip."}
	var stream:=ActorAudio.source(source,job)
	if stream==null:return {"error":"The dialogue source is unavailable."}
	var decoded:=KiwiAudioSourceCache.decode(stream,24000,start,duration,60)
	if not str(decoded.get("error","")).is_empty():return decoded
	var samples:PackedVector2Array=decoded.samples;var hop:=480;var regions:Array=[];var first:=-1
	for frame in range(0,samples.size(),hop):
		if job!=null and job.is_cancelled():return {"error":"Cancelled."}
		var end:=mini(samples.size(),frame+hop);var power:=0.;var peak:=0.;var crossings:=0;var previous:=0.
		for i in range(frame,end):
			var value:float=(samples[i].x+samples[i].y)*.5;power+=value*value;peak=maxf(peak,absf(value));crossings+=1 if value*previous<0 else 0;previous=value
		var rms:=sqrt(power/maxi(1,end-frame));var db:=linear_to_db(maxf(.000001,rms))
		var candidate:=db > -55 and db < -16 and float(crossings)/maxi(1,end-frame)>.12 and peak/maxf(.000001,rms)<5.
		if candidate and first<0:first=frame
		if first>=0 and (not candidate or end==samples.size()):
			var last:=frame if not candidate else end;var seconds:=float(last-first)/24000
			if seconds>=.05 and seconds<=.8:regions.append({"start":start+float(first)/24000,"end":start+float(last)/24000})
			first=-1
	return {"error":"","regions":regions}
