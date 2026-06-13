class_name BlockSkins
extends RefCounted

# Single source of truth for all block skin rendering. Everything is
# proportional to the rect size, so the same painter draws 44px board cells,
# 28px tray pieces and 12px menu fallers identically.
# Used by Grid.gd (board), Game.gd (tray + dragged piece) and the menus
# (falling background pieces).
#
# Styles: 0 PASTEL  1 NEON  2 CIRCUIT  3 BRICK  4 CRYSTAL  5 CANDY
#         6 FROST   7 GRASS 8 WATER    9 LAVA  10 WOOD    11 GALAXY
# Animated (need per-frame redraw): 8, 9, 11

const ANIMATED : Array = [2, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]

# 4x4 ordered-dither (Bayer) matrix — the classic limited-palette gradient trick
const BAYER4 : Array = [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

# Styles whose effects hang BELOW the block (drips) — on the grid these must
# be painted in a second pass after all cells, or the row below covers them
const OVERLAY_STYLES : Array = [12, 18]

# 8x8 pixel sprites for the RETRO skin ('X' = filled). Shading is automatic:
# top-edge pixels get lit, bottom-edge pixels get shaded, plus a black outline.
const RETRO_SPRITES : Array = [
	[   # heart
		"........",
		".XX..XX.",
		"XXXXXXXX",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		"...XX...",
		"........"],
	[   # star
		"...XX...",
		"...XX...",
		"..XXXX..",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		".XX..XX.",
		"........"],
	[   # gem
		"........",
		"..XXXX..",
		".XXXXXX.",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX..",
		"...XX...",
		"........"],
	[   # coin (stamped centre)
		"..XXXX..",
		".XXXXXX.",
		"XXXXXXXX",
		"XXX..XXX",
		"XXX..XXX",
		"XXXXXXXX",
		".XXXXXX.",
		"..XXXX.."],
	[   # lightning bolt
		"...XXX..",
		"..XXX...",
		".XXXX...",
		"XXXXXX..",
		"..XXX...",
		".XXX....",
		".XX.....",
		"X......."],
]

# Representative piece shapes for menu backgrounds
const DEMO_SHAPES : Array = [
	[[0, 0]],
	[[0, 0], [1, 0]],
	[[0, 0], [0, 1]],
	[[0, 0], [1, 0], [2, 0]],
	[[0, 0], [1, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [0, 1]],
	[[1, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [2, 0], [1, 1]],
	[[1, 0], [2, 0], [0, 1], [1, 1]],
	[[0, 0], [1, 0], [1, 1], [1, 2]],
]

# glow (0..1): set while the block is part of a match preview — skins that
# support it (circuit) light up their detail work.
# pr: the block's RESTING rect — canvas-continuous skins (honey/sakura/metals)
# derive their pattern scale from it so squash/stretch animations don't
# momentarily resize the shared pattern and tear it against neighbours.
static func paint(ci: CanvasItem, style: int, r: Rect2, col: Color, seed_v: int = 0, glow: float = 0.0, pr: Rect2 = Rect2(), with_overlay: bool = true) -> void:
	var s   := r.size.x
	var rad := s * 0.16
	if pr.size.x <= 0.0:
		pr = r
	match style:
		0:  _pastel(ci, r, col, s, rad)
		1:  _neon(ci, r, col, s, rad)
		2:  _circuit(ci, r, col, s, rad, seed_v, glow)
		3:  _brick(ci, r, col, s, rad, seed_v)
		4:  _crystal(ci, r, col, s, rad, seed_v)
		5:  _candy(ci, r, col, s, rad, seed_v)
		6:  _frost(ci, r, col, s, rad, seed_v)
		7:  _grass(ci, r, col, s, rad, seed_v)
		8:  _water(ci, r, col, s, rad, seed_v)
		9:  _lava(ci, r, col, s, rad, seed_v)
		10: _wood(ci, r, col, s, rad, seed_v)
		11: _galaxy(ci, r, col, s, rad, seed_v)
		12: _honey(ci, r, col, s, rad, seed_v, pr)
		13: _retro(ci, r, col, s, rad, seed_v)
		14: _bubble(ci, r, col, s, rad, seed_v)
		15: _storm(ci, r, col, s, rad, seed_v)
		16: _sakura(ci, r, col, s, rad, seed_v, pr)
		17: _gold(ci, r, col, s, rad, seed_v, pr)
		18: _slime(ci, r, col, s, rad, seed_v)
		19: _disco(ci, r, col, s, rad, seed_v)
		20: _cat(ci, r, col, s, rad, seed_v)
	if with_overlay and OVERLAY_STYLES.has(style):
		paint_overlay(ci, style, r, col, seed_v)

# ── Polygon clipping (Sutherland–Hodgman vs axis-aligned rect) ────────────────
# Lets cross-block animations (sakura petals, metal gleams) be drawn by every
# block they touch while staying EXACTLY inside each block's bounds.
static func clip_poly_to_rect(pts: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var out := pts
	for edge in 4:
		if out.size() < 3:
			return PackedVector2Array()
		var inp := out
		out = PackedVector2Array()
		for i in inp.size():
			var a := inp[i]
			var b := inp[(i + 1) % inp.size()]
			var a_in := _inside_edge(a, r, edge)
			var b_in := _inside_edge(b, r, edge)
			if a_in:
				out.append(a)
				if not b_in:
					out.append(_isect_edge(a, b, r, edge))
			elif b_in:
				out.append(_isect_edge(a, b, r, edge))
	return out

static func _inside_edge(p: Vector2, r: Rect2, e: int) -> bool:
	match e:
		0: return p.x >= r.position.x
		1: return p.x <= r.end.x
		2: return p.y >= r.position.y
		_: return p.y <= r.end.y

static func _isect_edge(a: Vector2, b: Vector2, r: Rect2, e: int) -> Vector2:
	var k : float
	match e:
		0:
			k = (r.position.x - a.x) / (b.x - a.x)
			return Vector2(r.position.x, a.y + (b.y - a.y) * k)
		1:
			k = (r.end.x - a.x) / (b.x - a.x)
			return Vector2(r.end.x, a.y + (b.y - a.y) * k)
		2:
			k = (r.position.y - a.y) / (b.y - a.y)
			return Vector2(a.x + (b.x - a.x) * k, r.position.y)
		_:
			k = (r.end.y - a.y) / (b.y - a.y)
			return Vector2(a.x + (b.x - a.x) * k, r.end.y)

# ── Rounded helpers ───────────────────────────────────────────────────────────
static func rr_points(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(rad, rad),                      PI,        PI * 1.5],
		[Vector2(r.end.x - rad, r.position.y + rad),          PI * 1.5,  TAU],
		[r.end - Vector2(rad, rad),                           0.0,       PI * 0.5],
		[Vector2(r.position.x + rad, r.end.y - rad),          PI * 0.5,  PI],
	]
	for cn in corners:
		for i in 4:
			var a : float = lerpf(cn[1], cn[2], float(i) / 3.0)
			pts.append(cn[0] + Vector2(cos(a), sin(a)) * rad)
	return pts

# Degenerate guard: rects under ~6px collapse the corner arcs into invalid
# polygons (menu fallers paint at ~10px cells) — fall back to plain rects
static func rr_fill(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, col, true)
		return
	ci.draw_polygon(rr_points(r, rad), PackedColorArray([col]))

static func rr_outline(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, col, false, width)
		return
	var pts := rr_points(r, rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width)

static func rr_grad(ci: CanvasItem, r: Rect2, rad: float, top_col: Color, bot_col: Color) -> void:
	if r.size.x < 6.0 or r.size.y < 6.0:
		ci.draw_rect(r, top_col.lerp(bot_col, 0.5), true)
		return
	var pts  := rr_points(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top_col.lerp(bot_col, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)

# ── 0 PASTEL ──────────────────────────────────────────────────────────────────
static func _pastel(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float) -> void:
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.18))
	rr_grad(ci, r, rad, col.lightened(0.50), col.lightened(0.10))
	rr_outline(ci, r, rad, col.darkened(0.15), 1.5)
	ci.draw_circle(r.position + r.size * 0.26, s * 0.10, col.lightened(0.80))

# ── 1 NEON ────────────────────────────────────────────────────────────────────
static func _neon(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float) -> void:
	rr_fill(ci, r.grow(s * 0.18), rad + s * 0.14, Color(col.r, col.g, col.b, 0.05))
	rr_fill(ci, r.grow(s * 0.09), rad + s * 0.07, Color(col.r, col.g, col.b, 0.12))
	rr_fill(ci, r.grow(s * 0.05), rad + s * 0.04, Color(col.r, col.g, col.b, 0.22))
	rr_fill(ci, r, rad, col.darkened(0.82))
	rr_outline(ci, r, rad, col, 2.0)

# ── 2 CIRCUIT (animated) ──────────────────────────────────────────────────────
# Traces run edge-to-edge at fixed fractions, so neighbouring blocks form one
# continuous circuit. Solder pads at junctions, a seeded SMD chip, and a data
# pulse travelling the traces. `glow` (match preview) lights the whole net up.
static func _circuit(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int, glow: float = 0.0) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.05), r.size + Vector2(s * 0.05, s * 0.05)), rad, Color(0, 0, 0, 0.40))
	rr_grad(ci, r, rad, col.darkened(0.18 - glow * 0.10), col.darkened(0.42 - glow * 0.10))
	rr_outline(ci, r, rad, col.lightened(0.30 + glow * 0.30), 1.5 + glow)
	# Traces — same fractions on every block => they connect across the board
	var tc := Color(col.lightened(glow * 0.5).r, col.lightened(glow * 0.5).g,
		col.lightened(glow * 0.5).b, 0.50 + glow * 0.50)
	var tw := 1.2 + glow * 1.2
	var y1 := r.position.y + r.size.y * 0.30
	var y2 := r.position.y + r.size.y * 0.70
	var x1 := r.position.x + r.size.x * 0.50
	ci.draw_line(Vector2(r.position.x, y1), Vector2(r.end.x, y1), tc, tw)
	ci.draw_line(Vector2(r.position.x, y2), Vector2(r.end.x, y2), tc, tw)
	ci.draw_line(Vector2(x1, r.position.y), Vector2(x1, r.end.y), tc, tw)
	# Solder pads at the junctions
	for jy in [y1, y2]:
		ci.draw_circle(Vector2(x1, jy), s * 0.055 + glow * s * 0.02, col.lightened(0.55 + glow * 0.25))
		ci.draw_circle(Vector2(x1, jy), s * 0.025, col.darkened(0.45))
	# Seeded SMD chip on one of four spots, legs reaching the nearest trace
	var spots := [Vector2(0.22, 0.50), Vector2(0.78, 0.50), Vector2(0.25, 0.14), Vector2(0.72, 0.86)]
	var sp : Vector2 = r.position + r.size * spots[seed_v % 4]
	var chip := Rect2(sp - Vector2(s * 0.07, s * 0.05), Vector2(s * 0.14, s * 0.10))
	ci.draw_rect(chip, Color(0.08, 0.08, 0.10), true)
	ci.draw_rect(chip, col.lightened(0.20), false, 1.0)
	for leg in 3:
		var lx := chip.position.x + s * 0.025 + float(leg) * s * 0.045
		ci.draw_line(Vector2(lx, chip.position.y - s * 0.03), Vector2(lx, chip.position.y), tc, 1.0)
		ci.draw_line(Vector2(lx, chip.end.y), Vector2(lx, chip.end.y + s * 0.03), tc, 1.0)
	# Data pulse riding the traces — constant speed (a glow-scaled speed makes
	# the dot teleport, since position = time × speed); glow brightens it instead
	var k := fmod(t * 0.45 + float(seed_v % 23) * 0.13, 1.0)
	var pp : Vector2
	if k < 0.5:   # along the top trace, left -> right
		pp = Vector2(lerpf(r.position.x, r.end.x, k * 2.0), y1)
	else:         # down the vertical, then it wraps
		pp = Vector2(x1, lerpf(y1, r.end.y, (k - 0.5) * 2.0))
	ci.draw_circle(pp, s * 0.045, Color(1, 1, 1, 0.55 + glow * 0.40))
	ci.draw_circle(pp, s * 0.09, Color(col.lightened(0.5).r, col.lightened(0.5).g, col.lightened(0.5).b, 0.22 + glow * 0.30))

