extends Area3D
class_name PaintDroplet

# Paint droplet configuration
@export var paint_value: int = 5  # How much paint this droplet gives
@export var lifetime: float = 10.0  # How long before disappearing
@export var collection_distance: float = 2.0  # Distance at which it's collected
@export var attraction_distance: float = 5.0  # Distance at which it starts moving toward player
@export var attraction_speed: float = 15.0  # Speed when moving toward player
@export var ground_offset: float = 0.2  # How high above ground to float
@export var bob_height: float = 0.15  # Bobbing animation height
@export var bob_speed: float = 2.0  # Bobbing animation speed

# Visual configuration
@export var droplet_color: Color = Color(0.0, 0.8, 1.0)  # Cyan by default

# Internal state
var lifetime_timer: float = 0.0
var collected: bool = false
var attracted_to_player: bool = false
var target_player: Node3D = null
var ground_level: float = 0.0
var time_passed: float = 0.0

# References
var mesh_instance: MeshInstance3D

func _ready():
	# Add to Collectible groups
	add_to_group("Collectible")
	add_to_group("PaintDroplet")
	
	# CRITICAL: Set collision properties to NOT affect player
	collision_layer = 0  # Don't exist on any physics layer
	collision_mask = 1   # Only detect player on layer 1
	monitorable = false  # Other things can't detect us
	monitoring = true    # We can detect others
	
	# Find ground level
	find_ground_level()
	
	# Setup visual mesh
	setup_mesh()
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func find_ground_level():
	"""Raycast down to find ground and position above it"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -100, 0)
	)
	query.collision_mask = 1  # Check ground layer
	
	var result = space_state.intersect_ray(query)
	if result:
		ground_level = result.position.y + ground_offset
		global_position.y = ground_level
	else:
		ground_level = global_position.y

func setup_mesh():
	"""Create the visual mesh for the paint droplet"""
	# Check if mesh already exists from scene
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

func _physics_process(delta: float):
	# Update lifetime
	lifetime_timer += delta
	if lifetime_timer >= lifetime:
		fade_out_and_delete()
		return
	
	# Bobbing animation (only when not attracted)
	if not attracted_to_player and not collected:
		time_passed += delta
		var bob_offset = sin(time_passed * bob_speed) * bob_height
		global_position.y = ground_level + bob_offset
		
		# Check for nearby player for attraction
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
	
	if not is_instance_valid(player):
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance <= attraction_distance:
		attracted_to_player = true
		target_player = player

func move_toward_player(delta: float):
	"""Move toward the player when attracted"""
	if not target_player or not is_instance_valid(target_player):
		attracted_to_player = false
		target_player = null
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

func _on_area_entered(area: Area3D):
	"""Handle area entered (for player's collection area)"""
	if collected:
		return
	
	if area.name == "GearCollectionArea":
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
		print("WARNING: PaintManager not found or doesn't have add_paint method!")
	
	# Visual feedback
	create_collection_effect()
	
	# Delete after effect
	await get_tree().create_timer(0.2).timeout
	
	if is_instance_valid(self):
		queue_free()

func create_collection_effect():
	"""Create visual effect when collected"""
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
	
	if not mesh_instance or not is_instance_valid(mesh_instance):
		queue_free()
		return
	
	var material = mesh_instance.material_override as StandardMaterial3D
	if material:
		var tween = create_tween()
		tween.tween_property(material, "albedo_color:a", 0.0, 0.5)
		tween.tween_property(material, "emission_energy_multiplier", 0.0, 0.5)
		
		await tween.finished
	
	if is_instance_valid(self):
		queue_free()

# Public API
func set_paint_value(value: int):
	paint_value = value

func set_color(color: Color):
	droplet_color = color
	if mesh_instance and is_instance_valid(mesh_instance) and mesh_instance.material_override:
		var material = mesh_instance.material_override as StandardMaterial3D
		material.albedo_color = color
		material.emission = color
