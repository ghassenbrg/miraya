#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Deterministic, editable Beam masters."""
from pathlib import Path
import json, subprocess, math
import cairosvg
from PIL import Image, PngImagePlugin

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
STATUS = 'PROPOSAL ONLY — NOT IMPLEMENTED'
for folder in ['logos', 'icons/macos', 'icons/android-tv', 'icons/ios-future', 'icons/roles', 'ui', 'source']:
    (ASSETS / folder).mkdir(parents=True, exist_ok=True)
subprocess.run(['swift', str(ROOT/'tools/outline-wordmark.swift'), str(ASSETS/'source/wordmark-outline.json')], check=True)
word = json.loads((ASSETS/'source/wordmark-outline.json').read_text())
subprocess.run(['swift', str(ROOT/'tools/outline-wordmark.swift'), str(ASSETS/'source/receiver-outline.json'), 'Receiver'], check=True)
receiver_word=json.loads((ASSETS/'source/receiver-outline.json').read_text())

def svg(content, size='0 0 1000 1000', title='Miraya Beam', extra=''):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{size}" {extra}><title>{title} — {STATUS}</title><desc>Miraya Beam design proposal. {STATUS}. Two opposing planes connected by a luminous central seam. Not a shipping asset.</desc>{content}</svg>'''

def beam(prefix='b', mono=None, light=False, state='connected', micro=False, role=None):
    # Geometry is invariant; light is a state signal, not a continuous effect.
    gap = 34 if state in ['idle','discovering','offline','error'] else 0
    opacity = '.38' if state == 'offline' else '.65' if state == 'paused' else '1'
    amber = '#E0782C' if state == 'error' else '#FF9651'
    blue = '#3478F6'
    left = 'M116 108Q116 94 130 101L446 262Q458 268 458 282V718Q458 732 446 738L130 899Q116 906 116 892Z'
    right = 'M884 108Q884 94 870 101L554 262Q542 268 542 282V718Q542 732 554 738L870 899Q884 906 884 892Z'
    defs = f'''<defs><linearGradient id="{prefix}a" x1="0" x2="1"><stop stop-color="#FF7835"/><stop offset=".6" stop-color="{amber}"/><stop offset="1" stop-color="#FFF3C9"/></linearGradient><linearGradient id="{prefix}b" x1="1" x2="0"><stop stop-color="#1659F4"/><stop offset=".56" stop-color="#2589FF"/><stop offset="1" stop-color="#C5F7FF"/></linearGradient><radialGradient id="{prefix}light"><stop stop-color="#FFFFFF" stop-opacity=".95"/><stop offset=".22" stop-color="#FFFFFF" stop-opacity=".75"/><stop offset=".65" stop-color="#DDEEFF" stop-opacity=".16"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient><radialGradient id="{prefix}warm"><stop stop-color="#FFD1A0" stop-opacity=".22"/><stop offset="1" stop-color="#FF9651" stop-opacity="0"/></radialGradient><radialGradient id="{prefix}cool"><stop stop-color="#7ACBFF" stop-opacity=".24"/><stop offset="1" stop-color="#3478F6" stop-opacity="0"/></radialGradient></defs>'''
    a, b = (mono, mono) if mono else (f'url(#{prefix}a)', f'url(#{prefix}b)')
    seam = mono or ('#354760' if light else '#FFFFFF')
    # The connection is a short beam of light, never a white H or metal pole.
    lit = state not in ['idle','offline','error']
    bloom = '' if mono or light or not lit else f'<ellipse cx="442" cy="500" rx="230" ry="345" fill="url(#{prefix}warm)"/><ellipse cx="558" cy="500" rx="230" ry="345" fill="url(#{prefix}cool)"/>'
    connection = f'<path d="M454 500H546" stroke="{seam}" stroke-width="{10 if state=="paused" else 16}" stroke-linecap="round"/>' if lit else ''
    if not mono and not light and lit:
        connection += f'<ellipse cx="500" cy="500" rx="110" ry="72" fill="url(#{prefix}light)"/>'
    return defs+f'<g opacity="{opacity}">{bloom}<path d="{left}" fill="{a}" opacity="{.88 if role == "receiver" else 1}" transform="translate({-gap} 0)"/><path d="{right}" fill="{b}" opacity="{.88 if role == "sender" else 1}" transform="translate({gap} 0)"/>{connection}</g>'

