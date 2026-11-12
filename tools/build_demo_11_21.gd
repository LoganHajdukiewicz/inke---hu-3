extends SceneTree
## Builds test/demo_11_21_2026.tscn - "Gearhaven Isle" (see docs/DEMO_11_21_2026.md).
##   godot --headless --path . -s res://tools/build_demo_11_21.gd
## Re-running OVERWRITES the scene. After you start hand-editing in the
## editor, stop re-running this (or copy the scene first).
##
## Layout (metres, +Z = south, -Z = north, Inke spawns on the south-east beach):
##   Hub town      (0, 0, 0)        flat pad r=28
##   Shipwreck     west  x -60..-170 over water (floor-type gauntlet)
##   Summit        north z -40..-110, climbs to y=46
##   Junkyard      east  x 45..120  (rail + combat camp)
##   Boss islet    south (0, 0, 135) reached by spring + rail past a CRED gate

const SCENE_NAME := "Demo_11_21_2026"   # = dialogue/Demo_11_21_2026/
const OUT := "res://test/demo_11_21_2026.tscn"

var R: Node3D
var _terrain_script = load("res://scripts/environments/worldbuilding/terrain.gd")
var _pad_script = load("res://scripts/environments/worldbuilding/flatten_pad.gd")
var _platform = load("res://addons/level_kit/nodes/platform.gd")
var S := {}


func _initialize() -> void:
	var paths := {
		"inke": "res://scenes/characters/Player/inke.tscn",
		"floor": "res://scenes/environments/floor.tscn",
		"sign": "res://scenes/items/Signs/sign.tscn",
		"trigger": "res://scenes/environments/dialogue_trigger.tscn",
		"checkpoint": "res://scenes/environments/checkpoint.tscn",
		"merchant": "res://scenes/characters/NPCs/Friendly NPCs/merchant.tscn",
		"giver": "res://scenes/characters/NPCs/Friendly NPCs/quest_giver.tscn",
		"gear": "res://scenes/items/Collectibles/six_teeth_gear.tscn",
		"cred": "res://scenes/items/Collectibles/cred.tscn",
		"spray": "res://scenes/items/Collectibles/spray_can.tscn",
		"health": "res://scenes/items/Collectibles/health_pickup.tscn",
		"box": "res://scenes/items/Breakables/box.tscn",
		"barrel": "res://scenes/items/Breakables/explosive_barrel.tscn",
		"enemy": "res://scenes/characters/NPCs/Enemies/enemy.tscn",
		"charger": "res://scenes/characters/NPCs/Enemies/charger_enemy.tscn",
		"turret": "res://scenes/characters/NPCs/Enemies/turret_enemy.tscn",
		"hopper": "res://scenes/characters/NPCs/Enemies/hopper_enemy.tscn",
		"bomber": "res://scenes/characters/NPCs/Enemies/bomber_enemy.tscn",
		"rail": "res://scenes/items/Rails/rail.tscn",
		"grapple": "res://scenes/environments/grapple_point.tscn",
		"swingbar": "res://scenes/environments/swing_bar.tscn",
		"rope": "res://scenes/environments/rope.tscn",
		"fence": "res://scenes/environments/climbable_wall.tscn",
		"ladder": "res://scenes/environments/ladder.tscn",
		"mound": "res://scenes/environments/ground_pound_mound.tscn",
		"healpatch": "res://scenes/environments/heal_patch.tscn",
		"water": "res://scenes/environments/water_zone.tscn",
		"reset": "res://scenes/environments/reset_plane.tscn",
		"flag": "res://scenes/quests/location_flag.tscn",
		"exit": "res://scenes/environments/scene_transitioner.tscn",
		"ui": "res://scenes/UI/dialogue_ui.tscn",
	}
	for k in paths:
		S[k] = load(paths[k])
	_build_and_save.call_deferred()


