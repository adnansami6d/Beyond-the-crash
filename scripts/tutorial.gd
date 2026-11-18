extends Control
# v_047: GUIDED TUTORIAL (like Free Fire). A new player is led step by step: the button to use is lit up
# (screen dimmed around it, pulsing ring, bobbing arrow, short text). The step finishes only when the player
# really does it (a button signal, the inventory, the weapon in the hand ...), then a green "Great!" and the next step.
# The overlay never blocks the game: it only takes touches on its own buttons (SKIP ALL / NEXT STEP / GOT IT).
# Button places come from touch_controls.gd (center_px, _rad, _group_rects), so the arrows follow a HUD layout the
# player changed in the HUD editor.
# Saved: user://tutorial.cfg  [tutorial] done=true  (written when the tutorial is finished or skipped).
# The gear menu has a "Tutorial" row that plays it again (settings_menu.gd -> restart()).
# To add a step: add a line to STEPS, a rule for it in _check(), and (if a button / box must be lit) in _view().
# Text is English on purpose: the built-in font has no Bengali letters.

const SAVE := "user://tutorial.cfg"
const GOLD := Color(1.0, 0.85, 0.25)
const GREEN := Color(0.35, 1.0, 0.45)
const SKIP_AFTER := 20.0     # seconds after which a NEXT STEP button appears (a player who is stuck is never locked)
const AXE := 1               # index in shooter.WEAPONS
const SMG := 0

const STEPS := [
	{"id": "welcome", "text": ""},
	{"id": "move", "text": "Touch and drag on the LEFT side of the screen to walk"},
	{"id": "look", "text": "Drag on the RIGHT side of the screen to look around"},
	{"id": "run", "text": "Tap RUN to run faster"},
	{"id": "jump", "text": "Tap JUMP to jump"},
	{"id": "axe", "text": "Tap the AXE box to hold the axe"},
	{"id": "tree", "text": "Walk to the tree, then hold FIRE to chop it. You get wood"},
	{"id": "bag", "text": "Tap BAG to see what you collected"},
	{"id": "bagclose", "text": "Tap the red X to close the bag"},
	{"id": "build", "text": "Tap BUILD to switch to building mode"},
	{"id": "place", "text": "Aim at the ground and hold PLACE to put a block"},
	{"id": "build_off", "text": "Tap the BUILD button again to go back to fighting"},
	{"id": "gun", "text": "Tap the SMG box to take your gun"},
	{"id": "fire", "text": "Hold FIRE to shoot"},
	{"id": "reload", "text": "Tap the big AMMO box to reload"},
	{"id": "bars", "text": "The top bar is your HEALTH. The bar under it is HUNGER. When you are hungry you cannot run. Hunt cows with the axe and eat the meat from the BAG. At night ghosts attack: build a shelter!"},
	{"id": "vehicle", "text": "Walk to the tractor or the helicopter and tap IN/OUT to get in"},
]

var main
var touch
var shooter
var active := false
var _i := 0
var _t := 0.0              # seconds in this step
var _acc := 0.0            # progress inside a step (seconds of walking, shooting ...)
var _flash := 0.0          # > 0: the green "Great!" is shown, then the next step starts
var _ph := 0.0             # animation clock
var _start_wood := 0
var _look_px := 0.0
var _ev := ""              # "run" / "jump" / "reload": set by the touch signals
var _go := false           # a GOT IT / LET'S GO button was pressed
var _tree := Vector3.ZERO
var _has_tree := false
var _tree_t := 0.0
var _hide := false
var _end_t := 0.0          # seconds left of the closing banner
var _skip_rect := Rect2()
var _next_rect := Rect2()
var _ok_rect := Rect2()
var _ok2_rect := Rect2()
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


# main.gd calls this right after add_child (touch and shooter already exist)
func setup(m) -> void:
	main = m
	touch = m.touch
	shooter = m.shooter
	touch.run_pressed.connect(func() -> void: _ev = "run")
	touch.jump_pressed.connect(func() -> void: _ev = "jump")
	touch.reload_pressed.connect(func() -> void: _ev = "reload")
	touch.look_dragged.connect(func(dx: float, dy: float) -> void: _look_px += absf(dx) + absf(dy))


