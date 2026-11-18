extends Node3D
# BEYOND THE CRASH main: builds the world (the Fx99 map, fx_map.gd), the character, tractor, helicopter, camera, controls, gun.
#
# Where things come from (demo version):
#   Farm_v10 : camera (camera_rig.gd), tractor turning + engine / crash sound (tractor.gd, sfx.gd, audio_lib.gd)
#   Fx99     : character (player.gd, human.gd, characters/valery.glb + characters/anims (Mixamo clips)), trees, helicopter, touch controls
#   Fx99     : the map (fx_map.gd, props.gd, coast.gd, railway.gd, train.gd ...).   new: shooter.gd (gun, items), build.gd, hud.gd

const Util = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const Catalog = preload("res://scripts/catalog.gd")
const CharDb = preload("res://scripts/char_db.gd")
const LoadingScript = preload("res://scripts/loading.gd")
const LobbyScript = preload("res://scripts/lobby.gd")
const SplashScript = preload("res://scripts/splash.gd")
const MIN_LOADING_MS := 2000   # a loading screen stays at least 2 seconds; longer if the work takes longer
const TractorScript = preload("res://scripts/tractor.gd")
const HeliScript = preload("res://scripts/helicopter.gd")
const HeliUiScript = preload("res://scripts/heli_ui.gd")
const FxMapScript = preload("res://scripts/fx_map.gd")
const ShooterScript = preload("res://scripts/shooter.gd")
const HudScript = preload("res://scripts/hud.gd")
const BuildScript = preload("res://scripts/build.gd")
const BiomeScript = preload("res://scripts/biome.gd")
const Cfg = preload("res://scripts/config.gd")
const SkyFx = preload("res://scripts/sky_fx.gd")
const DayNight = preload("res://scripts/daynight.gd")
const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const FloraScript = preload("res://scripts/flora.gd")
const CoconutScript = preload("res://scripts/coconut.gd")
const WarmupScript = preload("res://scripts/warmup.gd")
const CombatScript = preload("res://scripts/combat.gd")
const SaveGameScript = preload("res://scripts/savegame.gd")
const SettingsMenuScript = preload("res://scripts/settings_menu.gd")   # v_015: gear button + HUD / Sound / Graphics list
const _AXE_ICON_PATH := "res://ui/icon_axe.png"   # v_031: picture of the axe in the gun box
var _axe_icon: Texture2D = load(_AXE_ICON_PATH) if ResourceLoader.exists(_AXE_ICON_PATH) else null
const _GUN_ICON_PATH := "res://ui/icon_smg.png"   # v_016: picture of the SMG in the gun box (white, see-through)
var _gun_icon: Texture2D = load(_GUN_ICON_PATH) if ResourceLoader.exists(_GUN_ICON_PATH) else null
const BagUiScript = preload("res://scripts/bag_ui.gd")   # v_043: the BAG screen
const HudEditorScript = preload("res://scripts/hud_editor.gd")         # v_015: move / resize / fade the buttons
const TutorialScript = preload("res://scripts/tutorial.gd")   # v_047: guided tutorial for new players

var layer: CanvasLayer
var loader
var _game_ready := false
var world
var player
var rig
var touch
var tractor
var heli
var heli_ui
var settings_menu   # v_015
var tutorial          # v_047: scripts/tutorial.gd
var hud_editor      # v_015
var shooter
var build
var bag_ui   # v_043
var combat   # v_007: bandits / health (scripts/combat.gd), null when Cfg.COMBAT is false
var hud
var debug_overlay
var horn: AudioStreamPlayer
var driving := false
var flying := false
var savegame   # v_012d: saves + restores everything (scripts/savegame.gd)
var daynight   # F11: day / night clock (scripts/daynight.gd)
var sky_shader_mat: ShaderMaterial   # F10: sky with clouds (time is updated in _process)
var sun_light: DirectionalLight3D   # F8: the sun (day / night later)


