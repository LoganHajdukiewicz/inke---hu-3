extends Node2D

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const DELAY: float = 5.0

func _ready() -> void:
	var timer = get_tree().create_timer(DELAY)
	timer.timeout.connect(_go_to_main_menu)

func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