# main.gd calls this when the loading screen is gone: a new player gets the tutorial, an old one does not
func begin() -> void:
	if not _was_done():
		restart()


func restart() -> void:
	active = true
	_end_t = 0.0
	_i = 0
	_flash = 0.0
	_begin_step()
	visible = true


func _was_done() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return false
	return bool(cf.get_value("tutorial", "done", false))


func _finish(completed: bool) -> void:
	active = false
	var cf := ConfigFile.new()
	cf.set_value("tutorial", "done", true)
	cf.save(SAVE)
	if completed:
		_end_t = 4.5
	else:
		visible = false


func _begin_step() -> void:
	_t = 0.0
	_acc = 0.0
	_ev = ""
	_go = false
	_look_px = 0.0
	_tree_t = 0.0
	_start_wood = int(shooter.inv.get("wood", 0))


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


# ---------------------------------------------------------------- logic

func _slot_of(w: int) -> int:
	for k in shooter.slots.size():
		if int(shooter.slots[k]) == w:
			return k
	return -1


func _holding(w: int) -> bool:
	return shooter.hand >= 0 and int(shooter.cur) == w


# does the player do what this step asks?
func _check(id: String, dt: float) -> bool:
	match id:
		"welcome", "bars":
			return _go
		"move":
			if touch.move_dir.length() > 0.4:
				_acc += dt
			return _acc > 1.2
		"look":
			return _look_px > 450.0
		"run":
			if main.combat != null and not main.combat.can_run():
				return true   # too hungry to run: nothing to teach here
			return _ev == "run"
		"jump":
			return _ev == "jump"
		"axe":
			return _slot_of(AXE) < 0 or _holding(AXE)
		"tree":
			return int(shooter.inv.get("wood", 0)) > _start_wood
		"bag":
			return bool(shooter.bag_open)
		"bagclose":
			return _t > 0.5 and not bool(shooter.bag_open)
		"build":
			return bool(touch.build_mode)
		"place":
			return bool(touch.held.get("place", false)) or int(shooter.inv.get("wood", 0)) < _start_wood
		"build_off":
			return not bool(touch.build_mode)
		"gun":
			return _slot_of(SMG) < 0 or _holding(SMG)
		"fire":
			if bool(shooter.firing) and _holding(SMG):
				_acc += dt
			return _acc > 0.6
		"reload":
			return _ev == "reload"
		"vehicle":
			return bool(main.driving) or bool(main.flying)
	return true


func _process(delta: float) -> void:
	if main == null or (not active and _end_t <= 0.0):
		return
	_ph += delta
	var dead: bool = main.combat != null and main.combat.dead
	var menu: bool = main.settings_menu != null and main.settings_menu.open
	_hide = get_tree().paused or bool(touch.edit) or dead or menu
	if not active:   # the closing banner
		_end_t -= delta
		if _end_t <= 0.0:
			visible = false
		queue_redraw()
		return
	if _hide:
		queue_redraw()
		return
	var id: String = STEPS[_i]["id"]
	if (main.driving or main.flying) and id != "vehicle":
		queue_redraw()   # waits (the screen says "get out first")
		return
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_i += 1
			if _i >= STEPS.size():
				_finish(true)
			else:
				_begin_step()
		queue_redraw()
		return
	_t += delta
	_tree_t -= delta
	if _tree_t <= 0.0:
		_tree_t = 0.6
		if id == "tree":
			_find_tree()
	if _check(id, delta):
		_flash = 0.9
		_ev = ""
	queue_redraw()


