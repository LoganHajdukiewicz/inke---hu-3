extends State
class_name RailGrindingState

# Rail grinding variables
var rail_grind_node = null
var countdown_for_next_grind: float = 1.0
var countdown_for_next_grind_time_left: float = 1.0
var grind_timer_complete: bool = true
var start_grind_timer: bool = false
var detached_from_rail: bool = false

# Configuration
var jump_velocity: float = 10.0 # Controls the upwards movement of jumping off a rail
var grind_exit_speed: float = 15.0 # Controls the horizontal movement of jumping off a rail
var lerp_speed: float = 50.0 # Does NOT control how fast you are going

## Max body tilt (radians) while grinding. Purely visual: steep rails used
## to pitch the model into the rail ("shishkabab"). ~35 degrees feels right.
@export var max_visual_pitch: float = 0.6

@export_category("Grind Sparks")
## Spark trail while grinding. Three looks - try them all:
##   CLASSIC: orange metal-grinding sparks kicked back and down (skate game)
##   EMBER FOUNTAIN: red-hot embers spraying UP and back, big and showy
##   ELECTRIC: cyan-blue crackle, tight and buzzy - fits HU3's tech vibe
@export_enum("Classic Sparks", "Ember Fountain", "Electric Crackle") var spark_style: int = 0
@export var sparks_enabled: bool = true
## Punk/anime grind flame pinned at the feet while grinding: a jagged
## trailing TRIANGLE of layered fire colors - front point at the feet on
## the rail, bottom edge flat along the rail (nothing below it), top point
## at the back. Boils by cycling through preset hand-drawn-style frames.
@export var feet_burst_enabled: bool = true
## Flame height in meters (top point of the triangle above the rail).
## Default 0.5 = about 1/3 of Inke.
@export var burst_height: float = 0.5
## How far the flame trails behind the feet along the rail, in meters.
@export var burst_length: float = 1.4
## Boil speed: preset flame frames shown per second (classic anime boil ~6).
@export var boil_fps: float = 6.0
## How many preset flame drawings to cycle through.
@export_range(2, 12, 1) var boil_frames: int = 6

var _sparks: GPUParticles3D = null
var _burst: MeshInstance3D = null
var _burst_timer: float = 0.0
var _burst_frames: Array[ArrayMesh] = []
var _burst_frame_i: int = 0

# Flame layers, drawn big-to-small: yellow rim -> orange -> red -> hot core
const BURST_COLORS: Array[Color] = [
	Color(1.0, 0.92, 0.15),   # yellow (outer)
	Color(1.0, 0.55, 0.05),   # orange
	Color(0.95, 0.12, 0.03),  # red
	Color(1.0, 0.97, 0.72),   # white-hot core
]
const BURST_SCALES: Array[float] = [1.0, 0.72, 0.48, 0.24]

func enter():
	
	# Restore double jump and air dash abilities when starting rail grinding
	player.can_double_jump = true
	player.has_double_jumped = false
	if sparks_enabled:
		_create_sparks()
	if feet_burst_enabled:
		_create_feet_burst()
	player.can_air_dash = true
	player.has_air_dashed = false

func physics_update(delta: float):
	_update_sparks()
	_update_feet_burst(delta)
	if Input.is_action_just_pressed("yoyo"):
		change_to("GrappleHookState")
		return
	# Handle the grinding movement and physics
	if rail_grind_node:
		# Smoothly move player to rail position
		player.position = lerp(player.position, rail_grind_node.global_position, delta * lerp_speed)
		
		# Rotate player to align with rail direction.
		# PITCH CLAMP: on steep rail sections the follower's basis pitches
		# hard, which used to rotate the player's body INTO the rail
		# ("shishkabab" glitch). We rebuild the target rotation from the rail
		# direction with the pitch limited, keeping the body mostly upright.
		var rail_forward: Vector3 = -rail_grind_node.global_transform.basis.z.normalized()
		if not rail_grind_node.forward:
			rail_forward = -rail_forward
		
		var flat := Vector3(rail_forward.x, 0, rail_forward.z)
		var target_rotation: Basis
		if flat.length() > 0.05:
			flat = flat.normalized()
			# Actual slope pitch of the rail, clamped to +/- max_visual_pitch
			var pitch := asin(clampf(rail_forward.y, -1.0, 1.0))
			pitch = clampf(pitch, -max_visual_pitch, max_visual_pitch)
			var yaw := atan2(-flat.x, -flat.z)
			target_rotation = Basis.from_euler(Vector3(pitch, yaw, 0.0))
		else:
			# Near-vertical rail segment: keep the body fully upright,
			# preserve current yaw
			target_rotation = Basis.from_euler(Vector3(0.0, player.rotation.y, 0.0))
		
		# Smoothly rotate the player to match the (clamped) rail direction
		player.transform.basis = player.transform.basis.slerp(target_rotation, delta * lerp_speed).orthonormalized()
		
		# Set velocity based on rail movement direction
		var rail_velocity = Vector3.ZERO
		if rail_grind_node.forward:
			rail_velocity = rail_grind_node.transform.basis.z * grind_exit_speed
		else:
			rail_velocity = -rail_grind_node.transform.basis.z * grind_exit_speed
		
		# CRITICAL FIX: Set the ACTUAL velocity so speed effects can detect it
		# The speed effects manager reads player.velocity to determine speed
		player.velocity = rail_velocity
		player.velocity.y = 0  # Keep it horizontal for grinding
		
		# Check for manual jump input for mid-grind jumping
		if Input.is_action_just_pressed("jump"):
			detach_from_rail()
			return
		
		# Check for automatic detachment at rail end
		if rail_grind_node.detach:
			detach_from_rail()
			return
	else:
		change_to("FallingState")
		return
	
	grind_timer(delta)

