"""Restore the versioned regression inputs without replacing local changes."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[2]
folder = root / 'src/sim/fixtures'
manifest = json.loads((folder / 'archive-manifest.json').read_text(encoding='utf8'))
with zipfile.ZipFile(folder / 'regression_inputs.zip') as archive:
    assert sorted(archive.namelist()) == sorted(manifest['files'])
    for name, expected in manifest['files'].items():
        target = (folder / name).resolve()
        assert target.is_relative_to(folder.resolve()) and target.suffix == '.mem'
        data = archive.read(name)
        assert hashlib.sha256(data).hexdigest() == expected, name
        if target.exists():
            assert hashlib.sha256(target.read_bytes()).hexdigest() == expected, f'Local fixture differs: {target}'
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
print('FIXTURES_READY', len(manifest['files']))
