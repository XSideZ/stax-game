extends Node2D

# ── Piece shapes ──────────────────────────────────────────────────────────────
const SHAPES: Array = [
	[[0,0]],
	[[0,0],[1,0]],
	[[0,0],[0,1]],
	[[0,0],[1,0],[2,0]],
	[[0,0],[0,1],[0,2]],
	[[0,0],[1,0],[2,0],[3,0]],
	[[0,0],[0,1],[0,2],[0,3]],
	[[0,0],[1,0],[2,0],[3,0],[4,0]],
	[[0,0],[0,1],[0,2],[0,3],[0,4]],
	[[0,0],[1,0],[0,1],[1,1]],
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],
	[[0,0],[1,0],[0,1]],
	[[0,0],[1,0],[1,1]],
	[[0,0],[0,1],[1,1]],
	[[1,0],[0,1],[1,1]],
	[[0,0],[0,1],[0,2],[1,2]],
	[[1,0],[1,1],[0,2],[1,2]],
	[[0,0],[1,0],[2,0],[1,1]],
	[[0,0],[1,0],[2,0],[0,1]],
	[[0,0],[1,0],[2,0],[2,1]],
	[[0,0],[1,0],[1,1],[1,2]],
	[[0,0],[1,0],[0,1],[0,2]],
	# S / Z tetrominoes (horizontal + vertical)
	[[1,0],[2,0],[0,1],[1,1]],
	[[0,0],[1,0],[1,1],[2,1]],
	[[0,0],[0,1],[1,1],[1,2]],
	[[1,0],[0,1],[1,1],[0,2]],
	# T rotations (up / left / right — down already exists)
	[[1,0],[0,1],[1,1],[2,1]],
	[[0,0],[0,1],[1,1],[0,2]],
	[[1,0],[0,1],[1,1],[1,2]],
	# Plus / cross
	[[1,0],[0,1],[1,1],[2,1],[1,2]],
	# Filled 2×3 and 3×2 rectangles
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1]],
	[[0,0],[1,0],[0,1],[1,1],[0,2],[1,2]],
]

const COLORS: Array = [
	Color(0.20, 0.75, 0.95),
	Color(1.00, 0.55, 0.15),
	Color(0.90, 0.25, 0.60),
	Color(0.20, 0.85, 0.45),
	Color(0.65, 0.30, 0.95),
	Color(0.95, 0.85, 0.15),
]

# ── Themes ────────────────────────────────────────────────────────────────────
# Each theme controls: bg color, orb accent, name, block style (matches index)
# Style 0=Pastel  1=Neon  2=Circuit  3=Brick  4=Crystal
const THEMES: Array = [
	{"bg": Color(0.06, 0.05, 0.09), "orb": Color(0.55, 0.70, 1.00, 0.07), "name": "DEEP SPACE"},
	{"bg": Color(0.03, 0.08, 0.04), "orb": Color(0.20, 1.00, 0.45, 0.07), "name": "NEON JUNGLE"},
	{"bg": Color(0.07, 0.03, 0.10), "orb": Color(0.70, 0.20, 1.00, 0.07), "name": "SYNTHWAVE"},
	{"bg": Color(0.10, 0.05, 0.01), "orb": Color(1.00, 0.50, 0.10, 0.07), "name": "SOLAR FLARE"},
	{"bg": Color(0.03, 0.05, 0.12), "orb": Color(0.40, 0.65, 1.00, 0.07), "name": "NEBULA"},
]
const THEME_INTERVAL := 7

# ── Layout ────────────────────────────────────────────────────────────────────
const GRID_X    := 24.0
const GRID_Y    := 175.0
const CELL      := 44.0
const GRID_STEP := 46.0
const GRID_COLS := 8
const GRID_ROWS := 8

const TRAY_Y    := 600.0
const TRAY_H    := 175.0
const TRAY_CELL := 28.0
const TRAY_STEP := 29.0
const SLOT_W    := 138.0

const EARLY_SHAPES: Array = [
	[[0,0]],
	[[0,0],[1,0]],
	[[0,0],[0,1]],
	[[0,0],[1,0],[2,0]],
	[[0,0],[0,1],[0,2]],
	[[0,0],[1,0],[0,1]],
	[[0,0],[1,0],[1,1]],
	[[0,0],[0,1],[1,1]],
	[[1,0],[0,1],[1,1]],
	[[0,0],[1,0],[0,1],[1,1]],
]

