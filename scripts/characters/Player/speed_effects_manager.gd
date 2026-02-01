extends Node
class_name SpeedEffectsManager

@export_category("Speed Settings")
@export var enabled: bool = true  # Enable/disable motion lines
@export var speed_threshold: float = 15.0  # Speed at which lines start appearing
@export var max_speed: float = 50.0  # Speed at which lines are at maximum intensity
@export var fade_speed: float = 3.0  # How quickly lines fade in/out

@export_category("Motion Lines Appearance")
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.8)  # White with transparency
@export var line_count_min: int = 12  # Minimum number of radial lines
@export var line_count_max: int = 20  # Maximum number of radial lines
@export var line_thickness_primary: float = 0.005  # Thickness of main lines
@export var line_thickness_secondary: float = 0.03  # Thickness of underlayer lines
@export var line_length_min: float = 0.3  # Minimum distance from center where lines start
@export var line_length_max: float = 0.9  # Maximum distance from center where lines end
@export var line_individual_length_variation: float = 0.5  # How much each line can vary in length (0.0 = no variation, 1.0 = max variation)
@export var line_sharpness: float = 0.95  # How sharp/crisp the lines are (higher = sharper)

# Internal state
var shader_material: ShaderMaterial
var color_rect: ColorRect
var canvas_layer: CanvasLayer
var current_intensity: float = 0.0
var actual_line_count: int = 16  # Randomized on setup

var player: CharacterBody3D
var camera_controller: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	camera_controller = player.get_node("CameraController") if player.has_node("CameraController") else null
	
	# Randomize line count on startup
	randomize_line_count()
	
	call_deferred("setup_effect")

func randomize_line_count():
	"""Randomize the number of speed lines within the specified range"""
	actual_line_count = randi_range(line_count_min, line_count_max)
	print("Speed lines randomized to: ", actual_line_count, " lines")

func setup_effect():
	"""Setup the motion lines effect"""
	await get_tree().process_frame
	
	if not is_inside_tree():
		call_deferred("setup_effect")
		return
	
	# Clean up any existing effect
	cleanup_effect()
	
	# Don't create anything if disabled
	if not enabled:
		print("Motion lines disabled")
		return
	
	# Create canvas layer
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MotionLinesCanvas"
	canvas_layer.layer = 100  # Draw on top
	
	# Create ColorRect for fullscreen shader
	color_rect = ColorRect.new()
	color_rect.name = "MotionLinesRect"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create shader material
	shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = get_motion_lines_shader()
	
	shader_material.shader = shader
	setup_shader_parameters()
	
	color_rect.material = shader_material
	
	# Add to scene
	canvas_layer.add_child(color_rect)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(canvas_layer)
		print("Anime-style motion lines created with ", actual_line_count, " lines!")
	else:
		print("Could not add motion lines - no current scene found")

func cleanup_effect():
	"""Clean up existing effect"""
	if canvas_layer and is_instance_valid(canvas_layer):
		canvas_layer.queue_free()
		canvas_layer = null
	
	shader_material = null
	color_rect = null
	current_intensity = 0.0

func get_motion_lines_shader() -> String:
	return """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform int line_count = 16;
uniform float line_thickness_primary = 0.005;
uniform float line_thickness_secondary = 0.03;
uniform float line_length_min = 0.3;
uniform float line_length_max = 0.9;
uniform float line_length_variation = 0.3;
uniform float line_sharpness = 0.95;
uniform float animation_speed = 1.0;

// Simple hash function for pseudo-random values per line
float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 uv = UV - center;
	
	// Calculate distance and angle from center
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	
	// Normalize angle to 0-TAU range
	float angle_normalized = mod(angle + 3.14159265359, 6.28318530718);
	
	// Calculate which line segment we're in
	float line_angle = 6.28318530718 / float(line_count);
	float line_index = floor(angle_normalized / line_angle);
	float line_position = mod(angle_normalized, line_angle) / line_angle;
	
	// Generate per-line random values using hash
	float line_random = hash(line_index);
	
	// Calculate random length for this specific line
	float length_range = line_length_max - line_length_min;
	float random_length_offset = line_random * line_length_variation * length_range;
	float this_line_max = line_length_max - random_length_offset;
	
	// Create dual-thickness lines
	// Primary (thin) line
	float primary_line = smoothstep(0.5 - line_thickness_primary, 0.5, line_position) * 
	                     smoothstep(0.5 + line_thickness_primary, 0.5, line_position);
	primary_line = pow(primary_line, 1.0 / line_sharpness);
	
	// Secondary (thick underlayer) line
	float secondary_line = smoothstep(0.5 - line_thickness_secondary, 0.5, line_position) * 
	                       smoothstep(0.5 + line_thickness_secondary, 0.5, line_position);
	secondary_line = pow(secondary_line, 1.0 / (line_sharpness * 0.8)); // Slightly softer
	
	// Combine lines - secondary is darker/more transparent base
	float combined_line = max(secondary_line * 0.4, primary_line);
	
	// Apply randomized radial mask for this line
	float radial_mask = smoothstep(line_length_min, line_length_min + 0.05, dist) * 
	                     smoothstep(this_line_max, this_line_max - 0.1, dist);
	
	// Add subtle animation - lines pulse outward with some randomness
	float pulse_offset = line_random * 3.14159; // Random phase offset per line
	float pulse = sin(TIME * animation_speed - dist * 3.0 + pulse_offset) * 0.5 + 0.5;
	radial_mask *= (0.8 + pulse * 0.2);
	
	// Add slight edge vignette for clean look
	float edge_fade = smoothstep(1.0, 0.85, dist);
	
	// Combine everything
	float alpha = combined_line * radial_mask * edge_fade * intensity;
	
	COLOR = vec4(line_color.rgb, alpha * line_color.a);
}
"""