def save(path, value): (ASSETS/path).write_text(value)
for name, args in [('beam-mark',{}),('beam-mark-light',{'light':True}),('beam-mono-dark',{'mono':'#101B2F'}),('beam-mono-white',{'mono':'#FFFFFF'})]:
    save(f'logos/{name}.svg', svg(beam(name,**args), title=name))
for state in ['idle','discovering','pairing','connecting','connected','paused','error','offline']:
    save(f'logos/beam-{state}.svg', svg(beam('s'+state,state=state), title=f'Beam state: {state}'))

for tone,color in [('dark','#101B2F'),('white','#FFFFFF')]:
    save(f'logos/wordmark-{tone}.svg', svg(f'<path d="{word["path"]}" fill="{color}"/>', f'0 0 {word["width"]} 150', title='Miraya outlined wordmark'))
    word_scaled = f'<g transform="translate(215 14) scale(1.12)"><path d="{word["path"]}" fill="{color}"/></g>'
    mark = f'<g transform="translate(0 -12) scale(.21)">{beam("lock"+tone,light=tone=="dark")}</g>'
    save(f'logos/logo-horizontal-{tone}.svg', svg(mark+word_scaled, f'0 0 {word["width"]*1.12+225} 190', title='Miraya horizontal lockup'))
    mark_v=f'<g transform="translate(150 0) scale(.5)">{beam("vert"+tone,light=tone=="dark")}</g>'
    word_v=f'<g transform="translate({(800-word["width"]*1.4)/2} 510) scale(1.4)"><path d="{word["path"]}" fill="{color}"/></g>'
    save(f'logos/logo-vertical-{tone}.svg', svg(mark_v+word_v,'0 0 800 750',title='Miraya vertical lockup'))

def icon(platform):
    if platform=='macos':
        bg='''<defs><linearGradient id="tile" x2=".6" y2="1"><stop stop-color="#263247"/><stop offset=".46" stop-color="#101A2C"/><stop offset="1" stop-color="#080E1B"/></linearGradient><radialGradient id="aw"><stop stop-color="#FF9651" stop-opacity=".15"/><stop offset="1" stop-color="#FF9651" stop-opacity="0"/></radialGradient><radialGradient id="ac"><stop stop-color="#3478F6" stop-opacity=".2"/><stop offset="1" stop-color="#3478F6" stop-opacity="0"/></radialGradient></defs><rect x="70" y="86" width="884" height="884" rx="208" fill="#050911" opacity=".18"/><rect x="64" y="64" width="896" height="896" rx="208" fill="url(#tile)"/><rect x="66" y="66" width="892" height="892" rx="206" fill="none" stroke="#FFFFFF" stroke-opacity=".23" stroke-width="3"/><defs><clipPath id="tileClip"><rect x="64" y="64" width="896" height="896" rx="208"/></clipPath></defs><g clip-path="url(#tileClip)"><ellipse cx="330" cy="500" rx="280" ry="320" fill="url(#aw)"/><ellipse cx="710" cy="500" rx="280" ry="320" fill="url(#ac)"/></g>'''
        mark=f'<g transform="translate(160 142) scale(.704)">{beam("mac",role="sender")}</g>'
    elif platform=='android-tv':
        bg='<rect x="0" y="0" width="1024" height="1024" fill="#0C1528"/>'
        mark=f'<g transform="translate(160 160) scale(.704)">{beam("atv",role="receiver")}</g>'
    else:
        # iOS source is deliberately unmasked; the OS supplies its platform mask.
        bg='<rect width="1024" height="1024" fill="#F7F8FA"/>'
        mark=f'<g transform="translate(150 150) scale(.724)">{beam("ios",light=True,role="sender")}</g>'
    return svg(bg+mark,'0 0 1024 1024',title=f'Miraya {platform} '+('receiver' if platform=='android-tv' else 'sender')+' icon'+(' — FUTURE / PROPOSED' if platform=='ios-future' else ''))

for platform in ['macos','android-tv','ios-future']:
    save(f'icons/{platform}/icon-master.svg',icon(platform))