func _build_and_save() -> void:
	build()
	# Anything that _ready() generated while the tree was live (meshes,
	# collisions, buoys, labels...) has no owner - only owned nodes get
	# packed, but clear owners on runtime children just in case.
	for n in R.find_children("*", "", true, false):
		if n.owner != R and n.owner != null and n.owner.get_parent() != null and not n.owner.scene_file_path.is_empty():
			continue
	var ps := PackedScene.new()
	var err := ps.pack(R)
	if err == OK:
		err = ResourceSaver.save(ps, OUT)
	print("build_demo_11_21: ", "saved " + OUT if err == OK else "FAILED %d" % err, "  nodes=", R.find_children("*", "", true, false).size())
	quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
func folder(name: String, parent: Node = null) -> Node3D:
	var n := Node3D.new()
	n.name = name
	(parent if parent else R).add_child(n)
	n.owner = R
	return n


var _ground_nodes := []   # [node, lift] - re-seated on the terrain after build


func ground(n: Node, lift: float) -> Node:
	_ground_nodes.append([n, lift])
	return n


func put(key: String, parent: Node, name: String, pos: Vector3, yaw_deg := 0.0, props := {}) -> Node:
	var n: Node = S[key].instantiate()
	n.name = name
	if parent.has_node(NodePath(name)):
		var k := 2
		while parent.has_node(NodePath("%s%d" % [name, k])):
			k += 1
		n.name = "%s%d" % [name, k]
	for p in props:
		n.set(p, props[p])
	parent.add_child(n)
	n.owner = R
	if n is Node3D:
		(n as Node3D).position = pos
		(n as Node3D).rotation_degrees.y = yaw_deg
	return n


func plat(parent: Node, name: String, top: Vector3, size: Vector3, look := 0, shape := 0, props := {}) -> Node3D:
	var p = _platform.new()
	p.name = name
	p.shape = shape
	p.size = size
	p.look = look
	for k in props:
		p.set(k, props[k])
	parent.add_child(p)
	p.owner = R
	p.position = top
	return p


func floor_t(parent: Node, name: String, top: Vector3, size: Vector3, ftype: int, props := {}) -> Node3D:
	# Floor's origin sits at the top of its box (mesh offset -0.25 in the scene)
	props["floor_size"] = size
	props["floor_type"] = ftype
	return put("floor", parent, name, top, 0.0, props)


func sign_at(parent: Node, name: String, pos: Vector3, yaw: float, dialogue: String, once := false) -> Node:
	var s = put("sign", parent, name, pos, yaw)
	var t = put("trigger", s, "DialogueTrigger", Vector3.ZERO, 0.0, {"dialogue_file": dialogue, "box_size": Vector3(5, 5, 5), "trigger_once": once})
	t.camera_walls_enabled = true
	t.camera_wall_left = 6.0
	t.camera_wall_right = 6.0
	return s


func wall_trigger(parent: Node, name: String, pos: Vector3, yaw: float, dialogue: String, size := Vector3(12, 6, 1)) -> Node:
	return put("trigger", parent, name, pos, yaw, {"dialogue_file": dialogue, "auto_start": true, "show_prompt": false, "box_size": size, "trigger_once": true, "dynamic_camera": false})


func gear(parent: Node, name: String, pos: Vector3) -> void:
	put("gear", parent, name, pos, 0.0)


func rail(parent: Node, name: String, pts: Array) -> Node:
	var r = S["rail"].instantiate()
	r.name = name
	var c := Curve3D.new()
	for p in pts:
		c.add_point(p - pts[0])
	r.curve = c
	parent.add_child(r)
	r.owner = R
	r.position = pts[0]
	return r


# ---------------------------------------------------------------------------
func build() -> void:
	R = Node3D.new()
	R.name = SCENE_NAME
	_world()
	_hub()
	_shipwreck()
	_summit()
	_junkyard()
	_boss()
	_seat_on_terrain()
	var ui = put("ui", R, "DialogueUI", Vector3.ZERO)
	var ct := Node.new()
	ct.name = "CredThreshold"
	ct.set_script(load("res://scripts/levels/cred_threshold.gd"))
	ct.set("cred_needed", 45)
	R.add_child(ct)
	ct.owner = R


