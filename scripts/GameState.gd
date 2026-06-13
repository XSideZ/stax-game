extends Node

var last_score : int   = 0
var best_score : int   = 0
var scores     : Array = []   # top MAX_SCORES, sorted descending

# Settings
var sound_on   : bool = true
var music_on   : bool = true
var haptics_on : bool = true

# One ad-revive per run
var revive_used : bool = false

# Dev skin changer (main-menu picker, session-only): -1 = follow the theme
var dev_skin_override : int = -1

# AUTO-mode skin cycling uses a shuffle bag: every unlocked skin appears once
# before any repeats. Persisted so the cycle carries across runs.
var theme_bag : Array = []

# ── Secret cat skin (easter egg: tap S-T-A-X on the title in order) ───────────
# CAT is the last THEMES entry; the random theme rotation only uses 0..CAT_SKIN-1
# so it never appears by chance. cat_mode forces it on everywhere, and persists.
const CAT_SKIN := 25
var cat_mode : bool = false

# Effective skin index, honoured by Game/MainMenu/GameOver
func active_skin(theme_i: int) -> int:
	if cat_mode:
		return CAT_SKIN
	if dev_skin_override >= 0:
		return dev_skin_override
	return theme_i % THEMES.size()

func set_cat_mode(on: bool) -> void:
	cat_mode = on
	_save()

# Skins available for AUTO rotation. TODO: filter to the player's unlocked set
# once level/achievement gating exists; for now every non-cat skin is available.
func unlocked_skins() -> Array:
	var pool : Array = []
	for i in CAT_SKIN:   # 0 .. CAT_SKIN-1, never the secret cat
		pool.append(i)
	return pool

# Next AUTO skin via a shuffle bag: returns each unlocked skin once before any
# repeat. Refills + reshuffles when empty, avoiding an immediate repeat.
func next_auto_theme(current: int) -> int:
	if theme_bag.is_empty():
		theme_bag = unlocked_skins()
		theme_bag.shuffle()
		if theme_bag.size() > 1 and int(theme_bag[0]) == current:
			theme_bag.push_back(theme_bag.pop_front())
	var nxt : int = int(theme_bag.pop_front())
	_save()
	return nxt

# ── Player profile / XP ───────────────────────────────────────────────────────
# Level curve: cost(level→level+1) = 20 + 0.28·level². Total to hit MAX_LEVEL
# is ~92k XP; an average run (≈40 moves, ≈800 pts) pays ~80 XP, so level 100
# lands around 100 hours of normal play.
const MAX_LEVEL := 100
var player_name  : String = ""
var player_xp    : int = 0
var games_played : int = 0
var unlocked     : Dictionary = {}   # achievement id -> true
var pending_toasts : Array = []      # achievements unlocked at game over (shown on GameOver)
var last_xp_gain   : int = 0
var last_xp_before : int = 0         # XP before the run's payout — drives the bar animation

# Lifetime stats (profile card → stats panel, achievement quest values)
var total_score       : int = 0     # every run's final score summed
var stat_blocks       : int = 0     # total pieces placed
var stat_best_streak  : int = 0     # longest clear streak ever
var stat_run_lines    : int = 0     # most lines cleared in a single run
var stat_board_clears : int = 0     # lifetime full-board clears
var stat_best_multi   : int = 0     # most lines cleared in ONE move
var stat_revives      : int = 0     # lifetime ad-revives used

func add_revive() -> void:
	stat_revives += 1
	_save()

