extends Control
# Phone controls.
# On foot: joystick (left), drag right side = look, JUMP, RUN, GET IN (near tractor).
# Driving: GAS, BRAKE, < and >, ATTACH/DETACH, GET IN/OUT. Drag anywhere else = look around.
# Driving also shows the BOTTOM BAR: HORN (hold) and WORK (press = machine starts, press again = stops).
# WORK only appears while a machine is hooked on.
# v_015: the old three-line menu button and the old edit mode are gone. The gear button (settings_menu.gd) opens
# the HUD editor (hud_editor.gd): every button can be dragged, made bigger / smaller and more / less see-through.
# There are 3 HUD layouts (HUD 1 / 2 / 3), saved on the phone (user://hud_layout.cfg). This script only keeps the
# layout data (btn) and draws / reads the buttons; the editor changes the data through the functions below.

signal look_dragged(dx: float, dy: float)
signal jump_pressed
signal run_pressed
signal action_pressed
signal hitch_pressed
signal work_pressed
signal map_pressed
signal poi_pressed
signal seed_pressed
signal reload_pressed
signal swap_pressed
signal gun_slot_pressed(slot: int)   # v_016: tap on a gun slot box (0, 1) or on the HANDS box (-1)
signal bag_pressed
signal sleep_pressed   # v_026: SLEEP button (lie down / get up)
signal mode_pressed
signal slot_pressed(slot: int)   # v_009: tap on a hotbar picture (1..hotbar_n)

const STICK_R := 100.0
const LOOK_HOLD := ["fire", "jump", "place", "break"]   # a finger on these buttons can still drag to look / aim
const CFG := "user://hud_layout.cfg"
const SHOOT_IDS := ["fire", "reload", "swap", "guns"]    # shown in SHOOT mode
const BOX_IDS := ["guns"]   # v_016: ONE group of 3 boxes (gun 1, gun 2, empty hands): moves / resizes / fades as one piece
const GUN_BOXES := ["gun1", "gun2", "hands"]   # the boxes inside the group, left to right
const BAR_IDS := ["hp", "hunger"]   # v_017: the health bar (drawn by combat_hud.gd) is a HUD piece too: the editor moves / resizes / fades it. Not a button.
const BOX_GAP := 0.14   # gap between the boxes (x box size)
const BIG_H := 1.5      # height of the big ammo box on top of the 3 small boxes (x r)
const BUILD_IDS := ["place", "break"]    # shown in BUILD mode
const PRESETS := 3                       # v_015: HUD 1 / 2 / 3
const SCALE_MIN := 0.5                   # v_015: size 50 % ... 200 %
const SCALE_MAX := 2.0
const OPACITY_MIN := 0.1                 # v_015: 10 % ... 100 % (never fully invisible)
const VIEW_FOOT := 0                     # v_015: which buttons the editor shows
const VIEW_BUILD := 1
const VIEW_DRIVE := 2
const VIEW_FLY := 3

