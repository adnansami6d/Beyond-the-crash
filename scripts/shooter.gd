extends Node
# Weapons + items. (Replaces the old combat.gd: no bandits / missions in Beyond the Crash.)
#   FIRE at a tree / bush / rock -> it breaks after some hits and gives WOOD / STONE blocks. The ground and the buildings can not be broken.
# Items go into `inv` (wood, stone). hud.gd shows them.
# Weapon: the SMG only (v_014, the old pistol and rifle are gone). Infinite ammo, the magazine must be reloaded (RELOAD button).

const Cfg = preload("res://scripts/config.gd")   # v_043
const Util = preload("res://scripts/util.gd")
const DebrisScript = preload("res://scripts/debris.gd")
const Hardness = preload("res://scripts/hardness.gd")
const SaveGame = preload("res://scripts/savegame.gd")

const WEAPONS := [
	{"name": "SMG", "gap": 0.09, "mag": 30, "spread": 1.8, "reload": 1.7, "hits": 14, "dmg": 1, "edmg": 14.0},
	# v_031: the axe (melee). FIRE = one chop (clip "chop"). Cutting trees with it comes in a later step.
	{"name": "AXE", "melee": true, "gap": 0.85, "mag": 0, "spread": 0.0, "reload": 0.0, "hits": 5, "dmg": 1, "edmg": 20.0},
]
const ITEM_COLORS := {"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.56, 0.56, 0.6), "meat": Color(0.75, 0.2, 0.25)}
const MAX_ITEMS := 40          # flying blocks at the same time
const CHOP_HIT_AT := 0.64     # v_040: second of the chop clip where the blade lands (tools/bake_chop.gd KEYS); a chained chop starts later in the clip, so it hits sooner
const CHOP_REACH := 1.3       # sphere centre in front of the player (m)
const CHOP_RADIUS := 0.8      # sphere radius (m)
const TREE_HITS := 3
const TREE_WOOD := 2

var main
var player
var rig
var touch
var world
var hud

var cur := 0   # weapon in the hand (index in WEAPONS); only meaningful while hand >= 0
var slots := [0, 1]   # v_016: the weapon in each gun slot (index in WEAPONS), -1 = empty slot
var hand := -1         # v_016: the slot that is in the hand, -1 = EMPTY HANDS (no gun)
var mag := [30, 0]
var reloading := false
var reload_t := 0.0
var reload_total := 1.0
var fire_t := 0.0
var _hint_t := 0.0     # v_016: pause between two 'hands are empty' messages
var aim_hold := 0.0
var firing := false
var holstered := false   # build mode: gun put away, no shooting
var bag_open := false
var _cut_dmg := {}      # shape instance id -> damage (trees, rocks, bushes)
var inv := {"wood": 0, "stone": 0}
var _items: Array = []   # {n: Node3D, kind: String, t: float, vel: Vector3}
var _debris            # falling pieces (scripts/debris.gd)

var _s_pistol: AudioStreamPlayer
var _s_rifle: AudioStreamPlayer
var _s_reload: AudioStreamPlayer
var _s_pick: AudioStreamPlayer
var _s_chop: AudioStreamPlayer


func setup(m, p, r, t, w) -> void:
	main = m
	player = p
	rig = r
	touch = t
	world = w
	_debris = DebrisScript.new()
	add_child(_debris)
	_debris.setup(Callable(world, "height_at"))
	_s_pistol = _player_snd(_noise_wav(0.28, 32.0, 120.0, 22.0, 1.0), -2.0)
	_s_rifle = _player_snd(_noise_wav(0.18, 45.0, 160.0, 35.0, 0.9), -4.0)
	_s_reload = _player_snd(_click_wav(), -2.0)
	_s_pick = _player_snd(_noise_wav(0.12, 30.0, 700.0, 18.0, 0.4), -8.0)
	_s_chop = _player_snd(_noise_wav(0.12, 40.0, 260.0, 40.0, 0.8), -4.0)


func on_foot() -> bool:
	return player != null and not main.driving and not main.flying


func weapon_name() -> String:
	if hand < 0:
		return "HANDS"
	return String(WEAPONS[cur]["name"])


func armed() -> bool:
	return hand >= 0


# v_016: tap on a gun slot box (0, 1). A filled slot comes to the hand; tap the same slot again = put it away (empty hands).
# slot -1 = the HANDS box: empty hands.
func equip(slot: int) -> void:
	if not on_foot():
		return
	if slot >= slots.size() or (slot >= 0 and int(slots[slot]) < 0):
		return   # an empty box: nothing happens
	if slot < 0 or slot == hand:
		hand = -1
	else:
		hand = slot
		cur = int(slots[slot])
	reloading = false
	firing = false
	aim_hold = 0.0


# v_016: a weapon is picked up / given: it goes to the first free slot. false = both slots are full.
func give_weapon(w: int) -> bool:
	for i in slots.size():
		if int(slots[i]) == w:
			return true
	for i in slots.size():
		if int(slots[i]) < 0:
			slots[i] = w
			return true
	return false


func ammo_text() -> String:
	return "%d / %d" % [int(mag[cur]), int(WEAPONS[cur]["mag"])]


# ---------------------------------------------------------------- buttons

func swap_weapon() -> void:
	if not on_foot():
		return
	hud.say(weapon_name(), 1.0)   # v_014: only one weapon, SWAP just shows its name


func reload() -> void:
	if not on_foot() or hand < 0 or reloading or int(mag[cur]) >= int(WEAPONS[cur]["mag"]):
		return
	reloading = true
	reload_total = float(WEAPONS[cur]["reload"])
	reload_t = reload_total
	_s_reload.play()


func toggle_bag() -> void:
	bag_open = not bag_open


# v_043: food items of the bag: kind -> food points of ONE piece. Only ADD new foods here (bag_ui.gd lists every entry).
const FOODS := {"meat": Cfg.MEAT_FOOD}


# v_043: the small "eat" button in the bag (bag_ui.gd) calls this: one piece of that food is used, hunger goes up
func eat_food(kind: String) -> void:
	if int(inv.get(kind, 0)) <= 0:
		say_bag("No %s left" % kind, 1.5)
		return
	if main.combat == null or main.combat.hunger >= Cfg.HUNGER_MAX - 0.5:
		say_bag("You are full", 1.2)
		return
	var pts: float = float(FOODS.get(kind, 0.0))
	inv[kind] = int(inv[kind]) - 1
	main.combat.eat(pts)
	say_bag("You ate %s  +%d food" % [kind, int(pts)], 1.5)


# v_043: a message that is also shown inside the open bag screen (bag_ui.gd covers the normal HUD message)
func say_bag(t: String, secs: float = 1.5) -> void:
	hud.say(t, secs)
	if main.get("bag_ui") != null:
		main.bag_ui.toast(t, secs)


func add_item(kind: String, n: int = 1) -> void:
	inv[kind] = int(inv.get(kind, 0)) + n


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var can := on_foot()
	fire_t -= delta
	_hint_t -= delta
	aim_hold -= delta
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			mag[cur] = int(WEAPONS[cur]["mag"])
	var armed_now := hand >= 0
	player.gun_kind = cur if (can and not holstered and armed_now) else -1
	var melee := armed_now and bool(WEAPONS[cur].get("melee", false))
	player.aiming = can and not holstered and armed_now and not melee and (firing or aim_hold > 0.0)
	if player.aiming:
		player.aim_point = _crosshair_point()   # v_030: the rifle turns to this point
	else:
		player.aim_point = Vector3.ZERO
	if firing and can and not bag_open and not holstered:
		if melee:
			_try_chop()
		elif armed_now:
			_try_fire()
		elif _hint_t <= 0.0:
			_hint_t = 1.5
			hud.say("Hands are empty: pick a gun", 1.0)
	_tick_items(delta)


# v_030: the world point under the crosshair (a ray from the camera; a very near hit uses a far point instead)
func _crosshair_point() -> Vector3:
	var cam: Camera3D = rig.cam
	var fwd: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + fwd * 1.5
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 120.0)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	if not r.is_empty() and origin.distance_to(r["position"]) > 4.0:
		return r["position"]
	return origin + fwd * 40.0