# the nearest standing tree (the 400 map trees are in the group "cut_holder": holder -> body -> one shape per tree)
func _find_tree() -> void:
	var pp: Vector3 = main.actor_position()
	var best := INF
	_has_tree = false
	for h in get_tree().get_nodes_in_group("cut_holder"):
		for body in h.get_children():
			if not (body is StaticBody3D):
				continue
			for cs in body.get_children():
				if not (cs is CollisionShape3D):
					continue
				var c3 := cs as CollisionShape3D
				if c3.disabled or String(c3.get_meta("kind", "")) != "tree":
					continue
				var d: float = c3.global_position.distance_squared_to(pp)
				if d < best:
					best = d
					_tree = c3.global_position
					_has_tree = true


# ---------------------------------------------------------------- input (only our own buttons)

func _input(event: InputEvent) -> void:
	if not active or _hide or not visible:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var p: Vector2 = (event as InputEventScreenTouch).position
		if _ok_rect.has_point(p):
			_go = true
		elif _ok2_rect.has_point(p) or _skip_rect.has_point(p):
			_finish(false)
		elif _next_rect.has_point(p):
			_flash = 0.3
		else:
			return
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- what to show for a step

func _circ(id: String) -> Dictionary:
	return {"c": touch.center_px(id), "r": touch._rad(id)}


func _gun_box(w: int) -> Dictionary:
	var k := _slot_of(w)
	if k < 0:
		return {}
	var rects: Dictionary = touch._group_rects("guns")
	return {"rc": rects[touch.GUN_BOXES[k]]}


func _bag_x_rect() -> Rect2:
	var vp := _vp()
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var pr := Rect2(vp.x * 0.025, 0.0, vp.x * 0.95, vp.y)   # the same numbers as bag_ui.gd
	return Rect2(pr.end.x - 16.0 * u - 170.0 * u, pr.position.y + 8.0 * u, 56.0 * u, 48.0 * u)


# text, the lit target, dim around it, and a demo / world pointer for one step
func _view(id: String) -> Dictionary:
	var v := {"text": String(STEPS[_i]["text"]), "tg": {}, "dim": false, "demo": "", "wpos": null, "wtxt": ""}
	match id:
		"move":
			v["demo"] = "stick"
		"look":
			v["demo"] = "swipe"
		"run":
			v["tg"] = _circ("run")
			v["dim"] = true
		"jump":
			v["tg"] = _circ("jump")
			v["dim"] = true
		"axe":
			v["tg"] = _gun_box(AXE)
			v["dim"] = true
		"tree":
			if not _holding(AXE):
				v["text"] = "First take the axe: tap the AXE box"
				v["tg"] = _gun_box(AXE)
				v["dim"] = true
			else:
				v["tg"] = _circ("fire")
				if _has_tree:
					v["wpos"] = _tree
					v["wtxt"] = "TREE"
		"bag":
			v["tg"] = _circ("bag")
			v["dim"] = true
		"bagclose":
			v["tg"] = {"rc": _bag_x_rect()}
		"build":
			v["tg"] = _circ("mode")
			v["dim"] = true
		"place":
			v["tg"] = _circ("place")
			if int(shooter.inv.get("wood", 0)) <= 0:
				v["text"] += "\n(You need wood: use the BAG to see your blocks)"
		"build_off":
			v["tg"] = _circ("mode")
			v["dim"] = true
		"gun":
			if bool(touch.build_mode):
				v["text"] = "Tap the BUILD button to leave building mode"
				v["tg"] = _circ("mode")
			else:
				v["tg"] = _gun_box(SMG)
			v["dim"] = true
		"fire":
			if bool(touch.build_mode):
				v["text"] = "Tap the BUILD button to leave building mode"
				v["tg"] = _circ("mode")
				v["dim"] = true
			elif not _holding(SMG):
				v["text"] = "First take the gun: tap the SMG box"
				v["tg"] = _gun_box(SMG)
				v["dim"] = true
			else:
				v["tg"] = _circ("fire")
		"reload":
			if bool(touch.build_mode):
				v["text"] = "Tap the BUILD button to leave building mode"
				v["tg"] = _circ("mode")
			else:
				var rects: Dictionary = touch._group_rects("guns")
				v["tg"] = {"rc": rects["main"]}
			v["dim"] = true
		"bars":
			var a: Rect2 = touch.bar_rect("hp")
			v["tg"] = {"rc": a.merge(touch.bar_rect("hunger"))}
			v["dim"] = true
		"vehicle":
			var best: Vector3 = main.tractor.global_position
			var wt := "TRACTOR"
			var pp: Vector3 = main.actor_position()
			if main.heli.global_position.distance_to(pp) < best.distance_to(pp):
				best = main.heli.global_position
				wt = "HELICOPTER"
			v["wpos"] = best + Vector3(0, 2.0, 0)
			v["wtxt"] = wt
	return v