func _seat_on_terrain() -> void:
	"""Sample a standalone COPY of the island terrain (only the terrain and
	its pads go in the tree, so no gameplay node runs _ready) and drop every
	ground-level node onto the real surface. Everything sits at the origin,
	so local XZ == world XZ."""
	var src = R.find_child("Island", true, false)
	var t = src.duplicate()
	get_root().add_child(t)
	t.position = src.position
	t._rebuild()
	for pair in _ground_nodes:
		var n: Node3D = pair[0]
		var p := _local_pos(n)
		var h: float = t.get_height(Vector3(p.x, 0, p.z))
		var parent_y := _local_pos(n.get_parent()).y if n.get_parent() is Node3D else 0.0
		n.position.y = h + pair[1] - parent_y
	t.queue_free()


func _local_pos(n: Node) -> Vector3:
	"""Position relative to R without needing the scene tree."""
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur and cur != R:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin


func _world() -> void:
	var w := folder("World")
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Feb-24 demo look: purple zenith -> orange sunset horizon, glow, filmic
	sm.sky_top_color = Color(0.401837, 0.248319, 0.976917)
	sm.sky_horizon_color = Color(0.976471, 0.639216, 0.262745)
	sm.ground_bottom_color = Color(0.110067, 0.178332, 1)
	sm.ground_horizon_color = Color(0.618941, 0.639129, 0.727188)
	sm.energy_multiplier = 1.5
	sky.sky_material = sm
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.fog_enabled = false
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	env.environment = e
	w.add_child(env); env.owner = R
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	w.add_child(sun); sun.owner = R

	# Island terrain: 240x240, gentle hills, pads for hub/spokes, rim dips
	# under the water so the beach band appears automatically.
	var t = _terrain_script.new()
	t.name = "Island"
	t.size = Vector2(240, 240)
	t.resolution = 96
	t.hill_height = 7.0
	t.hill_frequency = 0.018
	t.edge_falloff = 0.22
	t.edge_height = -4.0
	t.noise_seed = 1121
	t.sand_distance = 14.0
	t.snow_height = 40.0
	w.add_child(t); t.owner = R
	t.position = Vector3(0, 0, 0)
	for pad in [[Vector3(0, 1.0, 0), 30.0, 10.0], [Vector3(0, 1.0, 92), 18.0, 8.0], [Vector3(-48, 1.0, 0), 12.0, 6.0], [Vector3(48, 1.0, 0), 12.0, 6.0], [Vector3(0, 1.0, -46), 14.0, 6.0], [Vector3(70, 1.0, -2), 24.0, 8.0], [Vector3(14, 1.0, 34), 10.0, 12.0]]:
		var fp = _pad_script.new()
		fp.name = "Pad"
		fp.radius = pad[1]
		fp.blend = pad[2]
		t.add_child(fp, true); fp.owner = R
		fp.position = pad[0]
	# Summit mountain is a sculpted Terrain bump behind the climb (scenery);
	# the actual climb is authored platforms so it's precise.
	var water = put("water", w, "Sea", Vector3(0, -0.6, 0), 0.0, {"water_size": Vector2(700, 700), "boundary_distance": 30.0})
	# Hand-authored buoy loop that wraps the island AND the shipwreck + boss islet
	var bl := Path3D.new(); bl.name = "BuoyLine"
	var c := Curve3D.new()
	for pt in [Vector3(150, 0, -40), Vector3(150, 0, 120), Vector3(60, 0, 235), Vector3(-60, 0, 235), Vector3(-150, 0, 130), Vector3(-215, 0, 90), Vector3(-215, 0, -50), Vector3(-120, 0, -200), Vector3(40, 0, -210), Vector3(150, 0, -40)]:
		c.add_point(pt)
	bl.curve = c
	water.add_child(bl); bl.owner = R
	put("reset", w, "ResetPlane", Vector3(0, -20, 0))


