extends Control
# v_043: the BAG screen (own design, replaces the small bag list of hud.gd). Opens with the BAG button (shooter.bag_open).
#   left   : MAIN WEAPONS (the 2 gun slots + empty hands). Tap = take it in the hand.
#   middle : everything the player owns / can use, in sections you can scroll (swipe up / down):
#            FOOD (every entry of Shooter.FOODS, small see-through "eat" button), BLOCKS (every block of Build.TYPES, count),
#            TREES (every plantable tree of Build.PLANTS, always there). Tap a block / tree = select it for BUILD mode.
#   right  : (later) things lying on the ground near the player that can be picked up.
# While the bag is open the touch buttons are hidden (and come back when it closes). Only ScreenTouch events are used
# (a touch also makes a fake mouse click in Godot, so using both would count a tap twice).

const Cfg = preload("res://scripts/config.gd")

var main
var shooter

var _open := false
var _scroll := 0.0
var _max_scroll := 0.0
var _hits: Array = []        # [Rect2, kind String, arg, in_list bool] rebuilt every frame (drawn order, later = on top)
var _list_rect := Rect2()
var _t_idx := -1
var _t_start := Vector2.ZERO
var _t_moved := false
var _t_in_list := false
var _toast_t := 0.0
var _toast_s := ""

const PANEL := Color(0.055, 0.065, 0.085, 1.0)   # fully solid: the scrolled-out part of the list must not shine through
const CARD := Color(0.13, 0.15, 0.19, 1.0)
const GOLD := Color(1.0, 0.85, 0.3)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func toast(t: String, secs: float = 1.5) -> void:
	_toast_s = t
	_toast_t = secs


func _process(delta: float) -> void:
	if shooter == null:
		return
	_toast_t = maxf(0.0, _toast_t - delta)
	if shooter.bag_open and not shooter.on_foot():
		shooter.bag_open = false   # got into a vehicle: close the bag
	if shooter.bag_open != _open:
		_open = shooter.bag_open
		visible = _open
		if _open:
			_scroll = 0.0
			_t_idx = -1
			main.touch.release_all()
			main.touch.visible = false   # the game buttons must not lie on top of the bag screen
		else:
			main.touch.visible = true
	if _open:
		queue_redraw()


