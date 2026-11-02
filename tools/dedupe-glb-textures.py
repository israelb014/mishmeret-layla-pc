# Moves the images embedded in assets/props/*.glb into one shared folder (assets/props/tex/) and
# makes every .glb reference them by relative URI. The building/ornament kits embed the same 2K
# textures in dozens of models; Godot used to extract and import one copy per model.
# Original image names are kept (so "*_Normal" maps are imported as BC5 normal maps); two
# different images with the same name get a short content hash suffix.
import os, json, struct, hashlib, glob
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
OUT = 'assets/props/tex'
os.makedirs(OUT, exist_ok=True)
by_hash, names = {}, {}
moved = 0
for path in sorted(glob.glob('assets/props/*.glb')):
    b = open(path, 'rb').read()
    jlen = struct.unpack_from('<I', b, 12)[0]
    j = json.loads(b[20:20 + jlen])
    rest = b[20 + jlen:] # BIN chunk (header included), unchanged
    bin_data = rest[8:8 + struct.unpack_from('<I', rest, 0)[0]] if rest else b''
    changed = False
    for img in j.get('images', []):
        if 'bufferView' not in img:
            continue
        bv = j['bufferViews'][img['bufferView']]
        data = bin_data[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        h = hashlib.md5(data).hexdigest()
        ext = 'png' if img.get('mimeType') == 'image/png' else 'jpg'
        if h not in by_hash:
            base = img.get('name') or h[:8]
            fname = '%s.%s' % (base, ext)
            if fname in names and names[fname] != h:
                fname = '%s_%s.%s' % (base, h[:6], ext)
            names[fname] = h
            by_hash[h] = fname
            open(os.path.join(OUT, fname), 'wb').write(data)
        img.pop('bufferView'); img.pop('mimeType', None)
        img['uri'] = 'tex/' + by_hash[h]
        changed = True
        moved += 1
    if not changed:
        continue
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + len(rest)) + struct.pack('<I4s', len(js), b'JSON') + js + rest
    open(path, 'wb').write(out)
# the per-model copies Godot extracted earlier are obsolete
removed = 0
for f in glob.glob('assets/props/*_*.jpg') + glob.glob('assets/props/*_*.png'):
    stem = os.path.basename(f)
    if any(stem.startswith(os.path.basename(g)[:-4] + '_') for g in glob.glob('assets/props/*.glb')):
        for x in (f, f + '.import'):
            if os.path.exists(x): os.remove(x); removed += 1
print('images re-linked:', moved, '| unique files:', len(by_hash), '| removed extracted copies:', removed)
