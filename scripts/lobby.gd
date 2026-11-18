extends Control
# Lobby (steps 1-2): background picture + menu buttons + the 3D character (camera is fixed, the character turns when you drag). Only START works: it emits start_pressed and main.gd then loads the game.
# Store / Character / Weapon / Eden Island are placeholders for now (they only show "Coming soon").
# Everything is built in code; sizes follow the screen height so it fits any phone.

signal start_pressed

const CharDb = preload("res://scripts/char_db.gd")
const BG_PATH := "res://assets/ui/lobby_bg.jpg"
const CHAR_HEIGHT := 1.7   # metres, the model is scaled to this
const DRAG_SPEED := 0.012   # radians per pixel
const TEAL := Color(0.25, 0.85, 0.8)
const AMBER := Color(1.0, 0.66, 0.15)
const PANEL := Color(0.04, 0.09, 0.14, 0.74)

var _started := false
var _ui: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _chip: PanelContainer
var _start_btn: Button
var _toast: Label
var _toast_tw: Tween
var _buttons: Array[Button] = []
var _pivot: Node3D       # the character turns around this (only left / right)
var _yaw := 0.0
var _drag := false
var _anim: AnimationPlayer
var _vp: SubViewport
var _cp: Control             # the CHARACTER screen (built when it is opened)
var _cards := {}             # character id -> {"panel": PanelContainer, "btn": Button}
var _sel_id := ""            # character shown now (preview)
var _eq_id := ""             # character equipped (used in the game)
var _r := {}                 # labels / picture of the right info box


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_character()
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	_chip = _make_level_chip()   # the level section: only a place holder, it is filled in later
	_ui.add_child(_chip)

	_left = VBoxContainer.new()
	_ui.add_child(_left)
	for t in ["STORE", "CHARACTER", "WEAPON"]:
		var mb := _menu_button(t)
		if t == "CHARACTER":
			mb.pressed.disconnect(_coming_soon)
			mb.pressed.connect(_open_characters)
		_left.add_child(mb)

	_right = VBoxContainer.new()
	_ui.add_child(_right)
	_right.add_child(_mode_button("EDEN ISLAND"))
	_start_btn = _start_button()
	_right.add_child(_start_btn)

	_toast = Label.new()
	_toast.text = "Coming soon"
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_toast)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_pulse_start()


func _unhandled_key_input(e: InputEvent) -> void:   # Enter starts too (for testing on a computer)
	if e.is_pressed() and (e as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_on_start()


# ---------------------------------------------------------------- build

func _build_background() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED   # fills the screen, never stretched
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH) as Texture2D
	else:
		var c := ColorRect.new()   # no picture: a plain night colour
		c.color = Color(0.03, 0.06, 0.16)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
	add_child(bg)
	# soft dark gradients on the left and at the bottom so the buttons are easy to read
	add_child(_shade(Vector2(0, 0.5), Vector2(0.45, 0.5), 0.55))
	add_child(_shade(Vector2(0.5, 1.0), Vector2(0.5, 0.55), 0.6))


func _shade(from: Vector2, to: Vector2, alpha: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, alpha))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 128
	gt.height = 128
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _box(bg: Color, accent: Color, accent_w: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = accent
	s.border_width_left = accent_w
	s.set_corner_radius_all(radius)
	s.content_margin_left = 22
	s.content_margin_right = 18
	return s


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(PANEL, TEAL, 5, 6))
	b.add_theme_stylebox_override("hover", _box(Color(0.07, 0.15, 0.2, 0.85), TEAL, 5, 6))
	b.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.22, 0.28, 0.92), AMBER, 5, 6))
	b.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.pressed.connect(_coming_soon)
	_buttons.append(b)
	return b


func _mode_button(text: String) -> Button:
	var b := _menu_button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_stylebox_override("normal", _box(PANEL, AMBER, 5, 6))
	b.add_theme_stylebox_override("hover", _box(Color(0.12, 0.13, 0.1, 0.88), AMBER, 5, 6))
	return b


func _start_button() -> Button:
	var b := Button.new()
	b.text = "START"
	b.focus_mode = Control.FOCUS_NONE
	var n := _box(AMBER, Color(1, 0.9, 0.55), 0, 10)
	n.set_border_width_all(3)
	n.shadow_color = Color(1.0, 0.6, 0.1, 0.45)
	n.shadow_size = 14
	var h := _box(Color(1.0, 0.74, 0.28), Color(1, 0.95, 0.7), 0, 10)
	h.set_border_width_all(3)
	var p := _box(Color(0.9, 0.5, 0.08), Color(1, 0.9, 0.55), 0, 10)
	p.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color(0.1, 0.07, 0.02))
	b.pressed.connect(_on_start)
	return b