# ── Achievements (tiered, Clash-style) ────────────────────────────────────────
# Each group is ONE quest with escalating tiers [target, xp]. The menu shows
# only the current tier; tapping a card expands the full ladder. Unlock keys
# are "<group>_<tier_index>".
const ACH_GROUPS : Array = [
	{"id": "games",  "name": "Dedicated",      "desc": "Play %s games",                  "tiers": [[1, 50], [5, 100], [10, 200]]},
	{"id": "score",  "name": "High Scorer",    "desc": "Score %s in one run",            "tiers": [[100, 50], [1000, 150], [10000, 400]]},
	{"id": "lines",  "name": "Line Clearer",   "desc": "Clear %s lines in total",        "tiers": [[50, 50], [500, 150], [2500, 350]]},
	{"id": "streak", "name": "On Fire",        "desc": "Reach a streak of %s clears",    "tiers": [[3, 50], [6, 150], [10, 300]]},
	{"id": "multi",  "name": "Combo King",     "desc": "Clear %s lines in one move",     "tiers": [[2, 50], [3, 150], [4, 400]]},
	{"id": "blocks", "name": "Master Builder", "desc": "Place %s blocks in total",       "tiers": [[100, 50], [1000, 150], [5000, 300]]},
	{"id": "boards", "name": "Clean Sweep",    "desc": "Empty the whole board %s times", "tiers": [[1, 75], [5, 200], [25, 500]]},
	{"id": "level",  "name": "Climber",        "desc": "Reach level %s",                 "tiers": [[5, 100], [15, 250], [30, 600]]},
	{"id": "revive", "name": "Second Wind",    "desc": "Continue a run with a revive",   "tiers": [[1, 100]]},
]
const TIER_NUMERALS : Array = ["I", "II", "III"]

static func fmt(n: int) -> String:
	if n < 1000:
		return str(n)
	return str(n / 1000) + "," + str(n % 1000).pad_zeros(3)

# Live value backing each quest group
func ach_value(group_id: String) -> int:
	match group_id:
		"games":  return games_played
		"score":  return best_score
		"lines":  return total_lines
		"streak": return stat_best_streak
		"multi":  return stat_best_multi
		"blocks": return stat_blocks
		"boards": return stat_board_clears
		"level":  return get_level()
		"revive": return stat_revives
	return 0

static func ach_group(group_id: String) -> Dictionary:
	for g in ACH_GROUPS:
		if g["id"] == group_id:
			return g
	return {}

# Display info for an unlock key like "score_1"
func ach_info(key: String) -> Dictionary:
	var sep := key.rfind("_")
	var g := ach_group(key.substr(0, sep))
	if g.is_empty():
		return {}
	var ti := int(key.substr(sep + 1))
	var tier : Array = g["tiers"][ti]
	var nm : String = g["name"]
	if g["tiers"].size() > 1:
		nm += " " + TIER_NUMERALS[ti]
	var d : String = g["desc"]
	if d.contains("%s"):
		d = d % fmt(tier[0])
	return {"name": nm, "desc": d, "xp": tier[1]}

# Walk every tier of every group, unlock anything earned, grant the XP.
# Returns the freshly unlocked keys (for toasts).
func check_unlocks() -> Array:
	var fresh : Array = []
	for g in ACH_GROUPS:
		var v := ach_value(g["id"])
		for ti in g["tiers"].size():
			var key := "%s_%d" % [g["id"], ti]
			if unlocked.get(key, false):
				continue
			if v >= g["tiers"][ti][0]:
				unlocked[key] = true
				player_xp += g["tiers"][ti][1]
				fresh.append(key)
	if not fresh.is_empty():
		_save()
	return fresh

static func xp_cost(level: int) -> int:
	return 20 + int(0.28 * float(level * level))

static func level_for_xp(xp: int) -> int:
	var lvl := 1
	var rem := xp
	while lvl < MAX_LEVEL and rem >= xp_cost(lvl):
		rem -= xp_cost(lvl)
		lvl += 1
	return lvl

# [xp into current level, xp needed for next level] — [0, 0] at max level
static func progress_for_xp(xp: int) -> Array:
	var lvl := 1
	var rem := xp
	while lvl < MAX_LEVEL and rem >= xp_cost(lvl):
		rem -= xp_cost(lvl)
		lvl += 1
	if lvl >= MAX_LEVEL:
		return [0, 0]
	return [rem, xp_cost(lvl)]

func get_level() -> int:
	return level_for_xp(player_xp)

func xp_progress() -> Array:
	return progress_for_xp(player_xp)

func set_player_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 12)
	_save()

