extends Node3D
# BEYOND THE CRASH - map of Fx99 (A1). Everything comes from res://data/layout.json (see data/README.txt).
# Same map as Fx99: ground, hill/sea/beach (coast.gd), railway + train, buildings, ponds, big solid rocks,
# (the roads and all trees except the coconut palms are DELETED)
# streamed rocks / reeds of the big map (stream.gd).
# REMOVED from Fx99 (never comes to Beyond the Crash): fields (soil), plow / seeder / sprayer / harvester / trailer, crops, shops economy,
# coins, fuel pump points, farm save. The "plots" list of layout.json is only kept as EMPTY LAND (no plants there).
#
# Questions the other scripts ask the world (main.gd, tractor.gd, camera_rig.gd, helicopter.gd, shooter.gd):
#   height_at(x, z), contains(x, z), spawn, tile_at(x, z)

const Util = preload("res://scripts/util.gd")
const Props = preload("res://scripts/props.gd")
const Coast = preload("res://scripts/coast.gd")
const Biome = preload("res://scripts/biome.gd")
const StreamScript = preload("res://scripts/stream.gd")
const RailwayScript = preload("res://scripts/railway.gd")
const GrassScript = preload("res://scripts/grass.gd")
const TreesScript = preload("res://scripts/trees.gd")
const Flora = preload("res://scripts/flora.gd")
const Cfg = preload("res://scripts/config.gd")
const MountainScript = preload("res://scripts/mountain.gd")
const TrainScript = preload("res://scripts/train.gd")
const LAYOUT_PATH := "res://data/layout.json"

var layout := {}
var map_half := 500.0
var spawn := Vector3(0, 3, 0)
var ponds: Array = []  # [{x, z, r}]
var rail_pts := PackedVector2Array()
var mountain = null   # F6: the big mountain (scripts/mountain.gd), null = none
var mountain_info := ""
var _mount_rect := Rect2()
var keep_clear: Array = []   # Rect2 list the mountain must not cover

var _rng := RandomNumberGenerator.new()


