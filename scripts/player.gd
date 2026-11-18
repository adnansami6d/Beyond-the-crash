extends CharacterBody3D
# The character. Height = 5 ft = 1.524 m.
# Built-in body is a placeholder. use_model(node) swaps in your own character.
# main.gd sets move_dir (joystick) and cam_yaw (camera) every frame.

const Util = preload("res://scripts/util.gd")
const Human = preload("res://scripts/human.gd")
const RigAnim = preload("res://scripts/rig_anim.gd")
const Sfx = preload("res://scripts/sfx.gd")
const AudioLib = preload("res://scripts/audio_lib.gd")
const Props = preload("res://scripts/props.gd")
const HEIGHT := 1.524
const WALK_SPEED := 3.0 * Util.CHAR_SCALE
const RUN_SPEED := 6.5 * Util.CHAR_SCALE
const JUMP_SPEED := 7.0   # 1.2 m high: enough to climb a 1 m block
const GRAVITY := 20.0
const SMG_PATH := "res://weapons/smg.glb"   # v_014: the only weapon (halo 2 anniversary SMG, shrunk by tools/shrink_gun.py)
const AXE_PATH := "res://weapons/axe.glb"   # v_031: the axe (stylized, handle along its +Z, blade edge to -Y)
const AXE_SCALE := 1.25            # the model is 0.51 m long: 0.64 m in the character space (a real hand axe is about 0.7 m)
const AXE_GRIP_AT := Vector3(0.0, 0.0, 0.14)   # the point of the handle that sits in the hand (axe model space, before AXE_SCALE)
# where the axe sits in the right hand (hand bone space: y = along the fingers)
# axe model axes -> hand bone axes: head (+Z) toward the thumb (hand x), blade edge (-Y) along the fingers (hand y), model x = hand z
const AXE_GRIP_BASIS := Basis(Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(1, 0, 0))
const AXE_GRIP_SHIFT := Vector3(0.0, 0.045, 0.0)
const CHOP_CHAIN_FROM := 0.12      # v_032: a chained chop starts here in the clip (the body is already moving back)
const CHOP_TIME := 1.2             # length of the chop clip
var anim_prefix := "res://characters/anims/boy_anims"   # set by main.gd from char_db.gd: clips are <prefix>.res, <prefix>_rifle.res, <prefix>_axe.res
const CUSTOM_MODEL_TURN_DEG := 180.0   # glb models usually face +Z; change to 0 if yours walks backwards

var move_dir := Vector2.ZERO
var cam_yaw := 0.0
var running := false

var model: Node3D
var pivot: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var elbow_l: Node3D   # V31: bend joints + chest + head of the realistic body
var elbow_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var spine: Node3D
var head: Node3D
var gun_kind := -1     # set by shooter.gd: -1 = no weapon, 0 = the SMG
var gun: Node3D        # the weapon shown in the hands (SMG model, grip at the node origin, muzzle looks to -Z)
var axe: Node3D        # v_031: the axe in the hand (follows the right hand bone)
var _holder: Node3D
var _chop_seek := -1.0   # v_032: where in the clip the new chop starts (set by start_chop, used once)
var _chop_blend := 0.08
var chop_t := 0.0      # v_031: shooter.gd sets this to CHOP_TIME at every chop: the "chop" clip plays while it runs
var gun_muzzle: Marker3D   # tip of the barrel (shooter.gd starts the tracer here)
var gun_amt := 0.0     # 0 = carried low, 1 = raised to aim
var model_scale := 1.0
var anim: AnimationPlayer       # plays the clips of valery_anims.res on the character skeleton
var skel: Skeleton3D
var rig                         # old code-made body animation: used ONLY for walking with the joystick and for sitting (tractor / helicopter)
var anim_t := 0.0
var idle_t := 0.0
var _hand_bone := -1            # right hand bone: the weapon follows it
var _lhand_bone := -1   # v_014: left hand bone (the SMG points from the right hand to the left hand in the rifle walk)
var _hips_bone := -1
var _cur := ""                  # clip that is playing now
var _dead := false
var was_on_floor := true
var seated := false
var _bench_dir := Vector3.ZERO   # v_039: not zero while sitting on a bench (facing direction)
var sleeping := false   # v_026: lying down with the Sleeping Idle clip (SLEEP button)
var aim_point := Vector3.ZERO   # v_030: world point under the crosshair (shooter.gd sets it every frame while aiming): the rifle turns to it
var _fire_hold := false
var shot_t := 0.0     # v_028: shooter.gd sets this at every shot: the "fire_rifle" clip plays while it runs
var aiming := false   # shooter.gd: facing the camera direction with the gun up

