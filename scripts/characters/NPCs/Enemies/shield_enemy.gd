extends Enemy
class_name ShieldEnemy

## Melee enemy carrying a big front shield. Attacks from the FRONT are
## blocked (clang, no damage, small recoil for the player). To hurt it:
##  - hit it from BEHIND (flank while it turns), or
##  - stomp its head from above, or
##  - break its guard: a blocked heavy hit staggers it briefly, dropping
##    the shield.
## The shield is visualized as a plate in front of the body.

@export_group("Shield")
@export var shield_arc_degrees: float = 130.0    # Frontal cone that blocks damage
@export var block_stagger_hits: int = 3          # Blocks before a guard-break stagger
@export var stagger_duration: float = 1.6        # Vulnerable window after guard break
@export var shield_color: Color = Color(0.35, 0.4, 0.55)

var shield_mesh: MeshInstance3D = null
var blocks_taken: int = 0
var is_staggered: bool = false
var stagger_timer: float = 0.0

func _ready():
	super._ready()
	_create_shield_visual()
	# Shield enemies are tanky but slow
	chase_speed *= 0.8

func _create_shield_visual():
	shield_mesh = MeshInstance3D.new()
	shield_mesh.name = "ShieldPlate"
	var plate = BoxMesh.new()
	plate.size = Vector3(1.1, 1.2, 0.12)
	shield_mesh.mesh = plate
	var mat = StandardMaterial3D.new()
	mat.albedo_color = shield_color
	mat.metallic = 0.7
	mat.roughness = 0.35
	shield_mesh.material_override = mat
	shield_mesh.position = Vector3(0, 0.6, -0.55)  # In front (enemy faces -Z)
	add_child(shield_mesh)

func _physics_process(delta: float) -> void:
	if is_staggered:
		stagger_timer -= delta
		if stagger_timer <= 0.0:
			is_staggered = false
			blocks_taken = 0
			if shield_mesh:
				# Shield comes back up
				var tween = create_tween()
				tween.tween_property(shield_mesh, "position", Vector3(0, 0.6, -0.55), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tween.parallel().tween_property(shield_mesh, "rotation", Vector3.ZERO, 0.25)
	super._physics_process(delta)

func _is_attack_from_front(attacker_position: Vector3) -> bool:
	"""Is the attacker inside the frontal shield arc?"""
	var to_attacker = attacker_position - global_position
	to_attacker.y = 0
	if to_attacker.length() < 0.1:
		return true
	var facing = -global_transform.basis.z
	facing.y = 0
	var angle = rad_to_deg(facing.normalized().angle_to(to_attacker.normalized()))
	return angle <= shield_arc_degrees * 0.5

func take_damage(amount: int, knockback_velocity: Vector3 = Vector3.ZERO):
	# Staggered = guard is down, damage goes through normally
	if is_staggered:
		super.take_damage(amount, knockback_velocity)
		return
	
	# Where did the hit come from? Knockback pushes AWAY from the attacker,
	# so the attacker sits opposite the knockback. Fall back to the player.
	var attacker_pos: Vector3
	var kb_flat = Vector3(knockback_velocity.x, 0, knockback_velocity.z)
	if kb_flat.length() > 0.5:
		attacker_pos = global_position - kb_flat.normalized() * 2.0
	elif player and is_instance_valid(player):
		attacker_pos = player.global_position
	else:
		attacker_pos = global_position + global_transform.basis.z  # Behind = hit lands
	
	if _is_attack_from_front(attacker_pos):
		_block_hit()
		return
	
	# Hit from behind - full damage
	super.take_damage(amount, knockback_velocity)

func _block_hit():
	"""Attack bounced off the shield."""
	blocks_taken += 1
	
	# Clang feedback: shield flash + brief brace
	if shield_mesh and shield_mesh.material_override is StandardMaterial3D:
		var mat = shield_mesh.material_override
		var tween = create_tween()
		tween.tween_property(mat, "albedo_color", Color(0.9, 0.95, 1.0), 0.05)
		tween.tween_property(mat, "albedo_color", shield_color, 0.15)
	var brace = create_tween()
	brace.tween_property(self, "scale", Vector3(1.06, 0.95, 1.06), 0.06)
	brace.tween_property(self, "scale", Vector3.ONE, 0.1)
	
	# Small recoil for the player so blocked spam feels wrong
	if player and is_instance_valid(player) and "velocity" in player:
		var push = (player.global_position - global_position)
		push.y = 0
		if push.length() > 0.1:
			player.velocity += push.normalized() * 5.0
	
	# Guard break after enough blocks
	if blocks_taken >= block_stagger_hits:
		_guard_break()

func strip_shield():
	"""The grapple hook rips the shield away entirely: the plate goes
	flying and this enemy fights unshielded from now on. Called by
	GrappleHookState when the player hooks us."""
	if shield_mesh == null or not is_instance_valid(shield_mesh):
		return
	is_staggered = true            # No blocking anymore
	stagger_timer = 999999.0       # Permanent: shield never comes back
	blocks_taken = 0
	# The plate tears off and tumbles away
	var plate = shield_mesh
	shield_mesh = null
	var fly_dir = global_transform.basis.z + Vector3(randf_range(-0.4, 0.4), 1.2, 0)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(plate, "global_position", plate.global_position + fly_dir.normalized() * 4.0, 0.6)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(plate, "rotation", Vector3(randf_range(2, 5), randf_range(2, 5), randf_range(2, 5)), 0.6)
	tween.tween_property(plate, "scale", Vector3.ONE * 0.05, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(plate.queue_free)
	# Startled hop
	var hop = create_tween()
	hop.tween_property(self, "scale", Vector3(0.9, 1.15, 0.9), 0.1)
	hop.tween_property(self, "scale", Vector3.ONE, 0.15)

func _guard_break():
	"""Too many blocks: stagger, shield drops, enemy is vulnerable."""
	is_staggered = true
	stagger_timer = stagger_duration
	blocks_taken = 0
	
	if shield_mesh:
		# Shield droops to the side
		var tween = create_tween()
		tween.tween_property(shield_mesh, "position", Vector3(0.5, 0.25, -0.35), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(shield_mesh, "rotation", Vector3(0, 0, deg_to_rad(-55)), 0.2)
	
	# Dizzy wobble
	var wobble = create_tween()
	wobble.set_loops(int(stagger_duration / 0.3))
	wobble.tween_property(self, "rotation:z", 0.08, 0.15)
	wobble.tween_property(self, "rotation:z", -0.08, 0.15)
	var straighten = create_tween()
	straighten.tween_interval(stagger_duration)
	straighten.tween_property(self, "rotation:z", 0.0, 0.1)
