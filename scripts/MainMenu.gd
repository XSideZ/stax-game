extends Node2D

# Intro screen: floating orbs + falling cartoon blocks behind an animated
# bouncing STAX logo, chunky PLAY / SETTINGS buttons, inline settings panel.

const COLORS: Array = [
	Color(0.32, 0.80, 0.97),
	Color(1.00, 0.63, 0.28),
	Color(0.95, 0.36, 0.68),
	Color(0.33, 0.90, 0.55),
	Color(0.73, 0.43, 0.97),
	Color(0.97, 0.88, 0.32),
]

const ORB_COUNT := 10
const FALL_COUNT := 12

# ── Dev skin changer — set to false before publishing to hide it ─────────────
const SHOW_SKIN_PICKER := true
const SKIN_NAMES : Array = ["PASTEL", "NEON", "CIRCUIT", "BRICK", "CRYSTAL",
	"CANDY", "FROST", "GRASS", "WATER", "LAVA", "WOOD", "GALAXY",
	"HONEY", "RETRO", "BUBBLE", "STORM", "SAKURA", "METALS", "SLIME", "DISCO",
	"AURORA", "PLASMA", "MARBLE", "MATRIX", "HOLOGRAM",
	"PRISM", "STAINED", "SYNTHWAVE", "AUTUMN", "WARP"]

var orbs    : Array = []
var fallers : Array = []
var time_t  : float = 0.0

var letters      : Array = []   # {lbl, base_pos, phase}
var bobbing      : bool  = false
var cat_progress : int   = 0    # secret: tap S-T-A-X in order to toggle cat mode
var settings_box : PanelContainer
var play_pulse   : Tween
var faller_layer : Node2D

@onready var ui : CanvasLayer = $UI

func _ready() -> void:
	for _i in ORB_COUNT:
		orbs.append({
			"pos":    Vector2(randf() * 414.0, randf() * 896.0),
			"vel":    Vector2((randf() - 0.5) * 18.0, (randf() - 0.5) * 18.0),
			"radius": randf_range(60.0, 140.0),
			"color":  Color(0.55, 0.55, 1.0, randf_range(0.04, 0.09)),
		})
	for _i in FALL_COUNT:
		fallers.append(_make_faller(true))

	# Fallers paint on their own translucent layer so full skin detail
	# can render without overpowering the menu
	faller_layer = Node2D.new()
	faller_layer.modulate = Color(1, 1, 1, 0.55)
	add_child(faller_layer)
	faller_layer.draw.connect(_draw_fallers)

	# First open: only the animated background + name prompt. The menu builds
	# (and the logo intro plays) after the name is confirmed.
	if GameState.player_name.is_empty():
		_build_name_prompt()
	else:
		_build_menu()
	Sfx.update_music()

func _build_menu() -> void:
	_build_logo()
	_build_profile()
	_build_buttons()
	_build_settings_panel()
	_build_achievements_panel()
	_build_stats_panel()
	if SHOW_SKIN_PICKER:
		_build_skin_picker()

func _make_faller(anywhere: bool) -> Dictionary:
	return {
		"pos":   Vector2(randf() * 414.0, (randf() * 896.0) if anywhere else -80.0),
		"spd":   randf_range(22.0, 55.0),
		"rot":   randf() * TAU,
		"rspd":  randf_range(-0.8, 0.8),
		"cs":    randf_range(11.0, 17.0),   # cell size of the mini piece
		"shape": BlockSkins.DEMO_SHAPES[randi() % BlockSkins.DEMO_SHAPES.size()],
		"seed":  randi() % 97,
		"color": COLORS[randi() % COLORS.size()],
	}

# Current skin for menu decoration: dev override wins, else the theme's skin
func _menu_skin() -> int:
	if GameState.cat_mode:
		return GameState.CAT_SKIN
	if GameState.dev_skin_override >= 0:
		return GameState.dev_skin_override
	return GameState.theme_idx % GameState.THEMES.size()

func _draw_fallers() -> void:
	var style := _menu_skin()
	for f in fallers:
		faller_layer.draw_set_transform(f["pos"], f["rot"])
		var cs : float = f["cs"]
		for cell in f["shape"]:
			BlockSkins.paint(faller_layer, style,
				Rect2(cell[0] * cs, cell[1] * cs, cs - 1.0, cs - 1.0),
				f["color"], f["seed"] + cell[0] * 7 + cell[1] * 13)
	faller_layer.draw_set_transform(Vector2.ZERO)