# Pixel-hinted micro mark: a crisp one-pixel seam and bridge, no blur or detail.
def micro_mark(role='sender'):
    left='M3 3L6.5 5V11L3 13Z';right='M13 3L9.5 5V11L13 13Z'
    def plane(path,color,filled):return f'<path d="{path}" fill="{color if filled else "none"}" stroke="{color}" stroke-width="{0 if filled else 1}"/>'
    return '<rect x="1" y="1" width="14" height="14" rx="3.3" fill="#101B2F"/>'+plane(left,'#FFAA65',role=='sender')+plane(right,'#5599FF',role=='receiver')+'<rect x="6" y="8" width="4" height="1" fill="#FFF"/><rect x="8" y="5" width="1" height="6" fill="#FFF"/>'

save('logos/beam-micro.svg',svg(micro_mark(),'0 0 16 16',title='Beam pixel-hinted 16px sender mark'))
for platform,role in [('macos','sender'),('android-tv','receiver')]:
    for size in [16,32,64,128,256,512,1024]:
        master=svg(micro_mark(role),'0 0 16 16',title=f'Beam {role} {size}px optical master') if size<=32 else icon(platform)
        save(f'icons/{platform}/icon-{size}.svg',master)
        path=ASSETS/f'icons/{platform}/icon-{size}.png'
        cairosvg.svg2png(bytestring=master.encode(),write_to=str(path),output_width=size,output_height=size)
        im=Image.open(path);meta=PngImagePlugin.PngInfo();meta.add_text('Status',STATUS);meta.add_text('Role',role);meta.add_text('Description',f'Miraya Beam {role}, optical size {size}px');im.save(path,pnginfo=meta)
for role in ['sender','receiver']:
    save(f'icons/roles/{role}-mark.svg',svg(beam('role'+role,role=role),title=f'Miraya {role} role mark'))
    save(f'icons/roles/{role}-mono.svg',svg(beam('mono'+role,mono='#FFFFFF',role=role),title=f'Miraya {role} monochrome role proof'))
for platform in ['android-tv','ios-future']:
    path=ASSETS/f'icons/{platform}/icon-1024.png'
    cairosvg.svg2png(bytestring=icon(platform).encode(),write_to=str(path),output_width=1024,output_height=1024)
    im=Image.open(path); meta=PngImagePlugin.PngInfo(); meta.add_text('Status',STATUS+(' — FUTURE iOS' if platform=='ios-future' else '')); im.save(path,pnginfo=meta)

foreground = svg(f'<g transform="translate(240 240) scale(.544)">{beam("adaptive",role="receiver")}</g>','0 0 1024 1024',title='Android adaptive foreground — keep within central safe zone')
save('icons/android-tv/adaptive-foreground.svg',foreground)
save('icons/android-tv/adaptive-background.svg',svg('<rect width="1024" height="1024" fill="#0C1528"/>','0 0 1024 1024',title='Android adaptive background'))
banner = '<rect width="1920" height="1080" fill="#0C1528"/>'+f'<g transform="translate(300 260) scale(.56)">{beam("banner",role="receiver")}</g><g transform="translate(950 404) scale(1.7)"><path d="{word["path"]}" fill="#FFF"/></g>'
banner += f'<g transform="translate(956 690) scale(.62)"><path d="{receiver_word["path"]}" fill="#BAC9DF"/></g>'
save('icons/android-tv/launcher-banner.svg',svg(banner,'0 0 1920 1080',title='Miraya Android TV launcher banner 16:9'))
for width,height in [(320,180),(1920,1080)]:
    path=ASSETS/f'icons/android-tv/launcher-banner-{width}.png'
    cairosvg.svg2png(bytestring=svg(banner,'0 0 1920 1080').encode(),write_to=str(path),output_width=width,output_height=height)
    im=Image.open(path); info=PngImagePlugin.PngInfo();info.add_text('Status',STATUS);im.save(path,pnginfo=info)

