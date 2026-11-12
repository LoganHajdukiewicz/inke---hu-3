@tool
extends RefCounted
class_name LevelKitGenerators
## Procedural platforming layouts, all spaced from Inke's MEASURED jump
## arcs (JumpArcs) so every generated gap is actually makeable with the
## chosen move. Each returns an Array of Dictionaries:
##   {pos: Vector3 (top-centre), size: Vector3, shape: int, look: int, rise: float}
## The plugin turns those into Platform nodes under one undoable action.

const JumpArcs = preload("res://addons/level_kit/jump_arcs.gd")


static func safe_gap(move: String, height_delta: float, difficulty: float, land_depth: float = 5.0) -> float:
	"""Edge-to-edge gap for a jump with this move onto a platform that is
	land_depth meters deep (along the jump direction).
	A fully-committed jump (holding forward the whole time, taking off at
	the edge) must land ON the target - not short of it, and not flying
	past it. So the gap is set from where the arc comes down:
	  difficulty 0 -> lands ~60% of the way into the target (forgiving)
	  difficulty 1 -> lands ~15% in, just past the near edge (tight)
	Returns 0 if the move can't reach that height at all."""
	var reach := JumpArcs.reach_at(move, height_delta)
	if reach <= 0.0:
		return 0.0
	var landing := land_depth * lerpf(0.6, 0.15, clampf(difficulty, 0.0, 1.0))
	return maxf(reach - landing - TAKEOFF_MARGIN, 0.5)


## Players jump a little before the edge; budget for it.
const TAKEOFF_MARGIN := 0.5


static func stepping_stones(count: int, move: String, difficulty: float, rise_per: float, plat_size: float, wander: float, seed_v: int) -> Array:
	"""A path of platforms heading -Z, each one jump apart, optionally
	climbing by rise_per and wandering left/right."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := []
	var pos := Vector3.ZERO
	var heading := 0.0
	# Long (dash) jumps need a RUNWAY: the dash itself covers ~14m before
	# the jump, so those platforms are stretched along the path.
	var long_runway := move == "long"
	var s := plat_size
	var d := maxf(plat_size, LONG_RUNWAY) if long_runway else plat_size
	for i in range(count):
		var round := not long_runway and rng.randf() < 0.3
		out.append({"pos": pos, "size": Vector3(s, 1.0, d if long_runway else s), "shape": Platform.Shape.ROUND if round else Platform.Shape.BOX, "look": Platform.Look.STONE, "rise": 0.0, "yaw": -heading})
		var next_s := plat_size * rng.randf_range(0.85, 1.25)
		var next_d := maxf(next_s, LONG_RUNWAY) if long_runway else next_s
		var dh := rise_per
		var gap := safe_gap(move, dh, difficulty, next_d)
		heading += rng.randf_range(-wander, wander)
		heading = clampf(heading, -1.2, 1.2)
		var dir := Vector3(sin(heading), 0, -cos(heading))
		var this_half := (d if long_runway else s) * 0.5
		pos += dir * (this_half + gap + next_d * 0.5)
		pos.y += dh
		s = next_s
		d = next_d
	return out


## Platform depth needed to dash + jump from a standstill (dash ~14m).
const LONG_RUNWAY := 18.0


static func spiral_tower(levels: int, move: String, difficulty: float, radius: float, rise_per: float, plat_size: float) -> Array:
	"""Platforms spiralling up around a central column."""
	var out := []
	var gap := safe_gap(move, rise_per, difficulty, plat_size)
	# angular step so the arc distance between platform edges == gap
	var circumference_step := gap + plat_size
	var dtheta := circumference_step / maxf(radius, 1.0)
	out.append({"pos": Vector3(0, levels * rise_per, 0), "size": Vector3(radius * 1.2, levels * rise_per + 2.0, radius * 1.2), "shape": Platform.Shape.ROUND, "look": Platform.Look.STONE, "rise": 0.0, "column": true})
	for i in range(levels):
		var a := dtheta * i
		var p := Vector3(cos(a) * radius, i * rise_per, sin(a) * radius)
		out.append({"pos": p, "size": Vector3(plat_size, 1.0, plat_size), "shape": Platform.Shape.BOX, "look": Platform.Look.WOOD, "rise": 0.0, "yaw": -a})
	return out


static func staircase_climb(steps: int, step_rise: float, step_depth: float, width: float) -> Array:
	"""Big chunky block steps (taller than stairs: each is a hop up)."""
	var out := []
	for i in range(steps):
		out.append({"pos": Vector3(0, i * step_rise, -i * step_depth), "size": Vector3(width, 1.0, step_depth), "shape": Platform.Shape.BOX, "look": Platform.Look.STONE, "rise": 0.0, "pillar": i * step_rise})
	return out


static func floating_islands(count: int, area: float, min_h: float, max_h: float, seed_v: int) -> Array:
	"""Scattered round islands, then pruned/pulled so each one is within
	a run jump of at least one other (no orphan unreachable islands)."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := []
	var tries := 0
	while pts.size() < count and tries < count * 40:
		tries += 1
		var s := rng.randf_range(5.0, 12.0)
		var p := Vector3(rng.randf_range(-area, area), rng.randf_range(min_h, max_h), rng.randf_range(-area, area))
		var ok := true
		for q in pts:
			if Vector2(p.x - q.pos.x, p.z - q.pos.z).length() < (s + q.size.x) * 0.5 + 2.0:
				ok = false
				break
		if ok:
			pts.append({"pos": p, "size": Vector3(s, 2.5, s), "shape": Platform.Shape.ROUND, "look": Platform.Look.GRASS, "rise": 0.0})
	# Reachability pass: pull any island that is too far from its nearest
	# neighbour toward it until a run jump makes it.
	for i in range(1, pts.size()):
		var best := -1
		var best_gap := INF
		for j in range(i):
			var g: float = Vector2(pts[i].pos.x - pts[j].pos.x, pts[i].pos.z - pts[j].pos.z).length() - (pts[i].size.x + pts[j].size.x) * 0.5
			if g < best_gap:
				best_gap = g
				best = j
		var dh: float = pts[i].pos.y - pts[best].pos.y
		var max_gap := safe_gap("run", dh, 0.6, pts[i].size.x)
		if max_gap <= 0.0:
			# too high to reach: drop it to a reachable height
			pts[i].pos.y = pts[best].pos.y + JumpArcs.apex("run") * 0.6
			dh = pts[i].pos.y - pts[best].pos.y
			max_gap = safe_gap("run", dh, 0.6, pts[i].size.x)
		if best_gap > max_gap:
			var a: Vector3 = pts[best].pos
			var b: Vector3 = pts[i].pos
			var flat := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			var want: float = (pts[i].size.x + pts[best].size.x) * 0.5 + max_gap
			pts[i].pos = Vector3(a.x + flat.x * want, b.y, a.z + flat.z * want)
	return pts