# ── State ─────────────────────────────────────────────────────────────────────
var pieces        : Array   = []
var placed        : Array   = [false, false, false]
var dragging_slot : int     = -1
var drag_pos      : Vector2 = Vector2.ZERO
var score         : int     = 0
var sets_given    : int     = 0
var lines_cleared : int     = 0
var combo         : int     = 0

# Theme / background
var theme_idx     : int    = 0
var prev_bg       : Color  = THEMES[0]["bg"]
var curr_bg       : Color  = THEMES[0]["bg"]
var theme_lerp    : float  = 1.0

# Screen shake
var shake_t      : float   = 0.0
var shake_offset : Vector2 = Vector2.ZERO

# Transition flash
var flash_t   : float = 0.0
var flash_col : Color = Color.TRANSPARENT

# Animated orbs
const ORB_COUNT := 14
var orbs: Array = []

@onready var grid        : Grid        = $Grid
@onready var score_label : Label       = $UI/ScoreLabel
@onready var best_label  : Label       = $UI/BestLabel
@onready var combo_label : Label       = $UI/ComboLabel
@onready var ui          : CanvasLayer = $UI

func _ready() -> void:
	_init_orbs()
	grid.block_style = theme_idx
	if GameState.has_save:
		_restore_state()
		GameState.has_save = false
	else:
		_spawn_pieces()
	_refresh_best()

# ── Orbs ──────────────────────────────────────────────────────────────────────
func _init_orbs() -> void:
	orbs = []
	for _i in ORB_COUNT:
		orbs.append(_make_orb())

func _make_orb() -> Dictionary:
	var orb_col: Color = THEMES[theme_idx]["orb"]
	return {
		"pos":    Vector2(randf() * 414.0, randf() * 896.0),
		"vel":    Vector2((randf() - 0.5) * 22.0, (randf() - 0.5) * 22.0),
		"radius": randf_range(50.0, 130.0),
		"color":  Color(orb_col.r, orb_col.g, orb_col.b, randf_range(0.04, 0.11)),
	}

func _update_orbs(delta: float) -> void:
	for orb in orbs:
		orb["pos"] += orb["vel"] * delta
		if orb["pos"].x < -140.0 or orb["pos"].x > 554.0:
			orb["vel"].x = -orb["vel"].x
		if orb["pos"].y < -140.0 or orb["pos"].y > 1036.0:
			orb["vel"].y = -orb["vel"].y

# ── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_orbs(delta)

	if theme_lerp < 1.0:
		theme_lerp = minf(theme_lerp + delta / 1.5, 1.0)

	if shake_t > 0.0:
		shake_t = maxf(shake_t - delta, 0.0)
		var intensity := shake_t * shake_t * 20.0
		shake_offset = Vector2(
			sin(shake_t * 53.0) * intensity,
			cos(shake_t * 41.0) * intensity * 0.6
		)
		grid.position = Vector2(GRID_X, GRID_Y) + shake_offset
	else:
		shake_offset = Vector2.ZERO
		grid.position = Vector2(GRID_X, GRID_Y)

	if flash_t > 0.0:
		flash_t = maxf(flash_t - delta / 0.35, 0.0)

	queue_redraw()

# ── Spawning ──────────────────────────────────────────────────────────────────
func _spawn_pieces() -> void:
	pieces        = []
	placed        = [false, false, false]
	dragging_slot = -1

	var picked_keys: Array = []
	for _i in 3:
		var shape := _pick_shape()
		var key   := str(shape)
		# Never give three identical shapes — when blocked, pick from EARLY_SHAPES
		# excluding the duplicate. Don't re-call _pick_shape() which may always
		# return the same thing when the board has only one matching gap pattern.
		if picked_keys.size() == 2 and picked_keys[0] == picked_keys[1] and key == picked_keys[0]:
			var blocked : String = picked_keys[0]
			var alts: Array = []
			for s in EARLY_SHAPES:
				if str(s) != blocked:
					alts.append(s)
			if alts.is_empty():
				for s in SHAPES:
					if str(s) != blocked:
						alts.append(s)
			if not alts.is_empty():
				shape = alts[randi() % alts.size()]
				key   = str(shape)
		picked_keys.append(key)
		pieces.append({"shape": shape, "color": COLORS[randi() % COLORS.size()]})

	sets_given += 1
	grid.clear_ghost()
	queue_redraw()
	if not grid.can_any_fit(_shapes_array(), placed):
		_game_over()

