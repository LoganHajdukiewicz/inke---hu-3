extends Node
class_name MotionLinesManager

# Motion lines configuration
@export var speed_threshold: float = 15.0  # Speed at which motion lines start appearing
@export var max_speed: float = 50.0  # Speed at which motion lines are at maximum intensity
@export var fade_speed: float = 3.0  # How quickly lines fade in/out

# Internal state
var motion_lines_material: ShaderMaterial
var color_rect: ColorRect
var current_intensity: float = 0.0

var player: CharacterBody3D
var camera_controller: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	camera_controller = player.get_node("CameraController") if player.has_node("CameraController") else null
	
	# Setup motion lines overlay
	call_deferred("setup_motion_lines")

func setup_motion_lines():
	"""Create a fullscreen overlay with motion lines shader"""
	await get_tree().process_frame
	
	if not is_inside_tree():
		call_deferred("setup_motion_lines")
		return
	
	# Create CanvasLayer to draw over everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MotionLinesCanvas"
	canvas_layer.layer = 100  # Draw on top
	
	# Create ColorRect for fullscreen shader
	color_rect = ColorRect.new()
	color_rect.name = "MotionLinesRect"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create shader material
	motion_lines_material = ShaderMaterial.new()
	var shader = Shader.new()
	
	# Motion lines shader code
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_density = 20.0;
uniform float line_speed = 2.0;
uniform float line_width = 0.02;

void fragment() {
	// Get UV coordinates centered around screen center
	vec2 uv = UV - center;
	
	// Calculate distance and angle from center
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	
	// Create radial lines pattern
	float lines = sin(angle * line_density + TIME * line_speed) * 0.5 + 0.5;
	
	// Make lines sharper
	lines = smoothstep(0.5 - line_width, 0.5 + line_width, lines);
	
	// Create radial gradient - lines appear more towards edges
	float radial_gradient = smoothstep(0.0, 0.8, dist);
	
	// Combine with distance-based falloff
	float alpha = lines * radial_gradient * intensity * 0.6;
	
	// Add some noise/variation
	float noise = fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453);
	alpha *= (0.8 + noise * 0.2);
	
	// Output color with alpha
	COLOR = vec4(line_color.rgb, alpha * line_color.a);
}
"""
	
	motion_lines_material.shader = shader
	
	# Set initial shader parameters
	motion_lines_material.set_shader_parameter("intensity", 0.0)
	motion_lines_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	motion_lines_material.set_shader_parameter("line_color", Color(0.8, 0.9, 1.0, 1.0))  # Light blue-white
	motion_lines_material.set_shader_parameter("line_density", 20.0)
	motion_lines_material.set_shader_parameter("line_speed", 2.0)
	motion_lines_material.set_shader_parameter("line_width", 0.02)
	
	color_rect.material = motion_lines_material
	
	# Add to scene
	canvas_layer.add_child(color_rect)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(canvas_layer)
		print("Motion lines overlay created!")
	else:
		print("Could not add motion lines - no current scene found")

func _process(delta: float):
	if not motion_lines_material or not player:
		return
	
	# Calculate player's horizontal speed
	var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_velocity.length()
	
	# Calculate target intensity based on speed
	var target_intensity = 0.0
	if speed > speed_threshold:
		target_intensity = clamp((speed - speed_threshold) / (max_speed - speed_threshold), 0.0, 1.0)
	
	# Smoothly interpolate current intensity
	if target_intensity > current_intensity:
		# Fade in quickly
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta * 2.0)
	else:
		# Fade out more slowly for smoother effect
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta)
	
	# Update shader intensity
	motion_lines_material.set_shader_parameter("intensity", current_intensity)
	
	# Update line speed based on player speed (faster = faster lines)
	var line_speed = 2.0 + (speed / max_speed) * 4.0
	motion_lines_material.set_shader_parameter("line_speed", line_speed)
	
	# Optional: Update center based on camera/movement direction
	# This would make lines flow from the direction of movement
	if camera_controller:
		# Keep centered for now, but could make dynamic
		motion_lines_material.set_shader_parameter("center", Vector2(0.5, 0.5))

func set_line_color(color: Color):
	"""Change the color of motion lines"""
	if motion_lines_material:
		motion_lines_material.set_shader_parameter("line_color", color)

func set_line_density(density: float):
	"""Change how many motion lines appear"""
	if motion_lines_material:
		motion_lines_material.set_shader_parameter("line_density", density)

func set_speed_threshold(threshold: float):
	"""Change the speed at which motion lines start appearing"""
	speed_threshold = threshold

func set_max_speed(max: float):
	"""Change the speed at which motion lines reach maximum intensity"""
	max_speed = max