# ── 3 BRICK (running-bond wall) ───────────────────────────────────────────────
static func _brick(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.07), r.size), rad, Color(0, 0, 0, 0.35))
	rr_fill(ci, r, rad, col.darkened(0.62))
	var rh := (r.size.y - s * 0.05) / 3.0
	var bi := 0
	for row in 3:
		var y := r.position.y + s * 0.025 + float(row) * rh
		var edges : Array = [0.0, 0.5, 1.0] if row % 2 == 0 else [0.0, 0.25, 0.75, 1.0]
		for i in edges.size() - 1:
			var x0 : float = r.position.x + s * 0.025 + edges[i]     * (r.size.x - s * 0.05)
			var x1 : float = r.position.x + s * 0.025 + edges[i + 1] * (r.size.x - s * 0.05)
			var shade := float((seed_v * 13 + bi * 37) % 5) * 0.035
			var brick := Rect2(x0 + s * 0.02, y + s * 0.02, x1 - x0 - s * 0.04, rh - s * 0.04)
			rr_fill(ci, brick, s * 0.05, col.darkened(0.05 + shade))
			ci.draw_rect(Rect2(brick.position, Vector2(brick.size.x, s * 0.045)), col.lightened(0.18), true)
			# Weathering: texture specks on every brick, a crack on the odd one
			for sp in 2:
				var px := brick.position.x + float((seed_v * 17 + bi * 29 + sp * 41) % 100) / 100.0 * brick.size.x
				var py := brick.position.y + s * 0.06 + float((seed_v * 23 + bi * 31 + sp * 53) % 100) / 100.0 * (brick.size.y - s * 0.08)
				ci.draw_circle(Vector2(px, py), s * 0.014, col.darkened(0.30 + shade))
			if (seed_v + bi * 7) % 9 == 0:
				var cx := brick.get_center()
				ci.draw_line(cx + Vector2(-s * 0.05, -s * 0.03), cx + Vector2(0, s * 0.02), col.darkened(0.50), 1.0)
				ci.draw_line(cx + Vector2(0, s * 0.02), cx + Vector2(s * 0.05, s * 0.045), col.darkened(0.50), 1.0)
			bi += 1
	# Moss tuft creeping out of the mortar on some blocks
	if seed_v % 6 == 0:
		var mp := r.position + r.size * Vector2(0.20 + float(seed_v % 3) * 0.25, 0.36)
		for m in 3:
			ci.draw_circle(mp + Vector2(float(m - 1) * s * 0.035, float(m % 2) * s * 0.02),
				s * 0.030, Color(0.45, 0.65, 0.30, 0.55))
	rr_outline(ci, r, rad, col.darkened(0.40), 1.5)

