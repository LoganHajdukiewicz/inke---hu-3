extends Node
class_name SpeedEffectsManager

@export_category("Speed Settings")
@export var enabled: bool = true  # Enable/disable motion lines
@export var speed_threshold: float = 15.0  # Speed at which lines start appearing
@export var max_speed: float = 50.0  # Speed at which lines are at maximum intensity
@export var fade_speed: float = 3.0  # How quickly lines fade in/out

@export_category("Motion Lines Appearance")
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.85)  # White with transparency
@export var line_count_min: int = 26  # Minimum number of radial streaks
@export var line_count_max: int = 38  # Maximum number of radial streaks
@export var line_flicker_speed: float = 14.0  # How fast streaks redraw (hand-drawn feel)
@export var line_inner_radius: float = 0.42   # Streaks never intrude past this (keeps center clear)
@export var line_individual_length_variation: float = 0.5  # Per-streak length variation

@export_category("Vignette Blur")
@export var vignette_blur_strength: float = 2.2   # Mipmap LOD at max speed (higher = blurrier edges)
@export var vignette_start: float = 0.45          # Distance from center where blur begins
@export var vignette_darken: float = 0.25         # Slight edge darkening at max intensity

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

// ---------------------------------------------------------------------------
// Anime speed lines + vignette blur
//  - Streaks are TAPERED: thick at the screen edge, needle-thin toward the
//    center, like ink brush strokes in a manga panel.
//  - Each streak flickers/redraws a few times a second (stepped time) so the
//    effect looks hand-drawn on 2s/3s rather than a static overlay.
//  - The screen edges get a radial mipmap blur + slight darkening so the
//    center of the screen stays crisp while the periphery smears with speed.
// ---------------------------------------------------------------------------

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform int line_count = 32;
uniform float flicker_speed = 14.0;
uniform float inner_radius = 0.42;
uniform float length_variation = 0.5;
uniform float blur_strength = 2.2;
uniform float vignette_start = 0.45;
uniform float vignette_darken = 0.25;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	// Aspect-corrected radial coordinates so streaks are even all around
	vec2 uv = UV - center;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(uv);
	float angle = atan(uv.y, uv.x);
	float angle01 = (angle + 3.14159265359) / 6.28318530718;
	
	// -------- vignette blur: radial ZOOM blur (works on every renderer) -----
	// Samples march toward screen center, smearing the periphery outward -
	// exactly the tunnel-vision zoom smear anime uses for extreme speed.
	float vig = smoothstep(vignette_start, 0.95, dist) * intensity;
	vec2 to_center = center - UV;
	float smear = vig * blur_strength * 0.035;
	vec4 screen = vec4(0.0);
	const int SAMPLES = 9;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		screen += texture(screen_texture, SCREEN_UV + to_center * smear * t);
	}
	screen /= float(SAMPLES);
	// slight edge darkening sells the tunnel-vision feel
	screen.rgb *= 1.0 - vig * vignette_darken;
	
	// -------- anime streaks --------
	// Stepped time = hand-drawn flicker (streaks redraw, not slide)
	float frame = floor(TIME * flicker_speed);
	
	float streaks = 0.0;
	// Two overlapping layers with different seeds for a rich, sketchy look
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		float count = float(line_count) * (1.0 - fl * 0.35);
		float seed = frame * 13.7 + fl * 91.3;
		
		float cell = angle01 * count;
		float idx = floor(cell);
		float fpos = fract(cell);            // 0..1 across this streak's wedge
		float rnd = hash2(vec2(idx, seed));
		
		// Most wedges have a streak each 'frame' (dense, energetic)
		if (rnd > 0.25) {
			// Random inward reach per streak
			float reach = inner_radius + rnd * length_variation * 0.3;
			
			// TAPER: thick at edge (dist ~ 1) -> needle at its inner tip
			float taper = smoothstep(reach, 0.9, dist);
			float half_w = mix(0.002, 0.34, taper * taper);
			
			// Streak center jitters inside its wedge per frame
			float mid = 0.3 + 0.4 * hash2(vec2(idx, seed + 7.0));
			float d = abs(fpos - mid);
			float line_mask = smoothstep(half_w, half_w * 0.3, d);
			
			// Fade the needle tip out smoothly
			float tip_fade = smoothstep(reach - 0.03, reach + 0.15, dist);
			
			streaks = max(streaks, line_mask * tip_fade * (0.7 + 0.3 * rnd));
		}
	}
	
	// Streaks only exist toward the edges; center always stays readable
	float edge_zone = smoothstep(inner_radius, inner_radius + 0.25, dist);
	float streak_alpha = streaks * edge_zone * intensity * line_color.a;
	
	// Composite: blurred screen with ink streaks on top
	vec3 final_rgb = mix(screen.rgb, line_color.rgb, streak_alpha);
	
	// Only take over pixels where we actually change something
	float total_alpha = max(streak_alpha, min(vig * 2.0, 1.0));
	COLOR = vec4(final_rgb, total_alpha);
}
"""

func setup_shader_parameters():
	"""Setup shader parameters for motion lines"""
	shader_material.set_shader_parameter("intensity", 0.0)
	shader_material.set_shader_parameter("center", Vector2(0.5, 0.5))
	shader_material.set_shader_parameter("line_color", line_color)
	shader_material.set_shader_parameter("line_count", actual_line_count)
	shader_material.set_shader_parameter("flicker_speed", line_flicker_speed)
	shader_material.set_shader_parameter("inner_radius", line_inner_radius)
	shader_material.set_shader_parameter("length_variation", line_individual_length_variation)
	shader_material.set_shader_parameter("blur_strength", vignette_blur_strength)
	shader_material.set_shader_parameter("vignette_start", vignette_start)
	shader_material.set_shader_parameter("vignette_darken", vignette_darken)

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
	
	# Flicker faster as the player goes faster (or a fixed fast rate on rails)
	var flicker = line_flicker_speed
	if is_rail_grinding:
		flicker = line_flicker_speed * 1.5
	else:
		flicker = line_flicker_speed * (0.7 + (speed / max_speed) * 0.8)
	shader_material.set_shader_parameter("flicker_speed", flicker)

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

func set_max_speed(new_max_speed: float):
	"""Change the max speed at runtime"""
	max_speed = new_max_speed

func rerandomize_lines():
	"""Re-randomize the number and appearance of lines"""
	randomize_line_count()
	if shader_material:
		shader_material.set_shader_parameter("line_count", actual_line_count)

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
