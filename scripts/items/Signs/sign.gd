@tool
extends StaticBody3D

## STREET SIGN - punk make-over. A battered metal street sign: galvanized
## pole, tilted panel with a spray-painted face, drips and slap stickers.
## The model is built in code (tweak the exports, it rebuilds live in the
## editor). Interaction is still handled by a DialogueTrigger child - add
## one and set its dialogue_file, or use the helpers below.

@export var panel_color: Color = Color(0.09, 0.08, 0.11):
	set(v):
		panel_color = v
		_rebuild()
@export var tag_color: Color = Color(1.0, 0.18, 0.53):
	set(v):
		tag_color = v
		_rebuild()
@export var panel_tilt_degrees: float = 6.0:
	set(v):
		panel_tilt_degrees = v
		_rebuild()
@export var pole_height: float = 1.9:
	set(v):
		pole_height = maxf(v, 0.5)
		_rebuild()

var _model: Node3D

func _ready():
	_rebuild()

func _rebuild():
	if not is_inside_tree():
		return
	if _model and is_instance_valid(_model):
		_model.free()
	# Hide any leftover meshes from older versions of the scene
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	
	_model = Node3D.new()
	_model.name = "SignModel"
	add_child(_model)
	
	# ── Pole: galvanized steel, slightly bent (been hit by a truck) ──────
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.6)
	steel.metallic = 0.8
	steel.roughness = 0.55
	
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.045
	pole_mesh.height = pole_height
	pole.mesh = pole_mesh
	pole.material_override = steel
	pole.position.y = pole_height * 0.5
	pole.rotation_degrees.z = 2.0   # A little lean - nothing here is straight
	_model.add_child(pole)
	
	# Concrete foot
	var foot := MeshInstance3D.new()
	var foot_mesh := CylinderMesh.new()
	foot_mesh.top_radius = 0.09
	foot_mesh.bottom_radius = 0.13
	foot_mesh.height = 0.12
	foot.mesh = foot_mesh
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.42, 0.4, 0.38)
	concrete.roughness = 1.0
	foot.material_override = concrete
	foot.position.y = 0.06
	_model.add_child(foot)
	
	# ── Panel: dark plate, tilted like it's half torn off ────────────────
	var panel_pivot := Node3D.new()
	panel_pivot.position = Vector3(0.03, pole_height - 0.05, 0)
	panel_pivot.rotation_degrees.z = panel_tilt_degrees
	_model.add_child(panel_pivot)
	
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = panel_color
	panel_mat.roughness = 0.7
	panel_mat.metallic = 0.25
	
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.06, 0.72, 1.05)
	panel.mesh = panel_mesh
	panel.material_override = panel_mat
	panel_pivot.add_child(panel)
	
	# Neon spray border on the face (emissive frame)
	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = tag_color
	border_mat.emission_enabled = true
	border_mat.emission = tag_color
	border_mat.emission_energy_multiplier = 0.9
	border_mat.roughness = 0.9
	for off in [Vector3(0.035, 0.31, 0), Vector3(0.035, -0.31, 0)]:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.012, 0.05, 0.95)
		stripe.mesh = sm
		stripe.material_override = border_mat
		stripe.position = off
		stripe.rotation_degrees.x = randf_range(-2.0, 2.0)
		panel_pivot.add_child(stripe)
	
	# Spray-paint drips under the bottom stripe
	for i in range(4):
		var drip := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.012
		dm.bottom_radius = 0.006
		dm.height = randf_range(0.06, 0.16)
		drip.mesh = dm
		drip.material_override = border_mat
		drip.position = Vector3(0.035, -0.36 - dm.height * 0.5, randf_range(-0.4, 0.4))
		panel_pivot.add_child(drip)
	
	# Slap stickers (little bright quads at random angles)
	var sticker_colors := [PunkTheme.CYAN, PunkTheme.YELLOW, PunkTheme.GREEN]
	for i in range(3):
		var stick := MeshInstance3D.new()
		var stm := BoxMesh.new()
		stm.size = Vector3(0.012, randf_range(0.08, 0.14), randf_range(0.1, 0.18))
		stick.mesh = stm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = sticker_colors[i % sticker_colors.size()]
		smat.roughness = 0.6
		stick.material_override = smat
		stick.position = Vector3(0.036, randf_range(-0.2, 0.2), randf_range(-0.42, 0.42))
		stick.rotation_degrees.x = randf_range(-25.0, 25.0)
		panel_pivot.add_child(stick)
	
	# A couple of rivets holding the panel to the pole
	for ry in [0.18, -0.18]:
		var rivet := MeshInstance3D.new()
		var rm := SphereMesh.new()
		rm.radius = 0.02
		rm.height = 0.04
		rivet.mesh = rm
		rivet.material_override = steel
		rivet.position = Vector3(-0.04, ry, 0)
		panel_pivot.add_child(rivet)

# Helpers to configure the child DialogueTrigger from the sign

func set_dialogue_file(dialogue_name: String):
	var dialogue_trigger = get_node_or_null("DialogueTrigger")
	if dialogue_trigger:
		dialogue_trigger.dialogue_file = dialogue_name

func set_trigger_type(type: int):
	var dialogue_trigger = get_node_or_null("DialogueTrigger")
	if dialogue_trigger:
		dialogue_trigger.trigger_type = type