icons={
 'display':'<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>',
 'window':'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M6 6.5h.01M9 6.5h.01"/>',
 'area':'<path d="M3 9V3h6M15 3h6v6M21 15v6h-6M9 21H3v-6"/><path d="M7 7h10v10H7z" stroke-dasharray="2 2"/>',
 'speaker':'<path d="M11 5L6 9H3v6h3l5 4zM15 8c3 2 3 6 0 8M18 5c5 4 5 10 0 14"/>',
 'muted':'<path d="M11 5L6 9H3v6h3l5 4zM16 9l5 6M21 9l-5 6"/>',
 'check':'<path d="M5 12l4 4L19 6"/>',
 'shield':'<path d="M12 3L4 6v6c0 5 8 9 8 9s8-4 8-9V6zM8 12l3 3 5-6"/>',
 'lock':'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 018 0v3"/>',
 'chevron':'<path d="M9 5l7 7-7 7"/>',
 'down':'<path d="M6 9l6 6 6-6"/>',
 'refresh':'<path d="M20 8V3l-3 3a8 8 0 10 3 9M20 3h-5"/>',
 'pause':'<path d="M8 5v14M16 5v14" stroke-width="4"/>',
 'play':'<path d="M8 5l11 7-11 7z"/>',
 'stop':'<rect x="5" y="5" width="14" height="14" rx="1" fill="currentColor" stroke="none"/>',
 'info':'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
 'warning':'<path d="M12 3L2 21h20zM12 9v5M12 17h.01"/>',
 'close':'<path d="M6 6l12 12M18 6L6 18"/>',
 'metrics':'<path d="M2 13h4l3-8 5 14 3-7h5"/>',
 'file':'<path d="M6 3h8l4 4v14H6zM14 3v5h4M10 12l5 3-5 3z"/>',
 'link':'<path d="M10 13a4 4 0 006 0l4-4a4 4 0 00-6-6l-2 2M14 11a4 4 0 00-6 0l-4 4a4 4 0 006 6l2-2"/>',
 'keyboard':'<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M5 9h.01M9 9h.01M13 9h.01M17 9h.01M6 14h12"/>',
}
for name,body in icons.items():
    save(f'ui/{name}.svg',svg(f'<g fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">{body}</g>','0 0 24 24',title=f'Miraya UI {name}'))

for mode in ['fit','fill','stretch']:
    source='<rect x="20" y="16" width="120" height="68" rx="6" fill="#101B2F"/>'
    if mode=='fit': body='<rect x="56" y="18" width="48" height="64" rx="2" fill="#3478F6"/><path d="M72 44l8 4 8-4v16l-8-4-8 4z" fill="#FFAA65"/>'
    elif mode=='fill': body='<path d="M20 18h120v64H20z" fill="#3478F6"/><path d="M45 18l35 20 35-20v64L80 62 45 82z" fill="#FFAA65"/>'
    else: body='<rect x="22" y="18" width="116" height="64" rx="2" fill="#3478F6"/><path d="M42 34l38 14 38-14v32L80 52 42 66z" fill="#FFAA65"/>'
    save(f'ui/picture-{mode}.svg',svg(source+body,'0 0 160 100',title=f'Beam thumbnail — {mode}'))

demo='''<rect width="1920" height="1080" fill="#101724"/><circle cx="1390" cy="430" r="220" fill="#E9BC7F"/><circle cx="1458" cy="370" r="222" fill="#101724"/><path d="M1210 750Q1490 650 1750 730" fill="none" stroke="#526680" stroke-width="2"/><text x="132" y="170" fill="#AEC0D7" font-family="Arial,sans-serif" font-size="24" letter-spacing="6">ILLUSTRATIVE SHARED CONTENT</text><text x="132" y="390" fill="#F9F6F0" font-family="Arial,sans-serif" font-size="110" font-weight="600">Light, distance</text><text x="132" y="520" fill="#F9F6F0" font-family="Arial,sans-serif" font-size="110" font-weight="600">and perspective.</text><text x="136" y="618" fill="#B3C2D5" font-family="Arial,sans-serif" font-size="34">A sample astronomy presentation.</text><path d="M136 760h450" stroke="#4C7DCA" stroke-width="4"/><text x="136" y="940" fill="#99AAC0" font-family="Arial,sans-serif" font-size="24">DEMO SLIDE 04 / 12 · NOT AN ACTUAL SCREEN CAPTURE</text>'''
save('demo-content.svg',svg(demo,'0 0 1920 1080',title='Illustrative shared content, not a live preview'))
manifest={'status':STATUS,'geometry':'Two opposed light planes joined by a short luminous seam. Optical micro masters use a 1px white spine and bridge.','assets':[str(p.relative_to(ASSETS)) for p in sorted(ASSETS.rglob('*')) if p.is_file()]}
(ASSETS/'asset-manifest.json').write_text(json.dumps(manifest,indent=2))
print('Built',len(manifest['assets']),'proposal assets')
