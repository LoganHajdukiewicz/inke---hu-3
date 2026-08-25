extends Node
class_name GrappleTargetManager

## Continuously tracks what the grapple hook would attach to and shows an
## on-screen reticle over it. GrappleHookState reads current_target /
## current_target_type instead of doing its own search, so what you SEE
## is always what you GET.
##
## Rules mirrored from GrappleHookState:
## - Grapple POINTS: only targetable while airborne (no ground swing).
## - ENEMIES: targetable from ground or air.

const POINT_COLOR := Color(0.0, 1.0, 0.8, 1.0)   # Teal - matches grapple point glow
const ENEMY_COLOR := Color(1.0, 0.3, 0.3, 1.0)   # Red - enemy grapple
const RETICLE_SIZE := 44.0

# What we're currently locked onto
var current_target: Node3D = null
var current_target_type: String = ""  # "point", "enemy" or ""

var player: CharacterBody3D
var camera: Camera3D

# UI
var canvas: CanvasLayer
var reticle: Control

# Search config (read from GrappleHookState exports at startup)
var point_range: float = 30.0
var enemy_range: float = 15.0

var _highlighted_point: Node3D = null


func _ready():
	player = get_parent() as CharacterBody3D
	
	_create_reticle()
	
	# Pull ranges from the grapple state so tuning stays in one place
	var state_machine = player.get_node_or_null("StateMachine")
	if state_machine:
		var grapple_state = state_machine.states.get("grapplehookstate")
		if grapple_state:
			point_range = grapple_state.max_grapple_distance
			enemy_range = grapple_state.enemy_grapple_distance


func _create_reticle():
	canvas = CanvasLayer.new()
	canvas.name = "GrappleReticleCanvas"
	canvas.layer = 10
	add_child(canvas)
	
	reticle = Control.new()
	reticle.name = "GrappleReticle"
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.visible = false
	reticle.draw.connect(_draw_reticle)
	canvas.add_child(reticle)


func _draw_reticle():
	var color := ENEMY_COLOR if current_target_type == "enemy" else POINT_COLOR
	var half := RETICLE_SIZE * 0.5
	var gap := RETICLE_SIZE * 0.18
	var width := 3.0
	
	# Four corner brackets (lock-on style)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * half, sy * half)
			reticle.draw_line(corner, corner - Vector2(sx * (half - gap), 0), color, width)
			reticle.draw_line(corner, corner - Vector2(0, sy * (half - gap)), color, width)
	
	# Center dot
	reticle.draw_circle(Vector2.ZERO, 3.0, color)


func _process(_delta):
	if not player or not is_instance_valid(player):
		return
	
	camera = player.get_viewport().get_camera_3d()
	if not camera:
		_set_target(null, "")
		return
	
	# Don't retarget while already grappling - keep the reticle on the
	# active target so the player sees what they're attached to
	var state_machine = player.get_node_or_null("StateMachine")
	if state_machine and state_machine.current_state:
		var state_name = state_machine.current_state.get_script().get_global_name()
		if state_name == "GrappleHookState":
			_update_reticle_position()
			return
	
	_search_for_target()
	_update_reticle_position()


func _search_for_target():
	"""Find the best grapple target under current rules"""
	var camera_forward: Vector3 = player.get_node("CameraController").get_camera_forward()
	
	# Enemies: always allowed (ground or air)
	var best_enemy = _best_in_group("Enemy", enemy_range, camera_forward)
	
	# Grapple points: only while airborne (no ground swinging)
	var best_point: Node3D = null
	if not player.is_on_floor():
		best_point = _best_in_group("GrapplePoint", point_range, camera_forward)
	
	# Prefer the better-aligned target if both exist
	if best_enemy and best_point:
		var enemy_align = _alignment(best_enemy, camera_forward)
		var point_align = _alignment(best_point, camera_forward)
		if enemy_align >= point_align:
			_set_target(best_enemy, "enemy")
		else:
			_set_target(best_point, "point")
	elif best_enemy:
		_set_target(best_enemy, "enemy")
	elif best_point:
		_set_target(best_point, "point")
	else:
		_set_target(null, "")


func _alignment(node: Node3D, camera_forward: Vector3) -> float:
	return (node.global_position - player.global_position).normalized().dot(camera_forward)


func _best_in_group(group: String, max_range: float, camera_forward: Vector3) -> Node3D:
	var best: Node3D = null
	var best_score: float = -INF
	
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		
		var to_node = node.global_position - player.global_position
		var distance = to_node.length()
		if distance > max_range:
			continue
		
		var alignment = to_node.normalized().dot(camera_forward)
		# Must be roughly in front of the camera to count as "aimed at"
		if alignment < 0.3:
			continue
		
		var score = alignment * 2.0 - (distance / max_range)
		if score > best_score:
			best_score = score
			best = node
	
	return best


func _set_target(target: Node3D, type: String):
	if current_target == target:
		return
	
	# Unhighlight old grapple point
	if _highlighted_point and is_instance_valid(_highlighted_point) and _highlighted_point.has_method("unhighlight"):
		_highlighted_point.unhighlight()
	_highlighted_point = null
	
	current_target = target
	current_target_type = type if target else ""
	
	# Highlight new grapple point (they support it natively)
	if target and type == "point" and target.has_method("highlight"):
		target.highlight()
		_highlighted_point = target


func _update_reticle_position():
	if not current_target or not is_instance_valid(current_target) or not camera:
		reticle.visible = false
		return
	
	var world_pos: Vector3 = current_target.global_position
	if current_target_type == "enemy":
		world_pos += Vector3(0, 0.5, 0)  # Aim at enemy center mass
	
	# Hide if behind the camera
	if camera.is_position_behind(world_pos):
		reticle.visible = false
		return
	
	reticle.position = camera.unproject_position(world_pos)
	reticle.visible = true
	reticle.queue_redraw()


func get_target() -> Node3D:
	"""Current valid target or null (validity re-checked)"""
	if current_target and is_instance_valid(current_target):
		return current_target
	return null


func get_target_type() -> String:
	return current_target_type