func _process(delta: float) -> void:
	time_t += delta
	for orb in orbs:
		orb["pos"] += orb["vel"] * delta
		if orb["pos"].x < -140.0 or orb["pos"].x > 554.0: orb["vel"].x = -orb["vel"].x
		if orb["pos"].y < -140.0 or orb["pos"].y > 1036.0: orb["vel"].y = -orb["vel"].y
	for i in fallers.size():
		var f : Dictionary = fallers[i]
		f["pos"].y += f["spd"] * delta
		f["rot"]   += f["rspd"] * delta
		if f["pos"].y > 950.0:
			fallers[i] = _make_faller(false)

	if bobbing:
		for i in letters.size():
			var entry : Dictionary = letters[i]
			var lbl   : Label      = entry["lbl"]
			lbl.position.y = entry["base_pos"].y + sin(time_t * 2.2 + entry["phase"]) * 7.0
			lbl.rotation_degrees = sin(time_t * 1.6 + entry["phase"]) * 3.0

	queue_redraw()
	faller_layer.queue_redraw()

# ── Background drawing — follows the selected skin's theme live ─────────────
func _draw() -> void:
	var theme_data : Dictionary = GameState.THEMES[_menu_skin() % GameState.THEMES.size()]
	draw_rect(Rect2(Vector2.ZERO, Vector2(414, 896)), theme_data["bg"], true)
	var oc : Color = theme_data["orb"]
	for orb in orbs:
		draw_circle(orb["pos"], orb["radius"],
			Color(oc.r, oc.g, oc.b, orb["color"].a))
	# Cat mode: paw prints drifting up the menu
	if GameState.cat_mode:
		var paw := Color(1.0, 0.80, 0.88, 0.08)
		for i in 8:
			var pxp : float = fmod(float(i * 131 + 37) * 29.7, 414.0)
			var pyp : float = fmod(float(i * 89 + 17) * 47.3 - time_t * (8.0 + float(i % 3) * 4.0), 940.0) - 22.0
			if pyp < -22.0: pyp += 940.0
			draw_circle(Vector2(pxp, pyp), 8.0, paw)
			for j in 4:
				var a := -PI * 0.5 + (float(j) - 1.5) * 0.5
				draw_circle(Vector2(pxp, pyp) + Vector2(cos(a), sin(a)) * 12.0, 3.5, paw)

# ── Logo ──────────────────────────────────────────────────────────────────────
func _build_logo() -> void:
	var text    := "STAX"
	var lw      := 78.0
	var start_x := (414.0 - lw * text.length()) * 0.5
	for i in text.length():
		var lbl := Label.new()
		lbl.text = text[i]
		lbl.add_theme_font_size_override("font_size", 96)
		lbl.add_theme_color_override("font_color", COLORS[i % COLORS.size()])
		lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09))
		lbl.add_theme_constant_override("outline_size", 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(lw, 120)
		lbl.pivot_offset = Vector2(lw * 0.5, 60)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP   # secret: each letter is tappable
		var base := Vector2(start_x + i * lw, 130.0)
		lbl.position = base - Vector2(0, 320)   # start off-screen above
		ui.add_child(lbl)
		letters.append({"lbl": lbl, "base_pos": base, "phase": float(i) * 0.8})
		var li := i
		lbl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_letter_tapped(li))

		# Drop in with overshoot, staggered
		var t := create_tween()
		t.tween_interval(0.15 + float(i) * 0.12)
		t.tween_property(lbl, "position", base, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i == letters.size() - 1 and text.length() - 1 == i:
			t.tween_callback(func(): bobbing = true)

	# Best score lives in the profile card now (folded out of the waterfall)

# ── Secret cat easter egg: tap the letters S-T-A-X in order ──────────────────
func _on_letter_tapped(idx: int) -> void:
	# Tapped letter does a happy hop
	var lbl : Label = letters[idx]["lbl"]
	var hop := create_tween()
	hop.tween_property(lbl, "scale", Vector2(1.3, 1.3), 0.10).set_trans(Tween.TRANS_BACK)
	hop.tween_property(lbl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	if GameState.haptics_on:
		Input.vibrate_handheld(15)
	if idx == cat_progress:
		cat_progress += 1
		Sfx.play_tick()
		if cat_progress >= letters.size():
			cat_progress = 0
			_toggle_cat_mode()
	else:
		# Wrong order — start over (but a first-letter tap still counts)
		cat_progress = 1 if idx == 0 else 0

func _toggle_cat_mode() -> void:
	# The bg, orbs and falling pieces all read the skin live each frame, so the
	# whole menu recolours to (or from) the cat theme instantly — no rebuild.
	GameState.set_cat_mode(not GameState.cat_mode)
	Sfx.play_meow()
	_show_meow_popup()
	# Letters do a happy scale-pop to celebrate (rotation is owned by the bob)
	for i in letters.size():
		var l : Label = letters[i]["lbl"]
		var t := create_tween()
		t.tween_interval(float(i) * 0.06)
		t.tween_property(l, "scale", Vector2(1.4, 1.4), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)

func _show_meow_popup() -> void:
	var lbl := Label.new()
	lbl.text = "MEOW!" if GameState.cat_mode else "BYE KITTY"
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.88))
	lbl.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.18))
	lbl.add_theme_constant_override("outline_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(414, 90)
	lbl.position = Vector2(0, 400)
	lbl.pivot_offset = Vector2(207, 45)
	lbl.scale = Vector2(0.2, 0.2)
	ui.add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.12)
	t.tween_interval(0.7)
	t.tween_property(lbl, "modulate:a", 0.0, 0.4)
	t.tween_callback(lbl.queue_free)

