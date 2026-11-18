#!/usr/bin/env python3
"""Shrinks a static gun glb (no skin): bakes node transforms, scales to metres, moves the grip to the origin,
simplifies each mesh (reuses simplify() from shrink_glb.py), keeps only colour maps (resized).
usage: python3 shrink_gun.py in.glb out.glb total_triangles length_m gx gy gz   (gx gy gz = grip point in the source units, after node transforms)"""
import sys, json, struct, io, importlib.util
import numpy as np
from PIL import Image
spec = importlib.util.spec_from_file_location('sg', sys.argv[0].rsplit('/', 1)[0] + '/shrink_glb.py')
sg = importlib.util.module_from_spec(spec); spec.loader.exec_module(sg)

def nmat(n):
    return np.array(n['matrix']).reshape(4, 4).T if 'matrix' in n else np.eye(4)

def main():
    src, dst, total, length = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
    grip = np.array([float(x) for x in sys.argv[5:8]])
    j, b = sg.read_glb(src)
    parent = {}
    for i, n in enumerate(j['nodes']):
        for c in n.get('children', []):
            parent[c] = i
    def world(i):
        m = nmat(j['nodes'][i])
        while i in parent:
            i = parent[i]; m = nmat(j['nodes'][i]) @ m
        return m
    items = []
    for i, n in enumerate(j['nodes']):
        if 'mesh' not in n:
            continue
        p = j['meshes'][n['mesh']]['primitives'][0]
        at = p['attributes']
        P = sg.acc(j, b, at['POSITION']).astype(np.float64)
        N = sg.acc(j, b, at['NORMAL']).astype(np.float64)
        UV = sg.acc(j, b, at['TEXCOORD_0']).astype(np.float64)
        T = sg.acc(j, b, p['indices']).astype(np.int64).reshape(-1, 3)
        # weld vertices that share position + uv (the model is flat shaded, every face has its own vertices)
        key = np.round(np.hstack([P, UV * 100.0]), 4)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        P = P[first]; N = N[first]; UV = UV[first]; T = inv[T]
        T = T[(T[:, 0] != T[:, 1]) & (T[:, 1] != T[:, 2]) & (T[:, 0] != T[:, 2])]
        W = world(i)
        P = (W @ np.hstack([P, np.ones((len(P), 1))]).T).T[:, :3]
        N = (np.linalg.inv(W[:3, :3]).T @ N.T).T
        items.append((n['name'], p['material'], P, N, UV, T))
    allP = np.vstack([it[2] for it in items])
    sc = length / (allP[:, 2].max() - allP[:, 2].min())
    tris_all = sum(len(it[5]) for it in items)
    print('source tris', tris_all, 'scale', sc)
    out = bytearray(); views = []; accs = []
    def add_view(data, target=None):
        while len(out) % 4: out.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data), **({'target': target} if target else {})})
        out.extend(data); return len(views) - 1
    def add_acc(vi, ct, count, typ, **kw):
        accs.append({'bufferView': vi, 'componentType': ct, 'count': count, 'type': typ, **kw}); return len(accs) - 1
    meshes = []; nodes = []
    for name, mat, P, N, UV, T in items:
        tgt = max(60, int(total * len(T) / tris_all))
        print(name, 'tris', len(T), '-> target', tgt)
        if len(T) > tgt:
            T = sg.simplify(P, UV, T, tgt)
        used = np.unique(T)
        remap = -np.ones(len(P), np.int64); remap[used] = np.arange(len(used))
        T = remap[T]; P = P[used]; UV = UV[used]
        fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
        N = np.zeros_like(P)
        for k in range(3): np.add.at(N, T[:, k], fn)
        P = ((P - grip) * sc).astype('<f4')
        N = (N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-8)).astype('<f4')
        UV = UV.astype('<f4')
        prim = {'mode': 4, 'material': mat, 'attributes': {}}
        vi = add_view(P.tobytes(), 34962)
        prim['attributes']['POSITION'] = add_acc(vi, 5126, len(P), 'VEC3', min=P.min(0).tolist(), max=P.max(0).tolist())
        vi = add_view(N.tobytes(), 34962); prim['attributes']['NORMAL'] = add_acc(vi, 5126, len(N), 'VEC3')
        vi = add_view(UV.tobytes(), 34962); prim['attributes']['TEXCOORD_0'] = add_acc(vi, 5126, len(UV), 'VEC2')
        vi = add_view(T.astype('<u2').reshape(-1).tobytes(), 34963); prim['indices'] = add_acc(vi, 5123, T.size, 'SCALAR')
        meshes.append({'name': name, 'primitives': [prim]}); nodes.append({'name': name, 'mesh': len(meshes) - 1})
        print('   final tris', len(T))
    new_tex = []; new_img = []; tex_of = {}; mats = []
    for m in j['materials']:
        ti = m['pbrMetallicRoughness']['baseColorTexture']['index']
        if ti not in tex_of:
            im = j['images'][j['textures'][ti]['source']]
            bv = j['bufferViews'][im['bufferView']]
            img = Image.open(io.BytesIO(b[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]))
            img = img.convert('RGB').resize((256, 256), Image.LANCZOS)
            buf = io.BytesIO(); img.save(buf, 'JPEG', quality=85, optimize=True)
            vi = add_view(buf.getvalue())
            new_img.append({'bufferView': vi, 'mimeType': 'image/jpeg'})
            new_tex.append({'sampler': 0, 'source': len(new_img) - 1}); tex_of[ti] = len(new_tex) - 1
            print('texture', ti, len(buf.getvalue()), 'bytes')
        mats.append({'name': m['name'], 'pbrMetallicRoughness': {'baseColorTexture': {'index': tex_of[ti]}, 'metallicFactor': 0.25, 'roughnessFactor': 0.6}})
    while len(out) % 4: out.append(0)
    jj = {'asset': {'version': '2.0', 'generator': 'shrink_gun.py'}, 'scene': 0,
          'scenes': [{'nodes': [0]}],
          'nodes': [{'name': 'SMG', 'children': list(range(1, len(nodes) + 1))}] + nodes,
          'meshes': meshes, 'materials': mats, 'textures': new_tex, 'images': new_img,
          'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
          'bufferViews': views, 'accessors': accs, 'buffers': [{'byteLength': len(out)}]}
    js = json.dumps(jj, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
    open(dst, 'wb').write(glb); print('WROTE', dst, len(glb), 'bytes')
main()
