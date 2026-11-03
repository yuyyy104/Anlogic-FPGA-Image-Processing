"""Independent full-image oracle for the filtered epoch-tail rectangle."""
from pathlib import Path
import hashlib
import json
import numpy as np

root = Path(__file__).resolve().parents[2]
dest = root / 'src/sim/fixtures/shape_recall'
W, H = 128, 16
words, records = [], []
for frame in (4, 5):
    rgb = np.full((H, W, 3), 48, dtype=np.int32)
    rgb[4:12, 32:96] = [255, 32, 32]
    if frame == 4:
        rgb[7, 64] = 255
    # The fixed display matrix is unchanged. Compute rounded, clipped output
    # directly, rather than reproducing its register stages.
    matrix = np.array([[286, -55, 25], [-25, 283, -2], [9, -56, 303]])
    rgb = np.clip((rgb @ matrix.T + 128) // 256, 0, 255)
    padded = np.pad(rgb, ((1, 1), (1, 1), (0, 0)))
    windows = [padded[a:a+H, b:b+W] for a in range(3) for b in range(3)]
    median = np.median(np.stack(windows), axis=0).astype(np.int32)
    weights = [1, 2, 1, 2, 4, 2, 1, 2, 1]
    gaussian = (sum(w * p for w, p in zip(weights, windows)) + 8) // 16
    filtered = (median + gaussian + 1) // 2
    quality = np.zeros_like(rgb)
    quality[1:, 1:] = filtered[:-1, :-1]
    r, g, b = quality.transpose(2, 0, 1)
    red = (r >= g+24) & (r >= b+24) & (2*r >= 3*g) & (2*r >= 3*b)
    p = np.pad(red, 1)
    n = p[:-2, 1:-1].astype(int) + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
    clean = red | (n >= 3)
    accepted = np.zeros((H, W), bool)
    accepted[:-2, 1:-2] = clean[:-2, :-3] & clean[:-2, 1:-2] & clean[:-2, 2:-1]
    yy, xx = np.nonzero(accepted)
    area, x0, x1, y0, y1 = len(xx), int(xx.min()), int(xx.max()), int(yy.min()), int(yy.max())
    box = (x1-x0+1)*(y1-y0+1)
    assert 16*area >= 13*box, 'fixture must be a dense rectangle'
    expected = [2, area, x0, x1, y0, y1, 0]
    words.extend(expected)
    records.append(dict(frame=frame, expected=expected, accepted_mask_sha256=hashlib.sha256(accepted.tobytes()).hexdigest()))
(dest/'quality_epoch_expected.mem').write_text('\n'.join(f'{v:08x}' for v in words)+'\n')
(dest/'quality_epoch_manifest.json').write_text(json.dumps(dict(width=W, height=H, records=records), indent=2))
print(json.dumps(records))