func _progression() -> float:
	return clampf((sets_given - 2) / 10.0, 0.0, 1.0)

func _pick_shape() -> Array:
	if randf() < _progression():
		return SHAPES[randi() % SHAPES.size()]
	return _pick_helpful_shape()

func _pick_helpful_shape() -> Array:
	var best_row    := -1
	var best_filled := 0
	for r in GRID_ROWS:
		var filled := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null:
				filled += 1
		if filled > best_filled and filled < GRID_COLS:
			best_filled = filled
			best_row    = r

	if best_row >= 0 and best_filled >= 3:
		var max_gap := 0
		var run     := 0
		for c in GRID_COLS:
			if grid.cells[best_row][c] == null:
				run += 1
				max_gap = max(max_gap, run)
			else:
				run = 0
		max_gap = min(max_gap, 5)
		if max_gap >= 1:
			var gap_shape: Array = []
			for i in max_gap:
				gap_shape.append([i, 0])
			for r in GRID_ROWS:
				for c in GRID_COLS:
					if grid.can_place(gap_shape, r, c):
						return gap_shape

	var candidates: Array = []
	for s in EARLY_SHAPES:
		var fits := false
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if grid.can_place(s, r, c):
					fits = true; break
			if fits: break
		if fits: candidates.append(s)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]

	var any_fitting: Array = []
	for s in SHAPES:
		var fits := false
		for r in GRID_ROWS:
			for c in GRID_COLS:
				if grid.can_place(s, r, c):
					fits = true; break
			if fits: break
		if fits: any_fitting.append(s)
	if not any_fitting.is_empty():
		return any_fitting[randi() % any_fitting.size()]

	return SHAPES[randi() % SHAPES.size()]

func _shapes_array() -> Array:
	var arr: Array = []
	for p in pieces:
		arr.append(p.shape)
	return arr

# ── Watch-ad restore ──────────────────────────────────────────────────────────
func _restore_state() -> void:
	score         = GameState.save_score
	sets_given    = GameState.save_sets_given
	lines_cleared = GameState.save_lines_cleared
	combo         = GameState.save_combo
	theme_idx     = GameState.save_theme_idx
	curr_bg       = THEMES[theme_idx]["bg"]
	prev_bg       = curr_bg
	theme_lerp    = 1.0
	grid.block_style = theme_idx

	for r in GRID_ROWS:
		for c in GRID_COLS:
			grid.cells[r][c] = GameState.save_cells[r][c]

	_help_player_continue()

	pieces = GameState.save_pieces.duplicate(true)
	placed = GameState.save_placed.duplicate()

	score_label.text = str(score)
	_update_combo_label()
	grid.queue_redraw()
	queue_redraw()

func _help_player_continue() -> void:
	var row_fills: Array = []
	for r in GRID_ROWS:
		var count := 0
		for c in GRID_COLS:
			if grid.cells[r][c] != null: count += 1
		row_fills.append({"r": r, "count": count})
	row_fills.sort_custom(func(a, b): return a["count"] > b["count"])
	for i in min(2, row_fills.size()):
		if row_fills[i]["count"] == 0: break
		var r : int = row_fills[i]["r"]
		for c in GRID_COLS:
			grid.cells[r][c] = null

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _start_drag(event.position)
		else:             _end_drag(event.position)
	elif event is InputEventMouseMotion and dragging_slot >= 0:
		drag_pos = event.position
		_update_ghost()
		queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed: _start_drag(event.position)
		else:             _end_drag(event.position)
	elif event is InputEventScreenDrag and dragging_slot >= 0:
		drag_pos = event.position
		_update_ghost()
		queue_redraw()

func _start_drag(pos: Vector2) -> void:
	var slot := _pos_to_slot(pos)
	if slot >= 0 and not placed[slot]:
		dragging_slot = slot
		drag_pos      = pos
		queue_redraw()

