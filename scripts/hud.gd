extends Control
# Beyond the Crash HUD (all drawn in code): crosshair, ammo, item boxes (dirt / wood), map name + position, messages.

var shooter
var main
var info_text := ""        # extra line under the map name (speed / altitude while driving / flying)
var _say_text := ""
var _say_t := 0.0
var _pop := {}             # kind -> seconds left of the "+1" flash
var _pulse := {}           # kind -> seconds left of the box pulse


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# v_021: colour of a bag item that has no entry in shooter.ITEM_COLORS (taken from the block of the same name)
func _kind_color(k: String) -> Color:
	for t in main.build.TYPES:
		if String(t["kind"]) == k:
			return t["col"]
	return Color.WHITE


func say(t: String, secs: float = 1.8) -> void:
	_say_text = t
	_say_t = secs


func pop(kind: String) -> void:
	_pop[kind] = 0.7
	_pulse[kind] = 0.25


func _process(delta: float) -> void:
	_say_t = maxf(0.0, _say_t - delta)
	for k in _pop.keys():
		_pop[k] = maxf(0.0, float(_pop[k]) - delta)
	for k in _pulse.keys():
		_pulse[k] = maxf(0.0, float(_pulse[k]) - delta)
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if shooter == null or main == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := vp / 2.0
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var foot: bool = shooter.on_foot()

	# crosshair
	if foot:
		var on_bandit: bool = main.combat != null and main.combat.target_on   # v_007: red over a bandit
		var cgap := 13.0 if on_bandit else 9.0
		var ccol := Color(1.0, 0.1, 0.05) if on_bandit else Color(1, 1, 1, 0.9)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * cgap, c + d * (cgap + 12.0), ccol, 4.0 if on_bandit else 3.0)
		draw_circle(c, 2.5 if on_bandit else 2.0, Color(1.0, 0.2, 0.2))

	# v_010: the map name / x z position line is removed (only speed / altitude is shown while driving / flying)
	if info_text != "":
		var lines := info_text.split("\n")
		var y := 130.0 * u
		for ln in lines:
			_text(ln, Vector2(24.0 * u, y), int(26.0 * u), Color(1.0, 0.92, 0.5))
			y += 30.0 * u

	var kinds := ["wood", "stone", "meat"]   # v_009: the Wood / Stone boxes moved into the BAG panel
	if main.build != null:   # v_021: every other block you own is listed too
		for t in main.build.TYPES:
			var kk := String(t["kind"])
			if kk != "" and not kinds.has(kk) and int(shooter.inv.get(kk, 0)) > 0:
				kinds.append(kk)
	# "+1" flash next to the BAG button when something is picked up
	var bagc: Vector2 = Vector2(main.touch.btn["bag"]["pos"]) * vp
	var fy := 0.0
	for k in kinds:
		var pp := float(_pop.get(k, 0.0))
		if pp > 0.0:
			_text("+1 %s" % k.capitalize(), Vector2(bagc.x - 120.0 * u, bagc.y + 80.0 * u + fy - (0.7 - pp) * 30.0 * u), int(26.0 * u), Color(1.0, 0.95, 0.4, minf(pp * 3.0, 1.0)), 240.0 * u, HORIZONTAL_ALIGNMENT_CENTER)
			fy += 30.0 * u

	# build mode: one button for every block you own (bottom center). The yellow frame = selected block. Many blocks: swipe the bar
	if foot and main.touch.build_mode:
		var rects: Array = main.touch.hotbar_rects()
		var owned: Array = main.build.owned
		var first: int = main.touch.hotbar_first
		if rects.is_empty():
			_text("No blocks - cut a tree or break a rock", Vector2(0, vp.y - 40.0 * u), int(26.0 * u), Color(1.0, 0.9, 0.5), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			for i in rects.size():
				var gi: int = first + i
				if gi >= owned.size():
					break
				var bid: int = int(owned[gi])
				var sr: Rect2 = rects[i]
				var chosen: bool = bid == main.build.sel
				draw_rect(sr, Color(1, 1, 1, 0.22 if chosen else 0.12))
				draw_texture_rect(main.build.icon_tex(bid), sr.grow(-sr.size.x * 0.14), false)
				if chosen:
					draw_rect(sr, Color(1.0, 0.9, 0.3), false, 4.0 * u)
				else:
					draw_rect(sr, Color(1, 1, 1, 0.5), false, 2.0)
				if bid <= main.build.PLANT_BASE:   # v_042: planted trees are unlimited: no number
					_text("%d" % main.build.count_of(bid), Vector2(sr.position.x, sr.end.y - 4.0 * u), int(sr.size.y * 0.34), Color.WHITE, sr.size.x - 5.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
			var ars: Array = main.touch.hotbar_arrow_rects()
			if ars.size() == 2:
				var ra: Rect2 = ars[0]
				var rb: Rect2 = ars[1]
				var ca := Color(1, 1, 1, 0.9 if first > 0 else 0.25)
				var cb := Color(1, 1, 1, 0.9 if first + main.touch.HOTBAR_VIS < owned.size() else 0.25)
				draw_colored_polygon(PackedVector2Array([Vector2(ra.end.x, ra.position.y + ra.size.y * 0.2), Vector2(ra.position.x, ra.position.y + ra.size.y * 0.5), Vector2(ra.end.x, ra.end.y - ra.size.y * 0.2)]), ca)
				draw_colored_polygon(PackedVector2Array([Vector2(rb.position.x, rb.position.y + rb.size.y * 0.2), Vector2(rb.end.x, rb.position.y + rb.size.y * 0.5), Vector2(rb.position.x, rb.end.y - rb.size.y * 0.2)]), cb)
			var top: float = (rects[0] as Rect2).position.y
			_text(main.build.block_name(), Vector2(0, top - 10.0 * u), int(26.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)


	if _say_t > 0.0:
		_text(_say_text, Vector2(0, c.y + 130.0 * u), int(28.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
