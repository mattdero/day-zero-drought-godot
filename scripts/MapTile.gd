extends Node2D

signal tile_clicked(tile: Node2D)

const TILE_SIZE := Vector2(96.0, 48.0)   # diamond bounding box
const ISO_HALF_W := 48.0
const ISO_HALF_H := 24.0

const TERRAIN_NAMES := {
	0: "Table Mtn",
	1: "Catchment",
	2: "Urban",
	3: "Coastal",
}

const TERRAIN_COLORS := {
	0: Color(0.50, 0.44, 0.36),  # Mountain  — warm grey rock
	1: Color(0.18, 0.50, 0.16),  # Catchment — rich forest green
	2: Color(0.60, 0.60, 0.58),  # Urban     — warm concrete
	3: Color(0.06, 0.38, 0.72),  # Coastal   — vivid ocean blue
}

# Which solution IDs each terrain can accept
const SOLUTION_ALLOWED := {
	0: [0, 1, 2, 3],   # Mountain:  Swales, Rain Gardens, Native Grasses, Terraces
	1: [0, 1, 2, 3],   # Catchment: same
	2: [1, 4],         # Urban:     Rain Gardens, Retention Ponds
	3: [],             # Coastal:   none
}

const SOLUTION_ABBREV := {0: "SWL", 1: "RGD", 2: "GRS", 3: "TRC", 4: "RTP"}
const SOLUTION_NAMES  := {0: "Swales", 1: "Rain\nGarden", 2: "Grasses", 3: "Terraces", 4: "Pond"}

var terrain: int = 0
var col: int = 0
var row: int = 0
var solution_placed: int = -1   # -1 = none
var _show_cursor_ring: bool = false

var _hl_mode: int = 0       # 0=none  1=green  2=red
var _hl_alpha: float = 0.0  # animated by tween for mode 1
var _hl_tween: Tween
var _detail: TerrainDetail
var _sol_overlay: SolutionOverlay


