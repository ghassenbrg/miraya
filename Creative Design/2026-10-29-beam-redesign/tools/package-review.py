#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Build and verify the clean local review ZIP."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1];STATUS='PROPOSAL ONLY — NOT IMPLEMENTED'
exclude={'exports','output','.playwright-cli','__pycache__'}
def included(p):return p.is_file() and not any(x in exclude for x in p.relative_to(ROOT).parts) and p.name not in ['.DS_Store','package-manifest.json','archive-validation.json']
files=sorted(p for p in ROOT.rglob('*') if included(p))
manifest={'status':STATUS,'purpose':'Clean local review package; no application implementation','files':[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
m=ROOT/'audit/package-manifest.json';m.write_text(json.dumps(manifest,indent=2));files.append(m)
folder=ROOT/'exports';folder.mkdir(exist_ok=True);archive=folder/'Miraya-Beam-PROPOSAL-ONLY-2026-10-29.zip'
prefix='Miraya-Beam-PROPOSAL-ONLY-2026-10-29'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=8) as z:
 z.comment=STATUS.encode()
 for p in files:z.write(p,prefix+'/'+str(p.relative_to(ROOT)))
with zipfile.ZipFile(archive) as z:
 bad=z.testzip();checks=[]
 for f in manifest['files']:
  checks.append(hashlib.sha256(z.read(prefix+'/'+f['path'])).hexdigest()==f['sha256'])
report={'status':STATUS,'file':str(archive.relative_to(ROOT)),'entries':len(files),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'crcError':bad,'allFileHashesMatch':all(checks),'passed':not bad and all(checks),'excluded':'Runtime browser logs, output intermediates, exports, caches; source assets and validation reports are included.'}
(ROOT/'audit/archive-validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
raise SystemExit(not report['passed'])
