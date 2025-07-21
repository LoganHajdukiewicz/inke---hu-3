extends Area3D
class_name CRED

# CRED Properties
@export var cred_value: int = 10
@export var collected: bool = false
@export var rainbow_speed: float = 2.0
@export var float_amplitude: float = 0.2
@export var float_speed: float = 1.5
@export var rotation_speed: float = 1.0

# Cutscene Properties
@export var cutscene_duration: float = 2.0
@export var zoom_strength: float = 0.3
@export var collection_delay: float = 1.0

# Node References
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
#@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

# GameManager reference
var game_manager: Node = null

# Animation variables
var time_elapsed: float = 0.0
var original_position: Vector3
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
	# Set up the area
	add_to_group("CRED")
	
	# Store original position for floating animation
	original_position = global_position
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	if not game_manager:
		print("CRED: Warning - GameManager not found!")
	
	# Set up rainbow material
	setup_rainbow_material()
	
	# Connect area signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Connect to GameManager signals if available
	if game_manager and game_manager.has_signal("player_spawned"):
		game_manager.player_spawned.connect(_on_player_spawned)
	
	print("CRED initialized with value: ", cred_value)

func setup_rainbow_material():
	"""Create and apply rainbow shader material to the CRED sphere"""
	if not mesh_instance:
		print("CRED: No MeshInstance3D found for rainbow material!")
		return
	
	# Store original material
	if mesh_instance.get_surface_override_material_count() > 0:
		original_material = mesh_instance.get_surface_override_material(0)
	
	# Create shader material for rainbow effect
	rainbow_material = ShaderMaterial.new()
	
	# Create the rainbow shader code
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

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
	COLOR = vec4(hsv_to_rgb(hsv), 1.0);
}
"""
	
	# For 3D, we need a different shader type
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
	print("CRED: Rainbow material applied")

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
	
	# Floating animation
	var float_offset = sin(time_elapsed * float_speed) * float_amplitude
	global_position.y = original_position.y + float_offset
	
	# Rotation animation
	rotation.y += rotation_speed * delta
	
	# Handle cutscene
	if is_playing_cutscene:
		handle_cutscene(delta)

func handle_cutscene(delta: float):
	"""Handle the collection cutscene"""
	cutscene_timer += delta
	
	if cutscene_timer >= cutscene_duration:
		# End cutscene
		end_cutscene()
	else:
		# Cutscene effects (camera zoom, slow motion, etc.)
		var progress = cutscene_timer / cutscene_duration
		
		# Scale effect - grow then shrink
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
	
	# Check if it's the player or player's collection area
	if body.is_in_group("Player") or body.name == "GearCollectionArea":
		var player_node = body
		
		# If it's the collection area, get the parent (player)
		if body.name == "GearCollectionArea":
			player_node = body.get_parent()
		
		if player_node and player_node.is_in_group("Player"):
			start_collection_cutscene(player_node)

func _on_area_entered(area: Area3D):
	"""Handle when an area enters the CRED area"""
	if collected or is_playing_cutscene:
		return
	
	# Check if it's a gear collection area from the player
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
	
	# Emit cutscene started signal
	cutscene_started.emit(self)
	
	# Disable player movement if possible
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(false)
	
	# Camera effects
	apply_cutscene_camera_effects()
	
	# Play collection sound if available
	#if audio_player and audio_player.stream:
	#	audio_player.play()
	
	# Schedule collection after delay
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
	
	# Add CRED to GameManager
	if game_manager and game_manager.has_method("add_CRED"):
		game_manager.add_CRED(cred_value)
	else:
		print("CRED: Could not add CRED to GameManager!")
	
	print("CRED: Collected! Value: ", cred_value)
	
	# Emit collection signal
	cred_collected.emit(self, cred_value)
	queue_free()

func end_cutscene():
	"""End the collection cutscene"""
	is_playing_cutscene = false
	
	# Re-enable player movement
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(true)
	
	# Emit cutscene finished signal
	cutscene_finished.emit(self)
	
	# Hide and remove the CRED
	visible = false
	collision_shape.disabled = true
	
	# Wait a moment then queue free
	queue_free()

# === PUBLIC METHODS ===

func set_cred_value(new_value: int):
	"""Set the CRED value"""
	cred_value = new_value

func get_cred_value() -> int:
	"""Get the CRED value"""
	return cred_value

func is_collected() -> bool:
	"""Check if this CRED has been collected"""
	return collected

func force_collect():
	"""Force collect this CRED without cutscene"""
	if collected:
		return
	
	collect_cred()
	visible = false
	collision_shape.disabled = true
	queue_free()

# === SAVE/LOAD SUPPORT ===

func get_save_data() -> Dictionary:
	"""Get save data for this CRED"""
	return {
		"collected": collected,
		"position": global_position,
		"cred_value": cred_value
	}

func load_save_data(data: Dictionary):
	"""Load save data for this CRED"""
	collected = data.get("collected", false)
	cred_value = data.get("cred_value", 10)
	
	if collected:
		# If already collected, remove from scene
		queue_free()
	else:
		# Set position if provided
		var saved_position = data.get("position", Vector3.ZERO)
		if saved_position != Vector3.ZERO:
			global_position = saved_position
			original_position = saved_position