# v_031: FIRE with the axe in the hand = one chop (the clip is played by player.gd). No hit logic yet.
func _try_chop() -> void:
	if fire_t > 0.0 or not player.is_on_floor():
		return
	fire_t = float(WEAPONS[cur]["gap"])
	var from: float = player.start_chop()
	# the blade lands when the clip reaches its hit second
	get_tree().create_timer(maxf(CHOP_HIT_AT - from, 0.05)).timeout.connect(_chop_hit.bind(cur))


# the axe lands: a sphere in front of the player finds the nearest tree / rock / bush and damages it.
# Only the axe cuts trees and rocks (bullets do not).
func _chop_hit(weapon: int) -> void:
	if cur != weapon or player == null or not player.is_inside_tree():
		return
	var yaw: float = player.pivot.rotation.y
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var sp := SphereShape3D.new()
	sp.radius = CHOP_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sp
	q.transform = Transform3D(Basis.IDENTITY, player.global_position + f * CHOP_REACH + Vector3(0, 0.9 * Util.CHAR_SCALE, 0))
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var best: Dictionary = {}
	var best_d := INF
	for r in space.intersect_shape(q, 16):
		var cn := r["collider"] as Node
		if cn == null:
			continue
		var co := cn as CollisionObject3D
		var pos: Vector3 = (cn as Node3D).global_position if cn is Node3D else player.global_position
		if bool(cn.get_meta("cuttable", false)) and co != null:
			var oid: int = co.shape_find_owner(int(r["shape"]))
			var cs := co.shape_owner_get_owner(oid) as Node3D
			if cs == null or not cs.has_meta("kind"):
				continue
			pos = cs.global_position
		elif not cn.is_in_group("tree") and not cn.is_in_group("cow"):
			continue
		var d: float = pos.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = r
	if best.is_empty():
		return
	var target := best["collider"] as Node
	if target.is_in_group("cow"):   # the axe hits a cow
		_s_chop.play()
		(target.get_parent() as Cow).hurt(float(WEAPONS[cur]["edmg"]), player.global_position)
	elif bool(target.get_meta("cuttable", false)):
		_hit_cuttable(target, best, WEAPONS[cur], f, true)
	else:
		_hit_tree(target as Node3D)


