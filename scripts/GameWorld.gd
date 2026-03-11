extends Node2D

@onready var water_cycle: Node              = $WaterCycle
@onready var map_container: Node2D          = $MapContainer
@onready var hud: CanvasLayer               = $HUD
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var ap_timer: Timer                = $APTimer

var _tile_scene: PackedScene = preload("res://scenes/MapTile.tscn")
var _tiles: Array[Node2D] = []
var _placing_solution: int = -1
var action_points: int = 3
var _is_mobile: bool
var _prev_state: Dictionary = {}

const MAX_AP := 6
const SOLUTION_COSTS := {0: 2, 1: 2, 2: 1, 3: 3, 4: 4}
const SOLUTION_TRUST := {0: 3.0, 1: 5.0, 2: 2.0, 3: 4.0, 4: 2.0}

const MAP_COLS := 20
const MAP_ROWS := 15

const ISO_HALF_W  := 48
const ISO_HALF_H  := 24
const ISO_ORIGIN_X := MAP_ROWS * ISO_HALF_W + 20   # = 740
const ISO_ORIGIN_Y := 80

const MAP_LAYOUT := [
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],  # 0 Table Mountain peaks
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],  # 1 Mountain slopes
	[0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0],  # 2 Mountain/Catchment mix
	[0,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,0],  # 3 Catchment zones
	[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],  # 4 Thwaterskloof
	[1,1,2,2,1,1,1,2,2,1,1,2,2,1,1,1,2,2,1,1],  # 5 Catchment/urban fringe
	[1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],  # 6 Urban edges
	[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2],  # 7 Urban core (CBD)
	[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2],  # 8 City centre
	[2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2],  # 9 Southern suburbs
	[2,2,3,2,2,2,2,3,3,2,2,3,3,2,2,2,2,3,3,2],  # 10 Coastal/suburban mix
	[2,3,3,3,2,2,3,3,3,3,3,3,3,3,2,2,3,3,3,2],  # 11 Coastal urbanising
	[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],  # 12 Coastal strip
	[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],  # 13 Beach
	[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],  # 14 Ocean
]

var _overlay: ColorRect
var _overlay_label: Label
var splash_particles: CPUParticles2D


# ── Ripple effect inner class ─────────────────────────────────────────────────

class RippleEffect extends Node2D:
	var _rings: Array = []  # Array of {radius:float, alpha:float, speed:float}
	var _life: float = 0.0

	func init(rings_data: Array) -> void:
		_rings = rings_data

	func _process(delta: float) -> void:
		_life += delta
		var any_visible := false
		for ring in _rings:
			ring["radius"] += delta * ring["speed"]
			ring["alpha"] = maxf(0.0, ring["alpha"] - delta * 1.4)
			if ring["alpha"] > 0.0:
				any_visible = true
		queue_redraw()
		if not any_visible:
			queue_free()

	func _draw() -> void:
		for ring in _rings:
			if ring["alpha"] > 0.01:
				draw_arc(Vector2.ZERO, ring["radius"], 0.0, TAU, 32,
					Color(0.3, 0.85, 1.0, ring["alpha"]), 3.5)

# ── Camera ───────────────────────────────────────────────────────────────────
@onready var _camera: Camera2D = $Camera2D

const ZOOM_LEVELS := [
	Vector2(0.65, 0.65),   # 0 overview (fits full map width)
	Vector2(1.20, 1.20),   # 1 medium
	Vector2(2.00, 2.00),   # 2 close
]
const ZOOM_MIN := Vector2(0.45, 0.45)
const ZOOM_MAX := Vector2(3.0, 3.0)
var _zoom_idx: int = 2   # start at close zoom on urban zone

# ── Desktop pan state ────────────────────────────────────────────────────────
var _is_mouse_dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_cam: Vector2

# ── Touch state machine ──────────────────────────────────────────────────────
var _touch_state: int = 0
var _touches: Dictionary = {}
var _pinch_prev_dist: float = 0.0
var _touch_pan_prev: Vector2