func _make_level_chip() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(PANEL, AMBER, 5, 6))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = "LV 1"
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	pc.add_child(l)
	pc.set_meta("label", l)
	return pc


# ---------------------------------------------------------------- 3D character

func _build_character() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true   # the 3D picture always has the size of the screen
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true   # the lobby picture shows behind the character
	vp.msaa_3d = Viewport.MSAA_DISABLED
	svc.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()   # moonlight from the front-left
	key.light_color = Color(0.85, 0.9, 1.0)
	key.light_energy = 0.8
	key.rotation_degrees = Vector3(-30, -35, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()   # teal rim light from behind (the shape stands out of the picture)
	rim.light_color = Color(0.3, 0.9, 0.85)
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-15, 160, 0)
	vp.add_child(rim)

	var cam := Camera3D.new()   # fixed camera
	cam.fov = 28.0
	cam.position = Vector3(0.0, 1.05, 4.6)
	cam.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
	vp.add_child(cam)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 0.0, 0.0)
	vp.add_child(_pivot)
	vp.add_child(_shadow())

	_vp = vp
	_eq_id = CharDb.selected_id()
	_sel_id = _eq_id
	_load_preview(_eq_id)


# puts the character with this id in the middle (the old one is removed)
func _load_preview(id: String) -> void:
	for c in _pivot.get_children():
		c.queue_free()
	_anim = null
	var ch: Dictionary = CharDb.by_id(id)
	var res = load(String(ch["glb"]))
	if not (res is PackedScene):
		return
	var model := (res as PackedScene).instantiate() as Node3D
	if model == null:
		return
	_pivot.add_child(model)
	var box := _aabb(model)
	if box.size.y > 0.001:
		var k := CHAR_HEIGHT / box.size.y
		model.scale = Vector3.ONE * k
		model.position = Vector3(-(box.position.x + box.size.x * 0.5) * k, -box.position.y * k, -(box.position.z + box.size.z * 0.5) * k)
	_play_idle(model, String(ch["anims"]) + ".res")


func _shadow() -> MeshInstance3D:   # a soft dark spot under the feet
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = gt
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.orientation = PlaneMesh.FACE_Y
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position.y = 0.01
	return mi


func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf: Transform3D = inv * mi.global_transform if root.is_inside_tree() else mi.transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# the idle clip of the game; the clips are copied so the game's own copy is not touched
func _play_idle(model: Node3D, anims_path: String) -> void:
	var sk := model.find_children("*", "Skeleton3D", true, false)
	var lib = load(anims_path)
	if sk.is_empty() or not (lib is AnimationLibrary) or not (lib as AnimationLibrary).has_animation("idle"):
		return
	var skel := sk[0] as Skeleton3D
	var a := (lib as AnimationLibrary).get_animation("idle").duplicate() as Animation
	a.loop_mode = Animation.LOOP_LINEAR
	var ap := AnimationPlayer.new()
	skel.get_parent().add_child(ap)
	ap.root_node = NodePath("..")
	var sp := String(skel.get_parent().get_path_to(skel))
	for i in a.get_track_count():
		var bone := String(a.track_get_path(i)).get_slice(":", 1)
		a.track_set_path(i, NodePath(sp + ":" + bone))
	var l := AnimationLibrary.new()
	l.add_animation("idle", a)
	ap.add_animation_library("", l)
	ap.play("idle")
	_anim = ap


func _gui_input(e: InputEvent) -> void:   # drag on an empty place: the character turns around (left / right only)
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * DRAG_SPEED


func _process(d: float) -> void:
	if _pivot != null:
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _yaw, 1.0 - exp(-14.0 * d))


# ---------------------------------------------------------------- layout (sizes follow the screen height)

