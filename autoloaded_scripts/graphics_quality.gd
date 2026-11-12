extends Node
## GRAPHICS QUALITY + FPS GUARD
## One place that decides how expensive the game looks.
##
## Presets (pause menu ▸ CONTROLS tab ▸ Graphics, or `GraphicsQuality.set_preset()`):
##   LOW    - no shadows, no glow/SSAO, simple sky ambient, 75% render scale,
##            small decorative lights off, short draw distance
##   MEDIUM - sun shadows (short range, soft off), glow on, no SSAO,
##            decorative lights on, full render scale
##   HIGH   - everything on (what the scenes are authored with)
##   AUTO   - (default) starts at MEDIUM and the FPS GUARD steps quality DOWN
##            when the frame rate stays under min_fps, and back UP when there
##            is lots of headroom. Render scale is the fine-grained knob.
##
## Applies to every scene automatically (WorldEnvironment, lights, camera)
## when it loads, and to anything spawned later.

enum Preset { LOW, MEDIUM, HIGH, AUTO }

## Target minimum frame rate the guard defends.
@export var min_fps: float = 40.0
## Above this with no struggle for a while, the guard raises quality.
@export var comfy_fps: float = 75.0

const SETTINGS_PATH := "user://graphics.cfg"

var preset: int = Preset.AUTO
var _level: int = 1            # effective level 0=low 1=med 2=high while AUTO
var _scale: float = 1.0        # effective 3D render scale
var _fps_avg: float = 60.0
var _low_time := 0.0
var _high_time := 0.0
var _cooldown := 3.0           # seconds to wait after a change / scene load
var _scene: Node = null
var _env_defaults := {}        # Environment -> {glow, ssao, sdfgi, ...} authored values

signal quality_changed(level: int, render_scale: float)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	get_tree().node_added.connect(_on_node_added)
	_level = _start_level()
	_apply_viewport()


func _start_level() -> int:
	match preset:
		Preset.LOW: return 0
		Preset.HIGH: return 2
		_:
			# Software renderer / integrated GPU heuristic: start LOW
			var adapter := RenderingServer.get_video_adapter_name().to_lower()
			if adapter.contains("llvmpipe") or adapter.contains("swiftshader") or adapter.contains("software"):
				return 0
			return 1


func set_preset(p: int) -> void:
	preset = p
	_level = _start_level()
	_scale = 1.0 if _level > 0 else 0.75
	_save()
	_apply_all()


func get_preset() -> int:
	return preset


func effective_level() -> int:
	return _level


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var fps := 1.0 / delta
	_fps_avg = lerpf(_fps_avg, fps, clampf(delta * 2.0, 0.0, 1.0))
	if get_tree().current_scene != _scene:
		_scene = get_tree().current_scene
		_cooldown = 3.0
		_apply_all()
		return
	if preset != Preset.AUTO or get_tree().paused:
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	if _fps_avg < min_fps:
		_low_time += delta
		_high_time = 0.0
		if _low_time > 1.5:
			_low_time = 0.0
			_step_down()
	elif _fps_avg > comfy_fps:
		_high_time += delta
		_low_time = 0.0
		if _high_time > 8.0:
			_high_time = 0.0
			_step_up()
	else:
		_low_time = 0.0
		_high_time = 0.0


func _step_down() -> void:
	# Render scale first (cheapest visual loss), then features
	if _scale > 0.76:
		_scale = 0.75
	elif _level > 0:
		_level -= 1
		_scale = 0.9 if _level > 0 else 0.75
	elif _scale > 0.6:
		_scale = 0.6
	elif _scale > 0.5:
		_scale = 0.5
	else:
		return
	_cooldown = 2.5
	_apply_all()
	print("GraphicsQuality: FPS %.0f < %.0f -> level %d, render scale %.2f" % [_fps_avg, min_fps, _level, _scale])


func _step_up() -> void:
	if _scale < 0.99 and (_level == 0 or _scale < 0.9):
		_scale = minf(_scale + 0.15, 1.0)
	elif _level < 2:
		_level += 1
		_scale = 1.0
	else:
		return
	_cooldown = 6.0
	_apply_all()
	print("GraphicsQuality: headroom (FPS %.0f) -> level %d, render scale %.2f" % [_fps_avg, _level, _scale])


