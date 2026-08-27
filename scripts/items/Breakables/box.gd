extends CharacterBody3D
class_name Box

## NOTE: Boxes used to be RigidBody3D, but stacked boxes refused to fall
## when their support broke (sleeping bodies never re-check support).
## Now they're CharacterBody3D with explicit gravity every frame - dumb,
## predictable, and it always works.

# Crate properties
@export_group("Crate Health")
@export var max_health: int = 2  # How many hits to break
@export var current_health: int = 2

@export_group("Loot Drops")
@export var drops_gears: bool = true
@export var gear_count_min: int = 50
@export var gear_count_max: int = 50

@export_group("Bounce Settings")
@export var bounce_enabled: bool = true        # Whether boxes bounce the player
@export var bounce_force: float = 8.0         # Upward bounce velocity
@export var break_on_bounce: bool = true       # Break immediately after bounce
@export var bounce_damage: int = 2             # Damage dealt when bounced on

@export_group("Explosion Settings")
@export var spawn_spread: float = 2.5           # How far apart gears spawn
@export var gears_per_frame: int = 6            # Spawn batch size (prevents frame hitches)
@export var scatter_duration: float = 0.35      # How long the scatter animation takes

# References to child nodes
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var damage_area: Area3D = $DamageDetection
@onready var particles: GPUParticles3D = $BreakParticles if has_node("BreakParticles") else null
@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

# Preloaded scenes
var gear_scene = preload("res://scenes/items/Collectibles/six_teeth_gear.tscn")

# State
var is_broken: bool = false
var game_manager
var just_bounced: bool = false  # Prevent multiple bounces in rapid succession

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Support check: a real box falls off an edge when its center of mass is
# past the support - i.e. when more than 50% of it hangs over. We sample
# rays under the base each frame while grounded and shove the box toward
# the unsupported side when the balance tips.
var slide_off_speed: float = 2.0        # How fast an overhanging box slides off
var support_probe_depth: float = 0.35   # How far below the base counts as "supported"
var _base_half_extents: Vector2 = Vector2(0.5, 0.5)
var _last_tip_dir: Vector3 = Vector3.ZERO  # Keeps the slide going on the final sliver

func _ready():
	current_health = max_health
	game_manager = get_node("/root/GameManager")
	
	# Add to Breakables group
	if not is_in_group("Breakables"):
		add_to_group("Breakables")
	
	# Connect damage detection area
	if damage_area:
		damage_area.body_entered.connect(_on_damage_body_entered)
		damage_area.area_entered.connect(_on_damage_area_entered)
	
	# Setup bounce detection if enabled
	if bounce_enabled:
		setup_bounce_detection()
	
	# Setup material for hit feedback
	if mesh and mesh.get_active_material(0):
		var material = mesh.get_active_material(0).duplicate()
		mesh.set_surface_override_material(0, material)

func _physics_process(delta: float):
	"""Explicit gravity: if nothing is under the box, it falls. Every frame,
	no sleeping, no exceptions. Boxes settle on floors and on each other.
	
	REALISTIC SUPPORT: is_on_floor() is true even when one pixel touches.
	So while grounded we check how much of the base is actually supported -
	if the center of mass is past the support (more than half hanging over
	an edge), the box slides off toward the overhang and falls, like a real
	object would."""
	if is_broken:
		return
	if is_on_floor():
		var tip_dir = _get_tip_direction()
		if tip_dir != Vector3.ZERO:
			# Over-balanced: slide off toward the unsupported side
			velocity.x = tip_dir.x * slide_off_speed
			velocity.z = tip_dir.z * slide_off_speed
			velocity.y = -1.0
		else:
			velocity = Vector3.ZERO
	else:
		velocity.y -= gravity * delta
		# Light horizontal damping so nudged boxes don't glide forever
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	move_and_slide()

func _get_tip_direction() -> Vector3:
	"""Sample 5 points under the base (center + 4 corners). Returns the
	horizontal direction to fall in if the box is over-balanced, or ZERO if
	it's stably supported.
	
	Physics rule of thumb: a uniform box on an edge tips exactly when its
	CENTER is past the support. So: center supported = stable, no matter
	how little of the rim hangs on. Center unsupported = more than 50% is
	overhanging -> fall toward the unsupported side."""
	_refresh_base_extents()
	var space_state = get_world_3d().direct_space_state
	var base_y = global_position.y  # Origin is at the collider center; rays start low
	
	var hx = _base_half_extents.x * 0.8
	var hz = _base_half_extents.y * 0.8
	var offsets := [
		Vector3.ZERO,
		Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
		Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz),
	]
	
	var supported: Array[Vector3] = []
	var unsupported: Array[Vector3] = []
	for off in offsets:
		var from = Vector3(global_position.x + off.x, base_y, global_position.z + off.z)
		var to = from + Vector3(0, -(_collider_half_height() + support_probe_depth), 0)
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [self]
		if space_state.intersect_ray(query):
			supported.append(off)
		else:
			unsupported.append(off)
	
	# Fully supported: stable, clear any tip memory
	if unsupported.is_empty():
		_last_tip_dir = Vector3.ZERO
		return Vector3.ZERO
	
	# All probe rays miss but is_on_floor() is still true: we're balanced on
	# a sliver thinner than the probe ring. If we were already tipping, keep
	# sliding the same way until we're truly airborne (otherwise the box
	# stalls, held up by one pixel - exactly the bug we're fixing).
	if supported.is_empty():
		return _last_tip_dir
	
	# Center supported = center of mass is over the ledge = stable
	if Vector3.ZERO in supported:
		_last_tip_dir = Vector3.ZERO
		return Vector3.ZERO
	
	# Center hanging over: fall away from whatever support remains
	var support_centroid := Vector3.ZERO
	for s in supported:
		support_centroid += s
	support_centroid /= supported.size()
	if support_centroid.length() < 0.01:
		return Vector3.ZERO  # Support is symmetric (e.g. straddling a gap): balanced
	_last_tip_dir = -support_centroid.normalized()
	return _last_tip_dir