# ── Player profile card: name + level chip + XP bar + best, tap for stats ───
var profile_name : Label
var profile_chip : Label
var profile_best : Label
var xp_fill      : Panel
var xp_text      : Label

const XP_BAR_W := 268.0

func _build_profile() -> void:
	var card := Button.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.set_corner_radius_all(18)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0, 0, 0, 0.38)
	var sb_press := sb.duplicate()
	sb_press.bg_color = Color(0, 0, 0, 0.45)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", sb_hover)
	card.add_theme_stylebox_override("pressed", sb_press)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.size = Vector2(300, 96)
	card.position = Vector2(57, 300)
	ui.add_child(card)
	card.pressed.connect(func():
		Sfx.play_click()
		_open_stats())
	_add_press_effect(card)

	profile_name = Label.new()
	profile_name.add_theme_font_size_override("font_size", 20)
	profile_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	profile_name.position = Vector2(16, 6)
	profile_name.size = Vector2(190, 28)
	card.add_child(profile_name)

	profile_chip = Label.new()
	profile_chip.add_theme_font_size_override("font_size", 14)
	profile_chip.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05))
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.95, 0.78, 0.20)
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 10; csb.content_margin_right = 10
	csb.content_margin_top = 3;   csb.content_margin_bottom = 3
	profile_chip.add_theme_stylebox_override("normal", csb)
	profile_chip.position = Vector2(222, 9)
	card.add_child(profile_chip)

	var track := Panel.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0.40)
	tsb.set_corner_radius_all(6)
	track.add_theme_stylebox_override("panel", tsb)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = Vector2(16, 42)
	track.size = Vector2(XP_BAR_W, 12)
	card.add_child(track)

	xp_fill = Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.95, 0.78, 0.20)
	fsb.set_corner_radius_all(6)
	xp_fill.add_theme_stylebox_override("panel", fsb)
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_fill.position = Vector2(16, 42)
	card.add_child(xp_fill)

	profile_best = Label.new()
	profile_best.add_theme_font_size_override("font_size", 13)
	profile_best.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 0.90))
	profile_best.position = Vector2(16, 62)
	profile_best.size = Vector2(160, 22)
	card.add_child(profile_best)

	xp_text = Label.new()
	xp_text.add_theme_font_size_override("font_size", 12)
	xp_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_text.position = Vector2(144, 63)
	xp_text.size = Vector2(140, 20)
	card.add_child(xp_text)

	_refresh_profile()

func _refresh_profile() -> void:
	profile_name.text = GameState.player_name if not GameState.player_name.is_empty() else "PLAYER"
	var lvl := GameState.get_level()
	profile_chip.text = "LV " + str(lvl)
	profile_best.text = ("BEST  " + _fmt_num(GameState.best_score)) if GameState.best_score > 0 else "NO RUNS YET"
	if lvl >= GameState.MAX_LEVEL:
		xp_fill.size = Vector2(XP_BAR_W, 12)
		xp_text.text = "MAX LEVEL"
	else:
		var prog : Array = GameState.xp_progress()
		var frac : float = clampf(float(prog[0]) / float(maxi(prog[1], 1)), 0.0, 1.0)
		xp_fill.size = Vector2(maxf(XP_BAR_W * frac, 12.0 if prog[0] > 0 else 0.0), 12)
		xp_text.text = str(prog[0]) + " / " + str(prog[1]) + " XP"

# ── First-open name prompt ────────────────────────────────────────────────────
func _build_name_prompt() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", psb)
	panel.position = Vector2(47, 300)
	panel.custom_minimum_size = Vector2(320, 0)
	ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "WHAT'S YOUR NAME?"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var input := LineEdit.new()
	input.max_length = 12
	input.placeholder_text = "PLAYER"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 22)
	input.custom_minimum_size = Vector2(0, 52)
	vbox.add_child(input)

	var go := _make_chunky_button("LET'S GO", Color(0.20, 0.85, 0.45), 22)
	go.custom_minimum_size = Vector2(0, 56)
	vbox.add_child(go)

	var confirm := func():
		var n := input.text.strip_edges()
		GameState.set_player_name(n if not n.is_empty() else "PLAYER")
		Sfx.play_click()
		dim.queue_free()
		panel.queue_free()
		_build_menu()   # menu intro plays now, on a clean screen
	go.pressed.connect(confirm)
	input.text_submitted.connect(func(_t): confirm.call())
	input.grab_focus()

