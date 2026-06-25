extends Node

# Dev-only auto-player. Activated by launching the project with
# `-- --autoplay`. Now:
#   - Enumerates every PERMUTATION of the 3 pieces in the current set
#     (6 orderings) and every (col, row) placement for each, picks the
#     sequence with the best heuristic score → meaningful multi-piece
#     lookahead instead of pure greedy-per-piece.
#   - Heuristic rewards row/col clears, then penalises HOLES (empty
#     cells with a filled cell anywhere above in the same column) and
#     BUMPINESS (height difference between adjacent columns), like a
#     classic Tetris evaluator.
#   - Fires a Power ability when stuck (no legal placement found OR
#     the placement leaves the board ≥85% full and the meter has a
#     bomb charge) — Game._fire_power picks the strongest ability the
#     meter can afford. Stops STAX dying with a half-full meter.
#   - Clamps the drop-position so wide / row-7 placements don't get
#     rejected by _drop_targets_board (lifted+DRAG_LIFT was landing
#     exactly on TRAY_Y).
#   - Survives game-overs via the matching block in GameOver.gd which
#     reloads Game.tscn after a short delay — see that script.

var game : Node = null

const COLS := 8
const ROWS := 8
const CELL := 46.0          # GRID_STEP
const ORIGIN_X := 24.0      # GRID_X
const ORIGIN_Y := 175.0     # GRID_Y
const TRAY_TOP := 700.0
const TRAY_Y_CONST := 600.0
const DRAG_LIFT := 80.0     # mirrors Game.gd
const DROP_Y_MAX := 580.0   # TRAY_Y_CONST - 20, so finger stays above the tray

# Heuristic weights. Line clears dominate (multi-line clears compound via the
# in-game streak multiplier, so over-rewarding them is correct). Holes still
# hurt — but less than before, because the previous tuning was so cautious it
# refused good clears that left one small hole. Playability ("can common
# pieces still fit here?") catches "looks fine but kills the next set" boards.
const W_LINE_BASE   :=  1400
const W_LINE_QUAD   :=   600   # extra (lines^2 - 1) per extra line — 2-line = 2x, 3 = 5x, 4 = 10x
const W_HOLE        :=   -32
const W_BUMPY       :=    -6
const W_EMPTY       :=     2
const W_BOARD_END   :=  -150
const W_PLAYABILITY :=    25   # per common shape that still fits after placement