func _try_fire() -> void:
	if reloading or fire_t > 0.0:
		return
	if int(mag[cur]) <= 0:
		reload()
		return
	var w: Dictionary = WEAPONS[cur]
	fire_t = float(w["gap"])
	mag[cur] = int(mag[cur]) - 1
	aim_hold = 1.5
	player.shot_t = 0.3   # v_028: standing fire clip
	_s_rifle.play()

	var cam: Camera3D = rig.cam
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + cam_fwd * 1.5
	var fwd := cam_fwd
	if main.combat != null:   # v_007: light aim assist toward a bandit near the crosshair
		fwd = main.combat.assist_dir(origin, cam_fwd)
	var dir := _spread_dir(fwd, deg_to_rad(float(w["spread"])))
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	var aim: Vector3 = origin + dir * 120.0
	var col: Object = null
	if not r.is_empty():
		aim = r["position"]
		col = r["collider"]

	var muzzle := _muzzle()
	var puff_col := Color(1.0, 0.85, 0.5)
	if col is Node:
		var cn := col as Node
		if main.combat != null and cn.is_in_group("enemy"):   # v_007: a bandit
			main.combat.hit_enemy(cn, aim, float(w["edmg"]))
			puff_col = Color(1.0, 0.1, 0.05)
		elif cn.is_in_group("cow"):   # a cow
			(cn.get_parent() as Cow).hurt(float(w["edmg"]), player.global_position)
			puff_col = Color(1.0, 0.1, 0.05)
		elif bool(cn.get_meta("cuttable", false)):   # bullets: bushes only (trees and rocks need the axe)
			puff_col = _hit_cuttable(cn, r, w, dir, false)
	var tr_end := aim
	if muzzle.distance_to(aim) > 90.0:
		tr_end = muzzle + (aim - muzzle).normalized() * 90.0
	_tracer(muzzle, tr_end, Color(1.0, 0.9, 0.4))
	_puff(muzzle, Color(1.0, 0.8, 0.3), 0.13, 0.04)
	if not r.is_empty():
		_puff(aim, puff_col, 0.14, 0.12)
	rig.pitch = clampf(rig.pitch - 0.004, rig.PITCH_MIN, rig.PITCH_MAX)
	if main.combat != null:   # v_007: shots are heard by bandits nearby
		main.combat.alert_near(player.global_position, 30.0)


func _hit_tree(tree: Node3D) -> void:
	_s_chop.play()
	var hp := int(tree.get_meta("hp", TREE_HITS)) - 1
	tree.set_meta("hp", hp)
	if hp > 0:
		var tw := tree.create_tween()
		tw.tween_property(tree, "rotation:z", 0.06, 0.05)
		tw.tween_property(tree, "rotation:z", 0.0, 0.1)
		return
	var pos := tree.global_position + Vector3(0, 1.5, 0)
	tree.queue_free()
	for i in TREE_WOOD:
		_spawn_item("wood", pos + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)))
	hud.say("Tree cut +%d wood" % TREE_WOOD, 1.5)