# ---------------------------------------------------------------- drawing

func _box(rc: Rect2, bg: Color, border: Color, radius: float, bw: int) -> void:
	_sb.bg_color = bg
	_sb.border_color = border
	_sb.set_border_width_all(bw)
	_sb.set_corner_radius_all(int(radius))
	draw_style_box(_sb, rc)


func _pill(rc: Rect2, text: String, col: Color, u: float) -> void:
	_box(rc, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.95), col, 12.0 * u, 3)
	var f := ThemeDB.fallback_font
	var fs := int(24.0 * u)
	draw_string(f, Vector2(rc.position.x, rc.get_center().y + fs * 0.33), text, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, fs, Color.WHITE)


# a text bubble, centred; returns its rectangle
func _bubble(text: String, vp: Vector2, u: float, top: float, border: Color) -> Rect2:
	var f := ThemeDB.fallback_font
	var fs := int(26.0 * u)
	var w := minf(vp.x * 0.66, 700.0 * u)
	var iw := w - 36.0 * u
	var sz: Vector2 = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, iw, fs)
	var rc := Rect2(vp.x * 0.5 - w * 0.5, top, w, sz.y + 30.0 * u)
	_box(rc, Color(0.07, 0.09, 0.12, 0.92), border, 14.0 * u, 3)
	draw_multiline_string(f, Vector2(rc.position.x + 18.0 * u, rc.position.y + 15.0 * u + f.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_CENTER, iw, fs, -1, Color.WHITE)
	return rc


# arrow whose TIP is at `tip` and that points along `d`
func _arrow(tip: Vector2, d: Vector2, col: Color, u: float) -> void:
	var perp := Vector2(-d.y, d.x)
	var base := tip - d * 38.0 * u
	var tri := PackedVector2Array([tip, base + perp * 22.0 * u, base - perp * 22.0 * u])
	draw_colored_polygon(tri, col)
	draw_line(base, base - d * 30.0 * u, col, 14.0 * u)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.8), 2.0)


func _spot(tg: Dictionary, vp: Vector2, u: float, dim: bool) -> void:
	var rc: Rect2
	var round_btn := tg.has("c")
	var c := Vector2.ZERO
	var r := 0.0
	if tg.has("rc"):
		rc = (tg["rc"] as Rect2).grow(10.0 * u)
	else:
		c = tg["c"]
		r = float(tg["r"]) + 12.0
		rc = Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
	if dim:
		var dc := Color(0, 0, 0, 0.5)
		draw_rect(Rect2(0, 0, vp.x, maxf(rc.position.y, 0.0)), dc)
		draw_rect(Rect2(0, rc.end.y, vp.x, maxf(vp.y - rc.end.y, 0.0)), dc)
		draw_rect(Rect2(0, rc.position.y, maxf(rc.position.x, 0.0), rc.size.y), dc)
		draw_rect(Rect2(rc.end.x, rc.position.y, maxf(vp.x - rc.end.x, 0.0), rc.size.y), dc)
	var pulse := 0.5 + 0.5 * sin(_ph * 5.0)
	if round_btn:
		draw_arc(c, r + pulse * 8.0 * u, 0.0, TAU, 48, GOLD, 5.0)
		draw_arc(c, r, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.45), 3.0)
	else:
		draw_rect(rc.grow(pulse * 7.0 * u), GOLD, false, 5.0)
	# the arrow comes from the side of the screen centre and bobs toward the target
	var mid := rc.get_center()
	var dir := vp * 0.5 - mid
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.UP
	var ext := maxf(rc.size.x, rc.size.y) * 0.5
	var tip := mid + dir * (ext + 14.0 * u + sin(_ph * 7.0) * 10.0 * u)
	_arrow(tip, -dir, GOLD, u)


