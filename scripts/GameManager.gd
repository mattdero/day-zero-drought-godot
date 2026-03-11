extends Node

# GameManager is an autoload singleton — available everywhere as GameManager.*

const VERSION := "0.1.0"

# Persistent player state
var current_level: int = 1
var score: int = 0
var high_score: int = 0
var tutorial_shown: bool = false

const SAVE_PATH := "user://save.cfg"


func _ready() -> void:
	_load_save()


# ──────────────────────────────────────────
#  Save / Load
# ──────────────────────────────────────────

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = cfg.get_value("player", "high_score", 0)
		current_level = cfg.get_value("player", "current_level", 1)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "high_score", high_score)
	cfg.set_value("player", "current_level", current_level)
	cfg.save(SAVE_PATH)


# ──────────────────────────────────────────
#  Score helpers
# ──────────────────────────────────────────

func add_score(amount: int) -> void:
	score += amount
	if score > high_score:
		high_score = score
		save()


func reset_score() -> void:
	score = 0
