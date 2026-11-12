@tool
extends RefCounted
class_name JumpArcs
## MEASURED jump trajectories of the real Inke controller (not guesses).
## Each arc = [horizontal_m, height_m] samples from takeoff, recorded headless
## by addons/level_kit/tools/record_arcs.gd. Re-run that after tuning movement:
##   godot --headless --path . -s res://addons/level_kit/tools/record_arcs.gd

const ARCS := {
	"walk": [Vector2(0.0, 0.0), Vector2(0.17, 0.0), Vector2(0.43, 0.48), Vector2(0.7, 0.92), Vector2(0.97, 1.33), Vector2(1.23, 1.71), Vector2(1.5, 2.05), Vector2(1.77, 2.36), Vector2(2.03, 2.64), Vector2(2.3, 2.89), Vector2(2.57, 3.1), Vector2(2.83, 3.29), Vector2(3.1, 3.43), Vector2(3.37, 3.55), Vector2(3.63, 3.63), Vector2(3.9, 3.68), Vector2(4.17, 3.7), Vector2(4.3, 3.7), Vector2(4.57, 3.68), Vector2(4.83, 3.65), Vector2(5.1, 3.6), Vector2(5.37, 3.55), Vector2(5.63, 3.48), Vector2(5.9, 3.39), Vector2(6.17, 3.28), Vector2(6.43, 3.15), Vector2(6.7, 3.0), Vector2(6.97, 2.82), Vector2(7.23, 2.62), Vector2(7.5, 2.4), Vector2(7.77, 2.15), Vector2(8.03, 1.88), Vector2(8.3, 1.58), Vector2(8.57, 1.26), Vector2(8.83, 0.92), Vector2(9.1, 0.55), Vector2(9.37, 0.16), Vector2(9.63, -0.26), Vector2(9.9, -0.7), Vector2(10.17, -1.16), Vector2(10.43, -1.65), Vector2(10.7, -2.16), Vector2(10.97, -2.7), Vector2(11.23, -3.26), Vector2(11.5, -3.85), Vector2(11.77, -4.45), Vector2(12.03, -5.08), Vector2(12.3, -5.74), Vector2(12.57, -6.42), Vector2(12.83, -7.12), Vector2(13.1, -7.85), Vector2(13.37, -8.6), Vector2(13.63, -9.38), Vector2(13.9, -10.18), Vector2(14.17, -11.0), Vector2(14.43, -11.85), Vector2(14.7, -12.72), Vector2(14.97, -13.62), Vector2(15.23, -14.54), Vector2(15.5, -15.48), Vector2(15.77, -16.45), Vector2(16.03, -17.44), Vector2(16.3, -18.44), Vector2(16.57, -19.44), Vector2(16.83, -20.44), Vector2(17.1, -21.44), Vector2(17.37, -22.44), Vector2(17.63, -23.44), Vector2(17.9, -24.44), Vector2(18.17, -25.44), Vector2(18.43, -26.44), Vector2(18.7, -27.44), Vector2(18.97, -28.44), Vector2(19.23, -29.44), Vector2(19.5, -30.44), Vector2(19.77, -31.44), Vector2(20.03, -32.44), Vector2(20.3, -33.44), Vector2(20.57, -34.44), Vector2(20.83, -35.44), Vector2(21.1, -36.44), Vector2(21.37, -37.44), Vector2(21.63, -38.44), Vector2(21.9, -39.44), Vector2(22.17, -40.44)],
	"run": [Vector2(0.0, 0.0), Vector2(0.33, 0.0), Vector2(0.87, 0.48), Vector2(1.4, 0.92), Vector2(1.93, 1.33), Vector2(2.47, 1.71), Vector2(3.0, 2.05), Vector2(3.53, 2.36), Vector2(4.07, 2.64), Vector2(4.6, 2.89), Vector2(5.13, 3.1), Vector2(5.67, 3.29), Vector2(6.2, 3.43), Vector2(6.73, 3.55), Vector2(7.27, 3.63), Vector2(7.8, 3.68), Vector2(8.33, 3.7), Vector2(8.6, 3.7), Vector2(9.13, 3.68), Vector2(9.67, 3.65), Vector2(10.2, 3.6), Vector2(10.73, 3.55), Vector2(11.27, 3.48), Vector2(11.8, 3.39), Vector2(12.33, 3.28), Vector2(12.87, 3.15), Vector2(13.4, 3.0), Vector2(13.93, 2.82), Vector2(14.47, 2.62), Vector2(15.0, 2.4), Vector2(15.53, 2.15), Vector2(16.07, 1.88), Vector2(16.6, 1.58), Vector2(17.13, 1.26), Vector2(17.67, 0.92), Vector2(18.2, 0.55), Vector2(18.73, 0.16), Vector2(19.27, -0.26), Vector2(19.8, -0.7), Vector2(20.33, -1.16), Vector2(20.87, -1.65), Vector2(21.4, -2.16), Vector2(21.93, -2.7), Vector2(22.47, -3.26), Vector2(23.0, -3.85), Vector2(23.53, -4.45), Vector2(24.07, -5.08), Vector2(24.6, -5.74), Vector2(25.13, -6.42), Vector2(25.67, -7.12), Vector2(26.2, -7.85), Vector2(26.73, -8.6), Vector2(27.27, -9.38), Vector2(27.8, -10.18), Vector2(28.33, -11.0), Vector2(28.87, -11.85), Vector2(29.4, -12.72), Vector2(29.93, -13.62), Vector2(30.47, -14.54), Vector2(31.0, -15.48), Vector2(31.53, -16.45), Vector2(32.07, -17.44), Vector2(32.6, -18.44), Vector2(33.13, -19.44), Vector2(33.67, -20.44), Vector2(34.2, -21.44), Vector2(34.73, -22.44), Vector2(35.27, -23.44), Vector2(35.8, -24.44), Vector2(36.33, -25.44), Vector2(36.87, -26.44), Vector2(37.4, -27.44), Vector2(37.93, -28.44), Vector2(38.47, -29.44), Vector2(39.0, -30.44), Vector2(39.53, -31.44), Vector2(40.07, -32.44), Vector2(40.6, -33.44), Vector2(41.13, -34.44), Vector2(41.67, -35.44), Vector2(42.2, -36.44), Vector2(42.73, -37.44), Vector2(43.27, -38.44), Vector2(43.8, -39.44), Vector2(44.33, -40.44)],
	"double": [Vector2(0.0, 0.0), Vector2(0.33, 0.0), Vector2(0.87, 0.48), Vector2(1.4, 0.92), Vector2(1.93, 1.33), Vector2(2.47, 1.71), Vector2(3.0, 2.05), Vector2(3.53, 2.36), Vector2(4.07, 2.64), Vector2(4.6, 2.89), Vector2(5.13, 3.1), Vector2(5.67, 3.29), Vector2(5.93, 3.36), Vector2(6.47, 3.9), Vector2(7.0, 4.42), Vector2(7.53, 4.95), Vector2(8.07, 5.48), Vector2(8.6, 6.0), Vector2(9.13, 6.52), Vector2(9.67, 7.02), Vector2(10.2, 7.49), Vector2(10.73, 7.92), Vector2(11.27, 8.32), Vector2(11.8, 8.69), Vector2(12.33, 9.02), Vector2(12.87, 9.32), Vector2(13.4, 9.59), Vector2(13.93, 9.83), Vector2(14.47, 10.03), Vector2(15.0, 10.2), Vector2(15.53, 10.34), Vector2(16.07, 10.45), Vector2(16.6, 10.52), Vector2(17.13, 10.56), Vector2(17.4, 10.57), Vector2(17.93, 10.56), Vector2(18.47, 10.54), Vector2(19.0, 10.51), Vector2(19.53, 10.47), Vector2(20.07, 10.41), Vector2(20.6, 10.34), Vector2(21.13, 10.25), Vector2(21.67, 10.14), Vector2(22.2, 10.0), Vector2(22.73, 9.85), Vector2(23.27, 9.66), Vector2(23.8, 9.46), Vector2(24.33, 9.23), Vector2(24.87, 8.97), Vector2(25.4, 8.69), Vector2(25.93, 8.39), Vector2(26.47, 8.06), Vector2(27.0, 7.71), Vector2(27.53, 7.34), Vector2(28.07, 6.94), Vector2(28.6, 6.52), Vector2(29.13, 6.07), Vector2(29.67, 5.6), Vector2(30.2, 5.11), Vector2(30.73, 4.59), Vector2(31.27, 4.05), Vector2(31.8, 3.48), Vector2(32.33, 2.89), Vector2(32.87, 2.28), Vector2(33.4, 1.64), Vector2(33.93, 0.98), Vector2(34.47, 0.29), Vector2(35.0, -0.42), Vector2(35.53, -1.15), Vector2(36.07, -1.91), Vector2(36.6, -2.69), Vector2(37.13, -3.49), Vector2(37.67, -4.32), Vector2(38.2, -5.18), Vector2(38.73, -6.05), Vector2(39.27, -6.95), Vector2(39.8, -7.88), Vector2(40.33, -8.83), Vector2(40.87, -9.8), Vector2(41.4, -10.8), Vector2(41.93, -11.8), Vector2(42.47, -12.8), Vector2(43.0, -13.8), Vector2(43.53, -14.8), Vector2(44.07, -15.8), Vector2(44.6, -16.8), Vector2(45.13, -17.8), Vector2(45.67, -18.8), Vector2(46.2, -19.8), Vector2(46.73, -20.8), Vector2(47.27, -21.8), Vector2(47.8, -22.8), Vector2(48.33, -23.8), Vector2(48.87, -24.8), Vector2(49.4, -25.8), Vector2(49.93, -26.8), Vector2(50.47, -27.8), Vector2(51.0, -28.8), Vector2(51.53, -29.8), Vector2(52.07, -30.8), Vector2(52.6, -31.8), Vector2(53.13, -32.8), Vector2(53.67, -33.8), Vector2(54.2, -34.8), Vector2(54.73, -35.8), Vector2(55.27, -36.8), Vector2(55.8, -37.8), Vector2(56.33, -38.8), Vector2(56.87, -39.8)],
	"long": [Vector2(0.0, 0.0), Vector2(0.33, 0.0), Vector2(1.17, 0.48), Vector2(2.0, 0.92), Vector2(2.83, 1.33), Vector2(3.66, 1.71), Vector2(4.49, 2.05), Vector2(5.33, 2.36), Vector2(6.16, 2.64), Vector2(6.99, 2.89), Vector2(7.82, 3.1), Vector2(8.65, 3.29), Vector2(9.49, 3.43), Vector2(10.32, 3.55), Vector2(11.15, 3.63), Vector2(11.98, 3.68), Vector2(12.81, 3.7), Vector2(13.23, 3.7), Vector2(14.06, 3.68), Vector2(14.89, 3.65), Vector2(15.73, 3.6), Vector2(16.56, 3.55), Vector2(17.39, 3.48), Vector2(18.22, 3.39), Vector2(19.05, 3.28), Vector2(19.89, 3.15), Vector2(20.72, 3.0), Vector2(21.55, 2.82), Vector2(22.38, 2.62), Vector2(23.21, 2.4), Vector2(24.05, 2.15), Vector2(24.88, 1.88), Vector2(25.71, 1.58), Vector2(26.54, 1.26), Vector2(27.37, 0.92), Vector2(28.21, 0.55), Vector2(29.04, 0.16), Vector2(29.87, -0.26), Vector2(30.7, -0.7), Vector2(31.53, -1.16), Vector2(32.37, -1.65), Vector2(33.2, -2.16), Vector2(34.03, -2.7), Vector2(34.86, -3.26), Vector2(35.69, -3.85), Vector2(36.53, -4.45), Vector2(37.36, -5.08), Vector2(38.19, -5.74), Vector2(39.02, -6.42), Vector2(39.85, -7.12), Vector2(40.69, -7.85), Vector2(41.52, -8.6), Vector2(42.35, -9.38), Vector2(43.18, -10.18), Vector2(44.01, -11.0), Vector2(44.85, -11.85), Vector2(45.68, -12.72), Vector2(46.51, -13.62), Vector2(47.34, -14.54), Vector2(48.17, -15.48), Vector2(49.01, -16.45), Vector2(49.84, -17.44), Vector2(50.67, -18.44), Vector2(51.5, -19.44), Vector2(52.33, -20.44), Vector2(53.17, -21.44), Vector2(54.0, -22.44), Vector2(54.83, -23.44), Vector2(55.66, -24.44), Vector2(56.49, -25.44), Vector2(57.33, -26.44), Vector2(58.16, -27.44), Vector2(58.99, -28.44), Vector2(59.82, -29.44), Vector2(60.65, -30.44), Vector2(61.49, -31.44), Vector2(62.32, -32.44), Vector2(63.15, -33.44), Vector2(63.98, -34.44), Vector2(64.81, -35.44), Vector2(65.65, -36.44), Vector2(66.48, -37.44), Vector2(67.31, -38.44), Vector2(68.14, -39.44), Vector2(68.97, -40.44)],
}

