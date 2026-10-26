"""Read-only verification of ordered packages and an optional native source state.
Never applies patches, modifies sources, runs Godot or starts local jobs.
"""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,stat,zipfile
root=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True,help='Folder containing the five existing batch 4-8 ZIP files');p.add_argument('--target',type=Path,help='Optional source root to identify exact resume point');a=p.parse_args()
ledger=json.loads((root/'ordered_delivery_ledger.json').read_text())
def digest(data):return hashlib.sha256(data).hexdigest()
def safe(name):
 path=PurePosixPath(name);assert not path.is_absolute() and '..' not in path.parts and '\\' not in name,name
 return path
current=ledger['states'][0]['files']
for step in ledger['steps']:
 assert step['all_source_baseline_sha256']==current
 assert len(current)==76 and step['all_source_candidate_sha256'].keys()==current.keys()
 changed={k for k,v in step['all_source_candidate_sha256'].items() if current[k]!=v}
 assert changed=={entry['path'] for entry in step['targets']}
 assert step['unchanged_dependency_sha256']=={k:v for k,v in current.items() if k not in changed}
 for entry in step['targets']:
  safe(entry['path']);assert entry['base_sha256']==current[entry['path']];assert entry['sha256']==step['all_source_candidate_sha256'][entry['path']]
 current=step['all_source_candidate_sha256']
 if step['batch']<4:continue
 archive=a.archives/step['archive_name'];assert archive.stat().st_size==step['archive_bytes'];assert digest(archive.read_bytes())==step['archive_sha256'],str(archive)
 with zipfile.ZipFile(archive) as z:
  names=set()
  for info in z.infolist():
   safe(info.filename);assert info.filename not in names;names.add(info.filename);assert not stat.S_ISLNK(info.external_attr>>16)
  prefix=step['package_root']+'/';mdata=z.read(prefix+'apply_manifest.json');assert digest(mdata)==step['original_package_manifest_sha256']
  manifest=json.loads(mdata);assert manifest['files']==step['targets']
  for name,sha in manifest.get('package_inputs',{}).items():safe(name);assert digest(z.read(prefix+name))==sha,name
  for entry in step['targets']:
   assert digest(z.read(prefix+'baseline/'+entry['path']))==entry['base_sha256'];assert digest(z.read(prefix+'candidate/'+entry['path']))==entry['sha256']
 print('Verified batch',step['batch'],step['archive_name'],len(step['targets']),'targets')
print('Verified full 76-file hash chain: original snapshot -> batches 1,2,3,4,5,6,7,8')
if a.target:
 observed={name:digest((a.target/Path(*safe(name).parts)).read_bytes()) if (a.target/Path(*safe(name).parts)).is_file() else 'MISSING' for name in current}
 matches=[state['name'] for state in ledger['states'][3:] if state['files']==observed]
 if not matches:
  expected=ledger['states'][3]['files'];mismatches=[name for name in expected if observed[name]!=expected[name]]
  print('STOP: target is not an exact batch-3/4/5/6/7/8 state; no automatic overwrite is safe.')
  print('Differences from parent-confirmed batch 3:',json.dumps(mismatches,indent=2));raise SystemExit(2)
 batch=int(matches[0].split('_')[1]);pending=[n for n in ledger['pending_order'] if n>batch]
 print('Exact target state:',matches[0]);print('Remaining ordered batches:',pending)
 print('Read-only check only. Resume is authorized, but application still requires the sole bridge and exact source verification.')
