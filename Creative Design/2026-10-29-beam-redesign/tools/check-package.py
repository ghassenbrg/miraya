#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Asset, contrast and outside-file audit."""
from pathlib import Path
import hashlib,json,subprocess,xml.etree.ElementTree as ET
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];REPO=ROOT.parents[1];STATUS='PROPOSAL ONLY — NOT IMPLEMENTED'
def lum(h):
 vals=[int(h[i:i+2],16)/255 for i in [1,3,5]];r,g,b=[x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in vals];return .2126*r+.7152*g+.0722*b
def contrast(a,b):
 x,y=sorted([lum(a),lum(b)]);return (y+.05)/(x+.05)
pairs=[('Mac primary','#182233','#F6F7F9',4.5),('Mac secondary','#596474','#F6F7F9',4.5),('Primary white label','#FFFFFF','#155DDD',4.5),('Mac Stop','#FFFFFF','#BE2C3C',4.5),('Mac success','#237348','#F6F7F9',4.5),('Mac warning','#8D4D00','#F6F7F9',4.5),('Light control boundary','#7F8A9A','#FFFFFF',3),('Inactive switch','#6F7B8C','#F6F7F9',3),('Dark Mac primary','#F4F7FB','#17202E',4.5),('Dark Mac secondary','#B4C0D1','#202C3D',4.5),('Dark control boundary','#7B8DA6','#202C3D',3),('TV primary','#F4F7FB','#0B1323',4.5),('TV secondary','#A8B8CD','#172237',4.5),('TV neutral button label','#E4ECF8','#18253A',4.5),('TV focused label','#101B2F','#F4F7FB',4.5),('TV focus outline','#BDD7FF','#18253A',3),('TV Stop','#FFFFFF','#A92536',4.5),('TV focused Stop','#A02031','#FFFFFF',4.5)]
rows=[{'name':n,'foreground':a,'background':b,'ratio':round(contrast(a,b),2),'minimum':v,'passed':contrast(a,b)>=v} for n,a,b,v in pairs]
(ROOT/'audit/accessibility-validation.json').write_text(json.dumps({'status':STATUS,'method':'WCAG relative sRGB luminance; solid colors, not decorative light gradients','contrast':rows},indent=2))
issues=[];svgs=list((ROOT/'assets').rglob('*.svg'));pngs=list((ROOT/'assets').rglob('*.png'))
for p in svgs:
 try:
  node=ET.parse(p).getroot();texts=' '.join(node.itertext())
  if STATUS not in texts:issues.append(str(p.relative_to(ROOT))+': missing proposal title/desc')
  if 'wordmark' in p.name or 'logo-' in p.name:
   if any(e.tag.endswith('text') for e in node.iter()):issues.append(p.name+': non-outlined logo lettering')
 except ET.ParseError as e:issues.append(p.name+': '+str(e))
for p in pngs:
 im=Image.open(p)
 if STATUS not in im.info.get('Status',''):issues.append(str(p.relative_to(ROOT))+': missing proposal metadata')
optical=[]
for size in [16,32,64,128,256,512,1024]:
 for platform in ['macos','android-tv']:
  p=ROOT/f'assets/icons/{platform}/icon-{size}.png';im=Image.open(p)
  if im.size!=(size,size):issues.append(str(p)+': wrong size')
  optical.append({'platform':platform,'size':size,'alpha':im.mode=='RGBA','dimensionsPass':im.size==(size,size)})
for platform in ['macos','android-tv']:
 im=Image.open(ROOT/f'assets/icons/{platform}/icon-16.png').convert('RGBA')
 if im.getpixel((8,8))[:3]!=(255,255,255):issues.append(platform+': micro seam not white')
if Image.open(ROOT/'assets/icons/macos/icon-16.png').tobytes()==Image.open(ROOT/'assets/icons/android-tv/icon-16.png').tobytes():issues.append('Micro role pixels are identical')
(ROOT/'audit/asset-validation.json').write_text(json.dumps({'status':STATUS,'svgCount':len(svgs),'pngCount':len(pngs),'wordmark':'Outlined SVG paths; no text nodes','opticalSizes':optical,'issues':issues},indent=2))
baseline=json.loads((ROOT/'audit/repository-baseline.json').read_text());outside=baseline['outsideFiles'];modified=[]
for name,sha in outside.items():
 p=REPO/name
 if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:modified.append(name)
files=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z'],cwd=REPO).decode().split('\0');prefix=str(ROOT.relative_to(REPO))+'/'
new=[n for n in files if n and not n.startswith(prefix) and n not in outside and (REPO/n).is_file()]
branch=subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()
scope={'status':STATUS,'branch':branch,'baselineOutsideFiles':len(outside),'modifiedOutsideFiles':modified,'newOutsideFiles':new,'passed':not modified and not new and branch=='creative-design/2026-10-29-beam-redesign','note':'Preexisting dirty production changes are preserved. This compares file contents against the design starting baseline, not a clean HEAD.'}
(ROOT/'audit/scope-validation.json').write_text(json.dumps(scope,indent=2))
print(json.dumps({'contrast':rows,'assetIssues':issues,'scope':scope},indent=2))
raise SystemExit(bool(issues or any(not x['passed'] for x in rows) or not scope['passed']))
