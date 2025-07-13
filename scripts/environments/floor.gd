extends StaticBody3D
class_name Floor

enum FloorType {
	NORMAL,
	SPRING
}

@export var floor_type: FloorType = FloorType.NORMAL
@export var spring_force: float = 20.0
@export var spring_cooldown: float = 0.5
@export var spring_tween_duration: float = 0.1

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var spring_area: Area3D = $SpringArea
@onready var spring_collision: CollisionShape3D = $SpringArea/CollisionShape3D

var players_on_floor: Array[CharacterBody3D] = []
var spring_cooldown_timer: float = 0.0

func _ready():
	setup_floor_type()
	
	# Connect spring area signals
	if spring_area:
		spring_area.body_entered.connect(_on_spring_area_body_entered)
		spring_area.body_exited.connect(_on_spring_area_body_exited)

func _process(delta):
	if spring_cooldown_timer > 0:
		spring_cooldown_timer -= delta
	
	# Handle spring bouncing for players on the floor
	if floor_type == FloorType.SPRING and spring_cooldown_timer <= 0:
		if players_on_floor.size() > 0:
			activate_spring()

func setup_floor_type():
	"""Setup the floor based on the selected type"""
	match floor_type:
		FloorType.NORMAL:
			setup_normal_floor()
		FloorType.SPRING:
			setup_spring_floor()

func setup_normal_floor():
	"""Setup a normal floor"""
	# Set normal green color
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(0, 0.41793, 0, 1)  # Green
	
	# Disable spring area
	if spring_area:
		spring_area.monitoring = false
		spring_area.visible = false

func setup_spring_floor():
	"""Setup a spring floor"""
	# Set spring color (bouncy orange/yellow)
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(1.0, 0.6, 0.0, 1)  # Orange
	material.metallic = 0.2
	material.roughness = 0.3
	
	# Enable spring area
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		# Make sure the collision shape matches the floor size
		var floor_shape = collision_shape.shape as BoxShape3D
		if floor_shape and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape.size.x, floor_shape.size.y + 0.5, floor_shape.size.z)
				spring_collision.position.y = floor_shape.size.y * 0.25

func _on_spring_area_body_entered(body):
	"""When a player enters the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		if not players_on_floor.has(body):
			players_on_floor.append(body)

func _on_spring_area_body_exited(body):
	"""When a player exits the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		players_on_floor.erase(body)

func activate_spring():
	"""Activate the spring effect for all players on the floor"""
	for player in players_on_floor:
		if player and is_instance_valid(player):
			apply_spring_effect(player)
	
	# Set cooldown
	spring_cooldown_timer = spring_cooldown

func apply_spring_effect(player: CharacterBody3D):
	"""Apply spring effect to a specific player"""
	if not player:
		return
	
	# Reset double jump ability when using spring
	if player.has_method("get") and player.get("has_double_jumped") != null:
		player.has_double_jumped = false
		player.can_double_jump = true
	
	# Create a tween for the spring effect
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Store original position
	var original_y = player.global_position.y
	
	# Quick upward movement (smaller lift to feel more responsive)
	tween.tween_method(
		func(pos_y): _set_player_y_position(player, pos_y),
		original_y,
		original_y + 0.3,  # Smaller lift for more responsive feel
		spring_tween_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# Apply upward velocity immediately (don't wait for tween)
	_apply_spring_velocity(player)
	
	# Also apply a callback after tween to ensure velocity is set
	tween.tween_callback(func(): _apply_spring_velocity(player)).set_delay(spring_tween_duration)

func _set_player_y_position(player: CharacterBody3D, y_pos: float):
	"""Helper function to set player Y position"""
	if player and is_instance_valid(player):
		player.global_position.y = y_pos

func _apply_spring_velocity(player: CharacterBody3D):
	"""Apply upward velocity to the player"""
	if player and is_instance_valid(player):
		# Set the velocity directly - this should override gravity
		player.velocity.y = spring_force
		
		# Force the player into jumping state immediately
		if player.has_method("get") and player.get("state_machine"):
			var state_machine = player.get("state_machine")
			if state_machine and state_machine.has_method("change_state"):
				state_machine.change_state("JumpingState")
		
		# Also call move_and_slide to ensure the velocity is applied
		player.move_and_slide()
		
		print("Spring activated! Player bounced with force: ", spring_force, " Current velocity.y: ", player.velocity.y)