# main.gd calls this once
func build() -> void:
	layout = _read_layout()
	var g: Dictionary = layout.get("ground", {})
	map_half = float(g.get("size", 600.0)) / 2.0
	var gmat := _ground_material()
	var ground := _solid_box(Vector3(0, -0.5, 0), Vector3(map_half * 2.0, 1, map_half * 2.0), gmat)
	ground.collision_layer = 2   # ground = layer 2: the player + the helicopter ray see it, the tractor follows the ground by code
	ground.collision_mask = 0
	ground.add_to_group("voxel_ground")   # build.gd treats this group as ground
	var coast := Coast.new()   # sea (west, east, south, north) + beaches + edge walls
	add_child(coast)
	coast.build(map_half)

	var blocked: Array = [Rect2(-12, -12, 24, 24)]   # plants stay away from the start area
	var small: Array = [Rect2(-8, -8, 16, 16)]       # rocks keep a smaller distance
	keep_clear = [Rect2(-12, -12, 24, 24)]   # the mountain never covers: start area, buildings, ponds (plots are empty land, the mountain may cover them)
	for edge in [Rect2(-map_half, -map_half, map_half * 2.0, 24.0), Rect2(-map_half, -map_half, 22.0, map_half * 2.0), Rect2(map_half - 22.0, -map_half, 22.0, map_half * 2.0), Rect2(-map_half, map_half - 22.0, map_half * 2.0, 22.0)]:
		blocked.append(edge)   # hill foot + beaches stay free of plants
		small.append(edge)

	var railway := RailwayScript.new()
	add_child(railway)
	railway.build()
	var train := TrainScript.new()   # train (1 engine + 3 flat carriages), stops 60 s at every station
	add_child(train)
	train.setup(railway)
	for k in range(0, railway.path.size(), 5):
		rail_pts.append(Vector2(railway.path[k].x, railway.path[k].z))

	# former fields: now EMPTY LAND (only keeps plants away)
	var plots := {}
	for p in layout.get("plots", []):
		var rect := Rect2(float(p["x"]) - float(p["w"]) / 2.0, float(p["z"]) - float(p["d"]) / 2.0, float(p["w"]), float(p["d"]))
		plots[p["id"]] = rect
		blocked.append(rect.grow(4.0))
		small.append(rect.grow(2.0))

	for o in layout.get("objects", []):
		var node := Props.make(String(o["type"]))
		if node == null:
			continue
		node.position = Vector3(float(o["x"]), 0, float(o["z"]))
		node.rotation_degrees.y = float(o.get("rot", 0))
		add_child(node)
		_far_cull(node, 320.0)
		var f: Vector2 = Props.FOOT.get(String(o["type"]), Vector2(4, 4))
		if int(o.get("rot", 0)) % 180 != 0:
			f = Vector2(f.y, f.x)
		var fr := Rect2(float(o["x"]) - f.x / 2.0, float(o["z"]) - f.y / 2.0, f.x, f.y)
		blocked.append(fr.grow(4.0))
		small.append(fr.grow(1.5))
		keep_clear.append(fr.grow(4.0))

	for pd in layout.get("ponds", []):
		ponds.append(pd)
		_make_pond(pd)
		var pr := Rect2(float(pd["x"]) - float(pd["r"]), float(pd["z"]) - float(pd["r"]), float(pd["r"]) * 2.0, float(pd["r"]) * 2.0)
		blocked.append(pr.grow(4.0))
		small.append(pr.grow(2.0))
		keep_clear.append(pr.grow(4.0))

	if Cfg.SUN:   # F8: flat pieces (ground box, sand, roads, water, paint) cast no shadow: no stripes / acne on the ground
		for gi in find_children("*", "MeshInstance3D", true, false):
			var gmi := gi as MeshInstance3D
			if gmi.mesh != null and gmi.mesh.get_aabb().size.y < 0.35:
				gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for gm in ground.find_children("*", "MeshInstance3D", true, false):
			(gm as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Flora.setup(blocked, railway, map_half)   # F2: one shared "is this spot free?" for all new plants
	if Cfg.MOUNTAIN:   # F6: one big mountain in a free place (switch: config.gd)
		var mc := _mountain_site()
		mountain = MountainScript.new()
		mountain.cx = mc.x
		mountain.cz = mc.y
		add_child(mountain)
		mountain.build()
		mountain_info = mountain.info
		var mr: Rect2 = mountain.footprint()
		_mount_rect = mr.grow(6.0)
		blocked.append(_mount_rect)   # no trees / rocks / reeds on the mountain
		small.append(_mount_rect)
	_build_scatter(small, map_half)
	if map_half > 250.0:
		var stream := StreamScript.new()   # rocks / reeds of the big map, made around the camera
		stream.half = map_half
		var sb: Array = [Rect2(-200.0, -200.0, 400.0, 400.0)]
		if mountain != null:
			sb.append(_mount_rect)
		for pid in plots:
			sb.append((plots[pid] as Rect2).grow(5.0))
		for o in layout.get("objects", []):
			var ff: Vector2 = Props.FOOT.get(String(o["type"]), Vector2(4, 4))
			var m := maxf(ff.x, ff.y) + 10.0
			sb.append(Rect2(float(o["x"]) - m * 0.5, float(o["z"]) - m * 0.5, m, m))
		stream.blocks = sb
		stream.rail = railway
		add_child(stream)
		stream.start()
		var grass := GrassScript.new()   # v_021: grass / bushes over the whole map (colour follows the biome)
		grass.half = map_half
		grass.rail = railway
		add_child(grass)
		grass.start()
		var trees := TreesScript.new()   # v_023: 400 trees of 9 kinds
		add_child(trees)
		trees.build(map_half)


# F6: nearest free round place for the mountain, looking in rings around the map centre.
# FIX (mountain on the railway): the old search never found a place (the map is full) and then used a fixed spot that lay ON the
# railway. Now the place must (1) be farther than the mountain radius + 10 m from EVERY rail point, (2) not cover any building /
# pond / the start area (exact circle-rectangle test), (3) stay inside the map. Plots are empty land, so the mountain may cover them.
func _mountain_site() -> Vector2:
	var rad: float = MountainScript.R_MAX
	var r := 170.0
	while r <= 430.0:
		for k in 24:
			var a := 0.5 + TAU * float(k) / 24.0
			var c := Vector2(cos(a) * r, sin(a) * r)
			if _site_free(c, rad):
				return c
		r += 10.0
	# nothing free in the rings: take the place that is farthest from the railway (still never on it)
	var best := Vector2.ZERO
	var best_d := -1.0
	var x := -300.0
	while x <= 300.0:
		var z := -300.0
		while z <= 300.0:
			var c2 := Vector2(x, z)
			var dd := _rail_dist(c2)
			if dd > best_d:
				best_d = dd
				best = c2
			z += 20.0
		x += 20.0
	return best


func _rail_dist(c: Vector2) -> float:
	var best := INF
	for q in rail_pts:
		best = minf(best, (q as Vector2).distance_to(c))
	return best


func _site_free(c: Vector2, rad: float) -> bool:
	if absf(c.x) + rad > map_half - 28.0 or absf(c.y) + rad > map_half - 28.0:
		return false
	if _rail_dist(c) < rad + 10.0:
		return false
	for b in keep_clear:
		var rc: Rect2 = b
		var nx := clampf(c.x, rc.position.x, rc.end.x)
		var nz := clampf(c.y, rc.position.y, rc.end.y)
		if Vector2(nx, nz).distance_to(c) < rad:
			return false
	return true


# ---------------------------------------------------------------- questions of the other scripts

func height_at(x: float, z: float) -> float:
	if mountain != null and mountain.inside(x, z):
		return mountain.height_at(x, z)
	return 0.0   # the ground is flat


# is this place inside the map? (6 m away from the edge, like Fx99 heli.limit)
func contains(x: float, z: float) -> bool:
	return absf(x) < map_half - 6.0 and absf(z) < map_half - 6.0


# v_022: can a PLAYER stand here? The map plus the walkable sea floor round it (Coast.SEA_RUN m)
func contains_walk(x: float, z: float) -> bool:
	var lim: float = map_half + Coast.SEA_RUN - 2.0
	return absf(x) < lim and absf(z) < lim


func tile_at(_x: float, _z: float):
	return null




# ---------------------------------------------------------------- ground, roads, walls

func _ground_material() -> ShaderMaterial:
	# one shader paints the ground of all biomes (F11c grass + dirt pictures)
	var sh := Shader.new()
	var m := ShaderMaterial.new()
	var tex: Dictionary = {}
	if Cfg.REAL_GRASS:
		tex = Biome.load_ground_textures()
	if tex.size() > 0:
		sh.code = Biome.GROUND_SHADER
		m.shader = sh
		for k in tex:
			m.set_shader_parameter(k, tex[k])
		m.set_shader_parameter("bright", Cfg.GROUND_BRIGHT)
	else:
		sh.code = Biome.GRASS_SHADER   # pictures missing: noise grass (never a white ground)
		m.shader = sh
	return m


# ---------------------------------------------------------------- ponds

func _make_pond(pd: Dictionary) -> void:
	var r := float(pd["r"])
	var pos := Vector3(float(pd["x"]), 0, float(pd["z"]))
	var sand := Util.mim(Util.cyl(r + 1.6, 0.04, 28), Util.mat(Color(0.75, 0.68, 0.45), 1.0))
	sand.position = pos + Vector3(0, 0.02, 0)
	add_child(sand)
	var water := Util.mim(Util.cyl(r, 0.05, 28), Util.mat(Color(0.14, 0.42, 0.62), 0.1, 0.2))
	water.position = pos + Vector3(0, 0.05, 0)
	add_child(water)
	var reeds: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31.0 + pos.z * 17.0)
	for i in int(r * 1.5):
		var a := rng.randf() * TAU
		var d := r + rng.randf_range(0.2, 1.4)
		var s := rng.randf_range(0.8, 1.5)
		reeds.append(Transform3D(Basis.from_scale(Vector3(s, s, s)), pos + Vector3(cos(a) * d, 0.5 * s, sin(a) * d)))
	Util.multi(self, Util.cone(0.18, 1.0, 5), Util.mat(Color(0.25, 0.5, 0.15)), reeds)
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r * 0.97
	sh.height = 2.0
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	body.add_child(cs)
	add_child(body)

