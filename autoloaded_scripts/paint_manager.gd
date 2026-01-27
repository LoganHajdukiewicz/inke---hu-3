extends Node

# Paint types enum
enum PaintType {
	SAVE,    # D-pad Up
	HEAL,    # D-pad Down
	FLY,     # D-pad Left
	COMBAT   # D-pad Right
}

# Current selected paint
var current_paint: PaintType = PaintType.SAVE
var previous_paint: PaintType = PaintType.SAVE

# Paint meter system
var current_paint_amount: int = 100  # Start with full paint
var max_paint_amount: int = 100
var paint_per_use: int = 20  # How much paint each spray costs

# Signals for paint meter
signal paint_amount_changed(current: int, maximum: int)
signal paint_collected(amount: int)
signal paint_depleted  # When paint runs out

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
var paint_indicator: MeshInstance3D  # Visual indicator on player

# Cooldown to prevent rapid switching
var switch_cooldown: float = 0.0
var switch_cooldown_time: float = 0.2

# Paint ability cooldowns
var paint_ability_cooldowns: Dictionary = {
	PaintType.SAVE: 0.0,
	PaintType.HEAL: 0.0,
	PaintType.FLY: 0.0,
	PaintType.COMBAT: 0.0
}

var paint_ability_cooldown_times: Dictionary = {
	PaintType.SAVE: 2.0,    # 2 second cooldown for save
	PaintType.HEAL: 5.0,    # 5 second cooldown for heal
	PaintType.FLY: 3.0,     # 3 second cooldown for fly
	PaintType.COMBAT: 1.0   # 1 second cooldown for combat
}

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
	# Clean up old references if they exist
	if is_initialized and paint_indicator and is_instance_valid(paint_indicator):
		print("PaintManager: Cleaning up old paint indicator")
		paint_indicator.queue_free()
		paint_indicator = null
	
	player = player_node
	setup_paint_indicator()
	update_paint_indicator()
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
		
		return true
	else:
		print("Not enough paint! Need ", amount, ", have ", current_paint_amount)
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

func has_enough_paint_for_use() -> bool:
	"""Check if player has enough paint to use ability"""
	return current_paint_amount >= paint_per_use

# ==========================================
# EXISTING PAINT SYSTEM FUNCTIONS
# ==========================================

func setup_paint_indicator():
	"""Create a visual indicator showing current paint type"""
	if not player or not is_instance_valid(player):
		print("PaintManager: Cannot setup indicator - invalid player reference")
		return
	
	paint_indicator = MeshInstance3D.new()
	paint_indicator.name = "PaintIndicator"
	
	# Create a small sphere that floats above the player
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	paint_indicator.mesh = sphere_mesh
	
	# Create glowing material
	var indicator_material = StandardMaterial3D.new()
	indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator_material.albedo_color = paint_colors[current_paint]
	indicator_material.emission_enabled = true
	indicator_material.emission = paint_colors[current_paint]
	indicator_material.emission_energy_multiplier = 2.0
	
	paint_indicator.material_override = indicator_material
	
	# Position above player's head
	paint_indicator.position = Vector3(0, 2.5, 0)
	
	player.add_child(paint_indicator)
	
	# Add gentle bobbing animation
	create_bobbing_animation()

func create_bobbing_animation():
	"""Create a gentle floating animation for the paint indicator"""
	if not paint_indicator or not is_instance_valid(paint_indicator):
		return
	
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	var base_y = 2.5
	tween.tween_property(paint_indicator, "position:y", base_y + 0.2, 1.0)
	tween.tween_property(paint_indicator, "position:y", base_y - 0.2, 1.0)

func _process(delta: float):
	# Check if player is still valid - if not, reset
	if is_initialized and (not player or not is_instance_valid(player)):
		print("PaintManager: Player no longer valid, resetting...")
		cleanup()
		return
	
	# Don't process if not initialized
	if not is_initialized or not player:
		return
	
	# Update switch cooldown
	if switch_cooldown > 0:
		switch_cooldown -= delta
	
	# Update paint ability cooldowns
	for paint_type in paint_ability_cooldowns.keys():
		if paint_ability_cooldowns[paint_type] > 0:
			paint_ability_cooldowns[paint_type] -= delta
			
			# Update indicator if this is the current paint
			if paint_type == current_paint:
				update_cooldown_visual()
	
	# Check for paint switching input
	check_paint_switch_input()
	
	# Check for paint usage
	check_paint_use_input()

func update_cooldown_visual():
	"""Update the visual state of paint indicator based on cooldown"""
	if not paint_indicator or not is_instance_valid(paint_indicator):
		return
	
	var material = paint_indicator.material_override as StandardMaterial3D
	if not material:
		return
	
	var cooldown_remaining = paint_ability_cooldowns[current_paint]
	
	if cooldown_remaining > 0:
		# On cooldown - darker and dim
		var color = paint_colors[current_paint].darkened(0.5)
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 0.5
	else:
		# Ready - bright and glowing
		var color = paint_colors[current_paint]
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 2.0

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
	
	# Update visual indicator
	update_paint_indicator()
	
	# Emit signal
	paint_changed.emit(current_paint, previous_paint)
	
	# Print feedback
	print("Paint switched: ", paint_names[previous_paint], " → ", paint_names[current_paint])
	
	# Visual/audio feedback
	play_switch_effect()