func _ready() -> void:
	randomize()
	get_viewport().scaling_3d_scale = Cfg.RENDER_SCALE   # v1.0: lighter graphics (1.0 = full)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA   # smooths the far block edges (no shimmer)
	layer = CanvasLayer.new()
	add_child(layer)
	# 1) the logo (3 s, always), 2) the loading screen (at least 2 s) while the lobby is built, 3) the lobby; the game is built after START
	var splash := SplashScript.new()
	layer.add_child(splash)
	await splash.done
	splash.queue_free()
	loader = LoadingScript.new()
	layer.add_child(loader)
	loader.set_progress(0.3, "Loading...")
	var t_lobby := Time.get_ticks_msec()
	await get_tree().process_frame   # the loading screen is drawn first
	await get_tree().process_frame
	var lobby := LobbyScript.new()
	lobby.visible = false
	layer.add_child(lobby)
	loader.set_progress(1.0, "Loading...")
	while Time.get_ticks_msec() - t_lobby < MIN_LOADING_MS:
		await get_tree().process_frame
	lobby.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	loader.queue_free()
	await lobby.start_pressed
	lobby.queue_free()
	loader = LoadingScript.new()
	layer.add_child(loader)
	var t_game := Time.get_ticks_msec()
	loader.set_progress(0.05, "Loading...")
	await get_tree().process_frame   # make sure the loading screen is drawn first
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout   # logo is on screen before the heavy work starts
	# put your character (.glb/.gltf/.tscn) in res://characters/ -> it is used automatically. No file = built-in character.
	var ch: Dictionary = CharDb.selected()   # the character chosen (EQUIP) in the lobby
	await _start_game(String(ch["glb"]), String(ch["anims"]))
	loader.set_progress(1.0, "Ready")
	await get_tree().create_timer(0.5).timeout
	set_clock(Cfg.START_HOUR)   # a new game always begins at 06:00 morning ...
	savegame = SaveGameScript.new()
	add_child(savegame)
	savegame.start(self)   # ... a saved game goes on exactly where it was left (clock, place, health, bag, broken trees ...)
	_game_ready = true
	while Time.get_ticks_msec() - t_game < MIN_LOADING_MS:   # the loading screen is never shorter than 2 s
		await get_tree().process_frame
	settings_menu.visible = true   # v_015: the gear button shows when the loading screen goes away
	loader.queue_free()
	if tutorial != null:
		tutorial.begin()   # v_047: a new player gets the tutorial (saved in user://tutorial.cfg), an old one does not


# sets the game clock and updates sun, sky and light at once
func set_clock(h: float) -> void:
	if daynight == null:
		return
	daynight.hour = fposmod(h, 24.0)
	daynight._step_t = 99.0   # turn the light to the new time right now
	daynight.update(0.0)


func _step(p: float, m: String) -> void:
	loader.set_progress(p, m)
	await get_tree().process_frame
	await get_tree().process_frame


# loads a .tscn/.glb and returns it as a Node3D (or null if it fails)
func _load_scene(path: String) -> Node3D:
	if path == "":
		return null
	var res = load(path)
	if res is PackedScene:
		var n = res.instantiate()
		if n is Node3D:
			return n
		n.queue_free()
	push_warning("Could not load: " + path)
	return null


