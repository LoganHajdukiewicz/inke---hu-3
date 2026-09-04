extends Node3D
class_name SwingRope

## A hanging rope. Jump into it to grab on:
##  - swings like a grapple swing point (pendulum from the anchor)
##  - but you can also CLIMB up and down the rope while hanging
##  - jump to launch off, crouch to let go
## Place the node at the anchor (top); the rope hangs straight down.

@export var rope_length: float = 8.0:
	set(value):
		rope_length = value
		if is_inside_tree():
			_rebuild()
@export var rope_color: Color = Color(0.72, 0.55, 0.3)
@export var rope_thickness: float = 0.07
@export var min_grab_distance: float = 1.2   # Can't climb higher than this from the anchor
@export var regrab_delay: float = 0.4        # After letting go, before you can regrab

var rope_visual: MeshInstance3D = null
var rope_material: StandardMaterial3D = null
var grab_area: Area3D = null
var attached_player: CharacterBody3D = null

func _ready():
	add_to_group("Rope")
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	# Anchor knob
	var knob = MeshInstance3D.new()
	var knob_mesh = SphereMesh.new()
	knob_mesh.radius = 0.16
	knob_mesh.height = 0.32
	knob.mesh = knob_mesh
	var knob_mat = StandardMaterial3D.new()
	knob_mat.albedo_color = rope_color.darkened(0.35)
	knob.material_override = knob_mat
	add_child(knob)
	
	# Rope visual: single thin cylinder from anchor straight down (idle pose).
	# While a player swings, _process redraws it to the player.
	rope_visual = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = rope_thickness
	cyl.bottom_radius = rope_thickness
	cyl.height = 1.0  # scaled at runtime
	rope_visual.mesh = cyl
	rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = rope_color
	rope_material.roughness = 1.0
	rope_visual.material_override = rope_material
	add_child(rope_visual)
	_draw_rope_to(global_position + Vector3.DOWN * rope_length)
	
	# Grab detection along the rope's hanging line
	grab_area = Area3D.new()
	grab_area.monitoring = true
	var col = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.65
	capsule.height = rope_length
	col.shape = capsule
	col.position = Vector3(0, -rope_length * 0.5, 0)
	grab_area.add_child(col)
	add_child(grab_area)
	grab_area.body_entered.connect(_on_body_entered)

func _process(_delta):
	if attached_player and is_instance_valid(attached_player):
		_draw_rope_to(attached_player.global_position + Vector3(0, 1.2, 0))
	else:
		attached_player = null
		_draw_rope_to(global_position + Vector3.DOWN * rope_length)
		# body_entered only fires on ENTRY - someone already standing inside
		# the grab zone (ground grabs!) would never trigger it. Poll while
		# unoccupied so standing at a rope grabs it too.
		if grab_area and grab_area.monitoring:
			for b in grab_area.get_overlapping_bodies():
				if b.is_in_group("Player"):
					_on_body_entered(b)
					break

func _draw_rope_to(world_point: Vector3):
	if not rope_visual or not is_inside_tree():
		return
	var from = global_position
	var length = from.distance_to(world_point)
	if length < 0.05:
		rope_visual.visible = false
		return
	rope_visual.visible = true
	rope_visual.top_level = true
	rope_visual.global_position = (from + world_point) * 0.5
	# Cylinder's long axis is Y: build a basis whose Y points along the rope
	var y_axis = (world_point - from).normalized()
	var ref = Vector3.RIGHT if abs(y_axis.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis = ref.cross(y_axis).normalized()
	var z_axis = x_axis.cross(y_axis).normalized()
	rope_visual.global_basis = Basis(x_axis, y_axis, z_axis)
	rope_visual.scale = Vector3(1, length, 1)

func _on_body_entered(body: Node3D):
	if attached_player:
		return
	if not body.is_in_group("Player"):
		return
	if body.get("is_dead") == true or body.get("controls_disabled") == true:
		return
	# Regrab cooldown after release
	if body.has_meta("rope_regrab_until") and Time.get_ticks_msec() < body.get_meta("rope_regrab_until"):
		return
	
	var sm = body.get_node_or_null("StateMachine")
	if not sm:
		return
	var state_name = sm.current_state.get_script().get_global_name() if sm.current_state else ""
	var grounded: bool = body.is_on_floor()
	if grounded:
		# GROUND GRAB: walking into a rope grabs it too - hop the player up a
		# touch first so the swing starts clean instead of dragging the floor.
		if not state_name in ["IdleState", "WalkingState", "RunningState"]:
			return
		body.global_position.y += 0.6
		body.velocity.y = maxf(body.velocity.y, 2.5)
	elif not state_name in ["JumpingState", "FallingState", "DoubleJumpState", "WallJumpingState", "GrappleHookState"]:
		return
	
	var rope_state = sm.states.get("ropeswingstate")
	if rope_state:
		rope_state.setup(self)
		sm.change_state("RopeSwingState")

func set_attached(p: CharacterBody3D):
	attached_player = p

func clear_attached(p: CharacterBody3D):
	if attached_player == p:
		attached_player = null
	if p:
		p.set_meta("rope_regrab_until", Time.get_ticks_msec() + int(regrab_delay * 1000))