func _muzzle() -> Vector3:
	if player.gun_muzzle != null and player.gun != null and player.gun.visible and player.gun_muzzle.is_inside_tree():
		return player.gun_muzzle.global_position   # v_014: the tip of the SMG barrel
	var yaw: float = player.pivot.rotation.y
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rgt := Vector3(cos(yaw), 0.0, -sin(yaw))
	return player.global_position + (Vector3(0, 0.35, 0) + f * 0.85 + rgt * 0.25) * Util.CHAR_SCALE


func _spread_dir(fwd: Vector3, ang: float) -> Vector3:
	var b := Basis.looking_at(fwd, Vector3.UP)
	var a := randf() * TAU
	var m := randf() * ang
	return (b * Vector3(sin(m) * cos(a), sin(m) * sin(a), -cos(m))).normalized()


# ---------------------------------------------------------------- cut trees / bushes / rocks

# a bullet hit a tree / bush / rock (a CollisionShape3D with meta "kind" and "size"). Returns the colour of the hit puff.
func _hit_cuttable(body: Node, r: Dictionary, w: Dictionary, dir: Vector3, by_axe: bool) -> Color:
	var col := Color(0.6, 0.45, 0.25)
	var co := body as CollisionObject3D
	if co == null:
		return col
	var oid: int = co.shape_find_owner(int(r["shape"]))
	var cs := co.shape_owner_get_owner(oid) as Node3D
	if cs == null or not cs.has_meta("kind"):
		return col
	var kind := String(cs.get_meta("kind"))
	if (kind == "tree" or kind == "rock") and not by_axe:
		return col   # only the axe cuts trees and rocks
	var hard := Hardness.for_kind(kind)
	if hard <= 0.0:
		return col   # not breakable
	if kind == "bush":
		col = Color(0.3, 0.55, 0.2)
	elif kind == "rock":
		col = Color(0.62, 0.62, 0.66)
		hard *= clampf(float(cs.get_meta("size", 1.0)), 0.4, 1.0)   # FIX: a small stone breaks faster than a big rock
	var id := cs.get_instance_id()
	var dmg: float = float(_cut_dmg.get(id, 0.0)) + (1.0 / float(w.get("hits", 10))) / hard
	if dmg < 0.999:
		_cut_dmg[id] = dmg
		_s_chop.play()
		return col
	_cut_dmg.erase(id)
	_cut_down(cs, kind, col, dir)
	return col


func _cut_down(cs: Node3D, kind: String, col: Color, dir: Vector3) -> void:
	var gp := cs.global_position
	var holder: Node = cs.get_parent().get_parent()   # shape -> body -> the node that holds the MultiMeshInstance3D copies
	var size := float(cs.get_meta("size", 1.0))
	var copy: Dictionary = _hide_copies(holder, gp)
	cs.set_deferred("disabled", true)
	SaveGame.note_cut(gp)   # v_012d: stays broken after restart (and when the 100 m square is built again)
	_s_chop.play()
	_debris.spawn(gp + Vector3(0, 0.8, 0), col, dir)
	if kind == "tree":
		var n := maxi(1, int(round(size * Hardness.TREE_WOOD_PER_SIZE)))
		if copy.is_empty():
			for i in n:
				_spawn_item("wood", gp + Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5)))
		else:
			_fall_tree(copy, gp, dir, n)   # v_040: the tree tips over, then the wood flies out
		hud.say("Tree cut +%d wood" % n, 1.5)
	elif kind == "rock":
		var n2 := maxi(1, int(round(size * Hardness.ROCK_STONE_PER_SIZE)))
		for i in n2:
			_spawn_item("stone", gp + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)))
		hud.say("Rock broken +%d stone" % n2, 1.5)


# trees / bushes / rocks are copies in MultiMeshes: the copies standing at this place are shrunk to nothing
# returns {mesh, xf} of the copy that was hidden (v_040: the falling tree is drawn from it), or {}
func _hide_copies(holder: Node, gp: Vector3) -> Dictionary:
	var found := {}
	for ch in holder.get_children():
		var mmi := ch as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var gt := mmi.global_transform
		for i in mm.instance_count:
			var lt := mm.get_instance_transform(i)
			var o := gt * lt.origin
			if absf(o.x - gp.x) < 0.06 and absf(o.z - gp.z) < 0.06:
				if found.is_empty():
					found = {"mesh": mm.mesh, "xf": gt * lt}
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), lt.origin))
	return found