func _make_environment() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X if Cfg.MSAA else Viewport.MSAA_DISABLED   # F11b
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# F10: own sky shader = blue sky + cloud shapes + real sun disc (the sun disc is drawn by the shader,
	# the DirectionalLight below only lights the world)
	var sun_dir := Basis.from_euler(Vector3(deg_to_rad(-Cfg.SUN_ELEVATION), deg_to_rad(Cfg.SUN_AZIMUTH), 0.0)).z
	sky_shader_mat = SkyFx.make_material(sun_dir, Cfg.CLOUD_COVER if Cfg.CLOUDS else 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_shader_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32   # ambient light is a plain colour, so the sky cube map can be tiny
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Cfg.AMBIENT_COLOR if Cfg.SUN else Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = Cfg.AMBIENT_ENERGY if Cfg.SUN else 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if (Cfg.SUN and Cfg.SUN_FILMIC) else Environment.TONE_MAPPER_LINEAR
	if Cfg.SUN and Cfg.SUN_FILMIC:   # F9: a little more contrast, colours not too loud
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.1
		env.adjustment_saturation = 0.95
	env.tonemap_exposure = Cfg.EXPOSURE
	env.fog_enabled = Cfg.FOG   # F10: false = no fog
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	if Cfg.SUN:   # F8: real sun
		sun.rotation_degrees = Vector3(-Cfg.SUN_ELEVATION, Cfg.SUN_AZIMUTH, 0.0)
		sun.light_color = Cfg.SUN_COLOR
		sun.light_energy = Cfg.SUN_ENERGY
		sun.light_angular_distance = 2.0   # size of the sun disc in the sky (real sun 0.5, bigger is easier to see)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # F10: the sun disc comes from the sky shader
		sun.shadow_enabled = Cfg.SHADOWS
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # one split = the cheapest
		sun.directional_shadow_max_distance = Cfg.SHADOW_DISTANCE
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 1.0
		sun.shadow_blur = 1.6   # F9: softer shadow edge (the blocky edge in the screenshot)
	else:
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.light_energy = 0.55
		sun.shadow_enabled = false
	sun_light = sun
	add_child(sun)
	if Cfg.DAY_NIGHT:   # F11
		daynight = DayNight.new()
		daynight.setup(sun, env, sky_shader_mat)


func _start_game(char_path: String, anim_prefix: String = "res://characters/anims/boy_anims") -> void:
	await _step(0.15, "Building the world...")
	_make_environment()
	world = FxMapScript.new()   # the Fx99 map is the only world (fx_map.gd)
	add_child(world)
	world.build()
	var start: Vector3 = world.spawn

	await _step(0.5, "Spawning...")
	player = PlayerScript.new()
	player.position = start
	add_child(player)
	var model := _load_scene(char_path)
	player.anim_prefix = anim_prefix
	if model != null:
		player.use_model(model)
	tractor = TractorScript.new()
	tractor.position = start + Vector3(5, -0.95, -3)
	add_child(tractor)
	tractor.setup_ground(Callable(world, "height_at"))
	heli = HeliScript.new()
	heli.position = start + Vector3(-9, 0, -4)
	heli.rotation.y = 0.6
	heli.area_check = Callable(world, "contains")
	add_child(heli)
	_spawn_cows(start)

	await _step(0.75, "Preparing controls...")
	rig = CameraRigScript.new()
	rig.ground = Callable(world, "height_at")
	add_child(rig)
	rig.set_target(player)

	hud = HudScript.new()
	layer.add_child(hud)
	touch = TouchScript.new()
	layer.add_child(touch)
	touch.hidden_ids = ["hitch", "poi", "swap", "reload"]   # v_016: SWAP and RELOAD are replaced by the gun boxes (tap the big box = reload)   # buttons of the farm game that Beyond the Crash does not use
	touch.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))
	touch.jump_pressed.connect(func() -> void: player.jump())
	touch.run_pressed.connect(func() -> void: player.toggle_run())
	touch.action_pressed.connect(_on_action)

	shooter = ShooterScript.new()
	add_child(shooter)
	shooter.hud = hud
	shooter.setup(self, player, rig, touch, world)
	hud.shooter = shooter
	hud.main = self
	touch.reload_pressed.connect(shooter.reload)
	touch.swap_pressed.connect(shooter.swap_weapon)
	touch.gun_slot_pressed.connect(shooter.equip)   # v_016: gun boxes / empty hands
	touch.bag_pressed.connect(shooter.toggle_bag)
	touch.sleep_pressed.connect(func() -> void:
		var bench := _bench_near_player()   # v_039: next to a bench the same button sits down
		if bench != null and not player.sleeping:
			player.sit_on_bench(bench)
		else:
			player.toggle_sleep())   # v_026: lie down / get up

	build = BuildScript.new()
	add_child(build)
	build.setup(self, player, rig, touch, shooter, hud, world)
	touch.slot_pressed.connect(build.select_block)
	touch.hotbar_n = 0   # v_021: build.gd sets it every frame (only the blocks you own)
	bag_ui = BagUiScript.new()   # v_043: full BAG screen (above the touch buttons, below the gear menu)
	bag_ui.main = self
	bag_ui.shooter = shooter
	layer.add_child(bag_ui)

	if Cfg.COMBAT:   # v_007: bandits, health, combat HUD (switch: config.gd)
		combat = CombatScript.new()
		add_child(combat)
		combat.setup(self, player, rig, touch, layer)

	heli_ui = HeliUiScript.new()
	layer.add_child(heli_ui)
	heli_ui.exit_pressed.connect(_leave_heli)
	heli_ui.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))
	heli_ui.touch = touch   # v_015: the 3 helicopter buttons use place / size / opacity from the HUD editor

	horn = _make_horn()

	# v_015: HUD editor + gear menu. They are added LAST in the layer, so they get every touch before the game buttons do.
	hud_editor = HudEditorScript.new()
	hud_editor.main = self
	hud_editor.touch = touch
	hud_editor.heli_ui = heli_ui
	layer.add_child(hud_editor)
	settings_menu = SettingsMenuScript.new()
	settings_menu.main = self
	settings_menu.editor = hud_editor
	settings_menu.visible = false   # hidden until the game is ready (_ready)
	layer.add_child(settings_menu)
	hud_editor.closed.connect(settings_menu.on_editor_closed)
	tutorial = TutorialScript.new()   # v_047: added last in the layer so its SKIP buttons get the touch first; it never blocks the game
	layer.add_child(tutorial)
	tutorial.setup(self)

	if Cfg.DEBUG_OVERLAY:   # v1.1: small info text (FPS, position ...). Switch: scripts/config.gd
		debug_overlay = DebugOverlayScript.new()
		debug_overlay.main = self
		layer.add_child(debug_overlay)
		debug_overlay.set_value("world", "BEYOND THE CRASH MAP   %d m" % int(world.map_half * 2.0))
		debug_overlay.set_value("flora", FloraScript.self_test())   # F2
		debug_overlay.set_value("ground", BiomeScript.report)   # F16

	if Cfg.COCONUTS:   # F7: coconut palms on all beaches (switch: config.gd)
		var coco_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("coconut", s)
		CoconutScript.place_all(world, coco_report)

	if Cfg.SUN and debug_overlay != null:   # F8
		debug_overlay.set_value("sun", "elev %d az %d  shadows %s %d m" % [int(Cfg.SUN_ELEVATION), int(Cfg.SUN_AZIMUTH), "ON" if Cfg.SHADOWS else "off", int(Cfg.SHADOW_DISTANCE)])

	if Cfg.MOUNTAIN and debug_overlay != null:   # F6
		debug_overlay.set_value("mountain", world.mountain_info)

	if Cfg.WARMUP:   # v1.1 step3: draw everything once while the loading screen is still on top
		await WarmupScript.run(self)


