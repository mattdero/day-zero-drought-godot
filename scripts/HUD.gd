extends CanvasLayer

signal solution_selected(solution_id: int)
signal minimap_clicked(norm_pos: Vector2)
signal event_zone_pan(terrain_type: int)

# ── Node references (matched to HUD.tscn) ──────────────────────────────────
@onready var day_label: Label            = $TopBar/DayLabel
@onready var day_sub_label: Label        = $TopBar/DaySubLabel
@onready var scarcity_bar: ProgressBar   = $GaugeBar/ScarcityRow/Bar
@onready var flood_bar: ProgressBar      = $GaugeBar/FloodRow/Bar
@onready var wildfire_bar: ProgressBar   = $GaugeBar/WildfireRow/Bar
@onready var ap_container: HBoxContainer = $ResourceRow/APDots
@onready var trust_label: Label          = $ResourceRow/TrustLabel
@onready var rain_label: Label           = $ResourceRow/RainLabel
@onready var aquifer_label: Label        = $ResourceRow/AquiferLabel
@onready var event_log: Label            = $EventLog
@onready var solution_bar: HBoxContainer = $SolutionBar/Cards

# ── Internal state ──────────────────────────────────────────────────────────
var _ap_dots: Array[Panel] = []
var _ap_dot_styles: Array[StyleBoxFlat] = []
var _ap_dot_tweens: Array = []
var _solution_cards: Array[Control] = []
var _card_styles: Array[StyleBoxFlat] = []
var _selected_solution: int = -1
var _event_lines: Array[String] = []

var _bar_tweens: Array = [null, null, null]
var _day_tween: Tween

var _minimap: MiniMap
var _hint_label: Label
var _pause_label: Label
var _last_event_terrain: int = 2

const SOLUTION_DATA := [
	{"name": "Swales",           "ap": 2, "desc": "Redirect runoff\ninto soil channels"},
	{"name": "Rain Gardens",     "ap": 2, "desc": "Filter water\nthrough native plants"},
	{"name": "Native Grasses",   "ap": 1, "desc": "Reduce fire risk\n& improve soil"},
	{"name": "Terraces",         "ap": 3, "desc": "Step planting\nslows runoff"},
	{"name": "Retention\nPonds", "ap": 4, "desc": "Store & filter\nsurface water"},
]

const EVENT_TERRAIN := {
	"wildfire_outbreak": 0,
	"heavy_rain":        1,
	"council_support":   2,
	"volunteers":        2,
	"dev_pressure":      2,
	"heatwave":          3,
}

const SOLUTION_EFFECT_DESC := {
	0: "Redirects runoff into soil\n→ less scarcity & flood risk",
	1: "Filters water through native plants\n→ recharges aquifer",
	2: "Restores biotic pump\n→ boosts rainfall & cuts wildfire",
	3: "Step planting slows runoff\n→ less flooding & erosion",
	4: "Stores & filters surface water\n→ major flood/scarcity cut",
}

const TIPS_CONTENT := [
	["MOUNTAIN tiles (grey)", "Use Swales or Terraces to slow runoff.\nNative Grasses prevent wildfire."],
	["CATCHMENT tiles (green)", "All solutions work here.\nNative Grasses restore the biotic pump."],
	["URBAN tiles (concrete)", "Rain Gardens infiltrate stormwater.\nRetention Ponds store flood water."],
	["COASTAL tiles (blue)", "No solutions available — protect\nthe land zones above."],
	["STRATEGY", "Keep aquifer high → scarcity falls.\nBalance infiltration with vegetation.\nSwales (2AP) = best early value."],
]

# StyleBox refs for gauge bars
var _scarcity_style: StyleBoxFlat
var _flood_style: StyleBoxFlat
var _wildfire_style: StyleBoxFlat

# ── UX enhancement state ─────────────────────────────────────────────────────
var _popup_layer: CanvasLayer

var _recommend_bg: ColorRect
var _recommend_label: Label
var _recommend_tween: Tween

var _tips_btn: Button
var _tips_panel: CanvasLayer
var _tips_visible: bool = false

var _tutorial_layer: CanvasLayer
var _tutorial_overlay: ColorRect
var _tutorial_title: Label
var _tutorial_body: Label
var _tutorial_btn: Button
var _tutorial_step: int = 0
var _tutorial_active: bool = false

var _prev_trust: float = 75.0
var _card_urgency_tweens: Array = []
var _gauge_flash_tweens: Array = [null, null, null]
var _urgent_sol_id: int = -1


