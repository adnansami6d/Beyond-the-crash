extends Node3D
# v_023 / v_024: 400 trees of 9 kinds (spruce, pine, poplar, ...) from the low poly forest pack (assets/grass/items/bg_tree_01..08, 10).
# Fixed places (same every game, seed below), chosen by biome: many in the forest, some in the swamp / farm land, few on the rocky
# land, very few in the desert. Nothing grows on buildings, ponds, plots, the start area, the mountain or the railway (Flora.spot_ok),
# and trees keep MIN_GAP metres from each other. The trunk of every tree is solid (thin cylinder).

const Biome = preload("res://scripts/biome.gd")
const Flora = preload("res://scripts/flora.gd")
const SaveGame = preload("res://scripts/savegame.gd")

const COUNT := 400
const SEED := 20261115
const MIN_GAP := 14.0
const FILES := ["01", "02", "03", "04", "05", "06", "07", "08", "10"]
# chance of each kind per biome [farm, forest, rock, desert, swamp]; kinds in the order of FILES
const KIND_W := [
	[2, 3, 3, 2, 2, 1, 1, 1, 2],   # farm
	[4, 2, 3, 4, 2, 2, 2, 2, 2],   # forest (many spruces / pines)
	[3, 0, 3, 2, 0, 1, 1, 1, 3],   # rock
	[0, 0, 0, 0, 0, 0, 0, 0, 0],   # desert (no trees)
	[1, 3, 1, 1, 3, 2, 2, 2, 1],   # swamp
]
const ACCEPT := [0.35, 1.0, 0.25, 0.0, 0.5]   # v_024: no trees in the desert
const DESERT_FILE := "res://assets/grass/items/desert_tree.glb"   # dead tree (3000 tris), 6 m tall, foot at 0,0,0
const DESERT_COUNT := 5   # only these few trees grow in the desert
const DESERT_TRUNK_R := 0.33
const DESERT_SCALE_MIN := 1.6   # v_041: desert dead tree size (model is 6 m tall) -> about 9.6 m .. 13.2 m
const DESERT_SCALE_MAX := 2.2
const TRUNK_R := [0.35, 0.45, 0.4, 0.35, 0.45, 0.35, 0.3, 0.3, 0.3]

var count := 0


func build(half: float) -> void:
	var meshes: Array = []
	for n in FILES:
		meshes.append(_solid_mesh(_mesh_of("res://assets/grass/items/bg_tree_%s.glb" % n)))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var xf: Array = []
	for i in FILES.size():
		xf.append([])
	var placed: Array = []
	var gap := {}   # 14 m squares -> trees inside (a fast "too close?" test)
	var body := StaticBody3D.new()
	body.set_meta("cuttable", true)   # the axe can cut these (shooter.gd)
	add_group_marker()
	add_child(body)
	var tries := 0
	while count < COUNT and tries < 20000:
		tries += 1
		var x := rng.randf_range(-half + 40.0, half - 40.0)
		var z := rng.randf_range(-half + 40.0, half - 40.0)
		var w: Array = Biome.weights(x, z)
		if float(w[3]) > 0.04:   # v_024: desert (and its soft border) stays free of trees
			continue
		var acc := 0.0
		for b in 5:
			acc += float(w[b]) * float(ACCEPT[b])
		if rng.randf() > acc:
			continue
		if not Flora.spot_ok(x, z, 3.0):
			continue
		var gk := Vector2i(floori(x / MIN_GAP), floori(z / MIN_GAP))
		var close := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var kk := Vector2i(gk.x + dx, gk.y + dz)
				if gap.has(kk):
					for q in gap[kk]:
						if (q as Vector2).distance_to(Vector2(x, z)) < MIN_GAP:
							close = true
		if close:
			continue
		if not gap.has(gk):
			gap[gk] = []
		gap[gk].append(Vector2(x, z))
		# kind: random by the weights of the biomes around
		var tw := []
		var sum := 0.0
		for k in FILES.size():
			var t := 0.0
			for b in 5:
				t += float(w[b]) * float((KIND_W[b] as Array)[k])
			tw.append(t)
			sum += t
		if sum <= 0.0:
			continue
		var pick := rng.randf() * sum
		var kind := 0
		for k in FILES.size():
			pick -= float(tw[k])
			if pick <= 0.0:
				kind = k
				break
		var sc := rng.randf_range(0.8, 1.25)
		xf[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(x, 0.0, z)))
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = float(TRUNK_R[kind]) * sc
		sh.height = 6.0
		cs.shape = sh
		cs.position = Vector3(x, 3.0, z)
		cs.set_meta("kind", "tree")
		cs.set_meta("size", sc)
		body.add_child(cs)
		count += 1
	for k in FILES.size():
		if meshes[k] == null or (xf[k] as Array).is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = (xf[k] as Array).size()
		for j in (xf[k] as Array).size():
			mm.set_instance_transform(j, (xf[k] as Array)[j])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-half, -1.0, -half), Vector3(half * 2.0, 40.0, half * 2.0))
		add_child(mi)
	_build_desert(half, body)
	SaveGame.apply_cuts(self)   # trees broken in an earlier session stay broken


