extends Node

# Game Resources
var gear_count: int = 0
var CRED: int = 0

# Health Stats
var player_health: int = 3
var player_max_health: int = 3

# Upgrade System
@export_group("Upgrades Purchased")
@export var double_jump_purchased: bool = false
@export var wall_jump_purchased: bool = false
@export var dash_purchased: bool = false
@export var speed_upgrade_purchased: bool = false
@export var health_upgrade_purchased: bool = false
@export var damage_upgrade_purchased: bool = false

# Upgrade Costs
@export_group("Upgrade Costs")
@export var double_jump_cost: int = 50
@export var wall_jump_cost: int = 50
@export var dash_cost: int = 50
@export var speed_upgrade_cost: int = 50
@export var health_upgrade_cost: int = 50
@export var damage_upgrade_cost: int = 50

# Player Reference
var player: CharacterBody3D = null
var hu3_companion: CharacterBody3D = null

# HU-3 Companion Scene
var hu3_scene = preload("res://scenes/characters/Player/HU-3.tscn")

# Signals
signal gear_collected(total_gears: int)
signal cred_collected(amount: int, total_cred: int)
signal upgrade_purchased(upgrade_type: String)
signal health_changed(new_health: int, max_health: int)
signal player_spawned(player: CharacterBody3D)
signal hu3_spawned(hu3: CharacterBody3D)

func _ready():
	find_player()
	
	if player and player.has_method("get_hu3_companion"):
		hu3_companion = player.get_hu3_companion()
	
	apply_purchased_upgrades()

func find_player():
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
		player_spawned.emit(player)
	else:
		print("GameManager: No player found in scene!")

# === PLAYER INITIALIZATION ===

func initialize_player():
	"""Initialize player with current game state"""
	if not player:
		find_player()
		return
	
	apply_purchased_upgrades()
	
	if player.has_method("set_health"):
		player.set_health(player_health)
	
	if not hu3_companion:
		# FIXED: Defer HU-3 spawning to next frame to ensure player is in tree
		call_deferred("spawn_hu3_companion")

func apply_purchased_upgrades():
	"""Apply all purchased upgrades to the player"""
	if not player:
		return
	
	if double_jump_purchased and player.has_method("unlock_double_jump"):
		player.unlock_double_jump()
		print("GameManager: Applied double jump upgrade to player")
	
	if wall_jump_purchased and player.has_method("unlock_wall_jump"):
		player.unlock_wall_jump()
		print("GameManager: Applied wall jump upgrade to player")
	
	if dash_purchased and player.has_method("unlock_dash"):
		player.unlock_dash()
		print("GameManager: Applied dash upgrade to player")
	
	if speed_upgrade_purchased and player.has_method("unlock_speed_upgrade"):
		player.unlock_speed_upgrade()
		print("GameManager: Applied speed upgrade to player")
	
	if health_upgrade_purchased and player.has_method("unlock_health_upgrade"):
		player.unlock_health_upgrade()
		# Also increase max health
		player_max_health = 4
	
	if damage_upgrade_purchased and player.has_method("unlock_damage_upgrade"):
		player.unlock_damage_upgrade()

# === HU-3 COMPANION MANAGEMENT ===

func spawn_hu3_companion():
	"""Spawn HU-3 companion robot"""
	# FIXED: Add safety checks to ensure player is valid and in scene tree
	if not player or not is_instance_valid(player):
		print("GameManager: Cannot spawn HU-3 - invalid player reference")
		return
	
	if not player.is_inside_tree():
		print("GameManager: Cannot spawn HU-3 - player not in scene tree yet, deferring...")
		call_deferred("spawn_hu3_companion")
		return
	
	if hu3_companion and is_instance_valid(hu3_companion):
		print("GameManager: HU-3 already exists, skipping spawn")
		return
	
	if hu3_scene:
		hu3_companion = hu3_scene.instantiate()
		
		# FIXED: Wait one frame before accessing player's global_position
		await get_tree().process_frame
		
		if not player or not is_instance_valid(player) or not player.is_inside_tree():
			print("GameManager: Player became invalid during HU-3 spawn")
			if hu3_companion:
				hu3_companion.queue_free()
			hu3_companion = null
			return
		
		# Position HU-3 to the right and above player
		hu3_companion.global_position = player.global_position + Vector3(1.5, 1.5, 1.0)
		
		# Add to scene
		player.get_parent().add_child(hu3_companion)
		
		# Set up HU-3's reference to player
		if hu3_companion.has_method("set_player_reference"):
			hu3_companion.set_player_reference(player)
		
		hu3_spawned.emit(hu3_companion)
		print("GameManager: HU-3 spawned successfully")
	else:
		print("GameManager: Could not load HU-3 scene!")

