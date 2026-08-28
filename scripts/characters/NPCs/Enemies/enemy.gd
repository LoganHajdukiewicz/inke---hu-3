extends CharacterBody3D
class_name Enemy

## Optional quest hook: DEFEAT_ENEMY quests track kills by this id.
## Leave empty for regular enemies.
@export var enemy_id: String = ""

# Health system
@export var max_health: int = 3
@export var current_health: int = 3

@export_group("Boss")
## Tick this to make ANY enemy (or subclass) a boss: it gets a big named
## health bar pinned to the bottom of the screen. All look & feel knobs
## below are Inspector-tweakable per boss.
@export var is_boss: bool = false
@export var boss_name: String = "BOSS"
## Fill color of the health bar.
@export var boss_bar_color: Color = Color(0.85, 0.15, 0.15)
## Background color behind the fill.
@export var boss_bar_bg_color: Color = Color(0.12, 0.1, 0.1, 0.85)
## Color of the name text above the bar.
@export var boss_name_color: Color = Color(1, 1, 1)
@export var boss_name_font_size: int = 30
## Bar width in pixels (height scales with it).
@export var boss_bar_width: float = 620.0
@export var boss_bar_height: float = 26.0
## Only show the bar once the player gets within this range (0 = always).
@export var boss_bar_show_range: float = 30.0
## Delayed white "damage ghost" behind the fill, like classic boss bars.
@export var boss_bar_damage_ghost: bool = true

var _boss_bar: BossHealthBar = null

# Behavior parameters
@export var detection_range: float = 15.0
@export var chase_speed: float = 8.0
@export var wander_speed: float = 3.0
@export var damage_to_player: int = 1
@export var bounce_feedback: int = 9
@export var max_roam_distance: float = 10.0  # Maximum distance from spawn point

@export_group("Sound")
## Played when the player bounces off this enemy's head. Leave EMPTY for
## the beefy built-in thud - drop any AudioStream here to replace it.
@export var stomp_sound: AudioStream = null
@export var stomp_volume_db: float = 1.0

@export_group("Attack")
@export var attack_range: float = 2.8           # Start a lunge from this close
@export var attack_windup: float = 0.35         # Telegraph time before the lunge
@export var lunge_speed: float = 16.0           # Speed of the lunge itself
@export var lunge_duration: float = 0.35        # How long the lunge lasts
@export var attack_recovery: float = 0.6        # Vulnerable pause after a lunge
@export var attack_cooldown: float = 1.0        # Min time between lunges

@export_group("Smart AI")
@export var stomp_evade_enabled: bool = true    # Sidestep when the player is dropping on us
@export var stomp_danger_height: float = 1.2    # Player this far above = stomp threat
@export var stomp_danger_radius: float = 2.2    # ...within this horizontal distance
@export var evade_speed: float = 10.0           # Sidestep speed when evading
@export var separation_radius: float = 1.4      # Personal space between ENEMIES (not the player)
@export var separation_strength: float = 3.0    # How hard enemies push apart from each other
var can_chase := true
var being_stomped := false
var spawn_position: Vector3 = Vector3.ZERO  # Track where enemy spawned
var attack_cooldown_timer: float = 0.0      # Ticks down between lunges

# Loot system
@export_group("Death Loot (Gears)")
@export var drops_gears_on_death: bool = true
@export var gear_count_min: int = 3
@export var gear_count_max: int = 8
@export var gear_scatter_radius: float = 2.0
@export var gear_scatter_duration: float = 0.35

@export_group("Hit Loot (Paint Droplets)")
@export var drops_paint_on_hit: bool = true
@export var paint_droplet_count_min: int = 5
@export var paint_droplet_count_max: int = 10
@export var paint_scatter_radius: float = 1.2
@export var paint_scatter_duration: float = 0.3
@export var paint_droplet_value_min: int = 10  # NEW: Min paint value per droplet
@export var paint_droplet_value_max: int = 25  # NEW: Max paint value per droplet

# Preloaded scenes
var gear_scene = preload("res://scenes/items/Collectibles/six_teeth_gear.tscn")
var paint_droplet_scene = preload("res://scenes/items/Collectibles/paint_droplet.tscn")

# Physics
var gravity: float = 9.8

