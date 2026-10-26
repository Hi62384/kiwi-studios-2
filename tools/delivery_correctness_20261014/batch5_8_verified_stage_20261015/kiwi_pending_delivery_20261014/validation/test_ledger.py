"""Exercise read-only resume detection without touching any production tree."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,sys,tempfile
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True);p.add_argument('--workspace',type=Path,required=True);a=p.parse_args();r=Path(__file__).resolve().parents[1];checks=[]
def check(ok,name):assert ok,name;checks.append(name)
def run(target):return subprocess.run([sys.executable,str(r/'verify_pending.py'),'--archives',str(a.archives),'--target',str(target)],capture_output=True,text=True)
folders={3:'kiwi_edit_preservation_20261014',4:'kiwi_gesture_safety_20261014',5:'kiwi_media_relink_20261014',6:'kiwi_recording_stream_20261014',7:'kiwi_dialogue_cleanup_20261014',8:'kiwi_recovery_checkpoints_20261014'}
for batch,folder in folders.items():
 target=a.workspace/folder/'candidate';before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in target.rglob('*.gd')};result=run(target)
 check(result.returncode==0 and 'Exact target state: batch_'+str(batch) in result.stdout,'exact batch '+str(batch)+' resume point')
 check(all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==sha for p,sha in before.items()),'batch '+str(batch)+' verification writes no source')
with tempfile.TemporaryDirectory(dir=r/'validation',prefix='ledger-negative-') as tmp:
 target=Path(tmp)/'source';shutil.copytree(a.workspace/folders[3]/'candidate',target)
 changed='Workspaces/AudioWorkspace/audio_workspace.gd';shutil.copyfile(a.workspace/folders[7]/'candidate'/changed,target/changed)
 result=run(target);check(result.returncode==2 and 'not an exact' in result.stdout,'mixed partial-application state stops')
 (target/'Workspaces/AudioWorkspace/audio_conductor.gd').unlink();result=run(target);check(result.returncode==2,'missing dependency stops')
original=a.workspace/'kiwi_current_20261014/baseline';check(run(original).returncode==2,'original pre-batch3 source cannot skip applied-stage precondition')
(r/'validation/ledger_test_results.json').write_text(json.dumps({'pass':True,'checks':len(checks),'cases':checks},indent=2)+'\n');print('LEDGER_CHECKS='+str(len(checks))+' FAILURES=0')
