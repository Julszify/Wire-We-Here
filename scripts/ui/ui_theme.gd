class_name UiTheme
extends RefCounted
## Spielzeug-Look für Anzeige und Tablet: runde, kräftige Flächen mit weichem Schatten, Pillen-Knöpfe,
## runde Schrift. Alle Farben und Formen an einer Stelle, damit HUD, Tablet und Meldungen gleich aussehen.

# Farben (Wolkig-Blau als Hauptfarbe, dazu kräftige Spielzeug-Töne)
const INK := Color(0.16, 0.19, 0.27)          # dunkle Schrift
const INK_SOFT := Color(0.38, 0.43, 0.52)     # Nebentext
const PAPER := Color(0.97, 0.98, 1.0)         # helle Flächen
const PAPER_DIM := Color(0.9, 0.93, 0.97)     # Zeilen, Felder
const BLUE := Color(0.18, 0.47, 0.9)          # Wolkig-Blau
const BLUE_DARK := Color(0.11, 0.32, 0.68)
const GREEN := Color(0.27, 0.74, 0.39)        # kaufen, ok
const GREEN_DARK := Color(0.17, 0.53, 0.27)
const YELLOW := Color(1.0, 0.8, 0.18)         # Geld
const YELLOW_DARK := Color(0.82, 0.58, 0.05)
const RED := Color(0.93, 0.33, 0.28)          # Warnung, gesperrt
const PURPLE := Color(0.55, 0.38, 0.9)        # Ruf, Auftrag
const GREY := Color(0.78, 0.81, 0.86)         # nicht möglich

static var _font: Font
static var _bold: Font


## Runde Schrift: erste vorhandene aus der Liste (macOS hat Arial Rounded), sonst die Godot-Schrift
static func font(bold := true) -> Font:
	if bold and _bold:
		return _bold
	if not bold and _font:
		return _font
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Nunito", "Varela Round", "Arial Rounded MT Bold", "Quicksand", "Helvetica Neue", "Arial"])
	f.font_weight = 800 if bold else 600
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	if bold:
		_bold = f
	else:
		_font = f
	return f


## Fläche mit runden Ecken, dickem Rand und weichem Schatten nach unten
static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 18, border_w := 0, shadow := 6, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	if shadow > 0:
		s.shadow_color = Color(0.05, 0.08, 0.15, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.6)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


## Pillen-Knopf in einer Farbe: unten dunklerer Rand („Spielzeug-Taste“), beim Drücken eingedrückt
static func style_button(b: Button, color: Color, dark: Color, text_color := Color.WHITE, size := 18) -> void:
	var normal := box(color, dark, 22, 0, 0, 10)
	normal.border_width_bottom = 5
	normal.border_color = dark
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.08)
	pressed.border_width_bottom = 1
	pressed.content_margin_top = 14
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = GREY
	disabled.border_color = GREY.darkened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, text_color)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))


## Reiter-Knopf: aktiv kräftig, sonst hell
static func style_tab(b: Button, active: bool) -> void:
	if active:
		style_button(b, BLUE, BLUE_DARK, Color.WHITE, 18)
	else:
		style_button(b, PAPER_DIM, GREY, INK_SOFT, 18)


static func style_label(l: Label, size := 18, color := INK, bold := true) -> void:
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


## Schrift für Anzeigen über der Spielwelt: weiß mit dicker dunkler Kontur
static func style_hud_label(l: Label, size := 20, color := Color.WHITE) -> void:
	style_label(l, size, color, true)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.1, 0.18))
	l.add_theme_constant_override("outline_size", 7)


## Feld hinter einer HUD-Anzeige (halbtransparent, rund)
static func hud_box(tint := Color(0.1, 0.13, 0.22, 0.55), radius := 16) -> StyleBoxFlat:
	var s := box(tint, Color(1, 1, 1, 0.25), radius, 2, 0, 10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	return s