# ── MiniMap inner class ───────────────────────────────────────────────────────
class MiniMap extends Control:
	signal clicked(norm_pos: Vector2)

	var cam_pos: Vector2 = Vector2.ZERO
	var cam_zoom: Vector2 = Vector2.ONE
	var map_layout: Array = []

	const CELL  := 9.0
	const MAP_C := 20
	const MAP_R := 15
	const T_COLORS := {
		0: Color(0.35, 0.28, 0.22),
		1: Color(0.22, 0.55, 0.22),
		2: Color(0.42, 0.47, 0.55),
		3: Color(0.15, 0.42, 0.72),
	}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.12, 0.9))
		if map_layout.is_empty():
			return
		for r in MAP_R:
			for c in MAP_C:
				var t: int = map_layout[r][c]
				draw_rect(Rect2(c * CELL, r * CELL, CELL - 1, CELL - 1), T_COLORS[t])
		# Viewport rect overlay
		var ww := float(MAP_C + MAP_R) * 48.0   # iso world width  = 1680
		var wh := float(MAP_C + MAP_R) * 24.0   # iso world height = 840
		var vw := 1080.0 / cam_zoom.x;  var vh := 1920.0 / cam_zoom.y
		var rx := (cam_pos.x - vw * 0.5) / ww * MAP_C * CELL
		var ry := (cam_pos.y - vh * 0.5) / wh * MAP_R * CELL
		var rw := vw / ww * MAP_C * CELL;  var rh := vh / wh * MAP_R * CELL
		draw_rect(Rect2(rx, ry, rw, rh), Color(1, 1, 1, 0.75), false, 1.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			emit_signal("clicked", event.position / size)
		elif event is InputEventScreenTouch and event.pressed:
			emit_signal("clicked", event.position / size)


# ── Procedural solution card icon ─────────────────────────────────────────────
class SolutionIcon extends Control:
	var sol_id: int = 0

	func _draw() -> void:
		match sol_id:
			0:  # Swales — 3 wavy horizontal polylines
				var colors := [
					Color(0.3, 0.6, 1.0, 0.9),
					Color(0.4, 0.7, 1.0, 0.7),
					Color(0.2, 0.5, 0.9, 0.8),
				]
				for w in range(3):
					var points := PackedVector2Array()
					var base_y := 20.0 + w * 17.0
					for px in range(0, 81, 4):
						var py := base_y + sin(px * 0.22 + w * 1.2) * 7.0
						points.append(Vector2(float(px), py))
					draw_polyline(points, colors[w], 2.5)

			1:  # Rain Garden — filled circle + stem + 2 leaves
				draw_circle(Vector2(40, 22), 16.0, Color(0.15, 0.65, 0.25))
				draw_line(Vector2(40, 38), Vector2(40, 65), Color(0.1, 0.45, 0.1), 3.0)
				draw_colored_polygon(
					PackedVector2Array([Vector2(40, 50), Vector2(18, 42), Vector2(26, 58)]),
					Color(0.15, 0.55, 0.2))
				draw_colored_polygon(
					PackedVector2Array([Vector2(40, 48), Vector2(62, 40), Vector2(54, 56)]),
					Color(0.15, 0.55, 0.2))

			2:  # Native Grasses — 5 angled blades, alternating heights
				var blade_a := Color(0.65, 0.78, 0.15, 0.9)
				var blade_b := Color(0.55, 0.68, 0.1, 0.8)
				var x_pos  := [10.0, 24.0, 38.0, 52.0, 66.0]
				var heights := [45.0, 35.0, 50.0, 30.0, 42.0]
				var leans   := [-8.0, 6.0, -4.0, 10.0, -6.0]
				for i in range(5):
					var bx: float = x_pos[i]
					var c: Color = blade_a if i % 2 == 0 else blade_b
					draw_line(Vector2(bx, 70), Vector2(bx + leans[i], 70 - heights[i]), c, 2.5)

			3:  # Terraces — 3 stepped filled rectangles, brown/terracotta
				draw_rect(Rect2(5, 55, 70, 18),  Color(0.55, 0.35, 0.18))
				draw_rect(Rect2(15, 37, 55, 18), Color(0.48, 0.30, 0.15))
				draw_rect(Rect2(25, 20, 38, 18), Color(0.42, 0.26, 0.12))

			4:  # Retention Pond — 3 concentric circles, dark→mid→light blue
				draw_circle(Vector2(40, 42), 30.0, Color(0.05, 0.12, 0.35))
				draw_circle(Vector2(40, 42), 20.0, Color(0.1,  0.25, 0.55))
				draw_circle(Vector2(40, 42), 10.0, Color(0.2,  0.45, 0.8))


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Darker panel backgrounds
	($TopBar as ColorRect).color      = Color(0.02, 0.04, 0.09, 1.0)
	($SolutionBar as ColorRect).color = Color(0.04, 0.06, 0.11, 1.0)

	_setup_gauge_styles()
	_build_ap_dots()
	_build_solution_cards()
	_build_minimap()
	_build_hint_label()
	_build_event_click_area()
	_build_popup_layer()
	_build_recommendation_bar()
	_build_tips_panel()
	_build_tutorial()
	# init urgency tweens array
	for i in SOLUTION_DATA.size():
		_card_urgency_tweens.append(null)


func _setup_gauge_styles() -> void:
	_scarcity_style = StyleBoxFlat.new()
	_scarcity_style.bg_color = Color(0.15, 0.85, 0.35)
	scarcity_bar.add_theme_stylebox_override("fill", _scarcity_style)
	scarcity_bar.value_changed.connect(func(v: float) -> void:
		_scarcity_style.bg_color = _lerp_gauge_color(v,
			Color(0.15, 0.85, 0.35), Color(1.0, 0.6, 0.0), Color(1.0, 0.1, 0.1)))

	_flood_style = StyleBoxFlat.new()
	_flood_style.bg_color = Color(0.2, 0.4, 0.9)
	flood_bar.add_theme_stylebox_override("fill", _flood_style)
	flood_bar.value_changed.connect(func(v: float) -> void:
		_flood_style.bg_color = _lerp_gauge_color(v,
			Color(0.2, 0.4, 0.9), Color(0.5, 0.2, 0.8), Color(1.0, 0.1, 0.1)))

	_wildfire_style = StyleBoxFlat.new()
	_wildfire_style.bg_color = Color(0.9, 0.8, 0.1)
	wildfire_bar.add_theme_stylebox_override("fill", _wildfire_style)
	wildfire_bar.value_changed.connect(func(v: float) -> void:
		_wildfire_style.bg_color = _lerp_gauge_color(v,
			Color(0.9, 0.8, 0.1), Color(1.0, 0.45, 0.0), Color(1.0, 0.1, 0.1)))

	for bar in [scarcity_bar, flood_bar, wildfire_bar]:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.06, 0.10)
		bar.add_theme_stylebox_override("background", bg)


