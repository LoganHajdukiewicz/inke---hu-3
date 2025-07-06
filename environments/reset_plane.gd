extends Node3D

@onready var area_3d = $Area3D

func _ready():
	# Connect the area entered signal
	area_3d.body_entered.connect(_on_body_entered)
	print("Reset plane initialized - will reload scene when player falls")

func _on_body_entered(body):
	# Check if the body that entered is the player
	if body.is_in_group("player") or body.name == "Inke":
		reload_scene()

func reload_scene():
	print("Player fell through reset plane - reloading scene")
	get_tree().reload_current_scene()