func grind_timer(delta: float):
	if start_grind_timer and countdown_for_next_grind_time_left > 0:
		countdown_for_next_grind_time_left -= delta
		if countdown_for_next_grind_time_left <= 0:
			countdown_for_next_grind_time_left = countdown_for_next_grind
			grind_timer_complete = true
			start_grind_timer = false

func setup_grinding(grind_ray):
	"""Legacy method for raycast compatibility - converts raycast to node"""
	var grind_rail = grind_ray.get_collider().get_parent()
	
	# Disable gravity while grinding
	player.gravity = 0.0
	
	# Find the nearest rail follower node
	rail_grind_node = find_nearest_rail_follower(player.global_position, grind_rail)
	
	if rail_grind_node:
		setup_rail_node(rail_grind_node)
		return true
	return false

func setup_grinding_with_node(rail_node):
	"""New method that directly accepts a rail follower node"""
	if not rail_node or not is_instance_valid(rail_node):
		return false
	
	# Disable gravity while grinding
	player.gravity = 0.0
	
	rail_grind_node = rail_node
	setup_rail_node(rail_grind_node)
	return true

func setup_rail_node(rail_node):
	"""Common setup for rail node"""
	if not rail_node:
		return
	
	# Set up the rail node
	rail_node.chosen = true
	rail_node.grinding = true
	
	# Determine grinding direction based on player facing
	if not rail_node.direction_selected:
		rail_node.forward = is_facing_same_direction(player, rail_node)
		rail_node.direction_selected = true

func find_nearest_rail_follower(player_position: Vector3, rail_node: Node):
	"""Find the nearest rail follower node from a rail parent"""
	var nearest_node = null
	var min_distance = INF
	
	for node in rail_node.get_children():
		if node.is_in_group("rail_follower"):
			var distance = player_position.distance_to(node.global_position)
			if distance < min_distance:
				min_distance = distance
				nearest_node = node
	
	return nearest_node

func is_facing_same_direction(player_node: CharacterBody3D, path_follow: PathFollow3D) -> bool:
	var player_forward = -player_node.global_transform.basis.z.normalized()
	var path_follow_forward = -path_follow.global_transform.basis.z.normalized()
	var dot_product = player_forward.dot(path_follow_forward)
	const THRESHOLD = 0.5
	return dot_product > THRESHOLD

func disable_rail_detection():
	"""Disable rail detection area temporarily"""
	if player.rail_grind_area:
		player.rail_grind_area.monitoring = false
		player.rail_grind_area.monitorable = false
		
		# Re-enable after a short delay using a timer
		var timer = Timer.new()
		timer.wait_time = 0.3
		timer.one_shot = true
		timer.timeout.connect(enable_rail_detection)
		player.add_child(timer)
		timer.start()

func enable_rail_detection():
	"""Re-enable rail detection area"""
	if player.rail_grind_area:
		player.rail_grind_area.monitoring = true
		player.rail_grind_area.monitorable = true

func exit():
	_kill_sparks()
	_kill_feet_burst()
	# Straighten the body: only yaw survives leaving the rail, so no leftover
	# pitch/roll from the grind pose leaks into other states
	if player:
		var exit_yaw = player.rotation.y
		player.rotation = Vector3(0.0, exit_yaw, 0.0)
	
	if rail_grind_node:
		rail_grind_node.chosen = false
		rail_grind_node.detach = false
		rail_grind_node.direction_selected = false
		rail_grind_node.grinding = false
	
	player.gravity = player.gravity_default
	
	grind_timer_complete = true
	start_grind_timer = false
	
	disable_rail_detection()