# pos = screen position as a fraction (0..1) so it fits any phone; scale = size multiplier; opacity = 0.1 .. 1.0 (added in _ready)
# mode: foot / drive / both / fly      hold: true = active while the finger stays down
# "fly" = the helicopter buttons (drawn by heli_ui.gd while flying, they live here so the editor can move them too)
var btn := {
	"jump": {"pos": Vector2(0.883, 0.764), "scale": 1.0, "r": 85.0, "text": "JUMP", "mode": "foot", "hold": false},
	"run": {"pos": Vector2(0.742, 0.847), "scale": 1.0, "r": 65.0, "text": "RUN", "mode": "foot", "hold": false},
	"action": {"pos": Vector2(0.88, 0.45), "scale": 1.0, "r": 65.0, "text": "IN/OUT", "mode": "both", "hold": false},
	"gas": {"pos": Vector2(0.90, 0.74), "scale": 1.0, "r": 90.0, "text": "GAS", "mode": "drive", "hold": true},
	"brake": {"pos": Vector2(0.75, 0.85), "scale": 1.0, "r": 70.0, "text": "BRAKE", "mode": "drive", "hold": true},
	"left": {"pos": Vector2(0.10, 0.80), "scale": 1.0, "r": 70.0, "text": "<", "mode": "drive", "hold": true},
	"right": {"pos": Vector2(0.25, 0.80), "scale": 1.0, "r": 70.0, "text": ">", "mode": "drive", "hold": true},
	"hitch": {"pos": Vector2(0.74, 0.62), "scale": 1.0, "r": 60.0, "text": "ATTACH", "mode": "drive", "hold": false},
	"poi": {"pos": Vector2(0.88, 0.27), "scale": 1.0, "r": 62.0, "text": "SHOP", "mode": "both", "hold": false},
	"fire": {"pos": Vector2(0.745, 0.60), "scale": 1.0, "r": 78.0, "text": "FIRE", "mode": "foot", "hold": true},
	"reload": {"pos": Vector2(0.62, 0.78), "scale": 1.0, "r": 52.0, "text": "RELOAD", "mode": "foot", "hold": false},
	"bag": {"pos": Vector2(0.78, 0.12), "scale": 1.0, "r": 46.0, "text": "BAG", "mode": "foot", "hold": false},
	"sleep": {"pos": Vector2(0.88, 0.27), "scale": 1.0, "r": 52.0, "text": "SLEEP", "mode": "foot", "hold": false},
	"swap": {"pos": Vector2(0.62, 0.60), "scale": 1.0, "r": 48.0, "text": "SWAP", "mode": "foot", "hold": false},
	"guns": {"pos": Vector2(0.50, 0.185), "scale": 1.0, "r": 46.0, "text": "", "mode": "foot", "hold": false},
	"hp": {"pos": Vector2(0.136, 0.065), "scale": 1.0, "r": 24.0, "text": "", "mode": "both", "hold": false},
	"hunger": {"pos": Vector2(0.1164, 0.105), "scale": 1.0, "r": 20.0, "text": "", "mode": "both", "hold": false},
	"mode": {"pos": Vector2(0.62, 0.42), "scale": 1.0, "r": 50.0, "text": "BUILD", "mode": "foot", "hold": false},
	"place": {"pos": Vector2(0.745, 0.60), "scale": 1.0, "r": 78.0, "text": "PLACE", "mode": "foot", "hold": true},
	"break": {"pos": Vector2(0.62, 0.78), "scale": 1.0, "r": 58.0, "text": "BREAK", "mode": "foot", "hold": true},
	"alt_up": {"pos": Vector2(0.898, 0.583), "scale": 1.0, "r": 62.0, "text": "UP", "mode": "fly", "hold": true},
	"alt_dn": {"pos": Vector2(0.898, 0.792), "scale": 1.0, "r": 62.0, "text": "DOWN", "mode": "fly", "hold": true},
	"exit": {"pos": Vector2(0.87, 0.22), "scale": 1.0, "r": 62.0, "text": "GET OUT", "mode": "fly", "hold": false},
}
var defaults := {}
var preset := 1               # v_015: the HUD layout in use (1..PRESETS)
var sleep_text := "SLEEP"   # main.gd / player: "WAKE" while the character sleeps
var hidden_ids: Array = []   # button ids that are never shown (main.gd hides the ones the game does not use)
var held := {"gas": false, "brake": false, "left": false, "right": false, "horn": false, "fire": false}
var hold_touch := {}      # finger index -> button id
var move_dir := Vector2.ZERO
var run_on := false
var drive_mode := false
var action_visible := false
var action_enabled := false
var action_text := "IN/OUT"
var hitch_text := "ATTACH"
var hitch_enabled := false
var work_available := false   # a machine is hooked on -> the WORK button shows in the bottom bar
var work_on := false          # machine is working right now
var seed_available := false   # seeder hooked on -> SEED button next to the horn
var poi_visible := false      # a shop / warehouse / fertilizer point is near -> button shows
var poi_text := "SHOP"
var swap_text := "SWAP"
var slot_view := {}   # v_016: what the gun boxes show: id -> {"name": String, "icon": Texture2D, "filled": bool, "active": bool} (main.gd fills it)
var next_text := "NEXT"   # (not shown any more, build.gd warm-up still sets it)
const HOTBAR_VIS := 6      # v_021: at most this many block buttons at once; more blocks = swipe the bar (or tap the arrows)
var hotbar_first := 0      # v_021: index of the first visible button (scroll)
var hb_touch := -1         # v_021: finger on the bar
var hb_start := Vector2.ZERO
var hb_start_first := 0
var hb_slot := -1
var hb_moved := false
var hotbar_n := 10           # v_009: number of block pictures in the bottom bar (main.gd sets it)
var build_mode := false       # BUILD button: true = place / break blocks, false = shoot
var fire_off := Vector2.ZERO      # FIRE button slides with the finger (like a joystick) and springs back
var fire_target := Vector2.ZERO
var blocked := false          # a pop-up screen is open: ignore touches
var map_rect := Rect2(20, 20, 220, 220)   # tap here = big map
var edit := false             # v_015: the HUD editor is open (hud_editor.gd sets this): all touches belong to the editor
var edit_view := VIEW_FOOT
var sel := "fire"             # the button that is selected in the editor
var _op := 1.0                # opacity of the button that is being drawn right now (see _a())
var stick_id := -1
var look_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the game is paused (HUD editor is open)
	for id in btn:
		btn[id]["opacity"] = 1.0
	defaults = btn.duplicate(true)
	preset = _load_active_preset()
	load_preset(preset)
	get_viewport().size_changed.connect(fit_all)   # v_018: turning the phone / a different screen size


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _center(id: String) -> Vector2:
	return Vector2(btn[id]["pos"]) * _vp()


func _rad(id: String) -> float:
	return float(btn[id]["r"]) * float(btn[id]["scale"])


# half size of the box group: the big ammo box on top, under it 3 small boxes of 2 * r (gaps between).
# For the health bar: a long thin bar (size follows the screen height like the other HUD parts).
func _box_half(id: String) -> Vector2:
	var h := _rad(id)
	if BAR_IDS.has(id):
		var u := clampf(_vp().y / 720.0, 0.7, 1.5)
		return Vector2(h * 6.25 * u, h * 0.46 * u)
	return Vector2(h * (3.0 + BOX_GAP * 2.0), h * (BIG_H + 2.0 + BOX_GAP * 2.0) / 2.0)


# the rectangle of the health bar on the screen (combat_hud.gd draws the bar there)
func bar_rect(id: String) -> Rect2:
	var hh := _box_half(id)
	return Rect2(_center(id) - hh, hh * 2.0)


# the rectangles of the group (screen pixels): "main" = big ammo box, and the 3 small boxes
func _group_rects(id: String) -> Dictionary:
	var h := _rad(id)
	var c := _center(id)
	var hh := _box_half(id)
	var d := {}
	var top := c.y - hh.y
	d["main"] = Rect2(c.x - hh.x, top, hh.x * 2.0, h * BIG_H)
	var row_c := c.y + hh.y - h
	for k in 3:
		d[GUN_BOXES[k]] = Rect2(c.x + (k - 1) * h * (2.0 + BOX_GAP * 2.0) - h, row_c - h, h * 2.0, h * 2.0)
	return d


