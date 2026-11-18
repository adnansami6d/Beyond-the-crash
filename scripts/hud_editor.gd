extends Control
# v_015: HUD EDITOR (gear button -> HUD). Opens over the game (the game is paused while it is open).
#   - Tap a button on the screen to select it, drag it to move it.
#   - Panel at the top:  EXIT | < HUD n > | VIEW      RESET | SAVE      Opacity slider, Size slider, arrow pad (fine moving).
#   - HUD 1 / 2 / 3 are three separate layouts. SAVE writes the one on the screen (user://hud_layout.cfg, see touch_controls.gd).
#   - VIEW switches between the buttons of FOOT (shooting), BUILD, DRIVE (tractor) and FLY (helicopter).
#   - The small arrow tab under the panel hides / shows the panel, so buttons behind it can be reached.
# All layout data lives in touch_controls.gd (btn). This script is only the screen with the panel and the touch handling.

signal closed

const NAMES := {
	"jump": "JUMP", "run": "RUN", "action": "IN / OUT", "gas": "GAS", "brake": "BRAKE", "left": "LEFT", "right": "RIGHT",
	"hitch": "ATTACH", "poi": "SHOP", "fire": "FIRE", "reload": "RELOAD", "bag": "BAG", "sleep": "SLEEP", "swap": "SWAP", "guns": "GUN BOXES (3 together)", "hp": "HEALTH BAR", "hunger": "HUNGER BAR", "mode": "BUILD / SHOOT",
	"place": "PLACE", "break": "BREAK", "alt_up": "HELI UP", "alt_dn": "HELI DOWN", "exit": "HELI GET OUT",
}
const VIEW_NAMES := ["FOOT", "BUILD", "DRIVE", "FLY"]
const NUDGE_STEP := 2.0       # pixels per step of the arrow pad

var main
var touch             # touch_controls.gd
var heli_ui           # heli_ui.gd
var active := false
var collapsed := false
var dirty := false    # something changed and is not saved yet
var _saved_touch_vis := true
var _saved_heli_vis := false
var _dialog := false  # "Save changes?" box
var _pending := ""    # what happens after the box: "close" or "hud:N"
var _slider_id := -1  # finger on a slider
var _slider_kind := ""
var _drag_id := -1    # finger dragging a button
var _drag_p0 := Vector2.ZERO
var _drag_moved := false
var _grab := Vector2.ZERO
var _nudge_id := -1   # finger on the arrow pad
var _nudge_dir := Vector2.ZERO
var _nudge_t := 0.0
var _nudge_first := true
var _toast := ""
var _toast_t := 0.0
var _sb := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # the game is paused while the editor is open
	visible = false


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _u() -> float:
	return clampf(_vp().y / 720.0, 0.7, 1.5)


# ---------------------------------------------------------------- open / close

func open_editor() -> void:
	active = true
	visible = true
	collapsed = false
	dirty = false
	_dialog = false
	_pending = ""
	_toast_t = 0.0
	_release_fingers()
	var view: int = touch.VIEW_FOOT
	if main.flying:
		view = touch.VIEW_FLY
	elif main.driving:
		view = touch.VIEW_DRIVE
	elif touch.build_mode:
		view = touch.VIEW_BUILD
	_saved_touch_vis = touch.visible
	touch.visible = true      # the buttons are drawn by touch_controls.gd, also while flying
	if heli_ui != null:
		_saved_heli_vis = heli_ui.visible
		heli_ui.visible = false   # (in the editor the helicopter buttons are drawn by touch_controls.gd too)
	touch.load_preset(int(touch.preset))   # start clean from what is saved
	touch.set_edit(true, view)
	queue_redraw()


func close_editor() -> void:
	active = false
	visible = false
	_release_fingers()
	touch.set_edit(false)
	touch.visible = _saved_touch_vis
	if heli_ui != null:
		heli_ui.visible = _saved_heli_vis
	closed.emit()


func _release_fingers() -> void:
	_slider_id = -1
	_drag_id = -1
	_nudge_id = -1