func get_hu3_companion() -> CharacterBody3D:
	"""Get reference to HU-3 companion"""
	return hu3_companion

# === GEAR MANAGEMENT ===

func add_gear(amount: int = 1):
	"""Add gears to the player's collection - unified for all collectors"""
	gear_count += amount
	gear_collected.emit(gear_count)

func spend_gears(amount: int) -> bool:
	"""Spend gears if player has enough"""
	if gear_count >= amount:
		gear_count -= amount
		return true
	return false

func get_gear_count() -> int:
	return gear_count

# === CRED MANAGEMENT ===

func add_CRED(reward: int):
	"""Add XP/CRED to Inke"""
	CRED += reward
	cred_collected.emit(reward, CRED)
	
func get_CRED_count() -> int:
	return CRED

# === UPGRADE SYSTEM ===

func purchase_upgrade(upgrade_type: String) -> bool:
	"""Purchase an upgrade if player has enough gears"""
	var cost = get_upgrade_cost(upgrade_type)
	
	if cost == -1:
		print("GameManager: Invalid upgrade type: ", upgrade_type)
		return false
	
	if is_upgrade_purchased(upgrade_type):
		return false
	
	if not spend_gears(cost):
		return false
	
	# Set the upgrade as purchased
	match upgrade_type.to_lower():
		"double_jump":
			double_jump_purchased = true
			if player and player.has_method("unlock_double_jump"):
				player.unlock_double_jump()
		"wall_jump":
			wall_jump_purchased = true
			if player and player.has_method("unlock_wall_jump"):
				player.unlock_wall_jump()
		"dash":
			dash_purchased = true
			if player and player.has_method("unlock_dash"):
				player.unlock_dash()
		"speed_upgrade":
			speed_upgrade_purchased = true
			if player and player.has_method("unlock_speed_upgrade"):
				player.unlock_speed_upgrade()
		"health_upgrade":
			health_upgrade_purchased = true
			player_max_health = 4  # Upgrade max health
			# Set health to max when upgrading (also triggers signal)
			set_player_health(player_max_health)
			if player and player.has_method("unlock_health_upgrade"):
				player.unlock_health_upgrade()
		"damage_upgrade":
			damage_upgrade_purchased = true
			if player and player.has_method("unlock_damage_upgrade"):
				player.unlock_damage_upgrade()
	
	upgrade_purchased.emit(upgrade_type)
	return true

func is_upgrade_purchased(upgrade_type: String) -> bool:
	"""Check if an upgrade has been purchased"""
	match upgrade_type.to_lower():
		"double_jump":
			return double_jump_purchased
		"wall_jump":
			return wall_jump_purchased
		"dash":
			return dash_purchased
		"speed_upgrade":
			return speed_upgrade_purchased
		"health_upgrade":
			return health_upgrade_purchased
		"damage_upgrade":
			return damage_upgrade_purchased
		_:
			return false

func get_upgrade_cost(upgrade_type: String) -> int:
	"""Get the cost of an upgrade"""
	match upgrade_type.to_lower():
		"double_jump":
			return double_jump_cost
		"wall_jump":
			return wall_jump_cost
		"dash":
			return dash_cost
		"speed_upgrade":
			return speed_upgrade_cost
		"health_upgrade":
			return health_upgrade_cost
		"damage_upgrade":
			return damage_upgrade_cost
		_:
			return -1

func get_upgrade_description(upgrade_type: String) -> String:
	"""Get the description of an upgrade"""
	match upgrade_type.to_lower():
		"double_jump":
			return "Allows you to jump again while in mid-air"
		"wall_jump":
			return "Allows you to jump between close walls"
		"dash":
			return "Allows you to dash past your enemies"
		"speed_upgrade":
			return "Allows you to zoom around"
		"health_upgrade":
			return "Allows you to take a harder hit"
		"damage_upgrade":
			return "Allows you to hit those evil robots harder"
		_:
			return "Unknown upgrade"

func get_upgrade_name(upgrade_type: String) -> String:
	"""Get the display name of an upgrade"""
	match upgrade_type.to_lower():
		"double_jump":
			return "Double Jump Upgrade"
		"wall_jump":
			return "Wall Jump Upgrade"
		"dash":
			return "Dash"
		"speed_upgrade":
			return "Speed Upgrade"
		"health_upgrade":
			return "Health Upgrade"
		"damage_upgrade":
			return "Damage Upgrade"
		_:
			return "Unknown Upgrade"

# === HEALTH MANAGEMENT ===

