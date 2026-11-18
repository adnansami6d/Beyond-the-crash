extends Node3D
# v_021: GRASS over the whole map (grass tufts, round bushes, small plants from the low poly forest pack).
# Made in 50 m squares around the camera (like stream.gd): only the nearby squares exist, far ones are deleted.
# The same square always gives the same grass (the random seed comes from the square number).
#  - colour follows the ground: green on farm land / forest, dark green in the swamp, grey-green on the rocky land,
#    dry yellow-brown in the desert (the tint is mixed from Biome.weights, same numbers as the ground shader)
#  - patchy: a slow noise makes some places THICK and some places THIN / bare (never the same everywhere)
#  - nothing grows on buildings, ponds, plots, the start area, the mountain or the railway (Flora.spot_ok)
#  - no collision (you walk through it), no shadow, drawn only up to VIS_END metres

const Biome = preload("res://scripts/biome.gd")
const Flora = preload("res://scripts/flora.gd")

const CHUNK := 50.0
const LOAD_R := 105.0   # build a square when its centre is closer than this
const KEEP_R := 140.0   # delete a square when its centre is farther than this
const VIS_END := 120.0  # grass farther than this from the camera is not drawn
const GRID := 18        # 18 x 18 cells per square (about 2.8 m each): small tufts, close together

# 0 = grass tuft (5.2 m wide), 1 = round bush, 2 / 3 = small plants
const FILES := [
	"res://assets/grass/items/bg_tree_09.glb", "res://assets/grass/items/bg_tree_11.glb",
	"res://assets/grass/items/bg_tree_12.glb", "res://assets/grass/items/bg_tree_13.glb",
]

# per biome [farm, forest, rock, desert, swamp]
const D_GRASS := [1.10, 1.40, 0.45, 0.25, 1.40]
const D_BUSH := [0.007, 0.027, 0.007, 0.013, 0.022]
const D_PLANT := [0.018, 0.054, 0.013, 0.009, 0.045]
# tint (multiplied with the picture of the pack) per biome
const TINT := [
	Color(0.92, 1.00, 0.62),   # farm: fresh green
	Color(0.74, 0.95, 0.58),   # forest: darker green
	Color(0.80, 0.88, 0.62),   # rock: grey-green
	Color(1.00, 0.90, 0.58),   # desert: dry yellow
	Color(0.66, 0.86, 0.52),   # swamp: dark wet green
]

var half := 500.0
var rail: Node = null

var _meshes: Array = []
var _mats: Array = []
var _chunks := {}
var _t := 1.0
var _building := false
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()


func start() -> void:
	for f in FILES:
		var ps = load(f)
		var mesh: Mesh = null
		if ps is PackedScene:
			var root: Node = (ps as PackedScene).instantiate()
			var stack: Array = [root]
			while not stack.is_empty() and mesh == null:
				var n: Node = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
				if n is MeshInstance3D:
					mesh = (n as MeshInstance3D).mesh
			root.free()
		var mat: Material = null
		if mesh != null and mesh.get_surface_count() > 0:
			var m0 = mesh.surface_get_material(0)
			if m0 is BaseMaterial3D:
				var m := (m0 as BaseMaterial3D).duplicate() as BaseMaterial3D
				m.vertex_color_use_as_albedo = true   # the colour of each plant (tint) is multiplied with the picture
				m.albedo_color = Color(1.0, 1.5, 0.9)   # FIX: pack picture is dark + yellow; this pushes it to the SAME green as the ground picture (ground avg 0.21/0.34/0.08)
				m.normal_enabled = false   # FIX: flat cards + normal map = black patches
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP   # FIX: the side away from the sun is not black
				m.roughness = 0.9
				mat = m
		_meshes.append(mesh)
		_mats.append(mat)
	_n1.seed = 4711
	_n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n1.frequency = 0.011   # big patches (thick / thin grass)
	_n2.seed = 815
	_n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n2.frequency = 0.045   # small patches


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25 and not _building:
		_t = 0.0
		_update()