# Damage cooldown
var damage_cooldown: float = 0.0
var damage_cooldown_time: float = 0.5

# State machine
var state_machine: EnemyStateMachine
var player: CharacterBody3D = null

# Animation/Visual
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var hit_box: Area3D = $HitBox
var initial_color: Color

func _ready():
	add_to_group("Enemy")
	
	# Store spawn position for roaming constraint
	spawn_position = global_position
	
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
	
	if mesh and mesh.material_override:
		initial_color = mesh.material_override.albedo_color
	
	if hit_box:
		hit_box.add_to_group("Enemy")
		
		# Connect body_entered signal
		if not hit_box.body_entered.is_connected(_on_hit_box_body_entered):
			hit_box.body_entered.connect(_on_hit_box_body_entered)
	else:
		print("ERROR: HitBox not found on enemy!")
	
	state_machine = EnemyStateMachine.new()
	state_machine.enemy = self
	add_child(state_machine)
	state_machine.initialize_states()
	
	if is_boss:
		_boss_bar = BossHealthBar.new()
		_boss_bar.setup(self)
		add_child(_boss_bar)

func _is_player_stomp_threat() -> bool:
	"""True ONLY when the player is directly above us AND falling - i.e. a
	stomp is genuinely incoming. Deliberately tight so enemies still press
	their attack when the player is merely jumping around nearby."""
	if not player or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var diff = player.global_position - global_position
	var height = diff.y
	var horizontal = Vector2(diff.x, diff.z).length()
	var player_airborne = not player.is_on_floor()
	var player_falling = player.velocity.y < -0.5 if "velocity" in player else false
	return player_airborne and player_falling and height > stomp_danger_height and horizontal < stomp_danger_radius

func _separation_push() -> Vector3:
	"""Push-apart vector from other nearby enemies so groups spread out
	instead of stacking into a single blob. Never pushes away from the player."""
	var push = Vector3.ZERO
	for other in get_tree().get_nodes_in_group("Enemy"):
		if other == self or not (other is CharacterBody3D) or not is_instance_valid(other):
			continue
		var away = global_position - other.global_position
		away.y = 0
		var d = away.length()
		if d < separation_radius and d > 0.01:
			push += away.normalized() * (1.0 - d / separation_radius)
	return push * separation_strength

func get_attack_state_name() -> String:
	"""Which state to enter when in attack range. Subclasses (e.g. laser
	enemies) override this to use their own attack."""
	return "aiattackstate"

func get_preferred_attack_range() -> float:
	"""Distance at which this enemy wants to start its attack."""
	return attack_range

func _register_extra_states(_states: Dictionary) -> void:
	"""Hook for subclasses to add their own AI states (e.g. laser attack)."""
	pass

func damage_player(player_body: Node3D):
	"""Apply damage and knockback to the player"""
	if not player_body.has_method("take_damage"):
		return
	
	var knockback_direction = (player_body.global_position - global_position).normalized()
	knockback_direction.y = 0
	
	player_body.take_damage(damage_to_player, knockback_direction)

func _on_hit_box_body_entered(body: Node) -> void:
	"""This detects when the PLAYER'S BODY enters the enemy's hitbox"""
	if not body.is_in_group("Player"):
		return
	
	# CRITICAL: Check if being stomped - if so, don't damage player OR trigger invulnerability
	if being_stomped:
		return
	
	if not can_chase:
		return
	
	# Check if player is above enemy and falling (head stomp scenario)
	var player_y = body.global_position.y
	var enemy_head_y = global_position.y + 0.8  # Approximate head height
	var is_above_head = player_y > enemy_head_y
	
	var player_velocity_y = 0.0
	if "velocity" in body:
		player_velocity_y = body.velocity.y
	var is_falling = player_velocity_y < 0
	
	
	# If player is doing a head stomp, don't damage them here
	if is_above_head and is_falling:
		return
	
	# Normal damage scenario
	can_chase = false
	damage_player(body)
	state_machine.change_state("aiidlestate")
	await get_tree().create_timer(1.3).timeout
	if is_instance_valid(self):
		can_chase = true
		

