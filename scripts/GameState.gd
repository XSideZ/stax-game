extends Node

var last_score : int   = 0
var best_score : int   = 0
var scores     : Array = []   # top MAX_SCORES, sorted descending

# Watch-ad continuation snapshot
var has_save          : bool  = false
var save_cells        : Array = []
var save_score        : int   = 0
var save_pieces       : Array = []
var save_placed       : Array = []
var save_sets_given   : int   = 0
var save_lines_cleared: int   = 0
var save_theme_idx    : int   = 0
var save_combo        : int   = 0

const SAVE_PATH  := "user://stax_save.dat"
const MAX_SCORES := 10

func _ready() -> void:
	_load()

func submit_score(s: int) -> void:
	last_score = s
	if s > best_score:
		best_score = s

func record_final_score(s: int) -> void:
	submit_score(s)
	if s > 0:
		scores.append(s)
		scores.sort()
		scores.reverse()
		if scores.size() > MAX_SCORES:
			scores.resize(MAX_SCORES)
	_save()

func snapshot(cells: Array, sc: int, pcs: Array, pl: Array,
			  sg: int, lc: int, ti: int, cb: int) -> void:
	has_save           = true
	save_cells         = cells.duplicate(true)
	save_score         = sc
	save_pieces        = pcs.duplicate(true)
	save_placed        = pl.duplicate()
	save_sets_given    = sg
	save_lines_cleared = lc
	save_theme_idx     = ti
	save_combo         = cb

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(best_score)
	f.store_var(scores)
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	best_score = f.get_var()
	scores     = f.get_var()
	f.close()
