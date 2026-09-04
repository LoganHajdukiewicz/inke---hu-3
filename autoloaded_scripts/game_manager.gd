extends Node

# Game Resources
var gear_count: int = 0
# Renamed from CRED: shadowed the global CRED collectible class (cred.gd)
var cred_count: int = 0

# Health Stats
const BASE_MAX_HEALTH: int = 3
const UPGRADED_MAX_HEALTH: int = 4
var player_health: int = BASE_MAX_HEALTH
var player_max_health: int = BASE_MAX_HEALTH

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

# HU3 Companion Scene
var hu3_scene = preload("res://scenes/characters/Player/HU3.tscn")

# Quit Input
var f1_held_time: float = 0.0
const F1_QUIT_DURATION: float = 1.0  # Hold for 1 second to quit

# Spray Can tracking (scout-fly style collectable, per level; formerly Ink Wisp)
var wisps_total: int = 0
var wisps_collected: int = 0
var _wisp_scene_id: int = 0  # instance id of the scene the wisps belong to
var cred_scene = preload("res://scenes/items/Collectibles/cred.tscn")

# Signals
signal gear_collected(total_gears: int)
signal cred_collected(amount: int, total_cred: int)
signal upgrade_purchased(upgrade_type: String)
signal health_changed(new_health: int, max_health: int)
signal player_spawned(player: CharacterBody3D)
signal hu3_spawned(hu3: CharacterBody3D)
signal wisp_collected_signal(collected: int, total: int)
signal all_wisps_collected()

func _ready():
	find_player()
	
	if player and player.has_method("get_hu3_companion"):
		hu3_companion = player.get_hu3_companion()
	
	apply_purchased_upgrades()

func _process(delta: float) -> void:
	# F1 hold-to-quit
	if Input.is_action_pressed("quit_game"):
		f1_held_time += delta
		if f1_held_time >= F1_QUIT_DURATION:
			get_tree().quit()
	else:
		f1_held_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# F10: free-roam debug camera toggle (works in any scene, no node needed)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		toggle_free_roam_camera()
		get_viewport().set_input_as_handled()


# === FREE ROAM DEBUG CAMERA (F10) ===

var _free_roam_cam: CutsceneCamera = null

func toggle_free_roam_camera() -> void:
	"""Detach a fly camera from the current view (F10). Fly with WASD/QE,
	Shift = fast, scroll = speed, P prints the pose for cutscene authoring.
	F10 again returns to gameplay. The player is frozen while flying."""
	if _free_roam_cam and is_instance_valid(_free_roam_cam):
		# Back to gameplay
		_free_roam_cam.deactivate(0.0)
		_free_roam_cam.queue_free()
		_free_roam_cam = null
		if player:
			player.process_mode = Node.PROCESS_MODE_INHERIT
		print("GameManager: free roam OFF")
		return
	var scene = get_tree().current_scene
	if scene == null:
		return
	var from_cam := get_viewport().get_camera_3d()
	_free_roam_cam = CutsceneCamera.new()
	_free_roam_cam.name = "FreeRoamCamera"
	_free_roam_cam.reports_to_cutscene_manager = false
	_free_roam_cam.default_blend_time = 0.0
	scene.add_child(_free_roam_cam)
	if from_cam:
		_free_roam_cam.global_transform = from_cam.global_transform
		_free_roam_cam.fov = from_cam.fov
	_free_roam_cam.activate(0.0)
	# Freeze the player so nothing walks off while you're framing shots
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	print("GameManager: free roam ON - WASD/QE fly, Shift fast, scroll speed, P prints pose, F10 exits")

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
		call_deferred("spawn_hu3_companion")

func apply_purchased_upgrades():
	"""Apply purchased upgrades that affect GameManager-owned state.
	Movement upgrades (double jump, wall jump, dash, speed) are queried live by
	the player states via can_double_jump()/can_wall_jump()/etc., so they need
	no push-style application here."""
	# Health upgrade increases max health; only clamp health (don't refill) so
	# re-running this on scene load doesn't grant a free heal.
	var new_max = UPGRADED_MAX_HEALTH if health_upgrade_purchased else BASE_MAX_HEALTH
	if player_max_health != new_max:
		player_max_health = new_max
		player_health = clamp(player_health, 0, player_max_health)
		health_changed.emit(player_health, player_max_health)

# === HU3 COMPANION MANAGEMENT ===