func _close() -> void:
	if shooter.bag_open:
		shooter.toggle_bag()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if not _open or shooter == null:
		return
	_hits.clear()
	var vp := get_viewport_rect().size
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	var P := Rect2(vp.x * 0.025, 0.0, vp.x * 0.95, vp.y)   # full height: nothing of the list can show outside the panel
	draw_rect(P, PANEL)
	draw_rect(P, Color(1, 1, 1, 0.35), false, 2.0)
	var pad := 16.0 * u
	var head_h := 64.0 * u
	var body_y0 := P.position.y + head_h + 8.0 * u
	var body_y1 := P.end.y - 44.0 * u

	# ---- left column: main weapons
	var lw := 290.0 * u
	var lx := P.position.x + pad
	_text("MAIN WEAPONS", Vector2(lx, body_y0 + 58.0 * u), int(20.0 * u), Color(1, 1, 1, 0.6))   # below the HP / FOOD bars
	var cy := body_y0 + 72.0 * u
	for i in shooter.slots.size():
		var wi: int = int(shooter.slots[i])
		var r := Rect2(lx, cy, lw, 112.0 * u)
		draw_rect(r, CARD)
		var inhand: bool = shooter.hand == i
		draw_rect(r, GOLD if inhand else Color(1, 1, 1, 0.25), false, 3.0 if inhand else 1.5)
		if wi >= 0:
			var wd: Dictionary = shooter.WEAPONS[wi]
			_text(String(wd["name"]), Vector2(r.position.x + 16.0 * u, r.position.y + 52.0 * u), int(40.0 * u), Color.WHITE)
			var sub := "MELEE" if bool(wd.get("melee", false)) else "AMMO  %d / %d" % [int(shooter.mag[wi]), int(wd["mag"])]
			_text(sub, Vector2(r.position.x + 16.0 * u, r.position.y + 90.0 * u), int(22.0 * u), Color(1, 1, 1, 0.7))
			if inhand:
				_text("IN HAND", Vector2(r.position.x, r.position.y + 28.0 * u), int(18.0 * u), GOLD, r.size.x - 12.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			_text("EMPTY SLOT", Vector2(r.position.x + 16.0 * u, r.position.y + 66.0 * u), int(26.0 * u), Color(1, 1, 1, 0.35))
		_hits.append([r, "weapon", i, false])
		cy += 124.0 * u
	var rh := Rect2(lx, cy, lw, 70.0 * u)
	draw_rect(rh, CARD)
	var hands: bool = shooter.hand < 0
	draw_rect(rh, GOLD if hands else Color(1, 1, 1, 0.25), false, 3.0 if hands else 1.5)
	_text("EMPTY HANDS", Vector2(rh.position.x + 16.0 * u, rh.position.y + 44.0 * u), int(26.0 * u), Color.WHITE)
	_hits.append([rh, "weapon", -1, false])

	# ---- middle: scrolling list
	var mx := lx + lw + pad * 1.5
	var mw := P.end.x - pad - mx
	_list_rect = Rect2(mx, body_y0, mw, body_y1 - body_y0)
	var ts := 108.0 * u
	var gap := 12.0 * u
	var cols := maxi(1, int((mw + gap) / (ts + gap)))
	var y := body_y0 - _scroll
	# FOOD
	y = _section("FOOD", y, mx, u)
	var fi := 0
	for k in shooter.FOODS.keys():
		var tr := Rect2(mx + float(fi % cols) * (ts + gap), y + float(fi / cols) * (ts + gap), ts, ts)
		_tile_item(tr, String(k), u, true)
		fi += 1
	y += float((fi + cols - 1) / cols) * (ts + gap) + 8.0 * u
	# BLOCKS
	y = _section("BLOCKS", y, mx, u)
	var bt: Array = main.build.TYPES
	for i in bt.size():
		var tr2 := Rect2(mx + float(i % cols) * (ts + gap), y + float(i / cols) * (ts + gap), ts, ts)
		_tile_block(tr2, i + 1, u)
	y += float((bt.size() + cols - 1) / cols) * (ts + gap) + 8.0 * u
	# TREES
	y = _section("TREES  (plant them in BUILD mode)", y, mx, u)
	var pl: Array = main.build.PLANTS
	for j in pl.size():
		var tr3 := Rect2(mx + float(j % cols) * (ts + gap), y + float(j / cols) * (ts + gap), ts, ts)
		_tile_block(tr3, main.build.PLANT_BASE + j + 1, u)
	y += float((pl.size() + cols - 1) / cols) * (ts + gap)
	var content_h := y + _scroll - body_y0
	_max_scroll = maxf(0.0, content_h - _list_rect.size.y)
	_scroll = clampf(_scroll, 0.0, _max_scroll)

	# bars over the list ends (hide what is scrolled out) + header + footer
	draw_rect(Rect2(mx - 4.0, P.position.y, P.end.x - mx, body_y0 - P.position.y), PANEL)
	draw_rect(Rect2(mx - 4.0, body_y1, P.end.x - mx, P.end.y - body_y1), PANEL)
	_text("BAG", Vector2(mx, P.position.y + 48.0 * u), int(38.0 * u), GOLD)   # next to the HP / FOOD bars, not under them
	var xr := Rect2(P.end.x - pad - 170.0 * u, P.position.y + 8.0 * u, 56.0 * u, 48.0 * u)   # left of the gear button
	draw_rect(xr, Color(0.55, 0.15, 0.15, 0.95))
	draw_rect(xr, Color(1, 1, 1, 0.6), false, 2.0)
	_text("X", Vector2(xr.position.x, xr.end.y - 12.0 * u), int(34.0 * u), Color.WHITE, xr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_hits.append([xr, "close", 0, false])
	if _max_scroll > 0.0:   # scroll bar
		var sh := _list_rect.size.y * _list_rect.size.y / (_list_rect.size.y + _max_scroll)
		var sy := _list_rect.position.y + (_list_rect.size.y - sh) * (_scroll / _max_scroll)
		draw_rect(Rect2(P.end.x - 8.0 * u, sy, 4.0 * u, sh), Color(1, 1, 1, 0.35))
	var foot := "Tap a block or tree to select it, then switch to BUILD.   Swipe the list up / down."
	if _toast_t > 0.0:
		foot = _toast_s
		_text(foot, Vector2(mx, P.end.y - 12.0 * u), int(24.0 * u), GOLD, mw)
	else:
		_text(foot, Vector2(mx, P.end.y - 12.0 * u), int(18.0 * u), Color(1, 1, 1, 0.5), mw)


func _section(title: String, y: float, x: float, u: float) -> float:
	_text(title, Vector2(x, y + 22.0 * u), int(20.0 * u), Color(1, 1, 1, 0.6))
	return y + 34.0 * u


# a raw food / material tile (kind = key of shooter.inv)
func _tile_item(r: Rect2, kind: String, u: float, food: bool) -> void:
	var n: int = int(shooter.inv.get(kind, 0))
	var a := 1.0 if n > 0 else 0.4
	draw_rect(r, CARD)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.5)
	var col: Color = shooter.ITEM_COLORS.get(kind, Color.WHITE)
	col.a = a
	var c := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.30)
	draw_circle(c, r.size.x * 0.17, col)
	draw_circle(c + Vector2(r.size.x * 0.05, -r.size.x * 0.04), r.size.x * 0.06, Color(1, 1, 1, 0.45 * a))
	_text(kind.to_upper(), Vector2(r.position.x, r.position.y + r.size.y * 0.66), int(18.0 * u), Color(1, 1, 1, a), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text("x %d" % n, Vector2(r.position.x, r.position.y + 22.0 * u), int(20.0 * u), Color(1, 1, 1, a), r.size.x - 8.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
	if food:   # the small see-through "eat" button inside the tile
		var pill := Rect2(r.position.x + r.size.x * 0.16, r.position.y + r.size.y * 0.74, r.size.x * 0.68, r.size.y * 0.20)
		draw_rect(pill, Color(1, 1, 1, 0.10))
		draw_rect(pill, Color(1, 1, 1, 0.4), false, 1.0)
		_text("eat", Vector2(pill.position.x, pill.end.y - pill.size.y * 0.25), int(pill.size.y * 0.62), Color(1, 1, 1, 0.75 * a), pill.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_hits.append([pill.grow(4.0 * u), "eat", kind, true])


# a block tile (id 1..TYPES.size) or a tree tile (id > PLANT_BASE)
func _tile_block(r: Rect2, id: int, u: float) -> void:
	var b = main.build
	var is_plant: bool = id > b.PLANT_BASE
	var n: int = 0 if is_plant else int(shooter.inv.get(String(b.TYPES[id - 1]["kind"]), 0))
	var a := 1.0 if (is_plant or n > 0) else 0.4
	draw_rect(r, CARD)
	var chosen: bool = b.sel == id
	draw_rect(r, GOLD if chosen else Color(1, 1, 1, 0.25), false, 3.0 if chosen else 1.5)
	var isz := r.size.x * 0.55
	draw_texture_rect(b.icon_tex(id), Rect2(r.position.x + (r.size.x - isz) * 0.5, r.position.y + 8.0 * u, isz, isz), false, Color(1, 1, 1, a))
	var nm: String = String(b.PLANTS[id - b.PLANT_BASE - 1]["name"]) if is_plant else String(b.TYPES[id - 1]["name"])
	_text(nm, Vector2(r.position.x, r.end.y - 10.0 * u), int(17.0 * u), Color(1, 1, 1, a), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if is_plant:
		_text("FREE", Vector2(r.position.x, r.position.y + 22.0 * u), int(16.0 * u), Color(0.6, 1.0, 0.6, a), r.size.x - 8.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_text("x %d" % n, Vector2(r.position.x, r.position.y + 22.0 * u), int(20.0 * u), Color(1, 1, 1, a), r.size.x - 8.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
	_hits.append([r, "block", id, true])


func _input(e: InputEvent) -> void:
	if not _open:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if _t_idx == -1:
				_t_idx = e.index
				_t_start = e.position
				_t_moved = false
				_t_in_list = _list_rect.has_point(e.position)
		elif e.index == _t_idx:
			_t_idx = -1
			if not _t_moved:
				_tap(e.position)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if e.index == _t_idx:
			if (e.position - _t_start).length() > 14.0:
				_t_moved = true
			if _t_in_list and _t_moved:
				_scroll = clampf(_scroll - e.relative.y, 0.0, _max_scroll)
		get_viewport().set_input_as_handled()


func _tap(pos: Vector2) -> void:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if bool(h[3]) and not _list_rect.has_point(pos):
			continue   # a tile that is scrolled under the header / footer
		if not (h[0] as Rect2).has_point(pos):
			continue
		var kind := String(h[1])
		if kind == "close":
			_close()
		elif kind == "weapon":
			shooter.equip(int(h[2]))
		elif kind == "eat":
			shooter.eat_food(String(h[2]))
		elif kind == "block":
			_select(int(h[2]))
		return


func _select(id: int) -> void:
	var b = main.build
	if id <= b.PLANT_BASE:
		var kind := String(b.TYPES[id - 1]["kind"])
		if int(shooter.inv.get(kind, 0)) <= 0:
			toast("No %s yet. Collect some first" % String(b.TYPES[id - 1]["name"]).to_lower(), 1.6)
			return
	b.select_id(id)
	toast("%s selected. Switch to BUILD to place it" % b.block_name(), 1.8)