func _physics_process(delta: float) -> void:
	# Get current state name for debugging
	var current_state_name = ""
	if state_machine and state_machine.current_state:
		current_state_name = state_machine.current_state.get_script().get_global_name()
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		# Only reset Y velocity if not in knockback state
		if current_state_name != "AIKnockbackState":
			velocity.y = 0
	
	if damage_cooldown > 0:
		damage_cooldown -= delta
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	
	if state_machine:
		state_machine.update(delta)
	
	move_and_slide()

func take_damage(amount: int, knockback_velocity: Vector3 = Vector3.ZERO):
	"""Reduce health and apply knockback"""
	
	# Ignore damage if still in cooldown
	if damage_cooldown > 0:
		return
	
	
	current_health -= amount
	damage_cooldown = damage_cooldown_time
	
	# Visual feedback
	flash_color()
	
	# NEW: Drop paint droplets when hit (but not when dying)
	if current_health > 0 and drops_paint_on_hit:
		spawn_paint_droplets()
	
	# CRITICAL: Set the knockback BEFORE changing state
	if state_machine:
		var knockback_state = state_machine.states.get("aiknockbackstate") as AIKnockbackState
		if knockback_state:
			knockback_state.set_knockback(knockback_velocity)
		else:
			print("ERROR: Could not get knockback state!")
		
		state_machine.change_state("aiknockbackstate")
		
		# Double-check the velocity was applied
	
	# Check for death
	if current_health <= 0:
		die()

func spawn_paint_droplets():
	"""Spawn paint droplets when enemy is hit"""
	if not paint_droplet_scene:
		print("ERROR: Paint droplet scene not found!")
		return
	
	var spawn_position = global_position + Vector3(0, 0.5, 0)
	var droplet_count = randi_range(paint_droplet_count_min, paint_droplet_count_max)
	
	
	for i in range(droplet_count):
		var droplet = paint_droplet_scene.instantiate()
		get_parent().add_child(droplet)
		
		# Set random paint value
		var paint_value = randi_range(paint_droplet_value_min, paint_droplet_value_max)
		if droplet.has_method("set_paint_value"):
			droplet.set_paint_value(paint_value)
		
		# Scatter outward with a tween (droplets are Area3D - the old
		# apply_impulse branch was dead code)
		var angle = randf() * TAU
		var radius = randf_range(paint_scatter_radius * 0.3, paint_scatter_radius)
		var target = spawn_position + Vector3(cos(angle) * radius, randf_range(0.2, 0.6), sin(angle) * radius)
		
		droplet.global_position = spawn_position
		if droplet.has_method("scatter_to"):
			droplet.scatter_to(target, paint_scatter_duration)
		else:
			var tween = droplet.create_tween()
			tween.set_trans(Tween.TRANS_QUAD)
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(droplet, "global_position", target, paint_scatter_duration)

func die():
	"""Enemy dies, spawns gears, and is removed from scene"""
	
	if _boss_bar and is_instance_valid(_boss_bar):
		_boss_bar.dismiss()
		_boss_bar = null
	
	# Quest hook: report the kill if this enemy is a quest target
	if enemy_id != "":
		var qm = get_node_or_null("/root/QuestManager")
		if qm:
			qm.notify_enemy_defeated(enemy_id)
	
	# Spawn gear explosion
	if drops_gears_on_death:
		spawn_gear_explosion()
	
	# Optional death particles/effects here
	
	queue_free()

func spawn_gear_explosion():
	"""Spawn gears with a scatter effect when enemy dies.
	NOTE: gears are Area3D, not RigidBody3D - the old apply_impulse code
	silently did nothing. We animate the scatter with tweens instead."""
	if not gear_scene:
		print("ERROR: Gear scene not found!")
		return
	
	var spawn_position = global_position + Vector3(0, 0.5, 0)
	var gear_count = randi_range(gear_count_min, gear_count_max)
	var container = get_parent()
	
	for i in range(gear_count):
		var gear = gear_scene.instantiate()
		container.add_child(gear)
		
		var angle = randf() * TAU
		var radius = randf_range(gear_scatter_radius * 0.3, gear_scatter_radius)
		var target = spawn_position + Vector3(cos(angle) * radius, randf_range(0.3, 1.0), sin(angle) * radius)
		
		gear.global_position = spawn_position
		if gear.has_method("scatter_to"):
			gear.scatter_to(target, gear_scatter_duration)
		else:
			gear.global_position = target

