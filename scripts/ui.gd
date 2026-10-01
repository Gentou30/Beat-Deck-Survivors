class_name Ui
extends RefCounted
## Tiny immediate-mode UI: draw buttons/cards each frame, register their rects,
## and resolve clicks against last frame's registrations.

const W := 1280.0
const H := 720.0

var font: Font
var buttons: Array = []  # {id, rect}
var mouse := Vector2.ZERO
var time := 0.0
var touch := false
var _hover_id := ""

func begin(c: Control, delta: float) -> void:
	time += delta
	buttons.clear()
	_hover_id = ""
	mouse = c.get_local_mouse_position()

func hit(pos: Vector2) -> String:
	for i in range(buttons.size() - 1, -1, -1):
		if (buttons[i]["rect"] as Rect2).has_point(pos):
			return buttons[i]["id"]
	return ""

func is_hover(id: String) -> bool:
	return _hover_id == id

func _reg(id: String, rect: Rect2) -> bool:
	buttons.append({"id": id, "rect": rect})
	var h := rect.has_point(mouse)
	if h:
		_hover_id = id
	return h

func text(c: Control, s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	c.draw_string(font, pos + Vector2(1, 1), s, align, width, size, Color(0, 0, 0, col.a * 0.6))
	c.draw_string(font, pos, s, align, width, size, col)

func center(c: Control, s: String, y: float, size: int, col: Color) -> void:
	text(c, s, Vector2(0, y), size, col, HORIZONTAL_ALIGNMENT_CENTER, W)

func panel(c: Control, r: Rect2, fill := Color(0.08, 0.07, 0.13, 0.92), border := Color(0.5, 0.45, 0.8, 0.8), bw := 2.0) -> void:
	c.draw_rect(Rect2(r.position + Vector2(4, 5), r.size), Color(0, 0, 0, 0.4))
	c.draw_rect(r, fill)
	c.draw_rect(r, border, false, bw)

func button(c: Control, id: String, r: Rect2, label: String, enabled := true, accent := Color(0.55, 0.5, 0.95), size := 24) -> void:
	var h := _reg(id, r) and enabled
	var pulse := 0.5 + 0.5 * sin(time * 6.0)
	var rr := r
	if h:
		rr = r.grow(3.0)
	var fill := Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.95)
	if h:
		fill = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.98)
	if not enabled:
		fill = Color(0.15, 0.15, 0.18, 0.9)
	c.draw_rect(Rect2(rr.position + Vector2(3, 4), rr.size), Color(0, 0, 0, 0.45))
	c.draw_rect(rr, fill)
	var bc := accent if enabled else Color(0.4, 0.4, 0.45)
	if h:
		bc = bc.lerp(Color.WHITE, 0.35 + 0.25 * pulse)
	c.draw_rect(rr, bc, false, 3.0 if h else 2.0)
	var col := Color.WHITE if enabled else Color(0.55, 0.55, 0.6)
	c.draw_string(font, Vector2(rr.position.x, rr.position.y + rr.size.y / 2.0 + size * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, size, col)

func bar(c: Control, r: Rect2, frac: float, fill: Color, back := Color(0.12, 0.06, 0.1)) -> void:
	c.draw_rect(r, back)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), fill)
	c.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)

func slider(c: Control, id: String, r: Rect2, frac: float, accent := Color(0.55, 0.5, 0.95)) -> void:
	_reg(id, r.grow_individual(0, 10, 0, 10))
	c.draw_rect(r, Color(0.12, 0.12, 0.2))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), accent)
	c.draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
	var kx := r.position.x + r.size.x * frac
	c.draw_rect(Rect2(kx - 6, r.position.y - 6, 12, r.size.y + 12), Color.WHITE)