const LABELS := {"walk": "Walk jump", "run": "Run jump", "double": "Double jump", "long": "Long (dash) jump"}
const COLORS := {"walk": Color(0.4, 1.0, 0.4), "run": Color(0.3, 0.8, 1.0), "double": Color(1.0, 0.8, 0.2), "long": Color(1.0, 0.4, 1.0)}


static func apex(kind: String) -> float:
	var best := 0.0
	for p in ARCS.get(kind, []):
		best = maxf(best, p.y)
	return best


static func reach_at(kind: String, height_delta: float) -> float:
	"""Farthest horizontal distance at which the arc is still at or above
	height_delta (target top minus takeoff). -1 if never reachable."""
	var best := -1.0
	var arc: Array = ARCS.get(kind, [])
	for i in range(arc.size()):
		var p: Vector2 = arc[i]
		if p.y >= height_delta:
			best = p.x
			# interpolate to the crossing with the next (lower) sample
			if i + 1 < arc.size():
				var q: Vector2 = arc[i + 1]
				if q.y < height_delta and p.y != q.y:
					best = lerpf(p.x, q.x, (p.y - height_delta) / (p.y - q.y))
	return best


static func best_move(gap: float, height_delta: float) -> String:
	"""Easiest move that clears a gap (edge to edge) to a target height."""
	for k in ["walk", "run", "double", "long"]:
		if reach_at(k, height_delta) >= gap:
			return k
	return ""