func update_paint_indicator():
	"""Update the paint indicator color and emission"""
	if not paint_indicator or not is_instance_valid(paint_indicator):
		return
	
	var material = paint_indicator.material_override as StandardMaterial3D
	if material:
		var color = paint_colors[current_paint]
		
		# Check if current paint is on cooldown
		if paint_ability_cooldowns[current_paint] > 0:
			# Darken color and reduce emission when on cooldown
			color = color.darkened(0.5)
			material.albedo_color = color
			material.emission = color
			material.emission_energy_multiplier = 0.5
		else:
			# Normal bright color when ready
		material.albedo_color = color
		material.emission = color
			material.emission_energy_multiplier = 2.0
		
		# Pulse effect on switch
		var tween = create_tween()
		tween.tween_property(material, "emission_energy_multiplier", 4.0, 0.1)
		tween.tween_property(material, "emission_energy_multiplier", 2.0, 0.3)

func play_switch_effect():
	"""Visual effect when switching paints"""
	if not paint_indicator or not is_instance_valid(paint_indicator):
		return
	
	# Scale pulse
	if paint_indicator:
		var original_scale = paint_indicator.scale
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(paint_indicator, "scale", original_scale * 1.5, 0.15)
		tween.tween_property(paint_indicator, "scale", original_scale, 0.15)
	
	# TODO: Add sound effect here when you have audio
	# $SwitchSound.play()

func check_paint_use_input():
	"""Check for spray button press to use current paint"""
	if Input.is_action_just_pressed("spray"):
		use_current_paint()

func use_current_paint():
	"""Execute the action for the current paint type"""
	# Check if paint is on cooldown
	if paint_ability_cooldowns[current_paint] > 0:
		print("Paint on cooldown! Wait ", paint_ability_cooldowns[current_paint], " seconds")
		# Visual feedback for cooldown
		if paint_indicator and is_instance_valid(paint_indicator):
			var material = paint_indicator.material_override as StandardMaterial3D
			if material:
				# Quick red flash to indicate cooldown
				var tween = create_tween()
				var original_color = material.albedo_color
				tween.tween_property(material, "albedo_color", Color(1.0, 0.0, 0.0, 1.0), 0.1)
				tween.tween_property(material, "albedo_color", original_color, 0.2)
		return
	
	print("Using ", paint_names[current_paint])
	
	# Emit signal for other systems to handle
	paint_used.emit(current_paint)
	
	# Visual feedback
	play_use_effect()
	
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
	
	# Start cooldown for this paint type
	paint_ability_cooldowns[current_paint] = paint_ability_cooldown_times[current_paint]

func play_use_effect():
	"""Visual effect when using paint"""
	if not paint_indicator or not is_instance_valid(paint_indicator):
		return
	
		# Quick flash
		var material = paint_indicator.material_override as StandardMaterial3D
		if material:
			var tween = create_tween()
			tween.tween_property(material, "emission_energy_multiplier", 6.0, 0.05)
			tween.tween_property(material, "emission_energy_multiplier", 2.0, 0.2)
	
	# TODO: Add particle effect for paint spray
	# TODO: Add sound effect

# ==========================================
# PAINT ACTION METHODS (Placeholders)
# ==========================================

func execute_save_paint():
	"""Save paint functionality - saves checkpoint"""
	print("Save Paint: Creating checkpoint...")
	# TODO: Implement save/checkpoint logic
	# This will trigger checkpoint creation at player's current position

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
	
	# Make paint indicator pulse
	if paint_indicator and is_instance_valid(paint_indicator):
		var indicator_material = paint_indicator.material_override as StandardMaterial3D
		if indicator_material:
			var pulse_tween = create_tween()
			pulse_tween.tween_property(indicator_material, "emission_energy_multiplier", 8.0, 0.1)
			pulse_tween.tween_property(indicator_material, "emission_energy_multiplier", 2.0, 0.4)

func execute_fly_paint():
	"""Fly paint functionality - temporary flight/glide"""
	print("Fly Paint: Activating flight...")
	# TODO: Implement flight logic
	# This could give the player a temporary upward boost or glide ability

func execute_combat_paint():
	"""Combat paint functionality - offensive spray"""
	print("Combat Paint: Attacking...")
	# TODO: Implement combat spray logic
	# This could create a damaging spray cone in front of the player

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

func is_paint_type(paint_type: PaintType) -> bool:
	"""Check if current paint matches the given type"""
	return current_paint == paint_type

func is_paint_on_cooldown(paint_type: PaintType) -> bool:
	"""Check if a specific paint type is on cooldown"""
	return paint_ability_cooldowns.get(paint_type, 0.0) > 0

func get_paint_cooldown(paint_type: PaintType) -> float:
	"""Get the remaining cooldown time for a specific paint type"""
	return paint_ability_cooldowns.get(paint_type, 0.0)

func get_current_paint_cooldown() -> float:
	"""Get the remaining cooldown time for the current paint"""
	return paint_ability_cooldowns.get(current_paint, 0.0)

# ==========================================
# SETTERS (for external control if needed)
# ==========================================

func set_paint(paint_type: PaintType):
	"""Directly set the paint type (bypasses cooldown)"""
	if paint_type != current_paint:
		switch_paint(paint_type)

func cleanup():
	"""Clean up resources when player is no longer valid"""
	if paint_indicator and is_instance_valid(paint_indicator):
		paint_indicator.queue_free()
	
	paint_indicator = null
	player = null
	is_initialized = false
	print("PaintManager: Cleaned up resources")