# 5 dead trees in the desert (fixed places, same every game). They live in the same body/holder as the forest trees,
# so the axe can cut them and savegame.gd re-applies the cuts by position.
func _build_desert(half: float, body: StaticBody3D) -> void:
	var mesh := _solid_mesh(_mesh_of(DESERT_FILE))
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var spots: Array = []
	var need := 0.9
	var tries := 0
	while spots.size() < DESERT_COUNT and tries < 40000:
		tries += 1
		if tries == 20000:
			need = 0.6   # desert is small: relax a little if 5 spots were not found
		var x := rng.randf_range(-half + 40.0, half - 40.0)
		var z := rng.randf_range(-half + 40.0, half - 40.0)
		var w: Array = Biome.weights(x, z)
		if float(w[3]) < need:
			continue
		if not Flora.spot_ok(x, z, 3.0):
			continue
		var far := true
		for s in spots:
			if (s as Vector2).distance_to(Vector2(x, z)) < 25.0:
				far = false
		if far:
			spots.append(Vector2(x, z))
	if spots.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var p: Vector2 = spots[i]
		var sc := rng.randf_range(DESERT_SCALE_MIN, DESERT_SCALE_MAX)   # v_041: taller desert trees (was 0.85..1.2)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc, sc, sc)), Vector3(p.x, 0.0, p.y)))
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = DESERT_TRUNK_R * sc
		sh.height = 6.0 * sc   # v_041: trunk collision grows with the tree
		cs.shape = sh
		cs.position = Vector3(p.x, 3.0 * sc, p.y)   # v_041: stays standing on the ground
		cs.set_meta("kind", "tree")
		cs.set_meta("size", sc)
		body.add_child(cs)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-half, -1.0, -half), Vector3(half * 2.0, 40.0, half * 2.0))
	add_child(mi)


func add_group_marker() -> void:
	add_to_group("cut_holder")   # savegame.gd re-applies broken trees to this node


func _mesh_of(path: String) -> Mesh:
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var root: Node = (ps as PackedScene).instantiate()
	var found: Mesh = null
	var stack: Array = [root]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
	root.free()
	return found


# v_025: the tree material of the glb is "BLEND" (half see-through): the trunk foot looked see-through close up and mixed with the grass.
# Now every surface uses ALPHA SCISSOR (a pixel is fully solid or fully cut out), so trunks are always solid and sorted by depth.
func _solid_mesh(m: Mesh) -> Mesh:
	if m == null:
		return null
	var out := m.duplicate() as Mesh
	for i in out.get_surface_count():
		var mat = out.surface_get_material(i)
		if mat is BaseMaterial3D:
			var bm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			bm.alpha_scissor_threshold = 0.5
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.albedo_color = Color(1.9, 2.4, 1.6)   # FIX: the leaf / bark picture is very dark (avg 0.28), brighten it
			bm.normal_enabled = false   # FIX: flat leaf cards + normal map = black patches
			bm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP   # FIX: the side away from the sun is not black
			bm.roughness = 0.9
			out.surface_set_material(i, bm)
	return out