func _build_ap_dots() -> void:
	for i in range(6):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(28.0, 28.0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.9, 1.0) if i < 3 else Color(0.12, 0.13, 0.18)
		style.corner_radius_top_left    = 14
		style.corner_radius_top_right   = 14
		style.corner_radius_bottom_left  = 14
		style.corner_radius_bottom_right = 14
		dot.add_theme_stylebox_override("panel", style)
		ap_container.add_child(dot)
		_ap_dots.append(dot)
		_ap_dot_styles.append(style)
		_ap_dot_tweens.append(null)
		if i < 5:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(6.0, 0.0)
			ap_container.add_child(spacer)


func _build_solution_cards() -> void:
	for i in range(SOLUTION_DATA.size()):
		var data: Dictionary = SOLUTION_DATA[i]

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(190.0, 340.0)
		card.pivot_offset = Vector2(95.0, 170.0)

		var card_style := StyleBoxFlat.new()
		card_style.bg_color           = Color(0.08, 0.11, 0.17)
		card_style.border_color       = Color(0.18, 0.22, 0.32)
		card_style.border_width_left   = 2
		card_style.border_width_right  = 2
		card_style.border_width_top    = 2
		card_style.border_width_bottom = 2
		card_style.corner_radius_top_left    = 12
		card_style.corner_radius_top_right   = 12
		card_style.corner_radius_bottom_left  = 12
		card_style.corner_radius_bottom_right = 12
		card.add_theme_stylebox_override("panel", card_style)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		# Procedural icon (80×80)
		var icon := SolutionIcon.new()
		icon.sol_id = i
		icon.custom_minimum_size = Vector2(80.0, 80.0)
		vbox.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text = data["name"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

		var ap_lbl := Label.new()
		ap_lbl.text = "AP: %d" % data["ap"]
		ap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ap_lbl.add_theme_font_size_override("font_size", 16)
		ap_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))

		var desc_lbl := Label.new()
		desc_lbl.text = data["desc"]
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

		var btn := Button.new()
		btn.text = "PLACE"
		btn.custom_minimum_size = Vector2(150.0, 48.0)
		btn.add_theme_font_size_override("font_size", 18)
		var sol_id := i
		btn.pressed.connect(func() -> void: _on_card_pressed(sol_id))

		vbox.add_child(name_lbl)
		vbox.add_child(ap_lbl)
		vbox.add_child(desc_lbl)
		vbox.add_child(btn)
		card.add_child(vbox)
		solution_bar.add_child(card)

		_solution_cards.append(card)
		_card_styles.append(card_style)

		if i < SOLUTION_DATA.size() - 1:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(8.0, 0.0)
			solution_bar.add_child(sp)


