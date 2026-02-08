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

@export_group("Bounce Settings")
@export var bounce_enabled: bool = true        # Whether boxes bounce the player
@export var bounce_force: float = 8.0         # Upward bounce velocity
@export var break_on_bounce: bool = true       # Break immediately after bounce
@export var bounce_damage: int = 2             # Damage dealt when bounced on

@export_group("Explosion Settings")
@export var explosion_force_min: float = 200.0  # Minimum horizontal explosion force
@export var explosion_force_max: float = 500.0  # Maximum horizontal explosion force
@export var explosion_upward_min: float = 150.0   # Minimum upward boost
@export var explosion_upward_max: float = 250.0  # Maximum upward boost
@export var spawn_spread: float = 2.5           # How far apart gears spawn
@export var add_spin: bool = true                # Add random spinning to gears
@export var spin_intensity: float = 10.0        # How fast gears spin

# References to child nodes
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var damage_area: Area3D = $DamageDetection
@onready var particles: GPUParticles3D = $BreakParticles if has_node("BreakParticles") else null
@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

# Preloaded scenes
var gear_scene = preload("res://scenes/items/Collectibles/six_teeth_gear.tscn")

# State
var is_broken: bool = false
var game_manager
var just_bounced: bool = false  # Prevent multiple bounces in rapid succession

func _ready():
	current_health = max_health
	game_manager = get_node("/root/GameManager")
	
	# Add to Breakables group
	if not is_in_group("Breakables"):
		add_to_group("Breakables")
		print("Box ", name, " added to Breakables group")
	
	# Connect damage detection area
	if damage_area:
		damage_area.body_entered.connect(_on_damage_body_entered)
		damage_area.area_entered.connect(_on_damage_area_entered)
	
	# Setup bounce detection if enabled
	if bounce_enabled:
		setup_bounce_detection()
	
	# Setup material for hit feedback
	if mesh and mesh.get_active_material(0):
		var material = mesh.get_active_material(0).duplicate()
		mesh.set_surface_override_material(0, material)

func setup_bounce_detection():
	"""
	Setup bounce detection using an Area3D.
	
	WHY WE USE AREA3D:
	RigidBody3D.body_entered doesn't reliably detect CharacterBody3D collisions.
	Area3D.body_entered works perfectly for detecting when CharacterBody3D enters.
	"""
	# Create Area3D for bounce detection
	var bounce_area = Area3D.new()
	bounce_area.name = "BounceDetectionArea"
	
	# Set collision - detect player only
	bounce_area.collision_layer = 0  # Don't exist on any layer
	bounce_area.collision_mask = 1   # Detect layer 1 (where player is)
	bounce_area.monitoring = true
	bounce_area.monitorable = false
	
	add_child(bounce_area)
	
	# Create collision shape - a box on top of the crate
	var bounce_collision = CollisionShape3D.new()
	var bounce_shape = BoxShape3D.new()
	
	# Get the main collision box size
	if collision and collision.shape is BoxShape3D:
		var box_shape = collision.shape as BoxShape3D
		# Make detection area slightly larger and positioned on top
		bounce_shape.size = Vector3(
			box_shape.size.x * 1.2,  # Wider for easier stomping
			0.4,  # Thin detection zone on top
			box_shape.size.z * 1.2
		)
		# Position on top of the box
		bounce_collision.position = Vector3(0, box_shape.size.y * 0.5 + 0.2, 0)
	else:
		# Default size
		bounce_shape.size = Vector3(1.2, 0.4, 1.2)
		bounce_collision.position = Vector3(0, 0.7, 0)
	
	bounce_collision.shape = bounce_shape
	bounce_area.add_child(bounce_collision)
	
	# Connect to body_entered signal
	bounce_area.body_entered.connect(_on_bounce_area_body_entered)
	
	print("Box ", name, " - Bounce detection Area3D created!")
	print("  Detection position: ", bounce_collision.position)
	print("  Detection size: ", bounce_shape.size)

