# Download Poly Haven CC0 models (glTF, 2K textures) used to upgrade low-poly props.
import json, os, sys, urllib.request
op = urllib.request.build_opener(); op.addheaders = [('User-Agent', 'mishmeret-layla-pc-build')]
IDS = sys.argv[1:]
for pid in IDS:
    out = f'../assets/phm/{pid}'
    if os.path.exists(f'{out}/{pid}.gltf'): continue
    j = json.loads(op.open(f'https://api.polyhaven.com/files/{pid}').read())
    g = j['gltf'].get('2k') or j['gltf'].get('1k')
    g = g['gltf']
    os.makedirs(out, exist_ok=True)
    open(f'{out}/{pid}.gltf', 'wb').write(op.open(g['url']).read())
    for rel, inc in g.get('include', {}).items():
        p = os.path.join(out, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(op.open(inc['url']).read())
    info = json.loads(op.open(f'https://api.polyhaven.com/info/{pid}').read())
    print(pid, list(info.get('authors', {}).keys()), flush=True)