# ---------------------------------------------------------------- layout of the panel (screen pixels, scaled by u)

func _rects() -> Dictionary:
	var vp := _vp()
	var u := _u()
	var pw := 470.0 * u
	var ph := 314.0 * u
	var px := vp.x / 2.0 - pw / 2.0
	var pad := 12.0 * u
	var g := 4.0 * u
	var d := {}
	d["panel"] = Rect2(px, 0.0, pw, ph)
	var x := px + pad
	var y := pad
	var h := 52.0 * u
	d["exit"] = Rect2(x, y, 84.0 * u, h)
	x += 84.0 * u + g
	d["prev"] = Rect2(x, y, 56.0 * u, h)
	x += 56.0 * u + g
	d["hudname"] = Rect2(x, y, 118.0 * u, h)
	x += 118.0 * u + g
	d["next"] = Rect2(x, y, 56.0 * u, h)
	x += 56.0 * u + g
	d["view"] = Rect2(x, y, 116.0 * u, h)
	y = 72.0 * u
	d["reset"] = Rect2(px + pad, y, 221.0 * u, 46.0 * u)
	d["save"] = Rect2(px + pad + 221.0 * u + g, y, 221.0 * u, 46.0 * u)
	d["line_y"] = 128.0 * u
	d["sl_o"] = Rect2(px + pad, 172.0 * u, 280.0 * u, 56.0 * u)
	d["sl_s"] = Rect2(px + pad, 236.0 * u, 280.0 * u, 56.0 * u)
	var cx := px + 387.0 * u
	var cy := 232.0 * u
	var b := 46.0 * u
	d["up"] = Rect2(cx - b / 2.0, cy - 71.0 * u, b, b)
	d["down"] = Rect2(cx - b / 2.0, cy + 25.0 * u, b, b)
	d["left"] = Rect2(cx - 71.0 * u, cy - b / 2.0, b, b)
	d["right"] = Rect2(cx + 25.0 * u, cy - b / 2.0, b, b)
	d["tab"] = Rect2(vp.x / 2.0 - 44.0 * u, 0.0 if collapsed else ph, 88.0 * u, 30.0 * u)
	# "Save changes?" box
	var dw := 440.0 * u
	var dh := 200.0 * u
	var dx := vp.x / 2.0 - dw / 2.0
	var dy := vp.y / 2.0 - dh / 2.0
	d["dlg"] = Rect2(dx, dy, dw, dh)
	var bw := 128.0 * u
	var bx := dx + (dw - (bw * 3.0 + 10.0 * u * 2.0)) / 2.0
	var by := dy + dh - 66.0 * u
	d["dlg_save"] = Rect2(bx, by, bw, 50.0 * u)
	d["dlg_discard"] = Rect2(bx + bw + 10.0 * u, by, bw, 50.0 * u)
	d["dlg_cancel"] = Rect2(bx + (bw + 10.0 * u) * 2.0, by, bw, 50.0 * u)
	return d


# x range of a slider track (the handle is 14 px wide, so the track keeps 10 px free at both ends)
func _track(rc: Rect2) -> Vector2:
	var u := _u()
	return Vector2(rc.position.x + 10.0 * u, rc.end.x - 10.0 * u)


# ---------------------------------------------------------------- touches

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_press(e.index, e.position)
		else:
			_release(e.index)
		get_viewport().set_input_as_handled()   # while the editor is open, no other part of the game gets a touch
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position)
		get_viewport().set_input_as_handled()


func _press(idx: int, p: Vector2) -> void:
	var r := _rects()
	if _dialog:
		_press_dialog(p, r)
		return
	var u := _u()
	if (r["tab"] as Rect2).grow(8.0 * u).has_point(p):
		collapsed = not collapsed
		return
	if not collapsed and (r["panel"] as Rect2).has_point(p):
		_press_panel(idx, p, r)
		return
	var id: String = touch.button_at(p)   # a button of the game HUD: select it, drag moves it
	if id != "":
		touch.sel = id
		_drag_id = idx
		_drag_p0 = p
		_drag_moved = false
		_grab = touch.center_px(id) - p


