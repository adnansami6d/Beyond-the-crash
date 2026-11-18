class_name Cow
extends Node3D
# Beyond the Crash: a cow (animals/cow.glb, "Farm Cow Animated Dairy cattle" by Rukh3D, CC-BY-4.0).
# Standing: the two idle clips take turns. Walking: the model has no walk clip, so the four legs are swung by code (trot: diagonal legs together).
# The cow wanders: stands 3-8 s, walks 3-7 s in a new direction, and stays within HOME_RADIUS of where it was put.
# The model: 0.94 m long, head toward +Z, feet at y = 0. COW_SCALE makes it a real cow (about 2.4 m long, 1.45 m high).

const COW_PATH := "res://animals/cow.glb"
const COW_SCALE := 2.6
const IDLE_CLIPS := ["Armature|idle1", "Armature|idle2"]
const WALK_SPEED := 0.9        # m/s
const TURN_SPEED := 1.6        # rad/s
const HOME_RADIUS := 28.0
const STEP_RATE := 5.6         # leg cycles in rad/s (one cycle = 1.1 s)
const HIP_SWING := 0.50        # rad, the upper leg
const KNEE_LIFT := 0.65        # rad, the lower leg bends while the leg goes forward
# legs: [upper bone, lower bone, phase, knee direction]. Diagonal legs share a phase (front left + back right, front right + back left).
const LEGS := [
	["lfl1_017", "lfl2_018", 0.0, 1.0], ["lbr1_031", "lbr2_032", 0.0, -1.0],
	["lfr1_021", "lfr2_022", PI, 1.0], ["lbl1_02", "lbl2_03", PI, -1.0],
]

const MAX_HP := 100.0
const MEAT := 3               # pieces of meat that fall when the cow dies
const FLEE_TIME := 4.0
const FLEE_SPEED := 2.4       # m/s when hurt

var hp := MAX_HP
var dead := false
var body: StaticBody3D        # the hit box (group "cow"): bullets and the axe find the cow through it
var _flee := 0.0
var anim: AnimationPlayer
var ground: Callable
var area_check: Callable   # (x, z) -> bool, "is this place inside the map?"
var _model: Node3D
var _skel: Skeleton3D
var _idle_i := 0
var _home := Vector3.ZERO
var _state := "stand"      # stand / walk
var _timer := 3.0
var _heading := 0.0        # where the cow wants to look (yaw)
var _phase := 0.0
var _amp := 0.0            # 0 = standing, 1 = full stride
var _legs: Array = []      # [upper bone, upper rest, upper axis, lower bone, lower rest, lower axis, phase, knee dir]


# put the cow at x, z (ground height from the world), looking toward `yaw` (radians, 0 = looks to -Z like the character)
func setup(ground_fn: Callable, x: float, z: float, yaw: float) -> void:
	ground = ground_fn
	var ps = load(COW_PATH)
	if ps == null:
		push_warning("Cow model missing: " + COW_PATH)
		return
	_model = ps.instantiate()
	_model.scale = Vector3.ONE * COW_SCALE
	_model.rotation.y = PI   # the model looks to +Z, the game's "forward" is -Z
	add_child(_model)
	position = Vector3(x, ground.call(x, z), z)
	_home = position
	rotation.y = yaw
	_make_body()
	_heading = yaw
	_timer = randf_range(1.0, 6.0)
	var found := _model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	anim = found[0]
	for n in IDLE_CLIPS:   # the idle clips loop
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_next_idle)
	_play_idle(randf() * 2.0)   # every cow starts at another second, so they do not move together
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_skel = sks[0]
		_find_legs()


# each leg bone turns about the body's side axis (the skeleton's X axis): the axis is written in the bone's own space once
func _find_legs() -> void:
	for l in LEGS:
		var u := _skel.find_bone(l[0])
		var w := _skel.find_bone(l[1])
		if u < 0 or w < 0:
			continue
		var ua: Vector3 = _skel.get_bone_global_rest(u).basis.orthonormalized().inverse() * Vector3.RIGHT
		var wa: Vector3 = _skel.get_bone_global_rest(w).basis.orthonormalized().inverse() * Vector3.RIGHT
		_legs.append([u, _skel.get_bone_rest(u).basis.orthonormalized().get_rotation_quaternion(), ua,
			w, _skel.get_bone_rest(w).basis.orthonormalized().get_rotation_quaternion(), wa, l[2], l[3]])


