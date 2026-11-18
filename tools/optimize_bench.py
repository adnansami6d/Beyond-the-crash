#!/usr/bin/env python3
"""Optimise old_bench_3d_scan_free.glb: bake node transforms, scale to LENGTH m, long side along X, feet y=0,
simplify (UV aware), colour map 512 jpeg, no normal map, pack uint16.
usage: optimize_bench.py in.glb out.glb tris [length_m] [tex_size] [weld]   (near model: no weld; far LOD: weld)"""
import sys, os, json, struct, io, importlib.util
import numpy as np
from PIL import Image
spec = importlib.util.spec_from_file_location('shrink', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'shrink_glb.py'))
sh = importlib.util.module_from_spec(spec); spec.loader.exec_module(sh)
src, dst, tris = sys.argv[1], sys.argv[2], int(sys.argv[3])
LENGTH = float(sys.argv[4]) if len(sys.argv) > 4 else 1.8
TEX = int(sys.argv[5]) if len(sys.argv) > 5 else 512
j, b = sh.read_glb(src)
def M(n): return np.array(n['matrix'], float).reshape(4, 4).T if 'matrix' in n else np.eye(4)
parent = {}
for i, n in enumerate(j['nodes']):
    for c in n.get('children', []): parent[c] = i
def world(i):
    m = M(j['nodes'][i])
    while i in parent:
        i = parent[i]; m = M(j['nodes'][i]) @ m
    return m
ni = [i for i, n in enumerate(j['nodes']) if 'mesh' in n][0]
p = j['meshes'][j['nodes'][ni]['mesh']]['primitives'][0]
P = sh.acc(j, b, p['attributes']['POSITION']).astype(np.float64)
UV = sh.acc(j, b, p['attributes']['TEXCOORD_0']).astype(np.float64)
T = sh.acc(j, b, p['indices']).reshape(-1, 3).astype(np.int64)
P = (np.hstack([P, np.ones((len(P), 1))]) @ world(ni).T)[:, :3]
# yaw-align: principal axis of the top view (x,z) -> X
C = np.cov((P[:, [0, 2]] - P[:, [0, 2]].mean(0)).T)
w, v = np.linalg.eigh(C); main = v[:, 1]
ang = np.arctan2(main[1], main[0])
c, sn = np.cos(-ang), np.sin(-ang)
xz = P[:, [0, 2]] @ np.array([[c, sn], [-sn, c]])
P = np.stack([xz[:, 0], P[:, 1], xz[:, 1]], 1)
print('yaw', np.degrees(ang))
lo, hi = P.min(0), P.max(0); ext = hi - lo
print('extent', ext)
# long side -> X
s = LENGTH / (hi[0] - lo[0])
P = (P - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) * s
print('final size', P.max(0) - P.min(0))
# weld seam twins (same place) so they can be simplified; uv of the first one is kept
if len(sys.argv) > 6 and sys.argv[6] == 'weld':   # far LOD: weld the UV seams too (texture may stretch a little, nobody sees it from far)
    key = np.round(P / 1e-4).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True); inv = inv.reshape(-1)
    P, UV = P[first], UV[first]; T = inv[T]
    T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
    print('welded verts', len(P))
T2 = sh.simplify(P, UV, T, tris)
used = np.unique(T2); rm = -np.ones(len(P), np.int64); rm[used] = np.arange(len(used))
Pf, UVf, Tf = P[used], UV[used], rm[T2]
fn = np.cross(Pf[Tf[:, 1]] - Pf[Tf[:, 0]], Pf[Tf[:, 2]] - Pf[Tf[:, 0]])
N = np.zeros_like(Pf)
for c in range(3): np.add.at(N, Tf[:, c], fn)
N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
print('verts', len(Pf), 'tris', len(Tf))
out = bytearray(); views = []; accs = []
def addview(data, target=None):
    while len(out) % 4: out.append(0)
    v = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}
    if target: v['target'] = target
    views.append(v); out.extend(data); return len(views) - 1
vi = addview(Tf.astype(np.uint16).tobytes(), 34963)
vp = addview(Pf.astype(np.float32).tobytes(), 34962)
vn = addview(N.astype(np.float32).tobytes(), 34962)
vu = addview(UVf.astype(np.float32).tobytes(), 34962)
accs += [{'bufferView': vp, 'componentType': 5126, 'count': len(Pf), 'type': 'VEC3', 'min': Pf.min(0).tolist(), 'max': Pf.max(0).tolist()},
         {'bufferView': vn, 'componentType': 5126, 'count': len(Pf), 'type': 'VEC3'},
         {'bufferView': vu, 'componentType': 5126, 'count': len(Pf), 'type': 'VEC2'},
         {'bufferView': vi, 'componentType': 5123, 'count': int(Tf.size), 'type': 'SCALAR'}]
im = j['images'][0]; bv = j['bufferViews'][im['bufferView']]
img = Image.open(io.BytesIO(b[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])).convert('RGB')
print('colour map', img.size)
img = img.resize((TEX, TEX), Image.LANCZOS)
buf = io.BytesIO(); img.save(buf, 'JPEG', quality=82, optimize=True)
vimg = addview(buf.getvalue())
print('texture bytes', len(buf.getvalue()))
g = {'asset': {'version': '2.0', 'generator': 'bench optimizer'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
     'nodes': [{'name': 'Bench', 'mesh': 0}],
     'meshes': [{'name': 'Bench', 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0}]}],
     'materials': [{'name': 'bench', 'doubleSided': False, 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'metallicFactor': 0.0, 'roughnessFactor': 0.9}}],
     'textures': [{'sampler': 0, 'source': 0}], 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
     'images': [{'bufferView': vimg, 'mimeType': 'image/jpeg'}],
     'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(out)}]}
js = json.dumps(g).encode()
while len(js) % 4: js += b' '
while len(out) % 4: out.append(0)
glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
open(dst, 'wb').write(glb); print('wrote', dst, len(glb))
