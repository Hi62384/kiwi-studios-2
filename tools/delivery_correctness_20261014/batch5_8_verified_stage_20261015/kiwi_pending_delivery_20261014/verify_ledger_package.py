"""Verify this ledger artifact's own inputs; no source or archive mutations."""
from pathlib import Path,PurePosixPath
import hashlib,json
root=Path(__file__).resolve().parent;m=json.loads((root/'artifact_manifest.json').read_text())
for name,sha in m['files'].items():
 path=PurePosixPath(name);assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
 assert hashlib.sha256((root/Path(*path.parts)).read_bytes()).hexdigest()==sha,name
print('Verified ledger artifact:',len(m['files']),'exact inputs')