# distance of a point from the button: round buttons = distance to the centre. Box group = how far outside the group
# rectangle the point is, + the radius (so the same "< radius + margin" test as for round buttons works)
func _dist(id: String, p: Vector2) -> float:
	var d := p - _center(id)
	if BOX_IDS.has(id) or BAR_IDS.has(id):
		var hh := _box_half(id)
		return maxf(absf(d.x) - hh.x, absf(d.y) - hh.y) + _rad(id)
	return d.length()


# is this button shown right now?
func _vis(id: String) -> bool:
	if hidden_ids.has(id):
		return false
	var m: String = btn[id]["mode"]
	if edit:   # the editor shows the buttons of the view that is chosen there (FOOT / BUILD / DRIVE / FLY)
		match edit_view:
			VIEW_FOOT:
				return (m == "foot" or m == "both") and not BUILD_IDS.has(id)
			VIEW_BUILD:
				return (m == "foot" or m == "both") and not SHOOT_IDS.has(id)
			VIEW_DRIVE:
				return m == "drive" or m == "both"
			VIEW_FLY:
				return m == "fly"
		return false
	if m == "fly":   # helicopter buttons are drawn by heli_ui.gd
		return false
	if BUILD_IDS.has(id) and not build_mode:
		return false
	if SHOOT_IDS.has(id) and build_mode:
		return false
	if id == "action" and not action_visible:
		return false
	if id == "poi" and not poi_visible:
		return false
	return m == "both" or ((m == "drive") == drive_mode)


func release_all() -> void:
	stick_id = -1
	look_id = -1
	move_dir = Vector2.ZERO
	hold_touch.clear()
	hb_touch = -1
	fire_target = Vector2.ZERO
	for k in held:
		held[k] = false


# ---------------------------------------------------------------- v_015: layout data (HUD 1 / 2 / 3)
# Saved file user://hud_layout.cfg:  [meta] preset = the HUD in use   [hud1] [hud2] [hud3] <id>_x / _y / _s (size) / _o (opacity)
# A HUD that was never saved uses the default layout (the numbers in btn above).

const VIEW_FIRST := ["fire", "place", "gas", "alt_up"]   # button that is selected first in each editor view


func _load_active_preset() -> int:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return 1
	return clampi(int(cf.get_value("meta", "preset", 1)), 1, PRESETS)


const EDGE := 4.0   # v_018: a HUD piece always stays fully on the screen, this many pixels from the edge


# v_018: the position (fraction of the screen) that keeps the WHOLE piece (button, box group, health bar) on the screen.
# half = half size of the piece in pixels, so a big piece stops earlier at the edge than a small one.
func _clamp_pos(p: Vector2, half: Vector2 = Vector2.ZERO) -> Vector2:
	var vp := _vp()
	if vp.x < 1.0 or vp.y < 1.0:
		return p
	var lo := Vector2(half.x + EDGE, half.y + EDGE)
	var hi := vp - lo
	var px := p * vp
	px.x = clampf(px.x, lo.x, hi.x) if lo.x <= hi.x else vp.x / 2.0
	px.y = clampf(px.y, lo.y, hi.y) if lo.y <= hi.y else vp.y / 2.0
	return px / vp


# half size (pixels) of any HUD piece: round button = radius, box group / health bar = their rectangle
func _half_of(id: String) -> Vector2:
	if BOX_IDS.has(id) or BAR_IDS.has(id):
		return _box_half(id)
	return Vector2(_rad(id), _rad(id))


# puts piece id back on the screen (after a size change, after loading a layout, or when the screen size changes)
func fit(id: String) -> void:
	btn[id]["pos"] = _clamp_pos(btn[id]["pos"], _half_of(id))


func fit_all() -> void:
	for id in btn:
		fit(id)


# puts the saved layout of HUD n into btn (what was never saved = the default layout)
func load_preset(n: int) -> void:
	preset = clampi(n, 1, PRESETS)
	var cf := ConfigFile.new()
	var have_file: bool = cf.load(CFG) == OK
	var sec := "hud%d" % preset
	for id in btn:
		var d: Dictionary = defaults[id]
		var dp: Vector2 = d["pos"]
		var px: float = dp.x
		var py: float = dp.y
		var sc: float = float(d["scale"])
		var op: float = float(d["opacity"])
		if have_file and cf.has_section_key(sec, id + "_x"):
			px = float(cf.get_value(sec, id + "_x", px))
			py = float(cf.get_value(sec, id + "_y", py))
			sc = float(cf.get_value(sec, id + "_s", sc))
			op = float(cf.get_value(sec, id + "_o", op))
		btn[id]["pos"] = Vector2(px, py)
		btn[id]["scale"] = clampf(sc, SCALE_MIN, SCALE_MAX)
		btn[id]["opacity"] = clampf(op, OPACITY_MIN, 1.0)
		fit(id)   # v_018: the size is set now, so the whole piece is kept on the screen


# writes the layout that is on the screen now into HUD n (the other HUDs stay as they are) and makes it the HUD in use
func save_preset(n: int) -> void:
	n = clampi(n, 1, PRESETS)
	var cf := ConfigFile.new()
	cf.load(CFG)
	var sec := "hud%d" % n
	for id in btn:
		var p: Vector2 = btn[id]["pos"]
		cf.set_value(sec, id + "_x", p.x)
		cf.set_value(sec, id + "_y", p.y)
		cf.set_value(sec, id + "_s", float(btn[id]["scale"]))
		cf.set_value(sec, id + "_o", float(btn[id]["opacity"]))
	cf.set_value("meta", "preset", n)
	cf.save(CFG)
	preset = n


# only remembers which HUD is in use (used at the next start too)
func set_active_preset(n: int) -> void:
	preset = clampi(n, 1, PRESETS)
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("meta", "preset", preset)
	cf.save(CFG)