func setup_shader_parameters():
	"""Setup shader parameters for motion lines"""
	shader_material.set_shader_parameter("intensity", 0.0)
	shader_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	shader_material.set_shader_parameter("line_color", line_color)
	shader_material.set_shader_parameter("line_count", actual_line_count)
	shader_material.set_shader_parameter("line_thickness_primary", line_thickness_primary)
	shader_material.set_shader_parameter("line_thickness_secondary", line_thickness_secondary)
	shader_material.set_shader_parameter("line_length_min", line_length_min)
	shader_material.set_shader_parameter("line_length_max", line_length_max)
	shader_material.set_shader_parameter("line_length_variation", line_individual_length_variation)
	shader_material.set_shader_parameter("line_sharpness", line_sharpness)
	shader_material.set_shader_parameter("animation_speed", 1.0)

func _process(delta: float):
	if not enabled or not shader_material or not player:
		return
	
	# Check if we're in rail grinding state
	var state_machine = player.get_node("StateMachine") if player.has_node("StateMachine") else null
	var is_rail_grinding = false
	if state_machine and state_machine.current_state:
		var current_state_name = state_machine.current_state.get_script().get_global_name()
		is_rail_grinding = (current_state_name == "RailGrindingState")
	
	# Calculate player's horizontal speed
	var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_velocity.length()
	
	# Calculate target intensity based on speed OR rail grinding
	var target_intensity = 0.0
	if is_rail_grinding:
		# ALWAYS show lines at full intensity when rail grinding
		target_intensity = 1.0
	elif speed > speed_threshold:
		target_intensity = clamp((speed - speed_threshold) / (max_speed - speed_threshold), 0.0, 1.0)
	
	# Smoothly interpolate current intensity
	if target_intensity > current_intensity:
		# Fade in quickly
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta * 2.0)
	else:
		# Fade out more slowly for smoother effect
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta)
	
	# Update shader intensity
	shader_material.set_shader_parameter("intensity", current_intensity)
	
	# Speed up animation as player goes faster (or use default speed for grinding)
	var animation_speed = 1.0
	if is_rail_grinding:
		animation_speed = 2.5  # Nice fast animation for grinding
	else:
		animation_speed = 1.0 + (speed / max_speed) * 2.0
	shader_material.set_shader_parameter("animation_speed", animation_speed)

# Public API for runtime adjustments
func set_enabled(is_enabled: bool):
	"""Enable or disable motion lines at runtime"""
	if is_enabled != enabled:
		enabled = is_enabled
		if enabled:
			setup_effect()
		else:
			cleanup_effect()

func set_speed_threshold(threshold: float):
	"""Change the speed threshold at runtime"""
	speed_threshold = threshold

func set_max_speed(max: float):
	"""Change the max speed at runtime"""
	max_speed = max

func rerandomize_lines():
	"""Re-randomize the number and appearance of lines"""
	randomize_line_count()
	if shader_material:
		shader_material.set_shader_parameter("line_count", actual_line_count)
		print("Speed lines re-randomized to: ", actual_line_count, " lines")

func set_line_color(color: Color):
	"""Change the line color at runtime"""
	line_color = color
	if shader_material:
		shader_material.set_shader_parameter("line_color", line_color)

func set_line_count_range(min_count: int, max_count: int):
	"""Change the range of possible line counts"""
	line_count_min = min_count
	line_count_max = max_count
	rerandomize_lines()
