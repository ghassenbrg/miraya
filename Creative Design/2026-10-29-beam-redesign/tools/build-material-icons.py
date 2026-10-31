#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Layer generated material in vector masks.
No AI upscaling: preserve the 1254px source; export smaller platform sizes.
The editable all-vector construction masters remain icon-master.svg.
"""
from pathlib import Path
import base64,json
import cairosvg
from PIL import Image,PngImagePlugin
ROOT=Path(__file__).resolve().parents[1]; A=ROOT/'assets'; STATUS='PROPOSAL ONLY — NOT IMPLEMENTED'
for platform in ['macos','android-tv','ios-future']:
 folder=A/'icons'/platform
 raw=folder/'icon-artwork-master.png'
 im=Image.open(raw);meta=PngImagePlugin.PngInfo();meta.add_text('Status',STATUS+(' — FUTURE iOS' if platform=='ios-future' else ''));meta.add_text('Source','Built-in image_gen; unretouched source material');im.save(raw,pnginfo=meta)
 data=base64.b64encode(raw.read_bytes()).decode()
 # A reproducible rounded vector aperture removes peripheral generation specks.
 # Keep the full native source in the package for non-destructive refinement.
 mask='<rect x="90" y="105" width="1074" height="1040" rx="154"/>' if platform=='android-tv' else '<rect x="77" y="89" width="1103" height="1065" rx="204"/>'
 layered=f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1254 1254"><title>Miraya {platform} material master — {STATUS}</title><desc>Generated optical material within an editable vector tile aperture. Independent vector construction: icon-master.svg.</desc><defs><clipPath id="tile">{mask}</clipPath></defs><image width="1254" height="1254" clip-path="url(#tile)" xlink:href="data:image/png;base64,{data}"/></svg>'
 (folder/'icon-material-master.svg').write_text(layered)
 for size in ([64,128,256,512,1024] if platform!='ios-future' else [1024]):
  path=folder/f'icon-{size}.png'
  cairosvg.svg2png(bytestring=layered.encode(),write_to=str(path),output_width=size,output_height=size)
  rendered=Image.open(path);info=PngImagePlugin.PngInfo();info.add_text('Status',STATUS+(' — FUTURE iOS' if platform=='ios-future' else ''));info.add_text('Role','receiver' if platform=='android-tv' else 'sender');info.add_text('Source','icon-material-master.svg; generated material in vector aperture');rendered.save(path,pnginfo=info)
manifest=json.loads((A/'asset-manifest.json').read_text());manifest['assets']=[str(p.relative_to(A)) for p in sorted(A.rglob('*')) if p.is_file() and p.name!='asset-manifest.json'];manifest['material']='Generated high-resolution material masters for 64–1024px, optical vector marks at 16–32px; standalone vector construction masters are supplied separately.';(A/'asset-manifest.json').write_text(json.dumps(manifest,indent=2))
print('Material icon exports complete; source resolution 1254px, no upscaling.')
# Launcher combines the finished receiver tile with reproducible outlined lettering.
vector_banner=A/'icons/android-tv/launcher-banner.svg'
if not (A/'icons/android-tv/launcher-banner-vector.svg').exists():
 (A/'icons/android-tv/launcher-banner-vector.svg').write_text(vector_banner.read_text())
word=json.loads((A/'source/wordmark-outline.json').read_text());receiver=json.loads((A/'source/receiver-outline.json').read_text())
material=base64.b64encode((A/'icons/android-tv/icon-1024.png').read_bytes()).decode()
banner=f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1920 1080"><title>Miraya Receiver launcher — {STATUS}</title><desc>Finished optical receiver tile and outlined lettering. Proposal only.</desc><defs><radialGradient id="ambient"><stop stop-color="#1B2F50"/><stop offset="1" stop-color="#0C1528"/></radialGradient></defs><rect width="1920" height="1080" fill="url(#ambient)"/><image x="230" y="220" width="640" height="640" xlink:href="data:image/png;base64,{material}"/><g transform="translate(950 404) scale(1.7)"><path d="{word["path"]}" fill="#FFFFFF"/></g><g transform="translate(956 690) scale(.62)"><path d="{receiver["path"]}" fill="#BAC9DF"/></g></svg>'
vector_banner.write_text(banner)
for width,height in [(320,180),(1920,1080)]:
 path=A/f'icons/android-tv/launcher-banner-{width}.png';cairosvg.svg2png(bytestring=banner.encode(),write_to=str(path),output_width=width,output_height=height)
 im=Image.open(path);meta=PngImagePlugin.PngInfo();meta.add_text('Status',STATUS);meta.add_text('Source','Receiver material and outlined wordmark');im.save(path,pnginfo=meta)
manifest['assets']=[str(p.relative_to(A)) for p in sorted(A.rglob('*')) if p.is_file() and p.name!='asset-manifest.json'];(A/'asset-manifest.json').write_text(json.dumps(manifest,indent=2))