# ---------------------------------------------------------------------------
func _hub() -> void:
	var h := folder("Hub")
	ground(put("inke", R, "Inke", Vector3(22, 2.0, 50), 200.0), 1.0)
	var cp := folder("Checkpoints")
	ground(put("checkpoint", cp, "CP_Beach", Vector3(22, 1.2, 48), 0.0, {"checkpoint_id": "beach"}), 0.2)
	put("checkpoint", cp, "CP_Town", Vector3(0, 1.2, 8), 0.0, {"checkpoint_id": "town"})
	ground(sign_at(h, "S1GN_Welcome", Vector3(18, 1.2, 44), 200.0, "Welcome", false), 0.0)
	ground(wall_trigger(h, "HU3IntroWall", Vector3(10, 2, 30), 20.0, "HU3Intro", Vector3(18, 6, 1)), 2.0)
	sign_at(h, "S1GN_Town", Vector3(-4, 1.2, 12), 180.0, "TownSign")
	sign_at(h, "S1GN_Merchant", Vector3(14, 1.2, -10), 120.0, "MerchantSign")

	# Plaza + houses (Platforms as greybox buildings, with roofs you can reach)
	plat(h, "Plaza", Vector3(0, 1.1, 0), Vector3(26, 0.4, 26), 0)
	var houses := [[Vector3(-20, 6, -18), Vector3(10, 5, 10)], [Vector3(20, 6, -18), Vector3(10, 5, 9)], [Vector3(-22, 5, 16), Vector3(9, 4, 9)], [Vector3(24, 7, 14), Vector3(8, 6, 10)]]
	var i := 0
	for hs in houses:
		plat(h, "House%d" % i, hs[0], Vector3(hs[1].x, 0.5, hs[1].z), 1, 0, {"pillar_depth": hs[0].y - 1.0})
		i += 1
	put("healpatch", h, "HealPatch", Vector3(8, 1.35, 6))
	put("health", h, "Health", Vector3(-8, 2.2, -6))
	put("spray", h, "SprayCan_Roof", Vector3(24, 8.0, 14))   # roof bonus: house3 via house hop

	var npc := folder("NPCs")
	var m = put("merchant", npc, "Merchant", Vector3(16, 1.3, -14), 220.0)
	var ups = m.available_upgrades.duplicate()
	ups.clear()
	for u in [0, 1, 2, 9]:   # double jump, wall jump, dash, shockwave
		ups.append(u)
	m.available_upgrades = ups
	m.camera_walls_enabled = true
	_giver(npc, "Rust", Vector3(-12, 1.3, -4), 250.0, "demo_gears.tres", Color(0.85, 0.45, 0.15),
		["Ahoy... landlubber. Ignore the crying, it's sea spray.", "My gear crate went down with the old wreck out WEST. Six gears, scattered all over those rotten decks."],
		"Bring me six gears and the CRED is yours. Deal?")
	_giver(npc, "Echo", Vector3(-4, 1.3, -14), 180.0, "demo_summit.tres", Color(0.4, 0.75, 1.0),
		["...", "Sorry. I was listening to the mountain. It's NORTH. It hums."],
		"Climb to the very top and plant my flag. I'll meet you there.")
	_giver(npc, "Moxie", Vector3(12, 1.3, 2), 100.0, "demo_crates.tres", Color(0.95, 0.3, 0.55),
		["Robots set up a camp in the junkyard EAST of here.", "They're stockpiling crates. Of what? Don't care. I want them GONE."],
		"Smash six of their crates. Barrels go boom, by the way. Love that for you.")


func _giver(parent: Node, n: String, pos: Vector3, yaw: float, quest: String, col: Color, talk: Array, ask: String) -> void:
	var g = put("giver", parent, "QG_" + n, pos, yaw)
	g.npc_name = n
	g.body_color = col
	var st: Array[String] = []
	st.assign(talk)
	g.small_talk = st
	g.quest_ask = ask
	g.quest_file = quest
	g.camera_walls_enabled = true
	g.camera_wall_left = 5.0
	g.camera_wall_right = 5.0