func _layout() -> void:
	var vp := get_viewport_rect().size
	var u := vp.y
	var m := u * 0.04
	var ml := m
	var mr := m
	if OS.has_feature("mobile"):   # keep clear of the notch / rounded corners
		var sa := DisplayServer.get_display_safe_area()
		var ws := DisplayServer.window_get_size()
		if ws.x > 0:
			ml += clampf(float(sa.position.x), 0.0, ws.x * 0.08)
			mr += clampf(float(ws.x - sa.end.x), 0.0, ws.x * 0.08)
	# proportions measured from the reference lobby picture (height 400 px, width 720 px):
	# column starts at 23.5 % of the height, a button is 6.5 % high, 8.4 % from one to the next, 14 % of the width wide.
	# The empty space between the level chip and the column is for banners later.
	var bw := clampf(vp.x * 0.14, u * 0.26, u * 0.36)
	var bh := u * 0.065
	var fs := int(u * 0.03)
	for b in _buttons:
		b.add_theme_font_size_override("font_size", fs)
	var chip_l := _chip.get_meta("label") as Label
	chip_l.add_theme_font_size_override("font_size", fs)
	_chip.custom_minimum_size = Vector2(bw, u * 0.06)
	_chip.position = Vector2(ml, m)

	var gap := u * 0.019
	_left.add_theme_constant_override("separation", int(gap))
	for c in _left.get_children():
		(c as Control).custom_minimum_size = Vector2(bw, bh)
	_left.reset_size()
	_left.position = Vector2(ml, u * 0.235)

	_right.add_theme_constant_override("separation", int(u * 0.02))
	_right.get_child(0).custom_minimum_size = Vector2(u * 0.4, u * 0.075)
	_start_btn.custom_minimum_size = Vector2(u * 0.4, u * 0.105)
	_start_btn.add_theme_font_size_override("font_size", int(u * 0.055))
	_right.reset_size()
	_right.position = Vector2(vp.x - mr - _right.size.x, vp.y - m - _right.size.y)
	_start_btn.pivot_offset = _start_btn.custom_minimum_size * 0.5

	_toast.add_theme_font_size_override("font_size", int(u * 0.04))
	_toast.size = Vector2(vp.x, u * 0.08)
	_toast.position = Vector2(0, vp.y * 0.12)


# ---------------------------------------------------------------- actions

func _pulse_start() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_start_btn, "scale", Vector2(1.035, 1.035), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_start_btn, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)


func _coming_soon() -> void:
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast.modulate.a = 1.0
	_toast_tw = create_tween()
	_toast_tw.tween_interval(0.8)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_start() -> void:
	if _started:
		return
	_started = true
	_start_btn.disabled = true
	start_pressed.emit()


# ---------------------------------------------------------------- CHARACTER screen
# left: a card for every character (picture, name, EQUIP / IN USE button); tap a card = look at it in the middle.
# right: picture, name, age, height, story, ability. BACK closes. EQUIP saves the choice (CharDb) - the game starts with that character.

func _open_characters() -> void:
	if _cp != null:
		_cp.queue_free()
	_eq_id = CharDb.selected_id()
	_build_char_panel()
	_left.visible = false
	_right.visible = false
	_chip.visible = false
	_select(_eq_id)


func _close_characters() -> void:
	if _cp != null:
		_cp.queue_free()
		_cp = null
	_left.visible = true
	_right.visible = true
	_chip.visible = true
	if _sel_id != _eq_id:   # only looked at, not equipped: back to the equipped one
		_sel_id = _eq_id
		_load_preview(_eq_id)


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _small_button(text: String, size: int, amber: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	var fill := AMBER if amber else Color(0.12, 0.3, 0.32, 0.9)
	var n := _box(fill, Color(1, 0.9, 0.55), 0, 8)
	n.content_margin_left = 8
	n.content_margin_right = 8
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("disabled", n)
	var fc := Color(0.1, 0.07, 0.02) if amber else Color(0.7, 1.0, 0.95)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(k, fc)
	return b


func _card_box(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.1, 0.22, 0.95)
	s.border_color = AMBER if selected else Color(0.2, 0.4, 0.8, 0.8)
	s.set_border_width_all(4 if selected else 2)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(6)
	return s


func _panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.07, 0.16, 0.9)
	s.border_color = Color(0.2, 0.55, 0.95, 0.9)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(int(get_viewport_rect().size.y * 0.02))
	return s