# ── 4 CRYSTAL (v4: the block IS a cut gem — octagonal emerald cut) ───────────
static func _crystal(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int = 0) -> void:
	var cut := s * 0.24
	var oct := PackedVector2Array([
		Vector2(r.position.x + cut, r.position.y),
		Vector2(r.end.x - cut, r.position.y),
		Vector2(r.end.x, r.position.y + cut),
		Vector2(r.end.x, r.end.y - cut),
		Vector2(r.end.x - cut, r.end.y),
		Vector2(r.position.x + cut, r.end.y),
		Vector2(r.position.x, r.end.y - cut),
		Vector2(r.position.x, r.position.y + cut),
	])
	# Drop shadow (same octagon, offset)
	var sh := PackedVector2Array()
	for p in oct:
		sh.append(p + Vector2(s * 0.03, s * 0.06))
	ci.draw_polygon(sh, PackedColorArray([Color(0, 0, 0, 0.30)]))
	# Rim gradient — lit from above
	var rim_cols := PackedColorArray()
	for p in oct:
		rim_cols.append(col.lightened(0.30).lerp(col.darkened(0.28),
			clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(oct, rim_cols)
	# Inner table — the flat bright face of the gem
	var c := r.get_center()
	var table := PackedVector2Array()
	for p in oct:
		table.append(c + (p - c) * 0.54)
	var table_cols := PackedColorArray()
	for p in table:
		table_cols.append(col.lightened(0.60).lerp(col.lightened(0.18),
			clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	ci.draw_polygon(table, table_cols)
	# Facet edges from rim corners to table corners
	for i in oct.size():
		ci.draw_line(oct[i], table[i], Color(1, 1, 1, 0.22), 1.0)
	# Outlines
	var oct_closed := oct.duplicate(); oct_closed.append(oct[0])
	ci.draw_polyline(oct_closed, col.lightened(0.45), 1.5)
	var tbl_closed := table.duplicate(); tbl_closed.append(table[0])
	ci.draw_polyline(tbl_closed, Color(1, 1, 1, 0.40), 1.0)
	# Glint stroke across the table + a sparkle dot
	ci.draw_line(c + Vector2(-s * 0.14, -s * 0.06), c + Vector2(-s * 0.04, -s * 0.16),
		Color(1, 1, 1, 0.75), 2.0)
	ci.draw_circle(c + Vector2(s * 0.12, s * 0.10), s * 0.030, Color(1, 1, 1, 0.65))

# ── 5 CANDY (candy cane: diagonal stripes in the piece colour over white) ────
static func _candy(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int = 0) -> void:
	var crad := rad + s * 0.07
	var stripe := col.lerp(Color(0.95, 0.15, 0.20), 0.35)   # nudge toward candy red
	var white := Color(1.0, 0.97, 0.95)
	rr_fill(ci, Rect2(r.position + Vector2(0, s * 0.07), r.size), crad, Color(0, 0, 0, 0.30))
	# White peppermint base
	rr_grad(ci, r, crad, white, Color(0.90, 0.86, 0.87))
	# Diagonal coloured stripes, anchored to the block corner so every candy
	# looks identical; clipped just inside the rounded edge
	var inner := r.grow(-s * 0.05)
	var sw := s * 0.24
	var y0 := r.position.y - s * 0.1
	var y1 := r.end.y + s * 0.1
	var base := r.position.x + r.position.y
	var lo := -sw
	while lo < r.size.x + r.size.y + sw:
		var d := base + lo
		var poly := clip_poly_to_rect(PackedVector2Array([
			Vector2(d - y0, y0), Vector2(d + sw - y0, y0),
			Vector2(d + sw - y1, y1), Vector2(d - y1, y1)]), inner)
		if poly.size() >= 3:
			ci.draw_polygon(poly, PackedColorArray([stripe]))
		lo += sw * 2.0
	# Glossy shine across the top + a little sparkle
	var gloss := Rect2(r.position + Vector2(r.size.x * 0.12, r.size.y * 0.09),
		Vector2(r.size.x * 0.60, r.size.y * 0.18))
	rr_fill(ci, gloss, gloss.size.y * 0.5, Color(1, 1, 1, 0.45))
	ci.draw_circle(r.position + r.size * Vector2(0.78, 0.74), s * 0.045, Color(1, 1, 1, 0.40))
	rr_outline(ci, r, crad, stripe.darkened(0.35), 2.0)

# ── 6 FROST ───────────────────────────────────────────────────────────────────
static func _frost(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var ice := col.lerp(Color(0.65, 0.85, 1.0), 0.40)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad,
		Color(ice.lightened(0.40).r, ice.lightened(0.40).g, ice.lightened(0.40).b, 0.92),
		Color(ice.darkened(0.10).r,  ice.darkened(0.10).g,  ice.darkened(0.10).b,  0.88))
	# Seeded cracks
	var h := seed_v * 2654435761
	for i in 3:
		h = int(fmod(float(h) * 1103515.0 + 12345.0, 2147483647.0))
		var x0 : float = r.position.x + s * 0.11 + float(h % 100) / 100.0 * (r.size.x - s * 0.32)
		var y0 : float = r.position.y + s * 0.11 + float((h / 100) % 100) / 100.0 * (r.size.y - s * 0.32)
		var dx : float = (float((h / 7) % 17) - 8.0) * s * 0.027
		var dy : float = (float((h / 11) % 17) - 8.0) * s * 0.027
		var p0 := Vector2(x0, y0)
		var p1 := p0 + Vector2(dx, dy)
		ci.draw_line(p0, p1, Color(1, 1, 1, 0.40), 1.0)
		ci.draw_line(p1, p1 + Vector2(dy * 0.5, -dx * 0.5), Color(1, 1, 1, 0.25), 1.0)
	var band := Rect2(r.position + Vector2(s * 0.09, s * 0.07), Vector2(r.size.x - s * 0.18, s * 0.11))
	rr_fill(ci, band, s * 0.05, Color(1, 1, 1, 0.45))
	# Icicles hanging from the frosted edge (seeded count + lengths)
	for i in 2 + seed_v % 2:
		var ix := r.position.x + s * (0.20 + 0.28 * float(i)) + float((seed_v * 13 + i * 29) % 8) * s * 0.012
		var il := s * (0.10 + float((seed_v * 19 + i * 37) % 10) * 0.014)
		ci.draw_polygon(PackedVector2Array([
			Vector2(ix - s * 0.035, band.end.y), Vector2(ix, band.end.y + il),
			Vector2(ix + s * 0.035, band.end.y)]),
			PackedColorArray([Color(1, 1, 1, 0.38)]))
	# A frost sparkle that twinkles in and out
	var t := Time.get_ticks_msec() * 0.001
	var tw := absf(sin(t * 1.4 + float(seed_v % 13) * 0.8))
	var spx := r.position + r.size * Vector2(0.30 + float(seed_v % 4) * 0.13, 0.55 + float(seed_v % 3) * 0.10)
	ci.draw_line(spx + Vector2(-s * 0.05, 0), spx + Vector2(s * 0.05, 0), Color(1, 1, 1, 0.65 * tw), 1.0)
	ci.draw_line(spx + Vector2(0, -s * 0.05), spx + Vector2(0, s * 0.05), Color(1, 1, 1, 0.65 * tw), 1.0)
	rr_outline(ci, r.grow(-s * 0.045), rad - s * 0.034, Color(1, 1, 1, 0.30), 1.0)
	rr_outline(ci, r, rad, ice.lightened(0.55), 1.5)

# ── 7 GRASS ───────────────────────────────────────────────────────────────────
static func _grass(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var g := col.lerp(Color(0.30, 0.78, 0.30), 0.50)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad, g.lightened(0.25), g.darkened(0.30))
	var t := Time.get_ticks_msec() * 0.001
	var n_blades := 6
	for i in n_blades:
		var bx : float = r.position.x + s * 0.09 + float(i) * (r.size.x - s * 0.18) / float(n_blades - 1)
		var bh : float = s * (0.14 + float((seed_v * 7 + i * 11) % 5) * 0.036)
		# Blades sway gently in the breeze, each on its own phase
		var lean : float = float((seed_v + i * 3) % 5 - 2) * s * 0.027 \
			+ sin(t * 1.6 + float(seed_v % 9) * 0.7 + float(i) * 0.9) * s * 0.030
		ci.draw_polygon(PackedVector2Array([
			Vector2(bx - s * 0.045, r.position.y + s * 0.20),
			Vector2(bx + lean, r.position.y + s * 0.20 - bh),
			Vector2(bx + s * 0.045, r.position.y + s * 0.20)]),
			PackedColorArray([g.lightened(0.35 if i % 2 == 0 else 0.15)]))
	for i in 3:
		var px : float = r.position.x + s * 0.14 + float((seed_v * 31 + i * 53) % 100) / 100.0 * (r.size.x - s * 0.28)
		var py : float = r.position.y + r.size.y * 0.45 + float((seed_v * 17 + i * 29) % 100) / 100.0 * (r.size.y * 0.4)
		ci.draw_circle(Vector2(px, py), s * 0.034, g.lightened(0.40))
	if seed_v % 7 == 0:
		var fp := r.position + r.size * Vector2(0.68, 0.62)
		for i in 5:
			var a := float(i) / 5.0 * TAU
			ci.draw_circle(fp + Vector2(cos(a), sin(a)) * s * 0.068, s * 0.045, Color(1, 1, 1, 0.85))
		ci.draw_circle(fp, s * 0.04, Color(0.98, 0.85, 0.25))
	rr_outline(ci, r, rad, g.darkened(0.35), 1.5)

# ── 8 WATER (animated) ────────────────────────────────────────────────────────
static func _water(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var w := col.lerp(Color(0.20, 0.55, 1.00), 0.55)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad,
		Color(w.lightened(0.30).r, w.lightened(0.30).g, w.lightened(0.30).b, 0.95),
		Color(w.darkened(0.25).r,  w.darkened(0.25).g,  w.darkened(0.25).b,  0.95))
	for wave in 2:
		var base_y : float = r.position.y + r.size.y * (0.35 + 0.30 * float(wave))
		var pts := PackedVector2Array()
		for i in 9:
			var x : float = r.position.x + s * 0.09 + float(i) / 8.0 * (r.size.x - s * 0.18)
			var y : float = base_y + sin(t * 2.2 + float(seed_v) * 0.7 + float(wave) * 2.1 + float(i) * 0.8) * s * 0.057
			pts.append(Vector2(x, y))
		ci.draw_polyline(pts, Color(1, 1, 1, 0.30 - 0.10 * float(wave)), 1.5)
	var sx : float = r.position.x + s * 0.14 + fmod(t * s * 0.2 + float(seed_v % 13) * 3.7, r.size.x - s * 0.28)
	ci.draw_circle(Vector2(sx, r.position.y + r.size.y * 0.22), s * 0.045, Color(1, 1, 1, 0.55))
	# Bubbles rising from the depths, swaying as they go
	for i in 2:
		var bk := fmod(t * (0.22 + float(i) * 0.09) + float(seed_v % 7 + i * 3) * 0.14, 1.0)
		var bx := r.position.x + r.size.x * (0.30 + 0.40 * float((seed_v + i * 5) % 3) / 2.0) \
			+ sin(t * 2.5 + float(i) * 2.0) * s * 0.04
		var by := lerpf(r.end.y - s * 0.10, r.position.y + s * 0.12, bk)
		ci.draw_circle(Vector2(bx, by), s * (0.025 + float(i) * 0.012), Color(1, 1, 1, 0.40 * (1.0 - bk * 0.6)))
	rr_outline(ci, r, rad, w.lightened(0.30), 1.5)

# ── 9 LAVA (animated) ─────────────────────────────────────────────────────────
static func _lava(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var l := col.lerp(Color(1.00, 0.38, 0.05), 0.70)
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.55 + 0.45 * sin(t * 2.6 + float(seed_v % 9) * 0.8)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.35))
	rr_grad(ci, r, rad,
		Color(0.16, 0.07, 0.05).lerp(l.darkened(0.25), 0.25 + pulse * 0.18),
		Color(0.10, 0.04, 0.03))
	var crack_col := Color(l.r, l.g, l.b, 0.45 + pulse * 0.55)
	var h := seed_v
	for i in 3:
		h = (h * 1103515 + 12345) % 2147483647
		var x0 : float = r.position.x + s * 0.11 + float(h % 100) / 100.0 * (r.size.x - s * 0.36)
		var y0 : float = r.position.y + s * 0.11 + float((h / 100) % 100) / 100.0 * (r.size.y - s * 0.36)
		var p0 := Vector2(x0, y0)
		var p1 := p0 + Vector2(float((h / 7) % 13) - 6.0, float((h / 11) % 13) - 6.0) * s * 0.03
		var p2 := p1 + Vector2(float((h / 13) % 11) - 5.0, float((h / 17) % 11) - 5.0) * s * 0.027
		ci.draw_polyline(PackedVector2Array([p0, p1, p2]), crack_col, 2.0)
	ci.draw_circle(r.get_center() + Vector2(float(seed_v % 7) - 3.0, float(seed_v % 5) - 2.0) * s * 0.045,
		s * (0.068 + pulse * 0.045), Color(1.0, 0.75, 0.25, 0.30 + pulse * 0.35))
	# Spark leaping from the crack, arcing up then dying
	var sk := fmod(t * 0.55 + float(seed_v % 17) * 0.11, 1.0)
	if sk < 0.45:
		var kk := sk / 0.45
		var ox := r.position.x + r.size.x * (0.30 + 0.40 * float(seed_v % 4) / 3.0)
		var spark := Vector2(ox + kk * s * 0.16, r.position.y + r.size.y * 0.55 \
			- sin(kk * PI) * s * 0.30)
		ci.draw_circle(spark, s * 0.026, Color(1.0, 0.85, 0.35, 0.85 * (1.0 - kk)))
	rr_outline(ci, r, rad, Color(0.05, 0.02, 0.02, 0.9), 1.5)

# ── 10 WOOD ───────────────────────────────────────────────────────────────────
# End-grain log top (Minecraft style): bark rim around a cut face with
# concentric growth rings, slightly off-centre per block
static func _wood(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var w := col.lerp(Color(0.62, 0.42, 0.22), 0.60)
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	# Bark rim
	rr_grad(ci, r, rad, w.darkened(0.28), w.darkened(0.48))
	# Bark notches around the rim
	for i in 4:
		var na := float(i) * PI * 0.5 + float(seed_v % 7) * 0.3 + 0.4
		var np2 := r.get_center() + Vector2(cos(na), sin(na)) * s * 0.47
		ci.draw_line(np2, np2 + (r.get_center() - np2).normalized() * s * 0.05, w.darkened(0.60), 2.0)
	# Cut face
	var face := r.grow(-s * 0.11)
	rr_grad(ci, face, rad * 0.65, w.lightened(0.32), w.lightened(0.06))
	# Growth rings — rounded, jittered off-centre, alternating shade
	var jit := Vector2(float(seed_v % 5 - 2), float((seed_v / 5) % 5 - 2)) * s * 0.016
	for i in 3:
		var k := 0.76 - float(i) * 0.23
		var ring := Rect2(face.position + face.size * (1.0 - k) * 0.5 + jit * (1.0 + float(i) * 0.5),
			face.size * k)
		rr_outline(ci, ring, maxf(rad * 0.5 * k, 2.0), w.darkened(0.25 + float(i % 2) * 0.08), 1.6)
	# Core
	var core := face.get_center() + jit * 2.4
	ci.draw_circle(core, s * 0.050, w.darkened(0.32))
	ci.draw_circle(core, s * 0.024, w.lightened(0.10))
	# Radial drying crack on some logs
	if seed_v % 3 == 0:
		var ca2 := float(seed_v % 11) * 0.6
		var dir2 := Vector2(cos(ca2), sin(ca2))
		ci.draw_line(core + dir2 * s * 0.07, core + dir2 * s * 0.34, w.darkened(0.45), 1.3)
	rr_outline(ci, r, rad, w.darkened(0.45), 1.5)

# ── 12 HONEY (animated: continuous honeycomb + oozing drip) ──────────────────
static func _honey(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	# Every piece colour maps to a SHADE OF AMBER (light wildflower to dark
	# buckwheat) — pieces stay tellable apart, nothing reads green/blue
	var tone := fmod(col.h * 2.7 + col.v * 0.5, 1.0)
	var hn := Color(1.00, 0.76, 0.28).lerp(Color(0.78, 0.48, 0.10), tone)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.30))
	# Light base = the wax walls; the darker hex cells get drawn on top
	rr_grad(ci, r, rad, hn.lightened(0.35), hn.lightened(0.05))
	# Honeycomb tiled in ABSOLUTE canvas space — one continuous comb across
	# all neighbouring blocks, each cell clipped to its block
	var hs := ps * 0.27
	var hw := sqrt(3.0) * hs
	var vstep := 1.5 * hs
	var inner := r.grow(-s * 0.045)
	# Pattern-space translation: lattice is computed in pr-space and shifted by
	# delta — lets the dragged piece sample BOARD-space comb so the hover
	# preview matches the placed result exactly. Small deltas (squash wobble)
	# are zeroed so the pattern stays put during landing animations.
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var row0 := int(floor((pr.position.y - hs) / vstep))
	var row1 := int(ceil((pr.end.y + hs) / vstep))
	for row in range(row0, row1 + 1):
		var cy := float(row) * vstep
		var xoff := hw * 0.5 if posmod(row, 2) == 1 else 0.0
		var q0 := int(floor((pr.position.x - hw) / hw))
		var q1 := int(ceil((pr.end.x + hw) / hw))
		for q in range(q0, q1 + 1):
			var cx := float(q) * hw + xoff
			var hc := Vector2(cx, cy) + delta
			var hh := absi((q * 73856093) ^ (row * 19349663))
			var hex := PackedVector2Array()
			var fully_inside := true
			for i in 6:
				var a := PI / 6.0 + float(i) * PI / 3.0
				var pt := hc + Vector2(cos(a), sin(a)) * hs * 0.90
				hex.append(pt)
				if not inner.has_point(pt):
					fully_inside = false
			var cell := clip_poly_to_rect(hex, inner)
			if cell.size() >= 3:
				ci.draw_polygon(cell, PackedColorArray([hn.darkened(0.22 + float(hh % 5) * 0.05)]))
			# Wax-capped cells (only when the whole hex fits inside the block)
			if fully_inside and hh % 3 == 0:
				ci.draw_circle(hc, hs * 0.58, hn.lightened(0.22))
				ci.draw_circle(hc - Vector2(hs * 0.18, hs * 0.18), hs * 0.16, hn.lightened(0.45))
	# Glossy shine band
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.10, s * 0.06), Vector2(r.size.x - s * 0.20, s * 0.09)),
		s * 0.045, Color(1, 1, 0.85, 0.30))
	rr_outline(ci, r, rad, hn.darkened(0.35), 1.5)