func _build_minimap() -> void:
	_minimap = MiniMap.new()
	_minimap.position = Vector2(888.0, 12.0)
	_minimap.size     = Vector2(180.0, 135.0)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.clicked.connect(func(np: Vector2) -> void: emit_signal("minimap_clicked", np))
	add_child(_minimap)


func _build_hint_label() -> void:
	_hint_label = Label.new()
	_hint_label.position = Vector2(10.0, 415.0)
	_hint_label.size     = Vector2(1060.0, 36.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 22)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.0))
	add_child(_hint_label)

	_pause_label = Label.new()
	_pause_label.text = "⏸ PAUSED"
	_pause_label.position = Vector2(350.0, 940.0)
	_pause_label.size     = Vector2(380.0, 80.0)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.add_theme_font_size_override("font_size", 56)
	_pause_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 0.0))
	add_child(_pause_label)


func _build_event_click_area() -> void:
	var btn := Button.new()
	btn.flat = true
	btn.position = event_log.position
	btn.size     = Vector2(event_log.size.x, event_log.size.y)
	btn.pressed.connect(func() -> void: emit_signal("event_zone_pan", _last_event_terrain))
	add_child(btn)


func _build_popup_layer() -> void:
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 25
	add_child(_popup_layer)


func _build_recommendation_bar() -> void:
	var bar_container := Control.new()
	bar_container.position = Vector2(0.0, 1455.0)
	bar_container.size = Vector2(1080.0, 72.0)
	add_child(bar_container)

	# Top border line
	var border := ColorRect.new()
	border.color = Color(0.2, 0.3, 0.5, 1.0)
	border.position = Vector2(0.0, 0.0)
	border.size = Vector2(1080.0, 2.0)
	bar_container.add_child(border)

	_recommend_bg = ColorRect.new()
	_recommend_bg.color = Color(0.03, 0.05, 0.10, 0.92)
	_recommend_bg.position = Vector2(0.0, 2.0)
	_recommend_bg.size = Vector2(1080.0, 70.0)
	bar_container.add_child(_recommend_bg)

	# Icon label
	var icon_lbl := Label.new()
	icon_lbl.text = "●"
	icon_lbl.position = Vector2(12.0, 18.0)
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_recommend_bg.add_child(icon_lbl)

	_recommend_label = Label.new()
	_recommend_label.position = Vector2(44.0, 14.0)
	_recommend_label.size = Vector2(1020.0, 50.0)
	_recommend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_recommend_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recommend_label.add_theme_font_size_override("font_size", 24)
	_recommend_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_recommend_label.text = "✓ Stable — keep building to maintain resilience"
	_recommend_bg.add_child(_recommend_label)


