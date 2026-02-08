extends Node

# Paint types enum
enum PaintType {
	SAVE,    # D-pad Up
	HEAL,    # D-pad Down
	FLY,     # D-pad Left
	COMBAT   # D-pad Right
}

# Current selected paint
var current_paint: PaintType = PaintType.HEAL
var previous_paint: PaintType = PaintType.HEAL

# Paint meter system
var current_paint_amount: int = 100  # Start with full paint
var max_paint_amount: int = 100

# Paint ability costs (in paint units)
var paint_ability_costs: Dictionary = {
	PaintType.SAVE: 20,
	PaintType.HEAL: 20,
	PaintType.FLY: 20,
	PaintType.COMBAT: 10  # Combat is cheaper since it's used more often
}

# Signals for paint meter
signal paint_amount_changed(current: int, maximum: int)
signal paint_collected(amount: int)
signal paint_depleted  # When paint runs out
signal insufficient_paint(cost: int, current: int)  # When trying to use without enough paint

# Paint colors for visual feedback
var paint_colors: Dictionary = {
	PaintType.SAVE: Color(0.0, 0.8, 1.0),      # Cyan
	PaintType.HEAL: Color(0.0, 1.0, 0.0),      # Green
	PaintType.FLY: Color(1.0, 0.8, 0.0),       # Gold/Yellow
	PaintType.COMBAT: Color(1.0, 0.2, 0.0)     # Red/Orange
}

# Paint names for UI/debug
var paint_names: Dictionary = {
	PaintType.SAVE: "Save Paint",
	PaintType.HEAL: "Heal Paint",
	PaintType.FLY: "Fly Paint",
	PaintType.COMBAT: "Combat Paint"
}

# References
var player: CharacterBody3D
var paint_ui: CanvasLayer  # UI-based paint meter

# Cooldown to prevent rapid switching
var switch_cooldown: float = 0.0
var switch_cooldown_time: float = 0.2

# Signals for other systems to respond to paint changes
signal paint_changed(new_paint: PaintType, previous_paint: PaintType)
signal paint_used(paint_type: PaintType)

# Initialization flag
var is_initialized: bool = false

func _ready():
	# PaintManager is autoloaded, so it doesn't have a parent
	# Wait for player to register itself
	print("PaintManager ready - waiting for player registration")

func register_player(player_node: CharacterBody3D):
	"""Called by player to register itself with PaintManager"""
	player = player_node
	setup_paint_ui()
	is_initialized = true
	print("Paint Manager initialized - Current paint: ", paint_names[current_paint])
	print("Starting paint amount: ", current_paint_amount, "/", max_paint_amount)

# ==========================================
# PAINT METER FUNCTIONS
# ==========================================

func add_paint(amount: int):
	"""Add paint to the meter from collecting droplets"""
	var old_amount = current_paint_amount
	current_paint_amount = min(current_paint_amount + amount, max_paint_amount)
	
	print("Paint collected! +", amount, " (", old_amount, " -> ", current_paint_amount, ")")
	
	paint_collected.emit(amount)
	paint_amount_changed.emit(current_paint_amount, max_paint_amount)

func consume_paint(amount: int) -> bool:
	"""Try to consume paint. Returns true if successful, false if not enough paint"""
	if current_paint_amount >= amount:
		current_paint_amount -= amount
		paint_amount_changed.emit(current_paint_amount, max_paint_amount)
		
		if current_paint_amount == 0:
			paint_depleted.emit()
		
		print("Paint consumed: -", amount, " (", current_paint_amount, "/", max_paint_amount, " remaining)")
		return true
	else:
		print("Not enough paint! Need ", amount, ", have ", current_paint_amount)
		insufficient_paint.emit(amount, current_paint_amount)
		return false

func get_paint_amount() -> int:
	"""Get current paint amount"""
	return current_paint_amount

func get_max_paint_amount() -> int:
	"""Get maximum paint amount"""
	return max_paint_amount

func get_paint_percentage() -> float:
	"""Get paint amount as percentage (0.0 to 1.0)"""
	return float(current_paint_amount) / float(max_paint_amount)

func has_enough_paint_for_ability(paint_type: PaintType) -> bool:
	"""Check if player has enough paint to use the specified ability"""
	var cost = paint_ability_costs.get(paint_type, 0)
	return current_paint_amount >= cost

func get_ability_cost(paint_type: PaintType) -> int:
	"""Get the paint cost for a specific ability"""
	return paint_ability_costs.get(paint_type, 0)

# ==========================================
# UI SETUP
# ==========================================

func setup_paint_ui():
	"""Create the UI-based paint meter"""
	if not player or not is_instance_valid(player):
		print("PaintManager: Cannot setup UI - invalid player reference")
		return
	
	# Load the PaintUIManager script
	var paint_ui_script = load("res://scripts/ui/paint_ui_manager.gd")
	if not paint_ui_script:
		print("PaintManager: ERROR - Could not load paint_ui_manager.gd!")
		return
	
	# Create the UI instance
	paint_ui = paint_ui_script.new()
	paint_ui.name = "PaintUI"
	
	# Add to scene tree
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(paint_ui)
		print("Paint UI created successfully!")
	else:
		print("PaintManager: Could not add paint UI - no current scene found")

