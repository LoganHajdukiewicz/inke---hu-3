extends RigidBody3D
class_name PaintDroplet

# Paint droplet configuration
@export var paint_value: int = 5  # How much paint this droplet gives
@export var lifetime: float = 10.0  # How long before disappearing
@export var collection_distance: float = 2.0  # Distance at which it's collected
@export var attraction_distance: float = 5.0  # Distance at which it starts moving toward player
@export var attraction_speed: float = 15.0  # Speed when moving toward player

# Visual configuration
@export var droplet_color: Color = Color(0.0, 0.8, 1.0)  # Cyan by default

# Internal state
var lifetime_timer: float = 0.0
var collected: bool = false
var attracted_to_player: bool = false
var target_player: Node3D = null

# References
var mesh_instance: MeshInstance3D
var collection_area: Area3D

func _ready():
	# FIXED: Add to Collectible group instead of Gear group
	add_to_group("Collectible")
	add_to_group("PaintDroplet")  # Specific group for paint droplets
	
	# Setup visual mesh
	setup_mesh()
	
	# Setup collection area
	setup_collection_area()
	
	# Add some initial random spin
	angular_velocity = Vector3(
		randf_range(-5, 5),
		randf_range(-5, 5),
		randf_range(-5, 5)
	)

func setup_mesh():
	"""Create the visual mesh for the paint droplet"""
	# BUGFIX: Check if mesh already exists from scene
	mesh_instance = get_node_or_null("Mesh")
	
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		
		# Create a small sphere mesh
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.15
		sphere_mesh.height = 0.3
		mesh_instance.mesh = sphere_mesh
		
		add_child(mesh_instance)
	
	# Create glowing material
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = droplet_color
	material.emission_enabled = true
	material.emission = droplet_color
	material.emission_energy_multiplier = 2.0
	
	mesh_instance.material_override = material
	
	# Add gentle pulsing animation
	create_pulse_animation()

func create_pulse_animation():
	"""Create a gentle pulsing glow effect"""
	# BUGFIX: Check if mesh_instance is valid before creating tween
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	var material = mesh_instance.material_override as StandardMaterial3D
	if material:
		tween.tween_property(material, "emission_energy_multiplier", 3.0, 0.5)
		tween.tween_property(material, "emission_energy_multiplier", 1.5, 0.5)

func setup_collection_area():
	"""Setup area for detecting player"""
	collection_area = Area3D.new()
	collection_area.name = "CollectionArea"
	
	# BUGFIX: Set proper collision layers/masks
	collection_area.collision_layer = 0  # Don't collide with anything
	collection_area.collision_mask = 1   # Detect player on layer 1
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = collection_distance
	collision_shape.shape = sphere_shape
	
	collection_area.add_child(collision_shape)
	add_child(collection_area)
	
	# Connect signals
	collection_area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float):
	# Update lifetime
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		fade_out_and_delete()
		return
	
	# Check for nearby player for attraction
	if not attracted_to_player and not collected:
		check_for_player_attraction()
	
	# Move toward player if attracted
	if attracted_to_player and target_player and is_instance_valid(target_player):
		move_toward_player(delta)

func check_for_player_attraction():
	"""Check if player is nearby to start attraction"""
	var players = get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return
	
	var player = players[0]
	
	# BUGFIX: Validate player is valid before accessing properties
	if not is_instance_valid(player):
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance <= attraction_distance:
		attracted_to_player = true
		target_player = player
		
		# Disable physics when attracted
		freeze = true
		gravity_scale = 0.0

func move_toward_player(delta: float):
	"""Move toward the player when attracted"""
	if not target_player or not is_instance_valid(target_player):
		attracted_to_player = false
		target_player = null
		freeze = false
		gravity_scale = 1.0
		return
	
	var direction = (target_player.global_position - global_position).normalized()
	var move_speed = attraction_speed * (1.0 + lifetime_timer * 0.5)  # Speed up over time
	
	global_position += direction * move_speed * delta
	
	# Check if close enough to collect
	var distance = global_position.distance_to(target_player.global_position)
	if distance < 1.0:
		collect()

func _on_body_entered(body: Node3D):
	"""Handle collision with player"""
	if collected:
		return
	
	if body.is_in_group("Player"):
		collect()

func collect():
	"""Collect this paint droplet"""
	if collected:
		return
	
	collected = true
	
	# Find PaintManager and add paint
	var paint_manager = get_node_or_null("/root/PaintManager")
	if paint_manager and paint_manager.has_method("add_paint"):
		paint_manager.add_paint(paint_value)
		print("Paint droplet collected! +", paint_value, " paint")
	else:
		# BUGFIX: Add warning if PaintManager not found
		print("WARNING: PaintManager not found or doesn't have add_paint method!")
	
	# Visual feedback
	create_collection_effect()
	
	# Delete after effect
	await get_tree().create_timer(0.2).timeout
	
	# BUGFIX: Check if still valid before freeing
	if is_instance_valid(self):
		queue_free()

func create_collection_effect():
	"""Create visual effect when collected"""
	# BUGFIX: Validate mesh_instance before creating effect
	if not mesh_instance or not is_instance_valid(mesh_instance):
		return
	
	# Quick scale up and fade
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(self, "scale", Vector3(2.0, 2.0, 2.0), 0.2)
	
	var material = mesh_instance.material_override as StandardMaterial3D
	if material:
		tween.tween_property(material, "emission_energy_multiplier", 8.0, 0.1)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.2)

func fade_out_and_delete():
	"""Fade out and delete when lifetime expires"""
	if collected:
		return
	
	# BUGFIX: Validate mesh_instance before fading
	if not mesh_instance or not is_instance_valid(mesh_instance):
		queue_free()
		return
	
	var material = mesh_instance.material_override as StandardMaterial3D
	if material:
		var tween = create_tween()
		tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
		tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.5)
		
		await tween.finished
	
	# BUGFIX: Check if still valid before freeing
	if is_instance_valid(self):
		queue_free()

# Public API for external scripts
func set_paint_value(value: int):
	"""Set the paint value of this droplet"""
	paint_value = value

func set_color(color: Color):
	"""Set the color of this droplet"""
	droplet_color = color
	if mesh_instance and is_instance_valid(mesh_instance) and mesh_instance.material_override:
		var material = mesh_instance.material_override as StandardMaterial3D
		material.albedo_color = color
		material.emission = color
