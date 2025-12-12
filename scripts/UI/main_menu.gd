extends Control

@export var combat_level_scene: PackedScene
@export var movement_level_scene: PackedScene

func _ready() -> void: pass

func _on_movement_demo_pressed() -> void:
	get_tree().change_scene_to_packed(movement_level_scene)

func _on_combat_demo_pressed() -> void:
	get_tree().change_scene_to_packed(combat_level_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()
