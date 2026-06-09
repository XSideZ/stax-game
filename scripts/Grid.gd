class_name Grid
extends Node2D

const COLS := 8
const ROWS := 8
const CELL := 44.0
const GAP  := 2.0
const STEP := CELL + GAP

var cells       : Array = []
var ghost_cells : Array[Vector2i] = []
var ghost_color := Color.TRANSPARENT
var block_style : int = 0   # set by Game.gd on theme change

var last_lines_cleared : int = 0

const CLEAR_DUR := 0.55
var clear_cells : Array[Vector2i] = []
var clear_t     : float = 0.0
var clearing    : bool  = false

var place_anim  : Array = []

func _ready() -> void:
	cells.resize(ROWS)
	for r in ROWS:
		cells[r] = []
		cells[r].resize(COLS)
		cells[r].fill(null)

func _process(delta: float) -> void:
	var needs_redraw := false

	var done: Array = []
	for pa in place_anim:
		pa["t"] += delta / 0.22
		if pa["t"] >= 1.0:
			done.append(pa)
		needs_redraw = true
	for pa in done:
		place_anim.erase(pa)

	if clearing:
		clear_t += delta / CLEAR_DUR
		if clear_t >= 1.0:
			clearing    = false
			clear_cells = []
			clear_t     = 0.0
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	for r in ROWS:
		for c in COLS:
			_draw_cell(r, c)
	if clearing:
		_draw_clear_flash()

func _draw_cell(r: int, c: int) -> void:
	var rect := Rect2(c * STEP, r * STEP, CELL, CELL)
	var col  : Color = cells[r][c] if cells[r][c] != null else Color.TRANSPARENT
	var gv   := Vector2i(c, r)

	if col == Color.TRANSPARENT:
		if ghost_cells.has(gv):
			draw_rect(rect, Color(ghost_color.r, ghost_color.g, ghost_color.b, 0.30), true)
			draw_rect(rect, Color(ghost_color.r, ghost_color.g, ghost_color.b, 0.65), false, 1.5)
		else:
			draw_rect(rect, Color(0.10, 0.08, 0.15), true)
			draw_rect(rect, Color(0.18, 0.14, 0.24), false, 1.0)
		return

	var scale := 1.0
	for pa in place_anim:
		if pa["r"] == r and pa["c"] == c:
			scale = 1.0 + sin(pa["t"] * PI) * 0.18
			break

	var drv := rect
	if scale != 1.0:
		drv = rect.grow(CELL * (scale - 1.0) * 0.5)

	match block_style:
		0: _draw_pastel(drv, col)
		1: _draw_neon(drv, col)
		2: _draw_circuit(drv, col)
		3: _draw_brick(drv, col)
		4: _draw_crystal(drv, col)

	if scale > 1.02:
		var glow_a := (scale - 1.0) / 0.18 * 0.5
		draw_rect(drv.grow(4), Color(col.r, col.g, col.b, glow_a), false, 3.0)

# ── Block style: PASTEL ───────────────────────────────────────────────────────
# Soft candy-like blocks, lighter fills, gentle bevels
func _draw_pastel(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(1.5, 1.5), r.size + Vector2(3.0, 3.0)), Color(0, 0, 0, 0.18), true)
	draw_rect(r, col.lightened(0.28), true)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), col.lightened(0.65), true)
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), col.lightened(0.65), true)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4)), col.darkened(0.12), true)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 4, 0), Vector2(4, r.size.y)), col.darkened(0.12), true)
	# Soft shine dot in top-left quadrant
	draw_rect(Rect2(r.position + r.size * 0.18, Vector2(7, 7)), col.lightened(0.80), true)

# ── Block style: NEON ─────────────────────────────────────────────────────────
# Nearly black fill, glowing coloured border + bloom layers
func _draw_neon(r: Rect2, col: Color) -> void:
	draw_rect(r.grow(8), Color(col.r, col.g, col.b, 0.05), true)
	draw_rect(r.grow(4), Color(col.r, col.g, col.b, 0.12), true)
	draw_rect(r.grow(2), Color(col.r, col.g, col.b, 0.22), true)
	draw_rect(r, col.darkened(0.82), true)
	draw_rect(r, col, false, 2.0)
	draw_rect(r.grow(-2), Color(col.r, col.g, col.b, 0.28), false, 1.0)
	# Corner glow dot
	draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(5, 5)), col.lightened(0.45), true)

# ── Block style: CIRCUIT ──────────────────────────────────────────────────────
# Dark fill with PCB trace lines and node dots
func _draw_circuit(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size + Vector2(4, 4)), Color(0, 0, 0, 0.40), true)
	draw_rect(r, col.darkened(0.32), true)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), col.lightened(0.38), true)
	draw_rect(Rect2(r.position, Vector2(4, r.size.y)), col.lightened(0.38), true)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), col.darkened(0.52), true)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 3, 0), Vector2(3, r.size.y)), col.darkened(0.52), true)
	var lc  := Color(col.r, col.g, col.b, 0.55)
	var y1  := r.position.y + r.size.y * 0.38
	var y2  := r.position.y + r.size.y * 0.65
	var x1  := r.position.x + r.size.x * 0.40
	draw_line(Vector2(r.position.x + 5, y1), Vector2(r.end.x - 5, y1), lc, 1.0)
	draw_line(Vector2(r.position.x + 5, y2), Vector2(r.end.x - 5, y2), lc, 1.0)
	draw_line(Vector2(x1, r.position.y + 5), Vector2(x1, r.end.y - 5), lc, 1.0)
	draw_rect(Rect2(Vector2(x1 - 2, y1 - 2), Vector2(4, 4)), col.lightened(0.65), true)
	draw_rect(Rect2(Vector2(x1 - 2, y2 - 2), Vector2(4, 4)), col.lightened(0.65), true)

