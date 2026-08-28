class_name BossHealthBar
extends CanvasLayer

## Big named boss health bar pinned to the bottom of the screen.
## Created automatically by Enemy when `is_boss` is ticked - all look &
## feel (colors, size, name, font size, show range, damage ghost) comes
## from the boss's own Inspector exports, so every boss can style its bar.

var boss: Node = null   # The Enemy that owns this bar

var _root: Control
var _name_label: Label
var _bg: ColorRect
var _fill: ColorRect
var _ghost: ColorRect          # Delayed white damage trail
var _shown: bool = false
var _last_health: int = -1
var _ghost_tween: Tween = null


func setup(owner_enemy: Node) -> void:
	boss = owner_enemy


func _ready() -> void:
	layer = 42   # Above the quest HUD (40), below pause menus
	
	var bar_w: float = boss.boss_bar_width
	var bar_h: float = boss.boss_bar_height
	
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_root.offset_left = -bar_w * 0.5
	_root.offset_right = bar_w * 0.5
	_root.offset_top = -(bar_h + 78.0)
	_root.offset_bottom = -40.0
	_root.modulate.a = 0.0
	add_child(_root)
	
	# Name above the bar
	_name_label = Label.new()
	_name_label.text = boss.boss_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", boss.boss_name_font_size)
	_name_label.add_theme_color_override("font_color", boss.boss_name_color)
	_name_label.add_theme_constant_override("outline_size", 10)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.offset_bottom = 38
	_root.add_child(_name_label)
	
	# Bar background
	_bg = ColorRect.new()
	_bg.color = boss.boss_bar_bg_color
	_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bg.offset_top = -bar_h
	_root.add_child(_bg)
	
	# Damage ghost (sits between bg and fill)
	if boss.boss_bar_damage_ghost:
		_ghost = ColorRect.new()
		_ghost.color = Color(1, 1, 1, 0.65)
		_ghost.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_ghost.offset_top = -bar_h + 3
		_ghost.offset_bottom = -3
		_ghost.offset_left = 3
		_ghost.offset_right = -3
		_bg.add_child(_ghost)
		_ghost.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_ghost.position = Vector2(3, 3)
		_ghost.size = Vector2(bar_w - 6, bar_h - 6)
	
	# Fill
	_fill = ColorRect.new()
	_fill.color = boss.boss_bar_color
	_bg.add_child(_fill)
	_fill.position = Vector2(3, 3)
	_fill.size = Vector2(bar_w - 6, bar_h - 6)
	
	_last_health = boss.current_health


func _process(_delta: float) -> void:
	if not boss or not is_instance_valid(boss):
		dismiss()
		return
	
	# Show/hide based on player distance (0 = always visible)
	var want_shown := true
	if boss.boss_bar_show_range > 0.0:
		var players = get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			want_shown = players[0].global_position.distance_to(boss.global_position) <= boss.boss_bar_show_range
		else:
			want_shown = false
	
	if want_shown != _shown:
		_shown = want_shown
		var t = create_tween()
		t.tween_property(_root, "modulate:a", 1.0 if _shown else 0.0, 0.35)
	
	# Track health
	if boss.current_health != _last_health:
		_on_health_changed(boss.current_health)
		_last_health = boss.current_health


func _on_health_changed(health: int) -> void:
	var frac: float = clampf(float(health) / float(maxi(boss.max_health, 1)), 0.0, 1.0)
	var inner_w: float = boss.boss_bar_width - 6.0
	
	# Fill snaps immediately
	_fill.size.x = inner_w * frac
	
	# Ghost trails behind after a beat
	if _ghost:
		if _ghost_tween and _ghost_tween.is_valid():
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.35)
		_ghost_tween.tween_property(_ghost, "size:x", inner_w * frac, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Hit shake
	var shake = create_tween()
	shake.tween_property(_root, "position", Vector2(6, 0), 0.04)
	shake.tween_property(_root, "position", Vector2(-4, 0), 0.04)
	shake.tween_property(_root, "position", Vector2.ZERO, 0.06)


func dismiss() -> void:
	"""Fade out and free (called when the boss dies)."""
	set_process(false)
	# Survive the boss being freed: hop off the dying enemy onto the tree root
	if boss and is_instance_valid(boss) and get_parent() == boss:
		var tree_root = boss.get_tree().root
		boss.remove_child(self)
		tree_root.add_child(self)
	boss = null
	if _root:
		var t = create_tween()
		t.tween_property(_root, "modulate:a", 0.0, 0.6)
		t.tween_callback(queue_free)
	else:
		queue_free()