# ── Double-tap detection ─────────────────────────────────────────────────────
var _last_tap_time: float = 0.0
var _last_tap_screen_pos: Vector2
const DOUBLE_TAP_SECS   := 0.35
const DOUBLE_TAP_PIXELS := 60.0

const ARROW_PAN_SPEED := 500.0

const ZONE_CENTERS := {
	0: Vector2(1172, 320),  # Mountain  avg(col=9.5, row=0.5)
	1: Vector2(1028, 392),  # Catchment avg(col=9.5, row=3.5)
	2: Vector2(836,  488),  # Urban     avg(col=9.5, row=7.5)
	3: Vector2(596,  608),  # Coastal   avg(col=9.5, row=12.5)
}


func _ready() -> void:
	_build_map()
	_build_overlay()
	_build_splash_particles()
	_build_vignette()
	_setup_camera()

	water_cycle.day_ticked.connect(_on_day_ticked)
	water_cycle.event_triggered.connect(_on_event_triggered)
	water_cycle.game_over.connect(_on_game_over)
	water_cycle.game_won.connect(_on_game_won)
	hud.solution_selected.connect(_on_solution_selected)
	hud.minimap_clicked.connect(_on_minimap_clicked)
	hud.event_zone_pan.connect(_on_event_zone_pan)
	ap_timer.timeout.connect(_on_ap_regen)

	hud.init_minimap_layout(MAP_LAYOUT)
	_update_hud(water_cycle.get_state())

	rain_particles.emitting = false
	rain_particles.amount = 0

	_detect_platform()


func _setup_camera() -> void:
	_camera.zoom = Vector2(2.0, 2.0)
	_camera.limit_left   = 0
	_camera.limit_top    = 0
	_camera.limit_right  = 1800
	_camera.limit_bottom = 1050
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed   = 8.0
	_camera.position = Vector2(836.0, 488.0)  # urban zone


func _detect_platform() -> void:
	_is_mobile = OS.has_feature("mobile")
	hud.show_platform_hint(_is_mobile)


func _build_map() -> void:
	for r in range(MAP_LAYOUT.size()):
		var row_data: Array = MAP_LAYOUT[r]
		for c in range(row_data.size()):
			var terrain: int = row_data[c]
			var tile: Node2D = _tile_scene.instantiate()
			map_container.add_child(tile)
			tile.setup(terrain, c, r)
			tile.position = Vector2(
				(c - r) * ISO_HALF_W + ISO_ORIGIN_X,
				(c + r) * ISO_HALF_H + ISO_ORIGIN_Y
			)
			tile.z_index = r * MAP_COLS + c
			tile.tile_clicked.connect(_on_tile_clicked)
			_tiles.append(tile)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.78)
	_overlay.size = Vector2(1080.0, 1920.0)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_overlay_label = Label.new()
	_overlay_label.size = Vector2(1000.0, 400.0)
	_overlay_label.position = Vector2(40.0, 760.0)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 72)
	_overlay_label.add_theme_color_override("font_color", Color.WHITE)
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	_overlay.add_child(_overlay_label)
	layer.add_child(_overlay)


func _build_splash_particles() -> void:
	splash_particles = CPUParticles2D.new()
	splash_particles.position = Vector2(540.0, 1360.0)
	splash_particles.direction = Vector2(0.0, -1.0)
	splash_particles.gravity = Vector2(0.0, 400.0)
	splash_particles.initial_velocity_min = 60.0
	splash_particles.initial_velocity_max = 140.0
	splash_particles.lifetime = 0.5
	splash_particles.color = Color(0.5, 0.75, 1.0, 0.6)
	splash_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	splash_particles.emission_rect_extents = Vector2(540.0, 0.0)
	splash_particles.emitting = false
	splash_particles.amount = 8
	add_child(splash_particles)


