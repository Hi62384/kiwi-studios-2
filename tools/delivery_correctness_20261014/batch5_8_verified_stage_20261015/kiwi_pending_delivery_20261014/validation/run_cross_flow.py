from pathlib import Path
import argparse,re,json,hashlib,os,shutil,subprocess,sys,datetime
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--batch7-package',type=Path,required=True);a=p.parse_args()
v=Path(__file__).resolve().parent
subprocess.run([sys.executable,str(a.batch7_package/'validation/prepare_harness.py')],check=True)
out=v/'cross_flow';shutil.copytree(a.batch7_package/'validation/candidate',out,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.godot','*.log'))
# Overlay actual final full classes, not the historical batch7 copies.
for item in a.source.rglob('*.gd'):
 if (out/item.name).is_file():shutil.copyfile(item,out/item.name)
# Historical UI fixture does not instantiate recovery controls.
harness=out/'workspace_harness.gd'
with harness.open('a') as f:f.write('\nfunc _close_recovery_review()->void:pass\n')
def extract(s,name):
 m=re.search(r'^(?:static )?func '+re.escape(name)+r'\(',s,re.M);assert m
 n=re.search(r'^(?:static )?func ',s[m.end():],re.M)
 return s[m.start():m.end()+n.start() if n else len(s)].rstrip()+'\n'
s=(a.source/'Workspaces/AudioWorkspace/audio_recording_prepare.gd').read_text();methods={n:extract(s,n) for n in ['signature','_stable_value']}
(out/'recording_signature.gd').write_text('class_name RecordingSignature\nextends RefCounted\n'+'\n'.join(methods.values()))
shutil.copyfile(v/'cross_flow_tests.gd',out/'cross_flow_tests.gd')
env=os.environ.copy()
for key,name in [('HOME','home'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
 path=v/'godot_home'/name;path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
report={'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'signature_excerpts_sha256':{n:hashlib.sha256(text.encode()).hexdigest() for n,text in methods.items()},'stages':{}}
for stage,cmd in [('import',['--editor','--import','--quit']),('run',['--script','cross_flow_tests.gd'])]:
 result=subprocess.run(['godot','--headless','--path',str(out),*cmd],env=env,capture_output=True,text=True,timeout=30);log=result.stdout+result.stderr;(v/('cross_flow_'+stage+'.log')).write_text(log)
 report['stages'][stage]={'exit_code':result.returncode,'errors':len(re.findall(r'^(?:SCRIPT )?ERROR:',log,re.M)),'warnings':len(re.findall(r'^WARNING:',log,re.M))}
 if stage=='run':
  match=re.search(r'CROSS_FLOW_CHECKS=(\d+) FAILURES=(\d+)',log);assert match,log
  report['checks']=int(match[1]);report['failures']=int(match[2])
report['pass']=report['failures']==0 and all(x['exit_code']==0 and x['errors']==0 and x['warnings']==0 for x in report['stages'].values())
(v/'cross_flow_results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));sys.exit(0 if report['pass'] else 1)