func _centre(k: Vector2i) -> Vector2:
	return Vector2((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)


func _update() -> void:
	var cam := get_viewport().get_camera_3d()
	var cp := Vector2.ZERO
	if cam != null:
		cp = Vector2(cam.global_position.x, cam.global_position.z)
	for k in _chunks.keys():
		if _centre(k).distance_to(cp) > KEEP_R:
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
	var ck := Vector2i(floori(cp.x / CHUNK), floori(cp.y / CHUNK))
	var best := Vector2i.ZERO
	var bd := LOAD_R
	var found := false
	var mapr := Rect2(-half, -half, half * 2.0, half * 2.0)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if _chunks.has(k) or not mapr.intersects(Rect2(float(k.x) * CHUNK, float(k.y) * CHUNK, CHUNK, CHUNK)):
				continue
			var d := _centre(k).distance_to(cp)
			if d < bd:
				bd = d
				best = k
				found = true
	if found:
		_build(best)


# how thick the grass is at (x, z): about 0.1 (almost bare) ... 1.5 (very thick)
func _patch(x: float, z: float) -> float:
	var a := _n1.get_noise_2d(x, z)   # -1 .. 1
	var b := _n2.get_noise_2d(x, z)
	var t := smoothstep(-0.30, 0.40, a)
	return clampf(0.10 + 1.25 * t + 0.25 * b, 0.05, 1.5)


func _build(k: Vector2i) -> void:
	_building = true
	var node := Node3D.new()
	var cx := (float(k.x) + 0.5) * CHUNK
	var cz := (float(k.y) + 0.5) * CHUNK
	node.position = Vector3(cx, 0.0, cz)
	add_child(node)
	_chunks[k] = node
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	var rng := RandomNumberGenerator.new()
	rng.seed = (k.x * 73856093) ^ (k.y * 19349663) ^ 31337
	var cell := CHUNK / float(GRID)
	var xf: Array = [[], [], [], []]
	var col: Array = [[], [], [], []]
	for gx in GRID:
		if gx % 3 == 2:
			await get_tree().process_frame
			if not _chunks.has(k):
				_building = false
				return
		for gz in GRID:
			var x := x0 + (float(gx) + rng.randf()) * cell
			var z := z0 + (float(gz) + rng.randf()) * cell
			var r1 := rng.randf()
			var r2 := rng.randf()
			var r3 := rng.randf()
			var w: Array = Biome.weights(x, z)
			var dg := 0.0
			var db := 0.0
			var dp := 0.0
			var tint := Color(0, 0, 0)
			for i in 5:
				var wi: float = w[i]
				dg += wi * D_GRASS[i]
				db += wi * D_BUSH[i]
				dp += wi * D_PLANT[i]
				tint += (TINT[i] as Color) * wi
			var patch := _patch(x, z)
			dg *= patch
			var desert: float = w[3]
			var swamp: float = w[4]
			var lx := x - cx
			var lz := z - cz
			var shade := rng.randf_range(0.82, 1.08)
			var c := Color(clampf(tint.r * shade, 0, 1), clampf(tint.g * shade, 0, 1), clampf(tint.b * shade, 0, 1), 1.0)
			# grass tuft: dg can be above 1 (very thick = a second tuft in the same cell)
			if r1 < dg and Flora.spot_ok(x, z, 0.0):
				var s := rng.randf_range(0.24, 0.42) * lerpf(1.0, 0.8, desert)   # FIX: smaller, so the tufts are not tall, odd walls on the ground
				xf[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s, s * 0.75 * lerpf(0.9, 1.3, swamp) * rng.randf_range(0.8, 1.2), s)), Vector3(lx, 0.0, lz)))
				col[0].append(c)
				if dg > 1.0 and r2 < dg - 1.0:
					var x2 := x + rng.randf_range(-1.4, 1.4)
					var z2 := z + rng.randf_range(-1.4, 1.4)
					if Flora.spot_ok(x2, z2, 0.0):
						var s2 := rng.randf_range(0.22, 0.38)
						xf[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(s2, s2, s2)), Vector3(x2 - cx, 0.0, z2 - cz)))
						col[0].append(c)
			# round bush (thicker where the grass is thick)
			if r2 < db * (0.4 + patch) and Flora.spot_ok(x + 1.0, z + 1.0, 1.5):
				var sb := rng.randf_range(0.6, 1.3)
				xf[1].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sb, sb, sb)), Vector3(lx + 1.0, 0.0, lz + 1.0)))
				col[1].append(c)
			# small plants
			if r3 < dp * (0.4 + patch) and Flora.spot_ok(x - 1.0, z - 1.0, 0.5):
				var kind := 2 + (1 if rng.randf() < 0.5 else 0)
				var sp := rng.randf_range(0.7, 1.4)
				xf[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sp, sp, sp)), Vector3(lx - 1.0, 0.0, lz - 1.0)))
				col[kind].append(c)
	await get_tree().process_frame
	if not _chunks.has(k) or not is_instance_valid(node):
		_building = false
		return
	for i in 4:
		_add_multi(node, i, xf[i], col[i])
	_building = false


func _add_multi(parent: Node, i: int, xforms: Array, colors: Array) -> void:
	if xforms.is_empty() or _meshes[i] == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _meshes[i]
	mm.instance_count = xforms.size()
	for j in xforms.size():
		mm.set_instance_transform(j, xforms[j])
		mm.set_instance_color(j, colors[j])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if _mats[i] != null:
		mi.material_override = _mats[i]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIS_END
	# the instances are spread over the whole square: tell the culling box (local, centred on the square)
	mi.custom_aabb = AABB(Vector3(-CHUNK * 0.5 - 3.0, -1.0, -CHUNK * 0.5 - 3.0), Vector3(CHUNK + 6.0, 6.0, CHUNK + 6.0))
	parent.add_child(mi)