# Inner class draws terrain patterns in isometric space
class TerrainDetail extends Node2D:
	var terrain_type: int = 0
	var _seed_x: int = 0
	var _seed_y: int = 0

	func setup(t: int, sx: int, sy: int) -> void:
		terrain_type = t
		_seed_x = sx
		_seed_y = sy
		queue_redraw()

	# Maps flat [0,92]^2 tile coords to iso screen coords relative to tile anchor (top vertex)
	func _iso(tx: float, ty: float) -> Vector2:
		var u := tx / 92.0
		var v := ty / 92.0
		return Vector2((u - v) * 48.0, (u + v) * 24.0)

	# Draws 3 visible faces of an isometric box
	func _draw_iso_box(fx: float, fy: float, fw: float, fh: float, bh: float,
			top_col: Color, front_col: Color, side_col: Color) -> void:
		var p00 := _iso(fx,      fy)
		var p10 := _iso(fx + fw, fy)
		var p11 := _iso(fx + fw, fy + fh)
		var p01 := _iso(fx,      fy + fh)
		var h   := Vector2(0.0, -bh)
		# Front face (south wall) — medium brightness
		draw_colored_polygon(PackedVector2Array([p01, p01 + h, p11 + h, p11]), front_col)
		# Side face (east wall) — darkest
		draw_colored_polygon(PackedVector2Array([p10, p10 + h, p11 + h, p11]), side_col)
		# Top face — brightest
		draw_colored_polygon(PackedVector2Array([p00 + h, p10 + h, p11 + h, p01 + h]), top_col)

	func _draw() -> void:
		match terrain_type:
			0:  # Mountain — Table Mountain mesa
				var sx := _seed_x; var sy := _seed_y
				var seed_h := float((sx * 7 + sy * 3) % 16)

				# Ground diamond
				var ground_pts := PackedVector2Array([
					_iso(0.0,  0.0), _iso(92.0, 0.0),
					_iso(92.0, 92.0), _iso(0.0, 92.0)
				])
				draw_colored_polygon(ground_pts, Color(0.50, 0.44, 0.36))

				# Main mesa
				var mesa_top   := Color(0.64, 0.58, 0.46)
				var mesa_front := Color(0.30, 0.24, 0.18)
				var mesa_side  := Color(0.20, 0.15, 0.10)
				_draw_iso_box(4.0, 4.0, 84.0, 84.0, 36.0 + seed_h, mesa_top, mesa_front, mesa_side)

				# Snow stripe across top face
				var mesa_h := 36.0 + seed_h
				var snow_pts := PackedVector2Array([
					_iso(4.0,  4.0)  + Vector2(0, -mesa_h),
					_iso(88.0, 4.0)  + Vector2(0, -mesa_h),
					_iso(88.0, 14.0) + Vector2(0, -mesa_h),
					_iso(4.0,  14.0) + Vector2(0, -mesa_h),
				])
				draw_colored_polygon(snow_pts, Color(0.92, 0.94, 0.98, 0.85))

				# Strata lines on front face
				var strata_col := Color(0.15, 0.10, 0.06, 0.7)
				for i in 3:
					var fy_strat := 4.0 + float(i + 1) * 22.0
					var lp0 := _iso(4.0,  fy_strat) + Vector2(0, -mesa_h * 0.3 * float(i + 1) / 3.0)
					var lp1 := _iso(88.0, fy_strat) + Vector2(0, -mesa_h * 0.3 * float(i + 1) / 3.0)
					draw_line(lp0, lp1, strata_col, 1.5)

				# Secondary smaller mesa offset by seed
				var ox := float((sx * 5) % 20)
				var small_top   := Color(0.58, 0.52, 0.40)
				var small_front := Color(0.25, 0.19, 0.13)
				var small_side  := Color(0.16, 0.12, 0.08)
				_draw_iso_box(ox + 8.0, 8.0, 30.0, 30.0, 18.0 + seed_h * 0.5,
					small_top, small_front, small_side)

				# Rock debris on mesa top — 3 tiny boxes
				for i in 3:
					var rx := float((sx * 11 + i * 17) % 60) + 14.0
					var ry := float((sy * 7  + i * 23) % 60) + 14.0
					var rh := float((sx + sy + i) % 3) + 4.0
					_draw_iso_box(rx, ry, 8.0, 8.0, rh,
						Color(0.72, 0.66, 0.54), Color(0.38, 0.30, 0.22), Color(0.28, 0.22, 0.16))

			1:  # Catchment — Forest with creek
				var sx := _seed_x; var sy := _seed_y

				# Ground diamond
				var ground_pts := PackedVector2Array([
					_iso(0.0,  0.0), _iso(92.0, 0.0),
					_iso(92.0, 92.0), _iso(0.0, 92.0)
				])
				draw_colored_polygon(ground_pts, Color(0.22, 0.52, 0.16))

				# Hill mound — low gentle hill
				var hill_h := float((sx * 5 + sy * 3) % 7) + 8.0
				_draw_iso_box(8.0, 30.0, 76.0, 52.0, hill_h,
					Color(0.28, 0.62, 0.20), Color(0.18, 0.45, 0.12), Color(0.14, 0.36, 0.10))

				# Creek — blue polyline projected through _iso()
				var cx0 := float((sx * 7) % 40) + 10.0
				var creek_pts := PackedVector2Array()
				for i in 8:
					var t := float(i) / 7.0
					var cpx := cx0 + t * 50.0 + sin(float(i) * 0.9 + float(sy) * 0.4) * 8.0
					var cpy := float(i) * 11.5
					creek_pts.append(_iso(cpx, cpy))
				draw_polyline(creek_pts, Color(0.25, 0.55, 0.90, 0.72), 2.0)

				# Trees at seed-determined positions
				var tree_positions := [
					Vector2(float((sx * 5  + 10) % 55) + 8.0,  float((sy * 7  + 5)  % 35) + 6.0),
					Vector2(float((sx * 11 + 20) % 50) + 20.0, float((sy * 3  + 15) % 40) + 12.0),
					Vector2(float((sx * 7  + 5)  % 60) + 5.0,  float((sy * 9  + 8)  % 30) + 40.0),
					Vector2(float((sx * 3  + 30) % 45) + 30.0, float((sy * 11 + 3)  % 35) + 50.0),
					Vector2(float((sx * 9  + 15) % 55) + 15.0, float((sy * 5  + 20) % 28) + 62.0),
				]
				for p in tree_positions:
					var trunk_h := float((sx + sy + int(p.x)) % 5) + 8.0
					var canopy_r := float((sx + int(p.y)) % 5) + 6.0
					# Trunk as tiny iso box
					_draw_iso_box(p.x - 2.0, p.y - 2.0, 4.0, 4.0, trunk_h,
						Color(0.45, 0.30, 0.18), Color(0.32, 0.20, 0.10), Color(0.25, 0.15, 0.08))
					# Canopy circle at trunk top
					var canopy_pos := _iso(p.x, p.y) + Vector2(0.0, -trunk_h - canopy_r)
					draw_circle(canopy_pos, canopy_r + 1.5, Color(0.08, 0.30, 0.08, 0.90))
					draw_circle(canopy_pos - Vector2(1.5, 1.5), canopy_r, Color(0.14, 0.48, 0.12, 0.85))
					draw_circle(canopy_pos - Vector2(2.5, 2.5), canopy_r * 0.5, Color(0.28, 0.62, 0.18, 0.65))

			2:  # Urban — City blocks with 3D buildings
				var sx := _seed_x; var sy := _seed_y

				# Asphalt ground
				var ground_pts := PackedVector2Array([
					_iso(0.0,  0.0), _iso(92.0, 0.0),
					_iso(92.0, 92.0), _iso(0.0, 92.0)
				])
				draw_colored_polygon(ground_pts, Color(0.44, 0.42, 0.38))

				# Road grid lines
				var gox := float((sx * 3) % 8) - 4.0
				var goy := float((sy * 5) % 8) - 4.0
				var vroads: Array[float] = [gox, 23.0 + gox, 46.0 + gox, 69.0 + gox]
				var hroads: Array[float] = [goy, 23.0 + goy, 46.0 + goy, 69.0 + goy]
				var road_col := Color(0.55, 0.52, 0.46, 0.85)
				for xr in vroads:
					if xr > 1.0 and xr < 91.0:
						draw_line(_iso(xr, 0.0), _iso(xr, 92.0), road_col, 1.5)
				for yr in hroads:
					if yr > 1.0 and yr < 91.0:
						draw_line(_iso(0.0, yr), _iso(92.0, yr), road_col, 1.5)

				# Determine building density from row (sy)
				var bldg_heights: Array[float]
				var bldg_palettes: Array[Color]  # top colors
				if sy >= 7 and sy <= 8:
					# Downtown — tall towers
					bldg_heights = [30.0, 36.0, 42.0, 38.0, 48.0]
					bldg_palettes = [
						Color(0.70, 0.72, 0.78), Color(0.78, 0.80, 0.85),
						Color(0.65, 0.68, 0.75), Color(0.82, 0.84, 0.88), Color(0.60, 0.65, 0.72)
					]
				elif (sy >= 5 and sy <= 6) or (sy >= 9 and sy <= 10):
					# Mid-city — medium brick
					bldg_heights = [18.0, 22.0, 25.0, 20.0, 28.0]
					bldg_palettes = [
						Color(0.62, 0.52, 0.40), Color(0.68, 0.56, 0.42),
						Color(0.58, 0.48, 0.36), Color(0.72, 0.60, 0.46), Color(0.55, 0.45, 0.35)
					]
				else:
					# Fringe — shorter residential
					bldg_heights = [10.0, 12.0, 14.0, 11.0, 16.0]
					bldg_palettes = [
						Color(0.75, 0.68, 0.58), Color(0.68, 0.62, 0.52),
						Color(0.80, 0.72, 0.62), Color(0.72, 0.65, 0.55), Color(0.65, 0.58, 0.48)
					]

				# Generate building footprints within road blocks, sorted by fy (back-to-front)
				var buildings: Array[Dictionary] = []
				for ci in range(vroads.size() - 1):
					for ri in range(hroads.size() - 1):
						var bx: float = vroads[ci] + 2.5
						var by_f: float = hroads[ri] + 2.5
						var bw: float = vroads[ci + 1] - vroads[ci] - 5.0
						var bh_f: float = hroads[ri + 1] - hroads[ri] - 5.0
						if bw < 4.0 or bh_f < 4.0:
							continue
						var is_park := ((sx * 3 + ci * 7 + sy * 5 + ri * 11) % 13) == 0
						if is_park:
							buildings.append({
								"bx": bx, "by": by_f, "bw": bw, "bh": bh_f,
								"height": 0.0, "park": true,
								"bldg_idx": (ci * 4 + ri) % 5
							})
						else:
							buildings.append({
								"bx": bx, "by": by_f, "bw": bw, "bh": bh_f,
								"height": 0.0, "park": false,
								"bldg_idx": (ci * 4 + ri) % 5
							})

				# Sort back-to-front by fy
				buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return a["by"] < b["by"])

				# Draw buildings
				for b in buildings:
					var bidx: int = b["bldg_idx"]
					if b["park"]:
						var park_center := _iso(b["bx"] + b["bw"] * 0.5, b["by"] + b["bh"] * 0.5)
						draw_circle(park_center, minf(b["bw"], b["bh"]) * 0.25, Color(0.22, 0.58, 0.18, 0.90))
					else:
						var bh_px := bldg_heights[bidx] * (0.85 + float((sx * bidx + sy) % 4) * 0.1)
						var top_c  := bldg_palettes[bidx]
						var front_c := top_c.darkened(0.35)
						var side_c  := top_c.darkened(0.55)
						_draw_iso_box(b["bx"], b["by"], b["bw"], b["bh"], bh_px,
							top_c, front_c, side_c)

			3:  # Coastal — Beach and ocean
				var sx := _seed_x; var sy := _seed_y

				if sy <= 12:
					# Beach tile — split diamond into sandy upper and ocean lower portions
					var split_v := float(13 - sy) / 13.0  # 0=all ocean, 1=all beach
					var beach_ty := 92.0 * (1.0 - split_v)

					# Ocean lower portion
					var ocean_pts := PackedVector2Array([
						_iso(0.0,   beach_ty),
						_iso(92.0,  beach_ty),
						_iso(92.0,  92.0),
						_iso(0.0,   92.0)
					])
					draw_colored_polygon(ocean_pts, Color(0.08, 0.38, 0.75))

					# Sandy upper portion
					var beach_pts := PackedVector2Array([
						_iso(0.0,  0.0),
						_iso(92.0, 0.0),
						_iso(92.0, beach_ty),
						_iso(0.0,  beach_ty)
					])
					draw_colored_polygon(beach_pts, Color(0.88, 0.82, 0.60))

					# Foam polyline at waterline
					var foam_pts := PackedVector2Array()
					for px in range(0, 93, 6):
						var foam_y := beach_ty + sin(float(px) * 0.20 + float(sx) * 0.5) * 3.0
						foam_pts.append(_iso(float(px), foam_y))
					draw_polyline(foam_pts, Color(1.0, 1.0, 1.0, 0.90), 2.5)

					# Dock/pier for sy = 10-11
					if sy >= 10 and sy <= 11:
						var dock_x := float((sx * 7) % 40) + 20.0
						_draw_iso_box(dock_x, beach_ty - 4.0, 12.0, 8.0, 4.0,
							Color(0.60, 0.48, 0.30), Color(0.42, 0.32, 0.18), Color(0.32, 0.24, 0.12))

				else:
					# Full ocean tile
					var ground_pts := PackedVector2Array([
						_iso(0.0,  0.0), _iso(92.0, 0.0),
						_iso(92.0, 92.0), _iso(0.0, 92.0)
					])
					draw_colored_polygon(ground_pts, Color(0.04, 0.22, 0.62))

					# Inner diamond for depth variation
					var inner_pts := PackedVector2Array([
						_iso(16.0, 16.0), _iso(76.0, 16.0),
						_iso(76.0, 76.0), _iso(16.0, 76.0)
					])
					draw_colored_polygon(inner_pts, Color(0.06, 0.28, 0.70))

					# Wave polylines
					var wave_col := Color(0.30, 0.55, 0.92, 0.40)
					for w in 4:
						var base_ty := 12.0 + float(w) * 20.0 + float((sx + w * 3) % 8)
						if base_ty >= 90.0:
							continue
						var phase := float(sx) * 0.4 + float(w) * 1.2
						var wave_pts := PackedVector2Array()
						for px in range(0, 93, 6):
							var wy := base_ty + sin(float(px) * 0.18 + phase) * 5.0
							wave_pts.append(_iso(float(px), wy))
						draw_polyline(wave_pts, wave_col, 1.8)


