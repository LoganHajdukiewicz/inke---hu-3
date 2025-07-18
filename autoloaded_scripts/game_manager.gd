extends Node

# Game Resources
@export var gear_count: int = 0
@export var CRED: int = 0

# Player Stats
@export var player_health: int = 3
@export var player_max_health: int = 3

# HU-3 Companion Stats
@export var hu3_collected_gears: int = 0

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
@export var double_jump_cost: int = 3
@export var wall_jump_cost: int = 4
@export var dash_cost: int = 3
@export var speed_upgrade_cost: int = 3
@export var health_upgrade_cost: int = 3
@export var damage_upgrade_cost: int = 3

# Player Reference
var player: CharacterBody3D = null
var hu3_companion: CharacterBody3D = null

# Signals
signal gear_collected(total_gears: int)
signal cred_collected(amount: int, total_cred: int)
signal upgrade_purchased(upgrade_type: String)
signal health_changed(new_health: int, max_health: int)
signal hu3_health_changed(new_health: int, max_health: int)

func _ready():
	# Find player reference
	find_player()
	
	# Connect to player's HU-3 companion if it exists
	if player and player.has_method("get_hu3_companion"):
		hu3_companion = player.get_hu3_companion()

func find_player():
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
		print("GameManager: Found player: ", player.name)
	else:
		print("GameManager: No player found in scene!")

# === GEAR MANAGEMENT ===

func add_gear(amount: int = 1):
	"""Add gears to the player's collection"""
	gear_count += amount
	print("Gear collected! Total gears: ", gear_count)
	gear_collected.emit(gear_count)

func spend_gears(amount: int) -> bool:
	"""Spend gears if player has enough"""
	if gear_count >= amount:
		gear_count -= amount
		print("Gears spent: ", amount, " Remaining: ", gear_count)
		return true
	return false

func get_gear_count() -> int:
	return gear_count

func add_hu3_gear():
	"""Called when HU-3 collects a gear"""
	hu3_collected_gears += 1
	add_gear(1)  # Still counts toward total gear count
	print("HU-3 collected gear! HU-3 gears: ", hu3_collected_gears)

func get_hu3_gear_count() -> int:
	return hu3_collected_gears

# === CRED MANAGEMENT ===

func add_CRED(reward: int):
	"""Add CRED to Inke"""
	CRED += reward
	print("CRED Received! CRED added: ", reward)
	print("Total CRED: ", CRED)
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
		print("GameManager: Upgrade already purchased: ", upgrade_type)
		return false
	
	if not spend_gears(cost):
		print("GameManager: Not enough gears for upgrade: ", upgrade_type)
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
			if player and player.has_method("unlock_health_upgrade"):
				player.unlock_health_upgrade()
		"damage_upgrade":
			damage_upgrade_purchased = true
			if player and player.has_method("unlock_damage_upgrade"):
				player.unlock_damage_upgrade()
	
	print("GameManager: Purchased upgrade: ", upgrade_type)
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


# === SAVE/LOAD SYSTEM ===

func save_game_state() -> Dictionary:
	"""Save the current game state to a dictionary"""
	return {
		"gear_count": gear_count,
		"CRED": CRED,
		"player_health": player_health,
		"player_max_health": player_max_health,
		"hu3_collected_gears": hu3_collected_gears,
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
	hu3_collected_gears = state.get("hu3_collected_gears", 0)
	double_jump_purchased = state.get("double_jump_purchased", false)
	wall_jump_purchased = state.get("wall_jump_purchased", false)
	dash_purchased = state.get("dash_purchased", false)
	speed_upgrade_purchased = state.get("speed_upgrade_purchased", false)
	health_upgrade_purchased = state.get("health_upgrade_purchased", false)
	damage_upgrade_purchased = state.get("damage_upgrade_purchased", false)
	
	# Apply upgrades to player if they exist
	if player:
		if double_jump_purchased and player.has_method("unlock_double_jump"):
			player.unlock_double_jump()
		if wall_jump_purchased and player.has_method("unlock_wall_jump"):
			player.unlock_wall_jump()
		# Add other upgrades as needed
	
	print("GameManager: Game state loaded")

# === UTILITY FUNCTIONS ===

func reset_game_state():
	"""Reset all game state to defaults"""
	gear_count = 0
	CRED = 0
	player_health = 3
	hu3_collected_gears = 0
	double_jump_purchased = false
	wall_jump_purchased = false
	dash_purchased = false
	speed_upgrade_purchased = false
	health_upgrade_purchased = false
	damage_upgrade_purchased = false
	
	print("GameManager: Game state reset to defaults")

func get_game_stats() -> Dictionary:
	"""Get current game statistics"""
	return {
		"total_gears": gear_count,
		"hu3_gears": hu3_collected_gears,
		"player_gears": gear_count - hu3_collected_gears,
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
