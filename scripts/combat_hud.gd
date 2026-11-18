extends Control
# Combat HUD (v_007, from Fx99 combat_hud.gd): damage flash, health bar, hit marker, objective, banner, death screen.
# The crosshair (red over a bandit), ammo and short messages are drawn by hud.gd (Beyond the Crash HUD), so nothing is drawn twice.

const Cfg = preload("res://scripts/config.gd")
var combat
var hit_t := 0.0
var hit_kill := false
var flash := 0.0
var _ban_text := ""
var _ban_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# short message: shown by the Beyond the Crash HUD
func say(t: String, secs: float = 1.8) -> void:
	if combat != null and combat.main != null and combat.main.hud != null:
		combat.main.hud.say(t, secs)


func banner(t: String, secs: float = 4.0) -> void:
	_ban_text = t
	_ban_t = secs


func hit(kill: bool) -> void:
	hit_t = 0.18
	hit_kill = kill


func hurt() -> void:
	flash = 0.45


func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	flash = maxf(0.0, flash - delta)
	_ban_t = maxf(0.0, _ban_t - delta)
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if combat == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := vp / 2.0
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.8, 0.0, 0.0, minf(flash, 0.45) * 0.5))

	# hit marker (white = hit, red = kill)
	if combat.on_foot() and hit_t > 0.0:
		var hc := Color(1.0, 0.15, 0.1) if hit_kill else Color(1, 1, 1)
		for sgn in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + sgn * 8.0, c + sgn * 18.0, hc, 3.0)

	# health bar (top left corner)
	var bw := 300.0 * u
	var bh := 22.0 * u
	var bx := 24.0 * u
	var by := 36.0 * u
	var op := 1.0
	var tc = combat.main.touch if (combat.main != null and combat.main.get("touch") != null) else null
	if tc != null:   # v_017: place, size and opacity come from the HUD layout (the HUD editor moves the bar)
		var rc: Rect2 = tc.bar_rect("hp")
		bx = rc.position.x
		by = rc.position.y
		bw = rc.size.x
		bh = rc.size.y
		op = tc.btn_opacity("hp")
	var fs := maxi(int(bh * 0.9), 10)
	var frac := clampf(combat.hp / combat.MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(bx - 3, by - 3, bw + 6, bh + 6), Color(0, 0, 0, 0.7 * op))
	var hc := Color(0.9, 0.15, 0.1).lerp(Color(0.25, 0.85, 0.25), frac)
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(hc.r, hc.g, hc.b, op))
	_text("HP %d" % int(ceil(combat.hp)), Vector2(bx, by + bh - maxf(bh * 0.18, 2.0)), fs, Color(1, 1, 1, op), bw, HORIZONTAL_ALIGNMENT_CENTER)

	# hunger bar (v_020, under the health bar)
	if Cfg.HUNGER:
		var hx := 24.0 * u
		var hy := by + bh + 14.0 * u
		var hw := 250.0 * u
		var hh := 18.0 * u
		var hop := 1.0
		if tc != null:
			var rc2: Rect2 = tc.bar_rect("hunger")
			hx = rc2.position.x
			hy = rc2.position.y
			hw = rc2.size.x
			hh = rc2.size.y
			hop = tc.btn_opacity("hunger")
		var hf := clampf(combat.hunger / Cfg.HUNGER_MAX, 0.0, 1.0)
		var hcol := Color(0.95, 0.55, 0.1) if combat.hunger >= Cfg.HUNGER_NO_RUN else Color(0.85, 0.15, 0.1)
		draw_rect(Rect2(hx - 3, hy - 3, hw + 6, hh + 6), Color(0, 0, 0, 0.7 * hop))
		draw_rect(Rect2(hx, hy, hw * hf, hh), Color(hcol.r, hcol.g, hcol.b, hop))
		_text("FOOD %d" % int(ceil(combat.hunger)), Vector2(hx, hy + hh - maxf(hh * 0.18, 2.0)), maxi(int(hh * 0.9), 10), Color(1, 1, 1, hop), hw, HORIZONTAL_ALIGNMENT_CENTER)

	# objective (under the health bar)
	var obj: String = combat.objective_text()
	if obj != "":
		var lines := obj.split("\n")
		var y := by + bh + 34.0 * u
		for ln in lines:
			_text(ln, Vector2(bx, y), int(22.0 * u), Color(1.0, 0.92, 0.5))
			y += 28.0 * u

	if _ban_t > 0.0:
		var by2 := c.y - 130.0 * u
		for ln2 in _ban_text.split("\n"):
			_text(ln2, Vector2(0, by2), int(40.0 * u), Color(1.0, 0.85, 0.2), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
			by2 += 46.0 * u

	if combat.dead:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
		_text("YOU DIED", Vector2(0, c.y), int(70.0 * u), Color(0.95, 0.2, 0.15), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