# ── Stats panel (opened from the profile card) ───────────────────────────────
var stats_box  : PanelContainer
var stats_grid : GridContainer
var stats_sub  : Label

func _build_stats_panel() -> void:
	stats_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	stats_box.add_theme_stylebox_override("panel", psb)
	stats_box.position = Vector2(22, 160)
	stats_box.custom_minimum_size = Vector2(370, 0)
	stats_box.visible = false
	ui.add_child(stats_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	stats_box.add_child(vbox)

	var title := Label.new()
	title.text = "STATS"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	stats_sub = Label.new()
	stats_sub.add_theme_font_size_override("font_size", 13)
	stats_sub.add_theme_color_override("font_color", Color(0.95, 0.78, 0.20, 0.90))
	stats_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats_sub)

	stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 10)
	stats_grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(stats_grid)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		stats_box.visible = false)
	vbox.add_child(close)

func _populate_stats() -> void:
	for child in stats_grid.get_children():
		child.queue_free()
	var pname := GameState.player_name if not GameState.player_name.is_empty() else "PLAYER"
	stats_sub.text = pname + "   ·   LEVEL " + str(GameState.get_level()) \
		+ "   ·   " + _fmt_num(GameState.player_xp) + " TOTAL XP"
	var stats : Array = [
		[_fmt_num(GameState.games_played),      "GAMES PLAYED"],
		[_fmt_num(GameState.best_score),        "HIGHEST SCORE"],
		[_fmt_num(GameState.total_score),       "TOTAL SCORE"],
		[_fmt_num(GameState.total_lines),       "LINES CLEARED"],
		[_fmt_num(GameState.stat_best_streak),  "LONGEST STREAK"],
		[_fmt_num(GameState.stat_run_lines),    "MOST LINES IN A RUN"],
		[_fmt_num(GameState.stat_blocks),       "BLOCKS PLACED"],
		[_fmt_num(GameState.stat_board_clears), "BOARD CLEARS"],
	]
	for s in stats:
		var tile := Panel.new()
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = Color(1, 1, 1, 0.05)
		tsb.set_corner_radius_all(14)
		tile.add_theme_stylebox_override("panel", tsb)
		tile.custom_minimum_size = Vector2(162, 62)
		var v := Label.new()
		v.text = s[0]
		v.add_theme_font_size_override("font_size", 21)
		v.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.position = Vector2(0, 6)
		v.size = Vector2(162, 30)
		tile.add_child(v)
		var c := Label.new()
		c.text = s[1]
		c.add_theme_font_size_override("font_size", 10)
		c.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.position = Vector2(0, 38)
		c.size = Vector2(162, 16)
		tile.add_child(c)
		stats_grid.add_child(tile)