func _on_bounce_area_body_entered(body: Node3D):
	"""
	Called when something enters the bounce detection Area3D.
	This is much more reliable than RigidBody collision detection!
	"""
	print("=== BOX COLLISION DETECTED ===")
	print("Body: ", body.name if body else "NULL")
	print("Is in Player group: ", body.is_in_group("Player") if body else false)
	print("Is broken: ", is_broken)
	print("Just bounced: ", just_bounced)
	
	if is_broken or just_bounced:
		print("REJECTED: Box is broken or just bounced")
		return
	
	# Check if it's the player
	if not body.is_in_group("Player"):
		print("REJECTED: Not in Player group")
		return
	
	var player = body as CharacterBody3D
	if not player:
		print("REJECTED: Cannot cast to CharacterBody3D")
		return
	
	print("Player velocity.y: ", player.velocity.y)
	print("Player Y position: ", player.global_position.y)
	print("Box Y position: ", global_position.y)
	print("Position difference: ", player.global_position.y - global_position.y)
	
	# CRITICAL: Only bounce if player is falling downward
	# This prevents bouncing when the player hits the side of the box
	if player.velocity.y >= -1.0:
		print("REJECTED: Player not falling fast enough (", player.velocity.y, ")")
		return
	
	print("=== PLAYER STOMPED ON BOX! ===")
	print("Player velocity before bounce: ", player.velocity)
	print("Break on bounce: ", break_on_bounce)
	print("Bounce damage: ", bounce_damage)
	
	# Apply bounce to player
	apply_bounce_to_player(player)
	
	# Box reaction - DEFERRED to avoid physics errors
	if break_on_bounce:
		print("Calling take_damage with amount: ", bounce_damage)
		call_deferred("take_damage", bounce_damage)
	else:
		print("Not breaking - just squashing")
		call_deferred("squash_and_stretch")

func apply_bounce_to_player(player: CharacterBody3D):
	"""
	Apply upward bounce velocity to the player.
	This creates that classic platformer stomp feel!
	"""
	# Set upward velocity for bounce
	player.velocity.y = bounce_force
	
	# Preserve horizontal momentum with slight reduction
	player.velocity.x *= 0.9
	player.velocity.z *= 0.9
	
	print("Bounce applied! New velocity: ", player.velocity)
	
	# Visual feedback
	call_deferred("squash_and_stretch")
	
	# Prevent multiple bounces in quick succession
	just_bounced = true
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		just_bounced = false
	
	# Give player brief invulnerability
	if player.has_method("set_invulnerable_without_flash"):
		player.set_invulnerable_without_flash(0.5)

func squash_and_stretch():
	"""
	Squash and stretch animation - classic animation principle!
	Makes the bounce feel more dynamic and satisfying.
	"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	var original_scale = mesh.scale
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	
	# Squash down
	tween.tween_property(mesh, "scale", Vector3(1.2, 0.6, 1.2), 0.1)
	# Spring back
	tween.tween_property(mesh, "scale", original_scale, 0.3)

func _on_damage_body_entered(body: Node3D):
	"""Detect when player or projectile hits the crate"""
	if body.is_in_group("Player"):
		var player = body as CharacterBody3D
		if player.has_node("AttackManager"):
			var attack_manager = player.get_node("AttackManager")
			if attack_manager.has_method("get_is_attacking") and attack_manager.get_is_attacking():
				take_damage(1)
	
	if body.is_in_group("Projectile") or body.is_in_group("Damaging"):
		var damage = 1
		if body.has_method("get_damage"):
			damage = body.get_damage()
		take_damage(damage)
		
		if body.has_method("queue_free"):
			body.queue_free()

func _on_damage_area_entered(area: Area3D):
	"""Detect area-based damage"""
	if area.is_in_group("Explosion") or area.is_in_group("Damaging"):
		var damage = 1
		if area.has_method("get_damage"):
			damage = area.get_damage()
		take_damage(damage)

func take_damage(amount: int):
	"""Apply damage to the crate"""
	print("=== TAKE_DAMAGE CALLED ===")
	print("Amount: ", amount)
	print("Current health: ", current_health)
	print("Is broken: ", is_broken)
	
	if is_broken:
		print("REJECTED: Already broken")
		return
	
	current_health -= amount
	print("Crate took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	# Visual feedback
	flash_white()
	shake_crate()
	
	if current_health <= 0:
		print("Health <= 0, calling break_crate()")
		break_crate()
	else:
		print("Health still above 0, not breaking yet")

func flash_white():
	"""Flash the crate white briefly"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		var original_color = material.albedo_color
		
		var tween = create_tween()
		tween.tween_property(material, "albedo_color", Color.WHITE, 0.05)
		tween.tween_property(material, "albedo_color", original_color, 0.1)