func _end_drag(pos: Vector2) -> void:
	if dragging_slot < 0:
		return
	var shape : Array    = pieces[dragging_slot].shape
	var color : Color    = pieces[dragging_slot].color
	var snap  : Vector2i = _get_snap(pos, shape)

	if grid.can_place(shape, snap.y, snap.x):
		grid.place(shape, snap.y, snap.x, color)
		placed[dragging_slot] = true

		var clear_bonus : int = grid.check_and_clear()

		if grid.last_lines_cleared > 0:
			combo += 1
		else:
			combo = 0

		var multiplier : int = max(1, combo)
		var gained     : int = (shape.size() + clear_bonus) * multiplier

		if grid.is_board_empty():
			gained += 500 * multiplier
			_show_board_clear_popup()

		score += gained
		score_label.text = str(score)
		GameState.submit_score(score)
		_refresh_best()
		_pop_score(gained)
		_show_score_popup(gained, grid.last_lines_cleared, multiplier)
		_show_clear_text(grid.last_lines_cleared)
		_update_combo_label()

		var new_total   := lines_cleared + grid.last_lines_cleared
		var old_bracket := lines_cleared / THEME_INTERVAL
		var new_bracket := new_total     / THEME_INTERVAL
		lines_cleared = new_total
		if new_bracket > old_bracket:
			_advance_theme()

		if placed[0] and placed[1] and placed[2]:
			_spawn_pieces()
		elif not grid.can_any_fit(_shapes_array(), placed):
			_game_over()

	dragging_slot = -1
	grid.clear_ghost()
	queue_redraw()

func _update_ghost() -> void:
	if dragging_slot < 0 or placed[dragging_slot]:
		return
	var shape : Array    = pieces[dragging_slot].shape
	var snap  : Vector2i = _get_snap(drag_pos, shape)
	if grid.can_place(shape, snap.y, snap.x):
		grid.set_ghost(shape, snap.y, snap.x, pieces[dragging_slot].color)
	else:
		grid.clear_ghost()

func _get_snap(pos: Vector2, shape: Array) -> Vector2i:
	var min_c := 99; var max_c := 0
	var min_r := 99; var max_r := 0
	for cell in shape:
		if (cell[0] as int) < min_c: min_c = cell[0]
		if (cell[0] as int) > max_c: max_c = cell[0]
		if (cell[1] as int) < min_r: min_r = cell[1]
		if (cell[1] as int) > max_r: max_r = cell[1]
	var gc := _screen_to_grid(pos)
	return Vector2i(
		gc.x - roundi((min_c + max_c) / 2.0),
		gc.y - roundi((min_r + max_r) / 2.0)
	)

func _screen_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(
		int((pos.x - GRID_X) / GRID_STEP),
		int((pos.y - GRID_Y) / GRID_STEP)
	)

func _pos_to_slot(pos: Vector2) -> int:
	if pos.y < TRAY_Y or pos.y > TRAY_Y + TRAY_H:
		return -1
	for i in 3:
		if pos.x >= i * SLOT_W and pos.x < (i + 1) * SLOT_W:
			return i
	return -1

# ── Theme ─────────────────────────────────────────────────────────────────────
func _advance_theme() -> void:
	prev_bg    = curr_bg
	theme_idx  = (theme_idx + 1) % THEMES.size()
	curr_bg    = THEMES[theme_idx]["bg"]
	theme_lerp = 0.0

	var orb_col: Color = THEMES[theme_idx]["orb"]
	for orb in orbs:
		orb["color"] = Color(orb_col.r, orb_col.g, orb_col.b, orb["color"].a)
		orb["vel"]   *= 1.4   # burst of speed on transition

	grid.block_style = theme_idx

	# Screen shake
	shake_t = 0.50

	# Bright flash in the theme's accent colour
	flash_col = Color(
		minf(orb_col.r * 4.0, 1.0),
		minf(orb_col.g * 4.0, 1.0),
		minf(orb_col.b * 4.0, 1.0),
		1.0
	)
	flash_t = 1.0

	_show_theme_popup(THEMES[theme_idx]["name"])

func _show_theme_popup(theme_name: String) -> void:
	var lbl := Label.new()
	lbl.text = theme_name
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(300, 48)
	lbl.position = Vector2(57, 460)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, 0.18)
	t.tween_interval(0.9)
	t.tween_property(lbl, "modulate:a", 0.0, 0.40)
	t.tween_callback(lbl.queue_free)