func _refresh_base_extents():
	if collision and collision.shape is BoxShape3D:
		var s = (collision.shape as BoxShape3D).size * collision.scale
		_base_half_extents = Vector2(s.x * 0.5, s.z * 0.5)
	elif collision and collision.shape is CylinderShape3D:
		var r = (collision.shape as CylinderShape3D).radius
		_base_half_extents = Vector2(r * 0.7, r * 0.7)  # Inscribed square-ish

func _collider_half_height() -> float:
	if collision and collision.shape is BoxShape3D:
		return (collision.shape as BoxShape3D).size.y * 0.5 + collision.position.y
	elif collision and collision.shape is CylinderShape3D:
		return (collision.shape as CylinderShape3D).height * 0.5 + collision.position.y
	return 0.5

func setup_bounce_detection():
	"""
	Setup bounce detection using an Area3D.
	
	WHY WE USE AREA3D:
	RigidBody3D.body_entered doesn't reliably detect CharacterBody3D collisions.
	Area3D.body_entered works perfectly for detecting when CharacterBody3D enters.
	"""
	# Create Area3D for bounce detection
	var bounce_area = Area3D.new()
	bounce_area.name = "BounceDetectionArea"
	
	# Set collision - detect player only
	bounce_area.collision_layer = 0  # Don't exist on any layer
	bounce_area.collision_mask = 1   # Detect layer 1 (where player is)
	bounce_area.monitoring = true
	bounce_area.monitorable = false
	
	add_child(bounce_area)
	
	# Create collision shape - a box on top of the crate
	var bounce_collision = CollisionShape3D.new()
	var bounce_shape = BoxShape3D.new()
	
	# Get the main collision box size
	if collision and collision.shape is BoxShape3D:
		var box_shape = collision.shape as BoxShape3D
		# Make detection area slightly larger and positioned on top
		bounce_shape.size = Vector3(
			box_shape.size.x * 1.2,  # Wider for easier stomping
			0.4,  # Thin detection zone on top
			box_shape.size.z * 1.2
		)
		# Position on top of the box
		bounce_collision.position = Vector3(0, box_shape.size.y * 0.5 + 0.2, 0)
	else:
		# Default size
		bounce_shape.size = Vector3(1.2, 0.4, 1.2)
		bounce_collision.position = Vector3(0, 0.7, 0)
	
	bounce_collision.shape = bounce_shape
	bounce_area.add_child(bounce_collision)
	
	# Connect to body_entered signal
	bounce_area.body_entered.connect(_on_bounce_area_body_entered)
	

func _on_bounce_area_body_entered(body: Node3D):
	"""
	Called when something enters the bounce detection Area3D.
	This is much more reliable than RigidBody collision detection!
	"""
	
	if is_broken or just_bounced:
		return
	
	# Check if it's the player
	if not body.is_in_group("Player"):
		return
	
	var player = body as CharacterBody3D
	if not player:
		return
	
	
	# CRITICAL: Only bounce if player is falling downward
	# This prevents bouncing when the player hits the side of the box
	if player.velocity.y >= -1.0:
		return
	
	
	# Apply bounce to player
	apply_bounce_to_player(player)
	
	# Box reaction - DEFERRED to avoid physics errors
	if break_on_bounce:
		call_deferred("take_damage", bounce_damage)
	else:
		call_deferred("squash_and_stretch")

func apply_bounce_to_player(player: CharacterBody3D):
	"""
	Apply upward bounce velocity to the player.
	This creates that classic platformer stomp feel!
	"""
	# Set upward velocity for bounce
	player.velocity.y = bounce_force
	
	# Preserve horizontal momentum with slight reduction
	player.velocity.x *= 0.9
	player.velocity.z *= 0.9
	
	
	# Visual feedback
	call_deferred("squash_and_stretch")
	
	# Prevent multiple bounces in quick succession
	just_bounced = true
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		just_bounced = false
	
	# Give player brief invulnerability
	if player.has_method("set_invulnerable_without_flash"):
		player.set_invulnerable_without_flash(0.5)