# ---------------------------------------------------------------------------
# SPOKE 1 - SHIPWRECK (west): floor types, Feb 24 beats 6-12
func _shipwreck() -> void:
	var w := folder("Shipwreck")
	var gq := folder("Gears", w)
	put("checkpoint", w, "CP_Wreck", Vector3(-48, 1.2, 0), 0.0, {"checkpoint_id": "wreck"})
	sign_at(w, "S1GN_Wreck1", Vector3(-52, 1.2, -6), 90.0, "Wreck1")
	# dock out over the water
	plat(w, "Dock", Vector3(-66, 1.0, 0), Vector3(14, 0.5, 8), 1, 0, {"pillar_depth": 4.0})
	# spring pads up onto the wreck bow (high)
	floor_t(w, "Spring1", Vector3(-76, 1.0, 0), Vector3(5, 0.5, 5), 1)
	plat(w, "Bow", Vector3(-88, 10.0, 0), Vector3(12, 0.6, 12), 1, 0, {"pillar_depth": 12.0})
	gear(gq, "Gear1", Vector3(-88, 11.2, 0))
	sign_at(w, "S1GN_Wreck2", Vector3(-92, 10.2, 4), 90.0, "Wreck2")
	# moving deck across the gap
	floor_t(w, "MovingDeck", Vector3(-98, 10.0, 0), Vector3(7, 0.5, 7), 4, {"movement_axis": Vector3(-20, 0, 0), "movement_duration": 4.0})
	plat(w, "MidDeck", Vector3(-128, 10.0, 0), Vector3(10, 0.6, 10), 1, 0, {"pillar_depth": 12.0})
	gear(gq, "Gear2", Vector3(-128, 11.2, 3))
	# falling planks (the troll: trigger AFTER you're on them)
	for k in range(4):
		floor_t(w, "Rotten%d" % k, Vector3(-138 - k * 7, 10.0, 0), Vector3(6, 0.5, 5), 2, {"fall_duration": 2.0, "respawn_delay": 2.5})
	wall_trigger(w, "FallTroll", Vector3(-139, 11.5, 0), 90.0, "WreckFall", Vector3(8, 4, 1))
	gear(gq, "Gear3", Vector3(-152, 11.5, 0))
	plat(w, "Stern", Vector3(-170, 10.0, 0), Vector3(12, 0.6, 14), 1, 0, {"pillar_depth": 12.0})
	put("checkpoint", w, "CP_Stern", Vector3(-170, 10.2, 4), 0.0, {"checkpoint_id": "stern"})
	sign_at(w, "S1GN_Wreck3", Vector3(-166, 10.2, 6), 0.0, "Wreck3")
	# spinning wheel deck -> heading back south-east
	floor_t(w, "SpinWheel", Vector3(-170, 10.0, 22), Vector3(12, 0.5, 12), 3, {"spin_speed": 45.0})
	gear(gq, "Gear4", Vector3(-174, 11.5, 22))
	# frozen hold over sludge (ice floors above damage floors)
	for k in range(3):
		floor_t(w, "Ice%d" % k, Vector3(-158 + k * 0.0, 10.0, 34 + k * 12), Vector3(8 - k * 2, 0.5, 12), 6)
		floor_t(w, "Sludge%d" % k, Vector3(-158, 7.0, 34 + k * 12), Vector3(20, 0.5, 12), 5)
	gear(gq, "Gear5", Vector3(-158, 11.5, 58))
	plat(w, "Hatch", Vector3(-158, 10.0, 72), Vector3(10, 0.6, 10), 1, 0, {"pillar_depth": 12.0})
	gear(gq, "Gear6", Vector3(-158, 11.2, 72))
	# exit: long slide-down rail back to the beach
	rail(w, "ReturnRail", [Vector3(-158, 11.5, 78), Vector3(-140, 8.0, 84), Vector3(-110, 4.0, 82), Vector3(-80, 2.5, 66)])
	put("cred", w, "BonusCRED_Wreck", Vector3(-88, 15.0, -8), 0.0, {"cred_value": 5})
	put("spray", w, "SprayCan_Wreck", Vector3(-170, 11.2, 34))