# ── Drawing ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	# Apply shake to all background / tray drawing
	draw_set_transform(shake_offset)

	# Background
	var bg : Color = prev_bg.lerp(curr_bg, theme_lerp)
	draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), bg, true)

	# Per-theme background pattern
	_draw_bg_pattern()

	# Orbs
	for orb in orbs:
		draw_circle(orb["pos"], orb["radius"], orb["color"])

	# Transition flash overlay
	if flash_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)),
			Color(flash_col.r, flash_col.g, flash_col.b, flash_t * 0.40), true)

	# Grid backdrop
	var grid_rect := Rect2(GRID_X - 6, GRID_Y - 6,
		GRID_COLS * GRID_STEP + 10, GRID_ROWS * GRID_STEP + 10)
	draw_rect(grid_rect, Color(0, 0, 0, 0.28), true)
	draw_rect(grid_rect, Color(1, 1, 1, 0.06), false, 1.5)

	# Tray
	for i in 3:
		_draw_slot(i)

	if dragging_slot >= 0 and not placed[dragging_slot]:
		_draw_dragging_piece()

	draw_set_transform(Vector2.ZERO)

func _draw_bg_pattern() -> void:
	match theme_idx:
		0:  # Deep Space — distant stars
			for i in 50:
				var sx : float = fmod(float(i * 97  + 13) * 37.3, 414.0)
				var sy : float = fmod(float(i * 53  + 71) * 19.7, 896.0)
				var sa : float = fmod(float(i * 31) * 0.13,  0.35) + 0.08
				draw_rect(Rect2(sx, sy, 2.0, 2.0), Color(1, 1, 1, sa), true)
		1:  # Neon Jungle — scanlines
			for y_line in range(0, 896, 5):
				draw_line(Vector2(0, y_line), Vector2(414, y_line),
					Color(0, 0, 0, 0.07), 1.0)
		2:  # Synthwave — perspective grid
			for gx in range(0, 414, 38):
				draw_line(Vector2(gx, 0), Vector2(gx, 896),
					Color(0.65, 0.20, 1.0, 0.07), 1.0)
			for gy in range(0, 896, 38):
				draw_line(Vector2(0, gy), Vector2(414, gy),
					Color(0.65, 0.20, 1.0, 0.05), 1.0)
		3:  # Solar Flare — diagonal heat streaks
			for i in 10:
				var ys : float = float(i) * 95.0
				draw_line(Vector2(0, ys + 30), Vector2(414, ys - 30),
					Color(1.0, 0.55, 0.10, 0.045), 2.5)
		4:  # Nebula — faint concentric rings
			for i in 4:
				draw_arc(Vector2(207, 448), 70.0 + i * 75.0, 0, TAU, 64,
					Color(0.40, 0.60, 1.0, 0.05), 1.5, false)

func _draw_slot(i: int) -> void:
	var sx   : float = i * SLOT_W
	var rect := Rect2(sx + 6, TRAY_Y, SLOT_W - 12, TRAY_H)
	var bg   : Color = Color(0.18, 0.14, 0.24) if dragging_slot == i else Color(0.11, 0.09, 0.16)
	draw_rect(rect, bg, true)
	draw_rect(rect, Color(1, 1, 1, 0.05), false, 1.0)

	if placed[i]:
		return

	var shape : Array = pieces[i].shape
	var color : Color = pieces[i].color
	if dragging_slot == i:
		color = Color(color.r, color.g, color.b, 0.25)

	var min_c := 99; var max_c := 0
	var min_r := 99; var max_r := 0
	for cell in shape:
		if (cell[0] as int) < min_c: min_c = cell[0]
		if (cell[0] as int) > max_c: max_c = cell[0]
		if (cell[1] as int) < min_r: min_r = cell[1]
		if (cell[1] as int) > max_r: max_r = cell[1]

	var pw : float = (max_c - min_c + 1) * TRAY_STEP - 1.0
	var ph : float = (max_r - min_r + 1) * TRAY_STEP - 1.0
	var avail_w : float = SLOT_W - 12.0
	var scale_f : float = minf(1.0, minf(avail_w / pw, TRAY_H / ph))
	var tcell   : float = TRAY_CELL * scale_f
	var tstep   : float = TRAY_STEP * scale_f
	var pw_s    : float = pw * scale_f
	var ph_s    : float = ph * scale_f
	var ox : float = sx + 6.0 + (avail_w - pw_s) * 0.5 - min_c * tstep
	var oy : float = TRAY_Y + (TRAY_H - ph_s) * 0.5 - min_r * tstep

	for cell in shape:
		var rx : float = ox + cell[0] * tstep
		var ry : float = oy + cell[1] * tstep
		if dragging_slot == i:
			draw_rect(Rect2(rx, ry, tcell, tcell), color, true)
		else:
			_draw_styled_block(Rect2(rx, ry, tcell, tcell), color)