# Overlay pass: effects that hang below the block (drawn after all grid cells)
static func paint_overlay(ci: CanvasItem, style: int, r: Rect2, col: Color, seed_v: int = 0) -> void:
	var s := r.size.x
	var t := Time.get_ticks_msec() * 0.001
	match style:
		12:  # Honey drip: oozes down slowly, then retracts back up — no popping
			var tone := fmod(col.h * 2.7 + col.v * 0.5, 1.0)
			var hn := Color(1.00, 0.76, 0.28).lerp(Color(0.78, 0.48, 0.10), tone)
			var dk := fmod(t * 0.30 + float(seed_v % 9) * 0.13, 1.0)
			var dx := r.position.x + r.size.x * (0.30 + 0.40 * float(seed_v % 3) / 2.0)
			var k := (dk / 0.7) if dk < 0.7 else (1.0 - (dk - 0.7) / 0.3)
			if k > 0.02:
				var stretch := s * 0.16 * k
				var bulb := s * 0.05 * (0.55 + 0.45 * k)
				ci.draw_circle(Vector2(dx, r.end.y - s * 0.02), s * 0.045 * (0.55 + 0.45 * k), hn.lightened(0.15))
				ci.draw_line(Vector2(dx, r.end.y - s * 0.02), Vector2(dx, r.end.y + stretch), hn.lightened(0.15), s * 0.06 * (0.55 + 0.45 * k))
				ci.draw_circle(Vector2(dx, r.end.y + stretch), bulb, hn.lightened(0.20))
		18:  # Slime drip: same ooze-then-retract envelope
			var gl := col.lerp(Color(0.40, 0.90, 0.25), 0.55)
			var dk2 := fmod(t * 0.26 + float(seed_v % 6) * 0.15, 1.0)
			var k2 := (dk2 / 0.65) if dk2 < 0.65 else (1.0 - (dk2 - 0.65) / 0.35)
			if k2 > 0.02:
				var dx2 := r.position.x + r.size.x * (0.62 - 0.30 * float(seed_v % 2))
				var stretch2 := s * 0.14 * k2
				ci.draw_line(Vector2(dx2, r.end.y - s * 0.02), Vector2(dx2, r.end.y + stretch2), gl.darkened(0.05), s * 0.055 * (0.55 + 0.45 * k2))
				ci.draw_circle(Vector2(dx2, r.end.y + stretch2), s * 0.045 * (0.55 + 0.45 * k2), gl.lightened(0.10))