func _build_vignette() -> void:
	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 2
	add_child(vignette_layer)

	_add_vignette(vignette_layer, Vector2(0, 0), Vector2(1080, 220),
		Color(0, 0, 0, 0.65), Color(0, 0, 0, 0),
		Vector2(0, 0), Vector2(0, 1))
	_add_vignette(vignette_layer, Vector2(0, 1320), Vector2(1080, 140),
		Color(0, 0, 0, 0), Color(0, 0, 0, 0.45),
		Vector2(0, 0), Vector2(0, 1))
	_add_vignette(vignette_layer, Vector2(0, 0), Vector2(80, 960),
		Color(0, 0, 0, 0.35), Color(0, 0, 0, 0),
		Vector2(0, 0), Vector2(1, 0))
	_add_vignette(vignette_layer, Vector2(1000, 0), Vector2(80, 960),
		Color(0, 0, 0, 0), Color(0, 0, 0, 0.35),
		Vector2(0, 0), Vector2(1, 0))


func _add_vignette(parent: Node, pos: Vector2, sz: Vector2,
		c0: Color, c1: Color, from: Vector2, to: Vector2) -> void:
	var grad := Gradient.new()
	grad.set_color(0, c0)
	grad.set_color(1, c1)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width  = int(sz.x)
	tex.height = int(sz.y)
	tex.fill      = GradientTexture2D.FILL_LINEAR
	tex.fill_from = from
	tex.fill_to   = to
	var rect := TextureRect.new()
	rect.texture      = tex
	rect.position     = pos
	rect.size         = sz
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# ── MOUSE (desktop) ──────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if _placing_solution != -1:
						var ti := _screen_to_tile(event.position)
						if ti.x >= 0 and ti.x < MAP_COLS and ti.y >= 0 and ti.y < MAP_ROWS:
							_on_tile_clicked(_tiles[ti.y * MAP_COLS + ti.x])
						return
					_is_mouse_dragging = true
					_drag_start_mouse  = event.position
					_drag_start_cam    = _camera.position
				else:
					_is_mouse_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				_cycle_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_zoom(-1)

	elif event is InputEventMouseMotion and _is_mouse_dragging:
		var delta: Vector2 = (event.position - _drag_start_mouse) / _camera.zoom.x
		_camera.position = _drag_start_cam - delta

	# Trackpad pinch (macOS / laptop touchpad)
	elif event is InputEventMagnifyGesture:
		var new_zoom: Vector2 = (_camera.zoom * event.factor).clamp(ZOOM_MIN, ZOOM_MAX)
		_camera.zoom = new_zoom

	# ── KEYBOARD (desktop) ───────────────────────────────────────────────────
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _quick_select(0)
			KEY_2: _quick_select(1)
			KEY_3: _quick_select(2)
			KEY_4: _quick_select(3)
			KEY_5: _quick_select(4)
			KEY_SPACE: _toggle_pause()
			KEY_ESCAPE:
				if _placing_solution != -1:
					_cancel_placement()
					_zoom_to_idx(0)

	# ── TOUCH (mobile) ───────────────────────────────────────────────────────
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_touch_state = 1
				_touch_pan_prev = event.position
				# Iso tile click when placing
				if _placing_solution != -1:
					var ti := _screen_to_tile(event.position)
					if ti.x >= 0 and ti.x < MAP_COLS and ti.y >= 0 and ti.y < MAP_ROWS:
						_on_tile_clicked(_tiles[ti.y * MAP_COLS + ti.x])
					return
				# Double-tap check
				var now := Time.get_ticks_msec() / 1000.0
				if (now - _last_tap_time < DOUBLE_TAP_SECS
						and event.position.distance_to(_last_tap_screen_pos) < DOUBLE_TAP_PIXELS):
					_on_double_tap(event.position)
				_last_tap_time = now
				_last_tap_screen_pos = event.position
			elif _touches.size() == 2:
				_touch_state = 2
				if _placing_solution != -1:
					_cancel_placement()
					_zoom_to_idx(0)
				var keys := _touches.keys()
				_pinch_prev_dist = _touches[keys[0]].distance_to(_touches[keys[1]])
		else:
			_touches.erase(event.index)
			if _touches.size() == 1:
				_touch_state = 1
				_touch_pan_prev = _touches[_touches.keys()[0]]
				_pinch_prev_dist = 0.0
			elif _touches.size() == 0:
				_touch_state = 0
				_pinch_prev_dist = 0.0

	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touch_state == 1 and event.index == 0:
			# Single-finger pan
			_camera.position -= event.relative / _camera.zoom.x
		elif _touch_state == 2 and _touches.size() == 2:
			# Pinch zoom
			var keys := _touches.keys()
			var new_dist: float = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])
			if _pinch_prev_dist > 0.0:
				var factor: float = new_dist / _pinch_prev_dist
				_camera.zoom = (_camera.zoom * factor).clamp(ZOOM_MIN, ZOOM_MAX)
			_pinch_prev_dist = new_dist