# --- sounds (your files in res://audio/walk, run, jump, land; empty folder = default sound from sfx.gd)
const STEP_EVERY_WALK := 0.52   # seconds between two steps
const STEP_EVERY_RUN := 0.34
var _snd_step: AudioStreamPlayer
var _snd_jump: AudioStreamPlayer
var _snd_land: AudioStreamPlayer
var _walk_sounds: Array = []
var _run_sounds: Array = []
var _step_t := 0.0
var _air_t := 0.0
var _step_last := -1


func _ready() -> void:
	add_to_group("player")
	_setup_sound()
	collision_mask = 3   # 1 = things (trees, walls, tractor), 2 = the ground
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25 * Util.CHAR_SCALE
	cap.height = HEIGHT * Util.CHAR_SCALE
	cs.shape = cap
	add_child(cs)

	pivot = Node3D.new()
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	add_child(pivot)
	model = Node3D.new()
	model.position = Vector3(0, -HEIGHT / 2.0, 0)   # feet at the bottom of the capsule
	pivot.add_child(model)
	_build_placeholder()
	_build_gun()


func _build_placeholder() -> void:
	var parts: Dictionary = Human.build(model, {"top": Color(0.09, 0.09, 0.11), "pants": Color(0.14, 0.14, 0.16), "boots": Color(0.25, 0.17, 0.11), "hair": Color(0.3, 0.19, 0.1), "sleeveless": true, "pack": true})
	arm_l = parts["arm_l"]
	arm_r = parts["arm_r"]
	leg_l = parts["leg_l"]
	leg_r = parts["leg_r"]
	elbow_l = parts.get("elbow_l")
	elbow_r = parts.get("elbow_r")
	knee_l = parts.get("knee_l")
	knee_r = parts.get("knee_r")
	spine = parts.get("spine")
	head = parts.get("head")


# The weapon in the hands: the SMG model, grip at the node origin, the muzzle looks to -Z (character model space).
func _build_gun() -> void:
	# NOT inside 'model': use_model() deletes everything inside model when a glb character is loaded
	var holder := Node3D.new()
	holder.position = Vector3(0, -HEIGHT / 2.0, 0)   # same place as 'model': feet at the bottom of the capsule
	pivot.add_child(holder)
	_holder = holder
	_build_axe(holder)
	gun = Node3D.new()
	gun.visible = false
	holder.add_child(gun)
	var ps = load(SMG_PATH)
	if ps is PackedScene:
		var smg: Node3D = ps.instantiate()
		smg.name = "SMG"
		gun.add_child(smg)
	else:
		push_warning("SMG model missing: " + SMG_PATH)
		Util.part(gun, Vector3(0.04, 0.07, 0.45), Vector3(0, 0.05, -0.1), Util.mat(Color(0.12, 0.12, 0.14), 0.6, 0.3))
	gun_muzzle = Marker3D.new()
	gun_muzzle.name = "Muzzle"
	gun_muzzle.position = Vector3(0.0, 0.075, -0.38)
	gun.add_child(gun_muzzle)


# v_031: the axe. Its mesh is taken out of the glb (the file has a tilted parent chain), so the handle lies along +Z and the grip point is the node origin.
func _build_axe(holder: Node3D) -> void:
	axe = Node3D.new()
	axe.name = "Axe"
	axe.visible = false
	holder.add_child(axe)
	var ps = load(AXE_PATH)
	if ps is PackedScene:
		var inst: Node = ps.instantiate()
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var m: MeshInstance3D = meshes[0]
			m.get_parent().remove_child(m)
			m.transform = Transform3D(Basis.from_scale(Vector3.ONE * AXE_SCALE), -AXE_GRIP_AT * AXE_SCALE)
			for si in m.mesh.get_surface_count():   # the blade is one-sided in the file: show both faces
				var mat = m.mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					var m2: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
					m2.cull_mode = BaseMaterial3D.CULL_DISABLED
					m.set_surface_override_material(si, m2)
			axe.add_child(m)
		inst.free()
	else:
		push_warning("Axe model missing: " + AXE_PATH)