# ---------------------------------------------------------------------------
func _apply_all() -> void:
	_apply_viewport()
	var root := get_tree().current_scene
	if root == null:
		return
	for n in root.find_children("*", "WorldEnvironment", true, false):
		_apply_env(n)
	for n in root.find_children("*", "Light3D", true, false):
		_apply_light(n)
	quality_changed.emit(_level, _scale)


func _on_node_added(n: Node) -> void:
	# Any primitive mesh anywhere (enemies, HU3, pickups, debris...) gets a
	# sane tessellation: Godot's Sphere/Cylinder defaults are 64 segments.
	if n is MeshInstance3D:
		_cap_mesh.call_deferred(n)
	# New lights/environments (barrels, room lights, spawned stuff) follow suit
	if n is Light3D:
		_apply_light.call_deferred(n)
	elif n is WorldEnvironment:
		_apply_env.call_deferred(n)


func _cap_mesh(m: MeshInstance3D) -> void:
	if is_instance_valid(m) and m.mesh is PrimitiveMesh and not Engine.is_editor_hint():
		m.mesh = MeshMerge._low_poly(m.mesh)


func _apply_viewport() -> void:
	var vp := get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _scale
	vp.msaa_3d = Viewport.MSAA_DISABLED if _level < 2 else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if _level == 0 else Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_shadow_atlas_set_size(1024 if _level == 0 else (2048 if _level == 1 else 4096), true)


func _apply_env(we: WorldEnvironment) -> void:
	if not is_instance_valid(we) or we.environment == null:
		return
	var e := we.environment
	if not _env_defaults.has(e):
		_env_defaults[e] = {"glow": e.glow_enabled, "ssao": e.ssao_enabled, "ssil": e.ssil_enabled,
			"sdfgi": e.sdfgi_enabled, "ssr": e.ssr_enabled, "fog": e.volumetric_fog_enabled,
			"amb": e.ambient_light_source, "refl": e.reflected_light_source}
	var d: Dictionary = _env_defaults[e]
	e.glow_enabled = d.glow and _level >= 1
	e.ssao_enabled = d.ssao and _level >= 2
	e.ssil_enabled = d.ssil and _level >= 2
	e.sdfgi_enabled = d.sdfgi and _level >= 2
	e.ssr_enabled = d.ssr and _level >= 2
	e.volumetric_fog_enabled = d.fog and _level >= 2
	# The sky is still DRAWN at low; it just stops being sampled for
	# per-pixel ambient + reflections (a big cost on weak GPUs).
	if _level == 0:
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		if e.ambient_light_color == Color(0, 0, 0, 1):
			e.ambient_light_color = Color(0.55, 0.5, 0.62)
		e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	else:
		e.ambient_light_source = d.amb
		e.reflected_light_source = d.refl


func _apply_light(l: Light3D) -> void:
	if not is_instance_valid(l):
		return
	if not l.has_meta("_gq_shadow"):
		l.set_meta("_gq_shadow", l.shadow_enabled)
		l.set_meta("_gq_visible", l.visible)
	var authored_shadow: bool = l.get_meta("_gq_shadow")
	if l is DirectionalLight3D:
		var dl := l as DirectionalLight3D
		dl.shadow_enabled = authored_shadow and _level >= 1
		if _level == 1:
			dl.directional_shadow_max_distance = minf(dl.directional_shadow_max_distance, 60.0)
			dl.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			dl.shadow_blur = 0.0
	else:
		# Small decorative omni/spot lights (barrel warnings, room bulbs):
		# off at LOW, no shadows below HIGH, fade with distance at MEDIUM
		l.shadow_enabled = authored_shadow and _level >= 2
		l.visible = bool(l.get_meta("_gq_visible")) and _level >= 1
		l.distance_fade_enabled = _level < 2
		l.distance_fade_begin = 30.0
		l.distance_fade_length = 10.0


# ---------------------------------------------------------------------------
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		preset = int(cf.get_value("graphics", "preset", Preset.AUTO))
		min_fps = float(cf.get_value("graphics", "min_fps", min_fps))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", preset)
	cf.set_value("graphics", "min_fps", min_fps)
	cf.save(SETTINGS_PATH)
