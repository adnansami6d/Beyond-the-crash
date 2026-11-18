#!/usr/bin/env python3
"""Optimise cloth_ghost.glb: bake node transforms, weld, simplify, smooth normals, pack uint16.
usage: optimize_ghost.py in.glb out.glb tris_cloth tris_skin"""
import sys, json, struct, importlib.util
import numpy as np
import os
spec = importlib.util.spec_from_file_location('shrink', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shrink_glb.py'))
sh = importlib.util.module_from_spec(spec); spec.loader.exec_module(sh)

src, dst, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
j, b = sh.read_glb(src)

def M(n):
    if 'matrix' in n: return np.array(n['matrix'], float).reshape(4, 4).T
    return np.eye(4)
# world matrix of each mesh node
parent = {}
for i, n in enumerate(j['nodes']):
    for c in n.get('children', []): parent[c] = i
def world(i):
    m = M(j['nodes'][i])
    while i in parent:
        i = parent[i]; m = M(j['nodes'][i]) @ m
    return m

meshes = []
for i, n in enumerate(j['nodes']):
    if 'mesh' not in n: continue
    p = j['meshes'][n['mesh']]['primitives'][0]
    P = sh.acc(j, b, p['attributes']['POSITION']).astype(np.float64)
    T = sh.acc(j, b, p['indices']).reshape(-1, 3).astype(np.int64)
    W = world(i)
    P = (np.hstack([P, np.ones((len(P), 1))]) @ W.T)[:, :3]
    meshes.append((n['name'], p['material'], P, T))
allp = np.vstack([m[2] for m in meshes])
lo, hi = allp.min(0), allp.max(0)
print('bounds', lo, hi)
H = 1.524
s = H / (hi[1] - lo[1])
off = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])

out = bytearray(); views = []; accs = []; prims = []
for k, (name, mat, P, T) in enumerate(meshes):
    # weld by position
    key = np.round(P / 1e-4).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inv = inv.reshape(-1)
    Pw = P[first]; Tw = inv[T]
    Tw = Tw[(Tw[:, 0] != Tw[:, 1]) & (Tw[:, 1] != Tw[:, 2]) & (Tw[:, 0] != Tw[:, 2])]
    print(name, 'welded', len(P), '->', len(Pw), 'tris', len(Tw))
    Ps = (Pw - off) * s
    target = (t0, t1)[k]
    T2 = sh.simplify(Ps, np.zeros((len(Ps), 2)), Tw, target)
    used = np.unique(T2); remap = -np.ones(len(Ps), np.int64); remap[used] = np.arange(len(used))
    Pf = Ps[used]; Tf = remap[T2]
    # smooth normals
    fn = np.cross(Pf[Tf[:, 1]] - Pf[Tf[:, 0]], Pf[Tf[:, 2]] - Pf[Tf[:, 0]])
    N = np.zeros_like(Pf)
    for c in range(3): np.add.at(N, Tf[:, c], fn)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
    print(name, 'final verts', len(Pf), 'tris', len(Tf))
    def addview(data, target):
        while len(out) % 4: out.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data), 'target': target}); out.extend(data); return len(views) - 1
    vi = addview(Tf.astype(np.uint16).tobytes(), 34963)
    vp = addview(Pf.astype(np.float32).tobytes(), 34962)
    vn = addview(N.astype(np.float32).tobytes(), 34962)
    a0 = len(accs)
    accs.append({'bufferView': vp, 'componentType': 5126, 'count': len(Pf), 'type': 'VEC3', 'min': Pf.min(0).tolist(), 'max': Pf.max(0).tolist()})
    accs.append({'bufferView': vn, 'componentType': 5126, 'count': len(Pf), 'type': 'VEC3'})
    accs.append({'bufferView': vi, 'componentType': 5123, 'count': int(Tf.size), 'type': 'SCALAR'})
    prims.append({'attributes': {'POSITION': a0, 'NORMAL': a0 + 1}, 'indices': a0 + 2, 'material': mat})
mats = [{'name': m['name'], 'doubleSided': True, 'pbrMetallicRoughness': m['pbrMetallicRoughness']} for m in j['materials']]
g = {'asset': {'version': '2.0', 'generator': 'ghost optimizer'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
     'nodes': [{'name': 'Ghost', 'mesh': 0}], 'meshes': [{'name': 'Ghost', 'primitives': prims}],
     'materials': mats, 'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(out)}]}
js = json.dumps(g).encode()
while len(js) % 4: js += b' '
while len(out) % 4: out.append(0)
glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
open(dst, 'wb').write(glb); print('wrote', dst, len(glb))