# back to the default layout (not saved until the editor saves it)
func reset_layout() -> void:
	for id in btn:
		btn[id]["pos"] = defaults[id]["pos"]
		btn[id]["scale"] = defaults[id]["scale"]
		btn[id]["opacity"] = defaults[id]["opacity"]
	fit_all()


# ---------------------------------------------------------------- v_015: functions for the HUD editor (hud_editor.gd)

func set_edit(on: bool, view: int = VIEW_FOOT) -> void:
	edit = on
	release_all()
	if on:
		set_view(view)


func set_view(v: int) -> void:
	edit_view = clampi(v, VIEW_FOOT, VIEW_FLY)
	sel = String(VIEW_FIRST[edit_view])


# the button under a finger (the nearest centre wins when buttons overlap), "" = none
func button_at(p: Vector2) -> String:
	var best := ""
	var bd := 1.0e9
	for id in btn:
		if not _vis(id):
			continue
		var dist: float = _dist(id, p)
		if dist < _rad(id) + 10.0 and dist < bd:
			bd = dist
			best = id
	return best


func center_px(id: String) -> Vector2:
	return _center(id)


func set_center_px(id: String, c: Vector2) -> void:
	btn[id]["pos"] = _clamp_pos(c / _vp(), _half_of(id))


func nudge(id: String, dx: float, dy: float) -> void:
	set_center_px(id, _center(id) + Vector2(dx, dy))


func btn_scale(id: String) -> float:
	return float(btn[id]["scale"])


func set_btn_scale(id: String, s: float) -> void:
	btn[id]["scale"] = clampf(s, SCALE_MIN, SCALE_MAX)
	fit(id)   # v_018: a bigger piece next to the edge is pushed back in


func btn_opacity(id: String) -> float:
	return float(btn[id]["opacity"])


func set_btn_opacity(id: String, o: float) -> void:
	btn[id]["opacity"] = clampf(o, OPACITY_MIN, 1.0)


# opacity of the button that is drawn right now (alpha of a colour x opacity)
func _a(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * _op)


func _process(delta: float) -> void:
	var tgt := fire_target if held.get("fire", false) else Vector2.ZERO
	fire_off = fire_off.lerp(tgt, minf(1.0, 22.0 * delta))
	queue_redraw()


func _circle_btn(c: Vector2, r: float, text: String, col: Color, fs: int = 24) -> void:
	# v_009: glass look: see-through tinted disc, bright rim, small shine on top. (col.a >= 0.93 = pressed / active = a bit stronger)
	var a := (0.5 if col.a >= 0.93 else 0.28) * _op   # v_015: x the opacity chosen in the HUD editor
	draw_circle(c, r, Color(col.r, col.g, col.b, a))
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(1, 1, 1, 0.55 * _op), 2.5)
	draw_arc(c, r * 0.8, PI * 1.12, PI * 1.62, 16, Color(1, 1, 1, 0.35 * _op), maxf(2.0, r * 0.07))
	if text != "":
		var f := ThemeDB.fallback_font
		var tp := c + Vector2(-r, fs * 0.35)
		draw_string_outline(f, tp, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 4, Color(0, 0, 0, 0.55 * _op))
		draw_string(f, tp, text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, _op))


