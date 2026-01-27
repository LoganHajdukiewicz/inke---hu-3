extends Node
class_name MotionBlurManager

# Motion blur configuration
@export var speed_threshold: float = 15.0
@export var max_speed: float = 50.0
@export var fade_speed: float = 3.0

# Internal state
var motion_blur_material: ShaderMaterial
var color_rect: ColorRect
var current_intensity: float = 0.0

var player: CharacterBody3D
var camera_controller: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	camera_controller = player.get_node("CameraController") if player.has_node("CameraController") else null
	
	call_deferred("setup_motion_blur")

func setup_motion_blur():
	"""Create a fullscreen overlay with directional motion blur shader"""
	await get_tree().process_frame
	
	if not is_inside_tree():
		call_deferred("setup_motion_blur")
		return
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "MotionBlurCanvas"
	canvas_layer.layer = 100
	
	color_rect = ColorRect.new()
	color_rect.name = "MotionBlurRect"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	motion_blur_material = ShaderMaterial.new()
	var shader = Shader.new()
	
	# Directional speed lines shader
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 direction = vec2(0.0, 0.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_length = 0.3;
uniform float line_count = 30.0;
uniform float edge_fade = 0.3;

void fragment() {
	vec2 uv = UV;
	
	// Calculate distance from edges
	vec2 edge_dist = min(uv, 1.0 - uv);
	float edge_factor = min(edge_dist.x, edge_dist.y) / edge_fade;
	edge_factor = clamp(edge_factor, 0.0, 1.0);
	
	// Create diagonal lines pattern based on direction
	float line_dir = direction.x + direction.y;
	float lines = fract((uv.x + uv.y + line_dir) * line_count + TIME * 5.0);
	
	// Make lines sharp
	lines = smoothstep(0.4, 0.6, lines);
	
	// Add some variation
	float variation = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
	lines *= (0.7 + variation * 0.3);
	
	// Combine with edge fade
	float alpha = lines * intensity * edge_factor * 0.5;
	
	COLOR = vec4(line_color.rgb, alpha * line_color.a);
}
"""
	
	motion_blur_material.shader = shader
	
	motion_blur_material.set_shader_parameter("intensity", 0.0)
	motion_blur_material.set_shader_parameter("direction", Vector2(0.0, 0.0))
	motion_blur_material.set_shader_parameter("line_color", Color(0.8, 0.9, 1.0, 1.0))
	motion_blur_material.set_shader_parameter("line_length", 0.3)
	motion_blur_material.set_shader_parameter("line_count", 30.0)
	motion_blur_material.set_shader_parameter("edge_fade", 0.3)
	
	color_rect.material = motion_blur_material
	
	canvas_layer.add_child(color_rect)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(canvas_layer)
		print("Motion blur overlay created!")

func _process(delta: float):
	if not motion_blur_material or not player:
		return
	
	var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
	var speed = horizontal_velocity.length()
	
	var target_intensity = 0.0
	if speed > speed_threshold:
		target_intensity = clamp((speed - speed_threshold) / (max_speed - speed_threshold), 0.0, 1.0)
	
	if target_intensity > current_intensity:
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta * 2.0)
	else:
		current_intensity = lerp(current_intensity, target_intensity, fade_speed * delta)
	
	motion_blur_material.set_shader_parameter("intensity", current_intensity)
	
	# Update direction based on velocity
	if speed > 0.5:
		var normalized_vel = horizontal_velocity.normalized()
		motion_blur_material.set_shader_parameter("direction", normalized_vel)
