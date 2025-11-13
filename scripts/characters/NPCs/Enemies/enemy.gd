extends CharacterBody3D
class_name Enemy

# Health system
@export var max_health: int = 3
@export var current_health: int = 3

# Behavior parameters
@export var detection_range: float = 15.0
@export var chase_speed: float = 8.0
@export var wander_speed: float = 3.0
@export var damage_to_player: int = 1
@export var bounce_feedback: int = 9
var can_chase := true

# Physics
var gravity: float = 9.8

# Damage cooldown
var damage_cooldown: float = 0.0
var damage_cooldown_time: float = 0.5  # Brief cooldown after taking damage

# State machine
var state_machine: EnemyStateMachine
var player: CharacterBody3D = null

# Animation/Visual
@onready var mesh: MeshInstance3D = $MeshInstance3D
var initial_color: Color

func _ready():
	# Find the player in the scene
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
	
	# Store initial color for hit feedback
	if mesh and mesh.material_override:
		initial_color = mesh.material_override.albedo_color
	
	# Initialize state machine
	state_machine = EnemyStateMachine.new()
	state_machine.enemy = self
	add_child(state_machine)
	state_machine.initialize_states()
	
	# Setup damage detection for when player jumps on head
	if has_node("HeadHurtbox"):
		$HeadHurtbox.body_entered.connect(_on_head_hurtbox_body_entered)

func damage_player(player_body: Node3D):
	"""Apply damage and knockback to the player"""
	if not player_body.has_method("take_damage"):
		return
	
	# Calculate knockback direction (away from enemy)
	var knockback_direction = (player_body.global_position - global_position).normalized()
	knockback_direction.y = 0  # Keep horizontal
	
	# Apply damage with knockback info
	player_body.take_damage(damage_to_player, knockback_direction)


func _on_hit_box_body_entered(body: Node) -> void:
	if body.is_in_group("Player") and can_chase:
		can_chase = false
		damage_player(body)
		state_machine.change_state("aiidlestate")
		await get_tree().create_timer(1.3).timeout
		can_chase = true

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	# Update damage cooldown
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	# Update state machine
	if state_machine:
		state_machine.update(delta)
	
	move_and_slide()

func take_damage(amount: int):
	"""Reduce health and show hit feedback"""
	# Ignore damage if still in cooldown
	if damage_cooldown > 0:
		return
	
	current_health -= amount
	damage_cooldown = damage_cooldown_time
	
	# Visual feedback when hit
	flash_color()
	
	# Transition to knockback state
	if state_machine:
		state_machine.change_state("aiknockbackstate")
	
	if current_health <= 0:
		die()

func die():
	"""Enemy dies and is removed from scene"""
	queue_free()

func flash_color():
	"""Flash white when hit"""
	if mesh and mesh.material_override:
		var material = mesh.material_override.duplicate()
		material.albedo_color = Color.WHITE
		mesh.material_override = material
		
		# Reset color after brief delay
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			material.albedo_color = initial_color

func _on_head_hurtbox_body_entered(body: Node3D):
	"""Handle player jumping on enemy head"""
	if body.is_in_group("Player"):
		# Check if player is moving downward OR if they're in jumping/falling states
		var player_velocity_y = body.velocity.y
		var is_falling_or_jumping = player_velocity_y < 0 or player_velocity_y == 0
		var is_above_enemy = body.global_position.y > global_position.y
		
		# If player is above enemy and moving down (or stationary), take damage
		if is_above_enemy and is_falling_or_jumping:
			take_damage(1)
			# Give player bounce feedback
			body.velocity.y = bounce_feedback


# ============================================
# BASE STATE CLASS
# ============================================

class EnemyState extends Node:
	var enemy: Enemy
	
	func enter():
		pass
	
	func exit():
		pass
	
	func update(delta: float):
		pass


# ============================================
# AI IDLE STATE - Wander around aimlessly
# ============================================

