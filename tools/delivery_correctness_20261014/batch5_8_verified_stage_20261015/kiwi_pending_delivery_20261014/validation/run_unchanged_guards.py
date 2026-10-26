"""Verify batch1 save/conductor and batch2 export guards on exact final source."""
from pathlib import Path
import argparse,json,hashlib,re,shutil,os,subprocess,sys,zipfile
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True);p.add_argument('--source',type=Path,required=True);a=p.parse_args();v=Path(__file__).resolve().parent;r=v.parent
ledger=json.loads((r/'ordered_delivery_ledger.json').read_text());env=os.environ.copy()
for k,n in [('HOME','home'),('XDG_CACHE_HOME','cache'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data')]:
 d=v/'godot_home'/n;d.mkdir(parents=True,exist_ok=True);env[k]=str(d)
def ex(s,n):
 m=re.search(r'^(?:static )?func '+re.escape(n)+r'\(',s,re.M);assert m
 e=re.search(r'^(?:static )?func ',s[m.end():],re.M);lines=s[m.start():m.end()+e.start() if e else len(s)].rstrip().splitlines()
 while lines and (not lines[-1].strip() or lines[-1].startswith('#')):lines.pop()
 return '\n'.join(lines)+'\n'
report={'suites':{},'immutable_functions':{}}
for b in [1,2]:
 step=ledger['steps'][b-1];archive=a.archives/step['archive_name'];assert hashlib.sha256(archive.read_bytes()).hexdigest()==step['archive_sha256'];out=v/'archive_runs'/str(b);out.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive) as z:z.extractall(out)
 root=out/step['package_root'];old=(root/'candidate/Workspaces/AudioWorkspace/audio_workspace.gd').read_text();final=(a.source/'Workspaces/AudioWorkspace/audio_workspace.gd').read_text()
 names=['save_document','render_preview'] if b==1 else ['_choose_export','bounce_track','_stem_destination']
 for n in names:assert ex(old,n)==ex(final,n);report['immutable_functions'][n]=hashlib.sha256(ex(final,n).encode()).hexdigest()
 source_file='audio_conductor.gd' if b==1 else 'audio_renderer.gd';assert (root/'candidate/Workspaces/AudioWorkspace'/source_file).read_bytes()==(a.source/'Workspaces/AudioWorkspace'/source_file).read_bytes()
 shutil.copytree(a.source,root/'candidate',dirs_exist_ok=True);subprocess.run([sys.executable,str(root/'validation/prepare_harness.py')],check=True,stdout=subprocess.DEVNULL)
 if b==1:
  project=v/'unchanged_save_conductor';project.mkdir(exist_ok=True)
  generated=root/'validation/candidate'
  for name in ['project.godot','audio_conductor.gd','audio_tempo_map.gd','finite_stub.gd','conductor_test.gd','actor_stub.gd','clip_stub.gd'] :shutil.copyfile(generated/name,project/name)
  # Preserve the archived minimal document validation/save fixture.
  doc=next(p for p in generated.glob('*.gd') if 'class_name KiwiAudioDocument' in p.read_text());shutil.copyfile(doc,project/doc.name)
  (project/'workspace_harness.gd').write_text('class_name WorkspaceHarness\nextends Node\n'+ex(final,'save_document'))
  test=(generated/'workspace_test.gd').read_text().split(' var workspace := WorkspaceHarness.new()')[0]+' print("SAVE_GUARD_CHECKS=%d FAILURES=%d"%[checks,failures.size()])\n quit(0 if failures.is_empty() else 1)\n';(project/'save_test.gd').write_text(test)
  tests=['conductor_test.gd','save_test.gd']
 else:project=root/'validation/candidate';tests=['run.gd']
 for label,args in [('import',['--editor','--import','--quit'])]+[(n,['--script',n]) for n in tests]:
  run=subprocess.run(['godot','--headless','--path',str(project),*args],env=env,capture_output=True,text=True,timeout=30);log=run.stdout+run.stderr;(v/f'unchanged_{b}_{label}.log').write_text(log)
  report['suites'][str(b)+'_'+label]={'exit_code':run.returncode,'errors':len(re.findall(r'^(?:SCRIPT )?ERROR:',log,re.M)),'warnings':len(re.findall(r'^WARNING:',log,re.M)),'result_lines':[l for l in log.splitlines() if 'CHECKS' in l or 'assert' in l.lower() or 'failures' in l.lower()]}
report['pass']=all(x['exit_code']==0 and x['errors']==0 and x['warnings']==0 for x in report['suites'].values());(v/'unchanged_results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));sys.exit(0 if report['pass'] else 1)
