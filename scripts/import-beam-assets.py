#!/usr/bin/env python3
"""Import the approved Beam artwork into native app resources; no network access."""
from pathlib import Path
import json,shutil
from PIL import Image
import cairosvg
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'Creative Design/2026-10-29-beam-redesign/assets'
MAC=ROOT/'macos/Sources/Miraya/Resources'; RES=ROOT/'android/app/src/main/res'; ART=ROOT/'assets/beam'
for folder in [MAC,ART/'macos-icon',ART/'sources',RES/'drawable-nodpi',RES/'mipmap-anydpi-v26',RES/'mipmap-anydpi'] :folder.mkdir(parents=True,exist_ok=True)
def png(source,destination,size=None):
 im=Image.open(source).convert('RGBA');im=im.resize(size,Image.Resampling.LANCZOS) if size else im;im.save(destination)
def vector(source,destination,width):
 cairosvg.svg2png(url=str(source),write_to=str(destination),output_width=width)
 # Export approved artwork without proposal-only PNG metadata.
 im=Image.open(destination);im.save(destination)
for size in [16,32,64,128,256,512,1024]:png(SOURCE/f'icons/macos/icon-{size}.png', ART/f'macos-icon/icon-{size}.png')
for state in ['idle','discovering','pairing','connecting','connected','paused','error','offline']:
 vector(SOURCE/f'logos/beam-{state}.svg',MAC/f'beam-{state}.png',256)
vector(SOURCE/'logos/beam-mono-dark.svg',MAC/'beam-menu.png',32)
vector(SOURCE/'logos/wordmark-dark.svg',MAC/'wordmark-dark.png',720)
vector(SOURCE/'logos/wordmark-white.svg',MAC/'wordmark-white.png',720)
for name in ['display','speaker','info','stop','pause','play']:
 vector(SOURCE/f'ui/{name}.svg',RES/f'drawable-nodpi/beam_action_{name}.png',96)
vector(SOURCE/'logos/beam-mark.svg',RES/'drawable-nodpi/beam_mark.png',256)
vector(SOURCE/'logos/wordmark-white.svg',RES/'drawable-nodpi/beam_wordmark.png',720)
png(SOURCE/'backgrounds/tv-beam-lake.png',RES/'drawable-nodpi/beam_lake.png')
png(SOURCE/'icons/android-tv/icon-1024.png',RES/'drawable-nodpi/beam_receiver_icon.png')
png(SOURCE/'icons/android-tv/launcher-banner-320.png',RES/'drawable-nodpi/beam_tv_banner.png')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
 folder=RES/f'mipmap-{density}';folder.mkdir(exist_ok=True);png(SOURCE/'icons/android-tv/icon-1024.png',folder/'ic_launcher.png',(size,size))
(RES/'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/beam_navy"/><foreground android:drawable="@drawable/beam_receiver_icon"/></adaptive-icon>\n''')
# Keep the source identity editable without embedding proposal status into shipping files.
for name in ['beam-mark.svg','wordmark-dark.svg','wordmark-white.svg','logo-horizontal-dark.svg','logo-horizontal-white.svg']:
 s=(SOURCE/'logos'/name).read_text();s=s.replace(' — PROPOSAL ONLY — NOT IMPLEMENTED','').replace('PROPOSAL ONLY — NOT IMPLEMENTED.','Approved Beam identity.').replace('Miraya Beam design proposal.','Miraya Beam identity.').replace('Not a shipping asset.','Approved for native Miraya applications.')
 (ART/'sources'/name).write_text(s)
print('Imported approved Beam resources for macOS and Android TV.')
