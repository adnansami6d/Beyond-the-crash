extends SceneTree
# v_031: makes the "chop" clip (a one-handed overhead axe chop) for the Valery skeleton from key poses (no Mixamo file needed).
# -> characters/anims/boy_anims_axe.res (clip: chop). Run: godot --headless --script tools/bake_chop.gd
# How: every key pose says where the arm bones point (direction in the chest frame) and how far the spine bends / turns.
# Forward kinematics turns that into bone rotations for every frame (30 fps). The body is in a canonical frame:
#   x = right, y = up, z = back (the character looks to -z). Pitch + = lean back, yaw + = right shoulder forward.
const FPS := 30.0
const LENGTH := 1.2

# key poses (world directions, canonical frame): t = seconds, e = easing of the way INTO this key (s = smooth, in = slow start / fast end, out = fast start / slow end, l = linear)
# tp / ty = total trunk pitch / yaw (degrees, shared by hips + spine bones), head = [pitch, yaw], leg = knee bend 0..1
# RA / RF = right upper arm / forearm direction, LA / LF = left ones, A = where the axe head points (the blade edge E is turned 90 degrees from it, see solve()).
const KEYS := [
	{"t": 0.00, "e": "s", "tp": -5.0, "ty": 0.0, "head": [6.0, 0.0], "leg": 0.25,
	 "RA": Vector3(0.15, -0.90, -0.40), "RF": Vector3(0.05, -0.30, -0.95), "A": Vector3(0.0, 0.85, -0.50),
	 "LA": Vector3(-0.25, -0.90, -0.35), "LF": Vector3(-0.15, -0.10, -0.95)},
	{"t": 0.42, "e": "s", "tp": 10.0, "ty": -25.0, "head": [-4.0, 10.0], "leg": 0.30,
	 "RA": Vector3(0.45, 0.85, 0.20), "RF": Vector3(0.10, 0.92, -0.10), "A": Vector3(0.0, 0.35, 0.94),
	 "LA": Vector3(-0.60, 0.15, -0.78), "LF": Vector3(-0.35, 0.20, -0.90)},
	{"t": 0.50, "e": "s", "tp": 12.0, "ty": -28.0, "head": [-4.0, 11.0], "leg": 0.33,
	 "RA": Vector3(0.45, 0.85, 0.28), "RF": Vector3(0.10, 0.90, -0.02), "A": Vector3(0.0, 0.15, 0.99),
	 "LA": Vector3(-0.60, 0.15, -0.78), "LF": Vector3(-0.35, 0.20, -0.90)},
	{"t": 0.58, "e": "in", "tp": -8.0, "ty": 0.0, "head": [4.0, 0.0], "leg": 0.45,
	 "RA": Vector3(0.30, 0.60, -0.70), "RF": Vector3(0.10, 0.40, -0.90), "A": Vector3(0.0, 1.0, -0.05),
	 "LA": Vector3(-0.55, -0.20, -0.75), "LF": Vector3(-0.30, -0.10, -0.95)},
	{"t": 0.64, "e": "l", "tp": -36.0, "ty": 20.0, "head": [18.0, -8.0], "leg": 0.60,
	 "RA": Vector3(0.20, -0.30, -0.93), "RF": Vector3(0.10, -0.75, -0.65), "A": Vector3(0.0, -0.35, -0.94),
	 "LA": Vector3(-0.55, -0.70, -0.45), "LF": Vector3(-0.10, -0.35, -0.93)},
	{"t": 0.72, "e": "out", "tp": -42.0, "ty": 22.0, "head": [20.0, -8.0], "leg": 0.64,
	 "RA": Vector3(0.20, -0.45, -0.87), "RF": Vector3(0.10, -0.80, -0.60), "A": Vector3(0.0, -0.60, -0.80),
	 "LA": Vector3(-0.40, -0.85, -0.30), "LF": Vector3(-0.20, -0.50, -0.80)},
	{"t": 1.20, "e": "s", "tp": -5.0, "ty": 0.0, "head": [6.0, 0.0], "leg": 0.25,
	 "RA": Vector3(0.15, -0.90, -0.40), "RF": Vector3(0.05, -0.30, -0.95), "A": Vector3(0.0, 0.85, -0.50),
	 "LA": Vector3(-0.25, -0.90, -0.35), "LF": Vector3(-0.15, -0.10, -0.95)},
]

var tsk: Skeleton3D
var gr := {}    # bone -> rest global rotation
var gp := {}    # bone -> rest global position
var order: Array = []
var idx := {}   # base name -> bone index
var C := Basis.IDENTITY   # canonical -> skeleton space