# v_009: hammer icon (BUILD button)
func _icon_hammer(c: Vector2, r: float) -> void:
	draw_set_transform(c, PI / 4.0, Vector2.ONE * (r / 58.0))
	draw_rect(Rect2(-5, -14, 10, 56), _a(Color(0.85, 0.65, 0.4, 0.95)))
	draw_rect(Rect2(-5, -14, 10, 56), _a(Color(0, 0, 0, 0.5)), false, 2.0)
	draw_rect(Rect2(-24, -36, 48, 24), _a(Color(0.92, 0.94, 0.97, 0.97)))
	draw_rect(Rect2(-24, -36, 48, 24), _a(Color(0, 0, 0, 0.5)), false, 2.0)
	draw_rect(Rect2(-24, -36, 10, 24), _a(Color(0.6, 0.65, 0.75, 0.9)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# v_009: hammer hitting a cracked block (BREAK button)
func _icon_break(c: Vector2, r: float) -> void:
	var k := r / 58.0
	var b := c + Vector2(-8, 12) * k
	var sz := 34.0 * k
	draw_rect(Rect2(b - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), _a(Color(0.85, 0.85, 0.9, 0.35)))
	draw_rect(Rect2(b - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), _a(Color(1, 1, 1, 0.9)), false, 2.5)
	var cr := PackedVector2Array([b + Vector2(2, -17) * k, b + Vector2(-4, -6) * k, b + Vector2(5, 0) * k, b + Vector2(-3, 8) * k, b + Vector2(3, 17) * k])
	draw_polyline(cr, _a(Color(1, 1, 1, 0.95)), 2.5)
	draw_rect(Rect2(b + Vector2(20, 16) * k, Vector2(6, 6) * k), _a(Color(1, 1, 1, 0.8)))
	draw_rect(Rect2(b + Vector2(-30, 20) * k, Vector2(5, 5) * k), _a(Color(1, 1, 1, 0.8)))
	for d in [Vector2(-1, -0.2), Vector2(-0.6, -0.9)]:
		draw_line(b + Vector2(-2, -6) * k + d * 22.0 * k, b + Vector2(-2, -6) * k + d * 32.0 * k, _a(Color(1.0, 0.9, 0.3, 0.9)), 2.5)
	draw_set_transform(c + Vector2(14, -16) * k, PI / 4.0, Vector2.ONE * (r / 58.0) * 0.7)
	draw_rect(Rect2(-5, -14, 10, 56), _a(Color(0.85, 0.65, 0.4, 0.95)))
	draw_rect(Rect2(-24, -36, 48, 24), _a(Color(0.92, 0.94, 0.97, 0.97)))
	draw_rect(Rect2(-24, -36, 48, 24), _a(Color(0, 0, 0, 0.5)), false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# v_009 / v_021: the block-picture bar (bottom center, only in BUILD mode): one button for every block the player owns.
# More than HOTBAR_VIS blocks: swipe the bar left / right (or tap the arrows). hud.gd draws it, _press() reads it.
func _hotbar_layout() -> Dictionary:
	var vp := _vp()
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var gp := 6.0 * u
	var total_n := maxi(hotbar_n, 0)
	var n := mini(total_n, HOTBAR_VIS)
	hotbar_first = clampi(hotbar_first, 0, maxi(total_n - n, 0))
	var ss := minf(58.0 * u, (vp.x * 0.58 - gp * float(maxi(n - 1, 0))) / float(maxi(n, 1)))
	var total := ss * float(n) + gp * float(maxi(n - 1, 0))
	return {"n": n, "ss": ss, "gp": gp, "x0": vp.x / 2.0 - total / 2.0, "y0": vp.y - ss - 20.0 * u, "total": total}


func hotbar_rects() -> Array:
	var L := _hotbar_layout()
	var out: Array = []
	for i in int(L["n"]):
		out.append(Rect2(float(L["x0"]) + float(i) * (float(L["ss"]) + float(L["gp"])), float(L["y0"]), float(L["ss"]), float(L["ss"])))
	return out


# the two scroll arrows (left, right) next to the bar; empty when everything fits
func hotbar_arrow_rects() -> Array:
	if hotbar_n <= HOTBAR_VIS:
		return []
	var L := _hotbar_layout()
	var ss: float = L["ss"]
	var y0: float = L["y0"]
	var x0: float = L["x0"]
	var total: float = L["total"]
	return [Rect2(x0 - ss * 0.75, y0, ss * 0.65, ss), Rect2(x0 + total + ss * 0.10, y0, ss * 0.65, ss)]



# bottom bar: rectangles of the panel and its buttons (screen pixels)
func _bar_rects() -> Dictionary:
	var vp := _vp()
	var u := clampf(vp.y / 720.0, 0.6, 1.6)
	var bs := 100.0 * u
	var gap := 10.0 * u
	var pad := 12.0 * u
	var n := 1 + (1 if work_available else 0) + (1 if seed_available else 0)
	var w := pad * 2.0 + bs * n + gap * (n - 1)
	var h := pad * 2.0 + bs
	var panel := Rect2(vp.x / 2.0 - w / 2.0, vp.y - h - 14.0 * u, w, h)
	var d := {"panel": panel}
	var x := panel.position.x + pad
	if work_available:
		d["work"] = Rect2(x, panel.position.y + pad, bs, bs)
		x += bs + gap
	if seed_available:
		d["seed"] = Rect2(x, panel.position.y + pad, bs, bs)
		x += bs + gap
	d["horn"] = Rect2(x, panel.position.y + pad, bs, bs)
	return d


func _bar_btn(r: Rect2, sb: StyleBoxFlat, active: bool) -> void:
	sb.bg_color = Color(0.1, 0.24, 0.1) if active else Color(0.05, 0.05, 0.05)
	sb.border_color = Color(0.55, 0.9, 0.2) if active else Color(0.3, 0.3, 0.3)
	draw_style_box(sb, r)


func _icon_horn(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	var pts := PackedVector2Array([Vector2(-0.62, -0.12), Vector2(-0.2, -0.12), Vector2(0.4, -0.42), Vector2(0.4, 0.42), Vector2(-0.2, 0.12), Vector2(-0.62, 0.12)])
	for i in pts.size():
		pts[i] = c + pts[i] * k
	draw_colored_polygon(pts, col)
	draw_circle(c + Vector2(-0.72, 0) * k, 0.15 * k, col)
	draw_arc(c + Vector2(0.45, 0) * k, 0.3 * k, deg_to_rad(-45), deg_to_rad(45), 12, col, 0.09 * k)
	draw_arc(c + Vector2(0.45, 0) * k, 0.52 * k, deg_to_rad(-45), deg_to_rad(45), 12, col, 0.09 * k)


func _icon_work(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	var w := 0.13 * k
	draw_polyline(PackedVector2Array([c + Vector2(-0.6, -0.4) * k, c + Vector2(-0.35, -0.15) * k, c + Vector2(0.15, -0.8) * k]), col, w)
	draw_line(c + Vector2(-0.55, 0.8) * k, c + Vector2(0.25, 0.0) * k, col, 0.22 * k)
	draw_arc(c + Vector2(0.4, -0.15) * k, 0.26 * k, deg_to_rad(15), deg_to_rad(305), 18, col, 0.13 * k)


func _icon_seed(r: Rect2, col: Color) -> void:
	var k := r.size.x * 0.4
	var c := r.get_center()
	draw_circle(c + Vector2(-0.45, 0.35) * k, 0.26 * k, col)
	draw_circle(c + Vector2(0.45, 0.35) * k, 0.26 * k, col)
	draw_circle(c + Vector2(0.0, -0.4) * k, 0.26 * k, col)
	draw_line(c + Vector2(0.0, -0.1) * k, c + Vector2(0.0, 0.9) * k, col, 0.08 * k)


func _draw_bar() -> void:
	var b := _bar_rects()
	var sb_panel := StyleBoxFlat.new()
	sb_panel.bg_color = Color(0.12, 0.12, 0.13, 0.92)
	sb_panel.border_color = Color(0.3, 0.3, 0.32)
	sb_panel.set_border_width_all(3)
	sb_panel.set_corner_radius_all(16)
	draw_style_box(sb_panel, b["panel"])
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	var green := Color(0.5, 0.85, 0.15)
	if b.has("work"):
		_bar_btn(b["work"], sb, work_on)
		_icon_work(b["work"], Color(0.7, 1.0, 0.35) if work_on else green)
		if work_on:
			draw_circle((b["work"] as Rect2).position + Vector2((b["work"] as Rect2).size.x - 14.0, 14.0), 7.0, Color(0.5, 1.0, 0.2))
	if b.has("seed"):
		_bar_btn(b["seed"], sb, false)
		_icon_seed(b["seed"], green)
	_bar_btn(b["horn"], sb, held.get("horn", false))
	_icon_horn(b["horn"], Color(0.7, 1.0, 0.35) if held.get("horn", false) else green)


# v_016: a gun box (dark glass square, cut corner on the top right). Shows the gun picture, yellow edge = this one is in the hand.
func _draw_box(id: String) -> void:
	var h := _rad(id)
	var gr := _group_rects(id)
	_draw_main_box(gr["main"], h)
	for k in 3:   # the three small boxes: gun 1, gun 2, empty hands
		var r: Rect2 = gr[GUN_BOXES[k]]
		_draw_one_box(GUN_BOXES[k], r.get_center(), h)


# the big box: ammo in the magazine (big number) / magazine size, picture of the gun, bar. Tap = reload.
func _draw_main_box(r: Rect2, h: float) -> void:
	var info: Dictionary = slot_view.get("main", {})
	var armed: bool = bool(info.get("armed", false)) or edit
	var cut := h * 0.34
	var pts := PackedVector2Array([r.position, r.position + Vector2(r.size.x - cut, 0), r.position + Vector2(r.size.x, cut), r.end, r.position + Vector2(0, r.size.y)])
	draw_colored_polygon(pts, _a(Color(0.09, 0.14, 0.22, 0.88)))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), _a(Color(1, 1, 1, 0.35)), 2.0)
	var f := ThemeDB.fallback_font
	if not armed:
		draw_string(f, Vector2(r.position.x, r.get_center().y + h * 0.16), "EMPTY HANDS", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(h * 0.42), _a(Color(1, 1, 1, 0.55)))
		return
	if bool(info.get("melee", false)):   # v_031: the axe has no magazine: its name and picture
		draw_string(f, Vector2(r.position.x + h * 0.28, r.position.y + h * 0.82), "AXE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.7), _a(Color(1, 1, 1, 0.97)))
		var at: Texture2D = info.get("icon", null)
		if at != null:
			var asz := Vector2(h * 1.5, h * 1.5 * float(at.get_height()) / float(at.get_width()))
			draw_texture_rect(at, Rect2(r.position + Vector2(r.size.x - asz.x - h * 0.4, h * 0.3), asz), false, _a(Color(1, 1, 1, 0.97)))
		return
	var mag: int = int(info.get("mag", 30))
	var mx: int = maxi(int(info.get("mag_max", 30)), 1)
	var reloading: bool = bool(info.get("reloading", false))
	var col := Color(1, 1, 1, 0.97)
	if mag <= 0 and not reloading:
		col = Color(1.0, 0.35, 0.3, 1.0)
	var fs_big := int(h * 0.95)
	var x0 := r.position.x + h * 0.28
	var by := r.position.y + h * 0.82
	var num := str(mag)
	draw_string_outline(f, Vector2(x0, by), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big, 4, _a(Color(0, 0, 0, 0.5)))
	draw_string(f, Vector2(x0, by), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big, _a(col))
	var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_big).x
	draw_string(f, Vector2(x0 + nw + h * 0.08, by), "/%d" % mx, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.42), _a(Color(1, 1, 1, 0.7)))
	if reloading:
		draw_string(f, Vector2(x0, r.position.y + h * 1.18), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.26), _a(Color(1.0, 0.9, 0.3)))
	elif mag < mx:
		draw_string(f, Vector2(x0, r.position.y + h * 1.18), "TAP = RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.26), _a(Color(1, 1, 1, 0.55)))
	var tex: Texture2D = info.get("icon", null)
	if tex != null:
		var sz := Vector2(h * 1.5, h * 1.5 * float(tex.get_height()) / float(tex.get_width()))
		draw_texture_rect(tex, Rect2(r.position + Vector2(r.size.x - sz.x - h * 0.4, h * 0.12), sz), false, _a(Color(1, 1, 1, 0.97)))
	# bar: how full the magazine is (yellow while reloading = how far the reload is)
	var bar := Rect2(r.position.x + h * 0.2, r.end.y - h * 0.2, r.size.x - h * 0.4, h * 0.1)
	draw_rect(bar, _a(Color(0, 0, 0, 0.55)))
	var fill := float(info.get("reload_f", 0.0)) if reloading else float(mag) / float(mx)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fill, 0.0, 1.0), bar.size.y)), _a(Color(1.0, 0.85, 0.2, 0.95) if reloading else Color(1, 1, 1, 0.92)))


