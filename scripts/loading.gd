extends Control
# V29 splash: logo + progress bar while the game builds. All drawn in code (no image files).
var progress := 0.0
var shown := 0.0
var msg := "Loading..."
var t := 0.0
const TIPS := ["Collect resources to build a better home!", "Drive the tractor with the GET IN button.", "Torches keep bandits away at night.", "Fly the helicopter to see the whole world."]
const BG_PATH := "res://assets/ui/lobby_bg.jpg"   # the loading screen uses the lobby picture
const LOGO_PATH := "res://assets/ui/logo.png"
const VERSION := "v1"   # v_045: same as Cfg.VERSION (was "005")
var bg: Texture2D   # loading picture. No picture = the plain drawing
var logo: Texture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(BG_PATH):
		bg = load(BG_PATH) as Texture2D
	if ResourceLoader.exists(LOGO_PATH):
		logo = load(LOGO_PATH) as Texture2D


func set_progress(p: float, m: String) -> void:
	progress = p
	msg = "Ready" if m == "Ready" else "Loading..."   # v_010: no technical step names on screen


func _process(d: float) -> void:
	t += d
	shown = move_toward(shown, progress, d * 0.8)
	queue_redraw()


func _draw_picture(vp: Vector2, f: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.08, 0.05))
	# picture fills the screen (cover), centred
	var ts := bg.get_size()
	var k := maxf(vp.x / ts.x, vp.y / ts.y)
	var sz := ts * k
	draw_texture_rect(bg, Rect2((vp - sz) / 2.0, sz), false)
	# soft dark bands behind the logo and the bar so the text is easy to read
	draw_rect(Rect2(0, vp.y * 0.76, vp.x, vp.y * 0.24), Color(0, 0, 0, 0.42))
	var u := minf(vp.x, vp.y)
	# game logo (top left)
	if logo != null:
		var lh := vp.y * 0.34
		var lw := lh * logo.get_size().x / logo.get_size().y
		draw_texture_rect(logo, Rect2(Vector2(vp.x * 0.02, vp.y * 0.01), Vector2(lw, lh)), false)
	# version (top right)
	var ver := "Beyond the Crash  " + VERSION   # v_045: shows e.g. "Beyond the Crash  v1"
	var vs := int(u * 0.03)
	var vw := f.get_string_size(ver, HORIZONTAL_ALIGNMENT_LEFT, -1, vs).x
	_text(f, ver, Vector2(vp.x - vw - vp.x * 0.03, vp.y * 0.03 + vs), vs, Color(1, 1, 1, 0.9))
	# "Loading..." + bar + percent
	var bw := vp.x * 0.55
	var bh := maxf(16.0, vp.y * 0.03)
	var bar := Rect2(vp.x / 2.0 - bw / 2.0, vp.y * 0.88, bw, bh)
	var ls := int(u * 0.05)
	var lw := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	_text(f, msg, Vector2(vp.x / 2.0 - lw / 2.0, bar.position.y - bh * 0.7), ls, Color(1, 1, 1))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.08, 0.05, 0.75)
	track.set_corner_radius_all(int(bh / 2.0))
	track.border_color = Color(1, 1, 1, 0.45)
	track.set_border_width_all(2)
	draw_style_box(track, bar)
	var fw := maxf(bh, bw * clampf(shown, 0.0, 1.0))
	if shown > 0.005:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.45, 0.95, 0.1)
		fill.set_corner_radius_all(int(bh / 2.0))
		draw_style_box(fill, Rect2(bar.position + Vector2(2, 2), Vector2(fw - 4.0, bh - 4.0)))
	var pct := "%d%%" % int(clampf(shown, 0.0, 1.0) * 100.0)
	_text(f, pct, Vector2(bar.end.x + 14.0, bar.position.y + bh * 0.9), int(u * 0.035), Color(1, 1, 1))
	# tip (changes every 5 seconds)
	var tip: String = TIPS[int(t / 5.0) % TIPS.size()]
	var tsz := int(u * 0.032)
	var tw := f.get_string_size("Tip: " + tip, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
	_text(f, "Tip: " + tip, Vector2(vp.x / 2.0 - tw / 2.0, bar.end.y + tsz * 1.7), tsz, Color(1, 1, 1, 0.95))


func _text(f: Font, txt: String, pos: Vector2, size: int, col: Color) -> void:
	draw_string(f, pos + Vector2(size * 0.06, size * 0.06), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.75))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var f := ThemeDB.fallback_font
	if bg != null:
		_draw_picture(vp, f)
		return
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.1, 0.07))
	draw_rect(Rect2(0, vp.y * 0.62, vp.x, vp.y * 0.38), Color(0.1, 0.17, 0.09))   # field
	var c := Vector2(vp.x / 2.0, vp.y * 0.34)
	var r := minf(vp.x, vp.y) * 0.17
	# logo: tractor wheel + wheat
	draw_circle(c, r, Color(0.95, 0.76, 0.1))
	draw_circle(c, r * 0.82, Color(0.08, 0.1, 0.09))
	draw_circle(c, r * 0.62, Color(0.12, 0.52, 0.17))
	for k in 6:
		var a := t * 1.2 + TAU * float(k) / 6.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.6, Color(0.95, 0.76, 0.1), 5.0)
	draw_circle(c, r * 0.16, Color(0.95, 0.76, 0.1))
	for k in 5:
		var x := c.x - r * 0.5 + float(k) * r * 0.25
		draw_line(Vector2(x, c.y + r * 1.0), Vector2(x, c.y + r * 1.3), Color(0.95, 0.85, 0.3), 3.0)
		draw_circle(Vector2(x, c.y + r * 0.98), 6.0, Color(0.95, 0.85, 0.3))
	var title := "BEYOND THE CRASH"
	var fs := int(minf(vp.x, vp.y) * 0.1)
	var sz := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2(c.x - sz.x / 2.0, c.y + r + fs * 1.5), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.85, 0.3))
	# progress bar
	var bw := vp.x * 0.5
	var bar := Rect2(vp.x / 2.0 - bw / 2.0, vp.y * 0.86, bw, 18.0)
	draw_rect(bar, Color(0.2, 0.25, 0.2))
	draw_rect(Rect2(bar.position, Vector2(bw * clampf(shown, 0.0, 1.0), bar.size.y)), Color(0.5, 0.85, 0.15))
	var ms := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	draw_string(f, Vector2(vp.x / 2.0 - ms.x / 2.0, bar.position.y - 14.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.9, 0.85))
