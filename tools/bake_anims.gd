extends SceneTree
# Bakes the Mixamo FBX clips onto the Valery skeleton (global-delta retarget). Output: AnimationLibrary + debug json.
const SRC := {"run": "Standard_Run", "jump": "Jump", "die": "Dying", "sleep": "Sleeping_Idle", "sit": "Sitting_Idle"}
const FPS := 30.0
# name -> [source clip, first frame, last frame, loop]
const OUT := {"run": ["run", 0, 21, true], "jump": ["jump", 19, 41, false], "idle": ["jump", 0, 0, true], "die": ["die", 0, 106, false], "sleep": ["sleep", 0, -1, true], "sit": ["sit", 0, -1, true]}

func base_t(n: String) -> String:
	var u := n.rfind("_")
	if u > 0 and n.substr(u + 1).is_valid_int():
		return n.substr(0, u)
	return n

func base_s(n: String) -> String:
	var rx := RegEx.new()
	rx.compile("^mixamorig\\d*[_:]")
	return rx.sub(n, "")

func xf_to_root(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	if root is Node3D:
		t = (root as Node3D).transform * t
	return t

func gq(sk: Skeleton3D, i: int) -> Quaternion:
	return sk.get_bone_global_rest(i).basis.orthonormalized().get_rotation_quaternion()

# which character? godot --headless --script tools/<this>.gd -- <glb> <clip-file prefix>   (no arguments = the boy)
var TARGET_GLB := "res://characters/boy.glb"
var OUT_PREFIX := "res://characters/anims/boy_anims"

func _init():
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 2:
		TARGET_GLB = ua[0]
		OUT_PREFIX = ua[1]
	var out_lib := AnimationLibrary.new()
	var clips := {}
	var rtracks := {}
	var dbg := {}
	var troot: Node = load(TARGET_GLB).instantiate()
	var tsk: Skeleton3D = troot.find_children("*", "Skeleton3D", true, false)[0]
	var tq: Quaternion = xf_to_root(tsk, troot).basis.orthonormalized().get_rotation_quaternion()
	var tn := tsk.get_bone_count()
	var _mapped := {}
	var t_idx := {}
	for i in tn:
		t_idx[base_t(tsk.get_bone_name(i))] = i
	var t_hips: int = t_idx["Hips"]
	var t_hips_rest := tsk.get_bone_rest(t_hips).origin
	print("target Q ", tq, " hips rest ", t_hips_rest)
	# parents-first order
	var order: Array = []
	var seen := {}
	while order.size() < tn:
		for i in tn:
			if seen.has(i): continue
			var p := tsk.get_bone_parent(i)
			if p < 0 or seen.has(p):
				order.append(i); seen[i] = true

	# arm fix: a character in A-pose (arms down) gets the arm DIRECTIONS of the clip (aim upper arm / forearm like the source), the hand and fingers keep their bend relative to the forearm
	var ARM_CHILD := {"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "RightArm": "RightForeArm", "RightForeArm": "RightHand"}
	var hand_sub := {}
	for i in tn:
		var q := i
		while q >= 0:
			var qb := base_t(tsk.get_bone_name(q))
			if qb == "LeftHand" or qb == "RightHand":
				hand_sub[i] = true
				break
			q = tsk.get_bone_parent(q)
	for key in SRC:
		var sroot: Node = load("res://characters/anims_src/%s.fbx" % SRC[key]).instantiate()
		var ssk: Skeleton3D = sroot.find_children("*", "Skeleton3D", true, false)[0]
		var sap: AnimationPlayer = sroot.find_children("*", "AnimationPlayer", true, false)[0]
		var sa: Animation = sap.get_animation("mixamo_com")
		var sq: Quaternion = xf_to_root(ssk, sroot).basis.orthonormalized().get_rotation_quaternion()
		var sn := ssk.get_bone_count()
		var s_idx := {}
		for i in sn:
			s_idx[base_s(ssk.get_bone_name(i))] = i
		var s_hips: int = s_idx["Hips"]
		var s_hips_rest := ssk.get_bone_rest(s_hips).origin
		var ratio := t_hips_rest.y / s_hips_rest.y
		# tracks by bone
		var rot_tr := {}
		var pos_tr := -1
		for ti in sa.get_track_count():
			var path := String(sa.track_get_path(ti))
			var bn := path.get_slice(":", 1)
			var bi := ssk.find_bone(bn)
			if bi < 0: continue
			if sa.track_get_type(ti) == Animation.TYPE_ROTATION_3D: rot_tr[bi] = ti
			elif sa.track_get_type(ti) == Animation.TYPE_POSITION_3D and bi == s_hips: pos_tr = ti
		# map target -> source
		var map := {}
		for i in tn:
			var b := base_t(tsk.get_bone_name(i))
			if s_idx.has(b): map[i] = s_idx[b]
		for k2 in map: _mapped[k2] = true
		var unmapped: Array = []
		for i in tn:
			if not map.has(i): unmapped.append(tsk.get_bone_name(i))
		print(key, " frames: len ", sa.length, " ratio ", ratio, " unmapped target bones ", unmapped, " rot tracks ", rot_tr.size(), " pos track ", pos_tr)
		var nf := int(round(sa.length * FPS)) + 1
		var frames: Array = []
		for f in nf:
			var tm := minf(float(f) / FPS, sa.length)
			var sg := {}
			var spos := {}
			for i in sn:   # FBX bones are parents-first
				var p := ssk.get_bone_parent(i)
				var lr: Quaternion = ssk.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
				if rot_tr.has(i):
					lr = sa.rotation_track_interpolate(rot_tr[i], tm)
				var lo: Vector3 = ssk.get_bone_rest(i).origin
				if i == s_hips and pos_tr >= 0:
					lo = sa.position_track_interpolate(pos_tr, tm)
				if p < 0:
					sg[i] = lr
					spos[i] = lo
				else:
					assert(sg.has(p))
					sg[i] = (sg[p] as Quaternion) * lr
					spos[i] = (spos[p] as Vector3) + (sg[p] as Quaternion) * lo
			var hp: Vector3 = spos[s_hips]
			var tg := {}
			var tgo := {}
			var loc := {}
			var tqinv := tq.inverse()
			for i in order:
				var p := tsk.get_bone_parent(i)
				var g: Quaternion
				if map.has(i):
					var si: int = map[i]
					var delta: Quaternion = (sg[si] as Quaternion) * gq(ssk, si).inverse()
					g = (tqinv * (sq * delta * sq.inverse()) * tq) * gq(tsk, i)
				else:
					var lrest: Quaternion = tsk.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
					g = (tg[p] as Quaternion) * lrest if p >= 0 else lrest
				var g_orig := g
				var bn_i := base_t(tsk.get_bone_name(i))
				if map.has(i) and ARM_CHILD.has(bn_i) and s_idx.has(ARM_CHILD[bn_i]) and t_idx.has(ARM_CHILD[bn_i]):
					var ds: Vector3 = (spos[s_idx[ARM_CHILD[bn_i]]] as Vector3) - (spos[map[i]] as Vector3)
					var want: Vector3 = (tqinv * sq * ds).normalized()
					var rd: Vector3 = (tsk.get_bone_global_rest(t_idx[ARM_CHILD[bn_i]]).origin - tsk.get_bone_global_rest(i).origin).normalized()
					var cur: Vector3 = ((g * gq(tsk, i).inverse()) * rd).normalized()
					var axis := cur.cross(want)
					if axis.length() > 0.0001:
						g = Quaternion(axis.normalized(), cur.angle_to(want)) * g
				elif hand_sub.has(i) and p >= 0 and tgo.has(p):
					g = (tg[p] as Quaternion) * ((tgo[p] as Quaternion).inverse() * g)
				tgo[i] = g_orig
				tg[i] = g
				loc[i] = ((tg[p] as Quaternion).inverse() * g) if p >= 0 else g
			frames.append({"loc": loc, "hp": hp, "tg": tg})
		var hp0: Vector3 = frames[0]["hp"]
		var clip := []
		for fr in frames:
			var hp: Vector3 = fr["hp"]
			var d := hp - hp0
			var xz := Vector3(d.x, 0, d.z)
			if key == "run" or key == "sleep" or key == "sit":
				xz = Vector3.ZERO   # in place
			var newp := Vector3(t_hips_rest.x + xz.x * ratio, hp.y * ratio, t_hips_rest.z + xz.z * ratio)
			clip.append({"loc": fr["loc"], "tg": fr["tg"], "p": newp})
		clips[key] = clip
		sroot.free()
	for name in OUT:
		var spec: Array = OUT[name]
		var clip: Array = clips[spec[0]]
		var f0: int = spec[1]
		var f1: int = spec[2]
		if f1 < 0:
			f1 = clip.size() - 1   # -1 = to the last frame
		var anim := Animation.new()
		var bones: Array = []
		for i in tn:
			if i != 0 and not (i in [0]) and _mapped.has(i):
				bones.append(i)
		var trs := {}
		for i in bones:
			var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tr, NodePath("Skeleton3D:" + tsk.get_bone_name(i)))
			trs[i] = tr
		var ptr := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(ptr, NodePath("Skeleton3D:" + tsk.get_bone_name(t_hips)))
		var dbg_frames: Array = []
		for f in range(f0, f1 + 1):
			var tm := float(f - f0) / FPS
			var fr: Dictionary = clip[f]
			for i in bones:
				anim.rotation_track_insert_key(trs[i], tm, (fr["loc"][i] as Quaternion).normalized())
			anim.position_track_insert_key(ptr, tm, fr["p"])
			var tgq: Dictionary = fr["tg"]
			var pos_g := {}
			for i in order:
				var p := tsk.get_bone_parent(i)
				var lo: Vector3 = tsk.get_bone_rest(i).origin
				if i == t_hips: lo = fr["p"]
				if p < 0: pos_g[i] = lo
				else: pos_g[i] = (pos_g[p] as Vector3) + (tgq[p] as Quaternion) * lo
			var rowd := {}
			for nm in ["Hips", "Head", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftHand", "RightHand", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Spine2", "LeftForeArm", "RightForeArm", "Neck", "LeftUpLeg", "RightUpLeg"]:
				var v: Vector3 = pos_g[t_idx[nm]]
				rowd[nm] = [v.x, v.y, v.z]
			dbg_frames.append(rowd)
		var length := float(f1 - f0) / FPS
		if name == "idle":
			length = 1.0
			for i in bones:
				anim.rotation_track_insert_key(trs[i], length, (clip[f0]["loc"][i] as Quaternion).normalized())
			anim.position_track_insert_key(ptr, length, clip[f0]["p"])
		if name == "run":
			length = float(f1 - f0 + 1) / FPS   # last frame (22) == first frame (0): the loop closes by itself
		anim.length = length
		anim.loop_mode = Animation.LOOP_LINEAR if spec[3] else Animation.LOOP_NONE
		out_lib.add_animation(name, anim)
		dbg[name] = dbg_frames
	ResourceSaver.save(out_lib, OUT_PREFIX + ".res")
	var fa := FileAccess.open("/tmp/dbg.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(dbg))
	fa.close()
	print("saved")
	quit()
