extends Node
class_name SonicBoomManager

# Sonic boom configuration
@export var speed_threshold: float = 15.0
@export var max_speed: float = 50.0
@export var fade_speed: float = 3.0

# Internal state
var sonic_boom_material: ShaderMaterial
var color_rect: ColorRect
var current_intensity: float = 0.0

var player: CharacterBody3D
var camera_controller: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	camera_controller = player.get_node("CameraController") if player.has_node("CameraController") else null
	
	call_deferred("setup_sonic_boom")

func setup_sonic_boom():
	"""Create a fullscreen overlay with sonic boom/vortex effect"""
	await get_tree().process_frame
	
	if not is_inside_tree():
		call_deferred("setup_sonic_boom")
		return
	
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "SonicBoomCanvas"
	canvas_layer.layer = 100
	
	color_rect = ColorRect.new()
	color_rect.name = "SonicBoomRect"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	sonic_boom_material = ShaderMaterial.new()
	var shader = Shader.new()
	
	# Sonic boom vortex shader
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 ring_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ring_speed = 3.0;
uniform float twist_amount = 2.0;

void fragment() {
	vec2 uv = UV - center;
	
	// Calculate polar coordinates
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	
	// Create expanding rings
	float rings = fract(dist * 10.0 - TIME * ring_speed);
	
	// Add twist/spiral effect
	float twisted_angle = angle + dist * twist_amount + TIME;
	float spiral = sin(twisted_angle * 8.0) * 0.5 + 0.5;
	
	// Combine rings and spiral
	float pattern = rings * spiral;
	pattern = smoothstep(0.3, 0.7, pattern);
	
	// Create vortex gradient - stronger at edges, clear in center
	float vortex_gradient = smoothstep(0.1, 0.6, dist) * (1.0 - smoothstep(0.6, 1.0, dist));
	
	// Add chromatic aberration effect at high speeds
	float aberration = intensity * 0.3;
	vec2 aberration_offset = normalize(uv) * aberration * 0.02;
	
	// Create color variation
	vec4 color = mix(inner_color, ring_color, dist);
	
	// Combine all effects
	float alpha = pattern * vortex_gradient * intensity * 0.7;
	
	// Add some energy pulses
	float pulse = sin(TIME * 10.0 + dist * 15.0) * 0.5 + 0.5;
	alpha += pulse * intensity * 0.2 * vortex_gradient;
	
	COLOR = vec4(color.rgb, alpha * color.a);
}
"""
	
	sonic_boom_material.shader = shader
	
	sonic_boom_material.set_shader_parameter("intensity", 0.0)
	sonic_boom_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	sonic_boom_material.set_shader_parameter("ring_color", Color(0.5, 0.8, 1.0, 1.0))
	sonic_boom_material.set_shader_parameter("inner_color", Color(1.0, 1.0, 1.0, 1.0))
	sonic_boom_material.set_shader_parameter("ring_speed", 3.0)
	sonic_boom_material.set_shader_parameter("twist_amount", 2.0)
	
	color_rect.material = sonic_boom_material
	
	canvas_layer.add_child(color_rect)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(canvas_layer)
		print("Sonic boom overlay created!")

func _process(delta: float):
	if not sonic_boom_material or not player:
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
	
	sonic_boom_material.set_shader_parameter("intensity", current_intensity)
	
	# Speed up the rings as player goes faster
	var ring_speed = 3.0 + (speed / max_speed) * 5.0
	sonic_boom_material.set_shader_parameter("ring_speed", ring_speed)
	
	# Increase twist at higher speeds
	var twist = 2.0 + (speed / max_speed) * 3.0
	sonic_boom_material.set_shader_parameter("twist_amount", twist)

func set_colors(inner: Color, outer: Color):
	"""Customize the color scheme"""
	if sonic_boom_material:
		sonic_boom_material.set_shader_parameter("inner_color", inner)
		sonic_boom_material.set_shader_parameter("ring_color", outer)
