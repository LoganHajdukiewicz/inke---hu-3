extends Control

@export var combat_level_scene: PackedScene
@export var movement_level_scene: PackedScene

func _ready() -> void:
	# Punk-theme the menu buttons (spray sticker style, gamepad focus ring)
	var accents := {
		"MovementDemo": PunkTheme.PINK,
		"CombatDemo": PunkTheme.CYAN,
		"Quit": PunkTheme.RED,
	}
	var vbox := get_node_or_null("VBoxContainer")
	if vbox:
		vbox.add_theme_constant_override("separation", 14)
		var first: Button = null
		for child in vbox.get_children():
			if child is Button:
				PunkTheme.style_button(child, accents.get(String(child.name), PunkTheme.PINK), 26)
				if first == null:
					first = child
		if first:
			first.grab_focus()   # Controller can navigate immediately

func _on_movement_demo_pressed() -> void:
	get_tree().change_scene_to_packed(movement_level_scene)

func _on_combat_demo_pressed() -> void:
	get_tree().change_scene_to_packed(combat_level_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()
