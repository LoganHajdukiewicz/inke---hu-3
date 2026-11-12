extends SceneTree
## Re-measure Inke's jump trajectories from the LIVE controller and rewrite
## addons/level_kit/jump_arcs.gd. Run after any movement tuning:
##   godot --headless --path . -s res://addons/level_kit/tools/record_arcs.gd
## Each move: run up on a flat floor, take off, then the floor is removed so
## the arc keeps falling below takeoff height (for downward jumps).

const MOVES := ["walk", "run", "double", "long"]
var arcs := {}
var mi := 0
var inke: CharacterBody3D
var floor_body: StaticBody3D
var stage: Node3D
var t := 0.0
var phase := 0
var jt := 0.0
var start := Vector3.ZERO
var fwd := Vector3.FORWARD
var samples := []
var second_done := false


func _initialize() -> void:
	_setup()


func _setup() -> void:
	if stage:
		stage.queue_free()
	stage = Node3D.new()
	floor_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(4000, 1, 4000)
	cs.shape = b
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	stage.add_child(floor_body)
	inke = load("res://scenes/characters/Player/inke_no_hu3.tscn").instantiate()
	stage.add_child(inke)
	get_root().add_child(stage)
	current_scene = stage
	var gm = get_root().get_node("GameManager")
	gm.double_jump_purchased = true
	gm.dash_purchased = true
	inke.set("debug_double_jump", true)
	inke.set("debug_dash", true)
	t = 0.0; phase = 0; jt = 0.0; samples = []; second_done = false


func _physics_process(delta: float) -> bool:
	var mode: String = MOVES[mi]
	t += delta
	if phase == 0 and t > 1.0:
		Input.action_press("forward")
		if mode != "walk":
			Input.action_press("run")
		phase = 1
	elif phase == 1 and t > 2.5:
		if mode == "long":
			Input.action_press("dash"); phase = 5; jt = 0.0
		else:
			_takeoff()
	elif phase == 5:
		jt += delta
		if jt > 0.05: Input.action_release("dash")
		if jt > 0.32: _takeoff()
	elif phase == 2:
		jt += delta
		if jt > 0.1: Input.action_release("jump")
		if mode == "double" and not second_done and jt > 0.35:
			Input.action_press("jump"); second_done = true; jt = 0.0; phase = 3
		_sample()
	elif phase == 3:
		jt += delta
		if jt > 0.1:
			Input.action_release("jump"); phase = 2; jt = 0.2
		_sample()
	if t > 12.0:
		_next()
	return false


func _takeoff() -> void:
	start = inke.global_position
	fwd = Vector3(inke.velocity.x, 0, inke.velocity.z).normalized()
	Input.action_press("jump")
	phase = 2; jt = 0.0
	samples = [Vector2.ZERO]
	floor_body.position.y = -9000.0


func _sample() -> void:
	var p := inke.global_position - start
	samples.append(Vector2(snappedf(Vector3(p.x, 0, p.z).dot(fwd), 0.01), snappedf(p.y, 0.01)))
	if p.y < -40.0:
		_next()


func _next() -> void:
	for a in ["forward", "run", "jump", "dash"]:
		Input.action_release(a)
	var thin := []
	for i in range(0, samples.size(), 2):
		thin.append(samples[i])
	arcs[MOVES[mi]] = thin
	print("record_arcs: %s  %d samples" % [MOVES[mi], thin.size()])
	mi += 1
	if mi >= MOVES.size():
		_write()
		quit()
	else:
		_setup()


func _write() -> void:
	var path := "res://addons/level_kit/jump_arcs.gd"
	var src := FileAccess.get_file_as_string(path)
	var a := src.find("const ARCS := {")
	var b := src.find("\n}\n", a)
	if a < 0 or b < 0:
		push_error("record_arcs: couldn't find ARCS block in jump_arcs.gd")
		return
	var body := "const ARCS := {\n"
	for k in MOVES:
		var parts := PackedStringArray()
		for v in arcs[k]:
			parts.append("Vector2(%s, %s)" % [v.x, v.y])
		body += "\t\"%s\": [%s],\n" % [k, ", ".join(parts)]
	body += "}"
	var out := src.substr(0, a) + body + src.substr(b + 2)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("record_arcs: wrote ", path)
