"""Re-run the archived batch7 dialogue suite against exact batch8 source."""
from pathlib import Path,PurePosixPath
import argparse,json,hashlib,shutil,subprocess,os,re,zipfile,datetime
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True);p.add_argument('--source',type=Path,required=True);a=p.parse_args();v=Path(__file__).resolve().parent;r=v.parent
ledger=json.loads((r/'ordered_delivery_ledger.json').read_text());step=ledger['steps'][6];archive=a.archives/step['archive_name'];h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert h(archive)==step['archive_sha256']
assert all(h(a.source/name)==sha for name,sha in ledger['states'][-1]['files'].items())
out=v/'archive_runs/7';out.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
 for name in z.namelist():
  path=PurePosixPath(name);assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
 z.extractall(out)
package=out/step['package_root'];shutil.copytree(a.source,package/'candidate',dirs_exist_ok=True)
prepare=package/'validation/prepare_harness.py';text=prepare.read_text();text=text.replace("lines=body.splitlines();assert","lines=body.splitlines();lines=lines[1:] if lines and lines[0].strip()=='_recovery_tick()' else lines;assert");prepare.write_text(text)
subprocess.run(['python',str(prepare)],check=True)
project=package/'validation/candidate'
with (project/'workspace_harness.gd').open('a') as f:f.write('\nfunc _close_recovery_review()->void:pass\n')
env=os.environ.copy()
for key,leaf in [('HOME','home'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
 path=v/'godot_home'/leaf;path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
report={'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'stages':{},'seams':'Existing batch7 native UI/device/transport seams; newly added close-recovery hook is no-op because this fixture has no recovery window. Batch8 exact-handler/real-worker suite tests that workflow separately.','full_class_hashes':json.loads((project/'source_manifest.json').read_text())['full_class_sha256']}
for stage,args in [('import',['--editor','--import','--quit']),('run',['--script','run.gd'])]:
 result=subprocess.run(['godot','--headless','--path',str(project),*args],env=env,capture_output=True,text=True,timeout=30);log=result.stdout+result.stderr;(v/f'final_review_{stage}.log').write_text(log)
 report['stages'][stage]={'exit_code':result.returncode,'errors':len(re.findall(r'^(?:SCRIPT )?ERROR:',log,re.M)),'warnings':len(re.findall(r'^WARNING:',log,re.M))}
 if stage=='run':
  m=re.search(r'DIALOGUE_CLEANUP_CHECKS=(\d+) FAILURES=(\d+)',log);assert m,log;report['checks']=int(m[1]);report['failures']=int(m[2])
report['pass']=report['failures']==0 and all(x['exit_code']==0 and x['errors']==0 and x['warnings']==0 for x in report['stages'].values());(v/'final_review_results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(0 if report['pass'] else 1)
