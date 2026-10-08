extends Node
## Autoload "Game": estado global compartilhado entre cenas e scripts.

var dialog_active := false
var dialog_cooldown := 0.0
var input_locked := false      # true durante cutscenes/intro do boss
var checkpoint := Vector2.ZERO # posição global do último checkpoint
var visited_zones: Array = []
var kills := 0
var secrets := 0
var chests_opened := 0
var elapsed := 0.0
var running := false
var boss_fight := false

func reset() -> void:
	dialog_active = false
	dialog_cooldown = 0.0
	input_locked = false
	checkpoint = Vector2.ZERO
	visited_zones = []
	kills = 0
	secrets = 0
	chests_opened = 0
	elapsed = 0.0
	running = false
	boss_fight = false
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	if dialog_cooldown > 0.0:
		dialog_cooldown -= delta
	if running and not get_tree().paused:
		elapsed += delta

func time_text() -> String:
	var t := int(elapsed)
	return "%02d:%02d" % [t / 60, t % 60]