# Called once per game over: grants run XP, rolls lifetime stats and checks
# games-played milestones
func finish_run(moves: int, final_score: int, run_lines: int = 0,
		run_streak: int = 0, run_boards: int = 0) -> void:
	games_played += 1
	total_score       += final_score
	stat_blocks       += moves
	stat_board_clears += run_boards
	stat_best_streak   = maxi(stat_best_streak, run_streak)
	stat_run_lines     = maxi(stat_run_lines, run_lines)
	last_xp_before = player_xp
	last_xp_gain = moves + final_score / 20
	player_xp += last_xp_gain
	pending_toasts = check_unlocks()
	_save()

# Theme progression persists across runs — backgrounds keep rotating
# no matter how short each game is
var theme_idx   : int = 0
var total_lines : int = 0

# In-memory continuation snapshot (ad-continue and run-resume both use it)
# continue_mode: "ad" = gift 2 cleared rows on restore, "resume" = exact restore
var has_save           : bool   = false
var continue_mode      : String = "resume"
var save_cells         : Array  = []
var save_score         : int    = 0
var save_pieces        : Array  = []
var save_placed        : Array  = []
var save_sets_given    : int    = 0
var save_lines_cleared : int    = 0
var save_theme_idx     : int    = 0
var save_combo         : int    = 0
var save_placements    : int    = 0
var save_max_combo     : int    = 0
var save_board_clears  : int    = 0
var save_seeds         : Array  = []   # per-cell skin pattern seeds
var save_meter         : float  = 0.0  # power-meter charge (0..1)

const SAVE_PATH  := "user://stax_save.dat"
const RUN_PATH   := "user://stax_run.dat"
const MAX_SCORES := 10