# the hit box: about the size of the cow's body (1.0 x 1.4 x 2.2 m), on layer 1 like trees and rocks
func _make_body() -> void:
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("cow")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.0, 1.4, 2.2)
	cs.shape = bx
	cs.position = Vector3(0.0, 0.75, 0.0)
	body.add_child(cs)
	add_child(body)


# a bullet or the axe: dmg points of damage; `from` = where it came from (the cow runs away from there)
func hurt(dmg: float, from: Vector3) -> void:
	if dead:
		return
	hp -= dmg
	if hp <= 0.0:
		_die()
		return
	var away := global_position - from
	_heading = atan2(-away.x, -away.z)
	_flee = FLEE_TIME
	_state = "walk"
	_timer = FLEE_TIME


func _die() -> void:
	dead = true
	_state = "stand"
	_amp = 0.0
	if body != null:
		body.queue_free()
		body = null
	if anim != null and anim.has_animation("Armature|Death"):
		anim.get_animation("Armature|Death").loop_mode = Animation.LOOP_NONE
		if anim.animation_finished.is_connected(_next_idle):
			anim.animation_finished.disconnect(_next_idle)
		anim.play("Armature|Death")
	var shooter = get_parent().get("shooter")   # the cows are children of main
	await get_tree().create_timer(1.2).timeout
	if shooter != null and is_inside_tree():
		for i in MEAT:
			shooter._spawn_item("meat", global_position + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)))
		shooter.hud.say("Cow down +%d meat" % MEAT, 1.5)
	await get_tree().create_timer(25.0).timeout   # the body stays for a while, then it goes
	if is_inside_tree():
		queue_free()


func _play_idle(from_s: float = 0.0) -> void:
	var n: String = IDLE_CLIPS[_idle_i % IDLE_CLIPS.size()]
	if anim != null and anim.has_animation(n):
		anim.play(n)
		anim.seek(from_s, true)


func _next_idle(_name: StringName) -> void:
	_idle_i += 1
	if _state == "stand" and _amp <= 0.0:
		_play_idle()


func _process(delta: float) -> void:
	if _model == null or dead:
		return
	if _flee > 0.0:
		_flee -= delta
	_timer -= delta
	if _timer <= 0.0:
		if _state == "stand":
			_state = "walk"
			_timer = randf_range(3.0, 7.0)
			_heading = _pick_heading()
		else:
			_state = "stand"
			_timer = randf_range(3.0, 8.0)
	var want := 1.0 if _state == "walk" else 0.0
	var was := _amp
	_amp = move_toward(_amp, want, delta * 2.5)
	if _amp > 0.0 and was <= 0.0 and anim != null:
		anim.pause()   # the idle pose stays, the four legs are driven by code
	if _amp <= 0.0 and was > 0.0:
		_play_idle()
	if _amp > 0.0:
		_phase += delta * STEP_RATE * (0.4 + 0.6 * _amp) * (1.7 if _flee > 0.0 else 1.0)
		_swing_legs()
		# turn toward the heading, then walk
		var d := wrapf(_heading - rotation.y, -PI, PI)
		rotation.y += clampf(d, -TURN_SPEED * delta, TURN_SPEED * delta)
		if absf(d) < 0.6:
			var fwd := -global_transform.basis.z
			var np := position + fwd * (FLEE_SPEED if _flee > 0.0 else WALK_SPEED) * _amp * delta
			if area_check.is_valid() and not area_check.call(np.x, np.z):
				_heading = _pick_heading()   # the edge of the map: look for another way
			else:
				position.x = np.x
				position.z = np.z
				position.y = ground.call(np.x, np.z)


# a new direction: toward home when the cow is far away, otherwise anywhere
func _pick_heading() -> float:
	var to_home := _home - position
	if to_home.length() > HOME_RADIUS:
		return atan2(-to_home.x, -to_home.z) + randf_range(-0.5, 0.5)
	return randf() * TAU


func _swing_legs() -> void:
	for e in _legs:
		var ph: float = _phase + float(e[6])
		var swing := sin(ph) * HIP_SWING * _amp            # + = leg goes forward
		var lift := maxf(0.0, cos(ph)) * KNEE_LIFT * _amp   # the knee bends while the leg comes forward
		# forward = -Y of the skeleton, so a forward swing is a negative turn about +X
		_skel.set_bone_pose_rotation(int(e[0]), (e[1] as Quaternion) * Quaternion(e[2] as Vector3, -swing))
		_skel.set_bone_pose_rotation(int(e[3]), (e[4] as Quaternion) * Quaternion(e[5] as Vector3, lift * float(e[7])))