# ── 13 RETRO (chunky low-res pixel block, ordered-dither gradient) ────────────
# The whole block is an 8x8 grid of fat pixels: dark sprite outline, a
# dithered diagonal light gradient through a 4-shade palette (the classic
# limited-colour look), bright bevel pixels top-left + a wandering twinkle.
static func _retro(ci: CanvasItem, r: Rect2, col: Color, s: float, _rad: float, seed_v: int) -> void:
	var px := s / 8.0
	var t := Time.get_ticks_msec() * 0.001
	# Hard drop shadow (no soft edges in 8-bit land)
	ci.draw_rect(Rect2(r.position + Vector2(px * 0.7, px * 0.7), r.size), Color(0, 0, 0, 0.35), true)
	var outline := col.darkened(0.62)
	var pal := [col.darkened(0.40), col.darkened(0.18), col, col.lightened(0.40)]
	for gy in 8:
		for gx in 8:
			var cell := Rect2(r.position + Vector2(float(gx) * px, float(gy) * px), Vector2(px + 0.6, px + 0.6))
			# Outer ring = crisp dark pixel outline
			if gx == 0 or gy == 0 or gx == 7 or gy == 7:
				ci.draw_rect(cell, outline, true)
				continue
			# Brightness: diagonal light (top-left bright) + a soft highlight bump
			var fx := float(gx) / 7.0
			var fy := float(gy) / 7.0
			var v := 1.0 - (fx + fy) * 0.42
			v += 0.28 * (1.0 - clampf(Vector2(fx - 0.30, fy - 0.28).length() * 2.3, 0.0, 1.0))
			v = clampf(v, 0.0, 1.0)
			# Quantise into the 4-shade palette with ordered dithering
			var scaled := v * 3.0
			var bi := int(floor(scaled))
			var frac := scaled - float(bi)
			var thr := float(BAYER4[gy % 4][gx % 4]) / 16.0
			var idx := clampi(bi + (1 if frac > thr else 0), 0, 3)
			ci.draw_rect(cell, pal[idx], true)
	# Bright bevel highlight pixels, top-left interior
	ci.draw_rect(Rect2(r.position + Vector2(px * 1.0, px * 1.0), Vector2(px * 2.0 + 0.6, px + 0.6)), col.lightened(0.62), true)
	ci.draw_rect(Rect2(r.position + Vector2(px * 1.0, px * 2.0), Vector2(px + 0.6, px + 0.6)), col.lightened(0.62), true)
	# A single twinkle pixel that blinks on the block's own phase
	var bl := sin(t * 4.0 + float(seed_v) * 1.7)
	if bl > 0.4:
		var sxp := 3 + (seed_v % 3)
		var syp := 3 + ((seed_v / 3) % 2)
		ci.draw_rect(Rect2(r.position + Vector2(float(sxp) * px, float(syp) * px), Vector2(px + 0.6, px + 0.6)),
			Color(1, 1, 1, (bl - 0.4) / 0.6 * 0.9), true)