func _draw_dragging_piece() -> void:
	var shape : Array    = pieces[dragging_slot].shape
	var color : Color    = pieces[dragging_slot].color
	var snap  : Vector2i = _get_snap(drag_pos, shape)
	var over  : bool     = _is_over_grid(drag_pos)
	var valid : bool     = over and grid.can_place(shape, snap.y, snap.x)

	var ox : float
	var oy : float

	if over:
		ox = GRID_X + snap.x * GRID_STEP
		oy = GRID_Y + snap.y * GRID_STEP
	else:
		var min_c := 99; var max_c := 0; var min_r := 99; var max_r := 0
		for cell in shape:
			if (cell[0] as int) < min_c: min_c = cell[0]
			if (cell[0] as int) > max_c: max_c = cell[0]
			if (cell[1] as int) < min_r: min_r = cell[1]
			if (cell[1] as int) > max_r: max_r = cell[1]
		ox = drag_pos.x - (max_c - min_c + 1) * GRID_STEP * 0.5 - min_c * GRID_STEP
		oy = drag_pos.y - (max_r - min_r + 1) * GRID_STEP * 0.5 - min_r * GRID_STEP

	var draw_color : Color = color if (valid or not over) else Color(0.9, 0.2, 0.2, 0.7)

	for cell in shape:
		var rx : float = ox + cell[0] * GRID_STEP
		var ry : float = oy + cell[1] * GRID_STEP
		_draw_styled_block(Rect2(rx, ry, CELL, CELL), draw_color)

# ── Block style renderer (mirrors Grid.gd styles, proportional to rect size) ─
func _draw_styled_block(r: Rect2, col: Color) -> void:
	var s := r.size.x
	match grid.block_style:
		0:  # PASTEL
			draw_rect(Rect2(r.position + Vector2(s*0.04, s*0.04), r.size + Vector2(s*0.07, s*0.07)), Color(0,0,0,0.18), true)
			draw_rect(r, col.lightened(0.28), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, s*0.12)), col.lightened(0.65), true)
			draw_rect(Rect2(r.position, Vector2(s*0.12, r.size.y)), col.lightened(0.65), true)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - s*0.10), Vector2(r.size.x, s*0.10)), col.darkened(0.12), true)
			draw_rect(Rect2(r.position + Vector2(r.size.x - s*0.10, 0), Vector2(s*0.10, r.size.y)), col.darkened(0.12), true)
			draw_rect(Rect2(r.position + r.size * 0.18, Vector2(s*0.18, s*0.18)), col.lightened(0.80), true)
		1:  # NEON
			draw_rect(r.grow(s*0.18), Color(col.r, col.g, col.b, 0.05), true)
			draw_rect(r.grow(s*0.09), Color(col.r, col.g, col.b, 0.12), true)
			draw_rect(r.grow(s*0.05), Color(col.r, col.g, col.b, 0.22), true)
			draw_rect(r, col.darkened(0.82), true)
			draw_rect(r, col, false, 2.0)
			draw_rect(Rect2(r.position + Vector2(s*0.09, s*0.09), Vector2(s*0.13, s*0.13)), col.lightened(0.45), true)
		2:  # CIRCUIT
			draw_rect(Rect2(r.position + Vector2(s*0.05, s*0.05), r.size + Vector2(s*0.09, s*0.09)), Color(0,0,0,0.40), true)
			draw_rect(r, col.darkened(0.32), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, s*0.09)), col.lightened(0.38), true)
			draw_rect(Rect2(r.position, Vector2(s*0.09, r.size.y)), col.lightened(0.38), true)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - s*0.07), Vector2(r.size.x, s*0.07)), col.darkened(0.52), true)
			draw_rect(Rect2(r.position + Vector2(r.size.x - s*0.07, 0), Vector2(s*0.07, r.size.y)), col.darkened(0.52), true)
			var lc := Color(col.r, col.g, col.b, 0.55)
			var y1 := r.position.y + r.size.y * 0.38
			var x1 := r.position.x + r.size.x * 0.40
			draw_line(Vector2(r.position.x + s*0.12, y1), Vector2(r.end.x - s*0.12, y1), lc, 1.0)
			draw_line(Vector2(x1, r.position.y + s*0.12), Vector2(x1, r.end.y - s*0.12), lc, 1.0)
			draw_rect(Rect2(Vector2(x1 - s*0.05, y1 - s*0.05), Vector2(s*0.10, s*0.10)), col.lightened(0.65), true)
		3:  # BRICK
			draw_rect(Rect2(r.position + Vector2(s*0.07, s*0.07), r.size + Vector2(s*0.14, s*0.14)), Color(0,0,0,0.50), true)
			draw_rect(r, col.darkened(0.48), true)
			var inner := r.grow(-s*0.09)
			draw_rect(inner, col.darkened(0.08), true)
			draw_rect(Rect2(inner.position, Vector2(inner.size.x, s*0.09)), col.lightened(0.30), true)
			draw_rect(Rect2(inner.position, Vector2(s*0.09, inner.size.y)), col.lightened(0.24), true)
			draw_rect(Rect2(inner.position + Vector2(0, inner.size.y - s*0.09), Vector2(inner.size.x, s*0.09)), col.darkened(0.58), true)
			draw_rect(Rect2(inner.position + Vector2(inner.size.x - s*0.09, 0), Vector2(s*0.09, inner.size.y)), col.darkened(0.58), true)
		4:  # CRYSTAL
			draw_rect(Rect2(r.position + Vector2(s*0.05, s*0.05), r.size + Vector2(s*0.09, s*0.09)), Color(0,0,0,0.45), true)
			draw_rect(r, col, true)
			var tl  := r.position
			var tr  := r.position + Vector2(r.size.x, 0)
			var bl  := r.position + Vector2(0, r.size.y)
			var br  := r.end
			var ctr := r.get_center()
			draw_polygon(PackedVector2Array([tl, tr, ctr]), PackedColorArray([col.lightened(0.55), col.lightened(0.28), col.lightened(0.12)]))
			draw_polygon(PackedVector2Array([tl, bl, ctr]), PackedColorArray([col.lightened(0.38), col.lightened(0.08), col.lightened(0.12)]))
			draw_polygon(PackedVector2Array([tr, br, ctr]), PackedColorArray([col.darkened(0.18), col.darkened(0.38), col.darkened(0.08)]))
			draw_polygon(PackedVector2Array([bl, br, ctr]), PackedColorArray([col.darkened(0.22), col.darkened(0.52), col.darkened(0.12)]))
			draw_rect(r, col.lightened(0.50), false, 1.0)
			draw_rect(Rect2(ctr - Vector2(s*0.07, s*0.07), Vector2(s*0.14, s*0.14)), Color(1,1,1,0.65), true)

