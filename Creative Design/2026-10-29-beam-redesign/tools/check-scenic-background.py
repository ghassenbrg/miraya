#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Worst-case contrast over actual artwork."""
from pathlib import Path
import subprocess,json,math,re
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
r=subprocess.run(['/Users/ghassenbrg/.codex/skills/playwright/scripts/playwright_cli.sh','-s=miraya-beam','run-code',(ROOT/'tools/check-scenic-background.js').read_text()],cwd=ROOT,capture_output=True,text=True)
try:report=json.loads(r.stdout.split('### Result\n',1)[1].split('\n### Ran',1)[0])
except Exception:print(r.stdout[-2000:]);raise SystemExit(1)
def lum(rgb):
 s=[x/255 for x in rgb[:3]];v=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in s];return .2126*v[0]+.7152*v[1]+.0722*v[2]
checks=[]
for state in report['states']:
 im=Image.open(ROOT/state['file']).convert('RGB')
 for t in state['text']:
  coords=(max(0,math.floor(t['x'])),max(0,math.floor(t['y'])),min(im.width,math.ceil(t['x']+t['width'])),min(im.height,math.ceil(t['y']+t['height'])))
  if coords[2]<=coords[0] or coords[3]<=coords[1]:continue
  color=[float(x) for x in re.findall(r'[\d.]+',t['color'])][:3];fg=lum(color);tile=im.crop(coords);backgrounds=set(tile.get_flattened_data() if hasattr(tile,'get_flattened_data') else tile.getdata());ratio=min((max(fg,lum(bg))+.05)/(min(fg,lum(bg))+.05) for bg in backgrounds)
  inside=t['x']>=0 and t['y']>=0 and t['x']+t['width']<=im.width+1 and t['y']+t['height']<=im.height+1
  checks.append({'state':state['state'],'text':t['text'],'minimumContrast':round(ratio,2),'threshold':4.5,'withinFrame':inside,'passed':ratio>=4.5 and inside})
report={'status':report['status'],'method':'Worst luminance contrast anywhere in each text-node rectangle against a real Chromium background render with text/shadows temporarily hidden. Conservative 4.5:1 for all text, including large headings. No text shadows counted as contrast.','checks':checks,'passed':all(c['passed'] for c in checks)}
(ROOT/'audit/scenic-background-validation.json').write_text(json.dumps(report,indent=2));print(json.dumps({'checks':len(checks),'passed':report['passed'],'issues':[c for c in checks if not c['passed']]},indent=2));raise SystemExit(not report['passed'])