func _draw_one_box(kind: String, c: Vector2, h: float) -> void:
	var id := kind
	var info: Dictionary = slot_view.get(id, {})
	var filled: bool = bool(info.get("filled", false)) or edit
	var active: bool = bool(info.get("active", false))
	var cut := h * 0.34
	var tl := c + Vector2(-h, -h)
	var pts := PackedVector2Array([tl, tl + Vector2(h * 2.0 - cut, 0), tl + Vector2(h * 2.0, cut), c + Vector2(h, h), c + Vector2(-h, h)])
	draw_colored_polygon(pts, _a(Color(0.09, 0.14, 0.22, 0.88) if not active else Color(0.16, 0.24, 0.36, 0.92)))
	var edge := Color(1.0, 0.9, 0.3, 0.95) if active else Color(1, 1, 1, 0.35)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), _a(edge), 3.0 if active else 2.0)
	if id == "hands":   # the infinity sign = empty hands
		var pl := PackedVector2Array()
		for i in 41:
			var t := float(i) / 40.0 * TAU
			var dd := 1.0 + sin(t) * sin(t)
			pl.append(c + Vector2(cos(t) / dd, sin(t) * cos(t) / dd) * h * 0.62)
		draw_polyline(pl, _a(Color(1, 1, 1, 0.95)), maxf(3.0, h * 0.09))
		return
	if not filled:
		return
	var tex: Texture2D = info.get("icon", null)
	if tex != null:
		var sz := Vector2(h * 1.7, h * 1.7 * float(tex.get_height()) / float(tex.get_width()))
		draw_texture_rect(tex, Rect2(c - sz / 2.0, sz), false, _a(Color(1, 1, 1, 0.95)))
	else:
		var f := ThemeDB.fallback_font
		draw_string(f, c + Vector2(-h, 8.0), String(info.get("name", "GUN")), HORIZONTAL_ALIGNMENT_CENTER, h * 2.0, 24, _a(Color.WHITE))