func flash_color():
	"""Flash white when hit"""
	if mesh and mesh.material_override:
		var material = mesh.material_override.duplicate()
		material.albedo_color = Color.WHITE
		mesh.material_override = material
		
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			material.albedo_color = initial_color

func _on_head_hurtbox_body_entered(body: Node3D):
	"""Handle player jumping on enemy head"""
	if not body.is_in_group("Player"):
		return
	
	var player_velocity_y = body.velocity.y if "velocity" in body else 0.0
	var is_falling_or_jumping = player_velocity_y <= 0
	var is_above_enemy = body.global_position.y > global_position.y
	
	
	if is_above_enemy and is_falling_or_jumping:
		
		# CRITICAL: Set flag to prevent HitBox from damaging player
		being_stomped = true
		
		# Make player invulnerable WITHOUT flash (prevents damage from HitBox)
		if body.has_method("set_invulnerable_without_flash"):
			body.set_invulnerable_without_flash(0.5)
		
		# Give player bounce
		if "velocity" in body:
			body.velocity.y = bounce_feedback
		
		# Meaty head-bounce thud (Inspector slot overrides the default)
		var snd = stomp_sound if stomp_sound else Sfx.stomp_bounce()
		Sfx.play_3d(self, snd, global_position, stomp_volume_db)
		
		# Prevent enemy from damaging player
		can_chase = false
		
		# Damage the enemy
		take_damage(1)
		
		# Wait before re-enabling damage
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(self):
			being_stomped = false
			can_chase = true
# ============================================
# BASE STATE CLASS
# ============================================

class EnemyState extends Node:
	var enemy: Enemy
	
	func enter():
		pass
	
	func exit():
		pass
	
	func update(_delta: float):
		pass


# ============================================
# AI IDLE STATE
# ============================================

class AIIdleState extends EnemyState:
	var wander_timer: float = 0.0
	var wander_interval: float = 2.0
	var current_direction: Vector3 = Vector3.ZERO
	
	func enter():
		wander_timer = 0.0
		pick_wander_direction()
	
	func pick_wander_direction():
		var random_angle = randf() * TAU
		current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()
	
	func update(delta: float):
		# Even while idling: never loiter underneath an airborne player
		if enemy.stomp_evade_enabled and enemy._is_player_stomp_threat():
			enemy.state_machine.change_state("aievadestate")
			return
		
		if enemy.player and enemy.player.is_inside_tree() and enemy.can_chase:
			var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
			if distance_to_player < enemy.detection_range:
				enemy.state_machine.change_state("aichasestate")
				return
		
		# Keep the enemy within max_roam_distance of its spawn point
		var from_spawn = enemy.global_position - enemy.spawn_position
		from_spawn.y = 0
		if from_spawn.length() > enemy.max_roam_distance:
			# Head back toward spawn
			current_direction = -from_spawn.normalized()
			wander_timer = 0.0
		
		enemy.velocity.x = current_direction.x * enemy.wander_speed
		enemy.velocity.z = current_direction.z * enemy.wander_speed
		
		wander_timer += delta
		if wander_timer >= wander_interval:
			pick_wander_direction()
			wander_timer = 0.0


# ============================================
# AI CHASE STATE
# ============================================

