extends RigidBody3D
class_name Box

# Crate properties
@export_group("Crate Health")
@export var max_health: int = 2  # How many hits to break
@export var current_health: int = 2

@export_group("Loot Drops")
@export var drops_gears: bool = true
@export var gear_count_min: int = 50
@export var gear_count_max: int = 50


# References to child nodes
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var damage_area: Area3D = $DamageDetection
@onready var particles: GPUParticles3D = $BreakParticles if has_node("BreakParticles") else null
@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

# Preloaded scenes
var gear_scene = preload("res://scenes/items/Gears/six_teeth_gear.tscn")  # Adjust path as needed

# State
var is_broken: bool = false
var game_manager

func _ready():
	current_health = max_health
	game_manager = get_node("/root/GameManager")
	
	# Connect damage detection area
	if damage_area:
		damage_area.body_entered.connect(_on_damage_body_entered)
		damage_area.area_entered.connect(_on_damage_area_entered)
	
	# Setup material for hit feedback
	if mesh and mesh.get_active_material(0):
		# Clone material so each crate can flash independently
		var material = mesh.get_active_material(0).duplicate()
		mesh.set_surface_override_material(0, material)

func _on_damage_body_entered(body: Node3D):
	"""Detect when player or projectile hits the crate"""
	# Check if it's the player attacking
	if body.is_in_group("Player"):
		var player = body as CharacterBody3D
		# Check if player has an AttackManager and is currently attacking
		if player.has_node("AttackManager"):
			var attack_manager = player.get_node("AttackManager")
			if attack_manager.has_method("get_is_attacking") and attack_manager.get_is_attacking():
				take_damage(1)
	
	# Check for projectiles or other damage sources
	if body.is_in_group("Projectile") or body.is_in_group("Damaging"):
		var damage = 1
		if body.has_method("get_damage"):
			damage = body.get_damage()
		take_damage(damage)
		
		# Destroy projectile
		if body.has_method("queue_free"):
			body.queue_free()

func _on_damage_area_entered(area: Area3D):
	"""Detect area-based damage (like explosions)"""
	if area.is_in_group("Explosion") or area.is_in_group("Damaging"):
		var damage = 1
		if area.has_method("get_damage"):
			damage = area.get_damage()
		take_damage(damage)

func take_damage(amount: int):
	"""Apply damage to the crate"""
	if is_broken:
		return
	
	current_health -= amount
	print("Crate took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	if current_health <= 0:
		break_crate()


func flash_white():
	"""Flash the crate white briefly"""
	if not mesh:
		return
	
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		var original_color = material.albedo_color
		
		var tween = create_tween()
		tween.tween_property(material, "albedo_color", Color.WHITE, 0.05)
		tween.tween_property(material, "albedo_color", original_color, 0.1)

func shake_crate():
	"""Small shake animation"""
	var original_pos = position
	var shake_amount = 0.1
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	
	# Shake left and right
	tween.tween_property(self, "position", original_pos + Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos - Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)

func break_crate():
	"""Destroy the crate and spawn loot"""
	if is_broken:
		return
	
	is_broken = true
	print("Crate broken!")
	
	# Spawn break particles
	if particles:
		particles.emitting = true
	
	# Spawn loot
	spawn_loot()
	
	# Visual destruction effect
	play_break_animation()
	
	# Wait for effects to finish, then destroy
	await get_tree().create_timer(0.5).timeout
	queue_free()

func play_break_animation():
	"""Animated destruction of the crate"""
	if not mesh:
		return
	
	# Disable collision immediately
	if collision:
		collision.disabled = true
	if damage_area:
		damage_area.monitoring = false
	
	# Break into pieces animation (scale down and fade)
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Spin and shrink
	tween.tween_property(self, "rotation", rotation + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), 0.3)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	
	# Fade out if material supports it
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(material, "albedo_color:a", 0.0, 0.3)

func spawn_loot():
	"""Spawn gears and health pickups"""
	var spawn_position = global_position + Vector3(0, 0.5, 0)
	
	# Spawn gears
	if drops_gears and gear_scene:
		var gear_count = randi_range(gear_count_min, gear_count_max)
		for i in range(gear_count):
			var gear = gear_scene.instantiate()
			get_parent().add_child(gear)
			
			# Randomize spawn position slightly
			var offset = Vector3(
				randf_range(-0.5, 0.5),
				randf_range(0.2, 0.8),
				randf_range(-0.5, 0.5)
			)
			gear.global_position = spawn_position + offset
			
			# Give it some random velocity for scatter effect
			if gear is RigidBody3D:
				var impulse = Vector3(
					randf_range(-3, 3),
					randf_range(3, 6),
					randf_range(-3, 3)
				)
				gear.apply_impulse(impulse)
	

# Optional: Make crate react to nearby explosions
func _on_explosion_nearby(explosion_position: Vector3, explosion_force: float):
	"""React to nearby explosions"""
	var distance = global_position.distance_to(explosion_position)
	var damage = int(explosion_force / max(distance, 1.0))
	take_damage(max(1, damage))