# ── 14 BUBBLE (animated: iridescent soap film) ────────────────────────────────
static func _bubble(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad + s * 0.06, Color(0, 0, 0, 0.18))
	# Glassy translucent body
	var body := Color(col.lightened(0.20).r, col.lightened(0.20).g, col.lightened(0.20).b, 0.38)
	rr_grad(ci, r, rad + s * 0.06,
		Color(col.lightened(0.45).r, col.lightened(0.45).g, col.lightened(0.45).b, 0.45), body)
	# Iridescent rim — hue drifts over time, each block out of phase
	var hue := fmod(col.h + 0.12 * sin(t * 0.9 + float(seed_v % 13) * 0.7), 1.0)
	if hue < 0.0: hue += 1.0
	var iri := Color.from_hsv(hue, 0.55, 1.0, 0.75)
	rr_outline(ci, r, rad + s * 0.06, iri, 2.0)
	rr_outline(ci, r.grow(-s * 0.05), rad, Color(1, 1, 1, 0.18), 1.0)
	# Crescent highlight top-left
	ci.draw_arc(r.position + r.size * Vector2(0.34, 0.34), s * 0.20, PI * 0.95, PI * 1.55, 12,
		Color(1, 1, 1, 0.75), 2.5, false)
	ci.draw_circle(r.position + r.size * Vector2(0.26, 0.24), s * 0.045, Color(1, 1, 1, 0.85))
	# Mini-bubbles drifting up inside, swaying — each one pops at the top
	for i in 3:
		var bk := fmod(t * (0.14 + float(i) * 0.05) + float((seed_v + i * 7) % 9) * 0.13, 1.0)
		var bx := r.position.x + r.size.x * (0.25 + 0.50 * float((seed_v * 3 + i * 5) % 4) / 3.0) \
			+ sin(t * 2.0 + float(i) * 2.2 + float(seed_v)) * s * 0.05
		var by := lerpf(r.end.y - s * 0.14, r.position.y + s * 0.16, bk)
		var brr := s * (0.028 + 0.020 * bk + float(i % 2) * 0.012)
		if bk < 0.86:
			ci.draw_arc(Vector2(bx, by), brr, 0, TAU, 10, Color(1, 1, 1, 0.42), 1.0, false)
			ci.draw_circle(Vector2(bx - brr * 0.35, by - brr * 0.35), brr * 0.28, Color(1, 1, 1, 0.50))
		else:
			# Pop! — a quick expanding ring that fades out
			var pk := (bk - 0.86) / 0.14
			ci.draw_arc(Vector2(bx, by), brr * (1.0 + pk * 0.9), 0, TAU, 10,
				Color(1, 1, 1, 0.42 * (1.0 - pk)), 1.0, false)

# ── 15 STORM (animated: thundercloud with rain + lightning strikes) ───────────
static func _storm(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var st := col.lerp(Color(0.45, 0.50, 0.62), 0.60)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.32))
	rr_grad(ci, r, rad, st.lightened(0.15), st.darkened(0.40))
	# Cloud bumps along the top
	var cloud := st.lightened(0.35)
	ci.draw_circle(r.position + r.size * Vector2(0.25, 0.18), s * 0.14, cloud)
	ci.draw_circle(r.position + r.size * Vector2(0.50, 0.14), s * 0.17, cloud)
	ci.draw_circle(r.position + r.size * Vector2(0.75, 0.19), s * 0.13, cloud)
	# Rain streaks, falling on a loop
	var rain := Color(0.75, 0.85, 1.0, 0.45)
	for i in 3:
		var rx := r.position.x + r.size.x * (0.22 + 0.28 * float(i))
		var ry := r.position.y + r.size.y * 0.42 + fmod(t * s * 0.9 + float(seed_v * 7 + i * 31) * 3.0, r.size.y * 0.45)
		ci.draw_line(Vector2(rx, ry), Vector2(rx - s * 0.03, ry + s * 0.10), rain, 1.3)
	# Lightning strike — brief, seeded phase
	var lk := fmod(t * 0.45 + float(seed_v % 11) * 0.10, 1.0)
	if lk < 0.10:
		var flash := 1.0 - lk / 0.10
		var lx := r.position.x + r.size.x * (0.35 + 0.30 * float(seed_v % 3) / 2.0)
		ci.draw_polyline(PackedVector2Array([
			Vector2(lx, r.position.y + r.size.y * 0.28),
			Vector2(lx - s * 0.07, r.position.y + r.size.y * 0.52),
			Vector2(lx + s * 0.03, r.position.y + r.size.y * 0.58),
			Vector2(lx - s * 0.05, r.position.y + r.size.y * 0.85)]),
			Color(1.0, 1.0, 0.75, 0.95 * flash), 2.0)
		rr_fill(ci, r, rad, Color(1, 1, 1, 0.14 * flash))
	rr_outline(ci, r, rad, st.lightened(0.25), 1.5)

# ── 16 SAKURA (animated: one continuous petalfall flowing across all blocks) ─
# Petals live in ABSOLUTE canvas space (vertical lanes + global fall phase),
# so every block draws its slice of the same petal field — petals drift
# seamlessly from each block into the one below it.
static func _sakura(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	var sk := col.lerp(Color(1.00, 0.75, 0.82), 0.50)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.25))
	rr_grad(ci, r, rad, sk.lightened(0.32), sk.darkened(0.12))
	# Petal lanes: fixed x positions in canvas space, petals repeat vertically
	# and fall on a global clock
	# Petals are drawn slightly past the block edges (margin = petal size) and
	# in OPAQUE colours: a boundary-crossing petal gets drawn identically by
	# both neighbouring blocks, so there is no visible seam or pop-in.
	var margin := ps * 0.07
	var spacing := ps * 0.34
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var lane0 := int(floor((pr.position.x - margin) / spacing))
	var lane_count := int(ceil((pr.size.x + margin * 2.0) / spacing)) + 1
	for li in lane_count:
		var lane := lane0 + li
		var lx := float(lane) * spacing + spacing * 0.5
		if lx < pr.position.x - margin or lx > pr.end.x + margin:
			continue
		var lseed := absi(lane * 7919)
		var speed := ps * (0.40 + float(lseed % 5) * 0.07)
		var period := ps * (1.05 + float(lseed % 3) * 0.45)
		var base_y := fmod(t * speed + float(lseed % 100) * 3.7, period)
		var k0 := int(floor((pr.position.y - margin - base_y) / period))
		for k in range(k0, k0 + int(ceil((pr.size.y + margin * 2.0) / period)) + 2):
			var py := base_y + float(k) * period
			if py < pr.position.y - margin or py > pr.end.y + margin:
				continue
			var sway := sin(t * 1.8 + float(lane) * 1.3 + float(k) * 0.7) * ps * 0.05
			var p := Vector2(lx + sway, py) + delta
			var ang := t * 1.6 + float(lane * 3 + k) * 1.1
			var shade := 0.84 + 0.10 * sin(float(lane + k) * 2.3)
			_petal(ci, p, ang, ps * 0.058, Color(1.0, shade, 0.93), r)
	rr_outline(ci, r, rad, sk.darkened(0.25), 1.5)

