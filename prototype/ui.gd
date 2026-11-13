class_name UI
extends RefCounted

# Charte « Wii » — specs_artistiques.md §7.
# Palette, styles, icônes de dés vectorielles : tout est généré en code.

# ---- Palette ----
const BG := Color("#EEF2F7")            # ivoire bleuté
const PANEL := Color("#FFFFFF")
const EDGE := Color("#DDE3EB")          # bordures claires
const EDGE_DK := Color("#D3D9E1")       # biseau inférieur boutons
const INK := Color("#3C4048")           # texte (jamais de noir pur)
const DIM := Color("#8A919E")           # secondaire
const BLUE := Color("#2FA8D8")          # bleu Wii — accent principal
const BLUE_HI := Color("#55C8EC")
const BLUE_DK := Color("#1E86B0")
const ORANGE := Color("#FF9D3C")        # badge tour / timer
const ORANGE_DK := Color("#DE8A2E")
const RED := Color("#F25C54")           # Dudo
const RED_DK := Color("#D94A42")
const GREEN := Color("#67BB45")         # Calza / concordances
const GREEN_DK := Color("#55A738")
const AMBER := Color("#FFC94D")
# Couleurs joueur façon Wii (P1..P6 par siège).
const PLAYER: Array[Color] = [Color("#2E8BE6"), Color("#E64A3C"), Color("#3FAF49"),
	Color("#F5C518"), Color("#8E5BB5"), Color("#F28C28")]
const PIP := Color("#232B40")           # pips des dés

const FONT_UI := "res://assets/fonts/Nunito.ttf"
const FONT_DISP := "res://assets/fonts/Fredoka.ttf"
static var _f_ui: Font
static var _f_disp: Font

static func font() -> Font:
	if _f_ui == null:
		_f_ui = load(FONT_UI)
	return _f_ui

static func font_disp() -> Font:
	if _f_disp == null:
		_f_disp = load(FONT_DISP)
	return _f_disp

# FontVariation à un poids donné (fonts variables, axe wght).
static func font_w(wght: int, disp := false) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = font_disp() if disp else font()
	fv.variation_opentype = {"wght": wght}
	return fv

# StyleBox « soft plastic » : fond plat, bordure claire, biseau inférieur dur
# (ombre nette décalée, pas un glow).
static func sb(bg: Color, border: Color = EDGE, radius := 18, bw := 1, bevel := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if bevel > 0:
		# Biseau inférieur : teinte sombre de la variante si la bordure n'est
		# pas dessinée (bw=0), sinon gris foncé translucide — jamais blanc.
		s.shadow_color = border if bw == 0 else Color(0.16, 0.19, 0.26, 0.35)
		s.shadow_size = 1
		s.shadow_offset = Vector2(0, bevel)
	return s

static func _btn_colors(b: Button, c: Color) -> void:
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c)
	b.add_theme_color_override("font_pressed_color", c.darkened(0.15))
	b.add_theme_color_override("font_disabled_color", Color(c, 0.5))

# Bouton Wii par variante : primary (bleu), btn (blanc), dudo (rouge), calza (vert).
static func button(text: String, kind := "btn") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_w(800))
	b.add_theme_font_size_override("font_size", 26)
	var n: StyleBoxFlat
	match kind:
		"primary":
			n = sb(BLUE, BLUE_DK, 18, 0, 3)
			_btn_colors(b, Color.WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))
			b.add_theme_stylebox_override("hover", sb(BLUE_HI, BLUE_DK, 18, 0, 3))
			b.add_theme_stylebox_override("pressed", sb(BLUE_DK, BLUE_DK, 18, 0, 1))
		"dudo":
			n = sb(RED, RED_DK, 18, 0, 3)
			_btn_colors(b, Color.WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))
			b.add_theme_stylebox_override("hover", sb(RED.lightened(0.08), RED_DK, 18, 0, 3))
			b.add_theme_stylebox_override("pressed", sb(RED_DK, RED_DK, 18, 0, 1))
		"calza":
			n = sb(GREEN, GREEN_DK, 18, 0, 3)
			_btn_colors(b, Color.WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))
			b.add_theme_stylebox_override("hover", sb(GREEN.lightened(0.08), GREEN_DK, 18, 0, 3))
			b.add_theme_stylebox_override("pressed", sb(GREEN_DK, GREEN_DK, 18, 0, 1))
		_: # btn blanc
			n = sb(Color("#F5F7FA"), EDGE, 18, 1, 3)
			_btn_colors(b, INK)
			b.add_theme_stylebox_override("hover", sb(PANEL, BLUE, 18, 2, 3))
			b.add_theme_stylebox_override("pressed", sb(EDGE, EDGE, 18, 1, 1))
	b.add_theme_stylebox_override("normal", n)
	var dis := sb(Color(n.bg_color, 0.5), n.border_color, 18, n.get_border_width_min(), 3)
	b.add_theme_stylebox_override("disabled", dis)
	b.custom_minimum_size = Vector2(0, 56)
	return b