func _create_sparks():
	_kill_sparks()
	_sparks = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	var mesh := QuadMesh.new()
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.vertex_color_use_as_albedo = true
	mat.direction = Vector3(0, 0.3, 1)   # Backwards relative to travel (set each frame)
	mat.spread = 25.0
	mat.gravity = Vector3(0, -14, 0)
	
	match spark_style:
		0:   # CLASSIC: orange grinding sparks, kicked back low and fast
			_sparks.amount = 40
			_sparks.lifetime = 0.35
			mesh.size = Vector2(0.07, 0.07)
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 9.0
			mat.spread = 20.0
			mat.gravity = Vector3(0, -18, 0)
			mat.scale_min = 0.5
			mat.scale_max = 1.1
			var g0 := Gradient.new()
			# Fire ramp: yellow -> orange -> red
			g0.colors = PackedColorArray([Color(1.0, 0.95, 0.2, 1.0), Color(1.0, 0.5, 0.05, 0.95), Color(0.9, 0.1, 0.02, 0.0)])
			var gt0 := GradientTexture1D.new(); gt0.gradient = g0
			mat.color_ramp = gt0
		1:   # EMBER FOUNTAIN: big glowing embers spraying up and back
			_sparks.amount = 56
			_sparks.lifetime = 0.8
			mesh.size = Vector2(0.12, 0.12)
			mat.direction = Vector3(0, 1.0, 0.7)
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 7.0
			mat.spread = 40.0
			mat.gravity = Vector3(0, -9, 0)
			mat.scale_min = 0.6
			mat.scale_max = 1.6
			mat.angular_velocity_min = -180.0
			mat.angular_velocity_max = 180.0
			var g1 := Gradient.new()
			# Fire ramp: yellow -> orange -> red
			g1.colors = PackedColorArray([Color(1.0, 0.9, 0.15, 1.0), Color(1.0, 0.45, 0.05, 0.85), Color(0.8, 0.08, 0.02, 0.0)])
			var gt1 := GradientTexture1D.new(); gt1.gradient = g1
			mat.color_ramp = gt1
		2:   # ELECTRIC CRACKLE: tight cyan buzz around the contact point
			_sparks.amount = 64
			_sparks.lifetime = 0.22
			mesh.size = Vector2(0.05, 0.16)   # Stretched = little arcs
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 5.0
			mat.spread = 70.0
			mat.gravity = Vector3.ZERO
			mat.scale_min = 0.4
			mat.scale_max = 1.0
			var g2 := Gradient.new()
			g2.colors = PackedColorArray([Color(0.8, 1.0, 1.0, 1.0), Color(0.2, 0.7, 1.0, 0.9), Color(0.1, 0.2, 0.8, 0.0)])
			var gt2 := GradientTexture1D.new(); gt2.gradient = g2
			mat.color_ramp = gt2
	
	_sparks.process_material = mat
	_sparks.draw_pass_1 = mesh
	_sparks.local_coords = false
	_sparks.emitting = true
	player.get_tree().current_scene.add_child(_sparks)


func _update_sparks():
	if not _sparks or not is_instance_valid(_sparks):
		return
	# Sit at the TAIL of the feet flame so the particles read as bits
	# falling off the back of it (at the feet they were hidden inside/behind
	# the flame quad and invisible)
	var flat_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	var back := Vector3.ZERO
	if flat_vel.length() > 0.5:
		back = -flat_vel.normalized()
	_sparks.global_position = player.global_position \
			+ back * (burst_length * 0.85) + Vector3(0, 0.18, 0)
	if back != Vector3.ZERO:
		var pm: ParticleProcessMaterial = _sparks.process_material
		if spark_style == 1:
			pm.direction = (back * 0.7 + Vector3.UP).normalized()
		else:
			pm.direction = (back + Vector3(0, 0.25, 0)).normalized()


# === GRIND FLAME (punk/anime boil) ==========================================
# A flat, jagged TRIANGLE of fire trailing the feet along the rail:
#   - front point pinned at the feet, ON the rail
#   - bottom edge dead flat along the rail (nothing ever below the rail)
#   - jagged top edge climbing to the top point at the back
# Layered hard colors (yellow rim -> orange -> red -> white-hot core), all
# sharing the front point, like a graffiti flame sticker. Animates as a
# choppy BOIL: boil_frames preset drawings cycled at boil_fps - no smooth
# interpolation, hand-drawn anime fire style on purpose.