# ── Block style: BRICK ────────────────────────────────────────────────────────
# Mortar-gap surround with inset face, rough bevel
func _draw_brick(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size + Vector2(6, 6)), Color(0, 0, 0, 0.50), true)
	draw_rect(r, col.darkened(0.48), true)
	var inner := r.grow(-4)
	draw_rect(inner, col.darkened(0.08), true)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 4)), col.lightened(0.30), true)
	draw_rect(Rect2(inner.position, Vector2(4, inner.size.y)), col.lightened(0.24), true)
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - 4), Vector2(inner.size.x, 4)), col.darkened(0.58), true)
	draw_rect(Rect2(inner.position + Vector2(inner.size.x - 4, 0), Vector2(4, inner.size.y)), col.darkened(0.58), true)

# ── Block style: CRYSTAL ──────────────────────────────────────────────────────
# Four-facet gem look using per-vertex colour triangles
func _draw_crystal(r: Rect2, col: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size + Vector2(4, 4)), Color(0, 0, 0, 0.45), true)
	draw_rect(r, col, true)
	var tl  := r.position
	var tr  := r.position + Vector2(r.size.x, 0)
	var bl  := r.position + Vector2(0, r.size.y)
	var br  := r.end
	var ctr := r.get_center()
	# Top facet (bright)
	draw_polygon(PackedVector2Array([tl, tr, ctr]),
		PackedColorArray([col.lightened(0.55), col.lightened(0.28), col.lightened(0.12)]))
	# Left facet (medium bright)
	draw_polygon(PackedVector2Array([tl, bl, ctr]),
		PackedColorArray([col.lightened(0.38), col.lightened(0.08), col.lightened(0.12)]))
	# Right facet (slightly dark)
	draw_polygon(PackedVector2Array([tr, br, ctr]),
		PackedColorArray([col.darkened(0.18), col.darkened(0.38), col.darkened(0.08)]))
	# Bottom facet (dark)
	draw_polygon(PackedVector2Array([bl, br, ctr]),
		PackedColorArray([col.darkened(0.22), col.darkened(0.52), col.darkened(0.12)]))
	# Thin bright outline
	draw_rect(r, col.lightened(0.50), false, 1.0)
	# Centre sparkle
	draw_rect(Rect2(ctr - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, 0.65), true)

# ── Clear animation ───────────────────────────────────────────────────────────
func _draw_clear_flash() -> void:
	var total := clear_cells.size()
	if total == 0:
		return
	for idx in total:
		var cv     : Vector2i = clear_cells[idx]
		var rect   := Rect2(cv.x * STEP, cv.y * STEP, CELL, CELL)
		var appear : float    = float(idx) / float(total) * 0.55
		if clear_t < appear:
			continue
		var a     : float
		var scale : float
		if clear_t < 0.60:
			a     = 1.0
			scale = 1.0 + minf((clear_t - appear) * 0.25, 0.12)
		else:
			a     = 1.0 - (clear_t - 0.60) / 0.40
			scale = 1.12
		var exp := CELL * (scale - 1.0) * 0.5
		draw_rect(rect.grow(exp), Color(1, 1, 1, a), true)

# ── Grid logic ────────────────────────────────────────────────────────────────
func can_place(shape: Array, row: int, col: int) -> bool:
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		if r < 0 or r >= ROWS or c < 0 or c >= COLS:
			return false
		if cells[r][c] != null:
			return false
	return true

func place(shape: Array, row: int, col: int, color: Color) -> void:
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		cells[r][c] = color
		place_anim.append({"r": r, "c": c, "t": 0.0})
	ghost_cells = []
	queue_redraw()

func check_and_clear() -> int:
	var full_rows : Array[int] = []
	var full_cols : Array[int] = []

	for r in ROWS:
		var full := true
		for c in COLS:
			if cells[r][c] == null:
				full = false; break
		if full: full_rows.append(r)

	for c in COLS:
		var full := true
		for r in ROWS:
			if cells[r][c] == null:
				full = false; break
		if full: full_cols.append(c)

	last_lines_cleared = full_rows.size() + full_cols.size()

	if full_rows.is_empty() and full_cols.is_empty():
		return 0

	clear_cells = []
	for r in full_rows:
		for c in COLS:
			clear_cells.append(Vector2i(c, r))
	for c in full_cols:
		for r in ROWS:
			var cv := Vector2i(c, r)
			if not clear_cells.has(cv):
				clear_cells.append(cv)

	for r in full_rows:
		for c in COLS: cells[r][c] = null
	for c in full_cols:
		for r in ROWS: cells[r][c] = null

	clear_t  = 0.0
	clearing = true
	queue_redraw()

	var base  : int = full_rows.size() * COLS + full_cols.size() * ROWS
	var bonus : int = (last_lines_cleared - 1) * 25 if last_lines_cleared > 1 else 0
	return base + bonus

func is_board_empty() -> bool:
	for r in ROWS:
		for c in COLS:
			if cells[r][c] != null:
				return false
	return true

func set_ghost(shape: Array, row: int, col: int, color: Color) -> void:
	ghost_cells = []
	ghost_color = color
	for cell in shape:
		var r : int = row + cell[1]
		var c : int = col + cell[0]
		if r >= 0 and r < ROWS and c >= 0 and c < COLS:
			ghost_cells.append(Vector2i(c, r))
	queue_redraw()

func clear_ghost() -> void:
	if not ghost_cells.is_empty():
		ghost_cells = []
		queue_redraw()

func can_any_fit(pieces: Array, placed: Array) -> bool:
	for i in pieces.size():
		if placed[i]: continue
		for r in ROWS:
			for c in COLS:
				if can_place(pieces[i], r, c):
					return true
	return false
