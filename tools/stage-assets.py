# Builds data/stage_assets.json: which prefab models each stage needs, so the game loads only
# the main menu + stage 1 at startup and streams stages 2-3 in the background.
#   common  - prefabs used by code outside the set builders (weapons, pickups, effects, signs...)
#   stages  - per stage: prefabs referenced by its data (props, traffic, sets) and by every
#             builder function reachable from it (followed through calls and constants).
# A prefab missing from the list still works: it is loaded on that stage's loading screen.
import json, re, os, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

prefabs = set(json.load(open('data/prefabs.json')).keys())
up = open('scripts/world/prefabs.gd').read()
i = up.index('UPGRADES'); j = up.index('\n}', i)
prefabs |= set(re.findall(r'^\t"([a-z0-9_]+)":', up[i:j], re.M))

STR = re.compile(r'"([A-Za-z0-9_]+)"')
src = open('scripts/world/builders.gd').read()
consts = {m.group(1): set(STR.findall(m.group(2))) for m in re.finditer(r'^const ([A-Z_]+)\s*:?=\s*(\[.*?\]|\{.*?\})\s*$', src, re.M | re.S)}
funcs = {}
parts = re.split(r'^(?=static func |func )', src, flags=re.M)
for p in parts:
    m = re.match(r'(?:static )?func ([A-Za-z0-9_]+)\(', p)
    if m: funcs[m.group(1)] = p

def reach(fn, seen):
    if fn in seen or fn not in funcs: return set()
    seen.add(fn)
    body = funcs[fn]
    out = set(STR.findall(body)) & prefabs
    for c in consts:
        if re.search(r'\b%s\b' % c, body): out |= consts[c] & prefabs
    for call in set(re.findall(r'\b([a-z_][a-z0-9_]*)\(', body)):
        if call != fn: out |= reach(call, seen)
    return out

def strings(o, acc):
    if isinstance(o, dict):
        for k, v in o.items(): strings(v, acc)
        if 'kind' in o and isinstance(o['kind'], str): acc.add('set_' + o['kind'])
    elif isinstance(o, list):
        for v in o: strings(v, acc)
    elif isinstance(o, str): acc.add(o)
    return acc

# names used by code outside the builders (always loaded at startup)
common = set()
for root, _, files in os.walk('scripts'):
    for f in files:
        if f.endswith('.gd') and f != 'builders.gd':
            common |= set(STR.findall(open(os.path.join(root, f)).read())) & prefabs
# helpers every zone uses no matter the data (signs, lamps, decorations)
for fn in ('_decorate',):
    common |= reach(fn, set())

stages = []
for n in (1, 2, 3):
    st = json.load(open('data/stage%d.json' % n))
    s = strings(st, set())
    names = s & prefabs
    for fn in s:
        if fn in funcs: names |= reach(fn, set())
    names |= reach('run_set', set()) & set() # dispatch only (kinds are followed through set_<kind>)
    stages.append(sorted(names - common))

out = {'common': sorted(common), 'stages': stages}
json.dump(out, open('data/stage_assets.json', 'w'), indent=1)
print('common', len(common), 'stages', [len(s) for s in stages], 'unused', len(prefabs - common - set(sum(stages, []))))