func _press_panel(idx: int, p: Vector2, r: Dictionary) -> void:
	if (r["exit"] as Rect2).has_point(p):
		_request("close")
	elif (r["prev"] as Rect2).has_point(p):
		_request("hud:%d" % _wrap_preset(int(touch.preset) - 1))
	elif (r["next"] as Rect2).has_point(p):
		_request("hud:%d" % _wrap_preset(int(touch.preset) + 1))
	elif (r["view"] as Rect2).has_point(p):
		touch.set_view((int(touch.edit_view) + 1) % VIEW_NAMES.size())
	elif (r["reset"] as Rect2).has_point(p):
		touch.reset_layout()
		dirty = true
		_say("Reset - tap Save to keep it")
	elif (r["save"] as Rect2).has_point(p):
		if dirty:
			_save()
	elif (r["sl_o"] as Rect2).has_point(p):
		_slider_id = idx
		_slider_kind = "o"
		_set_slider(p.x)
	elif (r["sl_s"] as Rect2).has_point(p):
		_slider_id = idx
		_slider_kind = "s"
		_set_slider(p.x)
	else:
		var dir := Vector2.ZERO
		if (r["up"] as Rect2).has_point(p):
			dir = Vector2.UP
		elif (r["down"] as Rect2).has_point(p):
			dir = Vector2.DOWN
		elif (r["left"] as Rect2).has_point(p):
			dir = Vector2.LEFT
		elif (r["right"] as Rect2).has_point(p):
			dir = Vector2.RIGHT
		if dir != Vector2.ZERO:
			_nudge_id = idx
			_nudge_dir = dir
			_nudge_first = true
			_nudge_t = 0.0   # the first step comes at once (_process), then it repeats while the finger stays down


func _press_dialog(p: Vector2, r: Dictionary) -> void:
	if (r["dlg_save"] as Rect2).has_point(p):
		_save()
		_do(_pending)
	elif (r["dlg_discard"] as Rect2).has_point(p):
		touch.load_preset(int(touch.preset))
		dirty = false
		_do(_pending)
	elif (r["dlg_cancel"] as Rect2).has_point(p):
		_dialog = false


func _release(idx: int) -> void:
	if idx == _slider_id:
		_slider_id = -1
	if idx == _drag_id:
		_drag_id = -1
	if idx == _nudge_id:
		_nudge_id = -1


func _drag(idx: int, p: Vector2) -> void:
	if _dialog:
		return
	if idx == _slider_id:
		_set_slider(p.x)
	elif idx == _drag_id:
		if not _drag_moved and p.distance_to(_drag_p0) < 8.0 * _u():
			return   # a tap is not a move
		_drag_moved = true
		var id: String = touch.sel
		var before: Vector2 = touch.center_px(id)
		touch.set_center_px(id, p + _grab)
		if before.distance_to(touch.center_px(id)) > 0.01:
			dirty = true


# ---------------------------------------------------------------- actions

func _wrap_preset(n: int) -> int:
	var total: int = touch.PRESETS
	return (n - 1 + total) % total + 1


func _say(t: String) -> void:
	_toast = t
	_toast_t = 1.8


func _save() -> void:
	touch.save_preset(int(touch.preset))
	dirty = false
	_say("Saved HUD %d" % int(touch.preset))


# EXIT or another HUD was tapped: when something is not saved, ask first
func _request(action: String) -> void:
	if dirty:
		_dialog = true
		_pending = action
	else:
		_do(action)


func _do(action: String) -> void:
	_dialog = false
	if action == "close":
		close_editor()
	elif action.begins_with("hud:"):
		var n: int = int(action.substr(4))
		touch.load_preset(n)
		touch.set_active_preset(n)
		dirty = false
		_say("HUD %d" % n)