# v_031: one chop starts (shooter.gd): the clip plays from its first frame, also when the last chop just ended
# chain = the FIRE button is held and the last chop is still running out: the next chop starts at once, skipping the standing "ready" part of the clip
func start_chop() -> float:   # v_040: returns where in the clip this chop starts (seconds)
	var chain := chop_t > 0.0
	chop_t = CHOP_TIME - (CHOP_CHAIN_FROM if chain else 0.0)
	_chop_seek = CHOP_CHAIN_FROM if chain else 0.0
	_chop_blend = 0.2 if chain else 0.08
	if _cur == "chop":
		_cur = ""
	return _chop_seek

# the axe follows the right hand bone (position + turn), used for every clip
func _update_axe() -> void:
	if axe == null:
		return
	var show := gun_kind == 1 and not seated and not sleeping and not _dead and skel != null and _hand_bone >= 0
	axe.visible = show
	if not show:
		return
	var w: Transform3D = skel.global_transform * skel.get_bone_global_pose(_hand_bone)
	var th: Transform3D = _holder.global_transform.affine_inverse() * w
	th.basis = th.basis.orthonormalized()
	var grip := Transform3D(AXE_GRIP_BASIS, AXE_GRIP_SHIFT)
	axe.transform = th * grip


# v_012 / v_014: weapon poses (model space: feet y = 0, the body looks to -Z, +X = right). Each pose = [grip position, pitch in degrees (+ = muzzle up)].
# Checked against the real arm length of the character (reach 0.51 m from the shoulder): every hand point stays within about 0.5 m.
#   carry = while running (low, close to the body)   ready = standing / walking (in front of the chest)   aim = firing (raised, arms forward)
const GUN_POSES := {
	0: {"carry": [Vector3(0.10, 1.18, -0.04), 40.0], "ready": [Vector3(0.10, 1.26, -0.08), 22.0], "aim": [Vector3(0.09, 1.36, -0.06), 0.0],
		"hand_r": Vector3(0.0, -0.01, 0.015), "hand_l": Vector3(0.0, 0.0, -0.114)},         # SMG: right hand on the pistol grip, left on the fore grip
}
const GUN_HAND_SHIFT := Vector3(0.0, 0.0, 0.0)   # v_014: move the SMG in its own space when the hands miss the grip (x right, y up, z back)
var _gun_low := 0.0     # 0..1 carry pose (running)


func _update_gun(delta: float) -> void:
	if gun == null:
		return
	var visible_now := gun_kind == 0 and not seated and not sleeping
	gun.visible = visible_now
	if not visible_now:
		return
	var moving_fast := running and Vector2(velocity.x, velocity.z).length() > 1.0
	gun_amt = lerpf(gun_amt, 1.0 if aiming else 0.0, minf(14.0 * delta, 1.0))
	_gun_low = lerpf(_gun_low, 1.0 if (moving_fast and not aiming) else 0.0, minf(8.0 * delta, 1.0))
	var pz: Dictionary = GUN_POSES[0]
	var rdy: Array = pz["ready"]
	var carry: Array = pz["carry"]
	var aim: Array = pz["aim"]
	var pos: Vector3 = (rdy[0] as Vector3).lerp(carry[0], _gun_low).lerp(aim[0], gun_amt)
	var pitch: float = lerpf(lerpf(float(rdy[1]), float(carry[1]), _gun_low), float(aim[1]), gun_amt)
	var gb := Basis(Vector3.RIGHT, deg_to_rad(pitch))
	if _cur == "code" and rig != null:
		# code animation: the weapon follows the chest, both hands on it (old rig_anim.gd arm IK)
		var t: Transform3D = rig.chest_xform(Transform3D(gb, pos))
		gun.transform = t
		rig.set_hands(t * (pz["hand_l"] as Vector3), t * (pz["hand_r"] as Vector3), 1.0)
		return
	# v_014: rifle walk clip: the SMG lies in both hands (barrel from the right hand toward the left hand)
	if _cur == "walk_rifle" or _cur == "fire_rifle" or _cur == "idle_rifle":
		var rh = _bone_pos(_hand_bone)
		var lh = _bone_pos(_lhand_bone)
		if rh != null and lh != null and ((lh as Vector3) - (rh as Vector3)).length() > 0.05:
			var gbs := Basis.looking_at(((lh as Vector3) - (rh as Vector3)).normalized(), Vector3.UP)
			# v_030: the rifle turns toward the crosshair point (right hand stays on the grip), so the shot leaves the barrel tip
			if gun_amt > 0.01 and aim_point != Vector3.ZERO and gun.get_parent() is Node3D:
				var tl: Vector3 = (gun.get_parent() as Node3D).global_transform.affine_inverse() * aim_point
				var mz: Vector3 = (rh as Vector3) + gbs * GUN_HAND_SHIFT - gbs * (pz["hand_r"] as Vector3) + gbs * gun_muzzle.position
				var want: Vector3 = tl - mz
				if want.length() > 0.5:
					var nb := Basis.looking_at(want.normalized(), Vector3.UP)
					gbs = gbs.slerp(nb, clampf(gun_amt, 0.0, 1.0))
			gun.transform = Transform3D(gbs, (rh as Vector3) + gbs * GUN_HAND_SHIFT - gbs * (pz["hand_r"] as Vector3))
			return
	# clips: the weapon follows the right hand of the animated character (grip in the hand)
	var hp = _right_hand_pos()
	if hp != null:
		var in_hand: Vector3 = (hp as Vector3) - gb * (pz["hand_r"] as Vector3)
		pos = in_hand.lerp(aim[0], gun_amt)
	gun.transform = Transform3D(gb, pos)