func set_player_health(new_health: int):
	"""Set player's health"""
	player_health = clamp(new_health, 0, player_max_health)
	health_changed.emit(player_health, player_max_health)
	
	if player and player.has_method("set_health"):
		player.set_health(player_health)

func damage_player(amount: int):
	"""Deal damage to player"""
	set_player_health(player_health - amount)
	print("Player took ", amount, " damage. Health: ", player_health, "/", player_max_health)

func heal_player(amount: int):
	"""Heal the player"""
	set_player_health(player_health + amount)
	print("Player healed ", amount, " health. Health: ", player_health, "/", player_max_health)

func get_player_health() -> int:
	return player_health

func get_player_max_health() -> int:
	return player_max_health

func get_player_health_percentage() -> float:
	return float(player_health) / float(player_max_health)

# === PLAYER ABILITY CHECKS ===

func can_double_jump() -> bool:
	"""Check if player has double jump ability"""
	return double_jump_purchased

func can_wall_jump() -> bool:
	"""Check if player has wall jump ability"""
	return wall_jump_purchased

func can_dash() -> bool:
	"""Check if player has dash ability"""
	return dash_purchased

func has_speed_upgrade() -> bool:
	"""Check if player has speed upgrade"""
	return speed_upgrade_purchased

func has_health_upgrade() -> bool:
	"""Check if player has health upgrade"""
	return health_upgrade_purchased

func has_damage_upgrade() -> bool:
	"""Check if player has damage upgrade"""
	return damage_upgrade_purchased

# === SAVE/LOAD SYSTEM ===

func save_game_state() -> Dictionary:
	"""Save the current game state to a dictionary"""
	return {
		"gear_count": gear_count,
		"CRED": CRED,
		"player_health": player_health,
		"player_max_health": player_max_health,
		"double_jump_purchased": double_jump_purchased,
		"wall_jump_purchased": wall_jump_purchased,
		"dash_purchased": dash_purchased,
		"speed_upgrade_purchased": speed_upgrade_purchased,
		"health_upgrade_purchased": health_upgrade_purchased,
		"damage_upgrade_purchased": damage_upgrade_purchased
	}

func load_game_state(state: Dictionary):
	"""Load game state from a dictionary"""
	gear_count = state.get("gear_count", 0)
	CRED = state.get("CRED", 0)
	player_health = state.get("player_health", 3)
	player_max_health = state.get("player_max_health", 3)
	double_jump_purchased = state.get("double_jump_purchased", false)
	wall_jump_purchased = state.get("wall_jump_purchased", false)
	dash_purchased = state.get("dash_purchased", false)
	speed_upgrade_purchased = state.get("speed_upgrade_purchased", false)
	health_upgrade_purchased = state.get("health_upgrade_purchased", false)
	damage_upgrade_purchased = state.get("damage_upgrade_purchased", false)
	
	# Apply upgrades to player if they exist
	apply_purchased_upgrades()
	
	# Update player health
	if player and player.has_method("set_health"):
		player.set_health(player_health)
	

# === UTILITY FUNCTIONS ===

func reset_game_state():
	"""Reset all game state to defaults"""
	gear_count = 0
	CRED = 0
	player_health = 3
	player_max_health = 3
	double_jump_purchased = false
	wall_jump_purchased = false
	dash_purchased = false
	speed_upgrade_purchased = false
	health_upgrade_purchased = false
	damage_upgrade_purchased = false

func get_game_stats() -> Dictionary:
	"""Get current game statistics"""
	return {
		"total_gears": gear_count,
		"total_cred": CRED,
		"player_health_percent": get_player_health_percentage(),
		"upgrades_purchased": get_purchased_upgrades().size(),
		"total_upgrades": 6
	}

func get_purchased_upgrades() -> Array:
	"""Get list of purchased upgrades"""
	var upgrades = []
	if double_jump_purchased:
		upgrades.append("double_jump")
	if wall_jump_purchased:
		upgrades.append("wall_jump")
	if dash_purchased:
		upgrades.append("dash")
	if speed_upgrade_purchased:
		upgrades.append("speed_upgrade")
	if health_upgrade_purchased:
		upgrades.append("health_upgrade")
	if damage_upgrade_purchased:
		upgrades.append("damage_upgrade")
	return upgrades

# === PUBLIC API FOR OTHER SCRIPTS ===

func register_player(player_node: CharacterBody3D):
	"""Register the player node with GameManager"""
	player = player_node
	initialize_player()

func register_hu3(hu3_node: CharacterBody3D):
	"""Register HU-3 companion with GameManager"""
	hu3_companion = hu3_node

func get_player() -> CharacterBody3D:
	"""Get player reference"""
	return player
