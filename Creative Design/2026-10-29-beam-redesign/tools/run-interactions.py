#!/usr/bin/env python3
"""PROPOSAL ONLY — NOT IMPLEMENTED. Invoke owned Playwright CLI session."""
from pathlib import Path
import subprocess,json
root=Path(__file__).resolve().parents[1]
cli='/Users/ghassenbrg/.codex/skills/playwright/scripts/playwright_cli.sh'
r=subprocess.run([cli,'-s=miraya-beam','run-code',(root/'tools/check-interactions.js').read_text()],cwd=root,text=True,capture_output=True)
(root/'output/playwright/interactions-cli.log').write_text('PROPOSAL ONLY — NOT IMPLEMENTED\n'+r.stdout+'\n'+r.stderr)
try: report=json.loads(r.stdout.split('### Result\n',1)[1].split('\n### Ran',1)[0])
except (IndexError,json.JSONDecodeError):print(r.stdout[-2400:]);raise SystemExit(1)
(root/'audit/interaction-validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));raise SystemExit(any(not c['passed'] for c in report['checks']) or bool(report['errors'] or report['resources']))
