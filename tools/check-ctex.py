# CI gate: every imported 3D texture must be VRAM-compressed (BC/BPTC/RGTC), whatever its size.
# Parses the CompressedTexture2D header (.ctex "GST2") of everything in .godot/imported and exits
# non-zero, listing the offenders, if any is stored as raw/PNG/WebP (RGB8, RGBA8, ...).
# UI icons rasterized from SVG are 2D and exempt.
import os, struct, sys, glob, collections
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

FORMATS = ['L8', 'LA8', 'R8', 'RG8', 'RGB8', 'RGBA8', 'RGBA4444', 'RGB565', 'RF', 'RGF', 'RGBF', 'RGBAF',
           'RH', 'RGH', 'RGBH', 'RGBAH', 'RGBE9995', 'DXT1', 'DXT3', 'DXT5', 'RGTC_R', 'RGTC_RG',
           'BPTC_RGBA', 'BPTC_RF', 'BPTC_RFU']
DATA = ['IMAGE', 'PNG', 'WEBP', 'BASIS']
bad, stats, total = [], collections.Counter(), 0
for path in sorted(glob.glob('.godot/imported/*.ctex')):
    name = os.path.basename(path)
    with open(path, 'rb') as f:
        h = f.read(52)
    if len(h) < 52 or h[:4] != b'GST2':
        bad.append((name, 'not a GST2 texture')); continue
    w, hh = struct.unpack_from('<II', h, 8)
    data_format, = struct.unpack_from('<I', h, 36)
    fmt, = struct.unpack_from('<I', h, 48)
    fname = FORMATS[fmt] if fmt < len(FORMATS) else 'fmt%d' % fmt
    dname = DATA[data_format] if data_format < len(DATA) else str(data_format)
    total += 1
    stats['%s/%s' % (dname, fname)] += 1
    if '.svg-' in name:
        continue
    compressed = data_format in (0, 3) and fmt >= 17
    if not compressed:
        bad.append((name, '%dx%d %s %s' % (w, hh, dname, fname)))
print('textures:', total)
for k, v in sorted(stats.items()):
    print('  %-22s %d' % (k, v))
if total == 0:
    print('FAIL: no imported textures found'); sys.exit(1)
if bad:
    print('FAIL: %d textures are not VRAM-compressed:' % len(bad))
    for n, why in bad:
        print('  ', n, why)
    sys.exit(1)
print('OK: every 3D texture is VRAM-compressed')
