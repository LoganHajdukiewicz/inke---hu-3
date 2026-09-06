extends Object
class_name PunkTheme

## GRAFFITI / PUNK UI THEME — one place for every menu's look.
## Aesthetic: night asphalt + spray-paint neons, stencil-caps type,
## skewed "slapped-on sticker" panels, zero rounded corporate corners.

# ── Palette ────────────────────────────────────────────────────────────────
const ASPHALT      := Color(0.055, 0.05, 0.07, 0.97)   # Panel bg (near black)
const ASPHALT_LIGHT:= Color(0.11, 0.10, 0.13, 1.0)     # Cards / rows
const CONCRETE     := Color(0.16, 0.15, 0.18, 1.0)     # Hover rows
const PINK         := Color(1.0, 0.18, 0.53)           # Hot spray pink (primary)
const GREEN        := Color(0.67, 1.0, 0.0)            # Toxic green (success/afford)
const YELLOW       := Color(1.0, 0.87, 0.12)           # Caution-tape yellow (currency)
const CYAN         := Color(0.25, 0.9, 1.0)            # Chrome-tag cyan (info)
const RED          := Color(1.0, 0.25, 0.2)            # Danger red
const PAPER        := Color(0.92, 0.9, 0.85)           # Wheatpaste paper
const INK          := Color(0.1, 0.09, 0.11)           # Marker ink
const DIM          := Color(0.55, 0.53, 0.6)           # De-emphasized text

# ── Panels ─────────────────────────────────────────────────────────────────

## Main menu panel: black asphalt, thick neon border, slapped-on skew.
static func panel(border: Color = PINK, skew_x: float = 0.06) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = ASPHALT
	s.border_color = border
	s.set_border_width_all(3)
	# Punk = no rounded corners. One corner clipped like a torn sticker.
	s.set_corner_radius_all(0)
	s.corner_radius_top_right = 18
	s.skew = Vector2(skew_x, 0.0)
	s.shadow_size = 18
	s.shadow_color = Color(0, 0, 0, 0.65)
	s.shadow_offset = Vector2(6, 8)
	return s

## Row/card: flat dark chip with a colored left "spray stripe".
static func card(selected: bool = false, accent: Color = PINK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CONCRETE if selected else ASPHALT_LIGHT
	s.border_color = accent if selected else Color(0.28, 0.26, 0.32)
	s.border_width_left = 8 if selected else 4
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_width_right = 2
	s.set_corner_radius_all(0)
	s.corner_radius_bottom_right = 10
	s.skew = Vector2(0.03, 0.0)
	return s

## Wheatpaste poster (dialogue): aged paper, marker-ink border, slight tilt.
static func poster() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PAPER
	s.border_color = INK
	s.set_border_width_all(3)
	s.set_corner_radius_all(0)
	s.corner_radius_top_left = 14
	s.skew = Vector2(-0.02, 0.0)
	s.shadow_size = 12
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_offset = Vector2(4, 6)
	return s

## Button styleboxes (normal / hover / pressed / focus)
static func style_button(btn: Button, accent: Color = PINK, font_size: int = 22):
	var normal := StyleBoxFlat.new()
	normal.bg_color = ASPHALT_LIGHT
	normal.border_color = accent
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(0)
	normal.corner_radius_bottom_right = 12
	normal.skew = Vector2(0.08, 0.0)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	
	var hover := normal.duplicate()
	hover.bg_color = CONCRETE
	hover.set_border_width_all(3)
	
	var pressed := normal.duplicate()
	pressed.bg_color = accent
	
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = YELLOW
	focus.set_border_width_all(2)
	focus.skew = Vector2(0.08, 0.0)
	focus.set_corner_radius_all(0)
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", Color(0.95, 0.94, 0.98))
	btn.add_theme_color_override("font_hover_color", accent)
	btn.add_theme_color_override("font_pressed_color", ASPHALT)
	btn.add_theme_color_override("font_focus_color", Color(0.95, 0.94, 0.98))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_constant_override("outline_size", 0)
	# STENCIL CAPS - graffiti never does lowercase
	btn.text = btn.text.to_upper()

## Headline label: stencil caps + hard offset shadow (spray drop-shadow).
static func style_headline(lbl: Label, color: Color = PINK, size: int = 40):
	lbl.text = lbl.text.to_upper()
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 4)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))

## Tag underline: a hand-drawn-looking colored strike under headers.
static func tag_underline(parent: Control, color: Color = PINK, width: float = 220.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 5)
	r.rotation_degrees = -1.2
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(r)
	return r