func _process(delta: float) -> void:
	# Arrow / WASD pan (desktop)
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): pan.x += 1
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): pan.y -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): pan.y += 1
	if pan != Vector2.ZERO:
		_camera.position += pan * (ARROW_PAN_SPEED / _camera.zoom.x) * delta

	# Particles follow camera viewport centre
	var cp := _camera.global_position
	rain_particles.global_position   = cp
	splash_particles.global_position = cp + Vector2(0.0, 400.0 / _camera.zoom.y)

	# Feed camera state to mini-map
	hud.update_minimap(_camera.position, _camera.zoom)


# ── Zoom + navigation helpers ─────────────────────────────────────────────────

func _cycle_zoom(dir: int) -> void:
	_zoom_idx = clampi(_zoom_idx + dir, 0, ZOOM_LEVELS.size() - 1)
	_zoom_to_idx(_zoom_idx)


func _zoom_to_idx(idx: int) -> void:
	_zoom_idx = idx
	var tw := create_tween()
	tw.tween_property(_camera, "zoom", ZOOM_LEVELS[idx], 0.3).set_trans(Tween.TRANS_CUBIC)


func _on_double_tap(screen_pos: Vector2) -> void:
	var half := Vector2(1080.0, 1920.0) / 2.0
	var world_pos := _camera.position + (screen_pos - half) / _camera.zoom.x
	var tw := create_tween()
	tw.tween_property(_camera, "position", world_pos, 0.35).set_trans(Tween.TRANS_CUBIC)
	_zoom_to_idx(1)


func _pan_to_world(target: Vector2, zoom_idx: int = -1) -> void:
	var tw := create_tween()
	tw.tween_property(_camera, "position", target, 0.4).set_trans(Tween.TRANS_CUBIC)
	if zoom_idx >= 0:
		_zoom_to_idx(zoom_idx)


func _quick_select(idx: int) -> void:
	if _placing_solution == idx:
		_cancel_placement()
	else:
		hud.set_placement_mode(idx)
		_on_solution_selected(idx)


func _toggle_pause() -> void:
	water_cycle.paused = not water_cycle.paused
	hud.show_pause_state(water_cycle.paused)


func _cancel_placement() -> void:
	_placing_solution = -1
	hud.clear_placement_mode()
	_clear_all_highlights()
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)


func _spawn_ripple(world_pos: Vector2) -> void:
	var effect := RippleEffect.new()
	effect.position = world_pos
	effect.z_index = 9999
	effect.init([
		{"radius": 8.0,  "alpha": 0.95, "speed": 90.0},
		{"radius": 20.0, "alpha": 0.70, "speed": 70.0},
		{"radius": 38.0, "alpha": 0.45, "speed": 55.0},
	])
	map_container.add_child(effect)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var half := Vector2(1080.0, 1920.0) * 0.5
	var world := _camera.position + (screen_pos - half) / _camera.zoom.x
	var dx := world.x - float(ISO_ORIGIN_X)
	var dy := world.y - float(ISO_ORIGIN_Y)
	var col := (dx / float(ISO_HALF_W) + dy / float(ISO_HALF_H)) * 0.5
	var row := (dy / float(ISO_HALF_H) - dx / float(ISO_HALF_W)) * 0.5
	return Vector2i(roundi(col), roundi(row))


func _on_minimap_clicked(norm_pos: Vector2) -> void:
	var iso_w := float(MAP_COLS + MAP_ROWS) * float(ISO_HALF_W)
	var iso_h := float(MAP_COLS + MAP_ROWS) * float(ISO_HALF_H)
	var target := norm_pos * Vector2(iso_w, iso_h)
	_pan_to_world(target)


