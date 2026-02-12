extends State
class_name LedgeJumpState

@export var vault_duration: float = 0.3  # Faster than climb since it's a low ledge
@export var hang_offset: float = 0.8  # Distance from wall (matches LedgeHangingState)

# Internal state
var ledge_position: Vector3 = Vector3.ZERO
var ledge_normal: Vector3 = Vector3.ZERO
var is_vaulting: bool = false

func setup_ledge_hang(ledge_pos: Vector3, wall_normal: Vector3):
	ledge_position = ledge_pos
	ledge_normal = wall_normal
	print("Ledge vault setup - Pos: ", ledge_position, " Normal: ", ledge_normal)

func enter():
	print("=== ENTERED LEDGE JUMP STATE ===")
	print("Ledge position: ", ledge_position)
	print("Wall normal: ", ledge_normal)
	player.velocity = Vector3.ZERO
	player.set_velocity(Vector3.ZERO)
# Disable gravity while vaulting
	if player.has_method("set"):
		player.set("gravity", 0.0)

# Immediately start vault — no hanging
	vault_up()

func physics_update(_delta: float):
	if is_vaulting:
	# Lock velocity to zero during vault animation
		player.velocity = Vector3.ZERO

func vault_up():
	if is_vaulting:
		return

	is_vaulting = true

	# Calculate target position on top of ledge
	var vault_target = ledge_position
	vault_target.y = ledge_position.y + 0.1  # Slightly above the ledge surface
	vault_target -= ledge_normal * 0.8
	print("Vaulting from: ", player.global_position)
	print("Vaulting to: ", vault_target)

	# Create vault animation
	var tween = create_tween()
	tween.set_parallel(false)

	# Move up and forward in one smooth motion
	tween.tween_property(player, "global_position", vault_target, vault_duration)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	var scale_tween = create_tween()
	scale_tween.set_parallel(true)
	scale_tween.tween_property(player, "scale", Vector3(1.1, 0.9, 1.1), vault_duration * 0.3)
	scale_tween.tween_property(player, "scale", Vector3.ONE, vault_duration * 0.7).set_delay(vault_duration * 0.3)

	# Wait for vault to complete
	await tween.finished
	change_to("IdleState")

func exit():
	print("=== EXITED LEDGE JUMP STATE ===")
	is_vaulting = false
	player.scale = Vector3.ONE

# Restore gravity using player's property
	if player.has_method("set") and player.has_method("get"):
		var default_gravity = player.get("gravity_default")
		if default_gravity != null:
			player.set("gravity", default_gravity)
			print("Restored gravity to: ", default_gravity)
	print("Final velocity on exit: ", player.velocity)