func spawn_hu3_companion():
	"""Spawn HU3 companion robot"""
	# FIXED: Add safety checks to ensure player is valid and in scene tree
	if not player or not is_instance_valid(player):
		print("GameManager: Cannot spawn HU3 - invalid player reference")
		return
	
	if not player.is_inside_tree():
		call_deferred("spawn_hu3_companion")
		return
	
	if hu3_companion and is_instance_valid(hu3_companion):
		return
	
	if hu3_scene:
		hu3_companion = hu3_scene.instantiate()
		
		# FIXED: Wait one frame before accessing player's global_position
		await get_tree().process_frame
		
		if not player or not is_instance_valid(player) or not player.is_inside_tree():
			print("GameManager: Player became invalid during HU3 spawn")
			if hu3_companion:
				hu3_companion.queue_free()
			hu3_companion = null
			return
		
		# Add to scene FIRST, then position (global_position requires being inside the tree)
		player.get_parent().add_child(hu3_companion)
		
		# Spawn just BEHIND the camera's view so HU3 appears to fly in from
		# behind the player - much nicer than popping into existence on screen.
		var spawn_pos = player.global_position + Vector3(0, 1.5, 0)
		var cam := get_viewport().get_camera_3d()
		if cam:
			# 2.5m behind the camera position, along its backward axis
			spawn_pos = cam.global_position + cam.global_transform.basis.z * 2.5
		else:
			# No camera yet: behind the player's back instead
			spawn_pos = player.global_position + player.global_transform.basis.z * 3.0 + Vector3(0, 1.5, 0)
		hu3_companion.global_position = spawn_pos
		
		# Set up HU3's reference to player
		if hu3_companion.has_method("set_player_reference"):
			hu3_companion.set_player_reference(player)
		
		hu3_spawned.emit(hu3_companion)
	else:
		print("GameManager: Could not load HU3 scene!")

func get_hu3_companion() -> CharacterBody3D:
	"""Get reference to HU3 companion"""
	return hu3_companion

# === GEAR MANAGEMENT ===

# --- Keys (for LockedDoors) ------------------------------------------------
signal key_collected(key_id: String)
signal key_used(key_id: String)
var keys: Dictionary = {}   # key_id -> count

func collect_key(key_id: String) -> void:
	keys[key_id] = keys.get(key_id, 0) + 1
	key_collected.emit(key_id)

func has_key(key_id: String) -> bool:
	return keys.get(key_id, 0) > 0

func use_key(key_id: String) -> bool:
	if not has_key(key_id):
		return false
	keys[key_id] -= 1
	if keys[key_id] <= 0:
		keys.erase(key_id)
	key_used.emit(key_id)
	return true

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
	cred_count += reward
	cred_collected.emit(reward, cred_count)
	
func get_CRED_count() -> int:
	return cred_count

# === INK WISP TRACKING (per level) ===

func register_wisp(_wisp: Node) -> void:
	"""Called by each SprayCan in _ready(). Counts reset automatically when
	wisps register from a new scene (level change / reload)."""
	var scene = get_tree().current_scene
	var scene_id = scene.get_instance_id() if scene else 0
	if scene_id != _wisp_scene_id:
		_wisp_scene_id = scene_id
		wisps_total = 0
		wisps_collected = 0
	wisps_total += 1

func collect_wisp(_wisp: Node) -> void:
	wisps_collected += 1
	wisp_collected_signal.emit(wisps_collected, wisps_total)
	
	if wisps_collected >= wisps_total and wisps_total > 0:
		all_wisps_collected.emit()
		_spawn_wisp_reward_cred()

func get_wisp_progress() -> Dictionary:
	return {"collected": wisps_collected, "total": wisps_total}

func reset_wisp_tracking() -> void:
	"""Call on level change so wisp counts start fresh."""
	wisps_total = 0
	wisps_collected = 0

func _spawn_wisp_reward_cred() -> void:
	"""All wisps collected: a CRED appears 10 feet (~3 m) in front of the player."""
	if not player or not is_instance_valid(player) or not player.is_inside_tree():
		return
	if not cred_scene:
		return
	
	var cred = cred_scene.instantiate()
	player.get_parent().add_child(cred)
	
	# 10 feet ~= 3.05 meters, in front of where Inke is facing
	var forward = -player.global_transform.basis.z.normalized()
	var spawn_pos = player.global_position + forward * 3.05 + Vector3(0, 1.0, 0)
	cred.global_position = spawn_pos
	
	# Small arrival flourish
	cred.scale = Vector3(0.05, 0.05, 0.05)
	var tween = cred.create_tween()
	tween.tween_property(cred, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	
	# Set the upgrade as purchased.
	# Movement/damage upgrades are queried live via can_double_jump()/etc.
	match upgrade_type.to_lower():
		"double_jump":
			double_jump_purchased = true
		"wall_jump":
			wall_jump_purchased = true
		"dash":
			dash_purchased = true
		"speed_upgrade":
			speed_upgrade_purchased = true
		"health_upgrade":
			health_upgrade_purchased = true
			player_max_health = UPGRADED_MAX_HEALTH
			# Reward the purchase with a full heal (also triggers signal)
			set_player_health(player_max_health)
		"damage_upgrade":
			damage_upgrade_purchased = true
	
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

func heal_player(amount: int):
	"""Heal the player"""
	set_player_health(player_health + amount)

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
		"CRED": cred_count,
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
	cred_count = state.get("CRED", 0)
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
	cred_count = 0
	player_health = BASE_MAX_HEALTH
	player_max_health = BASE_MAX_HEALTH
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
		"total_cred": cred_count,
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
	"""Register HU3 companion with GameManager"""
	hu3_companion = hu3_node

func get_player() -> CharacterBody3D:
	"""Get player reference"""
	return player
