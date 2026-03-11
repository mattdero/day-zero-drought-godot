extends Control

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/GameWorld.tscn")


func _on_settings_pressed() -> void:
	# TODO: Replace with actual settings scene path
	# get_tree().change_scene_to_file("res://scenes/Settings.tscn")
	print("Settings pressed — settings scene not yet created.")


func _on_quit_pressed() -> void:
	get_tree().quit()