func _draw() -> void:
	if not edit and stick_id != -1:
		var d := stick_pos - stick_origin
		if d.length() > STICK_R:
			d = d.normalized() * STICK_R
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.2))
		draw_circle(stick_origin + d, 42.0, Color(1, 1, 1, 0.55))

	for id in btn:
		if not _vis(id):
			continue
		var col := Color(1.0, 0.6, 0.1, 0.9)
		var text: String = btn[id]["text"]
		if id == "run":
			col = Color(0.2, 0.8, 0.3, 0.95) if (run_on and not edit) else Color(0.3, 0.45, 0.7, 0.8)
		elif id == "action":
			if not edit:
				text = action_text
				if not action_enabled:
					col = Color(0.4, 0.4, 0.4, 0.6)
		elif id == "hitch":
			if not edit:
				text = hitch_text
				if not hitch_enabled:
					col = Color(0.4, 0.4, 0.4, 0.6)
		elif id == "fire":
			col = Color(1.0, 0.25, 0.15, 0.95) if held.get(id, false) else Color(0.8, 0.2, 0.15, 0.8)
		elif id == "alt_up" or id == "alt_dn":   # helicopter buttons (only shown in the HUD editor, see heli_ui.gd)
			col = Color(0.2, 0.4, 0.75, 0.75)
		elif id == "exit":
			col = Color(0.85, 0.25, 0.2, 0.9)
		elif id == "reload" or id == "swap" or id == "bag":
			col = Color(0.25, 0.5, 0.35, 0.85)
			if id == "swap" and not edit:
				text = swap_text
		elif id == "sleep":
			col = Color(0.2, 0.25, 0.6, 0.9)
			if not edit:
				text = sleep_text
		elif id == "poi":
			col = Color(0.15, 0.6, 0.85, 0.95)
			if not edit:
				text = poi_text
		elif id == "mode":
			col = Color(0.2, 0.7, 0.3, 0.95) if build_mode else Color(0.3, 0.45, 0.7, 0.85)
		elif id == "place":
			col = Color(0.25, 0.8, 0.35, 0.95) if held.get(id, false) else Color(0.15, 0.6, 0.25, 0.85)
		elif id == "break":
			col = Color(0.95, 0.4, 0.15, 0.95) if held.get(id, false) else Color(0.8, 0.3, 0.12, 0.85)
		elif btn[id]["hold"]:
			col = Color(1.0, 0.85, 0.2, 0.95) if held.get(id, false) else Color(0.3, 0.45, 0.7, 0.8)
		if id == "mode" or id == "break":
			text = ""
		_op = float(btn[id]["opacity"])   # v_015: every button has its own opacity
		if BAR_IDS.has(id):   # the bar itself is drawn by combat_hud.gd: here only the editor rings
			if edit:
				var bh2 := _box_half(id)
				draw_rect(Rect2(_center(id) - bh2 - Vector2(3, 3), (bh2 + Vector2(3, 3)) * 2.0), Color(1, 1, 1, 0.35), false, 2.0)
				if id == sel:
					draw_rect(Rect2(_center(id) - bh2 - Vector2(8, 8), (bh2 + Vector2(8, 8)) * 2.0), Color(1, 0.95, 0.2), false, 4.0)
			continue
		if BOX_IDS.has(id):
			_draw_box(id)
			_op = 1.0
			if edit:
				var hb := _box_half(id)
				draw_rect(Rect2(_center(id) - hb - Vector2(3, 3), (hb + Vector2(3, 3)) * 2.0), Color(1, 1, 1, 0.35), false, 2.0)
				if id == sel:
					draw_rect(Rect2(_center(id) - hb - Vector2(8, 8), (hb + Vector2(8, 8)) * 2.0), Color(1, 0.95, 0.2), false, 4.0)
			continue
		if id == "fire" and not edit:
			_circle_btn(_center(id) + fire_off, _rad(id) * (1.12 if held.get("fire", false) else 1.0), text, col)
		else:
			_circle_btn(_center(id), _rad(id), text, col)
		if id == "mode":
			_icon_hammer(_center(id), _rad(id))
		elif id == "break":
			_icon_break(_center(id), _rad(id))
		_op = 1.0
		if edit:   # thin ring = a very see-through button can still be found; yellow ring = the selected one
			draw_arc(_center(id), _rad(id) + 3.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
			if id == sel:
				draw_arc(_center(id), _rad(id) + 8.0, 0.0, TAU, 48, Color(1, 0.95, 0.2), 4.0)

	if drive_mode and not edit:
		_draw_bar()


func _input(event: InputEvent) -> void:
	if not visible or edit:   # while the HUD editor is open it handles every touch itself
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event)
		else:
			_release(event)
	elif event is InputEventScreenDrag:
		_drag(event)