## Draws a card. Returns true if hovered. `sel` highlights it.
func card(c: Control, id: String, r: Rect2, key: String, usable := true, sel := false, reg_id := "") -> bool:
	var d: Dictionary = Cards.def(id)
	var h := false
	if reg_id != "":
		h = _reg(reg_id, r)
	var rr := r
	if h and usable:
		rr = Rect2(r.position + Vector2(0, -14), r.size)
	var col: Color = d["color"]
	var dim := 1.0 if usable else 0.45
	c.draw_rect(Rect2(rr.position + Vector2(4, 6), rr.size), Color(0, 0, 0, 0.45))
	c.draw_rect(rr, Color(0.1, 0.09, 0.16, 0.97))
	c.draw_rect(Rect2(rr.position, Vector2(rr.size.x, 36)), Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, dim))
	var bcol := Color(col, dim)
	if sel or h:
		bcol = col.lerp(Color.WHITE, 0.5)
	c.draw_rect(rr, bcol, false, 3.0 if (sel or h) else 2.0)
	c.draw_circle(rr.position + Vector2(18, 18), 13.0, Color(0.15, 0.3, 0.8, dim))
	c.draw_string(font, rr.position + Vector2(8, 25), str(d["cost"]), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 18, Color(1, 1, 1, dim))
	var nm_col := Color(0.6, 1.0, 0.6, dim) if d["up"] else Color(1, 1, 1, dim)
	c.draw_string(font, rr.position + Vector2(34, 25), d["name"], HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 40.0, 13, nm_col)
	c.draw_string(font, rr.position + Vector2(10, 56), Cards.TYPE_JA[d["type"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, dim))
	c.draw_multiline_string(font, rr.position + Vector2(10, 84), d["desc"], HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 20.0, 14, -1, Color(0.9, 0.9, 0.95, dim))
	if key != "" and not touch:
		c.draw_string(font, rr.position + Vector2(0, rr.size.y - 8), "[" + key + "]", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 14, Color(1, 1, 1, 0.5 * dim))
	return h

## Compact one-line card for deck lists.
func mini_card(c: Control, id: String, r: Rect2, reg_id := "", sel := false) -> bool:
	var d: Dictionary = Cards.def(id)
	var h := false
	if reg_id != "":
		h = _reg(reg_id, r)
	var col: Color = d["color"]
	c.draw_rect(r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.95) if not h else Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.98))
	c.draw_rect(r, col.lerp(Color.WHITE, 0.5) if (h or sel) else col, false, 2.0)
	c.draw_circle(r.position + Vector2(16, r.size.y / 2.0), 11.0, Color(0.15, 0.3, 0.8))
	c.draw_string(font, r.position + Vector2(6, r.size.y / 2.0 + 6), str(d["cost"]), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 15)
	c.draw_string(font, r.position + Vector2(34, 22), d["name"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, 15, Color(0.6, 1.0, 0.6) if d["up"] else Color.WHITE)
	c.draw_string(font, r.position + Vector2(34, 42), d["desc"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40.0, 10, Color(0.85, 0.85, 0.9))
	return h

func relic_icon(c: Control, id: String, r: Rect2, reg_id: String) -> bool:
	var d: Dictionary = Relics.DB[id]
	var h := _reg(reg_id, r)
	var col: Color = d["color"]
	c.draw_rect(r, Color(col.r * 0.3, col.g * 0.3, col.b * 0.3))
	c.draw_rect(r, col.lerp(Color.WHITE, 0.4 if h else 0.0), false, 2.0)
	c.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.7), String(d["name"]).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.y * 0.6), col.lerp(Color.WHITE, 0.4))
	return h

func tooltip(c: Control, title: String, body: String, anchor: Vector2) -> void:
	var w := 300.0
	var r := Rect2(anchor + Vector2(0, 30), Vector2(w, 74))
	r.position.x = minf(r.position.x, W - w - 10.0)
	panel(c, r, Color(0.05, 0.05, 0.1, 0.97), Color(1, 0.9, 0.5, 0.9))
	text(c, title, r.position + Vector2(10, 24), 18, Color(1, 0.9, 0.5))
	c.draw_multiline_string(font, r.position + Vector2(10, 46), body, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0, 14, -1, Color(0.9, 0.9, 0.95))
