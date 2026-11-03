"""Configure only local paths in an extracted copy; requires Python 3.9+."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--td-home', type=Path, help='Installed TD root, for vendor-model simulations')
args = parser.parse_args()
state = root / '.local_paths.json'
prefixes = ['D:/fpga_2/fpga-competition-2026-main', 'D:/codex_project/FPGA_competiton']
if state.exists():
    prefixes.append(json.loads(state.read_text(encoding='utf-8'))['root'])
changed = []
for folder in (root/'src', root/'prj'):
    for path in folder.rglob('*'):
        if not path.is_file() or path.suffix.lower() not in {'.v','.sv','.vh','.tcl','.al','.py'}:
            continue
        data = path.read_bytes()
        updated = data
        for prefix in sorted(set(prefixes), key=len, reverse=True):
            updated = updated.replace(prefix.encode('utf-8'), root.as_posix().encode('utf-8'))
        if args.td_home:
            updated = updated.replace(b'D:/Software/Anlogic/TD_6.2.1_Engineer_6.2.168.116', args.td_home.resolve().as_posix().encode('utf-8'))
        if updated != data:
            path.write_bytes(updated)
            changed.append(str(path.relative_to(root)))
state.write_text(json.dumps({'root': root.as_posix()}, ensure_ascii=False, indent=2), encoding='utf-8')
al = root/'prj/td/lab_ex3_sc520/td_project/camera_to_dsi_display.al'
entries = re.findall(r'<File Path="([^"]+)"', al.read_text(encoding='utf-8'))
missing = [name for name in entries if not (al.parent/name).is_file()]
if missing:
    raise RuntimeError(f'Missing project inputs: {missing}')
assert (root/'src/rtl/osd/logo_data/index.dath').is_file()
assert (root/'src/rtl/osd/logo_data/palette.dath').is_file()
subprocess.run([sys.executable, str(root/'prj/scripts/unpack_sim_fixtures.py')], check=True)
print('PROJECT_READY', len(entries), 'inputs; relocated', len(changed), 'files')