class AIChaseState extends EnemyState:
	## Straightforward, aggressive chase. Enemies run AT the player and
	## commit to an attack when in range. Separation steering (from other
	## enemies only, never from the player) keeps groups spread out.
	var chase_timeout: float = 0.0
	var max_chase_time: float = 4.0
	
	func enter():
		chase_timeout = 0.0
	
	func update(delta: float):
		if not enemy.player or not enemy.player.is_inside_tree():
			enemy.state_machine.change_state("aiidlestate")
			return
		
		# Quick sidestep ONLY when a stomp is genuinely incoming
		# (player directly above AND falling)
		if enemy.stomp_evade_enabled and enemy._is_player_stomp_threat():
			enemy.state_machine.change_state("aievadestate")
			return
		
		var to_player = enemy.player.global_position - enemy.global_position
		to_player.y = 0
		var distance_to_player = to_player.length()
		
		# Give up if the player got far away
		if distance_to_player > enemy.detection_range * 1.5:
			chase_timeout += delta
			if chase_timeout > max_chase_time:
				enemy.state_machine.change_state("aiidlestate")
				return
		else:
			chase_timeout = 0.0
		
		# IN RANGE -> ATTACK (this is the fix: enemies now commit instead of
		# circling forever at arm's length)
		if distance_to_player <= enemy.get_preferred_attack_range() \
		and enemy.attack_cooldown_timer <= 0.0 and enemy.can_chase:
			enemy.state_machine.change_state(enemy.get_attack_state_name())
			return
		
		var direction_to_player = to_player.normalized()
		
		# Chase straight in + spread out from OTHER ENEMIES only
		var move = direction_to_player * enemy.chase_speed + enemy._separation_push()
		if move.length() > enemy.chase_speed:
			move = move.normalized() * enemy.chase_speed
		
		enemy.velocity.x = move.x
		enemy.velocity.z = move.z
		
		var target_rotation = atan2(-direction_to_player.x, -direction_to_player.z)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target_rotation, delta * 6.0)


# ============================================
# AI ATTACK STATE - telegraphed lunge
# ============================================

class AIAttackState extends EnemyState:
	## Windup (telegraph, squash down) -> lunge at the player -> recovery.
	## Contact damage during the lunge is handled by the HitBox as usual.
	var phase: String = "windup"
	var timer: float = 0.0
	var lunge_direction: Vector3 = Vector3.ZERO
	
	func enter():
		phase = "windup"
		timer = 0.0
		enemy.velocity.x = 0
		enemy.velocity.z = 0
		
		# Telegraph: crouch down like a spring being loaded
		if enemy.mesh:
			var tween = enemy.create_tween()
			tween.tween_property(enemy.mesh, "scale", Vector3(1.15, 0.75, 1.15), enemy.attack_windup)
	
	func update(delta: float):
		timer += delta
		
		match phase:
			"windup":
				# Track the player while winding up
				if enemy.player and enemy.player.is_inside_tree():
					var to_player = enemy.player.global_position - enemy.global_position
					to_player.y = 0
					if to_player.length() > 0.1:
						lunge_direction = to_player.normalized()
						var target_rotation = atan2(-lunge_direction.x, -lunge_direction.z)
						enemy.rotation.y = lerp_angle(enemy.rotation.y, target_rotation, delta * 10.0)
				enemy.velocity.x = 0
				enemy.velocity.z = 0
				
				if timer >= enemy.attack_windup:
					phase = "lunge"
					timer = 0.0
					# Release the spring!
					if enemy.mesh:
						var tween = enemy.create_tween()
						tween.tween_property(enemy.mesh, "scale", Vector3(0.85, 1.2, 0.85), 0.1)
						tween.tween_property(enemy.mesh, "scale", Vector3.ONE, 0.15)
			"lunge":
				enemy.velocity.x = lunge_direction.x * enemy.lunge_speed
				enemy.velocity.z = lunge_direction.z * enemy.lunge_speed
				
				if timer >= enemy.lunge_duration:
					phase = "recovery"
					timer = 0.0
			"recovery":
				# Skid to a stop; vulnerable window
				enemy.velocity.x = lerp(enemy.velocity.x, 0.0, delta * 8.0)
				enemy.velocity.z = lerp(enemy.velocity.z, 0.0, delta * 8.0)
				
				if timer >= enemy.attack_recovery:
					enemy.attack_cooldown_timer = enemy.attack_cooldown
					enemy.state_machine.change_state("aichasestate")
	
	func exit():
		if enemy.mesh:
			enemy.mesh.scale = Vector3.ONE


# ============================================
# AI EVADE STATE - quick sidestep, then back to the fight
# ============================================