# ==========================================
# EXISTING PAINT SYSTEM FUNCTIONS
# ==========================================

func _process(delta: float):
	# Don't process if not initialized
	if not is_initialized or not player:
		return
	
	# Check if player is still valid - if not, reset
	if not is_instance_valid(player):
		print("PaintManager: Player no longer valid, resetting...")
		cleanup()
		return
	
	# Update switch cooldown
	if switch_cooldown > 0:
		switch_cooldown -= delta
	
	# Check for paint switching input
	check_paint_switch_input()
	
	# Check for paint usage
	check_paint_use_input()

func check_paint_switch_input():
	"""Check D-pad input for paint switching"""
	if switch_cooldown > 0:
		return
	
	var new_paint: PaintType = current_paint
	var switched = false
	
	# D-pad Up = Save Paint
	if Input.is_action_just_pressed("d_pad_up"):
		new_paint = PaintType.SAVE
		switched = true
	
	# D-pad Down = Heal Paint
	elif Input.is_action_just_pressed("d_pad_down"):
		new_paint = PaintType.HEAL
		switched = true
	
	# D-pad Left = Fly Paint
	elif Input.is_action_just_pressed("d_pad_left"):
		new_paint = PaintType.FLY
		switched = true
	
	# D-pad Right = Combat Paint
	elif Input.is_action_just_pressed("d_pad_right"):
		new_paint = PaintType.COMBAT
		switched = true
	
	# If we switched to a different paint
	if switched and new_paint != current_paint:
		switch_paint(new_paint)

func switch_paint(new_paint: PaintType):
	"""Switch to a new paint type"""
	previous_paint = current_paint
	current_paint = new_paint
	
	# Start cooldown
	switch_cooldown = switch_cooldown_time
	
	# Emit signal
	paint_changed.emit(current_paint, previous_paint)
	
	# Print feedback
	var cost = paint_ability_costs.get(current_paint, 0)
	print("Paint switched: ", paint_names[previous_paint], " → ", paint_names[current_paint], " (Cost: ", cost, " paint)")

func check_paint_use_input():
	"""Check for spray button press to use current paint"""
	if Input.is_action_just_pressed("spray"):
		use_current_paint()

func use_current_paint():
	"""Execute the action for the current paint type"""
	var cost = paint_ability_costs.get(current_paint, 0)
	
	# Check if we have enough paint
	if not has_enough_paint_for_ability(current_paint):
		print("Not enough paint! Need ", cost, ", have ", current_paint_amount)
		return
	
	print("Using ", paint_names[current_paint], " (Cost: ", cost, " paint)")
	
	# Consume the paint BEFORE executing the ability
	if not consume_paint(cost):
		return
	
	# Emit signal for other systems to handle
	paint_used.emit(current_paint)
	
	# Execute paint-specific logic
	match current_paint:
		PaintType.SAVE:
			execute_save_paint()
		PaintType.HEAL:
			execute_heal_paint()
		PaintType.FLY:
			execute_fly_paint()
		PaintType.COMBAT:
			execute_combat_paint()

# ==========================================
# PAINT ACTION METHODS
# ==========================================

func execute_save_paint():
	"""Save paint functionality - saves checkpoint"""
	if not player or not is_instance_valid(player):
		print("Save Paint: No valid player reference")
		return
	
	# Check if player is on the floor
	if not player.is_on_floor():
		print("Save Paint: Must be on the ground to create checkpoint!")
		# Refund the paint since we couldn't use it
		add_paint(paint_ability_costs[PaintType.SAVE])
		return
	
	# Check if player has zero velocity (not moving)
	var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z)
	if horizontal_velocity.length() > 0.5:  # Small threshold for "standing still"
		print("Save Paint: Must be standing still to create checkpoint!")
		# Refund the paint since we couldn't use it
		add_paint(paint_ability_costs[PaintType.SAVE])
		return
	
	# All conditions met - create checkpoint!
	var checkpoint_manager = get_node_or_null("/root/CheckpointManager")
	if checkpoint_manager:
		var checkpoint_pos = player.global_position
		var checkpoint_rot = player.rotation
		
		checkpoint_manager.set_checkpoint(checkpoint_pos, checkpoint_rot)
		print("Save Paint: Checkpoint created at ", checkpoint_pos)
		
		# Create visual feedback for checkpoint creation
		create_checkpoint_effect()
	else:
		print("Save Paint: CheckpointManager not found!")
		# Refund the paint since we couldn't use it
		add_paint(paint_ability_costs[PaintType.SAVE])