# a limb = a joint node at the top; the box hangs below it, so rotating the joint swings the limb
func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	var part := Util.mi(Util.box(size), color)
	part.position = Vector3(0, -size.y / 2.0, 0)
	j.add_child(part)
	model.add_child(j)
	return j


# Swap the placeholder for your own character (call after the player is in the scene).
func use_model(node: Node3D) -> void:
	for c in model.get_children():
		c.queue_free()
	arm_l = null
	arm_r = null
	leg_l = null
	leg_r = null
	elbow_l = null
	elbow_r = null
	knee_l = null
	knee_r = null
	spine = null
	head = null
	model.add_child(node)

	var box := _model_aabb(node)
	if box.size.y > 0.001:
		var s := HEIGHT / box.size.y
		node.scale = Vector3.ONE * s
		model_scale = s
		node.position.y = -box.position.y * s
	node.rotation_degrees.y = CUSTOM_MODEL_TURN_DEG

	_setup_anims(node)


# Mixamo clips (characters/anims, already fitted to the Valery skeleton) -> an AnimationPlayer next to the skeleton.
func _setup_anims(node: Node3D) -> void:
	anim = null
	skel = null
	_hand_bone = -1
	_lhand_bone = -1
	_hips_bone = -1
	_cur = ""
	rig = null
	var list := node.find_children("*", "Skeleton3D", true, false)
	if list.is_empty():
		push_warning("Character has no skeleton: no animation.")
		return
	var lib = load((anim_prefix + ".res"))
	if not (lib is AnimationLibrary):
		push_warning("Animation file missing: " + (anim_prefix + ".res"))
		return
	# v_014: the rifle walk clip lives in its own file; it is added to the same library
	var rl = load((anim_prefix + "_rifle.res"))
	if rl is AnimationLibrary:
		for rn in rl.get_animation_list():
			if not lib.has_animation(rn):
				lib.add_animation(rn, rl.get_animation(rn))
	else:
		push_warning("Rifle walk file missing: " + (anim_prefix + "_rifle.res"))
	var al = load((anim_prefix + "_axe.res"))   # v_031: chop
	if al is AnimationLibrary:
		for an in al.get_animation_list():
			if not lib.has_animation(an):
				lib.add_animation(an, al.get_animation(an))
	else:
		push_warning("Axe animation file missing: " + (anim_prefix + "_axe.res"))
	skel = list[0]
	for i in skel.get_bone_count():
		var b := _bone_base(skel.get_bone_name(i))
		if b == "RightHand":
			_hand_bone = i
		elif b == "LeftHand":
			_lhand_bone = i
		elif b == "Hips":
			_hips_bone = i
	var ap := AnimationPlayer.new()
	ap.name = "PlayerAnim"
	skel.get_parent().add_child(ap)
	ap.root_node = NodePath("..")
	# the clips point to "Skeleton3D:<bone>": use the real name of the skeleton node
	var sp := String(ap.get_parent().get_path_to(skel))
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(n)
		for i in a.get_track_count():
			var bone := String(a.track_get_path(i)).get_slice(":", 1)
			a.track_set_path(i, NodePath(sp + ":" + bone))
	ap.add_animation_library("", lib)
	anim = ap
	var r := RigAnim.new()
	if r.setup(node):
		rig = r
	_play("idle", 1.0, 0.0)


