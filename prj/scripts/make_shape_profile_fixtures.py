"""Endpoint decision boundaries and HD profile arithmetic, from complete images."""
from pathlib import Path
import ast, hashlib, json
import numpy as np

root = Path(__file__).resolve().parents[2]
# Reuse the independently specified whole-image oracle without executing the
# recall generator or touching its existing 57 stimuli.
tree = ast.parse((root/'prj/scripts/make_shape_recall_fixtures.py').read_text())
function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'oracle')
code = ast.unparse(function)
for hd in (False, True):
    W, H = (1280, 720) if hd else (128, 96)
    dest = root/'src/sim/fixtures'/('shape_profile_hd' if hd else 'shape_profile')
    dest.mkdir(exist_ok=True)
    context = dict(np=np, H=H, W=W)
    # MASK0 isolates the endpoint geometry fractions from cleanup; HD uses the
    # unchanged production MASK1 cleanup and real full-raster input.
    exec(code if hd else code.replace('clean = red | (neighbors >= 3)', 'clean = red'), context)
    oracle = context['oracle']
    cases = []
    def mask_from_rows(width, height, spans, counts=None):
        mask = np.zeros((H, W), bool)
        for row, span in enumerate(spans):
            left = 40+(width-span)//2
            if counts is None or counts[row] == span:
                mask[20+row, left-1:left+span+1] = True
            else:
                points = counts[row]
                l = (points+1)//2
                r = points-l
                mask[20+row, left-1:left+l+1] = True
                mask[20+row, left+span-r-1:left+span+1] = True
        return mask
    def add(name, mask, want):
        rgb = np.full((H, W, 3), 48, dtype=np.uint8)
        rgb[mask] = [255, 32, 32]
        expected, stats = oracle(rgb)
        assert expected[0] == want, (name, want, expected, stats)
        cases.append((name, rgb, expected, stats))
    if not hd:
        for end in (25, 24):
            spans = [end]*4+[24]*32+[25]*4
            spans[20] = 40
            # Only one removed accepted point is needed to cross top sum100.
            if end == 24:
                spans[:4] = [24, 25, 25, 25]
            add(f'endpoint_span_{end}', mask_from_rows(40, 40, spans), 2 if end == 25 else 1)
        for point in (20, 19):
            spans = [40]*4+[24]*32+[40]*4
            counts = spans.copy()
            counts[:4] = [point, 20, 20, 20]
            counts[-4:] = [20]*4
            add(f'endpoint_points_{point}', mask_from_rows(40, 40, spans, counts), 2 if point == 20 else 1)
        for width, height, want in [(32, 40, 2), (31, 40, 1), (40, 32, 2), (40, 31, 1)]:
            spans = [width]*4+[width*3//5]*(height-8)+[width]*4
            add(f'min_dimensions_{width}x{height}', mask_from_rows(width, height, spans), want)
        for area, want in [(900, 2), (899, 3)]:
            interior = area-8*40
            spans = [40]*4+[interior//32+(i<interior%32) for i in range(32)]+[40]*4
            add(f'profile_fill_{area}', mask_from_rows(40, 40, spans), want)
    else:
        y, x = np.indices((H, W))
        for fraction, want in [(.4, 2), (.5, 3)]:
            mask = (x<1279)&(y>=2)&(y<716)
            gap = int(1279*fraction)
            mask[6:712, 640-gap//2:640+gap-gap//2] = False
            add(f'hd_profile_missing_{fraction}', mask, want)
    words, records = [], []
    for index, (name, rgb, expected, stats) in enumerate(cases):
        packed = (rgb[:,:,0].astype(np.uint32)<<16)|(rgb[:,:,1].astype(np.uint32)<<8)|rgb[:,:,2]
        file = dest/f'{index:02d}.mem'
        file.write_text('\n'.join(f'{v:06x}' for v in packed.ravel())+'\n')
        words.extend(expected)
        records.append(dict(name=name, file=file.name, expected=expected, stats=stats, sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
    (dest/'expected.mem').write_text('\n'.join(f'{v:08x}' for v in words)+'\n')
    (dest/'manifest.json').write_text(json.dumps(dict(width=W, height=H, mask_cleanup=int(hd), cases=records), indent=2))
    print('PROFILE_FIXTURES', W, H, len(cases), [r['expected'][:2] for r in records])
