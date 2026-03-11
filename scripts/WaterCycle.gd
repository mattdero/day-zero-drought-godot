extends Node

signal day_ticked(state: Dictionary)
signal event_triggered(event: Dictionary)
signal game_over(reason: String)
signal game_won()

const DAY_DURATION := 3.0   # real seconds per game day
const EVENT_CHANCE := 0.10

const EVENTS := [
	{"id":"wildfire_outbreak", "title":"Wildfire Outbreak!",  "wildfire":20.0,   "description":"Blaze in Table Mountain! Wildfire +20"},
	{"id":"heavy_rain",        "title":"Heavy Rains!",        "rain_bonus":15.0, "description":"Storm system arriving. +15mm rainfall today."},
	{"id":"council_support",   "title":"Council Support!",    "trust":10.0,      "description":"City council backs the program. +10 trust."},
	{"id":"volunteers",        "title":"Volunteers!",         "ap_bonus":2,      "description":"Community volunteers arrive. +2 action points."},
	{"id":"dev_pressure",      "title":"Developer Pressure",  "trust":-8.0,      "description":"Developers lobby against conservation. -8 trust."},
	{"id":"heatwave",          "title":"Heatwave Incoming",   "scarcity":10.0,   "description":"Temperatures soar, demand spikes. +10 scarcity."},
]

# Game state
var days_remaining: int    = 180
var scarcity: float        = 40.0
var flood_risk: float      = 10.0
var wildfire_danger: float = 20.0
var aquifer: float         = 60.0
var trust: float           = 75.0
var rainfall_mm: float     = 25.0

# Solution counts
var n_swales: int          = 0
var n_rain_gardens: int    = 0
var n_native_grasses: int  = 0
var n_terraces: int        = 0
var n_retention_ponds: int = 0

var paused: bool = false

var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _game_ended: bool = false


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if _game_ended or paused:
		return
	_timer += delta
	if _timer >= DAY_DURATION:
		_timer -= DAY_DURATION
		_tick_day()


func _tick_day() -> void:
	_compute_rainfall()
	_update_aquifer()
	_update_scarcity()
	_update_flood()
	_update_wildfire()
	_update_trust()
	_maybe_event()
	days_remaining -= 1
	_check_win_loss()
	if not _game_ended:
		emit_signal("day_ticked", _build_state())


func _compute_rainfall() -> void:
	var progress := (180.0 - days_remaining) / 180.0
	var base_rain := lerpf(25.0, 3.0, progress)
	var biotic_bonus := n_native_grasses * 0.4
	var variance := _rng.randf_range(-0.5, 0.5)
	rainfall_mm = clampf(base_rain * (1.0 + variance) + biotic_bonus, 0.0, 50.0)


func _update_aquifer() -> void:
	var recharge := rainfall_mm * 0.4 \
		+ n_swales * 1.5 \
		+ n_rain_gardens * 2.0 \
		+ n_retention_ponds * 2.5 \
		- 2.0
	aquifer = clampf(aquifer + recharge, 0.0, 100.0)


func _update_scarcity() -> void:
	var target_scarcity := 100.0 - aquifer
	scarcity += (target_scarcity - scarcity) * 0.25
	scarcity -= (n_swales * 5 + n_rain_gardens * 4 + n_terraces * 6 + n_native_grasses * 1) * 0.05
	scarcity = clampf(scarcity, 0.0, 100.0)


func _update_flood() -> void:
	var flood_delta := maxf(0.0, rainfall_mm - 15.0) * 2.0
	flood_delta -= (n_swales + n_terraces * 1.2 + n_retention_ponds * 1.5) * 2.0
	flood_risk = clampf(flood_risk + flood_delta, 0.0, 100.0)


func _update_wildfire() -> void:
	var fire_delta := 3.0 if rainfall_mm < 5.0 else -0.5
	fire_delta -= n_native_grasses * 2.0
	wildfire_danger = clampf(wildfire_danger + fire_delta, 0.0, 100.0)


func _update_trust() -> void:
	if scarcity > 70.0:
		trust -= 2.0
	elif scarcity < 40.0:
		trust += 1.0
	trust = clampf(trust, 0.0, 100.0)


func _maybe_event() -> void:
	if _rng.randf() > EVENT_CHANCE:
		return
	var event: Dictionary = EVENTS[_rng.randi() % EVENTS.size()]

	# Apply any direct state changes from the event
	if event.has("wildfire"):
		wildfire_danger = clampf(wildfire_danger + event["wildfire"], 0.0, 100.0)
	if event.has("rain_bonus"):
		rainfall_mm = clampf(rainfall_mm + event["rain_bonus"], 0.0, 50.0)
	if event.has("trust"):
		trust = clampf(trust + event["trust"], 0.0, 100.0)
	if event.has("scarcity"):
		scarcity = clampf(scarcity + event["scarcity"], 0.0, 100.0)
	# ap_bonus is handled by GameWorld via the signal

	emit_signal("event_triggered", event)


func _check_win_loss() -> void:
	if scarcity >= 95.0:
		_game_ended = true
		emit_signal("game_over", "TAPS RUN DRY\nScarcity reached critical levels.")
		return
	if trust < 10.0:
		_game_ended = true
		emit_signal("game_over", "POLITICAL FAILURE\nPublic trust collapsed.")
		return
	if days_remaining <= 0:
		_game_ended = true
		if scarcity < 80.0:
			emit_signal("game_won")
		else:
			emit_signal("game_over", "DAY ZERO REACHED\nWater ran out before the crisis ended.")


func add_solution(solution_id: int) -> void:
	match solution_id:
		0: n_swales += 1
		1: n_rain_gardens += 1
		2: n_native_grasses += 1
		3: n_terraces += 1
		4: n_retention_ponds += 1


func get_state() -> Dictionary:
	return _build_state()


func _build_state() -> Dictionary:
	return {
		"days_remaining":  days_remaining,
		"scarcity":        scarcity,
		"flood_risk":      flood_risk,
		"wildfire_danger": wildfire_danger,
		"aquifer":         aquifer,
		"trust":           trust,
		"rainfall_mm":     rainfall_mm,
	}