func _press(e: InputEventScreenTouch) -> void:
	if blocked:
		return
	if map_rect.has_point(e.position):
		map_pressed.emit()
		return
	if drive_mode:
		var bar := _bar_rects()
		if bar.has("work") and (bar["work"] as Rect2).grow(10.0).has_point(e.position):
			work_pressed.emit()
			return
		if bar.has("seed") and (bar["seed"] as Rect2).grow(10.0).has_point(e.position):
			seed_pressed.emit()
			return
		if (bar["horn"] as Rect2).grow(10.0).has_point(e.position):
			held["horn"] = true
			hold_touch[e.index] = "horn"
			return
	if build_mode and not drive_mode:
		var hb := hotbar_rects()
		var ar := hotbar_arrow_rects()
		if ar.size() == 2:
			if (ar[0] as Rect2).grow(6.0).has_point(e.position):
				hotbar_first = maxi(hotbar_first - 1, 0)
				return
			if (ar[1] as Rect2).grow(6.0).has_point(e.position):
				hotbar_first = mini(hotbar_first + 1, hotbar_n - HOTBAR_VIS)
				return
		if not hb.is_empty():
			var area: Rect2 = (hb[0] as Rect2).merge(hb[hb.size() - 1] as Rect2).grow(6.0)
			if area.has_point(e.position):   # a tap selects, a swipe scrolls (decided when the finger moves / lifts)
				hb_touch = e.index
				hb_start = e.position
				hb_start_first = hotbar_first
				hb_moved = false
				hb_slot = -1
				for i in hb.size():
					if (hb[i] as Rect2).grow(4.0).has_point(e.position):
						hb_slot = i
				return
	for id in btn:
		if not _vis(id):
			continue
		if BAR_IDS.has(id):
			continue   # the health bar is only to look at: a touch on it is a normal look / move touch
		if _dist(id, e.position) < _rad(id) + 20.0:
			if id == "guns":
				var gr := _group_rects(id)
				if e.position.y < (gr["main"] as Rect2).end.y + _rad(id) * BOX_GAP:   # the big ammo box: tap = reload
					reload_pressed.emit()
				else:   # which of the 3 small boxes: the nearest one left / middle / right
					var bx := clampi(int(round((e.position.x - _center(id).x) / (_rad(id) * (2.0 + BOX_GAP * 2.0)))), -1, 1)
					gun_slot_pressed.emit(-1 if bx == 1 else bx + 1)
			elif btn[id]["hold"]:
				held[id] = true
				hold_touch[e.index] = id
			elif id == "jump":
				jump_pressed.emit()
				hold_touch[e.index] = "jump"
			elif id == "run":
				run_pressed.emit()
			elif id == "action":
				action_pressed.emit()
			elif id == "hitch":
				hitch_pressed.emit()
			elif id == "poi":
				poi_pressed.emit()
			elif id == "reload":
				reload_pressed.emit()
			elif id == "swap":
				swap_pressed.emit()
			elif id == "bag":
				bag_pressed.emit()
			elif id == "sleep":
				sleep_pressed.emit()
			elif id == "mode":
				build_mode = not build_mode
				release_all()
				mode_pressed.emit()
			return
	# on foot: left side = joystick. driving: no joystick, the whole screen is look (look only, never steers)
	if not drive_mode and e.position.x < _vp().x * 0.4:
		if stick_id == -1:
			stick_id = e.index
			stick_origin = e.position
			stick_pos = e.position
	elif look_id == -1:
		look_id = e.index


func _release(e: InputEventScreenTouch) -> void:
	if e.index == hb_touch:
		if not hb_moved and hb_slot >= 0:
			slot_pressed.emit(hotbar_first + hb_slot + 1)
		hb_touch = -1
		return
	if hold_touch.has(e.index):
		var hid: String = hold_touch[e.index]
		if hid == "fire":
			fire_target = Vector2.ZERO
		if held.has(hid):
			held[hid] = false
		hold_touch.erase(e.index)
	if e.index == stick_id:
		stick_id = -1
		move_dir = Vector2.ZERO
	if e.index == look_id:
		look_id = -1


func _drag(e: InputEventScreenDrag) -> void:
	if blocked:
		return
	if e.index == hb_touch:
		var L := _hotbar_layout()
		var step: float = float(L["ss"]) + float(L["gp"])
		var dx: float = e.position.x - hb_start.x
		if absf(dx) > 14.0:
			hb_moved = true
		if hb_moved:
			hotbar_first = clampi(hb_start_first - int(round(dx / step)), 0, maxi(hotbar_n - HOTBAR_VIS, 0))
		return
	if hold_touch.has(e.index) and hold_touch[e.index] == "fire":
		fire_target = (e.position - _center("fire")).limit_length(_rad("fire") * 0.7)
	if hold_touch.has(e.index) and LOOK_HOLD.has(hold_touch[e.index]):
		look_dragged.emit(e.relative.x, e.relative.y)
		return
	if e.index == stick_id:
		stick_pos = e.position
		var d := stick_pos - stick_origin
		if d.length() > STICK_R:
			d = d.normalized() * STICK_R
		move_dir = d / STICK_R
	elif e.index == look_id:
		look_dragged.emit(e.relative.x, e.relative.y)