func _is_over_grid(pos: Vector2) -> bool:
	return pos.x >= GRID_X and pos.x <= GRID_X + GRID_COLS * GRID_STEP \
		and pos.y >= GRID_Y and pos.y <= GRID_Y + GRID_ROWS * GRID_STEP

# ── Score popups ──────────────────────────────────────────────────────────────
func _show_score_popup(amount: int, cleared_lines: int, multiplier: int) -> void:
	var lbl := Label.new()
	lbl.text = "+" + str(amount) + ("   x" + str(multiplier) if multiplier > 1 else "")
	lbl.add_theme_font_size_override("font_size", 32 if cleared_lines == 0 else 48)
	var pop_color : Color
	if multiplier >= 3:
		pop_color = Color(0.95, 0.85, 0.15, 1.0)
	elif cleared_lines > 0:
		pop_color = Color(0.20, 0.85, 0.45, 1.0)
	else:
		pop_color = Color(1, 1, 1, 0.9)
	lbl.add_theme_color_override("font_color", pop_color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(260, 60)
	lbl.position = Vector2(77, 120)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "position", Vector2(77, 60), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate", Color(pop_color.r, pop_color.g, pop_color.b, 0.0), 0.7)
	t.tween_callback(lbl.queue_free)

func _show_clear_text(lines: int) -> void:
	if lines == 0:
		return

	var text   : String
	var color  : Color
	var fsize  : int
	var bounce : float
	var hold   : float

	if lines == 1:
		text   = "NICE!"
		color  = Color(1.00, 1.00, 1.00, 1.0)
		fsize  = 38
		bounce = 1.18
		hold   = 0.30
	elif lines == 2:
		text   = "EXCELLENT!"
		color  = Color(0.20, 0.90, 0.50, 1.0)
		fsize  = 52
		bounce = 1.28
		hold   = 0.50
	elif lines == 3:
		text   = "AMAZING!"
		color  = Color(0.95, 0.85, 0.15, 1.0)
		fsize  = 66
		bounce = 1.40
		hold   = 0.70
	elif lines == 4:
		text   = "INCREDIBLE!"
		color  = Color(1.00, 0.50, 0.10, 1.0)
		fsize  = 72
		bounce = 1.52
		hold   = 0.90
	else:
		text   = "LEGENDARY!!!"
		color  = Color(0.90, 0.20, 0.65, 1.0)
		fsize  = 78
		bounce = 1.65
		hold   = 1.10

	var w    : float = 380.0
	var h    : float = float(fsize) + 24.0
	var px   : float = (414.0 - w) * 0.5
	var py   : float = 300.0

	# Glow halo behind (only for 2+ clears)
	if lines >= 2:
		var glow := Label.new()
		glow.text = text
		glow.add_theme_font_size_override("font_size", fsize + 6)
		glow.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.28))
		glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glow.size         = Vector2(w + 10, h + 10)
		glow.position     = Vector2(px - 5, py - 5)
		glow.scale        = Vector2(0.05, 0.05)
		glow.pivot_offset = Vector2((w + 10) * 0.5, (h + 10) * 0.5)
		ui.add_child(glow)
		var gt := create_tween()
		gt.tween_property(glow, "scale", Vector2(bounce * 1.08, bounce * 1.08), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		gt.tween_property(glow, "scale", Vector2(1.08, 1.08), 0.10)
		gt.tween_interval(hold + 0.15)
		gt.tween_property(glow, "modulate:a", 0.0, 0.45)
		gt.tween_callback(glow.queue_free)

	# Main label
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size         = Vector2(w, h)
	lbl.position     = Vector2(px, py)
	lbl.scale        = Vector2(0.05, 0.05)
	lbl.pivot_offset = Vector2(w * 0.5, h * 0.5)
	ui.add_child(lbl)

	var t := create_tween()
	# Pop in with bounce
	t.tween_property(lbl, "scale", Vector2(bounce, bounce), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.10).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

	# Extra wobble for big clears
	if lines >= 3:
		t.tween_property(lbl, "scale", Vector2(1.10, 0.92), 0.06)
		t.tween_property(lbl, "scale", Vector2(0.94, 1.08), 0.06)
		t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.06)

	# Double pulse for huge clears
	if lines >= 4:
		t.tween_property(lbl, "scale", Vector2(1.14, 1.14), 0.09).set_trans(Tween.TRANS_SINE)
		t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.09).set_trans(Tween.TRANS_SINE)

	# Legendary gets a third pulse + color flash
	if lines >= 5:
		t.tween_property(lbl, "scale", Vector2(1.18, 1.18), 0.08).set_trans(Tween.TRANS_SINE)
		t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.08).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(lbl, "modulate", Color(1.0, 0.85, 0.15, 1.0), 0.08)
		t.tween_property(lbl, "modulate", Color(1, 1, 1, 1), 0.08)

	# Hold then float up and fade
	t.tween_interval(hold)
	t.tween_property(lbl, "position", Vector2(px, py - 80.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.55)
	t.tween_callback(lbl.queue_free)

func _show_board_clear_popup() -> void:
	var lbl := Label.new()
	lbl.text = "BOARD CLEAR!"
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(320, 70)
	lbl.position = Vector2(47, 320)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "position", Vector2(47, 240), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate", Color(1, 1, 1, 0), 1.0).set_delay(0.5)
	t.tween_callback(lbl.queue_free)

func _update_combo_label() -> void:
	if combo >= 2:
		combo_label.text = str(combo) + "x COMBO"
		combo_label.scale = Vector2(1.3, 1.3)
		var t := create_tween()
		t.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	else:
		combo_label.text = ""

# ── Helpers ───────────────────────────────────────────────────────────────────
func _game_over() -> void:
	GameState.snapshot(grid.cells, score, pieces, placed,
		sets_given, lines_cleared, theme_idx, combo)
	GameState.record_final_score(score)
	await get_tree().create_timer(0.9).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

func _pop_score(gained: int) -> void:
	score_label.scale = Vector2(1.25, 1.25)
	var t := create_tween()
	t.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	if gained > 20:
		score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
		await get_tree().create_timer(0.4).timeout
		score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))

func _refresh_best() -> void:
	if GameState.best_score > 0:
		best_label.text = "BEST  " + str(GameState.best_score)
