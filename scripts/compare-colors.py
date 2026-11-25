#!/usr/bin/env python3
"""Local, opt-in paired-image regression. pip install pillow numpy scikit-image.

Convert embedded ICC profiles to sRGB, apply EXIF orientation, resize identically,
then measure CIEDE2000. Untagged files are assumed sRGB. Photos must be registered
and have the same aspect ratio. A low score on one photo is not general fidelity.
"""
import argparse
import io
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageCms, ImageOps
from skimage.color import rgb2lab, deltaE_ciede2000

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('reference', type=Path)
parser.add_argument('candidates', type=Path, nargs='+')
parser.add_argument('--width', type=int, default=960)
parser.add_argument('--output', type=Path)
parser.add_argument('--max-mean', type=float, help='Optional regression threshold for every candidate')
args = parser.parse_args()
if args.width < 16: parser.error('--width must be at least 16')

def read(path, size=None):
    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source)
        profile = image.info.get('icc_profile')
        if profile:
            image = ImageCms.profileToProfile(image, ImageCms.ImageCmsProfile(io.BytesIO(profile)), ImageCms.createProfile('sRGB'), outputMode='RGB')
        else:
            image = image.convert('RGB')
        if size and abs(image.width / image.height - size[0] / size[1]) > .005:
            raise ValueError(f'Aspect ratio differs: {path}')
        size = size or (args.width, round(image.height * args.width / image.width))
        return np.asarray(image.resize(size, Image.Resampling.LANCZOS), dtype=float) / 255, bool(profile)

reference, profile = read(args.reference)
lab = rgb2lab(reference)
report = {'reference': str(args.reference), 'comparison_space': 'sRGB / Lab D65',
          'reference_has_icc': profile, 'size': [reference.shape[1], reference.shape[0]],
          'metric': 'CIEDE2000 (lower is better)', 'results': []}
for path in args.candidates:
    candidate, tagged = read(path, tuple(report['size']))
    difference = deltaE_ciede2000(rgb2lab(candidate), lab)
    tiles = [float(tile.mean()) for row in np.array_split(difference, 3, axis=0) for tile in np.array_split(row, 3, axis=1)]
    report['results'].append({'file': str(path), 'has_icc': tagged,
        'mean': float(difference.mean()), 'median': float(np.median(difference)),
        'p95': float(np.percentile(difference, 95)), 'grid_3x3_mean': tiles})
text = json.dumps(report, indent=2, ensure_ascii=False)
print(text)
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + '\n')
if args.max_mean is not None and any(row['mean'] > args.max_mean for row in report['results']):
    raise SystemExit(1)
