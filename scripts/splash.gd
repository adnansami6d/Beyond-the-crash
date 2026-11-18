extends Control
# Start screen: the game logo on black, shown for exactly SHOW_TIME seconds (fade in, hold, fade out). Cannot be skipped.
signal done

const LOGO_PATH := "res://assets/ui/logo.png"
const SHOW_TIME := 3.0
const FADE_IN := 0.6
const FADE_OUT := 0.5


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var logo := TextureRect.new()
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.offset_left = 40
	logo.offset_right = -40
	logo.offset_top = 24
	logo.offset_bottom = -24
	if ResourceLoader.exists(LOGO_PATH):
		logo.texture = load(LOGO_PATH) as Texture2D
	logo.modulate.a = 0.0
	add_child(logo)
	var tw := create_tween()
	tw.tween_property(logo, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(SHOW_TIME - FADE_IN - FADE_OUT)
	tw.tween_property(logo, "modulate:a", 0.0, FADE_OUT)
	tw.finished.connect(func(): done.emit())