# a pointer to a place in the world: above it if it is on the screen, else on the screen edge
func _world_pointer(pos: Vector3, label: String, vp: Vector2, u: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := ThemeDB.fallback_font
	var behind := cam.is_position_behind(pos)
	var sp := cam.unproject_position(pos)
	var m := 80.0 * u
	var dist: float = main.actor_position().distance_to(pos)
	var txt := "%s  %d m" % [label, int(dist)]
	var fs := int(24.0 * u)
	if not behind and Rect2(m, m, vp.x - 2.0 * m, vp.y - 2.0 * m).has_point(sp):
		var tip := sp + Vector2(0, -26.0 * u + sin(_ph * 7.0) * 10.0 * u)
		_arrow(tip, Vector2.DOWN, GREEN, u)
		var tp := tip + Vector2(-120.0 * u, -70.0 * u)
		draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * u, fs, 6, Color(0, 0, 0, 0.9))
		draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * u, fs, GREEN)
	else:
		var c := vp * 0.5
		var dir := sp - c
		if behind:
			dir = -dir
		dir = dir.normalized() if dir.length() > 1.0 else Vector2.DOWN
		var half := vp * 0.5 - Vector2(m, m)
		var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var p := c + dir * k
		_arrow(p + dir * 10.0 * u, dir, GREEN, u)
		var tp2 := p - dir * 60.0 * u + Vector2(-120.0 * u, 8.0 * u)
		draw_string_outline(f, tp2, txt, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * u, fs, 6, Color(0, 0, 0, 0.9))
		draw_string(f, tp2, txt, HORIZONTAL_ALIGNMENT_CENTER, 240.0 * u, fs, GREEN)


func _demo_stick(vp: Vector2, u: float) -> void:
	var base := Vector2(vp.x * 0.17, vp.y * 0.68)
	var rad := 90.0 * u
	draw_circle(base, rad, Color(1, 1, 1, 0.1))
	draw_arc(base, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0)
	var a := _ph * 2.2
	var knob := base + Vector2(cos(a), sin(a)) * rad * 0.6
	draw_line(base, knob, Color(GOLD.r, GOLD.g, GOLD.b, 0.6), 8.0 * u)
	draw_circle(knob, 30.0 * u, Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	draw_circle(knob, 12.0 * u, Color(1, 1, 1, 0.9))


func _demo_swipe(vp: Vector2, u: float) -> void:
	var c := Vector2(vp.x * 0.68, vp.y * 0.52)
	var span := 120.0 * u
	draw_line(c - Vector2(span, 0), c + Vector2(span, 0), Color(1, 1, 1, 0.35), 6.0 * u)
	var p := c + Vector2(sin(_ph * 2.4) * span, 0)
	draw_circle(p, 30.0 * u, Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	draw_circle(p, 12.0 * u, Color(1, 1, 1, 0.9))
	for s in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(s * (span + 24.0 * u), 0)
		draw_colored_polygon(PackedVector2Array([e + Vector2(s * 18.0 * u, 0), e + Vector2(0, -16.0 * u), e + Vector2(0, 16.0 * u)]), Color(1, 1, 1, 0.55))


func _check_mark(c: Vector2, u: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-20, 0) * u, c + Vector2(-6, 15) * u, c + Vector2(22, -17) * u]), GREEN, 8.0 * u)


