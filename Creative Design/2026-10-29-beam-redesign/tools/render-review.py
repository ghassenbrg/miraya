#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Render through the Playwright CLI."""
from pathlib import Path
import json, subprocess
from PIL import Image, PngImagePlugin
ROOT=Path(__file__).resolve().parents[1]
cli='/Users/ghassenbrg/.codex/skills/playwright/scripts/playwright_cli.sh'
code=(ROOT/'tools/render-review.js').read_text()
result=subprocess.run([cli,'-s=miraya-beam','run-code',code],cwd=ROOT,text=True,capture_output=True)
(ROOT/'output/playwright/render-cli.log').write_text('PROPOSAL ONLY — NOT IMPLEMENTED\n'+result.stdout+'\n'+result.stderr)
try:
    payload=result.stdout.split('### Result\n',1)[1].split('\n### Ran',1)[0].strip()
    report=json.loads(payload)
except (IndexError,json.JSONDecodeError):
    print(result.stdout[:2000]); print(result.stderr[-1500:]); raise SystemExit(result.returncode or 1)
(ROOT/'audit/render-validation.json').write_text(json.dumps(report,indent=2))
for capture in report['captures']:
    path=ROOT/capture['file']; image=Image.open(path); info=PngImagePlugin.PngInfo();info.add_text('Status','PROPOSAL ONLY — NOT IMPLEMENTED');info.add_text('Source','Actual Chromium rendering of index.html'); image.save(path,pnginfo=info)
bad=[x for x in report['states'] if x['clipped'] or x['broken'] or not x['footerVisible']]
print(json.dumps({'captures':len(report['captures']),'stateChecks':len(report['states']),'pageErrors':report['errors'],'issues':bad},indent=2))
raise SystemExit(bool(bad or report['errors']))