func _open_stats() -> void:
	_populate_stats()
	stats_box.visible = true
	stats_box.scale = Vector2(0.85, 0.85)
	stats_box.pivot_offset = Vector2(185, 240)
	var t := create_tween()
	t.tween_property(stats_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Achievements panel (tiered: card shows current tier, tap to expand) ──────
var ach_box      : PanelContainer
var ach_rows     : VBoxContainer
var ach_expanded : Dictionary = {}   # group id -> bool

func _build_achievements_panel() -> void:
	ach_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.11, 0.20)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	ach_box.add_theme_stylebox_override("panel", psb)
	ach_box.position = Vector2(22, 70)
	ach_box.custom_minimum_size = Vector2(370, 0)
	ach_box.visible = false
	ui.add_child(ach_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	ach_box.add_child(vbox)

	var title := Label.new()
	title.text = "ACHIEVEMENTS"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(334, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	ach_rows = VBoxContainer.new()
	ach_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(ach_rows)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 18)
	close.custom_minimum_size = Vector2(0, 50)
	close.pressed.connect(func():
		Sfx.play_click()
		ach_box.visible = false)
	vbox.add_child(close)

# Rebuilt on every open / expand-toggle so progress is always current
func _populate_achievements() -> void:
	for child in ach_rows.get_children():
		child.queue_free()
	for g in GameState.ACH_GROUPS:
		ach_rows.add_child(_make_ach_card(g))
		if ach_expanded.get(g["id"], false):
			ach_rows.add_child(_make_tier_list(g))

# First locked tier index, or tiers.size() when the whole ladder is done
func _ach_current_tier(g: Dictionary) -> int:
	for ti in g["tiers"].size():
		if not GameState.unlocked.get("%s_%d" % [g["id"], ti], false):
			return ti
	return g["tiers"].size()

func _ach_desc(g: Dictionary, target: int) -> String:
	var d : String = g["desc"]
	@warning_ignore("static_called_on_instance")
	return (d % GameState.fmt(target)) if d.contains("%s") else d

func _make_ach_card(g: Dictionary) -> PanelContainer:
	var tiers : Array = g["tiers"]
	var cur   := _ach_current_tier(g)
	var done  := cur >= tiers.size()
	var shown : int = mini(cur, tiers.size() - 1)
	var target : int = tiers[shown][0]
	var v := GameState.ach_value(g["id"])

	# PanelContainer for layout (Buttons don't size child containers);
	# tap-to-expand handled via gui_input
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.78, 0.20, 0.12) if done else Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(14)
	if done:
		sb.border_width_left = 5
		sb.border_color = Color(0.95, 0.78, 0.20)
	sb.content_margin_left = 14; sb.content_margin_right = 12
	sb.content_margin_top = 10;  sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	# PASS (not STOP) so a touch-drag starting on a card still reaches the
	# ScrollContainer and scrolls the list. Toggle only on a TAP — a press and
	# release with little movement — so scrolling never expands a card.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("moved", false)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				card.set_meta("press_pos", ev.position)
				card.set_meta("moved", false)
			elif not card.get_meta("moved", false):
				Sfx.play_click()
				ach_expanded[g["id"]] = not ach_expanded.get(g["id"], false)
				_populate_achievements()
		elif ev is InputEventMouseMotion and card.has_meta("press_pos"):
			if ev.position.distance_to(card.get_meta("press_pos")) > 12.0:
				card.set_meta("moved", true))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# Medal disc with the tier numeral (gold once the ladder is complete)
	var medal := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.set_corner_radius_all(17)
	if done:
		msb.bg_color = Color(0.95, 0.78, 0.20)
		msb.set_border_width_all(3)
		msb.border_color = Color(1.0, 0.92, 0.55)
	else:
		msb.bg_color = Color(0, 0, 0, 0.30)
		msb.set_border_width_all(2)
		msb.border_color = Color(1, 1, 1, 0.15)
	medal.add_theme_stylebox_override("panel", msb)
	medal.custom_minimum_size = Vector2(34, 34)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var numeral := Label.new()
	numeral.text = GameState.TIER_NUMERALS[shown] if tiers.size() > 1 else "I"
	numeral.add_theme_font_size_override("font_size", 14)
	numeral.add_theme_color_override("font_color",
		Color(0.10, 0.08, 0.05) if done else Color(1, 1, 1, 0.65))
	numeral.set_anchors_preset(Control.PRESET_FULL_RECT)
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	medal.add_child(numeral)
	h.add_child(medal)

	# Name + current-tier description + progress
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(vb)

	var nm := Label.new()
	nm.text = g["name"] + ((" " + GameState.TIER_NUMERALS[shown]) if tiers.size() > 1 and not done else "")
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 1, 1, 0.95) if done else Color(1, 1, 1, 0.75))
	vb.add_child(nm)

	var ds := Label.new()
	ds.text = "ALL TIERS COMPLETE" if done else _ach_desc(g, target)
	ds.add_theme_font_size_override("font_size", 12)
	ds.add_theme_color_override("font_color",
		Color(0.95, 0.78, 0.20, 0.85) if done else Color(1, 1, 1, 0.40))
	vb.add_child(ds)

	if not done:
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 8)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(ph)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = target
		bar.value = mini(v, target)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bbg := StyleBoxFlat.new()
		bbg.bg_color = Color(0, 0, 0, 0.35)
		bbg.set_corner_radius_all(5)
		var bfg := StyleBoxFlat.new()
		bfg.bg_color = Color(0.95, 0.78, 0.20)
		bfg.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("background", bbg)
		bar.add_theme_stylebox_override("fill", bfg)
		ph.add_child(bar)
		var pl := Label.new()
		@warning_ignore("static_called_on_instance")
		pl.text = GameState.fmt(mini(v, target)) + " / " + GameState.fmt(target)
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_child(pl)

	# XP chip: current tier's reward, or total earned when complete
	var chip := Label.new()
	var chip_xp : int = tiers[shown][1]
	if done:
		chip_xp = 0
		for tier in tiers:
			chip_xp += tier[1]
	chip.text = "+" + str(chip_xp) + " XP"
	chip.add_theme_font_size_override("font_size", 13)
	var csb := StyleBoxFlat.new()
	csb.set_corner_radius_all(10)
	csb.content_margin_left = 10; csb.content_margin_right = 10
	csb.content_margin_top = 4;   csb.content_margin_bottom = 4
	if done:
		csb.bg_color = Color(0.95, 0.78, 0.20)
		chip.add_theme_color_override("font_color", Color(0.10, 0.08, 0.05))
	else:
		csb.bg_color = Color(0, 0, 0, 0.30)
		chip.add_theme_color_override("font_color", Color(1, 1, 1, 0.40))
	chip.add_theme_stylebox_override("normal", csb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(chip)

	return card

# Expanded ladder: one line per tier, coloured by state
func _make_tier_list(g: Dictionary) -> PanelContainer:
	var cur := _ach_current_tier(g)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.22)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18; sb.content_margin_right = 14
	sb.content_margin_top = 8;   sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)

	for ti in g["tiers"].size():
		var tier : Array = g["tiers"][ti]
		var got : bool = GameState.unlocked.get("%s_%d" % [g["id"], ti], false)
		var row := Label.new()
		var numeral : String = GameState.TIER_NUMERALS[ti] if g["tiers"].size() > 1 else "I"
		var state : String = "DONE" if got else ("NEXT" if ti == cur else "LOCKED")
		row.text = numeral + "    " + _ach_desc(g, tier[0]) + "    ·    +" + str(tier[1]) + " XP    ·    " + state
		row.add_theme_font_size_override("font_size", 12)
		if got:
			row.add_theme_color_override("font_color", Color(0.95, 0.78, 0.20, 0.95))
		elif ti == cur:
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.80))
		else:
			row.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
		vb.add_child(row)

	return box