static func gauntlet(length: int, seed_v: int) -> Array:
	"""Mixed obstacle course: stones, a ramp, an arch bridge, a long-jump
	gap and a final raised goal. Good starting point to edit by hand."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := []
	var pos := Vector3.ZERO
	out.append({"pos": pos, "size": Vector3(10, 1, 10), "shape": Platform.Shape.BOX, "look": Platform.Look.STONE, "rise": 0.0})
	pos.z -= 5.0
	for i in range(length):
		var kind := rng.randi_range(0, 4)
		match kind:
			0:  # walk-jump stones
				for _k in range(3):
					var g := safe_gap("walk", 0.0, 0.4, 4.0)
					pos.z -= g + 2.0
					out.append({"pos": pos + Vector3(rng.randf_range(-2, 2), 0, 0), "size": Vector3(4, 1, 4), "shape": Platform.Shape.ROUND, "look": Platform.Look.WOOD, "rise": 0.0})
					pos.z -= 2.0
			1:  # ramp up
				pos.z -= 1.0
				var r := 4.0
				out.append({"pos": pos + Vector3(0, 0, -6), "size": Vector3(6, 1, 12), "shape": Platform.Shape.RAMP, "look": Platform.Look.STONE, "rise": r})
				pos.z -= 12.0
				pos.y += r
			2:  # arch bridge over a gap
				pos.z -= 1.0
				out.append({"pos": pos + Vector3(0, 0, -10), "size": Vector3(4, 0.6, 20), "shape": Platform.Shape.ARCH, "look": Platform.Look.WOOD, "rise": 3.0, "segments": 12})
				pos.z -= 20.0
			3:  # long-jump gap (runway platform, then the gap)
				out.append({"pos": pos + Vector3(0, 0, -LONG_RUNWAY * 0.5), "size": Vector3(6, 1, LONG_RUNWAY), "shape": Platform.Shape.BOX, "look": Platform.Look.METAL, "rise": 0.0})
				pos.z -= LONG_RUNWAY
				var g2 := safe_gap("long", 0.0, 0.5, 10.0)
				pos.z -= g2
				out.append({"pos": pos + Vector3(0, 0, -5), "size": Vector3(8, 1, 10), "shape": Platform.Shape.BOX, "look": Platform.Look.METAL, "rise": 0.0})
				pos.z -= 10.0
			4:  # climb: run jumps going up
				for _k in range(3):
					var dh := 2.0
					var g3 := safe_gap("run", dh, 0.45, 5.0)
					pos.z -= g3 + 2.5
					pos.y += dh
					out.append({"pos": pos, "size": Vector3(5, 1, 5), "shape": Platform.Shape.BOX, "look": Platform.Look.STONE, "rise": 0.0})
					pos.z -= 2.5
	pos.z -= safe_gap("run", 1.0, 0.4, 12.0) + 6.0
	pos.y += 1.0
	out.append({"pos": pos, "size": Vector3(12, 1, 12), "shape": Platform.Shape.ROUND, "look": Platform.Look.CRYSTAL, "rise": 0.0, "goal": true})
	return out
