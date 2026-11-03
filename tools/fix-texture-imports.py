# Forces VRAM compression for every 3D texture in the project (run before importing; CI runs it
# again after the first import because the glTF importer may rewrite the .import files of the
# textures it extracts from .glb files).
#   larger than 256 px  -> VRAM compressed: S3TC/BC (BC1/BC3), normal maps BC5 (RGTC), mipmaps
#   .hdr                -> VRAM compressed, high quality: BC6H (BPTC)
#   small textures      -> compressed as well (no RGB8 conversion warnings at load time)
# "detect_3d" is disabled everywhere: it only switches to VRAM compression inside the editor UI,
# never in a headless import, which is how the v1.0.0 textures ended up uncompressed.
import os, re, sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

NORMAL = re.compile(r'(normal|_nor(_gl|_dx)?[_.]|_nrm|_n\.)', re.I)

def setp(text, key, value):
    pat = re.compile(r'^%s=.*$' % re.escape(key), re.M)
    line = '%s=%s' % (key, value)
    if pat.search(text):
        return pat.sub(line, text)
    return text.replace('[params]\n', '[params]\n\n' + line + '\n', 1)

STUB = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://%s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/size_limit=0
detect_3d/compress_to=0
'''
# images that have no .import yet (e.g. the shared prop textures) get one before Godot sees them,
# otherwise Godot would create them with its lossless + detect_3d defaults
created = 0
for root, dirs, files in os.walk('assets'):
    for f in files:
        if f.lower().endswith(('.jpg', '.jpeg', '.png')) and not os.path.exists(os.path.join(root, f) + '.import'):
            src = os.path.join(root, f)
            open(src + '.import', 'w').write(STUB % src.replace(os.sep, '/'))
            created += 1
print('new .import files:', created)

changed = 0
small = 0
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.godot', '.git', 'build', 'dist', 'node_modules', 'docs', 'verification')]
    for f in files:
        if not f.endswith('.import'):
            continue
        path = os.path.join(root, f)
        src = path[:-7]
        text = open(path).read()
        if 'importer="texture"' not in text or not os.path.exists(src):
            continue
        hdr = src.lower().endswith(('.hdr', '.exr'))
        if src.lower().endswith('.svg'):
            continue # UI icons (2D)
        if not hdr and max(Image.open(src).size) <= 256:
            small += 1 # small tiles are compressed too (v1.0.1 left two RGB8 64x64 tiles lossless)
        new = text
        new = setp(new, 'compress/mode', 2)
        new = setp(new, 'compress/high_quality', 'true' if hdr else 'false')
        new = setp(new, 'compress/hdr_compression', 1)
        new = setp(new, 'compress/normal_map', 0 if hdr else (1 if NORMAL.search(os.path.basename(src)) else 2))
        new = setp(new, 'mipmaps/generate', 'false' if hdr else 'true')
        new = setp(new, 'detect_3d/compress_to', 0)
        if new != text:
            open(path, 'w').write(new)
            changed += 1
print('texture imports updated:', changed, '| of them small (<= 256 px):', small)
