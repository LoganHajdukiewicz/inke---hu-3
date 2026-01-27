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

# Signals for other systems to respond to paint changes
signal paint_changed(new_paint: PaintType, previous_paint: PaintType)
signal paint_used(paint_type: PaintType)

func _ready():
	player = get_parent() as CharacterBody3D
	setup_paint_indicator()
	update_paint_indicator()
	print("Paint Manager initialized - Current paint: ", paint_names[current_paint])

func setup_paint_indicator():
	"""Create a visual indicator showing current paint type"""
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
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	var base_y = 2.5
	tween.tween_property(paint_indicator, "position:y", base_y + 0.2, 1.0)
	tween.tween_property(paint_indicator, "position:y", base_y - 0.2, 1.0)

func _process(delta: float):
	# Update cooldown
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
	if not paint_indicator:
		return
	
	var material = paint_indicator.material_override as StandardMaterial3D
	if material:
		var color = paint_colors[current_paint]
		material.albedo_color = color
		material.emission = color
		
		# Pulse effect on switch
		var tween = create_tween()
		tween.tween_property(material, "emission_energy_multiplier", 4.0, 0.1)
		tween.tween_property(material, "emission_energy_multiplier", 2.0, 0.3)

func play_switch_effect():
	"""Visual effect when switching paints"""
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

func play_use_effect():
	"""Visual effect when using paint"""
	if paint_indicator:
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
	print("Heal Paint: Healing player...")
	# TODO: Implement healing logic
	# if player.has_method("heal"):
	#     player.heal(1)

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

# ==========================================
# SETTERS (for external control if needed)
# ==========================================

func set_paint(paint_type: PaintType):
	"""Directly set the paint type (bypasses cooldown)"""
	if paint_type != current_paint:
		switch_paint(paint_type)