static func _bone_base(n: String) -> String:
	var u := n.rfind("_")
	if u > 0 and n.substr(u + 1).is_valid_int():
		return n.substr(0, u)
	return n


# play a clip (nothing happens when it is already the current one; a one-shot clip stays on its last pose)
func _play(clip: String, speed: float, blend: float = 0.12) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _cur != clip:
		if _cur == "code":   # back from the code animation (walk / sit): clips take over again
			anim.active = true
			model.position.y = -HEIGHT / 2.0
			if rig != null:
				rig.clear_hands()
		_cur = clip
		anim.play(clip, blend)
	anim.speed_scale = speed


# the old code-made animation (walk with the joystick, sitting): the clip player is switched off while it runs
func _code_mode() -> void:
	if anim == null or rig == null:
		return
	if _cur != "code":
		_cur = "code"
		anim.active = false


# the old code walk (arms and legs swing), same numbers as before
func _code_walk(delta: float, dir: Vector2) -> void:
	_code_mode()
	var sp := minf(dir.length(), 1.0)
	anim_t += delta * 9.0 * sp
	idle_t += delta
	var swing := sin(anim_t) * 0.7 * sp
	var c := cos(anim_t)
	var kmax := 0.95 * sp
	var ebase := lerpf(0.15, 0.35, sp)
	var bob := absf(sin(anim_t)) * 0.016 * sp
	var k := minf(20.0 * delta, 1.0)
	if gun == null or not gun.visible:
		rig.set_hands(Vector3.ZERO, Vector3.ZERO, 0.0)
	rig.apply([swing, -swing, -swing, swing, ebase + maxf(0.0, c) * 0.3 * sp, ebase + maxf(0.0, -c) * 0.3 * sp,
		-0.04 - maxf(0.0, -c) * kmax, -0.04 - maxf(0.0, c) * kmax, 0.06 + 0.04 * sp, 0.0, swing * 0.18, bob,
		sin(idle_t * 2.2) * 0.012 * (1.0 - sp), 1.0, 0.0], k)
	model.position.y = -HEIGHT / 2.0 + bob


func _right_hand_pos():
	return _bone_pos(_hand_bone)


# position of a bone in the space of the gun holder (model space, feet at y = 0)
func _bone_pos(bone: int):
	if skel == null or bone < 0 or gun == null or not gun.is_inside_tree():
		return null
	var w: Vector3 = skel.global_transform * skel.get_bone_global_pose(bone).origin
	return (gun.get_parent() as Node3D).global_transform.affine_inverse() * w


# the character dies: plays the Dying clip, returns its length in seconds
func die() -> float:
	if _dead:
		return 0.0
	_dead = true
	sleeping = false
	running = false
	aiming = false
	if gun != null:
		gun.visible = false
	if anim == null or not anim.has_animation("die"):
		return 0.0
	_play("die", 1.0, 0.1)
	return anim.get_animation("die").length


# v_026: SLEEP button: lie down (Sleeping Idle clip) / get up. Moving the joystick or jumping also wakes the character.
func toggle_sleep() -> void:
	if sleeping:
		wake_up()
	elif not _dead and not seated and is_on_floor() and anim != null and anim.has_animation("sleep"):
		sleeping = true
		running = false
		aiming = false
		if gun != null:
			gun.visible = false
		_play("sleep", 1.0, 0.35)


func wake_up() -> void:
	if sleeping:
		sleeping = false
		if _bench_dir != Vector3.ZERO:   # v_039: stand up from the bench: one step forward, collisions on again
			global_position += _bench_dir * 0.75
			reset_physics_interpolation()
			collision_mask = 3
			_bench_dir = Vector3.ZERO
		_play("idle", 1.0, 0.35)


