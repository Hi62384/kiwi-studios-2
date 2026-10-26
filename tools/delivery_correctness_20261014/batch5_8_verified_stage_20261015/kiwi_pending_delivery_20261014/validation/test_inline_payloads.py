"""Verify exactly the requested bounded inline handoffs; writes cloud fixture only."""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil,tempfile
p=argparse.ArgumentParser();p.add_argument('--batch3-source',type=Path,required=True);a=p.parse_args();r=Path(__file__).resolve().parents[1];ledger=json.loads((r/'ordered_delivery_ledger.json').read_text());checks=0
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(dir=r/'validation',prefix='inline-reconstruction-') as tmp:
 target=Path(tmp)/'source';shutil.copytree(a.batch3_source,target)
 for n in range(4,9):
  raw=r/'bridge_inline'/f'batch{n}_inline_payload.json';data=json.loads(raw.read_text());step=ledger['steps'][n-1]
  assert data['batch']==n and data['precondition']==step['all_source_baseline_sha256'] and data['postcondition']==step['all_source_candidate_sha256'] and data['targets']==step['targets'];checks+=1
  assert raw.stat().st_size<100000;checks+=1
  assert all(h(target/name)==sha for name,sha in data['precondition'].items());checks+=1
  done=subprocess.run(['patch','-p1','--fuzz=0','--batch'],cwd=target,input=data['unified_diff'],text=True,capture_output=True);assert done.returncode==0,(n,done.stdout,done.stderr);checks+=1
  assert all(h(target/name)==sha for name,sha in data['postcondition'].items());checks+=1
report={'pass':True,'checks':checks,'steps':5,'all76_before_after_exact':True,'cloud_fixture_only':True,'max_payload_bytes':max(p.stat().st_size for p in (r/'bridge_inline').glob('*inline_payload.json'))}
(r/'validation/inline_test_results.json').write_text(json.dumps(report,indent=2)+'\n');print('INLINE_CHECKS='+str(checks)+' FAILURES=0')