# ---------------------------------------------------------------------------
# SPOKE 2 - SUMMIT (north): vertical traversal, Feb 24 beats 4,7,9,11
func _summit() -> void:
	var s := folder("Summit")
	put("checkpoint", s, "CP_SummitBase", Vector3(0, 1.2, -46), 0.0, {"checkpoint_id": "summit_base"})
	sign_at(s, "S1GN_Summit1", Vector3(6, 1.2, -42), 180.0, "Summit1")
	# 1) chain fence up the first cliff (8m)
	plat(s, "Cliff1", Vector3(0, 9.0, -64), Vector3(16, 0.6, 12), 0, 0, {"pillar_depth": 9.0})
	put("fence", s, "Fence1", Vector3(0, 1.0, -57.7), 0.0, {"wall_size": Vector3(8, 8.5, 0.5)})
	put("ladder", s, "Ladder1", Vector3(7, 1.0, -57.8), 0.0)
	# 2) swing bars across a ravine
	sign_at(s, "S1GN_Summit2", Vector3(-6, 9.2, -66), 180.0, "Summit2")
	put("swingbar", s, "Swing1", Vector3(0, 14.0, -76), 0.0, {"bar_length": 4.0, "show_posts": false})
	put("swingbar", s, "Swing2", Vector3(0, 15.0, -88), 0.0, {"bar_length": 4.0, "show_posts": false})
	plat(s, "Ledge2", Vector3(0, 12.0, -100), Vector3(12, 0.6, 10), 0, 0, {"pillar_depth": 12.0})
	put("checkpoint", s, "CP_Ledge2", Vector3(0, 12.2, -100), 0.0, {"checkpoint_id": "summit_mid"})
	put("health", s, "Health_Summit", Vector3(4, 13.2, -102))
	# 3) wall-jump chimney (two walls 5m apart, 14m tall) + a ledge-grab lip
	sign_at(s, "S1GN_Summit3", Vector3(-4, 12.2, -102), 180.0, "Summit3")
	plat(s, "ChimneyL", Vector3(-3.5, 27.0, -110), Vector3(1.0, 0.6, 8), 0, 0, {"pillar_depth": 15.0})
	plat(s, "ChimneyR", Vector3(3.5, 27.0, -110), Vector3(1.0, 0.6, 8), 0, 0, {"pillar_depth": 15.0})
	# non-wall-jump route: climb fence on the side (slower, always possible)
	put("fence", s, "Fence2", Vector3(9.0, 12.0, -108), 90.0, {"wall_size": Vector3(8, 15.5, 0.5)})
	plat(s, "Cliff3", Vector3(6, 27.0, -122), Vector3(18, 0.6, 14), 0, 0, {"pillar_depth": 27.0})
	# 4) grapple chain up to the peak
	sign_at(s, "S1GN_Summit4", Vector3(0, 27.2, -118), 180.0, "Summit4")
	put("grapple", s, "Grapple1", Vector3(0, 34.0, -136))
	put("grapple", s, "Grapple2", Vector3(-8, 40.0, -146))
	put("grapple", s, "Grapple3", Vector3(0, 46.0, -156))
	plat(s, "Peak", Vector3(0, 44.0, -166), Vector3(10, 0.6, 10), 5, 1, {"pillar_depth": 44.0})
	put("flag", s, "SummitFlag", Vector3(0, 45.5, -166), 0.0, {"flag_id": "demo_summit_top", "size": Vector3(8, 4, 8), "visible_in_game": true, "discovery_text": "THE SUMMIT"})
	sign_at(s, "S1GN_SummitTop", Vector3(3, 44.2, -168), 200.0, "SummitTop")
	put("cred", s, "BonusCRED_Peak", Vector3(0, 46.0, -169), 0.0, {"cred_value": 5})
	put("spray", s, "SprayCan_Summit", Vector3(-8, 41.5, -146))
	# zip back down
	rail(s, "SummitRail", [Vector3(4, 45.0, -162), Vector3(18, 30.0, -130), Vector3(22, 14.0, -90), Vector3(14, 3.0, -52)])