# ---------------------------------------------------------------- flowers (none placed now) ...

func _free_spot(rect: Rect2, near: Array) -> Variant:
	for t in 8:
		var q := Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
		var bad := false
		for b in near:
			if b.has_point(q):
				bad = true
				break
		if not bad:
			return q
	return null


func _near(blocked: Array, rect: Rect2) -> Array:
	var out: Array = []
	for b in blocked:
		if rect.intersects(b):
			out.append(b)
	return out


func _build_scatter(small: Array, half: float) -> void:
	var sc: Dictionary = layout.get("scatter", {})
	if sc.is_empty():
		return
	_rng.seed = int(sc.get("seed", 3))
	var ch := minf(half, 200.0)
	var whole := Rect2(-ch + 3.0, -ch + 3.0, ch * 2.0 - 6.0, ch * 2.0 - 6.0)
	var leaf_m := Util.vcol_mat()

	# the small scatter rocks are DELETED (the player could walk through them). Only the big solid rocks of stream.gd stay.

	var flowers: Array = []
	var fcol: Array = []
	var palette := [Color(0.9, 0.15, 0.15), Color(0.98, 0.85, 0.15), Color(0.97, 0.97, 0.95), Color(0.65, 0.3, 0.85), Color(1.0, 0.5, 0.15)]
	for i in int(sc.get("flower", 0)):
		var q = _free_spot(whole, small)
		if q == null:
			continue
		var col: Color = palette[_rng.randi() % palette.size()]
		for k in 7:
			var a := _rng.randf() * TAU
			var d := _rng.randf() * 1.3
			flowers.append(Transform3D(Basis(), Vector3(q.x + cos(a) * d, 0.12, q.y + sin(a) * d)))
			fcol.append(col)
	Util.multi(self, Util.sphere(0.085, 5, 3), leaf_m, flowers, fcol)


# ---------------------------------------------------------------- map data + helpers

func _read_layout() -> Dictionary:
	if ResourceLoader.exists(LAYOUT_PATH):
		var res = load(LAYOUT_PATH)   # .json is imported as a JSON resource (also works inside the APK)
		if res is JSON and res.data is Dictionary:
			return res.data
	if FileAccess.file_exists(LAYOUT_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if d is Dictionary:
			return d
	push_warning("layout.json not found or broken - using an empty map")
	return {"ground": {"size": 600}}


func _solid_box(pos: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.add_child(Util.mim(Util.box(size), material))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	return body


# parts of buildings farther than this from the camera are not drawn (less lag on the big map)
func _far_cull(n: Node, dist: float) -> void:
	if n is GeometryInstance3D and (n as GeometryInstance3D).visibility_range_end <= 0.0:   # v_039: the bench sets its own LOD ranges
		(n as GeometryInstance3D).visibility_range_end = dist
	for c in n.get_children():
		_far_cull(c, dist)