func _build_tips_panel() -> void:
	# Tips button added to the HUD layer
	_tips_btn = Button.new()
	_tips_btn.position = Vector2(10.0, 12.0)
	_tips_btn.size = Vector2(70.0, 70.0)
	_tips_btn.text = "?"
	_tips_btn.flat = true
	_tips_btn.add_theme_font_size_override("font_size", 36)
	_tips_btn.modulate = Color(0.6, 0.8, 1.0)
	_tips_btn.pressed.connect(_toggle_tips)
	add_child(_tips_btn)

	# Tips panel on its own CanvasLayer
	_tips_panel = CanvasLayer.new()
	_tips_panel.layer = 30
	_tips_panel.visible = false
	add_child(_tips_panel)

	var panel_bg := Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.04, 0.10, 0.97)
	panel_style.corner_radius_top_left    = 16
	panel_style.corner_radius_top_right   = 16
	panel_style.corner_radius_bottom_left  = 16
	panel_style.corner_radius_bottom_right = 16
	panel_bg.add_theme_stylebox_override("panel", panel_style)
	panel_bg.position = Vector2(40.0, 250.0)
	panel_bg.size = Vector2(1000.0, 1200.0)
	_tips_panel.add_child(panel_bg)

	var title_lbl := Label.new()
	title_lbl.text = "STRATEGY GUIDE"
	title_lbl.position = Vector2(0.0, 20.0)
	title_lbl.size = Vector2(1000.0, 60.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	panel_bg.add_child(title_lbl)

	var content_y := 90.0
	for entry in TIPS_CONTENT:
		var heading := Label.new()
		heading.text = entry[0]
		heading.position = Vector2(30.0, content_y)
		heading.size = Vector2(940.0, 40.0)
		heading.add_theme_font_size_override("font_size", 26)
		heading.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		panel_bg.add_child(heading)
		content_y += 44.0

		var body_lbl := Label.new()
		body_lbl.text = entry[1]
		body_lbl.position = Vector2(40.0, content_y)
		body_lbl.size = Vector2(920.0, 80.0)
		body_lbl.add_theme_font_size_override("font_size", 22)
		body_lbl.add_theme_color_override("font_color", Color(0.78, 0.85, 0.92))
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		panel_bg.add_child(body_lbl)
		content_y += 100.0

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.position = Vector2(350.0, content_y + 20.0)
	close_btn.size = Vector2(300.0, 70.0)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.pressed.connect(_toggle_tips)
	panel_bg.add_child(close_btn)


func _build_tutorial() -> void:
	if GameManager.tutorial_shown:
		return

	_tutorial_layer = CanvasLayer.new()
	_tutorial_layer.layer = 50
	add_child(_tutorial_layer)

	_tutorial_overlay = ColorRect.new()
	_tutorial_overlay.color = Color(0.0, 0.0, 0.0, 0.82)
	_tutorial_overlay.position = Vector2.ZERO
	_tutorial_overlay.size = Vector2(1080.0, 1920.0)
	_tutorial_layer.add_child(_tutorial_overlay)

	_tutorial_title = Label.new()
	_tutorial_title.position = Vector2(40.0, 580.0)
	_tutorial_title.size = Vector2(1000.0, 200.0)
	_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_title.add_theme_font_size_override("font_size", 52)
	_tutorial_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_tutorial_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tutorial_layer.add_child(_tutorial_title)

	_tutorial_body = Label.new()
	_tutorial_body.position = Vector2(80.0, 720.0)
	_tutorial_body.size = Vector2(920.0, 320.0)
	_tutorial_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tutorial_body.add_theme_font_size_override("font_size", 32)
	_tutorial_body.add_theme_color_override("font_color", Color(0.78, 0.85, 0.92))
	_tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tutorial_layer.add_child(_tutorial_body)

	_tutorial_btn = Button.new()
	_tutorial_btn.position = Vector2(340.0, 1100.0)
	_tutorial_btn.size = Vector2(400.0, 90.0)
	_tutorial_btn.add_theme_font_size_override("font_size", 32)
	_tutorial_btn.pressed.connect(_advance_tutorial)
	_tutorial_layer.add_child(_tutorial_btn)

	show_tutorial()


# ── Card interaction ──────────────────────────────────────────────────────────

func _on_card_pressed(sol_id: int) -> void:
	if _selected_solution == sol_id:
		_selected_solution = -1
		_highlight_card(-1)
		emit_signal("solution_selected", -1)
	else:
		_selected_solution = sol_id
		_highlight_card(sol_id)
		emit_signal("solution_selected", sol_id)


func _highlight_card(sol_id: int) -> void:
	for i in _solution_cards.size():
		var style := _card_styles[i]
		var tw := _solution_cards[i].create_tween()
		if i == sol_id:
			tw.tween_property(_solution_cards[i], "scale", Vector2(1.05, 1.05), 0.15)
			tw.parallel().tween_method(
				func(c: Color) -> void: style.border_color = c,
				style.border_color, Color(0.0, 0.9, 1.0), 0.15)
		else:
			tw.tween_property(_solution_cards[i], "scale", Vector2.ONE, 0.15)
			tw.parallel().tween_method(
				func(c: Color) -> void: style.border_color = c,
				style.border_color, Color(0.18, 0.22, 0.32), 0.15)


func _clear_card_selection() -> void:
	_highlight_card(-1)


# ── Bar tweening ──────────────────────────────────────────────────────────────

func _tween_bar(bar: ProgressBar, target: float, idx: int) -> void:
	if _bar_tweens[idx]:
		_bar_tweens[idx].kill()
	_bar_tweens[idx] = bar.create_tween()
	_bar_tweens[idx].tween_property(bar, "value", target, 0.5).set_trans(Tween.TRANS_CUBIC)


# ── Day label pulse ───────────────────────────────────────────────────────────

func _update_day_style(days: int) -> void:
	if _day_tween:
		_day_tween.kill()
	day_label.scale = Vector2.ONE
	day_label.pivot_offset = day_label.size / 2
	if days > 90:
		day_label.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	elif days > 45:
		day_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.1))
		_day_tween = day_label.create_tween().set_loops()
		_day_tween.tween_property(day_label, "scale", Vector2(1.04, 1.04), 0.6)
		_day_tween.tween_property(day_label, "scale", Vector2.ONE, 0.6)
	else:
		day_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		_day_tween = day_label.create_tween().set_loops()
		_day_tween.tween_property(day_label, "scale", Vector2(1.08, 1.08), 0.25)
		_day_tween.tween_property(day_label, "scale", Vector2.ONE, 0.25)


# ── AP dot animation ──────────────────────────────────────────────────────────