func _fmt_num(n: int) -> String:
	if n < 1000:
		return str(n)
	return str(n / 1000) + "," + str(n % 1000).pad_zeros(3)

func _open_achievements() -> void:
	_populate_achievements()
	ach_box.visible = true
	ach_box.scale = Vector2(0.85, 0.85)
	ach_box.pivot_offset = Vector2(185, 280)
	var t := create_tween()
	t.tween_property(ach_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Buttons ───────────────────────────────────────────────────────────────────
func _make_chunky_button(label_text: String, fill: Color, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = label_text
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(20)
	sb.border_width_bottom = 7
	sb.border_color = fill.darkened(0.40)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = fill.lightened(0.10)
	var sb_press := sb.duplicate()
	sb_press.bg_color = fill.darkened(0.10)
	sb_press.border_width_bottom = 2
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_press)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	var fc := Color(0.08, 0.06, 0.12)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	_add_press_effect(b)
	return b

# Press-and-hold sinks the button face by the same 5px the bottom edge
# collapses, so it physically pushes in; release springs it back out.
func _add_press_effect(b: Button) -> void:
	b.button_down.connect(func():
		Sfx.play_tick()
		if b.has_meta("press_tw"):
			var old: Tween = b.get_meta("press_tw")
			if old and old.is_valid(): old.kill()
		b.set_meta("press_y", b.position.y)
		var t := b.create_tween()
		b.set_meta("press_tw", t)
		t.tween_property(b, "position:y", b.position.y + 5.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func():
		if not b.has_meta("press_y"):
			return
		if b.has_meta("press_tw"):
			var old: Tween = b.get_meta("press_tw")
			if old and old.is_valid(): old.kill()
		var t := b.create_tween()
		b.set_meta("press_tw", t)
		t.tween_property(b, "position:y", float(b.get_meta("press_y")), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

func _build_buttons() -> void:
	var has_run := GameState.has_run_save()
	var fade_in : Array = []
	var primary : Button

	if has_run:
		var cont := _make_chunky_button("CONTINUE", Color(0.95, 0.75, 0.15), 28)
		cont.size = Vector2(280, 72)
		cont.position = Vector2(67, 430)
		cont.pivot_offset = cont.size * 0.5
		ui.add_child(cont)
		cont.pressed.connect(_on_continue_pressed.bind(cont))
		fade_in.append(cont)
		primary = cont

		var play := _make_chunky_button("NEW GAME", Color(0.20, 0.85, 0.45), 22)
		play.size = Vector2(280, 58)
		play.position = Vector2(67, 516)
		play.pivot_offset = play.size * 0.5
		ui.add_child(play)
		play.pressed.connect(_on_play_pressed.bind(play))
		fade_in.append(play)
	else:
		var play := _make_chunky_button("PLAY", Color(0.20, 0.85, 0.45), 34)
		play.size = Vector2(280, 78)
		play.position = Vector2(67, 430)
		play.pivot_offset = play.size * 0.5
		ui.add_child(play)
		play.pressed.connect(_on_play_pressed.bind(play))
		fade_in.append(play)
		primary = play

	var ach := _make_chunky_button("ACHIEVEMENTS", Color(0.95, 0.55, 0.25), 22)
	ach.size = Vector2(280, 58)
	ach.position = Vector2(67, 588 if has_run else 526)
	ach.pivot_offset = ach.size * 0.5
	ui.add_child(ach)
	ach.pressed.connect(func():
		Sfx.play_click()
		_open_achievements())
	fade_in.append(ach)

	var settings := _make_chunky_button("SETTINGS", Color(0.20, 0.75, 0.95), 22)
	settings.size = Vector2(280, 58)
	settings.position = Vector2(67, 660 if has_run else 598)
	settings.pivot_offset = settings.size * 0.5
	ui.add_child(settings)
	settings.pressed.connect(func():
		Sfx.play_click()
		_open_settings())
	fade_in.append(settings)

	# Fade buttons in after the logo lands
	for btn in fade_in:
		btn.modulate.a = 0.0
		var t := create_tween()
		t.tween_interval(0.85)
		t.tween_property(btn, "modulate:a", 1.0, 0.35)

	# Idle pulse on the primary button so it invites a tap
	play_pulse = create_tween().set_loops()
	play_pulse.tween_interval(1.2)
	play_pulse.tween_property(primary, "scale", Vector2(1.05, 1.05), 0.45).set_trans(Tween.TRANS_SINE)
	play_pulse.tween_property(primary, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)

func _on_play_pressed(play: Button) -> void:
	# A saved run exists → confirm before wiping it
	if GameState.has_run_save():
		_confirm_new_game(play)
		return
	GameState.has_save = false
	GameState.clear_run()
	_launch(play)

func _confirm_new_game(play: Button) -> void:
	Sfx.play_click()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(414, 896)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dim)

	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.19, 0.99)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 22;  sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(322, 0)
	box.position = Vector2(46, 330)
	dim.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)

	var title := Label.new()
	title.text = "START NEW GAME?"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var msg := Label.new()
	msg.text = "Your saved run will be lost."
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(msg)

	var yes := _make_chunky_button("NEW GAME", Color(0.90, 0.35, 0.35), 22)
	yes.custom_minimum_size = Vector2(278, 56)
	vb.add_child(yes)
	var no := _make_chunky_button("KEEP PLAYING", Color(0.20, 0.75, 0.95), 22)
	no.custom_minimum_size = Vector2(278, 56)
	vb.add_child(no)

	box.modulate.a = 0.0
	box.scale = Vector2(0.9, 0.9)
	box.pivot_offset = Vector2(161, 120)
	var t := create_tween()
	t.tween_property(box, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	yes.pressed.connect(func():
		GameState.has_save = false
		GameState.clear_run()
		_launch(play))
	no.pressed.connect(func():
		Sfx.play_click()
		dim.queue_free())

func _on_continue_pressed(cont: Button) -> void:
	if not GameState.load_run_from_disk():
		# Run file unreadable — fall back to a fresh game
		GameState.has_save = false
		GameState.clear_run()
	_launch(cont)

func _launch(btn: Button) -> void:
	Sfx.play_click()
	if play_pulse:
		play_pulse.kill()
	var t := create_tween()
	t.tween_property(btn, "scale", Vector2(0.90, 0.90), 0.08)
	t.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/Game.tscn"))

# ── Settings panel ────────────────────────────────────────────────────────────
func _build_settings_panel() -> void:
	settings_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.10, 0.18)
	psb.set_corner_radius_all(24)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 28; psb.content_margin_right = 28
	psb.content_margin_top = 24;  psb.content_margin_bottom = 28
	settings_box.add_theme_stylebox_override("panel", psb)
	settings_box.position = Vector2(57, 280)
	settings_box.custom_minimum_size = Vector2(300, 0)
	settings_box.visible = false
	ui.add_child(settings_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	settings_box.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var snd := _make_chunky_button(_sound_text(), Color(0.20, 0.75, 0.95), 20)
	snd.custom_minimum_size = Vector2(0, 56)
	snd.pressed.connect(func():
		GameState.set_sound(not GameState.sound_on)
		snd.text = _sound_text()
		Sfx.play_click())
	vbox.add_child(snd)

	var mus := _make_chunky_button(_music_text(), Color(0.65, 0.30, 0.95), 20)
	mus.custom_minimum_size = Vector2(0, 56)
	mus.pressed.connect(func():
		GameState.set_music(not GameState.music_on)
		Sfx.update_music()
		mus.text = _music_text()
		Sfx.play_click())
	vbox.add_child(mus)

	var hap := _make_chunky_button(_haptics_text(), Color(0.95, 0.75, 0.15), 20)
	hap.custom_minimum_size = Vector2(0, 56)
	hap.pressed.connect(func():
		GameState.set_haptics(not GameState.haptics_on)
		hap.text = _haptics_text()
		if GameState.haptics_on:
			Input.vibrate_handheld(30)
		Sfx.play_click())
	vbox.add_child(hap)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 20)
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(func():
		Sfx.play_click()
		settings_box.visible = false)
	vbox.add_child(close)

	var ver := Label.new()
	ver.text = "STAX  v" + str(ProjectSettings.get_setting("application/config/version", "1.1.0"))
	ver.add_theme_font_size_override("font_size", 13)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.30))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ver)