class AIEvadeState extends EnemyState:
	## A SHORT dodge out from under an incoming stomp - not a retreat.
	## Sidesteps perpendicular to the player and immediately re-engages.
	var evade_direction: Vector3 = Vector3.ZERO
	var evade_time: float = 0.0
	const MAX_EVADE_TIME: float = 0.6
	
	func enter():
		evade_time = 0.0
		# Sidestep sideways (perpendicular to the player), randomized left/right
		var away = enemy.global_position - enemy.player.global_position
		away.y = 0
		if away.length() < 0.1:
			away = Vector3(randf() - 0.5, 0, randf() - 0.5)
		away = away.normalized()
		var side = away.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
		evade_direction = (away * 0.5 + side * 0.9).normalized()
	
	func update(delta: float):
		if not enemy.player or not enemy.player.is_inside_tree():
			enemy.state_machine.change_state("aiidlestate")
			return
		
		evade_time += delta
		
		# Done dodging (or threat passed): straight back to the chase
		if evade_time >= MAX_EVADE_TIME or not enemy._is_player_stomp_threat():
			if evade_time >= 0.25:  # Minimum commitment so it reads as a dodge
				enemy.state_machine.change_state("aichasestate")
				return
		
		enemy.velocity.x = evade_direction.x * enemy.evade_speed
		enemy.velocity.z = evade_direction.z * enemy.evade_speed
		
		# Keep FACING the player while dodging (it's a sidestep, not a flee)
		var to_player = enemy.player.global_position - enemy.global_position
		to_player.y = 0
		if to_player.length() > 0.1:
			var face = to_player.normalized()
			var target_rotation = atan2(-face.x, -face.z)
			enemy.rotation.y = lerp_angle(enemy.rotation.y, target_rotation, delta * 8.0)


# ============================================
# AI KNOCKBACK STATE - FIXED VERSION
# ============================================

class AIKnockbackState extends EnemyState:
	var knockback_velocity: Vector3 = Vector3.ZERO
	var knockback_duration: float = 0.8
	var knockback_timer: float = 0.0
	var initial_upward_velocity: float = 0.0
	var min_air_time: float = 0.1  # Minimum time before we check for landing
	
	func set_knockback(new_knockback: Vector3):
		"""Set the knockback velocity from external source"""
		knockback_velocity = new_knockback
		initial_upward_velocity = new_knockback.y
	
	func enter():
		knockback_timer = 0.0
		
		# If no knockback was set externally, use default
		if knockback_velocity.length() < 0.1:
			knockback_velocity = enemy.global_transform.basis.z * -8.0
			knockback_velocity.y = 3.0
			initial_upward_velocity = 3.0
		
		# Apply initial knockback immediately
		enemy.velocity = knockback_velocity
	
	func update(delta: float):
		knockback_timer += delta
		
		# Use normal gravity from the enemy (9.8)
		enemy.velocity.y -= enemy.gravity * delta
		
		# Gradually reduce horizontal knockback (air resistance)
		var horizontal_decay = 0.98  # Very slight decay
		enemy.velocity.x *= horizontal_decay
		enemy.velocity.z *= horizontal_decay
		
		# CRITICAL FIX: Only check for landing AFTER min_air_time has passed
		# This gives the enemy time to actually leave the ground
		if knockback_timer >= min_air_time:
			if enemy.is_on_floor() and enemy.velocity.y <= 0:
				enemy.state_machine.change_state("aiidlestate")
		
		# Safety timeout
		if knockback_timer >= knockback_duration * 2.0:
			enemy.state_machine.change_state("aiidlestate")
	
	func exit():
		# Reset knockback velocity for next time
		knockback_velocity = Vector3.ZERO
		initial_upward_velocity = 0.0


# ============================================
# ENEMY STATE MACHINE
# ============================================

class EnemyStateMachine extends Node:
	var enemy: Enemy
	var current_state: EnemyState
	var states: Dictionary = {}
	
	func initialize_states():
		var idle_state = AIIdleState.new()
		states["aiidlestate"] = idle_state
		
		var chase_state = AIChaseState.new()
		states["aichasestate"] = chase_state
		
		var knockback_state = AIKnockbackState.new()
		states["aiknockbackstate"] = knockback_state
		
		var evade_state = AIEvadeState.new()
		states["aievadestate"] = evade_state
		
		var attack_state = AIAttackState.new()
		states["aiattackstate"] = attack_state
		
		enemy._register_extra_states(states)
		
		change_state("aiidlestate")
	
	func change_state(state_name: String):
		if current_state:
			current_state.exit()
		
		current_state = states.get(state_name.to_lower())
		if current_state:
			current_state.enemy = enemy
			current_state.enter()
	
	func update(delta: float):
		if current_state:
			current_state.update(delta)