# Pill de label (badges, chips joueur, toasts).
static func pill(text: String, bg: Color, fg: Color, size := 20, wght := 800) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_w(wght))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fg)
	l.add_theme_stylebox_override("normal", sb(bg, bg, 20, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# Chip joueur à la couleur Wii de son siège (pseudo blanc).
static func player_chip(name: String, seat: int, size := 18) -> Label:
	return pill(name, PLAYER[seat % PLAYER.size()] if seat >= 0 else DIM, Color.WHITE, size)

# disp=true → Fredoka (titres/badges/chiffres), sinon Nunito.
static func label(text: String, size := 22, color: Color = INK, wght := 600, disp := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_w(wght, disp))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# Panneau blanc : bordure claire + vraie ombre portée (lisible sur scène claire).
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var s := sb(PANEL, EDGE, 20, 1)
	s.shadow_color = Color(0.16, 0.19, 0.26, 0.3)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", s)
	return p

# JSON : une clé présente à null ne prend PAS le défaut de Dictionary.get,
# et « x or [] » renvoie un bool en GDScript — d'où ces gardes.
static func arr(v: Variant) -> Array:
	return v if v is Array else []

static func obj(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

# Orbe pastel : disque blanc à dégradé radial, teinté via modulate
# (permet de changer la couleur à l'exécution — ex. halo du titre Dudo/Calza).
static func orb(col: Color, radius := 300.0) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = int(radius * 2)
	gt.height = int(radius * 2)
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.modulate = col
	tr.custom_minimum_size = Vector2(radius * 2, radius * 2)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# ---- Dots : trame de pois discrets façon fond Wii ----
class Dots:
	extends Control
	var spacing := 34.0
	var radius := 2.2
	var col := Color(0.24, 0.25, 0.28, 0.07)

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sz := size
		for x in range(0, int(sz.x) + int(spacing), int(spacing)):
			for y in range(0, int(sz.y) + int(spacing), int(spacing)):
				draw_circle(Vector2(x, y), radius, col)

# ---- CircleBadge : pastille circulaire colorée + chiffre blanc ----
# (compte de dés par joueur — couleur du siège, façon badge Wii)
class CircleBadge:
	extends Control
	var text := ""
	var col := BLUE
	var side := 40.0

	func _init(t := "", c := BLUE, s := 40.0) -> void:
		text = t
		col = c
		side = s
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_text(t: String) -> void:
		text = t
		queue_redraw()

	func _draw() -> void:
		var r := side / 2.0
		var c := Vector2(r, r)
		draw_circle(c, r, col)
		draw_arc(c, r - 2.0, 0.0, TAU, 40, Color.WHITE, 3.0, true)
		var f := UI.font_w(700, true)
		var fs := int(side * 0.52)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, Vector2(r - ts.x / 2.0, r + ts.y * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

# ---- DieIcon : face de dé blanche + pips encres ----
class DieIcon:
	extends Control
	var value := 1
	var size_px := 44
	var die_bg := Color("#FFFFFF")
	var pip := PIP
	var glow := false  # surbrillance : face verte, pips blancs (dé concordant)
	var sel := false   # anneau bleu (sélecteur de face)

	func _init(v := 1, s := 44) -> void:
		value = v
		size_px = s
		custom_minimum_size = Vector2(s, s)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(size_px, size_px))
		if sel:
			draw_rect(r.grow(4), BLUE, false, 3.0, true)
		var face_col := die_bg
		var pip_col := pip
		var edge_col := EDGE
		if glow:
			face_col = GREEN
			pip_col = Color.WHITE
			edge_col = GREEN_DK
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = face_col
		sbx.border_color = edge_col
		sbx.set_border_width_all(1)
		sbx.set_corner_radius_all(int(size_px * 0.22))
		sbx.shadow_color = edge_col.darkened(0.2)
		sbx.shadow_size = 1
		sbx.shadow_offset = Vector2(0, 3)
		sbx.draw(get_canvas_item(), r)
		var pip_r := size_px * 0.085
		var q := size_px / 4.0
		var pos := {
			1: [Vector2(2, 2) * q],
			2: [Vector2(1, 1) * q, Vector2(3, 3) * q],
			3: [Vector2(1, 1) * q, Vector2(2, 2) * q, Vector2(3, 3) * q],
			4: [Vector2(1, 1) * q, Vector2(3, 1) * q, Vector2(1, 3) * q, Vector2(3, 3) * q],
			5: [Vector2(1, 1) * q, Vector2(3, 1) * q, Vector2(2, 2) * q, Vector2(1, 3) * q, Vector2(3, 3) * q],
			6: [Vector2(1, 1) * q, Vector2(3, 1) * q, Vector2(1, 2) * q, Vector2(3, 2) * q, Vector2(1, 3) * q, Vector2(3, 3) * q],
		}
		for p in pos.get(clampi(value, 1, 6), pos[1]):
			draw_circle(p, pip_r, pip_col)