# A cherry-blossom petal: teardrop with the classic notched tip, manually
# rotated, CLIPPED to the block rect — adjacent blocks each draw their exact
# half of a boundary-crossing petal, so it's seamless with zero overhang
static func _petal(ci: CanvasItem, p: Vector2, ang: float, size_f: float, col: Color, clip: Rect2) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var shape := [
		Vector2(0.00, -0.62),   # notch dip (tip indent)
		Vector2(0.30, -0.95),   # tip lobe right
		Vector2(0.62, -0.30),
		Vector2(0.46, 0.55),
		Vector2(0.00, 0.90),    # base (stem end)
		Vector2(-0.46, 0.55),
		Vector2(-0.62, -0.30),
		Vector2(-0.30, -0.95),  # tip lobe left
	]
	var pts := PackedVector2Array()
	for v in shape:
		var sv : Vector2 = v * size_f
		pts.append(p + Vector2(sv.x * ca - sv.y * sa, sv.x * sa + sv.y * ca))
	var clipped := clip_poly_to_rect(pts, clip)
	if clipped.size() >= 3:
		ci.draw_polygon(clipped, PackedColorArray([col]))
	# Soft highlight toward the base — only when it sits fully inside
	var hp := p + Vector2(-0.45 * sa, 0.45 * ca) * size_f
	if clip.grow(-size_f * 0.25).has_point(hp):
		ci.draw_circle(hp, size_f * 0.22, Color(1.0, 0.97, 0.98))

# ── 17 METALS (animated: polished precious metal/gem — the piece colour IS
# the material: yellow=gold, orange=copper, magenta=ruby, cyan=sapphire,
# green=emerald, purple=amethyst) ──────────────────────────────────────────────
static func _gold(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, _seed_v: int, pr: Rect2 = Rect2()) -> void:
	var ps := pr.size.x if pr.size.x > 0.0 else s
	# Metallize: boost saturation + value so any hue reads as polished material
	var mt := Color.from_hsv(col.h, minf(col.s * 1.15, 0.92), maxf(col.v, 0.80))
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.07), r.size), rad, Color(0, 0, 0, 0.35))
	# High-contrast metal body with a mirror "horizon" across the middle
	rr_grad(ci, r, rad, mt.lightened(0.55), mt.darkened(0.45))
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.05, s * 0.05), Vector2(r.size.x - s * 0.10, r.size.y * 0.42)),
		rad * 0.8, Color(1, 1, 1, 0.14))
	# Bevel: bright top catch, deep bottom shade
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.08, s * 0.05), Vector2(r.size.x - s * 0.16, s * 0.08)),
		s * 0.04, mt.lightened(0.65))
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.10, r.size.y - s * 0.12), Vector2(r.size.x - s * 0.20, s * 0.07)),
		s * 0.035, Color(mt.darkened(0.50).r, mt.darkened(0.50).g, mt.darkened(0.50).b, 0.55))
	# Specular glints
	ci.draw_circle(r.position + r.size * Vector2(0.22, 0.24), s * 0.040, Color(1, 1, 1, 0.85))
	ci.draw_circle(r.position + r.size * Vector2(0.30, 0.18), s * 0.020, Color(1, 1, 1, 0.65))
	var gp := r.position + r.size * Vector2(0.78, 0.70)
	ci.draw_line(gp + Vector2(-s * 0.05, 0), gp + Vector2(s * 0.05, 0), Color(1, 1, 1, 0.40), 1.2)
	ci.draw_line(gp + Vector2(0, -s * 0.05), gp + Vector2(0, s * 0.05), Color(1, 1, 1, 0.40), 1.2)
	# Board-wide gleam: ONE diagonal light streak travels across the whole
	# canvas every few seconds, lighting blocks in sequence as it passes.
	# Computed in absolute canvas space (like the sakura petalfall), so it is
	# perfectly continuous across neighbouring blocks — and clipped to each.
	var delta := r.position - pr.position
	if delta.length() < s * 0.5:
		delta = Vector2.ZERO
	var phase := fmod(t * 250.0, 900.0)
	var dmin := pr.position.x + 0.4 * pr.position.y - ps * 0.45
	var dmax := pr.end.x + 0.4 * pr.end.y
	var m := floorf((dmin - phase) / 900.0) + 1.0
	var S := phase + m * 900.0
	if S <= dmax:
		var inner := r.grow(-s * 0.04)
		var y_top := pr.position.y - 4.0
		var y_bot := pr.end.y + 4.0
		# Main band + thin trailing band, as diagonal strips x + 0.4y ∈ [b0, b0+bw]
		for band in [[0.0, ps * 0.16, 0.45], [ps * 0.24, ps * 0.07, 0.20]]:
			var b0 : float = S + band[0]
			var bw : float = band[1]
			var poly := clip_poly_to_rect(PackedVector2Array([
				Vector2(b0 - 0.4 * y_top, y_top) + delta,
				Vector2(b0 + bw - 0.4 * y_top, y_top) + delta,
				Vector2(b0 + bw - 0.4 * y_bot, y_bot) + delta,
				Vector2(b0 - 0.4 * y_bot, y_bot) + delta]), inner)
			if poly.size() >= 3:
				ci.draw_polygon(poly, PackedColorArray([Color(1, 1, 1, band[2])]))
	rr_outline(ci, r, rad, mt.lightened(0.35), 1.5)

# ── 18 SLIME (animated: wobbling goo) ─────────────────────────────────────────
static func _slime(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var gl := col.lerp(Color(0.40, 0.90, 0.25), 0.55)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.07), r.size), rad + s * 0.05, Color(0, 0, 0, 0.28))
	rr_grad(ci, r, rad + s * 0.05, gl.lightened(0.25), gl.darkened(0.22))
	# Bubbles rising through the goo
	for i in 2:
		var bk := fmod(t * (0.18 + float(i) * 0.07) + float(seed_v % 8 + i * 3) * 0.16, 1.0)
		var bx := r.position.x + r.size.x * (0.30 + 0.40 * float((seed_v + i * 7) % 3) / 2.0)
		ci.draw_arc(Vector2(bx, lerpf(r.end.y - s * 0.12, r.position.y + s * 0.30, bk)),
			s * (0.030 + float(i) * 0.014), 0, TAU, 10,
			Color(gl.lightened(0.55).r, gl.lightened(0.55).g, gl.lightened(0.55).b, 0.55 * (1.0 - bk * 0.5)), 1.2, false)
	# Gloss
	ci.draw_circle(r.position + r.size * Vector2(0.28, 0.42), s * 0.055, Color(1, 1, 1, 0.40))
	rr_outline(ci, r, rad + s * 0.05, gl.darkened(0.30), 1.5)