# ── Themes ────────────────────────────────────────────────────────────────────
# Lives here (autoload) so Game AND the menus can read it — menu backgrounds
# follow the selected skin. Index = skin index. Brightened across the board;
# only VOLCANO and GALAXY stay dark by design.
# "accent" tints in-game text (clear popups, streak label, theme popup) so
# each theme's typography matches its world
const THEMES: Array = [
	{"bg": Color(0.45, 0.66, 0.86), "orb": Color(1.00, 1.00, 1.00, 0.08), "accent": Color(1.00, 1.00, 1.00), "name": "PASTEL SKY"},
	{"bg": Color(0.12, 0.27, 0.16), "orb": Color(0.20, 1.00, 0.45, 0.08), "accent": Color(0.40, 1.00, 0.60), "name": "NEON JUNGLE"},
	{"bg": Color(0.09, 0.23, 0.20), "orb": Color(0.20, 0.95, 0.65, 0.08), "accent": Color(0.35, 1.00, 0.80), "name": "CIRCUIT CITY"},
	{"bg": Color(0.29, 0.14, 0.11), "orb": Color(0.95, 0.45, 0.25, 0.08), "accent": Color(1.00, 0.65, 0.45), "name": "BRICKYARD"},
	{"bg": Color(0.15, 0.21, 0.37), "orb": Color(0.40, 0.65, 1.00, 0.08), "accent": Color(0.60, 0.80, 1.00), "name": "CRYSTAL CAVE"},
	{"bg": Color(0.37, 0.16, 0.27), "orb": Color(1.00, 0.45, 0.70, 0.08), "accent": Color(1.00, 0.60, 0.82), "name": "CANDY LAND"},
	{"bg": Color(0.15, 0.26, 0.36), "orb": Color(0.80, 0.95, 1.00, 0.08), "accent": Color(0.80, 0.95, 1.00), "name": "FROZEN PEAK"},
	{"bg": Color(0.13, 0.28, 0.15), "orb": Color(0.45, 0.95, 0.35, 0.08), "accent": Color(0.65, 1.00, 0.50), "name": "MEADOW"},
	{"bg": Color(0.10, 0.21, 0.38), "orb": Color(0.25, 0.65, 1.00, 0.08), "accent": Color(0.50, 0.82, 1.00), "name": "OCEAN"},
	{"bg": Color(0.11, 0.03, 0.02), "orb": Color(1.00, 0.35, 0.05, 0.08), "accent": Color(1.00, 0.58, 0.25), "name": "VOLCANO"},
	{"bg": Color(0.27, 0.19, 0.10), "orb": Color(0.85, 0.60, 0.25, 0.07), "accent": Color(0.98, 0.80, 0.50), "name": "TIMBER"},
	{"bg": Color(0.05, 0.02, 0.10), "orb": Color(0.75, 0.35, 1.00, 0.07), "accent": Color(0.85, 0.55, 1.00), "name": "GALAXY"},
	{"bg": Color(0.25, 0.17, 0.05), "orb": Color(1.00, 0.75, 0.20, 0.08), "accent": Color(1.00, 0.82, 0.35), "name": "THE HIVE"},
	{"bg": Color(0.07, 0.06, 0.13), "orb": Color(0.40, 1.00, 0.90, 0.08), "accent": Color(0.45, 1.00, 0.85), "name": "ARCADE"},
	{"bg": Color(0.20, 0.30, 0.42), "orb": Color(1.00, 1.00, 1.00, 0.09), "accent": Color(0.85, 0.95, 1.00), "name": "BUBBLE BATH"},
	{"bg": Color(0.13, 0.15, 0.23), "orb": Color(0.60, 0.70, 0.90, 0.08), "accent": Color(0.75, 0.85, 1.00), "name": "THUNDERSTORM"},
	{"bg": Color(0.33, 0.18, 0.24), "orb": Color(1.00, 0.70, 0.80, 0.08), "accent": Color(1.00, 0.75, 0.85), "name": "BLOSSOM"},
	{"bg": Color(0.19, 0.14, 0.06), "orb": Color(1.00, 0.85, 0.40, 0.07), "accent": Color(1.00, 0.85, 0.45), "name": "THE VAULT"},
	{"bg": Color(0.10, 0.18, 0.08), "orb": Color(0.50, 0.90, 0.30, 0.08), "accent": Color(0.62, 1.00, 0.42), "name": "SWAMP"},
	{"bg": Color(0.11, 0.05, 0.15), "orb": Color(0.90, 0.40, 1.00, 0.08), "accent": Color(1.00, 0.50, 0.90), "name": "DANCE FLOOR"},
	{"bg": Color(0.04, 0.07, 0.16), "orb": Color(0.30, 1.00, 0.70, 0.07), "accent": Color(0.50, 1.00, 0.85), "name": "AURORA SKY"},
	{"bg": Color(0.08, 0.04, 0.16), "orb": Color(0.70, 0.40, 1.00, 0.08), "accent": Color(0.85, 0.60, 1.00), "name": "PLASMA FIELD"},
	{"bg": Color(0.26, 0.24, 0.30), "orb": Color(1.00, 1.00, 1.00, 0.06), "accent": Color(0.92, 0.90, 0.96), "name": "MARBLE HALL"},
	{"bg": Color(0.02, 0.08, 0.04), "orb": Color(0.20, 1.00, 0.40, 0.07), "accent": Color(0.40, 1.00, 0.50), "name": "DATA STREAM"},
	{"bg": Color(0.06, 0.07, 0.14), "orb": Color(0.40, 0.90, 1.00, 0.08), "accent": Color(0.60, 0.90, 1.00), "name": "HOLO DECK"},
	# index 25 = secret CAT skin (never in random rotation; easter-egg only)
	{"bg": Color(0.20, 0.14, 0.24), "orb": Color(1.00, 0.80, 0.90, 0.09), "accent": Color(1.00, 0.78, 0.88), "name": "MEOW TOWN"},
]

func _ready() -> void:
	_load()
	check_unlocks()   # silent retroactive reconcile at boot

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

func set_sound(on: bool) -> void:
	sound_on = on
	_save()

func set_music(on: bool) -> void:
	music_on = on
	_save()

func set_haptics(on: bool) -> void:
	haptics_on = on
	_save()

func add_lines(n: int) -> void:
	total_lines += n
	_save()

func set_theme(i: int) -> void:
	theme_idx = i
	_save()

func snapshot(cells: Array, sc: int, pcs: Array, pl: Array,
			  sg: int, lc: int, ti: int, cb: int, pm: int = 0,
			  mc: int = 0, bc: int = 0, sd: Array = [], mt: float = 0.0) -> void:
	has_save           = true
	save_cells         = cells.duplicate(true)
	save_score         = sc
	save_pieces        = pcs.duplicate(true)
	save_placed        = pl.duplicate()
	save_sets_given    = sg
	save_lines_cleared = lc
	save_theme_idx     = ti
	save_combo         = cb
	save_placements    = pm
	save_max_combo     = mc
	save_board_clears  = bc
	save_seeds         = sd.duplicate(true)
	save_meter         = mt