# ---------------------------------------------------------------------------
# SPOKE 3 - JUNKYARD (east): rails + combat camp, Feb 24 beats 3,5,18
func _junkyard() -> void:
	var j := folder("Junkyard")
	put("checkpoint", j, "CP_Junk", Vector3(46, 1.2, 0), 0.0, {"checkpoint_id": "junk"})
	sign_at(j, "S1GN_Junk1", Vector3(42, 1.2, 6), 270.0, "Junk1")
	plat(j, "RailStart", Vector3(50, 4.0, 0), Vector3(6, 0.6, 6), 2, 0, {"pillar_depth": 3.0})
	plat(j, "Step", Vector3(44, 2.5, 0), Vector3(3, 0.5, 4), 2, 0, {"pillar_depth": 1.5})
	rail(j, "CampRail", [Vector3(53, 5.0, 0), Vector3(62, 6.5, -4), Vector3(74, 7.0, -10), Vector3(84, 4.0, -6)])
	var camp := folder("Camp", j)
	plat(camp, "Arena", Vector3(72, 1.1, -2), Vector3(34, 0.4, 30), 2)
	sign_at(j, "S1GN_Junk2", Vector3(60, 1.3, 10), 270.0, "Junk2")
	sign_at(j, "S1GN_Junk3", Vector3(58, 1.3, -14), 270.0, "Junk3")
	# junk-pile cover + crates (6+ needed, 9 placed)
	plat(camp, "Pile1", Vector3(66, 3.0, -8), Vector3(5, 0.5, 4), 2, 0, {"pillar_depth": 2.0})
	plat(camp, "Pile2", Vector3(80, 4.0, 6), Vector3(4, 0.5, 6), 2, 0, {"pillar_depth": 3.0})
	var crates := [Vector3(64, 1.8, 2), Vector3(65, 1.8, 3.4), Vector3(64.5, 2.8, 2.7), Vector3(76, 1.8, -10), Vector3(77.4, 1.8, -10), Vector3(84, 1.8, 0), Vector3(85, 1.8, 1.6), Vector3(70, 1.8, 10), Vector3(66, 3.8, -8)]
	var i := 0
	for c in crates:
		put("box", camp, "Crate%d" % i, c); i += 1
	put("barrel", camp, "Barrel1", Vector3(74, 1.9, 4))
	put("barrel", camp, "Barrel2", Vector3(82, 1.9, -6))
	put("mound", camp, "Mound", Vector3(88, 1.3, 10))
	var en := folder("Enemies", camp)
	for p in [Vector3(68, 1.6, -4), Vector3(74, 1.6, 0), Vector3(78, 1.6, -4), Vector3(70, 1.6, 6), Vector3(82, 1.6, 4)]:
		put("enemy", en, "Inkling", p, 270.0)
	put("charger", en, "Charger", Vector3(84, 1.6, -2), 270.0)
	put("turret", en, "Turret", Vector3(80, 4.5, 6), 270.0)
	put("cred", j, "BonusCRED_Junk", Vector3(80, 6.0, 6), 0.0, {"cred_value": 5})
	put("spray", j, "SprayCan_Junk", Vector3(88, 2.5, -14))
	put("health", j, "Health_Junk", Vector3(60, 2.2, -6))


