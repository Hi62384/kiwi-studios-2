extends RefCounted
## Post-fader/pre-send route peaks tapped from the SAME offline render graph.
## Bounded 20 Hz data for previews <=10 minutes and <=32 routes.
const HZ:=20
const MAX_SECONDS:=600.
const MAX_ROUTES:=32
const MAX_LOG_BYTES:=4*1024*1024

static func enabled(document:KiwiAudioDocument,options:Dictionary)->bool:
	var seconds:=float(options.get("duration",document.duration()-float(options.get("start",0))))
	return bool(options.get("route_meters",false)) and document.tracks.size()<=MAX_ROUTES and seconds>0 and seconds<=MAX_SECONDS

static func tap(filters:PackedStringArray,label:String,index:int,directory:String,start:float,duration:float,rate:int)->Dictionary:
	var output:="meter_audio_%d"%index;var branch:="meter_branch_%d"%index
	filters.append("[%s]asplit=2[%s][%s]"%[label,output,branch])
	var chain:="atrim=start=%s:duration=%s,asetpts=PTS-STARTPTS,asetnsamples=n=%d:p=0,astats=metadata=1:reset=1:measure_perchannel=Peak_level:measure_overall=none"%[KiwiAudioEffects.number(start),KiwiAudioEffects.number(duration),maxi(1,rate/HZ)]
	var paths:Array=[]
	for channel in 2:
		var path:=directory.path_join("meter_%d_%d.txt"%[index,channel]);paths.append(path)
		var escaped:=path.replace("\\","/").replace(":","\\:").replace("'","'\\''")
		chain+=",ametadata=mode=print:key=lavfi.astats.%d.Peak_level:file='%s':direct=1"%[channel+1,escaped]
	filters.append("[%s]%s,anullsink"%[branch,chain])
	return {"filters":filters,"label":output,"paths":paths}

static func read(routes:Array,duration:float)->Dictionary:
	var result:Dictionary={}
	var frames:=mini(ceili(MAX_SECONDS*HZ)+2,ceili(duration*HZ)+2)
	for route in routes:
		var levels:=PackedVector2Array();levels.resize(frames);levels.fill(Vector2(-80,-80));var valid:=true
		for channel in 2:
			var file:=FileAccess.open(str(route.paths[channel]),FileAccess.READ)
			if file==null or file.get_length()>MAX_LOG_BYTES:valid=false;break
			var index:=0
			while not file.eof_reached():
				var line:=file.get_line()
				if line.begins_with("frame:"):
					var marker:=line.find("pts_time:")
					if marker>=0:index=roundi(float(line.substr(marker+9))*HZ)
				elif line.begins_with("lavfi.astats.") and index>=0 and index<frames:
					var text:=line.get_slice("=",1).strip_edges();var db:=clampf(float(text),-80,24) if text.is_valid_float() else -80.
					var value:=levels[index];value[channel]=db;levels[index]=value
			file.close()
		if valid:result[str(route.id)]=levels
	return result
