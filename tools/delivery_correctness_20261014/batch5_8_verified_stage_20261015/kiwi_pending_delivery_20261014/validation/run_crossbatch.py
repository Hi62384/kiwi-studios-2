"""Run archived focused suites against final batch-8 source; no native project writes.
Only harness declarations/stubs are adapted for newer unrelated APIs. Full
production copies and extracted function bodies come from the final candidate.
"""
from pathlib import Path
import argparse,json,hashlib,os,re,shutil,subprocess,sys,zipfile,datetime
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--batches',default='3,4,5,6');a=p.parse_args()
r=Path(__file__).resolve().parents[1];v=r/'validation';ledger=json.loads((r/'ordered_delivery_ledger.json').read_text())
h=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
expected=ledger['states'][-1]['files'];assert all(h(a.source/name)==sha for name,sha in expected.items())
def extract(s,name):
 m=re.search(r'^(?:static )?func '+re.escape(name)+r'\(',s,re.M);assert m,name
 n=re.search(r'^(?:static )?func ',s[m.end():],re.M)
 return s[m.start():m.end()+n.start() if n else len(s)].rstrip()+'\n'
env=os.environ.copy()
for key,dirname in [('HOME','home'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
 directory=v/'godot_home'/dirname;directory.mkdir(parents=True,exist_ok=True);env[key]=str(directory)
report={'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'final_revision':'kiwi-recovery-checkpoints-20261014','suites':{},'production_edits':False,'mocks':'Same focused historical test mocks, plus newer unrelated dependencies and silence-review no-op hooks; cross-flow tests separately use actual silence core/UI methods.'}
ws=(a.source/'Workspaces/AudioWorkspace/audio_workspace.gd').read_text()
for batch in [int(x) for x in a.batches.split(',')]:
 step=ledger['steps'][batch-1];archive=a.archives/step['archive_name'];assert h(archive)==step['archive_sha256']
 out=v/'archive_runs'/str(batch);out.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  for name in z.namelist():assert not name.startswith('/') and '..' not in Path(name).parts and '\\' not in name
  z.extractall(out)
 root=out/step['package_root'];shutil.copytree(a.source,root/'candidate',dirs_exist_ok=True)
 subprocess.run([sys.executable,str(root/'validation/prepare_harness.py')],check=True,stdout=subprocess.DEVNULL)
 if batch==4:subprocess.run([sys.executable,str(root/'validation/prepare_workspace_harness.py')],check=True,stdout=subprocess.DEVNULL)
 projects=[root/'validation/candidate']+([root/'validation/workspace_candidate'] if batch==4 else [])
 for project in projects:
  seams=[]
  # Compile newer core APIs with their real dependencies. Historical tests do
  # not call these through stubs; their new workflows have the batch-7 suite.
  for name in ['audio_analysis.gd','audio_region_edit.gd','audio_source_cache.gd','audio_jobs.gd','audio_pcm_file.gd']:
   shutil.copyfile(a.source/'Workspaces/AudioWorkspace'/name,project/name)
  for name in ['actor_object_data.gd','actor_object_reference.gd','actor_animation_track.gd','actor_keyframe.gd']:
   if not (project/name).exists():shutil.copyfile(a.source/'scripts/actors/core'/name,project/name)
  for old in ['source_cache.gd','pcm_stub.gd']:(project/old).unlink(missing_ok=True)
  if batch==4:
   shutil.copyfile(a.source/'scripts/actors/core/actor_audio.gd',project/'actor_audio.gd')
  if batch==3:
   with (project/'actor_audio.gd').open('a') as f:f.write('\nconst MAX_NATIVE_WAV_BYTES:=67108864\nstatic func invalidate(_path:String)->void:pass\nstatic func needs_file_preview(_value:Variant)->bool:return false\nstatic func source(value:Variant,_job:RefCounted=null)->AudioStream:return value if value is AudioStream else null\nstatic func source_stamp(value:Variant)->Dictionary:return {"key":str(value),"missing":value==null}\nstatic func pcm_info(_path:String)->Dictionary:return {"error":"unused in this harness"}\n')
   seams.append('Retained historical fail_duration ActorAudio mock; newer relink declarations are not exercised in this suite')
  for name in ['encoder_stub.gd','video_stub.gd']:
   source=v/'stubs'/name
   if source.exists():shutil.copyfile(source,project/name)
  effects=next((x for x in [project/'effects_stub.gd',project/'effects.gd'] if x.exists()),None)
  if effects is None:
   effects=project/'effects_stub.gd';effects.write_text('class_name KiwiAudioEffects\nextends RefCounted\n')
  if effects:
   s=effects.read_text()
   methods={'number':'static func number(value:float)->String:return str(value)','tempo_filter':'static func tempo_filter(_value:float)->String:return ""','create':'static func create(_kind:String)->Dictionary:return {"parameters":{}}','offline_filter':'static func offline_filter(_effect:Dictionary,_rate:int)->String:return ""','tail_seconds':'static func tail_seconds(_stack:Array)->float:return 0.0'}
   for name,line in methods.items():
    if 'func '+name+'(' not in s:s+='\n'+line+'\n'
   effects.write_text(s)
  renderer=next((x for x in [project/'renderer_stub.gd',project/'renderer.gd'] if x.exists()),project/'renderer_stub.gd')
  s=renderer.read_text() if renderer.exists() else 'class_name KiwiAudioRenderer\nextends RefCounted\n'
  for name,line in {'execute':'static func execute(_encoder:String,_args:PackedStringArray,_duration:float,_job:RefCounted=null)->Dictionary:return {"error":"encoder mocked"}','finish_process_files':'static func finish_process_files(_result:Dictionary,_directory:String)->void:pass','_remove_owned':'static func _remove_owned(_path:String)->PackedStringArray:return PackedStringArray()'}.items():
   if 'func '+name+'(' not in s:s+='\n'+line+'\n'
  renderer.write_text(s)
  harness=project/'workspace_harness.gd'
  if harness.exists():
   s=harness.read_text();s+='\nvar _silence_review:Dictionary={}\nvar _silence_check_at:=0\nfunc _close_silence_review(_token:int=-1)->void:pass\nfunc _stop_silence_audition(_token:int)->void:pass\nfunc _silence_review_current(_token:int)->bool:return false\n'
   s+='func _close_recovery_review()->void:pass\nfunc _recovery_tick()->void:pass\nfunc _queue_recovery_checkpoint(_manual:bool=false)->void:pass\n'
   if batch==4:s+='func _refresh_analysis()->void:pass\nfunc notice(_message:String)->void:pass\n'
   harness.write_text(s);seams.append('Silence-review hooks are no-op in historical fixtures; tested with real handlers separately')
  integration=project/'playback_integration_harness.gd'
  if integration.exists():
   with integration.open('a') as f:f.write('\nvar _recording_file_token:Dictionary={}\nvar _recording_file_owner:WeakRef\n')
   seams.append('Added current recording-token fields to historical playback prefix')
  result={'harness_seams':seams,'full_class_sha256':{name:h(project/name) for name in ['audio_edit_session.gd','audio_document.gd','audio_analysis.gd','audio_region_edit.gd','audio_source_cache.gd']},'stages':{}}
  for stage,cmd in [('import',['--editor','--import','--quit']),('run',['--script','run.gd'])]:
   command=['godot','--headless','--path',str(project),*cmd]
   try:run=subprocess.run(command,env=env,capture_output=True,text=True,timeout=30);log=run.stdout+run.stderr;code=run.returncode
   except subprocess.TimeoutExpired as error:
    log=(error.stdout or b'').decode(errors='replace')+(error.stderr or b'').decode(errors='replace');code=124
   logfile=v/f'crossbatch_{batch}_{project.name}_{stage}.log';logfile.write_text(log)
   result['stages'][stage]={'exit_code':code,'errors':len(re.findall(r'^(?:SCRIPT )?ERROR:',log,re.M)),'warnings':len(re.findall(r'^WARNING:',log,re.M)),'log':logfile.name}
   if stage=='run':result['result_lines']=[line for line in log.splitlines() if 'CHECKS=' in line or 'FAILURES=' in line or 'failures' in line.lower()]
  result['pass']=all(x['exit_code']==0 and x['errors']==0 and x['warnings']==0 for x in result['stages'].values())
  report['suites'][str(batch)+'_'+project.name]=result
report['pass']=all(x['pass'] for x in report['suites'].values());(v/'crossbatch_results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));sys.exit(0 if report['pass'] else 1)