func _set_slider(x: float) -> void:
	var r := _rects()
	var rc: Rect2 = r["sl_o"] if _slider_kind == "o" else r["sl_s"]
	var trk := _track(rc)
	var t := clampf((x - trk.x) / maxf(trk.y - trk.x, 1.0), 0.0, 1.0)
	var id: String = touch.sel
	if _slider_kind == "o":
		var before: float = touch.btn_opacity(id)
		touch.set_btn_opacity(id, lerpf(float(touch.OPACITY_MIN), 1.0, t))
		if absf(before - float(touch.btn_opacity(id))) > 0.0005:
			dirty = true
	else:
		var before_s: float = touch.btn_scale(id)
		touch.set_btn_scale(id, lerpf(float(touch.SCALE_MIN), float(touch.SCALE_MAX), t))
		if absf(before_s - float(touch.btn_scale(id))) > 0.0005:
			dirty = true


func _process(delta: float) -> void:
	if not active:
		return
	_toast_t = maxf(0.0, _toast_t - delta)
	if _nudge_id != -1 and not _dialog:
		_nudge_t -= delta
		if _nudge_t <= 0.0:
			var id: String = touch.sel
			var before: Vector2 = touch.center_px(id)
			touch.nudge(id, _nudge_dir.x * NUDGE_STEP, _nudge_dir.y * NUDGE_STEP)
			if before.distance_to(touch.center_px(id)) > 0.01:
				dirty = true
			_nudge_t = 0.4 if _nudge_first else 0.035   # wait a little before the key repeats
			_nudge_first = false
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _box(rc: Rect2, bg: Color, border: Color = Color(0, 0, 0, 0), radius: float = 8.0, bw: int = 0) -> void:
	_sb.bg_color = bg
	_sb.border_color = border
	_sb.set_border_width_all(bw)
	_sb.set_corner_radius_all(int(radius))
	draw_style_box(_sb, rc)


# light grey panel button (like the reference picture); enabled = false -> dark grey
func _light(rc: Rect2, enabled: bool = true, down: bool = false) -> void:
	var u := _u()
	var bg := Color(0.92, 0.93, 0.94)
	if not enabled:
		bg = Color(0.27, 0.3, 0.33)
	elif down:
		bg = Color(0.68, 0.7, 0.74)
	_box(rc, bg, Color(0, 0, 0, 0.35), 3.0 * u, 1)


func _ct(rc: Rect2, s: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(rc.position.x, rc.get_center().y + float(size) * 0.35), s, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x, size, col)


# triangle pointing along dir (a unit axis vector), k = size
func _tri(c: Vector2, k: float, dir: Vector2, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([c + dir * k, c - dir * k * 0.7 + n * k * 0.85, c - dir * k * 0.7 - n * k * 0.85]), col)


func _icon_exit(rc: Rect2, col: Color) -> void:
	var c := rc.get_center()
	var k := rc.size.y * 0.36
	var w := maxf(2.5, k * 0.16)
	draw_polyline(PackedVector2Array([c + Vector2(-0.05, -1.0) * k, c + Vector2(-0.9, -1.0) * k, c + Vector2(-0.9, 1.0) * k, c + Vector2(-0.05, 1.0) * k]), col, w)
	draw_line(c + Vector2(-0.35, 0.0) * k, c + Vector2(0.9, 0.0) * k, col, w)
	_tri(c + Vector2(0.75, 0.0) * k, k * 0.4, Vector2.RIGHT, col)


func _icon_reset(rc: Rect2, col: Color) -> void:
	var c := rc.get_center()
	var k := rc.size.y * 0.3
	draw_arc(c, k, deg_to_rad(-60.0), deg_to_rad(235.0), 28, col, maxf(2.5, k * 0.22))
	var a := deg_to_rad(235.0)
	var tip := c + Vector2(cos(a), sin(a)) * k
	_tri(tip, k * 0.5, Vector2(-sin(a), cos(a)), col)