func _on_event_zone_pan(terrain_type: int) -> void:
	_pan_to_world(ZONE_CENTERS[terrain_type], 1)


func _update_tile_alerts(state: Dictionary) -> void:
	var sc: float = state["scarcity"]
	var fl: float = state["flood_risk"]
	var wf: float = state["wildfire_danger"]
	for tile in _tiles:
		var tint := Color.TRANSPARENT
		match tile.terrain:
			0:  if wf > 60.0: tint = Color(1.0, 0.4, 0.0, (wf - 60.0) / 40.0 * 0.4)
			1:  if sc > 65.0: tint = Color(1.0, 0.8, 0.0, (sc - 65.0) / 35.0 * 0.35)
			2:  if sc > 65.0: tint = Color(1.0, 0.6, 0.1, (sc - 65.0) / 35.0 * 0.3)
			3:  if fl > 60.0: tint = Color(0.2, 0.5, 1.0, (fl - 60.0) / 40.0 * 0.35)
		tile.set_risk_alert(tint)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_tile_clicked(tile: Node2D) -> void:
	if _placing_solution == -1:
		return

	if tile.can_accept(_placing_solution) and action_points >= SOLUTION_COSTS[_placing_solution]:
		action_points -= SOLUTION_COSTS[_placing_solution]
		tile.place_solution(_placing_solution)
		water_cycle.add_solution(_placing_solution)
		water_cycle.trust = clampf(water_cycle.trust + SOLUTION_TRUST[_placing_solution], 0.0, 100.0)
		_update_hud(water_cycle.get_state())
		_spawn_ripple(tile.global_position)
		hud.show_solution_feedback(_placing_solution)
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)

	_placing_solution = -1
	hud.clear_placement_mode()
	_clear_all_highlights()


func _on_solution_selected(sol_id: int) -> void:
	if sol_id == -1:
		_placing_solution = -1
		_clear_all_highlights()
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)
		return
	_placing_solution = sol_id
	_show_placement_highlights(sol_id)
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_CROSS)


func _on_ap_regen() -> void:
	action_points = mini(action_points + 1, MAX_AP)
	_update_hud(water_cycle.get_state())


func _on_day_ticked(state: Dictionary) -> void:
	if not _prev_state.is_empty():
		hud.show_gauge_deltas(
			state["scarcity"]        - _prev_state["scarcity"],
			state["flood_risk"]      - _prev_state["flood_risk"],
			state["wildfire_danger"] - _prev_state["wildfire_danger"],
			state["trust"]           - _prev_state["trust"]
		)
	_prev_state = state.duplicate()

	var rf: float = state["rainfall_mm"]
	rain_particles.amount = int(rf * 3.0)
	rain_particles.emitting = rf > 0.0
	splash_particles.amount = int(rf * 1.5)
	splash_particles.emitting = rf > 2.0
	_update_hud(state)
	_update_tile_alerts(state)


func _on_event_triggered(event: Dictionary) -> void:
	hud.show_event(event)
	if event.has("ap_bonus"):
		action_points = mini(action_points + event["ap_bonus"], MAX_AP)
		_update_hud(water_cycle.get_state())


func _on_game_over(reason: String) -> void:
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)
	_show_overlay("GAME OVER\n\n" + reason + "\n\nReturning to menu…")
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))


func _on_game_won() -> void:
	DisplayServer.cursor_set_shape(DisplayServer.CURSOR_ARROW)
	GameManager.add_score(1000 + int(water_cycle.trust) * 10)
	_show_overlay("YOU SURVIVED!\n\nCape Town made it to the rains.\n\nReturning to menu…")
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))


# ── Helpers ───────────────────────────────────────────────────────────────────

func _update_hud(state: Dictionary) -> void:
	hud.update_state(state, action_points)


func _show_placement_highlights(sol_id: int) -> void:
	for tile in _tiles:
		if tile.can_accept(sol_id):
			tile.set_highlight(1)
		else:
			tile.set_highlight(2)


func _clear_all_highlights() -> void:
	for tile in _tiles:
		tile.set_highlight(0)


func _show_overlay(text: String) -> void:
	_overlay_label.text = text
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, 0.8)