class SolutionOverlay extends Node2D:
	var _sol_id: int = -1

	func show_solution(id: int) -> void:
		_sol_id = id
		queue_redraw()

	func _draw() -> void:
		if _sol_id == -1:
			return
		match _sol_id:
			0:  # Swales — 3 curved contour trenches
				var c := Color(0.62, 0.48, 0.25, 0.92)
				for i in 3:
					var pts := PackedVector2Array()
					var by := -18.0 + float(i) * 14.0
					for px in range(-46, 47, 6):
						pts.append(Vector2(float(px), by + sin(float(px) * 0.15 + float(i) * 1.2) * 6.0))
					draw_polyline(pts, c, 3.5)
			1:  # Rain Garden — ring + pool + 6 plant dots
				draw_circle(Vector2.ZERO, 26.0, Color(0.10, 0.50, 0.15, 0.42))
				draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 48, Color(0.15, 0.65, 0.20, 0.92), 3.0)
				draw_circle(Vector2.ZERO, 9.0, Color(0.20, 0.55, 0.90, 0.85))
				for i in 6:
					var a := float(i) / 6.0 * TAU
					draw_circle(Vector2(cos(a) * 16.0, sin(a) * 16.0), 4.5, Color(0.10, 0.55, 0.10, 0.92))
			2:  # Native Grasses — 12 scattered blade pairs
				var grass := Color(0.30, 0.72, 0.12, 0.92)
				for i in 12:
					var gx := float((i * 13 + 7) % 74) - 37.0
					var gy := float((i * 17 + 11) % 64) - 32.0
					var h  := float((i * 7) % 14) + 10.0
					draw_line(Vector2(gx, gy + h), Vector2(gx - 4.0, gy), grass, 2.0)
					draw_line(Vector2(gx, gy + h), Vector2(gx + 4.0, gy + h * 0.35), grass, 1.5)
			3:  # Terraces — 4 stepped platforms with shadow edge
				for i in 4:
					var ty  := -30.0 + float(i) * 16.0
					var tx_l :=  -40.0 + float(i) * 5.0
					var tx_r :=   40.0 - float(i) * 5.0
					draw_rect(Rect2(tx_l, ty, tx_r - tx_l, 9.0), Color(0.62, 0.48, 0.28, 0.92))
					draw_line(Vector2(tx_l, ty + 9.0), Vector2(tx_r, ty + 9.0), Color(0.32, 0.22, 0.10, 0.92), 2.5)
			4:  # Retention Pond — filled oval + 3 ripple arcs
				draw_circle(Vector2.ZERO, 28.0, Color(0.12, 0.40, 0.85, 0.90))
				for r_i in [20, 13, 6]:
					draw_arc(Vector2.ZERO, float(r_i), 0.0, TAU, 32, Color(0.60, 0.82, 1.0, 0.65), 1.8)


