extends Control
# v_015: SETTINGS MENU. The gear button (top right, where the old three-line button was) opens a small list:
#   HUD       -> opens the HUD editor (hud_editor.gd): move / resize / fade every button
#   Sound     -> only a name for now (shows "Coming soon", does nothing)
#   Graphics  -> only a name for now (later: high graphics)
# While the list is open the game is paused and every touch belongs to this menu.
# To give Sound / Graphics a real job later: handle their id in _choose() (or listen to option_selected).

signal option_selected(id: String)

const OPTIONS := [
	{"id": "hud", "text": "HUD"},
	{"id": "tutorial", "text": "Tutorial"},   # v_047: plays the guided tutorial again
	{"id": "sound", "text": "Sound"},
	{"id": "graphics", "text": "Graphics"},
]
const GEAR_R := 36.0
const ROW_H := 60.0
const ROW_GAP := 8.0
const PANEL_W := 250.0

var main
var editor            # hud_editor.gd
var open := false
var _soon_t := 0.0
var _paused_by_me := false
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


# same place and size as the old menu button
func _gear_center() -> Vector2:
	return Vector2(_vp().x - 55.0, 55.0)


func _panel_rect() -> Rect2:
	var vp := _vp()
	var h := 8.0 + float(OPTIONS.size()) * (ROW_H + ROW_GAP)
	return Rect2(vp.x - 20.0 - PANEL_W, 55.0 + GEAR_R + 10.0, PANEL_W, h)


func _row_rect(i: int) -> Rect2:
	var pr := _panel_rect()
	return Rect2(pr.position.x + 8.0, pr.position.y + 8.0 + float(i) * (ROW_H + ROW_GAP), pr.size.x - 16.0, ROW_H)


func _set_pause(on: bool) -> void:
	if on:
		if not get_tree().paused:
			get_tree().paused = true
			_paused_by_me = true
	elif _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false


func _let_go_of_everything() -> void:
	if main != null:
		if main.touch != null:
			main.touch.release_all()
		if main.heli_ui != null:
			main.heli_ui.release_all()


func open_menu() -> void:
	open = true
	_soon_t = 0.0
	_let_go_of_everything()
	_set_pause(true)


func close_menu() -> void:
	open = false
	_set_pause(false)


# called by the HUD editor when it is closed
func on_editor_closed() -> void:
	visible = true
	open = false
	_set_pause(false)


func _choose(id: String) -> void:
	option_selected.emit(id)
	if id == "hud" and editor != null:
		open = false
		visible = false   # the editor has its own screen (the game stays paused)
		editor.open_editor()
	elif id == "tutorial" and main != null and main.get("tutorial") != null:   # v_047
		close_menu()
		main.tutorial.restart()
	else:
		_soon_t = 1.4


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if open:
			if e.pressed:
				_press_open(e.position)
			get_viewport().set_input_as_handled()
		elif e.pressed and e.position.distance_to(_gear_center()) < GEAR_R + 12.0:
			open_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and open:
		get_viewport().set_input_as_handled()


func _press_open(p: Vector2) -> void:
	for i in OPTIONS.size():
		if _row_rect(i).has_point(p):
			_choose(String(OPTIONS[i]["id"]))
			return
	# the gear again, or a tap outside the list, closes it
	if p.distance_to(_gear_center()) < GEAR_R + 12.0 or not _panel_rect().has_point(p):
		close_menu()


func _process(delta: float) -> void:
	_soon_t = maxf(0.0, _soon_t - delta)
	if visible:
		queue_redraw()


func _box(rc: Rect2, bg: Color, border: Color, radius: float, bw: int) -> void:
	_sb.bg_color = bg
	_sb.border_color = border
	_sb.set_border_width_all(bw)
	_sb.set_corner_radius_all(int(radius))
	draw_style_box(_sb, rc)


func _draw_gear(c: Vector2, r: float, col: Color, hole: Color) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.6, c + d * r * 1.2, col, r * 0.42)
	draw_circle(c, r * 0.88, col)
	draw_circle(c, r * 0.38, hole)


# small icons for the list (c = centre of the icon)
func _icon_hud(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-9, -7), 6.0, col)
	draw_circle(c + Vector2(9, -7), 6.0, col)
	draw_circle(c + Vector2(0, 9), 6.0, col)
	draw_arc(c, 17.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 1.5)


func _icon_sound(c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -5), c + Vector2(-7, -5), c + Vector2(1, -13), c + Vector2(1, 13), c + Vector2(-7, 5), c + Vector2(-14, 5)]), col)
	draw_arc(c + Vector2(2, 0), 7.0, deg_to_rad(-50), deg_to_rad(50), 10, col, 2.5)
	draw_arc(c + Vector2(2, 0), 13.0, deg_to_rad(-50), deg_to_rad(50), 12, col, 2.5)


func _icon_graphics(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-16, -12), Vector2(32, 21)), col, false, 2.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-11, 6), c + Vector2(-3, -5), c + Vector2(2, 2), c + Vector2(6, -2), c + Vector2(11, 6)]), col)
	draw_line(c + Vector2(-8, 15), c + Vector2(8, 15), col, 2.5)
	draw_line(c + Vector2(0, 9), c + Vector2(0, 15), col, 2.5)


func _draw() -> void:
	if not visible:
		return
	var vp := _vp()
	var gc := _gear_center()
	if open:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
	# gear button: same glass look as the other buttons
	draw_circle(gc, GEAR_R, Color(0.15, 0.15, 0.2, 0.62 if open else 0.4))
	draw_arc(gc, GEAR_R - 1.5, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5)
	_draw_gear(gc, 14.0, Color(1, 1, 1, 0.95), Color(0.14, 0.15, 0.2, 1.0))
	if not open:
		return
	var pr := _panel_rect()
	_box(pr, Color(0.1, 0.13, 0.16, 0.97), Color(0.35, 0.42, 0.47), 12.0, 2)
	var f := ThemeDB.fallback_font
	for i in OPTIONS.size():
		var rr := _row_rect(i)
		var real: bool = String(OPTIONS[i]["id"]) in ["hud", "tutorial"]   # v_047
		_box(rr, Color(1, 1, 1, 0.1 if real else 0.05), Color(1, 1, 1, 0.25), 10.0, 1)
		var col := Color(1, 1, 1, 0.95 if real else 0.6)
		var ic := Vector2(rr.position.x + 38.0, rr.get_center().y)
		match String(OPTIONS[i]["id"]):
			"hud":
				_icon_hud(ic, col)
			"tutorial":
				draw_circle(ic, 17.0, Color(col.r, col.g, col.b, 0.25))   # v_047: a question mark in a circle
				draw_arc(ic, 17.0, 0.0, TAU, 24, col, 2.0)
				draw_string(f, ic + Vector2(-9.0, 12.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
			"sound":
				_icon_sound(ic, col)
			"graphics":
				_icon_graphics(ic, col)
		draw_string(f, Vector2(rr.position.x + 76.0, rr.get_center().y + 10.0), String(OPTIONS[i]["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
	if _soon_t > 0.0:
		var s := "Coming soon"
		var tp := Vector2(pr.position.x, pr.end.y + 34.0)
		draw_string_outline(f, tp, s, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 26, 6, Color(0, 0, 0, 0.9))
		draw_string(f, tp, s, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 26, Color(1.0, 0.92, 0.5, minf(_soon_t * 2.0, 1.0)))
