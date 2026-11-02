# Writes Godot .import files for assets loaded from code (so they get VRAM compression + mipmaps,
# and music loops). Run before the first import.
import os, glob
def tex(path, normal=False, hdr=False):
    rel = 'res://' + path
    open(path + '.import', 'w').write(f'''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{rel}"

[params]

compress/mode=2
compress/high_quality={'true' if hdr else 'false'}
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map={1 if normal else 0}
compress/channel_pack=0
mipmaps/generate={'false' if hdr else 'true'}
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/size_limit=0
detect_3d/compress_to=0
''')
for f in glob.glob('assets/tex/*/*.jpg'): tex(f, normal=f.endswith('normal.jpg'))
for f in glob.glob('assets/hdr/*.hdr'): tex(f, hdr=True)
for f in glob.glob('assets/audio/music/*.ogg'):
    open(f + '.import', 'w').write(f'''[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[deps]

source_file="res://{f}"

[params]

loop=true
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
''')
print('ok')
