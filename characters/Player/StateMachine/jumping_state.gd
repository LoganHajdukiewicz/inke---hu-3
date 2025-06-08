extends State
class_name JumpingState

var jump_velocity : float = 5.0

func enter():
	print("Entered Jumping State")
	player.velocity.y = jump_velocity

func physics_update(delta: float):
	player.velocity += player.get_gravity() * delta

	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var direction : Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		var current_horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
		var air_speed = max(current_horizontal_speed, 8.0)  # At least walking speed
		var target_velocity = direction * air_speed
		
		var air_control_factor = 0.3  # Adjust this value (0.0 = no air control, 1.0 = full control)
		player.velocity.x = lerp(player.velocity.x, target_velocity.x, air_control_factor)
		player.velocity.z = lerp(player.velocity.z, target_velocity.z, air_control_factor)

	if player.velocity.y <= 0:
		change_to("FallingState")
		return
	
	player.move_and_slide()