# v_039: sit on a bench (the SIT button, same button as SLEEP). The bench is a StaticBody3D in group "bench", front = local +Z.
func sit_on_bench(bench: Node3D) -> void:
	if sleeping or _dead or seated or anim == null or not anim.has_animation("sit"):
		return
	var f: Vector3 = bench.global_transform.basis * Vector3(0, 0, 1)
	f.y = 0.0
	f = f.normalized()
	var seat: Vector3 = bench.global_transform * Props.BENCH_SEAT
	collision_mask = 2   # only the ground: the bench body must not push the character away
	velocity = Vector3.ZERO
	global_position = Vector3(seat.x, global_position.y, seat.z)
	reset_physics_interpolation()
	pivot.rotation.y = atan2(-f.x, -f.z)
	_bench_dir = f
	sleeping = true   # same state as sleeping: stick / jump = stand up, the gun is hidden
	running = false
	aiming = false
	if gun != null:
		gun.visible = false
	_play("sit", 1.0, 0.35)


func _model_aabb(root: Node3D) -> AABB:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for m in meshes:
		var xf: Transform3D = inv * m.global_transform
		var b: AABB = xf * m.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# Sit on a seat marker (tractor). Character stays visible; physics off while seated.
func sit(seat: Node3D) -> void:
	seated = true
	sleeping = false
	running = false
	if gun != null:
		gun.visible = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	reparent(seat, false)
	position = Vector3.ZERO
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	pivot.rotation = Vector3.ZERO
	pivot.scale = Vector3.ONE
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	model.position.y = -HEIGHT / 2.0
	if rig != null:
		# the old code sitting pose: hips down to the seat, thighs forward, hands forward
		_code_mode()
		rig.clear_hands()
		var drop := maxf(0.0, rig.hips_height() * model_scale - 0.77) / maxf(model_scale, 0.001)
		rig.apply([1.0, 1.0, 1.45, 1.45, 0.9, 0.9, -1.45, -1.45, 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, drop], 1.0)


func stand(world: Node, pos: Vector3) -> void:
	reparent(world, false)
	global_position = pos
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 3
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	model.position.y = -HEIGHT / 2.0
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	seated = false
	_dead = false
	if anim != null:
		anim.active = true   # the clips take over again (the code pose of sitting is over)
	if rig != null:
		rig.clear_hands()
	_cur = ""
	set_physics_process(true)


func jump() -> void:
	if sleeping:
		wake_up()   # JUMP wakes the character up first
		return
	if is_on_floor():
		velocity.y = JUMP_SPEED
		_snd_jump.play()


