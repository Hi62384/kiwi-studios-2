"""Cloud-only exact patch reconstruction. Requires original76 source + all8 archives."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,shutil,stat,subprocess,zipfile,datetime
p=argparse.ArgumentParser();p.add_argument('--archives',type=Path,required=True);p.add_argument('--original',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=Path(__file__).resolve().parents[1];ledger=json.loads((r/'ordered_delivery_ledger.json').read_text());assert not a.output.exists(),'Use a fresh reconstruction directory'
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def state(root):return {name:h(root/Path(*PurePosixPath(name).parts)) for name in ledger['states'][0]['files']}
assert state(a.original)==ledger['states'][0]['files'];shutil.copytree(a.original,a.output);results=[]
for step in ledger['steps']:
 assert state(a.output)==step['all_source_baseline_sha256']
 archive=a.archives/step['archive_name'];assert h(archive)==step['archive_sha256'] and archive.stat().st_size==step['archive_bytes']
 with zipfile.ZipFile(archive) as z:
  names=set()
  for item in z.infolist():
   path=PurePosixPath(item.filename);assert not path.is_absolute() and '..' not in path.parts and '\\' not in item.filename and item.filename not in names and not stat.S_ISLNK(item.external_attr>>16);names.add(item.filename)
  patches=[n for n in names if n.endswith('.patch')];assert len(patches)==1,patches
  done=subprocess.run(['patch','--batch','--fuzz=0','-p1'],input=z.read(patches[0]),cwd=a.output,capture_output=True);assert done.returncode==0,(step['batch'],done.stdout,done.stderr)
 assert state(a.output)==step['all_source_candidate_sha256'],step['batch']
 results.append({'batch':step['batch'],'all76_before_after_exact':True,'patch_output':done.stdout.decode().strip(),'archive_sha256':step['archive_sha256']})
report={'pass':True,'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'states':9,'source_files_per_state':76,'source_edits':False,'method':'Fresh cloud copy of original snapshot; each original immutable package diff applied with fuzz=0; all76 hashes checked before/after every batch.','steps':results}
(r/'validation/reconstruction_results.json').write_text(json.dumps(report,indent=2)+'\n');print('RECONSTRUCTION: original -> 8 batches, 9 exact 76-file states PASS')