# v_040: a cut tree tips over (slow at first, then faster) away from the cutter, hits the ground, and the wood flies out of the trunk
func _fall_tree(copy: Dictionary, gp: Vector3, dir: Vector3, wood: int) -> void:
	var xf: Transform3D = copy["xf"]
	var base := Vector3(gp.x, xf.origin.y, gp.z)
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.1:
		d = Vector3.FORWARD
	d = d.normalized()
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = base
	var mi := MeshInstance3D.new()
	mi.mesh = copy["mesh"]
	mi.transform = Transform3D(xf.basis, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	var axis := Vector3.UP.cross(d).normalized()
	var tw := create_tween()
	tw.tween_method(func(a: float): pivot.basis = Basis(axis, a), 0.0, deg_to_rad(88.0), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_s_chop.play()
		_debris.spawn(base + d * 3.0 + Vector3(0, 0.4, 0), Color(0.45, 0.35, 0.2), d)
		for i in wood:
			_spawn_item("wood", base + d * randf_range(1.0, 5.0) + Vector3(randf_range(-0.4, 0.4), 0.8, randf_range(-0.4, 0.4)))
		pivot.queue_free())


# ---------------------------------------------------------------- item blocks (they fly out, then to the player)

func _spawn_item(kind: String, pos: Vector3) -> void:
	if _items.size() >= MAX_ITEMS:
		var old: Dictionary = _items.pop_front()
		(old["n"] as Node3D).queue_free()
		_collect(String(old["kind"]))
	var mi := Util.mi(Util.box(Vector3(0.3, 0.3, 0.3)), ITEM_COLORS.get(kind, Color.WHITE))
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	_items.append({"n": mi, "kind": kind, "t": 0.0, "vel": Vector3(randf_range(-1.2, 1.2), randf_range(3.5, 5.0), randf_range(-1.2, 1.2))})


func _collect(kind: String) -> void:
	add_item(kind, 1)
	_s_pick.play()
	hud.pop(kind)


func _tick_items(delta: float) -> void:
	var i := _items.size() - 1
	while i >= 0:
		var it: Dictionary = _items[i]
		var n: Node3D = it["n"]
		it["t"] = float(it["t"]) + delta
		n.rotation.y += delta * 3.0
		if float(it["t"]) < 0.5:
			var v: Vector3 = it["vel"]
			v.y -= 14.0 * delta
			it["vel"] = v
			n.global_position += v * delta
			var gy: float = world.height_at(n.global_position.x, n.global_position.z) + 0.2
			if n.global_position.y < gy:
				n.global_position.y = gy
		elif on_foot():
			var target: Vector3 = player.global_position + Vector3(0, 0.5, 0)
			var to := target - n.global_position
			var d := to.length()
			var speed := 6.0 + 10.0 * (float(it["t"]) - 0.5)
			if d < 0.7:
				n.queue_free()
				_items.remove_at(i)
				_collect(String(it["kind"]))
				i -= 1
				continue
			n.global_position += to / d * minf(speed * delta, d)
		i -= 1


# ---------------------------------------------------------------- effects + sounds

func _tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, len)
	var mi := Util.mim(bm, Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = (a + b) / 2.0
	var up := Vector3.UP
	if absf((b - a).normalized().dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	mi.look_at(b, up)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _puff(pos: Vector3, col: Color, r: float, life: float) -> void:
	var mi := Util.mim(Util.sphere(r, 6, 3), Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(life).timeout.connect(mi.queue_free)


func _player_snd(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _noise_wav(dur: float, decay: float, tone: float, tone_decay: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := (randf() * 2.0 - 1.0) * exp(-t * decay)
		if tone > 0.0:
			v += sin(TAU * tone * t) * exp(-t * tone_decay) * 0.9
		data.encode_s16(i * 2, int(clampf(v * vol, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _click_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.55 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var a := exp(-t * 160.0)
		var b := 0.0
		if t >= 0.4:
			b = exp(-(t - 0.4) * 160.0)
		var v := (randf() * 2.0 - 1.0) * (a + b) * 0.6
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
