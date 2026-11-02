# Download Poly Haven PBR sets and HDRIs (all CC0) for the PC edition.
import json, os, urllib.request
op = urllib.request.build_opener(); op.addheaders = [('User-Agent', 'mishmeret-layla-pc-build')]
OUT = '../assets'
SETS = {  # name: (polyhaven id, hero 4K?)
  'asphalt': ('asphalt_02', True), 'limestone': ('large_sandstone_blocks', True), 'deck': ('metal_plate', True), 'tiles': ('floor_tiles_08', True),
  'pavers': ('concrete_pavers_02', False), 'plaster': ('plastered_wall_02', False), 'concrete': ('concrete_wall_008', False), 'brick': ('brick_wall_02', False),
  'corrugated': ('corrugated_iron_02', False), 'planks': ('brown_planks_05', False), 'facade_tiles': ('rectangular_facade_tiles', False), 'shutter': ('painted_metal_shutter', False),
}
def get(url, path):
    if os.path.exists(path): return
    data = op.open(url, timeout=600).read(); open(path, 'wb').write(data)
for name, (pid, hero) in SETS.items():
    j = json.loads(op.open(f'https://api.polyhaven.com/files/{pid}').read())
    os.makedirs(f'{OUT}/tex/{name}', exist_ok=True)
    for key, short, res in [('Diffuse', 'color', '4k' if hero else '2k'), ('nor_gl', 'normal', '4k' if hero else '2k'), ('arm', 'orm', '2k'), ('Displacement', 'height', '2k')]:
        if key == 'Displacement' and not hero: continue
        try: url = j[key][res]['jpg']['url']
        except KeyError: url = j[key]['2k']['jpg']['url']
        get(url, f'{OUT}/tex/{name}/{short}.jpg')
    print('tex', name, flush=True)
for name, pid in {'afternoon': 'kloofendal_43d_clear_puresky', 'sunset': 'qwantani_sunset_puresky', 'night': 'rooftop_night'}.items():
    j = json.loads(op.open(f'https://api.polyhaven.com/files/{pid}').read())
    get(j['hdri']['4k']['hdr']['url'], f'{OUT}/hdr/{name}.hdr'); print('hdr', name, flush=True)