func _ready() -> void:
	# Terrain pattern detail layer
	_detail = TerrainDetail.new()
	add_child(_detail)

	# Solution icon overlay (at diamond centre)
	_sol_overlay = SolutionOverlay.new()
	_sol_overlay.position = Vector2(0.0, ISO_HALF_H)
	add_child(_sol_overlay)


func setup(terrain_type: int, c: int, r: int) -> void:
	terrain = terrain_type
	col = c
	row = r
	# Position is set by GameWorld._build_map()
	_detail.setup(terrain, col, row)


func place_solution(sol_id: int) -> void:
	solution_placed = sol_id
	_sol_overlay.show_solution(sol_id)
	_sol_overlay.scale = Vector2(0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(_sol_overlay, "scale", Vector2(1.25, 1.25), 0.12)
	tw.tween_property(_sol_overlay, "scale", Vector2(1.0, 1.0), 0.10)

	set_highlight(0)


func can_accept(sol_id: int) -> bool:
	return sol_id in SOLUTION_ALLOWED[terrain] and solution_placed == -1


# mode: 0=none  1=green (valid, breathing)  2=red (invalid, static)
func set_highlight(mode: int) -> void:
	if _hl_tween:
		_hl_tween.kill()
		_hl_tween = null
	_hl_mode = mode
	_hl_alpha = 0.0
	match mode:
		0:
			self_modulate = Color.WHITE
			queue_redraw()
		1:
			_hl_tween = create_tween().set_loops()
			_hl_tween.tween_method(
				func(a: float) -> void:
					_hl_alpha = a
					var t := (a - 0.35) / 0.55
					self_modulate = Color(1.2, 1.3, 1.1).lerp(Color(1.5, 1.6, 1.3), t)
					queue_redraw(),
				0.35, 0.90, 0.6)
			_hl_tween.tween_method(
				func(a: float) -> void:
					_hl_alpha = a
					var t := (a - 0.35) / 0.55
					self_modulate = Color(1.2, 1.3, 1.1).lerp(Color(1.5, 1.6, 1.3), t)
					queue_redraw(),
				0.90, 0.35, 0.6)
		2:
			self_modulate = Color(0.40, 0.40, 0.46)
			_hl_alpha = 0.60
			queue_redraw()


func set_risk_alert(tint: Color) -> void:
	modulate = Color.WHITE if tint == Color.TRANSPARENT else Color.WHITE.lerp(tint + Color(1, 1, 1, 0), 0.85)


func set_cursor_ring(active: bool) -> void:
	_show_cursor_ring = active
	queue_redraw()


func _draw() -> void:
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(ISO_HALF_W, ISO_HALF_H),
		Vector2(0.0, ISO_HALF_H * 2.0), Vector2(-ISO_HALF_W, ISO_HALF_H)
	])
	if _hl_mode == 1 and _hl_alpha > 0.0:
		draw_colored_polygon(pts, Color(0.0, 1.0, 0.3, _hl_alpha * 0.5))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.05, 1.0, 0.4, clampf(_hl_alpha, 0.0, 1.0)), 6.0)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.6, 1.0, 0.7, _hl_alpha * 0.8), 2.5)
	elif _hl_mode == 2:
		draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.65))
		draw_line(pts[0], pts[2], Color(1.0, 0.12, 0.12, 0.92), 5.0)
		draw_line(pts[1], pts[3], Color(1.0, 0.12, 0.12, 0.92), 5.0)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.9, 0.2, 0.2, 0.7), 2.0)
	if _show_cursor_ring:
		draw_arc(Vector2(0.0, ISO_HALF_H), 26.0, 0.0, TAU, 32, Color(1.0, 1.0, 0.5, 0.9), 3.0)