# ── 19 DISCO (animated: mirror-ball facets cycling colour) ────────────────────
static func _disco(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.35))
	rr_fill(ci, r, rad, col.darkened(0.45))
	# 3x3 mirror facets, each cycling hue on its own offset
	var fs := (r.size.x - s * 0.14) / 3.0
	for fy in 3:
		for fx in 3:
			var hue := fmod(col.h + float(fx + fy) * 0.07 + t * 0.12 + float(seed_v % 9) * 0.03, 1.0)
			var bright := 0.55 + 0.40 * absf(sin(t * 1.8 + float(fx * 3 + fy) * 1.3 + float(seed_v)))
			var facet := Rect2(r.position + Vector2(s * 0.07 + float(fx) * fs, s * 0.07 + float(fy) * fs),
				Vector2(fs - s * 0.02, fs - s * 0.02))
			ci.draw_rect(facet, Color.from_hsv(hue, 0.45, bright), true)
	rr_outline(ci, r, rad, col.lightened(0.40), 1.5)

# ── 20 CAT (secret: cartoony/anime kitty face, blinks + ear-twitch) ──────────
static func _cat(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var fur := col.lerp(Color(1.0, 0.86, 0.66), 0.45)   # soft pastel fur
	var dark := fur.darkened(0.45)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.28))
	var c := r.get_center()
	# Ears (triangles up top, with pink inner) — a gentle twitch
	var tw := sin(t * 2.0 + float(seed_v)) * s * 0.012
	for sgn : float in [-1.0, 1.0]:
		var ex := c.x + sgn * s * 0.26
		var ey := r.position.y + s * 0.16
		ci.draw_polygon(PackedVector2Array([
			Vector2(ex - s * 0.14, ey + s * 0.02), Vector2(ex + sgn * tw, ey - s * 0.18),
			Vector2(ex + s * 0.14, ey + s * 0.02)]), PackedColorArray([fur.darkened(0.10)]))
		ci.draw_polygon(PackedVector2Array([
			Vector2(ex - s * 0.06, ey - s * 0.01), Vector2(ex + sgn * tw, ey - s * 0.12),
			Vector2(ex + s * 0.06, ey - s * 0.01)]), PackedColorArray([Color(1.0, 0.65, 0.72)]))
	# Head
	rr_grad(ci, r, rad, fur.lightened(0.18), fur.darkened(0.12))
	rr_outline(ci, r, rad, dark, 1.5)
	# Eyes — big anime eyes that blink (~every few seconds, seeded phase)
	var blink := fmod(t * 0.6 + float(seed_v % 11) * 0.5, 1.0)
	var open := blink > 0.06
	var eye_y := c.y + s * 0.02
	for sgn2 : float in [-1.0, 1.0]:
		var ex2 := c.x + sgn2 * s * 0.20
		if open:
			ci.draw_circle(Vector2(ex2, eye_y), s * 0.115, Color(0.10, 0.09, 0.14))   # eye
			ci.draw_circle(Vector2(ex2, eye_y), s * 0.115, dark)
			ci.draw_circle(Vector2(ex2, eye_y + s * 0.01), s * 0.085, Color(0.12, 0.10, 0.16))
			# Iris glow + sparkle
			ci.draw_circle(Vector2(ex2, eye_y + s * 0.015), s * 0.05,
				Color(col.lightened(0.35).r, col.lightened(0.35).g, col.lightened(0.35).b, 0.9))
			ci.draw_circle(Vector2(ex2 - s * 0.03, eye_y - s * 0.03), s * 0.028, Color(1, 1, 1, 0.95))
			ci.draw_circle(Vector2(ex2 + s * 0.025, eye_y + s * 0.03), s * 0.014, Color(1, 1, 1, 0.6))
		else:
			# Closed: a happy upward curve  ^_^
			ci.draw_arc(Vector2(ex2, eye_y + s * 0.04), s * 0.10, PI * 1.15, PI * 1.85, 8, dark, 2.0)
	# Blush cheeks
	ci.draw_circle(c + Vector2(-s * 0.30, s * 0.10), s * 0.05, Color(1.0, 0.55, 0.65, 0.5))
	ci.draw_circle(c + Vector2(s * 0.30, s * 0.10), s * 0.05, Color(1.0, 0.55, 0.65, 0.5))
	# Nose (:3 mouth)
	var nx := c.x
	var ny := c.y + s * 0.18
	ci.draw_polygon(PackedVector2Array([
		Vector2(nx - s * 0.035, ny), Vector2(nx + s * 0.035, ny), Vector2(nx, ny + s * 0.03)]),
		PackedColorArray([Color(1.0, 0.55, 0.62)]))
	ci.draw_arc(Vector2(nx - s * 0.05, ny + s * 0.04), s * 0.05, 0, PI, 6, dark, 1.3)
	ci.draw_arc(Vector2(nx + s * 0.05, ny + s * 0.04), s * 0.05, 0, PI, 6, dark, 1.3)
	# Whiskers
	for wy in [ny - s * 0.02, ny + s * 0.05]:
		ci.draw_line(Vector2(c.x - s * 0.20, wy), Vector2(c.x - s * 0.42, wy - s * 0.03), dark, 1.2)
		ci.draw_line(Vector2(c.x + s * 0.20, wy), Vector2(c.x + s * 0.42, wy - s * 0.03), dark, 1.2)

# ── 11 GALAXY (animated) ──────────────────────────────────────────────────────
static func _galaxy(ci: CanvasItem, r: Rect2, col: Color, s: float, rad: float, seed_v: int) -> void:
	var g := col.lerp(Color(0.45, 0.22, 0.80), 0.55)
	var t := Time.get_ticks_msec() * 0.001
	rr_fill(ci, Rect2(r.position + Vector2(s * 0.03, s * 0.06), r.size), rad, Color(0, 0, 0, 0.35))
	rr_grad(ci, r, rad, g.darkened(0.45), Color(0.06, 0.03, 0.12))
	var np := r.position + r.size * Vector2(0.35 + float(seed_v % 4) * 0.10, 0.40 + float(seed_v % 3) * 0.12)
	ci.draw_circle(np, s * 0.28, Color(g.r, g.g, g.b, 0.18))
	ci.draw_circle(np + Vector2(s * 0.11, -s * 0.09), s * 0.16,
		Color(g.lightened(0.30).r, g.lightened(0.30).g, g.lightened(0.30).b, 0.15))
	for i in 5:
		var px : float = r.position.x + s * 0.11 + float((seed_v * 31 + i * 47) % 100) / 100.0 * (r.size.x - s * 0.23)
		var py : float = r.position.y + s * 0.11 + float((seed_v * 19 + i * 61) % 100) / 100.0 * (r.size.y - s * 0.23)
		var tw : float = 0.35 + 0.65 * absf(sin(t * 2.0 + float(seed_v + i * 7) * 1.3))
		ci.draw_circle(Vector2(px, py), s * 0.03, Color(1, 1, 1, tw))
	# Hero star lands somewhere different on every block (seeded)
	var hx := 0.18 + float((seed_v * 53) % 100) / 100.0 * 0.64
	var hy := 0.15 + float((seed_v * 29) % 100) / 100.0 * 0.58
	var hp := r.position + r.size * Vector2(hx, hy)
	var ha := 0.45 + 0.55 * absf(sin(t * 1.6 + float(seed_v) * 0.9))
	ci.draw_line(hp + Vector2(-s * 0.09, 0), hp + Vector2(s * 0.09, 0), Color(1, 1, 1, ha), 1.0)
	ci.draw_line(hp + Vector2(0, -s * 0.09), hp + Vector2(0, s * 0.09), Color(1, 1, 1, ha), 1.0)
	ci.draw_circle(hp, s * 0.036, Color(1, 1, 1, ha))
	rr_outline(ci, r, rad, g.lightened(0.25), 1.5)