func _set_ap_dot(i: int, filled: bool) -> void:
	if _ap_dot_tweens[i]:
		_ap_dot_tweens[i].kill()
	var dot_style := _ap_dot_styles[i]
	var target := Color(0.0, 0.9, 1.0) if filled else Color(0.12, 0.13, 0.18)
	var tw := _ap_dots[i].create_tween()
	_ap_dot_tweens[i] = tw
	tw.tween_method(
		func(c: Color) -> void: dot_style.bg_color = c,
		dot_style.bg_color, target, 0.18)
	if filled:
		_ap_dots[i].pivot_offset = Vector2(14.0, 14.0)
		tw.parallel().tween_property(_ap_dots[i], "scale", Vector2(1.4, 1.4), 0.09)
		tw.tween_property(_ap_dots[i], "scale", Vector2.ONE, 0.09)


# ── Public API ────────────────────────────────────────────────────────────────

func update_state(state: Dictionary, action_points: int) -> void:
	var days: int = state["days_remaining"]
	day_label.text = str(days)
	_update_day_style(days)

	_tween_bar(scarcity_bar,  state["scarcity"],         0)
	_tween_bar(flood_bar,     state["flood_risk"],        1)
	_tween_bar(wildfire_bar,  state["wildfire_danger"],   2)

	for i in range(_ap_dots.size()):
		_set_ap_dot(i, i < action_points)

	trust_label.text   = "Trust %d%%" % int(state["trust"])
	rain_label.text    = "Rain %.1fmm" % state["rainfall_mm"]
	aquifer_label.text = "Aquifer %d%%" % int(state["aquifer"])

	# Trust shake
	var new_trust: float = state["trust"]
	if new_trust < _prev_trust - 4.0:
		_shake_trust_label()
	_prev_trust = new_trust
	# Update recommendation system
	update_recommendations(state)


func show_event(event: Dictionary) -> void:
	var line := "[%s] %s" % [event["title"], event["description"]]
	_event_lines.push_front(line)
	if _event_lines.size() > 3:
		_event_lines.resize(3)
	event_log.text = "\n".join(_event_lines)
	event_log.modulate.a = 0.0

	# Determine event color
	var event_id: String = event.get("id", "")
	var event_color: Color
	if event_id in ["wildfire_outbreak", "dev_pressure", "heatwave"]:
		event_color = Color(1.0, 0.38, 0.38)
	elif event_id in ["heavy_rain", "council_support", "volunteers"]:
		event_color = Color(0.3, 1.0, 0.58)
	else:
		event_color = Color(0.9, 0.85, 0.5)

	var tw := event_log.create_tween()
	tw.tween_property(event_log, "modulate:a", 1.0, 0.35)
	tw.tween_method(
		func(c: Color) -> void: event_log.add_theme_color_override("font_color", c),
		event_color, Color(0.78, 0.85, 0.92), 2.5)

	if EVENT_TERRAIN.has(event_id):
		_last_event_terrain = EVENT_TERRAIN[event_id]


func set_placement_mode(sol_id: int) -> void:
	_selected_solution = sol_id
	_highlight_card(sol_id)


func clear_placement_mode() -> void:
	_selected_solution = -1
	_clear_card_selection()


func init_minimap_layout(layout: Array) -> void:
	if _minimap:
		_minimap.map_layout = layout


func update_minimap(pos: Vector2, zoom: Vector2) -> void:
	if _minimap:
		_minimap.cam_pos  = pos
		_minimap.cam_zoom = zoom
		_minimap.queue_redraw()


func show_platform_hint(is_mobile: bool) -> void:
	if _hint_label == null:
		return
	_hint_label.text = "Swipe · Pinch to zoom · 2-finger tap cancel" if is_mobile \
				  else "Drag to pan · Scroll to zoom · 1-5 select · ESC cancel"
	var tw := _hint_label.create_tween()
	tw.tween_property(_hint_label, "modulate:a", 1.0, 0.5)
	tw.tween_interval(3.0)
	tw.tween_property(_hint_label, "modulate:a", 0.0, 1.2)


func show_pause_state(is_paused: bool) -> void:
	if _pause_label == null:
		return
	var tw := _pause_label.create_tween()
	tw.tween_property(_pause_label, "modulate:a", 1.0 if is_paused else 0.0, 0.25)


func spawn_popup(text: String, color: Color, screen_y: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", color)
	lbl.modulate.a = 0.0
	var rx := float(randi_range(60, 500))
	lbl.position = Vector2(rx, screen_y - 10.0)
	_popup_layer.add_child(lbl)

	var tw := lbl.create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(lbl, "position:y", screen_y - 10.0 - 90.0, 1.6)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free)