func _draw() -> void:
	_skip_rect = Rect2()
	_next_rect = Rect2()
	_ok_rect = Rect2()
	_ok2_rect = Rect2()
	if not visible or _hide or main == null:
		return
	var vp := _vp()
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var f := ThemeDB.fallback_font
	if not active:   # closing banner
		_check_mark(Vector2(vp.x * 0.5, vp.y * 0.30), u)
		_bubble("TUTORIAL COMPLETE!\nGood luck, survivor.", vp, u, vp.y * 0.34, GREEN)
		return
	var id: String = STEPS[_i]["id"]
	var step_no := "STEP %d / %d" % [_i, STEPS.size() - 1]
	# the buttons that are always there (not on the welcome panel)
	if id != "welcome":
		_skip_rect = Rect2(16.0, vp.y * 0.30, 170.0 * u, 46.0 * u)
		_pill(_skip_rect, "SKIP ALL", Color(0.8, 0.8, 0.85), u)
		if _t > SKIP_AFTER and _flash <= 0.0 and id != "bars":
			_next_rect = Rect2(16.0, vp.y * 0.30 + 56.0 * u, 170.0 * u, 46.0 * u)
			_pill(_next_rect, "NEXT STEP", Color(0.45, 0.75, 1.0), u)
	if (main.driving or main.flying) and id != "vehicle":
		_bubble("Get out of the vehicle to go on with the tutorial", vp, u, vp.y * 0.33, GOLD)
		return
	if _flash > 0.0:
		_check_mark(Vector2(vp.x * 0.5, vp.y * 0.30), u)
		_bubble("Great!", vp, u, vp.y * 0.34, GREEN)
		return
	if id == "welcome":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))
		var title_fs := int(44.0 * u)
		var ty := vp.y * 0.30
		draw_string_outline(f, Vector2(0, ty), "WELCOME, SURVIVOR!", HORIZONTAL_ALIGNMENT_CENTER, vp.x, title_fs, 8, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(0, ty), "WELCOME, SURVIVOR!", HORIZONTAL_ALIGNMENT_CENTER, vp.x, title_fs, GOLD)
		var br := _bubble("Learn the basics in about 2 minutes:\nwalk, chop trees, build, shoot and drive.", vp, u, ty + 30.0 * u, GOLD)
		_ok_rect = Rect2(vp.x * 0.5 - 250.0 * u, br.end.y + 24.0 * u, 230.0 * u, 58.0 * u)
		_ok2_rect = Rect2(vp.x * 0.5 + 20.0 * u, br.end.y + 24.0 * u, 230.0 * u, 58.0 * u)
		_pill(_ok_rect, "LET'S GO", GREEN, u)
		_pill(_ok2_rect, "SKIP", Color(0.8, 0.8, 0.85), u)
		return
	var v: Dictionary = _view(id)
	var tg: Dictionary = v["tg"]
	var bag_up: bool = bool(shooter.bag_open)
	if not bag_up:
		if String(v["demo"]) == "stick":
			_demo_stick(vp, u)
		elif String(v["demo"]) == "swipe":
			_demo_swipe(vp, u)
		if not tg.is_empty():
			_spot(tg, vp, u, bool(v["dim"]))
		if v["wpos"] != null:
			_world_pointer(v["wpos"], String(v["wtxt"]), vp, u)
	elif id == "bagclose" and not tg.is_empty():
		_spot(tg, vp, u, false)
	draw_string(f, Vector2(vp.x * 0.5 - minf(vp.x * 0.33, 350.0 * u), vp.y * 0.33 - 8.0 * u), step_no, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20.0 * u), Color(GOLD.r, GOLD.g, GOLD.b, 0.85))
	var bubble_top := vp.y * 0.33
	if bag_up and id != "bagclose":
		bubble_top = vp.y * 0.55
	var rc := _bubble(String(v["text"]), vp, u, bubble_top, GOLD)
	if id == "bars":
		_ok_rect = Rect2(vp.x * 0.5 - 115.0 * u, rc.end.y + 14.0 * u, 230.0 * u, 54.0 * u)
		_pill(_ok_rect, "GOT IT", GREEN, u)
