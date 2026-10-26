extends RefCounted
## Bounded optional CLI invocation. No shell interpolation or credential argv.
static func run(executable:String,args:PackedStringArray,input:String="",job:RefCounted=null,seconds:float=60.,max_bytes:int=2097152)->Dictionary:
	if job!=null and job.is_cancelled():return {"success":false,"error":"Cancelled."}
	var process:=OS.execute_with_pipe(executable,args,false)
	if process.is_empty():return {"success":false,"error":"Could not start the configured optional tool."}
	var pipe:FileAccess=process.stdio;var errors:FileAccess=process.stderr
	if not input.is_empty():pipe.store_buffer((input+"\n").to_utf8_buffer())
	var output:=PackedByteArray();var total:=0;var deadline:=Time.get_ticks_msec()+int(clampf(seconds,1,1800)*1000);var problem:="";var exited:=false
	while true:
		for unused in 8:
			var block:=KiwiAudioEncoderProcess._available(pipe);var diagnostic:=KiwiAudioEncoderProcess._available(errors)
			total+=block.size()+diagnostic.size()
			if output.size()+block.size()<=max_bytes:output.append_array(block)
			if block.is_empty() and diagnostic.is_empty():break
		if total>max_bytes:problem="Optional tool exceeded its output limit."
		if job!=null and job.is_cancelled():problem="Cancelled."
		if Time.get_ticks_msec()>=deadline:problem="Optional tool exceeded its time limit."
		if not problem.is_empty():
			if OS.is_process_running(process.pid):exited=OS.kill(process.pid)==OK
			else:exited=true
			break
		if not OS.is_process_running(process.pid):exited=true;break
		OS.delay_msec(10)
	var code:=OS.get_process_exit_code(process.pid)
	# Drain final buffered stdout without releasing/reopening the process pipes.
	for unused in 8:
		var block:=KiwiAudioEncoderProcess._available(pipe)
		if block.is_empty():break
		if output.size()+block.size()>max_bytes:problem="Optional tool exceeded its output limit.";break
		output.append_array(block)
	pipe.close();errors.close()
	if problem.is_empty() and code!=0:problem="Optional tool failed. Check its executable/model configuration."
	return {"success":problem.is_empty(),"error":problem,"stdout":output.get_string_from_utf8() if problem.is_empty() else "","process_exited":exited}