class AIIdleState extends EnemyState:
	var wander_timer: float = 0.0
	var wander_interval: float = 2.0
	var current_direction: Vector3 = Vector3.ZERO
	
	func enter():
		print("Enemy entering AI IDLE state")
		wander_timer = 0.0
		pick_wander_direction()
	
	func pick_wander_direction():
		"""Choose a random direction to wander"""
		var random_angle = randf() * TAU
		current_direction = Vector3(cos(random_angle), 0, sin(random_angle)).normalized()
	
	func update(delta: float):
		# Check if player is nearby - if so, switch to chase (only if allowed)
		if enemy.player and enemy.player.is_inside_tree() and enemy.can_chase:
			var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
			if distance_to_player < enemy.detection_range:
				enemy.state_machine.change_state("aichasestate")
				return
		
		# Wander around
		enemy.velocity.x = current_direction.x * enemy.wander_speed
		enemy.velocity.z = current_direction.z * enemy.wander_speed
		
		# Change direction periodically
		wander_timer += delta
		if wander_timer >= wander_interval:
			pick_wander_direction()
			wander_timer = 0.0


# ============================================
# AI CHASE STATE - Pursue the player
# ============================================

class AIChaseState extends EnemyState:
	var chase_timeout: float = 0.0
	var max_chase_time: float = 4.0  # Give up after 4 seconds
	
	func enter():
		print("Enemy entering AI CHASE state")
		chase_timeout = 0.0
	
	func update(delta: float):
		if not enemy.player or not enemy.player.is_inside_tree():
			enemy.state_machine.change_state("aiidlestate")
			return
		
		var distance_to_player = enemy.global_position.distance_to(enemy.player.global_position)
		
		# If player is out of range, return to idle
		if distance_to_player > enemy.detection_range * 1.5:
			chase_timeout += delta
			if chase_timeout > max_chase_time:
				enemy.state_machine.change_state("aiidlestate")
				return
		else:
			chase_timeout = 0.0  # Reset timeout while player is in range
		
		# Calculate direction to player
		var direction_to_player = (enemy.player.global_position - enemy.global_position).normalized()
		
		# Move towards player
		enemy.velocity.x = direction_to_player.x * enemy.chase_speed
		enemy.velocity.z = direction_to_player.z * enemy.chase_speed
		
		# Rotate to face player
		var target_rotation = atan2(-direction_to_player.x, -direction_to_player.z)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, target_rotation, delta * 5.0)


# ============================================
# AI KNOCKBACK STATE - React to being hit
# ============================================

class AIKnockbackState extends EnemyState:
	var knockback_velocity: Vector3 = Vector3.ZERO
	var knockback_duration: float = 0.15  # Much shorter knockback
	var knockback_timer: float = 0.0
	
	func enter():
		print("Enemy entering AI KNOCKBACK state")
		knockback_timer = 0.0
		# Enemy was just hit, so apply knockback - straight up and back
		knockback_velocity = enemy.global_transform.basis.z * -3.0  # Less horizontal force
		knockback_velocity.y = 2.0  # Quick upward burst
	
	func update(delta: float):
		knockback_timer += delta
		
		# Apply knockback movement
		enemy.velocity.x = knockback_velocity.x
		enemy.velocity.z = knockback_velocity.z
		enemy.velocity.y = knockback_velocity.y
		
		# Quick decay - knockback ends fast
		var decay_factor = 1.0 - (knockback_timer / knockback_duration)
		knockback_velocity *= decay_factor
		
		# Return to appropriate state
		if knockback_timer >= knockback_duration:
			enemy.state_machine.change_state("aiidlestate")


# ============================================
# ENEMY STATE MACHINE
# ============================================

class EnemyStateMachine extends Node:
	var enemy: Enemy
	var current_state: EnemyState
	var states: Dictionary = {}
	
	func initialize_states():
		"""Create and register all states"""
		# Idle state - wander around
		var idle_state = AIIdleState.new()
		states["aiidlestate"] = idle_state
		
		# Chase state - pursue player
		var chase_state = AIChaseState.new()
		states["aichasestate"] = chase_state
		
		# Knockback state - react to being hit
		var knockback_state = AIKnockbackState.new()
		states["aiknockbackstate"] = knockback_state
		
		# Set initial state
		change_state("aiidlestate")
	
	func change_state(state_name: String):
		"""Transition to a new state"""
		if current_state:
			current_state.exit()
		
		current_state = states.get(state_name.to_lower())
		if current_state:
			current_state.enemy = enemy
			current_state.enter()
	
	func update(delta: float):
		"""Update the current state"""
		if current_state:
			current_state.update(delta)
