extends Node2D

@onready var score_label : Label = $UI/FinalScore
@onready var best_label  : Label = $UI/BestScore
@onready var ui          : CanvasLayer = $UI

func _ready() -> void:
	score_label.text = str(GameState.last_score)

	if GameState.best_score > 0:
		if GameState.last_score >= GameState.best_score:
			best_label.text = "NEW BEST!"
			best_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.15, 1.0))
		else:
			best_label.text = "BEST  " + str(GameState.best_score)

	# Score count-up
	var target : int = GameState.last_score
	var tween  := create_tween()
	tween.tween_method(func(v: float): score_label.text = str(int(v)),
		0.0, float(target), clampf(target * 0.01, 0.1, 1.2))

	# Leaderboard
	_build_leaderboard()

func _build_leaderboard() -> void:
	var scores := GameState.scores
	if scores.is_empty():
		return

	var header := Label.new()
	header.text = "— TOP SCORES —"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.size = Vector2(300, 24)
	header.position = Vector2(57, 420)
	ui.add_child(header)

	var top_n : int = min(scores.size(), 5)
	for i in top_n:
		var lbl := Label.new()
		var is_current : bool = (scores[i] == GameState.last_score and i == 0)
		lbl.text = "#%d    %d" % [i + 1, scores[i]]
		lbl.add_theme_font_size_override("font_size", 22)
		var col : Color
		if i == 0:
			col = Color(0.95, 0.85, 0.15, 0.95)
		elif is_current:
			col = Color(0.20, 0.85, 0.45, 0.9)
		else:
			col = Color(1, 1, 1, 0.45 - i * 0.06)
		lbl.add_theme_color_override("font_color", col)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(300, 32)
		lbl.position = Vector2(57, 448.0 + i * 34.0)
		ui.add_child(lbl)

func _on_watch_ad_pressed() -> void:
	# Real AdMob call goes here — for now just continue
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_retry_pressed() -> void:
	GameState.has_save = false
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