func shake_crate():
	"""Small shake animation"""
	if not is_instance_valid(self):
		return
		
	var original_pos = position
	var shake_amount = 0.1
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(self, "position", original_pos + Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos - Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)

func break_crate():
	"""Destroy the crate and spawn loot"""
	print("=== BREAK_CRATE CALLED ===")
	print("Is broken: ", is_broken)
	
	if is_broken:
		print("REJECTED: Already broken")
		return
	
	is_broken = true
	print("Crate breaking!")
	
	# Spawn particles
	if particles:
		print("Emitting particles")
		particles.emitting = true
	else:
		print("No particles node found")
	
	# Spawn loot
	print("Spawning loot...")
	spawn_loot()
	
	# Visual destruction
	print("Playing break animation...")
	play_break_animation()
	
	# Clean up
	print("Waiting 0.5s before queue_free...")
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		print("Calling queue_free()")
		queue_free()
	else:
		print("Instance no longer valid")

func play_break_animation():
	"""
	Animated destruction of the crate.
	Uses set_deferred to avoid physics errors.
	"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	# Disable collisions using deferred calls
	if collision:
		collision.set_deferred("disabled", true)
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	
	# Disable contact monitoring
	set_deferred("contact_monitor", false)
	
	# Break animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Spin and shrink
	tween.tween_property(self, "rotation", rotation + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), 0.3)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	
	# Fade out
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(material, "albedo_color:a", 0.0, 0.3)

func spawn_loot():
	"""Spawn gears with explosive scatter effect!"""
	if not is_instance_valid(self):
		return
		
	var spawn_position = global_position + Vector3(0, 0.5, 0)
	
	if drops_gears and gear_scene:
		var gear_count = randi_range(gear_count_min, gear_count_max)
		
		for i in range(gear_count):
			var gear = gear_scene.instantiate()
			get_parent().add_child(gear)
			
			# Spawn position with spread
			var offset = Vector3(
				randf_range(-spawn_spread, spawn_spread),
				randf_range(0.3, 1.0),
				randf_range(-spawn_spread, spawn_spread)
			)
			gear.global_position = spawn_position + offset
			
			# Explosive velocity
			if gear is RigidBody3D:
				var explosion_direction = Vector3(
					randf_range(-1.0, 1.0),
					randf_range(0.5, 1.0),
					randf_range(-1.0, 1.0)
				).normalized()
				
				var explosion_force = randf_range(explosion_force_min, explosion_force_max)
				var impulse = explosion_direction * explosion_force
				impulse.y += randf_range(explosion_upward_min, explosion_upward_max)
				
				gear.apply_impulse(impulse)
				
				if add_spin:
					var torque = Vector3(
						randf_range(-spin_intensity, spin_intensity),
						randf_range(-spin_intensity, spin_intensity),
						randf_range(-spin_intensity, spin_intensity)
					)
					gear.apply_torque_impulse(torque)