func squash_and_stretch():
	"""
	Squash and stretch animation - classic animation principle!
	Makes the bounce feel more dynamic and satisfying.
	"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	var original_scale = mesh.scale
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)
	
	# Squash down
	tween.tween_property(mesh, "scale", Vector3(1.2, 0.6, 1.2), 0.1)
	# Spring back
	tween.tween_property(mesh, "scale", original_scale, 0.3)

func _on_damage_body_entered(body: Node3D):
	"""Detect when player or projectile hits the crate"""
	if body.is_in_group("Player"):
		var player = body as CharacterBody3D
		if player.has_node("AttackManager"):
			var attack_manager = player.get_node("AttackManager")
			if attack_manager.has_method("get_is_attacking") and attack_manager.get_is_attacking():
				take_damage(1)
	
	if body.is_in_group("Projectile") or body.is_in_group("Damaging"):
		var damage = 1
		if body.has_method("get_damage"):
			damage = body.get_damage()
		take_damage(damage)
		
		if body.has_method("queue_free"):
			body.queue_free()

func _on_damage_area_entered(area: Area3D):
	"""Detect area-based damage"""
	if area.is_in_group("Explosion") or area.is_in_group("Damaging"):
		var damage = 1
		if area.has_method("get_damage"):
			damage = area.get_damage()
		take_damage(damage)

func take_damage(amount: int):
	"""Apply damage to the crate"""
	
	if is_broken:
		return
	
	current_health -= amount
	
	# Visual feedback
	flash_white()
	shake_crate()
	
	if current_health <= 0:
		break_crate()
	else:
		pass

func flash_white():
	"""Flash the crate white briefly"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		var original_color = material.albedo_color
		
		var tween = create_tween()
		tween.tween_property(material, "albedo_color", Color.WHITE, 0.05)
		tween.tween_property(material, "albedo_color", original_color, 0.1)

func shake_crate():
	"""Small shake animation"""
	if not is_instance_valid(self):
		return
		
	var original_pos = position
	var shake_amount = 0.1
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	
	tween.tween_property(self, "position", original_pos + Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos - Vector3(shake_amount, 0, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)

func break_crate():
	"""Destroy the crate and spawn loot"""
	
	if is_broken:
		return
	
	is_broken = true
	
	# Spawn particles
	if particles:
		particles.emitting = true
	else:
		pass
	
	# Spawn loot
	spawn_loot()
	
	# Visual destruction
	play_break_animation()
	
	# Clean up
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		queue_free()
	else:
		pass

func play_break_animation():
	"""
	Animated destruction of the crate.
	Uses set_deferred to avoid physics errors.
	"""
	if not mesh or not is_instance_valid(mesh):
		return
	
	# Disable collisions using deferred calls
	if collision:
		collision.set_deferred("disabled", true)
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	
	# Break animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Spin and shrink
	tween.tween_property(self, "rotation", rotation + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), 0.3)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	
	# Fade out
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(material, "albedo_color:a", 0.0, 0.3)

func spawn_loot():
	"""Spawn gears with a scatter effect, staggered across frames.
	
	PERFORMANCE: spawning all gears in a single frame (instantiate + add_child
	+ per-gear ground raycast) caused a visible hitch with large gear counts.
	We now spawn gears_per_frame per frame instead. The scatter is animated
	with a cheap tween (gears are Area3D, so physics impulses never applied)."""
	if not is_instance_valid(self):
		return
	
	if drops_gears and gear_scene:
		var gear_count = randi_range(gear_count_min, gear_count_max)
		# Parent gears to our parent so they survive the box being freed;
		# capture references now because the box may be freed mid-coroutine.
		var container = get_parent()
		var spawn_position = global_position + Vector3(0, 0.5, 0)
		_spawn_gears_staggered(container, spawn_position, gear_count)

func _spawn_gears_staggered(container: Node, spawn_position: Vector3, gear_count: int) -> void:
	"""Coroutine: spawn gears in small batches to avoid frame hitches.
	Runs on the container's tree so it keeps going after the box is freed."""
	var tree = container.get_tree()
	var spawned := 0
	
	while spawned < gear_count:
		if not is_instance_valid(container):
			return
		
		var batch = mini(gears_per_frame, gear_count - spawned)
		for i in range(batch):
			var gear = gear_scene.instantiate()
			container.add_child(gear)
			
			# Final scatter position in a ring around the box
			var angle = randf() * TAU
			var radius = randf_range(spawn_spread * 0.3, spawn_spread)
			var target = spawn_position + Vector3(cos(angle) * radius, randf_range(0.3, 1.0), sin(angle) * radius)
			
			# Start at the box and animate outward for the "explosion" feel
			gear.global_position = spawn_position
			if gear.has_method("scatter_to"):
				gear.scatter_to(target, scatter_duration)
			else:
				gear.global_position = target
		
		spawned += batch
		await tree.process_frame