# ---------------------------------------------------------------------------
# BOSS: gate on the south beach -> spring -> rail -> arena islet
func _boss() -> void:
	var b := folder("Boss")
	var gate := StaticBody3D.new()
	gate.name = "CredGate"
	gate.set_script(load("res://scripts/levels/cred_gate.gd"))
	b.add_child(gate); gate.owner = R
	gate.set("cred_needed", 45)
	gate.set("size", Vector3(16, 6, 0.6))
	gate.set("open_dialogue", "GateOpen")
	gate.position = Vector3(0, 4.0, 78)
	ground(sign_at(b, "S1GN_Gate", Vector3(-9, 1.2, 74), 160.0, "GateLocked"), 0.0)
	put("checkpoint", b, "CP_Gate", Vector3(0, 1.2, 84), 0.0, {"checkpoint_id": "gate"})
	# fence posts either side of the gate so you can't walk around it
	plat(b, "GateWallL", Vector3(-14, 7.0, 78), Vector3(12, 0.5, 1.2), 0, 0, {"pillar_depth": 8.0})
	plat(b, "GateWallR", Vector3(14, 7.0, 78), Vector3(12, 0.5, 1.2), 0, 0, {"pillar_depth": 8.0})
	floor_t(b, "BossSpring", Vector3(0, 1.0, 96), Vector3(6, 0.5, 6), 1, {"spring_force": 26.0})
	plat(b, "Launch", Vector3(0, 14.0, 108), Vector3(8, 0.6, 6), 0, 0, {"pillar_depth": 2.0})
	rail(b, "BossRail", [Vector3(0, 15.5, 112), Vector3(0, 13.0, 130), Vector3(4, 9.0, 148), Vector3(0, 6.0, 162)])
	var arena := folder("Arena", b)
	plat(arena, "Islet", Vector3(0, 3.0, 180), Vector3(40, 3.0, 40), 0, 1, {"pillar_depth": 8.0, "round_sides": 40, "color": Color(0.75, 0.9, 0.6)})
	# sludge moat ring is just the water + low damage floors near the rim
	for k in range(4):
		var a := k * PI * 0.5 + PI * 0.25
		plat(arena, "Pillar%d" % k, Vector3(cos(a) * 12.0, 7.0, 180 + sin(a) * 12.0), Vector3(3, 0.5, 3), 0, 1, {"pillar_depth": 4.0})
	put("checkpoint", arena, "CP_Arena", Vector3(0, 3.2, 166), 0.0, {"checkpoint_id": "arena"})
	put("trigger", arena, "BossIntro", Vector3(0, 4.5, 168), 0.0, {"dialogue_file": "BossIntro", "auto_start": true, "show_prompt": false, "box_size": Vector3(30, 6, 3), "trigger_once": true})
	var king = put("charger", arena, "SludgeKing", Vector3(0, 3.6, 186), 180.0)
	king.is_boss = true
	king.boss_name = "THE SLUDGE KING"
	king.boss_bar_color = Color(0.45, 0.85, 0.2)
	king.max_health = 12
	king.current_health = 12
	king.enemy_id = "sludge_king"
	king.scale = Vector3(2.2, 2.2, 2.2)
	king.charge_damage = 1
	king.detection_range = 40.0
	for p in [Vector3(-8, 3.6, 184), Vector3(8, 3.6, 184), Vector3(0, 3.6, 194)]:
		put("enemy", arena, "Sludgeling", p, 180.0)
	for p in [Vector3(-14, 3.7, 176), Vector3(14, 3.7, 176), Vector3(0, 3.7, 196)]:
		put("barrel", arena, "Barrel", p)
	put("health", arena, "Health_Arena1", Vector3(-12, 4.2, 168))
	put("health", arena, "Health_Arena2", Vector3(12, 4.2, 168))
	# Boss quest giver = the Warden on the gate side, gated by CRED 45
	var w = put("giver", b, "QG_Warden", Vector3(9, 1.3, 86), 180.0)
	w.npc_name = "Warden"
	w.body_color = Color(0.55, 0.7, 0.3)
	w.cred_minimum = 45
	var st: Array[String] = []
	st.assign(["So the townsfolk vouch for you now.", "The Sludge King's been flooding this beach with sludge for weeks."])
	w.small_talk = st
	w.quest_ask = "Go knock him off his throne. Spring pad, then the rail."
	w.quest_file = "demo_boss.tres"
	# Victory: win dialogue + exit
	var win = put("trigger", arena, "WinTalk", Vector3(0, 4.0, 200), 0.0, {"dialogue_file": "Win", "box_size": Vector3(6, 6, 6), "auto_start": true, "show_prompt": false, "trigger_once": true})
	var ex = put("exit", arena, "ToYouWin", Vector3(0, 4.5, 206), 0.0, {"target_scene": "res://scenes/levels/youwinyay.tscn"})
	plat(arena, "VictoryStep", Vector3(0, 4.0, 202), Vector3(8, 0.5, 8), 6)