# Reduced probe library — the four "tightest fit" shapes. More probes meant
# better playability evaluation but made planning frame-time spike (8 × ~900
# placement evals = 2M+ cell checks per plan). Four catches the same dead
# boards at ¼ the cost.
const PROBE_SHAPES : Array = [
	[[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],  # 3x3 square
	[[0,0],[1,0],[2,0],[3,0],[4,0]],                          # 5 horizontal
	[[0,0],[0,1],[0,2],[0,3],[0,4]],                          # 5 vertical
	[[0,0],[1,0],[2,0],[0,1]],                                # L 4-cell
]

# Timing — slightly slower than the previous "blink and you'll miss it" pass
# so you can actually watch the placements land.
const STARTUP_WAIT       := 0.40
const DRAG_TWEEN_TIME    := 0.18
const PER_MOVE_PAUSE     := 0.08
const BETWEEN_SETS_PAUSE := 0.10
const POWER_WAIT         := 0.35

# Consecutive failed/skipped moves before we bail to a power-or-give-up path.
# Catches the case where the planner emits a move the live game rejects
# (timing race with a mid-clear board), which used to spin the loop.
const STALL_GIVE_UP := 4

func _ready() -> void:
	game = get_parent()
	await get_tree().create_timer(STARTUP_WAIT).timeout
	_play_loop()

func _play_loop() -> void:
	var stall : int = 0
	while is_instance_valid(game):
		# Wait if the game's between sets / mid-animation
		if game.pieces.size() != 3 or game.placed.size() != 3:
			await get_tree().create_timer(BETWEEN_SETS_PAUSE).timeout
			continue

		var plan : Array = _best_plan()
		if plan.is_empty():
			# No legal placement found. Try the power; if that doesn't help,
			# WAIT and re-plan. The game's own no-moves logic eventually
			# triggers game-over → GameOver auto-restart picks up. Never
			# `return` here — that would leave the AI permanently stopped
			# even though the game might still resolve itself.
			if _try_fire_power():
				stall = 0
				await get_tree().create_timer(POWER_WAIT).timeout
			else:
				await get_tree().create_timer(0.50).timeout
			continue

		# Count actual placements — comparing unplaced-before/after broke
		# because successful 3-piece sets respawn the tray BACK to 3 unplaced,
		# which looked identical to a stuck loop. Track per-step success
		# (slot flipped from false → true) to spot real silent-skip rejections.
		var played : int = 0
		for step in plan:
			if not is_instance_valid(game): return
			var slot : int = int(step["slot"])
			var was_placed : bool = game.placed[slot]
			await _play_move(step)
			if not was_placed and game.placed[slot]:
				played += 1
			await get_tree().create_timer(PER_MOVE_PAUSE).timeout

		# Planner emitted moves but the grid rejected EVERY one → stale
		# snapshot race. Bump stall; after a few, fire the power, then keep
		# looping (NOT return — let the game decide when it's actually over).
		if plan.size() > 0 and played == 0:
			stall += 1
			if stall >= STALL_GIVE_UP:
				_try_fire_power()
				stall = 0
				await get_tree().create_timer(POWER_WAIT).timeout
		else:
			stall = 0

		# Proactive power at 70%+ fill — spends the meter while there's still
		# room for the blast to clear something useful.
		if _board_fill_pct() >= 0.70 and game.meter >= game.METER_BOMB:
			_try_fire_power()
			await get_tree().create_timer(POWER_WAIT).timeout

# ── Planning ─────────────────────────────────────────────────────────────────
# Returns the best plan (Array of {slot,row,col,shape}) for the slots that are
# still UNPLACED in the current set. Permuting over only the unplaced slots
# fixes the stuck-loop bug where the planner kept emitting moves for already-
# placed slots; _play_move silently skipped them, leaving the run hung.
func _best_plan() -> Array:
	var unplaced : Array = []
	for i in 3:
		if not game.placed[i]:
			unplaced.append(i)
	if unplaced.is_empty():
		return []
	var board : Array = _snapshot_cells()
	var best_seq : Array = []
	var best_score : float = -INF
	# Lookahead over every ordering of the remaining unplaced slots (max 6 = 3!).
	for order in _permutations(unplaced):
		var seq : Array = []
		var b : Array = _clone_board(board)
		var ok : bool = true
		var seq_score : float = 0.0
		for slot_idx in order:
			var shape : Array = game.pieces[slot_idx].shape
			var move : Dictionary = _best_placement_on(b, shape, slot_idx)
			if move.is_empty():
				ok = false
				break
			seq.append(move)
			b = _apply_and_clear(b, shape, move["row"], move["col"])
			seq_score += float(move["score"])
		if ok and seq_score > best_score:
			best_score = seq_score
			best_seq = seq
	# Fallback: if no complete sequence is feasible (e.g., two 3x3 squares but
	# only one 3x3 empty patch left), play whatever ONE move scores best so the
	# game keeps moving. Empty plan triggers _try_fire_power.
	if best_seq.is_empty():
		var best_single : Dictionary = {}
		var best_single_s : float = -INF
		for slot_idx in unplaced:
			var shape : Array = game.pieces[slot_idx].shape
			var move : Dictionary = _best_placement_on(board, shape, slot_idx)
			if not move.is_empty() and float(move["score"]) > best_single_s:
				best_single_s = float(move["score"])
				best_single = move
		if not best_single.is_empty():
			best_seq.append(best_single)
	return best_seq

func _permutations(arr: Array) -> Array:
	if arr.size() <= 1:
		return [arr]
	var out : Array = []
	for i in arr.size():
		var head = arr[i]
		var rest : Array = arr.duplicate()
		rest.remove_at(i)
		for sub in _permutations(rest):
			var seq : Array = [head]
			seq.append_array(sub)
			out.append(seq)
	return out

# Best (row, col) for a shape on the given board snapshot
func _best_placement_on(board: Array, shape: Array, slot_idx: int) -> Dictionary:
	var best : Dictionary = {}
	var best_s : float = -INF
	for r in range(ROWS):
		for c in range(COLS):
			if not _shape_fits(board, shape, r, c):
				continue
			var s : float = _score_placement(board, shape, r, c)
			if s > best_s:
				best_s = s
				best = {"slot": slot_idx, "row": r, "col": c, "shape": shape, "score": s}
	return best

# Evaluation ───────────────────────────────────────────────────────────────────
func _score_placement(board: Array, shape: Array, r: int, c: int) -> float:
	var b := _clone_board(board)
	for cell in shape:
		b[r + int(cell[1])][c + int(cell[0])] = true

	# Lines that would clear
	var lines : int = 0
	var row_clear : Array = []
	var col_clear : Array = []
	for rr in ROWS:
		var full := true
		for cc in COLS:
			if not b[rr][cc]:
				full = false; break
		row_clear.append(full)
		if full: lines += 1
	for cc in COLS:
		var full := true
		for rr in ROWS:
			if not b[rr][cc]:
				full = false; break
		col_clear.append(full)
		if full: lines += 1

	# Apply the clears for downstream metrics
	for rr in ROWS:
		for cc in COLS:
			if row_clear[rr] or col_clear[cc]:
				b[rr][cc] = false

	# Holes: empty cells with a filled cell ABOVE in the same column
	var holes : int = 0
	for cc in COLS:
		var seen_top := false
		for rr in ROWS:
			if b[rr][cc]:
				seen_top = true
			elif seen_top:
				holes += 1

	# Bumpiness: sum of |height[c] - height[c+1]|
	var heights : Array = []
	for cc in COLS:
		var h : int = 0
		for rr in ROWS:
			if b[rr][cc]:
				h = ROWS - rr
				break
		heights.append(h)
	var bumpy : int = 0
	for i in range(COLS - 1):
		bumpy += absi(heights[i] - heights[i + 1])

	var empty : int = 0
	for rr in ROWS:
		for cc in COLS:
			if not b[rr][cc]:
				empty += 1

	# Playability — how many probe shapes still fit on the resulting board.
	# A board where even a 3-cell stick can't fit is a death trap; reward
	# placements that keep the board "open" to whatever comes next.
	var playable : int = 0
	for ps in PROBE_SHAPES:
		if _any_fit(b, ps):
			playable += 1

	var fill_pct : float = float(ROWS * COLS - empty) / float(ROWS * COLS)
	var crowded : float = 0.0
	if fill_pct > 0.70:
		crowded = (fill_pct - 0.70) * 3.3   # 0..1 over 0.70..1.00

	# Line reward = base * lines + quadratic bonus for multi-line clears.
	# 1 line: 1400; 2: 4400; 3: 9000; 4: 15200 — incentivises set-up clears.
	var line_reward : float = float(W_LINE_BASE * lines)
	if lines > 1:
		line_reward += float(W_LINE_QUAD * (lines * lines - lines))

	return line_reward \
		+ float(holes * W_HOLE) \
		+ float(bumpy * W_BUMPY) \
		+ float(empty * W_EMPTY) \
		+ float(playable * W_PLAYABILITY) \
		+ crowded * W_BOARD_END

# Does shape `ps` fit ANYWHERE on board `b`? Used by the playability metric.
func _any_fit(b: Array, ps: Array) -> bool:
	for r in ROWS:
		for c in COLS:
			if _shape_fits(b, ps, r, c):
				return true
	return false

# ── Board snapshot / clone / apply ───────────────────────────────────────────
func _snapshot_cells() -> Array:
	var out : Array = []
	for r in ROWS:
		var row_arr : Array = []
		for c in COLS:
			row_arr.append(game.grid.cells[r][c] != null)
		out.append(row_arr)
	return out

func _clone_board(b: Array) -> Array:
	var out : Array = []
	for row in b:
		out.append((row as Array).duplicate())
	return out

func _apply_and_clear(b: Array, shape: Array, r: int, c: int) -> Array:
	var n := _clone_board(b)
	for cell in shape:
		n[r + int(cell[1])][c + int(cell[0])] = true
	# Clear full rows/cols
	var rc : Array = []
	var cc_ : Array = []
	for rr in ROWS:
		var full := true
		for cc in COLS:
			if not n[rr][cc]:
				full = false; break
		rc.append(full)
	for cc in COLS:
		var full := true
		for rr in ROWS:
			if not n[rr][cc]:
				full = false; break
		cc_.append(full)
	for rr in ROWS:
		for cc in COLS:
			if rc[rr] or cc_[cc]:
				n[rr][cc] = false
	return n

func _shape_fits(b: Array, shape: Array, r: int, c: int) -> bool:
	for cell in shape:
		var rr : int = r + int(cell[1])
		var cc : int = c + int(cell[0])
		if rr < 0 or rr >= ROWS or cc < 0 or cc >= COLS:
			return false
		if b[rr][cc]:
			return false
	return true

func _board_fill_pct() -> float:
	var n : int = 0
	for r in ROWS:
		for c in COLS:
			if game.grid.cells[r][c] != null:
				n += 1
	return float(n) / float(ROWS * COLS)

# ── Power abilities ───────────────────────────────────────────────────────────
func _try_fire_power() -> bool:
	if game.power_busy or game.dragging_slot >= 0:
		return false
	if game.meter < game.METER_BOMB:
		return false
	game._fire_power()
	return true

# ── Drag / drop ───────────────────────────────────────────────────────────────
func _play_move(move: Dictionary) -> void:
	var slot : int = move["slot"]
	var r : int = move["row"]
	var c : int = move["col"]
	var shape : Array = move["shape"]

	# Sanity: skip if game state changed mid-plan (e.g., the game cleared lines
	# and respawned during a tween).
	if game.placed[slot] or not game.grid.can_place(shape, r, c):
		return

	var slot_w : float = 414.0 / 3.0
	var slot_x : float = slot * slot_w + slot_w * 0.5
	var pickup := Vector2(slot_x, TRAY_TOP)
	game._start_drag(pickup)

	# Compute lifted snap centre then convert to finger position
	var min_c : int = 99; var min_r : int = 99
	var max_c : int = 0; var max_r : int = 0
	for cell in shape:
		var cx : int = int(cell[0]); var cy : int = int(cell[1])
		if cx < min_c: min_c = cx
		if cx > max_c: max_c = cx
		if cy < min_r: min_r = cy
		if cy > max_r: max_r = cy
	var bw : float = float(max_c - min_c) + 1.0
	var bh : float = float(max_r - min_r) + 1.0
	var lifted_x : float = ORIGIN_X + (float(c) + bw * 0.5) * CELL
	var lifted_y : float = ORIGIN_Y + (float(r) + bh * 0.5) * CELL
	# Finger position = lifted + DRAG_LIFT, but cap so it never lands on the
	# tray-Y boundary (which _drop_targets_board treats as a rejection).
	var drop_y : float = min(lifted_y + DRAG_LIFT, DROP_Y_MAX)
	var drop_pos := Vector2(lifted_x, drop_y)

	var t := game.create_tween()
	t.tween_method(func(p: float):
		if not is_instance_valid(game): return
		game.drag_pos = pickup.lerp(drop_pos, p)
		game._update_ghost()
		game.queue_redraw(),
		0.0, 1.0, DRAG_TWEEN_TIME).set_trans(Tween.TRANS_QUAD)
	await t.finished
	if not is_instance_valid(game): return
	game._end_drag(drop_pos)