func _build_char_panel() -> void:
	var vp := get_viewport_rect().size
	var u := vp.y
	var m := u * 0.04
	var pad := u * 0.02
	var pw := clampf(vp.x * 0.3, u * 0.55, u * 0.75)
	var ph := u * 0.86
	var top := u * 0.05
	_cp = Control.new()
	_cp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cp.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the middle stays free: drag turns the character
	_ui.add_child(_cp)
	_cards.clear()

	# ---- left: the list
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _panel_box())
	lp.position = Vector2(m, top)
	lp.custom_minimum_size = Vector2(pw, ph)
	lp.size = Vector2(pw, ph)
	_cp.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", int(pad * 0.6))
	lp.add_child(lv)
	var head := HBoxContainer.new()
	head.add_child(_lbl("CHARACTER", int(u * 0.04), AMBER))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_lbl("%d / %d" % [CharDb.LIST.size(), CharDb.LIST.size()], int(u * 0.032), Color(1, 0.9, 0.7)))
	lv.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(pad * 0.6))
	grid.add_theme_constant_override("v_separation", int(pad * 0.6))
	sc.add_child(grid)
	var cw := (pw - pad * 2.0 - pad * 0.6) / 2.0
	for ch in CharDb.LIST:
		var id: String = ch["id"]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_box(false))
		card.custom_minimum_size = Vector2(cw, 0)
		card.gui_input.connect(_on_card_input.bind(id))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", int(u * 0.008))
		card.add_child(cv)
		var pic := TextureRect.new()
		pic.texture = load(String(ch["portrait"])) as Texture2D
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(cw - 12, (cw - 12) * 0.9)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(pic)
		var nm := _lbl(String(ch["name"]), int(u * 0.036), Color(1, 1, 1))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(nm)
		var btn := _small_button("EQUIP", int(u * 0.03), true)
		btn.pressed.connect(_equip.bind(id))
		cv.add_child(btn)
		grid.add_child(card)
		_cards[id] = {"panel": card, "btn": btn}

	# ---- right: the info box
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _panel_box())
	rp.position = Vector2(vp.x - m - pw, top)
	rp.custom_minimum_size = Vector2(pw, ph)
	rp.size = Vector2(pw, ph)
	_cp.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", int(pad * 0.6))
	rp.add_child(rv)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", int(pad))
	rv.add_child(top_row)
	var rpic := TextureRect.new()
	rpic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rpic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rpic.custom_minimum_size = Vector2(u * 0.25, u * 0.25)
	top_row.add_child(rpic)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(info)
	var r_name := _lbl("", int(u * 0.06), Color(1, 1, 1))
	var r_title := _lbl("", int(u * 0.026), AMBER)
	var r_age := _lbl("", int(u * 0.03), Color(0.85, 0.92, 1))
	var r_h := _lbl("", int(u * 0.03), Color(0.85, 0.92, 1))
	for l in [r_name, r_title, r_age, r_h]:
		info.add_child(l)
	var tw := pw - pad * 2.0
	rv.add_child(_lbl("STORY", int(u * 0.036), AMBER))
	var r_story := _lbl("", int(u * 0.028), Color(0.9, 0.95, 1))
	r_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_story.custom_minimum_size = Vector2(tw, 0)
	rv.add_child(r_story)
	rv.add_child(_lbl("ABILITY", int(u * 0.036), AMBER))
	var abox := PanelContainer.new()
	var ab := _box(Color(0.08, 0.14, 0.3, 0.95), AMBER, 5, 8)
	ab.set_content_margin_all(int(pad * 0.7))
	abox.add_theme_stylebox_override("panel", ab)
	rv.add_child(abox)
	var av := VBoxContainer.new()
	abox.add_child(av)
	var r_an := _lbl("", int(u * 0.032), AMBER)
	var r_at := _lbl("", int(u * 0.027), Color(0.9, 0.95, 1))
	r_at.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_at.custom_minimum_size = Vector2(tw - pad * 2.0, 0)
	av.add_child(r_an)
	av.add_child(r_at)
	_r = {"pic": rpic, "name": r_name, "title": r_title, "age": r_age, "h": r_h, "story": r_story, "an": r_an, "at": r_at}

	# ---- BACK
	var back := _small_button("BACK", int(u * 0.035), true)
	back.custom_minimum_size = Vector2(u * 0.3, u * 0.075)
	back.position = Vector2((vp.x - u * 0.3) * 0.5, vp.y - m - u * 0.075)
	back.pressed.connect(_close_characters)
	_cp.add_child(back)


func _on_card_input(e: InputEvent, id: String) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_select(id)


# shows this character: in the middle (3D) and in the right box
func _select(id: String) -> void:
	if id != _sel_id or _pivot.get_child_count() == 0:
		_sel_id = id
		_load_preview(id)
	_sel_id = id
	var ch: Dictionary = CharDb.by_id(id)
	if not _r.is_empty():
		(_r["pic"] as TextureRect).texture = load(String(ch["portrait"])) as Texture2D
		(_r["name"] as Label).text = String(ch["name"])
		(_r["title"] as Label).text = String(ch["title"])
		(_r["age"] as Label).text = "Age : %d" % int(ch["age"])
		(_r["h"] as Label).text = "Height : %d cm" % int(ch["height"])
		(_r["story"] as Label).text = String(ch["story"])
		(_r["an"] as Label).text = String(ch["ability_name"])
		(_r["at"] as Label).text = String(ch["ability_text"])
	for cid in _cards:
		var c: Dictionary = _cards[cid]
		(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", _card_box(cid == id))
		var b: Button = c["btn"]
		var in_use: bool = cid == _eq_id
		b.text = "IN USE" if in_use else "EQUIP"
		b.disabled = in_use
		var nb := _small_button("", 10, not in_use)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, nb.get_theme_stylebox("normal"))
		var fc := Color(0.7, 1.0, 0.95) if in_use else Color(0.1, 0.07, 0.02)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(k, fc)
		nb.free()


func _equip(id: String) -> void:
	CharDb.set_selected(id)
	_eq_id = id
	_select(id)
