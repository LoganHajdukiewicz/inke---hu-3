extends Node3D

@onready var area_3d = $Area3D

func _ready():
	area_3d.body_entered.connect(_on_body_entered)


func _on_body_entered(body):
	# Check if the body that entered is the player
	if body.is_in_group("player") or body.name == "Inke":
		reload_scene()

func reload_scene():
	print("Player fell through reset plane - reloading scene")
	get_tree().reload_current_scene()