func create_checkpoint_effect():
	"""Create visual feedback for checkpoint creation"""
	if not player or not is_instance_valid(player):
		return
	
	# Create a temporary checkpoint glow effect
	var checkpoint_glow = MeshInstance3D.new()
	checkpoint_glow.name = "CheckpointGlow"
	
	# Create cylinder mesh for ground marker
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 1.5
	cylinder_mesh.bottom_radius = 1.5
	cylinder_mesh.height = 0.1
	checkpoint_glow.mesh = cylinder_mesh
	
	# Create glowing cyan material (save paint color)
	var glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.0, 0.8, 1.0, 0.6)  # Cyan with transparency
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.0, 0.8, 1.0, 1.0)
	glow_material.emission_energy_multiplier = 3.0
	
	checkpoint_glow.material_override = glow_material
	checkpoint_glow.position = Vector3(0, 0.05, 0)  # Slightly above ground
	
	# Add to player
	player.add_child(checkpoint_glow)
	
	# Animate the glow - pulse and expand
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Pulse scale
	tween.tween_property(checkpoint_glow, "scale", Vector3(1.5, 1.0, 1.5), 0.3)
	tween.tween_property(checkpoint_glow, "scale", Vector3(2.0, 1.0, 2.0), 0.4).set_delay(0.3)
	
	# Fade out
	tween.tween_property(glow_material, "albedo_color:a", 0.0, 0.7)
	
	# Clean up after animation
	tween.finished.connect(func(): 
		if is_instance_valid(checkpoint_glow):
			checkpoint_glow.queue_free()
	)

func execute_heal_paint():
	"""Heal paint functionality - restores health"""
	if not player or not is_instance_valid(player):
		print("Heal Paint: No valid player reference")
		return
	
	# Check if player can be healed (not at max health)
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		var current_health = game_manager.get_player_health()
		var max_health = game_manager.get_player_max_health()
		
		if current_health >= max_health:
			print("Heal Paint: Already at max health!")
			# Refund the paint since we couldn't use it
			add_paint(paint_ability_costs[PaintType.HEAL])
			return
	
	# Heal the player
	if player.has_method("heal"):
		player.heal(1)
		print("Heal Paint: Healed player for 1 HP")
		
		# Create healing visual effect
		create_heal_effect()
	else:
		print("Heal Paint: Player doesn't have heal method")

func create_heal_effect():
	"""Create visual feedback for healing"""
	if not player or not is_instance_valid(player):
		return
	
	# Create a temporary healing glow effect
	var heal_glow = MeshInstance3D.new()
	heal_glow.name = "HealGlow"
	
	# Create sphere mesh for glow
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.5
	sphere_mesh.height = 3.0
	heal_glow.mesh = sphere_mesh
	
	# Create glowing green material
	var glow_material = StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.0, 1.0, 0.0, 0.5)
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.0, 1.0, 0.0, 1.0)
	glow_material.emission_energy_multiplier = 3.0
	
	heal_glow.material_override = glow_material
	heal_glow.position = Vector3(0, 1.0, 0)
	
	# Add to player
	player.add_child(heal_glow)
	
	# Animate the glow - expand and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Scale up
	tween.tween_property(heal_glow, "scale", Vector3(2.0, 2.0, 2.0), 0.5)
	
	# Fade out
	tween.tween_property(glow_material, "albedo_color:a", 0.0, 0.5)
	
	# Move up slightly
	tween.tween_property(heal_glow, "position:y", 2.0, 0.5)
	
	# Clean up after animation
	tween.finished.connect(func(): 
		if is_instance_valid(heal_glow):
			heal_glow.queue_free()
	)

func execute_fly_paint():
	"""Fly paint functionality - temporary flight/glide"""
	print("Fly Paint: Activating flight...")
	# TODO: Implement flight logic

func execute_combat_paint():
	"""Combat paint functionality - offensive spray"""
	print("Combat Paint: Attacking...")
	# TODO: Implement combat spray logic

# ==========================================
# GETTERS
# ==========================================

func get_current_paint() -> PaintType:
	"""Get the currently selected paint type"""
	return current_paint

func get_current_paint_name() -> String:
	"""Get the name of the current paint"""
	return paint_names[current_paint]

func get_current_paint_color() -> Color:
	"""Get the color of the current paint"""
	return paint_colors[current_paint]

func get_current_paint_cost() -> int:
	"""Get the cost of the current paint ability"""
	return paint_ability_costs.get(current_paint, 0)

func is_paint_type(paint_type: PaintType) -> bool:
	"""Check if current paint matches the given type"""
	return current_paint == paint_type

# ==========================================
# SETTERS (for external control if needed)
# ==========================================

func set_paint(paint_type: PaintType):
	"""Directly set the paint type (bypasses cooldown)"""
	if paint_type != current_paint:
		switch_paint(paint_type)

func cleanup():
	"""Clean up resources when player is no longer valid"""
	if paint_ui and is_instance_valid(paint_ui):
		paint_ui.queue_free()
	
	paint_ui = null
	player = null
	is_initialized = false
	print("PaintManager: Cleaned up resources")
