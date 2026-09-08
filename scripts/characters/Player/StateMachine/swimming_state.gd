extends State
class_name SwimmingState

## Swim on the surface, dive under with an oxygen limit. Water is world
## boundary, not core gameplay: simple, forgiving movement.
##
##   Surface: move with the stick, JUMP = hop (climb out on a bank),
##            CROUCH (hold) = dive under.
##   Diving:  JUMP = rise, CROUCH = sink, oxygen drains while your head
##            is under. It refills in a second at the surface.
##   Oxygen empty = drown (die + respawn at checkpoint).
##
## The WaterZone node handles the buoy boundary + shark separately.

@export var swim_speed: float = 6.0
@export var dive_speed: float = 5.0
## Vertical speed while rising/sinking underwater.
@export var vertical_speed: float = 4.0
## How far below the surface Inke floats while surface swimming.
@export var float_depth: float = 0.35
## Hop velocity when jumping at the surface (enough to clear a bank).
@export var surface_hop_velocity: float = 6.5

var oxygen: float = 12.0
var oxygen_max: float = 12.0
var is_underwater := false

var _oxy_ui: CanvasLayer = null
var _oxy_bar: ColorRect = null
var _oxy_fill: ColorRect = null
var _bob_t := 0.0


func enter():
	var wz = player.current_water
	oxygen_max = wz.oxygen_seconds if wz else 12.0
	oxygen = oxygen_max
	is_underwater = false
	player.gravity = 0.0
	player.velocity.y = 0.0
	# Splash: kill most of the entry momentum
	player.velocity.x *= 0.4
	player.velocity.z *= 0.4
	player.can_double_jump = true
	player.has_double_jumped = false


func exit():
	player.gravity = player.gravity_default
	_hide_oxygen_ui()


func get_speed():
	return swim_speed


func physics_update(delta: float):
	var wz = player.current_water
	if wz == null or not is_instance_valid(wz):
		# Left the water volume
		change_to("FallingState")
		return
	if player.controls_disabled:
		return
	
	var surface: float = wz.get_surface_height()
	_bob_t += delta
	
	# Camera-relative horizontal input
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	var camera_basis = player.get_node("CameraController").transform.basis
	var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0.0
	if direction.length() > 0.05:
		direction = direction.normalized()
		var target_rotation = atan2(-direction.x, -direction.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, 8.0 * delta)
	
	var speed := dive_speed if is_underwater else swim_speed
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	
	# Vertical control
	var head_y: float = player.global_position.y + 0.6
	if is_underwater:
		var vy := 0.0
		if Input.is_action_pressed("jump"):
			vy = vertical_speed
		elif Input.is_action_pressed("crouch"):
			vy = -vertical_speed
		else:
			vy = 0.6   # Gentle buoyancy: drift up when idle
		player.velocity.y = vy
		# Don't rise above the surface float line, don't sink below the volume
		if player.global_position.y >= surface - float_depth - 0.6 and vy > 0.0:
			is_underwater = false
		var bottom: float = surface - wz.water_depth + 0.8
		if player.global_position.y < bottom and vy < 0.0:
			player.velocity.y = 0.0
	else:
		# Surface: stick to the float line with a light bob
		var want_y: float = surface - float_depth - 0.6 + sin(_bob_t * 2.2) * 0.06
		player.velocity.y = clampf((want_y - player.global_position.y) * 6.0, -3.0, 3.0)
		if Input.is_action_just_pressed("jump"):
			# Hop - lets you climb onto banks/docks
			player.gravity = player.gravity_default
			player.velocity.y = surface_hop_velocity
			change_to("JumpingState")
			return
		if Input.is_action_pressed("crouch"):
			is_underwater = true
			player.velocity.y = -vertical_speed
	
	player.move_and_slide()
	
	# Walked onto ground shallow enough to stand? Back to land states.
	if player.is_on_floor() and player.global_position.y > surface - 1.0:
		change_to("IdleState")
		return
	
	# --- Oxygen -------------------------------------------------------------
	# Only DIVING drains air - surface swimming keeps your head out (the
	# float line dips the collider under, so a raw height check would
	# wrongly drain at the surface too).
	var head_under: bool = is_underwater and head_y < surface
	if head_under:
		oxygen = maxf(oxygen - delta, 0.0)
		_show_oxygen_ui()
		if oxygen <= 0.0:
			_hide_oxygen_ui()
			if player.has_method("die"):
				player.die()
			return
	else:
		oxygen = minf(oxygen + delta * oxygen_max, oxygen_max)   # Fast refill
		if oxygen >= oxygen_max:
			_hide_oxygen_ui()
	_update_oxygen_ui()


# --- Oxygen bar UI -------------------------------------------------------------

func _show_oxygen_ui():
	if _oxy_ui and is_instance_valid(_oxy_ui):
		_oxy_ui.visible = true
		return
	_oxy_ui = CanvasLayer.new()
	_oxy_ui.layer = 80
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.position = Vector2(0, -120)
	_oxy_ui.add_child(holder)
	_oxy_bar = ColorRect.new()
	_oxy_bar.color = Color(0.05, 0.08, 0.1, 0.75)
	_oxy_bar.size = Vector2(320, 22)
	_oxy_bar.position = Vector2(-160, 0)
	holder.add_child(_oxy_bar)
	_oxy_fill = ColorRect.new()
	_oxy_fill.color = Color(0.25, 0.85, 1.0)
	_oxy_fill.size = Vector2(314, 16)
	_oxy_fill.position = Vector2(3, 3)
	_oxy_bar.add_child(_oxy_fill)
	var lbl := Label.new()
	lbl.text = "OXYGEN"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.position = Vector2(-160, -22)
	holder.add_child(lbl)
	player.add_child(_oxy_ui)


func _update_oxygen_ui():
	if _oxy_fill and is_instance_valid(_oxy_fill) and _oxy_ui.visible:
		var f: float = oxygen / maxf(oxygen_max, 0.01)
		_oxy_fill.size.x = 314.0 * f
		# Blue -> red as it runs out
		_oxy_fill.color = Color(0.25, 0.85, 1.0).lerp(Color(1.0, 0.2, 0.1), 1.0 - f if f < 0.35 else 0.0)


func _hide_oxygen_ui():
	if _oxy_ui and is_instance_valid(_oxy_ui):
		_oxy_ui.visible = false