func spawn_centered_popup(text: String, color: Color) -> void:
	var bg := Panel.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.02, 0.04, 0.08, 0.88)
	bg_style.corner_radius_top_left    = 12
	bg_style.corner_radius_top_right   = 12
	bg_style.corner_radius_bottom_left  = 12
	bg_style.corner_radius_bottom_right = 12
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.position = Vector2(140.0, 820.0)
	bg.size = Vector2(800.0, 200.0)
	bg.modulate.a = 0.0
	bg.pivot_offset = Vector2(400.0, 100.0)
	bg.scale = Vector2(0.8, 0.8)
	_popup_layer.add_child(bg)

	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(0.0, 0.0)
	lbl.size = Vector2(800.0, 200.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	bg.add_child(lbl)

	var tw := bg.create_tween()
	tw.tween_property(bg, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(bg, "scale", Vector2(1.0, 1.0), 0.2)
	tw.tween_interval(1.8)
	tw.tween_property(bg, "modulate:a", 0.0, 0.4)
	tw.tween_callback(bg.queue_free)


func show_solution_feedback(sol_id: int) -> void:
	var sol_name: String = SOLUTION_DATA[sol_id]["name"]
	var text := sol_name + " placed!\n" + SOLUTION_EFFECT_DESC[sol_id]
	spawn_centered_popup(text, Color(0.4, 1.0, 0.6))


func show_gauge_deltas(sc_d: float, fl_d: float, wf_d: float, trust_d: float) -> void:
	var sc_y := 160.0
	if scarcity_bar:
		sc_y = scarcity_bar.global_position.y
	var fl_y := 215.0
	if flood_bar:
		fl_y = flood_bar.global_position.y
	var wf_y := 270.0
	if wildfire_bar:
		wf_y = wildfire_bar.global_position.y

	if absf(sc_d) >= 2.5:
		var col := Color(1.0, 0.3, 0.3) if sc_d > 0.0 else Color(0.3, 1.0, 0.5)
		var sign_str := "+" if sc_d > 0.0 else ""
		spawn_popup("%s%.1f%% Scarcity" % [sign_str, sc_d], col, sc_y)
		_flash_gauge(0, sc_d > 2.5)

	if absf(fl_d) >= 2.5:
		var col := Color(0.4, 0.5, 1.0) if fl_d > 0.0 else Color(0.5, 0.9, 1.0)
		var sign_str := "+" if fl_d > 0.0 else ""
		spawn_popup("%s%.1f%% Flood" % [sign_str, fl_d], col, fl_y)
		_flash_gauge(1, fl_d > 2.5)

	if absf(wf_d) >= 2.5:
		var col := Color(1.0, 0.5, 0.1) if wf_d > 0.0 else Color(0.4, 0.9, 0.3)
		var sign_str := "+" if wf_d > 0.0 else ""
		spawn_popup("%s%.1f%% Wildfire" % [sign_str, wf_d], col, wf_y)
		_flash_gauge(2, wf_d > 2.5)

	if trust_d < -4.0:
		_shake_trust_label()
	if trust_d < -8.0:
		spawn_popup("%.0f Trust" % trust_d, Color(1.0, 0.3, 0.3), 420.0)


func update_recommendations(state: Dictionary) -> void:
	if _recommend_label == null:
		return
	var sc: float = state["scarcity"]
	var fl: float = state["flood_risk"]
	var wf: float = state["wildfire_danger"]
	var days: int = state["days_remaining"]
	var urgent_sol: int = -1
	var msg: String
	var msg_color: Color

	if sc > 75.0:
		msg = "⚠ CRITICAL: Place Swales or Rain Gardens — water scarcity critical!"
		msg_color = Color(1.0, 0.25, 0.25)
		urgent_sol = 0
	elif wf > 68.0:
		msg = "⚠ URGENT: Plant Native Grasses — wildfire threatens vegetation!"
		msg_color = Color(1.0, 0.55, 0.1)
		urgent_sol = 2
	elif fl > 68.0:
		msg = "⚠ WARNING: Place Retention Ponds in urban areas — flooding risk!"
		msg_color = Color(0.35, 0.6, 1.0)
		urgent_sol = 4
	elif sc > 55.0:
		msg = "▲ PRIORITY: Add infiltration — Swales or Rain Gardens recommended"
		msg_color = Color(1.0, 0.9, 0.2)
		urgent_sol = 0
	elif days < 30:
		msg = "⏱ FINAL STRETCH: Hold scarcity below 80% to survive!"
		msg_color = Color(1.0, 0.55, 0.1)
	else:
		msg = "✓ Stable — keep building to maintain resilience"
		msg_color = Color(0.3, 1.0, 0.55)

	_recommend_label.text = msg
	_recommend_label.add_theme_color_override("font_color", msg_color)
	_urgent_sol_id = urgent_sol
	_update_card_urgency(urgent_sol, state)


func _update_card_urgency(urgent_sol_id: int, state: Dictionary) -> void:
	for i in _solution_cards.size():
		if _card_urgency_tweens[i] != null:
			_card_urgency_tweens[i].kill()
			_card_urgency_tweens[i] = null

		var style := _card_styles[i]
		if i == urgent_sol_id:
			var tw := _solution_cards[i].create_tween().set_loops()
			tw.tween_method(
				func(c: Color) -> void: style.border_color = c,
				Color(1.0, 0.85, 0.0), Color(1.0, 0.5, 0.0), 0.5)
			tw.tween_method(
				func(c: Color) -> void: style.border_color = c,
				Color(1.0, 0.5, 0.0), Color(1.0, 0.85, 0.0), 0.5)
			style.bg_color = Color(0.12, 0.14, 0.20)
			_card_urgency_tweens[i] = tw
		elif state["scarcity"] > 75.0 and i in [0, 1]:
			style.border_color = Color(1.0, 0.9, 0.2)
			_card_urgency_tweens[i] = null
		else:
			style.border_color = Color(0.18, 0.22, 0.32)
			style.bg_color = Color(0.08, 0.11, 0.17)
			_card_urgency_tweens[i] = null


func _flash_gauge(gauge_idx: int, is_bad: bool) -> void:
	if gauge_idx < 0 or gauge_idx >= _gauge_flash_tweens.size():
		return
	var style: StyleBoxFlat
	match gauge_idx:
		0: style = _scarcity_style
		1: style = _flood_style
		2: style = _wildfire_style
	if style == null:
		return

	var flash_color := Color(1.0, 0.25, 0.25) if is_bad else Color(0.2, 1.0, 0.4)
	var original_color := style.bg_color

	if _gauge_flash_tweens[gauge_idx] != null:
		_gauge_flash_tweens[gauge_idx].kill()

	var tw := create_tween()
	_gauge_flash_tweens[gauge_idx] = tw
	tw.tween_method(
		func(c: Color) -> void: style.bg_color = c,
		original_color, flash_color, 0.12)
	tw.tween_method(
		func(c: Color) -> void: style.bg_color = c,
		flash_color, original_color, 0.4)


func _shake_trust_label() -> void:
	if trust_label == null:
		return
	var orig_x := trust_label.position.x
	var tw := trust_label.create_tween()
	for _i in 4:
		tw.tween_property(trust_label, "position:x", orig_x - 7.0, 0.07)
		tw.tween_property(trust_label, "position:x", orig_x + 7.0, 0.07)
	tw.tween_property(trust_label, "position:x", orig_x, 0.07)


# ── Tutorial ──────────────────────────────────────────────────────────────────

func show_tutorial() -> void:
	if _tutorial_layer == null:
		return
	_tutorial_layer.visible = true
	_tutorial_active = true
	_show_tutorial_step(0)


func _show_tutorial_step(step: int) -> void:
	_tutorial_step = step
	match step:
		0:
			_tutorial_title.text = "WELCOME TO\nDAY ZERO DROUGHT"
			_tutorial_body.text  = "Keep Water Scarcity below 80%\nuntil the rains come in 180 days.\n\nCape Town is counting on you."
			_tutorial_btn.text   = "NEXT →"
		1:
			_tutorial_title.text = "WATCH THE GAUGES"
			_tutorial_body.text  = "Three bars at top track city health:\n\n💧 Water Scarcity — must stay below 80%\n🌊 Flood Risk — high rainfall causes flooding\n🔥 Wildfire Danger — drought dries vegetation\n\nAll three can end the game if critical."
			_tutorial_btn.text   = "NEXT →"
		2:
			_tutorial_title.text = "PLACE SOLUTIONS"
			_tutorial_body.text  = "Select a solution card below.\nHighlighted tiles show where it can go.\nTap a green tile to place it.\n\nStart with Native Grasses or Swales\nfor the best early impact.\n\nGood luck — every action counts."
			_tutorial_btn.text   = "START GAME"


func _advance_tutorial() -> void:
	_tutorial_step += 1
	if _tutorial_step >= 3:
		_tutorial_layer.visible = false
		GameManager.tutorial_shown = true
		_tutorial_active = false
	else:
		_show_tutorial_step(_tutorial_step)


# ── Tips toggle ───────────────────────────────────────────────────────────────

func _toggle_tips() -> void:
	_tips_visible = not _tips_visible
	if _tips_panel != null:
		_tips_panel.visible = _tips_visible


# ── Helpers ───────────────────────────────────────────────────────────────────

func _lerp_gauge_color(value: float, low: Color, mid: Color, high: Color) -> Color:
	var t := clampf(value / 100.0, 0.0, 1.0)
	if t < 0.5:
		return low.lerp(mid, t * 2.0)
	else:
		return mid.lerp(high, (t - 0.5) * 2.0)