func _icon_save(rc: Rect2, col: Color, bg: Color) -> void:
	var c := rc.get_center()
	var k := rc.size.y * 0.34
	draw_rect(Rect2(c.x - k, c.y - k, k * 2.0, k * 2.0), col)
	draw_rect(Rect2(c.x - k * 0.55, c.y - k, k * 1.1, k * 0.7), bg)
	draw_rect(Rect2(c.x - k * 0.6, c.y + k * 0.15, k * 1.2, k * 0.85), bg)
	draw_rect(Rect2(c.x + k * 0.15, c.y - k * 0.85, k * 0.25, k * 0.45), col)


func _draw_slider(rc: Rect2, label: String, t: float, value_text: String) -> void:
	var u := _u()
	var f := ThemeDB.fallback_font
	var fs := int(24.0 * u)
	draw_string(f, Vector2(rc.position.x, rc.position.y + 22.0 * u), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	draw_string(f, Vector2(rc.position.x, rc.position.y + 22.0 * u), value_text, HORIZONTAL_ALIGNMENT_RIGHT, rc.size.x, fs, Color(1, 1, 1, 0.95))
	var trk := _track(rc)
	var cy := rc.position.y + 42.0 * u
	var th := 7.0 * u
	draw_rect(Rect2(trk.x, cy - th / 2.0, trk.y - trk.x, th), Color(0.03, 0.04, 0.05))
	var hx := trk.x + (trk.y - trk.x) * t
	draw_rect(Rect2(trk.x, cy - th / 2.0, hx - trk.x, th), Color(1.0, 0.67, 0.1))
	var hw := 14.0 * u
	var hh := 26.0 * u
	draw_rect(Rect2(hx - hw / 2.0, cy - hh / 2.0, hw, hh), Color(0.95, 0.95, 0.95))
	draw_rect(Rect2(hx - hw / 2.0, cy - hh / 2.0, hw, hh), Color(0, 0, 0, 0.6), false, 1.5)
	for i in 3:
		var ly := cy - 6.0 * u + float(i) * 6.0 * u
		draw_line(Vector2(hx - hw * 0.28, ly), Vector2(hx + hw * 0.28, ly), Color(0.2, 0.2, 0.2), 1.5)


func _draw() -> void:
	if not active:
		return
	var vp := _vp()
	var u := _u()
	var r := _rects()
	var f := ThemeDB.fallback_font
	var dark := Color(0.08, 0.09, 0.1)
	var panel_bg := Color(0.12, 0.16, 0.19, 0.97)
	var id: String = touch.sel

	if not collapsed:
		var panel: Rect2 = r["panel"]
		_box(panel, panel_bg, Color(0.3, 0.36, 0.4), 10.0 * u, 2)
		# row 1: EXIT  <  HUD n  >  VIEW
		_light(r["exit"])
		_icon_exit(r["exit"], dark)
		_light(r["prev"])
		_tri((r["prev"] as Rect2).get_center(), 14.0 * u, Vector2.LEFT, dark)
		_box(r["hudname"], Color(0.02, 0.03, 0.04), Color(0.3, 0.36, 0.4), 3.0 * u, 1)
		_ct(r["hudname"], "HUD %d" % int(touch.preset), int(28.0 * u), Color.WHITE)
		_light(r["next"])
		_tri((r["next"] as Rect2).get_center(), 14.0 * u, Vector2.RIGHT, dark)
		_light(r["view"])
		_ct(r["view"], String(VIEW_NAMES[int(touch.edit_view)]), int(24.0 * u), dark)
		# row 2: RESET  SAVE (dark grey = nothing to save)
		_light(r["reset"])
		_icon_reset(r["reset"], dark)
		_light(r["save"], dirty)
		_icon_save(r["save"], dark if dirty else Color(0.5, 0.53, 0.56), Color(0.92, 0.93, 0.94) if dirty else Color(0.27, 0.3, 0.33))
		draw_line(Vector2(panel.position.x + 12.0 * u, float(r["line_y"])), Vector2(panel.end.x - 12.0 * u, float(r["line_y"])), Color(1, 1, 1, 0.18), 1.5)
		# selected button
		draw_string(f, Vector2(panel.position.x + 12.0 * u, 156.0 * u), "Adjust:  %s" % String(NAMES.get(id, id)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(24.0 * u), Color(1.0, 0.9, 0.4))
		# sliders
		var o: float = touch.btn_opacity(id)
		var omin: float = touch.OPACITY_MIN
		_draw_slider(r["sl_o"], "Opacity", (o - omin) / (1.0 - omin), "%d%%" % int(round(o * 100.0)))
		var sc: float = touch.btn_scale(id)
		var smin: float = touch.SCALE_MIN
		var smax: float = touch.SCALE_MAX
		_draw_slider(r["sl_s"], "Size", (sc - smin) / (smax - smin), "%d%%" % int(round(sc * 100.0)))
		# arrow pad
		var dirs := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
		for k in dirs:
			var held: bool = _nudge_id != -1 and _nudge_dir == dirs[k]
			_light(r[k], true, held)
			_tri((r[k] as Rect2).get_center(), 12.0 * u, dirs[k], dark)

	# the tab under the panel (or at the top edge when the panel is hidden)
	var tab: Rect2 = r["tab"]
	_box(tab, panel_bg, Color(0.3, 0.36, 0.4), 6.0 * u, 1)
	var tc := tab.get_center()
	var cv := 7.0 * u
	var sgn := 1.0 if collapsed else -1.0   # open panel: "^" (tap = hide), hidden panel: "v" (tap = show)
	draw_polyline(PackedVector2Array([tc + Vector2(-cv * 1.6, -cv * 0.5 * sgn), tc + Vector2(0, cv * 0.5 * sgn), tc + Vector2(cv * 1.6, -cv * 0.5 * sgn)]), Color(1, 1, 1, 0.9), 3.0)
	# hint + message at the bottom
	var hint := "Drag a button to move it.  Tap the arrow tab to hide the panel."
	draw_string_outline(f, Vector2(0, vp.y - 24.0 * u), hint, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(22.0 * u), 6, Color(0, 0, 0, 0.9))
	draw_string(f, Vector2(0, vp.y - 24.0 * u), hint, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(22.0 * u), Color(1, 1, 1, 0.85))
	if _toast_t > 0.0:
		var ty := tab.end.y + 40.0 * u
		var ta := minf(_toast_t * 2.0, 1.0)
		draw_string_outline(f, Vector2(0, ty), _toast, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(28.0 * u), 6, Color(0, 0, 0, 0.9 * ta))
		draw_string(f, Vector2(0, ty), _toast, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(28.0 * u), Color(1.0, 0.92, 0.5, ta))

	if _dialog:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
		var dl: Rect2 = r["dlg"]
		_box(dl, Color(0.12, 0.16, 0.19, 1.0), Color(0.5, 0.58, 0.63), 12.0 * u, 2)
		draw_string(f, Vector2(dl.position.x, dl.position.y + 62.0 * u), "Save changes?", HORIZONTAL_ALIGNMENT_CENTER, dl.size.x, int(34.0 * u), Color.WHITE)
		draw_string(f, Vector2(dl.position.x, dl.position.y + 96.0 * u), "HUD %d is not saved" % int(touch.preset), HORIZONTAL_ALIGNMENT_CENTER, dl.size.x, int(22.0 * u), Color(1, 1, 1, 0.7))
		_box(r["dlg_save"], Color(0.2, 0.6, 0.25), Color(1, 1, 1, 0.5), 8.0 * u, 1)
		_ct(r["dlg_save"], "Save", int(24.0 * u), Color.WHITE)
		_box(r["dlg_discard"], Color(0.7, 0.25, 0.2), Color(1, 1, 1, 0.5), 8.0 * u, 1)
		_ct(r["dlg_discard"], "Discard", int(24.0 * u), Color.WHITE)
		_box(r["dlg_cancel"], Color(0.35, 0.38, 0.42), Color(1, 1, 1, 0.5), 8.0 * u, 1)
		_ct(r["dlg_cancel"], "Cancel", int(24.0 * u), Color.WHITE)