# ── Run persistence (auto-save until the player loses) ───────────────────────
func save_run_to_disk() -> void:
	var f := FileAccess.open(RUN_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(save_cells)
	f.store_var(save_score)
	f.store_var(save_pieces)
	f.store_var(save_placed)
	f.store_var(save_sets_given)
	f.store_var(save_lines_cleared)
	f.store_var(save_combo)
	f.store_var(save_placements)
	f.store_var(save_max_combo)
	f.store_var(save_board_clears)
	f.store_var(revive_used)
	f.store_var(save_seeds)
	f.store_var(save_meter)
	f.close()

func has_run_save() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func load_run_from_disk() -> bool:
	if not FileAccess.file_exists(RUN_PATH):
		return false
	var f := FileAccess.open(RUN_PATH, FileAccess.READ)
	if f == null:
		return false
	save_cells         = f.get_var()
	save_score         = f.get_var()
	save_pieces        = f.get_var()
	save_placed        = f.get_var()
	save_sets_given    = f.get_var()
	save_lines_cleared = f.get_var()
	save_combo         = f.get_var()
	save_placements    = f.get_var()
	# Stats + revive flag + seeds added later — older run files end early
	save_max_combo    = f.get_var() if f.get_position() < f.get_length() else 0
	save_board_clears = f.get_var() if f.get_position() < f.get_length() else 0
	revive_used       = f.get_var() if f.get_position() < f.get_length() else false
	save_seeds        = f.get_var() if f.get_position() < f.get_length() else []
	save_meter        = f.get_var() if f.get_position() < f.get_length() else 0.0
	f.close()
	save_theme_idx = theme_idx
	has_save       = true
	continue_mode  = "resume"
	return true

func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("stax_run.dat")

# ── Settings / meta persistence ───────────────────────────────────────────────
func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_var(best_score)
	f.store_var(scores)
	f.store_var(sound_on)
	f.store_var(music_on)
	f.store_var(theme_idx)
	f.store_var(total_lines)
	f.store_var(haptics_on)
	f.store_var(player_name)
	f.store_var(player_xp)
	f.store_var(games_played)
	f.store_var(unlocked)
	f.store_var(total_score)
	f.store_var(stat_blocks)
	f.store_var(stat_best_streak)
	f.store_var(stat_run_lines)
	f.store_var(stat_board_clears)
	f.store_var(stat_best_multi)
	f.store_var(stat_revives)
	f.store_var(cat_mode)
	f.store_var(theme_bag)
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	best_score = f.get_var()
	scores     = f.get_var()
	# Fields below were added over time — older save files end early
	if f.get_position() < f.get_length():
		sound_on = f.get_var()
	if f.get_position() < f.get_length():
		music_on = f.get_var()
	if f.get_position() < f.get_length():
		theme_idx = f.get_var()
	if f.get_position() < f.get_length():
		total_lines = f.get_var()
	if f.get_position() < f.get_length():
		haptics_on = f.get_var()
	if f.get_position() < f.get_length():
		player_name = f.get_var()
	if f.get_position() < f.get_length():
		player_xp = f.get_var()
	if f.get_position() < f.get_length():
		games_played = f.get_var()
	if f.get_position() < f.get_length():
		unlocked = f.get_var()
	if f.get_position() < f.get_length():
		total_score = f.get_var()
	if f.get_position() < f.get_length():
		stat_blocks = f.get_var()
	if f.get_position() < f.get_length():
		stat_best_streak = f.get_var()
	if f.get_position() < f.get_length():
		stat_run_lines = f.get_var()
	if f.get_position() < f.get_length():
		stat_board_clears = f.get_var()
	if f.get_position() < f.get_length():
		stat_best_multi = f.get_var()
	if f.get_position() < f.get_length():
		stat_revives = f.get_var()
	if f.get_position() < f.get_length():
		cat_mode = f.get_var()
	if f.get_position() < f.get_length():
		theme_bag = f.get_var()
	f.close()