# two-note horn made from math (no sound file needed). Loops while the HORN button is held.
func _make_horn() -> AudioStreamPlayer:
	var rate := 22050
	var n := 4410   # 0.2 s = exactly 60 cycles of 300 Hz and 80 cycles of 400 Hz, so the loop has no click
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := 0.0
		for f in [300.0, 400.0]:
			v += sin(TAU * f * t) + 0.5 * sin(TAU * 2.0 * f * t) + 0.25 * sin(TAU * 3.0 * f * t)
		data.encode_s16(i * 2, int(clampf(v * 0.3, -1.0, 1.0) * 22000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.volume_db = -4.0
	add_child(pl)
	return pl


# ---------------------------------------------------------------- helpers for the HUD

func actor_position() -> Vector3:
	if flying:
		return heli.global_position
	if driving:
		return tractor.global_position
	return player.global_position


func map_label() -> String:
	return "Beyond the Crash"   # v_044: was "Fx99" (old project name)


# ---------------------------------------------------------------- get in / out

func _near_tractor() -> bool:
	return player.global_position.distance_to(tractor.global_position) < 4.5


func _near_heli() -> bool:
	return player.global_position.distance_to(heli.global_position) < 6.0


func _leave_heli() -> void:
	if not flying or not heli.on_ground():
		return
	flying = false
	heli.stop_flight()
	heli_ui.release_all()
	heli_ui.visible = false
	touch.visible = true
	var side: Vector3 = heli.global_transform.basis.x * -3.2
	player.stand(self, heli.global_position + side + Vector3(0, 1.0, 0))
	rig.set_target(player)
	touch.release_all()


func _on_action() -> void:
	if flying:
		return
	if not driving and _near_heli():
		flying = true
		player.sit(heli.seat)
		heli.start_flight()
		heli_ui.visible = true
		touch.visible = false
		touch.release_all()
		rig.set_target(heli, 17.0, 3.0, true)
		return
	if driving:
		if absf(tractor.speed) > 1.5:
			return
		driving = false
		horn.stop()
		tractor.stop_inputs()
		var side: Vector3 = tractor.global_transform.basis.x * -2.3
		player.stand(self, tractor.global_position + side + Vector3(0, 1.0, 0))
		rig.set_target(player)
		touch.release_all()
	elif _near_tractor():
		driving = true
		player.sit(tractor.seat)
		rig.set_target(tractor, 6.5, 2.0, true)   # v10 tractor camera
		touch.release_all()


# fell out of the world: back to the start
# cows (cow.gd): a small herd that stands near the start (first step: standing only)
var cows: Array = []
const COW_SPOTS := [Vector2(14, 10), Vector2(18, 15), Vector2(11, 17), Vector2(22, 9)]   # metres from the start (x, z)
func _spawn_cows(start: Vector3) -> void:
	for i in COW_SPOTS.size():
		var c := Cow.new()
		add_child(c)
		var sp: Vector2 = COW_SPOTS[i]
		c.area_check = Callable(world, "contains")
		c.setup(Callable(world, "height_at"), start.x + sp.x, start.z + sp.y, randf() * TAU)
		cows.append(c)


func _respawn_player() -> void:
	if flying:
		flying = false
		heli.stop_flight()
		heli_ui.release_all()
		heli_ui.visible = false
		touch.visible = true
	if driving:
		driving = false
		horn.stop()
		tractor.stop_inputs()
	player.stand(self, world.spawn)
	rig.set_target(player)
	touch.release_all()


# ---------------------------------------------------------------- per frame

func _physics_process(_delta: float) -> void:
	if not _game_ready:
		return
	# safety net: anything that fell out of the world comes back to the start
	if not driving and not flying and player.global_position.y < -30.0:
		_respawn_player()
	if tractor.global_position.y < -30.0:
		tractor.global_position = world.spawn + Vector3(5, 0.5, -3)
		tractor.speed = 0.0
		tractor.reset_physics_interpolation()
	if heli.global_position.y < -30.0 and not flying:
		heli.global_position = world.spawn + Vector3(-9, 1.0, -4)
		heli.reset_physics_interpolation()
	# no fuel system in the demo
	tractor.fuel = tractor.fuel_cap
	heli.fuel = heli.fuel_cap

	player.cam_yaw = rig.yaw
	if combat != null and not combat.can_run():   # v_020: too hungry = walking only
		player.running = false
	shooter.holstered = touch.build_mode
	shooter.firing = bool(touch.held["fire"]) and not touch.blocked and not touch.build_mode and not (combat != null and combat.dead)
	if combat != null:
		combat.firing = shooter.firing
	if flying:
		var a: Vector3 = heli_ui.axes()
		heli.turn = a.x
		heli.fwd = a.y
		heli.lift = a.z
		heli_ui.can_exit = heli.on_ground() and absf(heli.speed) < 1.5
	elif driving:
		tractor.gas = touch.held["gas"]
		tractor.brake = touch.held["brake"]
		tractor.steer = float(touch.held["right"]) - float(touch.held["left"])
	else:
		player.move_dir = Vector2.ZERO if (combat != null and combat.dead) else touch.move_dir


# v_039: the closest bench within 2.2 m (flat distance) of the character, or null (checked 5 times a second)
var _bench_t := 0.0
var _bench_cache: Node3D
func _bench_near_player() -> Node3D:
	var now := Time.get_ticks_msec()
	if now - int(_bench_t) < 200:
		return _bench_cache
	_bench_t = float(now)
	_bench_cache = null
	if player == null or driving or flying or player.seated:
		return null
	var best := 2.2
	var pp: Vector3 = player.global_position
	for b in get_tree().get_nodes_in_group("bench"):
		var d := Vector2(b.global_position.x - pp.x, b.global_position.z - pp.z).length()
		if d < best and absf(b.global_position.y - (pp.y - 0.8)) < 1.5:
			best = d
			_bench_cache = b
	return _bench_cache


var _cloud_t := 0.0   # F10: cloud clock


func _process(_delta: float) -> void:
	if touch != null and player != null:
		touch.sleep_text = "WAKE" if player.sleeping else ("SIT" if _bench_near_player() != null else "SLEEP")   # v_026, v_039
	if daynight != null:   # F11: sun, sky, light colours follow the clock
		daynight.update(_delta if _game_ready else 0.0)   # clock is frozen while loading: the game always starts at Cfg.START_HOUR (06:00)
		if debug_overlay != null:
			debug_overlay.set_value("time", daynight.clock_text())
	if daynight != null and Cfg.LIGHTS and _game_ready:   # v_002: headlights while driving / flying at dusk and night
		var dark: bool = daynight.sun_elev < Cfg.LIGHT_ON_ELEV
		tractor.set_lights(driving and dark)
		heli.set_lights(flying and dark)
	if sky_shader_mat != null and Cfg.CLOUDS:   # F10: clouds drift
		_cloud_t += _delta * Cfg.CLOUD_SPEED
		sky_shader_mat.set_shader_parameter("cloud_time", _cloud_t)
	if not _game_ready:
		return
	touch.run_on = player.running
	touch.swap_text = shooter.weapon_name()
	for gi in ["gun1", "gun2"]:   # v_016: the gun boxes show the gun of the slot and which one is in the hand
		var sl := 0 if gi == "gun1" else 1
		var wi: int = int(shooter.slots[sl])
		touch.slot_view[gi] = {"filled": wi >= 0, "active": shooter.hand == sl, "icon": (_axe_icon if wi == 1 else _gun_icon), "name": String(shooter.WEAPONS[wi]["name"]) if wi >= 0 else ""}
	touch.slot_view["hands"] = {"filled": true, "active": shooter.hand < 0}
	touch.slot_view["main"] = {"armed": shooter.hand >= 0, "mag": int(shooter.mag[0]), "mag_max": int(shooter.WEAPONS[shooter.cur]["mag"]),
		"reloading": shooter.reloading, "reload_f": 1.0 - clampf(shooter.reload_t / maxf(shooter.reload_total, 0.01), 0.0, 1.0),
		"icon": (_axe_icon if shooter.cur == 1 else _gun_icon), "melee": shooter.hand >= 0 and bool(shooter.WEAPONS[shooter.cur].get("melee", false))}
	touch.next_text = build.block_name()
	touch.drive_mode = driving
	touch.work_available = false
	touch.seed_available = false
	if flying:
		hud.info_text = "%d km/h   alt %d m" % [int(round(heli.kmh())), int(round(heli.height()))]
		return
	if driving:
		hud.info_text = "%d km/h" % int(round(tractor.kmh()))
		if touch.held["horn"] and not horn.playing:
			horn.play()
		elif not touch.held["horn"] and horn.playing:
			horn.stop()
		touch.action_visible = true
		touch.action_text = "GET OUT"
		touch.action_enabled = absf(tractor.speed) < 1.5
	else:
		hud.info_text = ""
		var near := _near_tractor() or _near_heli()
		touch.action_visible = near
		touch.action_text = "GET IN"
		touch.action_enabled = near
