extends Area3D
class_name CRED

# CRED Properties
@export var cred_value: int = 10
@export var collected: bool = false
@export var rainbow_speed: float = 2.0
@export var float_amplitude: float = 0.2
@export var float_speed: float = 1.5
@export var rotation_speed: float = 1.0
@export var ground_offset: float = 0.3  # How high above ground to float

# Cutscene Properties
@export var cutscene_duration: float = 2.0
@export var zoom_strength: float = 0.3
@export var collection_delay: float = 1.0

# Node References
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# GameManager reference
var game_manager: Node = null

# Animation variables
var time_elapsed: float = 0.0
var original_position: Vector3
var ground_level: float = 0.0
var original_material: Material
var rainbow_material: ShaderMaterial
var is_playing_cutscene: bool = false
var cutscene_timer: float = 0.0

# Player reference for cutscene
var player: CharacterBody3D = null
var camera_controller: Node = null

# Signals
signal cred_collected(cred_node: CRED, value: int)
signal cutscene_started(cred_node: CRED)
signal cutscene_finished(cred_node: CRED)

func _ready():
	add_to_group("CRED")
	add_to_group("Collectible")
	
	# CRITICAL: Set collision properties to NOT affect player
	collision_layer = 0  # Don't exist on any physics layer
	collision_mask = 1   # Only detect player on layer 1
	monitorable = false  # Other things can't detect us
	monitoring = true    # We can detect others
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	
	# Find ground level and position above it
	call_deferred("find_ground_level")
	
	setup_rainbow_material()
	
	# Connect area signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	if game_manager and game_manager.has_signal("player_spawned"):
		game_manager.player_spawned.connect(_on_player_spawned)

func find_ground_level():
	"""Raycast down to find ground and position above it"""
	await get_tree().process_frame
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -100, 0)
	)
	query.collision_mask = 1
	
	var result = space_state.intersect_ray(query)
	if result:
		ground_level = result.position.y + ground_offset
		global_position.y = ground_level
		original_position = global_position
	else:
		ground_level = global_position.y
		original_position = global_position

func setup_rainbow_material():
	"""Create and apply rainbow shader material to the CRED sphere"""
	# Store original material
	if mesh_instance.get_surface_override_material_count() > 0:
		original_material = mesh_instance.get_surface_override_material(0)
	
	# Create shader material for rainbow effect
	rainbow_material = ShaderMaterial.new()
	
	# For 3D, we need a spatial shader
	var spatial_shader = Shader.new()
	spatial_shader.code = """
shader_type spatial;

uniform float speed : hint_range(0.0, 5.0) = 2.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	float time_offset = TIME * speed;
	float hue = fract(time_offset + UV.x * 0.5 + UV.y * 0.3);
	vec3 hsv = vec3(hue, saturation, brightness);
	ALBEDO = hsv_to_rgb(hsv);
	EMISSION = ALBEDO * 0.3;
}
"""
	
	rainbow_material.shader = spatial_shader
	rainbow_material.set_shader_parameter("speed", rainbow_speed)
	rainbow_material.set_shader_parameter("brightness", 1.2)
	rainbow_material.set_shader_parameter("saturation", 0.8)
	
	# Apply the material
	mesh_instance.set_surface_override_material(0, rainbow_material)

func _on_player_spawned(player_node: CharacterBody3D):
	"""Handle player spawning"""
	player = player_node
	
	# Try to get camera controller
	if player.has_node("CameraController"):
		camera_controller = player.get_node("CameraController")

func _process(delta: float):
	if collected:
		return
	
	time_elapsed += delta
	
	# Floating animation (stays above ground)
	var float_offset = sin(time_elapsed * float_speed) * float_amplitude
	global_position.y = ground_level + float_offset
	
	# Rotation animation
	rotation.y += rotation_speed * delta
	
	# Handle cutscene
	if is_playing_cutscene:
		handle_cutscene(delta)

func handle_cutscene(delta: float):
	"""Handle the collection cutscene"""
	cutscene_timer += delta
	
	if cutscene_timer >= cutscene_duration:
		end_cutscene()
	else:
		var progress = cutscene_timer / cutscene_duration
		
		# Scale effect
		var scale_factor = 1.0 + sin(progress * PI) * 0.3
		scale = Vector3.ONE * scale_factor
		
		# Brightness pulse
		if rainbow_material:
			var brightness = 1.2 + sin(progress * PI * 4.0) * 0.5
			rainbow_material.set_shader_parameter("brightness", brightness)

func _on_body_entered(body: Node3D):
	"""Handle when a body enters the CRED area"""
	if collected or is_playing_cutscene:
		return
	
	if body.is_in_group("Player") or body.name == "GearCollectionArea":
		var player_node = body
		
		if body.name == "GearCollectionArea":
			player_node = body.get_parent()
		
		if player_node and player_node.is_in_group("Player"):
			start_collection_cutscene(player_node)

func _on_area_entered(area: Area3D):
	"""Handle when an area enters the CRED area"""
	if collected or is_playing_cutscene:
		return
	
	if area.name == "GearCollectionArea":
		var player_node = area.get_parent()
		if player_node and player_node.is_in_group("Player"):
			start_collection_cutscene(player_node)

func start_collection_cutscene(player_node: CharacterBody3D):
	"""Start the collection cutscene"""
	if collected or is_playing_cutscene:
		return
	
	player = player_node
	is_playing_cutscene = true
	cutscene_timer = 0.0
	
	print("CRED: Starting collection cutscene")
	
	cutscene_started.emit(self)
	
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(false)
	
	apply_cutscene_camera_effects()
	
	await get_tree().create_timer(collection_delay).timeout
	collect_cred()

func apply_cutscene_camera_effects():
	"""Apply camera effects during cutscene"""
	if camera_controller and camera_controller.has_method("start_zoom_effect"):
		camera_controller.start_zoom_effect(zoom_strength, cutscene_duration)

func collect_cred():
	"""Actually collect the CRED and add to GameManager"""
	if collected:
		return
	
	collected = true
	
	if game_manager and game_manager.has_method("add_CRED"):
		game_manager.add_CRED(cred_value)
	else:
		print("CRED: Could not add CRED to GameManager!")
	
	cred_collected.emit(self, cred_value)
	queue_free()

func end_cutscene():
	"""End the collection cutscene"""
	is_playing_cutscene = false
	
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(true)
	
	cutscene_finished.emit(self)
	
	visible = false
	collision_shape.disabled = true
	
	# You win message
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var you_win = Label.new()
	you_win.text = "You win! Thank you for playing! <3 "
	you_win.add_theme_font_size_override("font_size", 50)
	you_win.position = Vector2(0, 0)
	you_win.visible = true
	canvas_layer.add_child(you_win)
	
	queue_free()

# Public methods
func set_cred_value(new_value: int):
	cred_value = new_value

func get_cred_value() -> int:
	return cred_value

func is_collected() -> bool:
	return collected

func force_collect():
	"""Force collect this CRED without cutscene"""
	if collected:
		return
	
	collect_cred()
	visible = false
	collision_shape.disabled = true
	queue_free()

# Save/Load support
func get_save_data() -> Dictionary:
	return {
		"collected": collected,
		"position": global_position,
		"cred_value": cred_value
	}

func load_save_data(data: Dictionary):
	collected = data.get("collected", false)
	cred_value = data.get("cred_value", 10)
	
	if collected:
		queue_free()
	else:
		var saved_position = data.get("position", Vector3.ZERO)
		if saved_position != Vector3.ZERO:
			global_position = saved_position
			original_position = saved_position