func _create_feet_burst():
	_kill_feet_burst()
	_burst = MeshInstance3D.new()
	_burst.name = "GrindFeetBurst"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # Visible from both sides
	_burst.material_override = m
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pre-roll the boil cycle: a fixed set of flame drawings, played in order
	_burst_frames.clear()
	for i in maxi(boil_frames, 2):
		_burst_frames.append(_gen_flame_frame())
	_burst_frame_i = 0
	_burst.mesh = _burst_frames[0]
	_burst_timer = 0.0
	player.get_tree().current_scene.add_child(_burst)

func _gen_flame_frame() -> ArrayMesh:
	"""One preset flame drawing. Local space: +X = backward along the rail,
	+Y = up. Front point at the origin (the feet), bottom edge on y=0 (the
	rail), jagged top edge rising to the top point at the back. Filled in 4
	hard-color layers that all share the front point."""
	var segs := 7
	# Jagged height profile: 0 at the feet, climbing to full height at the
	# back, with zigzag jitter for the punk spikes
	var profile := PackedFloat32Array()
	profile.resize(segs + 1)
	profile[0] = 0.0
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var spike := 1.0 + (0.42 if (i % 2 == 1) else -0.18) * randf_range(0.6, 1.4)
		profile[i] = t * spike
	profile[segs] = 1.0   # The back top point is THE point of the triangle
	
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for li in BURST_SCALES.size():
		var s: float = BURST_SCALES[li]
		var c: Color = BURST_COLORS[li]
		var z := 0.012 * li   # Tiny offsets: core draws on top, no z-fighting
		for i in range(segs):
			var x0 := float(i) / segs * s
			var x1 := float(i + 1) / segs * s
			var h0 := profile[i] * s
			var h1 := profile[i + 1] * s
			# Column quad from the rail (y=0) up to the jagged profile.
			# Both triangles, both windings covered by CULL_DISABLED.
			verts.append(Vector3(x0, 0, z)); cols.append(c)
			verts.append(Vector3(x1, 0, z)); cols.append(c)
			verts.append(Vector3(x1, h1, z)); cols.append(c)
			if h0 > 0.001:
				verts.append(Vector3(x0, 0, z)); cols.append(c)
				verts.append(Vector3(x1, h1, z)); cols.append(c)
				verts.append(Vector3(x0, h0, z)); cols.append(c)
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _update_feet_burst(delta: float):
	if not _burst or not is_instance_valid(_burst):
		return
	# Pin the front point to the rail contact (feet) and lay the triangle
	# backward along the travel direction, upright. Never below the rail.
	_burst.global_position = player.global_position + Vector3(0, 0.04, 0)
	var flat_vel := Vector3(player.velocity.x, 0, player.velocity.z)
	if flat_vel.length() > 0.5:
		var back := -flat_vel.normalized()
		var side := back.cross(Vector3.UP).normalized()
		_burst.global_transform.basis = Basis(back, Vector3.UP, side)
	# Boil: hard-cut to the next preset drawing at boil_fps
	_burst_timer -= delta
	if _burst_timer <= 0.0 and boil_fps > 0.0 and not _burst_frames.is_empty():
		_burst_timer = 1.0 / boil_fps
		_burst_frame_i = (_burst_frame_i + 1) % _burst_frames.size()
		_burst.mesh = _burst_frames[_burst_frame_i]
	# Size: length back along the rail, height up from it (configurable)
	_burst.scale = Vector3(burst_length, burst_height, 1.0)

func _kill_feet_burst():
	if _burst and is_instance_valid(_burst):
		_burst.queue_free()
	_burst = null

func _kill_sparks():
	if _sparks and is_instance_valid(_sparks):
		# Let live particles finish, then free
		_sparks.emitting = false
		var s = _sparks
		player.get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(s):
				s.queue_free()
		)
		_sparks = null


func detach_from_rail():
	player.velocity.y = jump_velocity
	
	if rail_grind_node:
		var rail_direction = Vector3.ZERO
		if rail_grind_node.forward:
			rail_direction = -rail_grind_node.transform.basis.z
		else:
			rail_direction = rail_grind_node.transform.basis.z
		
		var momentum_velocity = rail_direction * grind_exit_speed
		player.velocity.x = momentum_velocity.x
		player.velocity.z = momentum_velocity.z
	
	start_grind_timer = true
	countdown_for_next_grind_time_left = countdown_for_next_grind
	grind_timer_complete = false
	
	# Always transition to JumpingState when detaching from rail
	change_to("JumpingState")

func get_speed():
	return grind_exit_speed