func _sound_text() -> String:
	return "SOUND: ON" if GameState.sound_on else "SOUND: OFF"

func _music_text() -> String:
	return "MUSIC: ON" if GameState.music_on else "MUSIC: OFF"

func _haptics_text() -> String:
	return "HAPTICS: ON" if GameState.haptics_on else "HAPTICS: OFF"

func _open_settings() -> void:
	settings_box.visible = true
	settings_box.scale = Vector2(0.85, 0.85)
	settings_box.pivot_offset = Vector2(150, 130)
	var t := create_tween()
	t.tween_property(settings_box, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Dev skin picker (hidden when SHOW_SKIN_PICKER = false) ───────────────────
var skin_box   : PanelContainer
var skin_label : Label

func _build_skin_picker() -> void:
	var open_btn := _make_chunky_button("SKINS", Color(0.55, 0.45, 0.75), 15)
	open_btn.size = Vector2(96, 42)
	open_btn.position = Vector2(10, 844)
	open_btn.pivot_offset = open_btn.size * 0.5
	ui.add_child(open_btn)
	open_btn.pressed.connect(func():
		Sfx.play_click()
		skin_box.visible = not skin_box.visible)

	skin_box = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.10, 0.18)
	psb.set_corner_radius_all(20)
	psb.border_width_bottom = 8
	psb.border_color = Color(0.06, 0.05, 0.10)
	psb.content_margin_left = 18; psb.content_margin_right = 18
	psb.content_margin_top = 16;  psb.content_margin_bottom = 20
	skin_box.add_theme_stylebox_override("panel", psb)
	skin_box.position = Vector2(37, 250)
	skin_box.custom_minimum_size = Vector2(340, 0)
	skin_box.visible = false
	ui.add_child(skin_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	skin_box.add_child(vbox)

	var title := Label.new()
	title.text = "SKINS  (DEV)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	skin_label = Label.new()
	skin_label.text = _skin_current_text()
	skin_label.add_theme_font_size_override("font_size", 14)
	skin_label.add_theme_color_override("font_color", Color(0.55, 0.80, 0.95, 0.9))
	skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(skin_label)

	# Scrollable so the (now 30+) skins all fit on screen
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(304, 396)
	vbox.add_child(scroll)

	var grid_c := GridContainer.new()
	grid_c.columns = 3
	grid_c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS so a touch-drag starting on the grid still reaches the ScrollContainer
	grid_c.mouse_filter = Control.MOUSE_FILTER_PASS
	grid_c.add_theme_constant_override("h_separation", 8)
	grid_c.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid_c)

	var auto_btn := _make_chunky_button("AUTO", Color(0.20, 0.85, 0.45), 13)
	auto_btn.custom_minimum_size = Vector2(96, 40)
	auto_btn.mouse_filter = Control.MOUSE_FILTER_PASS   # let drags scroll, taps still select
	auto_btn.pressed.connect(func():
		GameState.dev_skin_override = -1
		skin_label.text = _skin_current_text()
		Sfx.play_click())
	grid_c.add_child(auto_btn)

	for i in SKIN_NAMES.size():
		var b := _make_chunky_button(SKIN_NAMES[i], Color(0.20, 0.75, 0.95), 13)
		b.custom_minimum_size = Vector2(96, 40)
		b.mouse_filter = Control.MOUSE_FILTER_PASS   # drag scrolls, tap selects
		var idx := i
		b.pressed.connect(func():
			GameState.dev_skin_override = idx
			skin_label.text = _skin_current_text()
			Sfx.play_click())
		grid_c.add_child(b)

	var close := _make_chunky_button("CLOSE", Color(0.90, 0.30, 0.40), 14)
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func():
		Sfx.play_click()
		skin_box.visible = false)
	vbox.add_child(close)

func _skin_current_text() -> String:
	if GameState.dev_skin_override < 0:
		return "CURRENT:  AUTO (follows theme)"
	return "CURRENT:  " + SKIN_NAMES[GameState.dev_skin_override]