func _player(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = db
	add_child(p)
	return p


func _setup_sound() -> void:
	_walk_sounds = AudioLib.custom_streams("walk")
	_run_sounds = AudioLib.custom_streams("run")
	if _walk_sounds.is_empty():
		for i in 4:
			_walk_sounds.append(Sfx.footstep(i + 1))
	if _run_sounds.is_empty():
		_run_sounds = _walk_sounds   # no run sounds: the walk sounds are played faster
	_snd_step = _player(-6.0)
	_snd_jump = _player(-8.0)
	var jc := AudioLib.custom_streams("jump")
	_snd_jump.stream = jc[0] if not jc.is_empty() else Sfx.jump()
	_snd_land = _player(-4.0)
	var lc := AudioLib.custom_streams("land")
	_snd_land.stream = lc[0] if not lc.is_empty() else Sfx.land()


# one step every STEP_EVERY_x seconds while walking / running on the ground
func _footsteps(delta: float, moving: bool) -> void:
	if not is_on_floor():
		_air_t += delta
		_step_t = 0.0
		return
	var flat := Vector2(velocity.x, velocity.z).length()
	if not moving or flat < 0.5:
		_step_t = 0.0
		return
	_step_t += delta
	if _step_t < (STEP_EVERY_RUN if running else STEP_EVERY_WALK):
		return
	_step_t = 0.0
	var list: Array = _run_sounds if running else _walk_sounds
	var i := randi() % list.size()
	if list.size() > 1 and i == _step_last:   # never the same sound twice in a row
		i = (i + 1) % list.size()
	_step_last = i
	_snd_step.stream = list[i]
	_snd_step.pitch_scale = randf_range(0.93, 1.07) * (1.12 if running and _run_sounds == _walk_sounds else 1.0)
	_snd_step.volume_db = -3.0 if running else -6.0
	_snd_step.play()


# Run: tap once = keeps running in the camera direction. Tap again = stop.
func toggle_run() -> void:
	running = not running


func _physics_process(delta: float) -> void:
	var dir := move_dir
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb != Vector2.ZERO:
		dir = kb
	if _dead:
		dir = Vector2.ZERO
		running = false
	elif Input.is_action_just_pressed("ui_accept"):
		jump()
	if sleeping:
		if dir.length() > 0.1:
			wake_up()   # the joystick wakes the character up
		else:
			dir = Vector2.ZERO
			running = false

	# V29: touching the joystick while auto-running stops the run (walk with the stick)
	if running and move_dir.length() > 0.1:
		running = false
	# auto-run: no joystick -> go straight ahead (the way the camera looks)
	if running and dir.length() < 0.1:
		dir = Vector2(0, -1)

	var moving := dir.length() > 0.1
	var speed := RUN_SPEED if running else WALK_SPEED
	var wd := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, cam_yaw)
	var v := velocity
	v.x = wd.x * speed
	v.z = wd.z * speed
	if is_on_floor() and v.y <= 0.0:
		v.y = 0.0
	else:
		v.y -= GRAVITY * delta
	velocity = v
	move_and_slide()
	_footsteps(delta, moving)

	if aiming or (chop_t > 0.0 and not moving):   # v_031: chopping faces where the camera looks
		pivot.rotation.y = lerp_angle(pivot.rotation.y, cam_yaw, 18.0 * delta)
	elif moving:
		var target := atan2(-wd.x, -wd.z)
		pivot.rotation.y = lerp_angle(pivot.rotation.y, target, 12.0 * delta)

	_animate(delta, dir)


func _animate(delta: float, dir: Vector2) -> void:
	var on_floor := is_on_floor()

	# the animation clips (Mixamo): die > jump (in the air) > run / walk > idle
	if not _dead and not sleeping:
		if not on_floor and (_air_t > 0.1 or velocity.y > 3.0):
			_play("jump", 1.0, 0.08)
		elif on_floor:
			if dir.length() > 0.1:
				if gun_kind == 0 and anim != null and anim.has_animation("walk_rifle"):
					# v_014: weapon in the hands -> walk with the rifle (running = the same clip, faster)
					_play("walk_rifle", (1.6 if running else 1.0) * clampf(dir.length(), 0.6, 1.0))
				elif running or rig == null:
					_play("run", 1.0 if running else 0.55)
				else:
					_code_walk(delta, dir)   # dragging the joystick: the old code walk
			elif gun_kind == 1 and chop_t > 0.0 and anim != null and anim.has_animation("chop"):
				_play("chop", 1.0, _chop_blend)   # the axe chop (FIRE with the axe in the hand)
				if _chop_seek >= 0.0:
					anim.seek(_chop_seek, false)
					_chop_seek = -1.0
			elif aiming and gun_kind == 0 and anim != null and anim.has_animation("fire_rifle"):
				# v_028: standing with the gun up: Mixamo Firing Rifle. Shooting = the recoil clip plays, between shots it waits in the first (aim) pose
				if shot_t > 0.0:
					_play("fire_rifle", 1.0, 0.06)
					_fire_hold = false
				else:
					if _cur != "fire_rifle":
						_play("fire_rifle", 0.0, 0.0)
					if not _fire_hold:
						anim.seek(0.0, true)
						_fire_hold = true
					anim.speed_scale = 0.0
			elif gun_kind == 0 and anim != null and anim.has_animation("idle_rifle"):
				_play("idle_rifle", 1.0)   # v_029: standing with the gun in the hands (Mixamo Rifle Idle)
			else:
				_play("idle", 1.0)

	shot_t = maxf(0.0, shot_t - delta)
	chop_t = maxf(0.0, chop_t - delta)
	_update_gun(delta)
	_update_axe()

	# landing squash
	if on_floor and not was_on_floor:
		if _air_t > 0.25:   # a real jump / fall, not a small step down
			_snd_land.volume_db = lerpf(-10.0, 0.0, clampf(_air_t / 0.8, 0.0, 1.0))
			_snd_land.play()
	if on_floor:
		_air_t = 0.0
	was_on_floor = on_floor