func base_t(n: String) -> String:
	var u := n.rfind("_")
	if u > 0 and n.substr(u + 1).is_valid_int():
		return n.substr(0, u)
	return n

func ease_t(t: float, kind: String) -> float:
	match kind:
		"in": return t * t * t
		"out": return 1.0 - pow(1.0 - t, 3.0)
		"l": return t
	return t * t * (3.0 - 2.0 * t)

func lerp_pose(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var o := {}
	for k in a:
		if k == "t" or k == "e":
			continue
		if a[k] is Array:
			var arr := []
			for i in (a[k] as Array).size():
				arr.append(lerpf(float(a[k][i]), float(b[k][i]), w))
			o[k] = arr
		elif a[k] is Vector3:
			o[k] = (a[k] as Vector3).lerp(b[k], w).normalized()
		else:
			o[k] = lerpf(float(a[k]), float(b[k]), w)
	return o

func pose_at(t: float) -> Dictionary:
	for i in range(1, KEYS.size()):
		if t <= float(KEYS[i]["t"]) + 0.0001:
			var a: Dictionary = KEYS[i - 1]
			var b: Dictionary = KEYS[i]
			var w := clampf((t - float(a["t"])) / (float(b["t"]) - float(a["t"])), 0.0, 1.0)
			return lerp_pose(a, b, ease_t(w, String(b["e"])))
	return lerp_pose(KEYS[KEYS.size() - 1], KEYS[KEYS.size() - 1], 0.0)

func canon_rot(v: Array) -> Quaternion:
	# pitch about x (+ = lean back), yaw about y, roll about z; mapped into skeleton space
	var q := Quaternion(Vector3.UP, deg_to_rad(float(v[1]))) * Quaternion(Vector3.RIGHT, deg_to_rad(float(v[0]))) * Quaternion(Vector3.BACK, deg_to_rad(float(v[2])))
	var cq := C.get_rotation_quaternion()
	return cq * q * cq.inverse()

func rest_dir(i: int, child: int) -> Vector3:
	return ((gp[child] as Vector3) - (gp[i] as Vector3)).normalized()

# returns { loc: {bone: Quaternion}, drop: hips drop in m }
func solve(p: Dictionary) -> Dictionary:
	var ag := {}
	var loc := {}
	var tp: float = p["tp"]
	var ty: float = p["ty"]
	var share := {"Hips": [0.0, 0.30], "Spine": [0.33, 0.23], "Spine1": [0.33, 0.23], "Spine2": [0.34, 0.24]}
	var arm_dirs := {"RightArm": ["RA", "RightForeArm"], "RightForeArm": ["RF", "RightHand"], "LeftArm": ["LA", "LeftForeArm"], "LeftForeArm": ["LF", "LeftHand"]}
	var k: float = float(p["leg"])
	var a_th := deg_to_rad(28.0 * k)
	var a_sh := deg_to_rad(34.0 * k)
	var drop := 0.4389 * (1.0 - cos(a_th)) + 0.4124 * (1.0 - cos(a_sh))
	var inv := {}
	for n in idx:
		inv[idx[n]] = n
	var cq := C.get_rotation_quaternion()
	var yawq := cq * Quaternion(Vector3.UP, deg_to_rad(ty)) * cq.inverse()   # the whole chest turn: arms and axe turn with it
	for i in order:
		var par := tsk.get_bone_parent(i)
		var nm: String = inv.get(i, "")
		var lr: Quaternion = tsk.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
		var pg: Quaternion = ag[par] if par >= 0 else Quaternion.IDENTITY
		var l := lr
		if share.has(nm) or nm == "Head":
			var d: Quaternion
			if nm == "Head":
				d = canon_rot([p["head"][0], p["head"][1], 0.0])
			else:
				d = canon_rot([tp * float(share[nm][0]), ty * float(share[nm][1]), 0.0])
			var pr: Quaternion = gr[par] if par >= 0 else Quaternion.IDENTITY
			l = (pr.inverse() * d * pr) * lr
		elif nm == "RightHand":
			# the axe is held with the head toward the thumb (hand x) and the blade edge along the fingers (hand y): the hand turns with the axe
			var a: Vector3 = (p["A"] as Vector3).normalized()
			var e := Vector3(0.0, a.z, -a.y)   # the edge turns 90 degrees from the head direction (pure pitch swing)
			e = (e - a * e.dot(a)).normalized()
			var ax: Vector3 = yawq * (C * a)
			var ex: Vector3 = yawq * (C * e)
			var g := Basis(ax, ex, ax.cross(ex)).get_rotation_quaternion()
			l = pg.inverse() * g
		elif arm_dirs.has(nm) or nm.ends_with("UpLeg") or nm.ends_with("Leg") or nm.ends_with("Foot"):
			var want := Vector3.ZERO
			var child := -1
			if arm_dirs.has(nm):
				var spec: Array = arm_dirs[nm]
				want = yawq * (C * (p[spec[0]] as Vector3).normalized())
				child = idx[spec[1]]
			elif nm.ends_with("UpLeg"):
				var s := 1.0 if nm.begins_with("Right") else -1.0
				want = C * Vector3(s * 0.06, -cos(a_th), -sin(a_th)).normalized()
				child = idx[nm.replace("UpLeg", "Leg")]
			elif nm.ends_with("Leg"):
				var s2 := 1.0 if nm.begins_with("Right") else -1.0
				want = C * Vector3(s2 * 0.04, -cos(a_sh), sin(a_sh)).normalized()
				child = idx[nm.replace("Leg", "Foot")]
			else:   # foot: stays flat like at rest
				child = idx[nm.replace("Foot", "ToeBase")]
				want = rest_dir(i, child)
			var rd := rest_dir(i, child)
			var g2 := Quaternion(rd, want.normalized()) * (gr[i] as Quaternion)
			l = pg.inverse() * g2
		loc[i] = l.normalized()
		ag[i] = pg * (loc[i] as Quaternion)
	return {"loc": loc, "drop": drop}

# which character? godot --headless --script tools/<this>.gd -- <glb> <clip-file prefix>   (no arguments = the boy)
var TARGET_GLB := "res://characters/boy.glb"
var OUT_PREFIX := "res://characters/anims/boy_anims"

func _init():
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 2:
		TARGET_GLB = ua[0]
		OUT_PREFIX = ua[1]
	var troot: Node = load(TARGET_GLB).instantiate()
	tsk = troot.find_children("*", "Skeleton3D", true, false)[0]
	var tn := tsk.get_bone_count()
	for i in tn:
		idx[base_t(tsk.get_bone_name(i))] = i
	while order.size() < tn:
		for i in tn:
			if order.has(i):
				continue
			var p := tsk.get_bone_parent(i)
			if p < 0 or order.has(p):
				order.append(i)
	for i in order:
		var p := tsk.get_bone_parent(i)
		var lq: Quaternion = tsk.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
		var lo: Vector3 = tsk.get_bone_rest(i).origin
		if p < 0:
			gr[i] = lq
			gp[i] = lo
		else:
			gr[i] = (gr[p] as Quaternion) * lq
			gp[i] = (gp[p] as Vector3) + (gr[p] as Quaternion) * lo
	# canonical frame: up = +y, forward from the heel to the toe, right = the side of the RightArm
	var fwd: Vector3 = (gp[idx["RightToeBase"]] as Vector3) - (gp[idx["RightFoot"]] as Vector3)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var up := Vector3.UP
	var right := up.cross(-fwd)   # x = y cross z, z = back
	if right.dot((gp[idx["RightArm"]] as Vector3) - (gp[idx["LeftArm"]] as Vector3)) < 0.0:
		print("WARNING: the right side is mirrored, flipping")
		right = -right
	C = Basis(right, up, -fwd)
	print("forward ", fwd, " right ", right, " basis det ", C.determinant())

	var anim := Animation.new()
	var trs := {}
	for i in order:
		if i == 0:
			continue
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, NodePath("Skeleton3D:" + tsk.get_bone_name(i)))
		trs[i] = tr
	var hips: int = idx["Hips"]
	var ptr := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(ptr, NodePath("Skeleton3D:" + tsk.get_bone_name(hips)))
	var hrest: Vector3 = tsk.get_bone_rest(hips).origin
	var nf := int(round(LENGTH * FPS))
	for f in nf + 1:
		var t := minf(float(f) / FPS, LENGTH)
		var s := solve(pose_at(t))
		for i in trs:
			anim.rotation_track_insert_key(trs[i], t, s["loc"][i])
		anim.position_track_insert_key(ptr, t, hrest - Vector3(0, float(s["drop"]), 0))
	anim.length = LENGTH
	anim.loop_mode = Animation.LOOP_NONE
	var lib := AnimationLibrary.new()
	lib.add_animation("chop", anim)
	ResourceSaver.save(lib, OUT_PREFIX + "_axe.res")
	print("saved chop, tracks ", anim.get_track_count(), " length ", anim.length)
	quit()
