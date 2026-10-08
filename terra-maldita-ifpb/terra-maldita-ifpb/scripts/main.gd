extends Node2D
## Cena principal: monta o nível, a HUD e conduz o fluxo do jogo
## (zonas, checkpoints, música dinâmica, luta contra o chefe, vitória e derrota).

const Hud = preload("res://scripts/hud.gd")
const Level = preload("res://scripts/level.gd")
const Dialogs = preload("res://scripts/dialogs.gd")
const LevelData = preload("res://scripts/level_data.gd")
const Fx = preload("res://scripts/fx.gd")

var _hud
var _player
var _world
var _boss
var _zone_id := ""
var _zone_t := 0.0
var _combat_hold := 0.0
var _boss_started := false
var _boss_done := false
var _music_lock := false
var _bird_t := 8.0

func _ready() -> void:
	Game.reset()
	get_tree().paused = false

	_world = Level.new()
	_world.position = $Mapa.position
	add_child(_world)

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("main.gd: jogador não encontrado (grupo 'player').")
		return
	_player.reparent(_world) # entra no y-sort do mundo
	_world.build()
	_boss = _world.boss

	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_hud = Hud.new()
	layer.add_child(_hud)
	_hud.secrets_total = _world.secrets_total

	_player.health_changed.connect(_hud.set_health)
	_player.ammo_changed.connect(_hud.set_ammo)
	_player.inventory_changed.connect(_hud.set_inventory)
	_player.died.connect(_on_player_died)
	_player.refresh_hud()
	_boss.hp_changed.connect(_hud.set_boss_hp)
	_boss.died.connect(_on_boss_died)
	_hud.respawn_requested.connect(_on_respawn)
	_hud.menu_requested.connect(_goto_menu)

	Game.checkpoint = _player.global_position
	Game.running = true
	_hud.set_objective("Objetivo: derrote o Coronel Cascavel")
	_hud.fade_to(0.0, 1.4)
	Audio.play_music("explore", 2.0)
	_hud.show_message("WASD mover | Shift correr | Mouse mirar | Clique atirar | R recarregar\nE interagir | 1-4 ou roda do mouse: trocar arma | ESC pausa", 7.0)
	_update_zone(true)

func _process(delta: float) -> void:
	if _player == null:
		return
	_zone_t -= delta
	if _zone_t <= 0.0:
		_zone_t = 0.3
		_update_zone(false)
		_check_boss_trigger()
	_update_music(delta)
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = randf_range(7.0, 16.0)
		if _zone_id in ["inicio", "vila", "estrada"] and not Audio.muted:
			Audio.sfx("bird1" if randf() < 0.5 else "bird2", -14.0, 1.0, 0.1)

# ------------------------------------------------------------------ Zonas

func _update_zone(first: bool) -> void:
	if _player.is_dead():
		return
	var idx: int = _world.nearest_path_index(_player.global_position)
	var z: Array = _world.zone_at(idx)
	var zid := String(z[2])
	if zid == _zone_id:
		return
	_zone_id = zid
	_hud.show_banner(String(z[3]), "", 3.2, false)
	if not first:
		_hud.set_objective("Objetivo: " + String(z[4]))
	else:
		_hud.set_objective("Objetivo: " + String(z[4]))
	if not Game.visited_zones.has(zid):
		Game.visited_zones.append(zid)
		if not first and not _boss_started:
			Game.checkpoint = _player.global_position
			Audio.sfx("checkpoint", -4.0)
			_hud.show_message("Checkpoint!", 1.8)
	Audio.set_wind(-30.0 if zid in ["vila", "abandonada"] else -22.0)

# ---------------------------------------------------------------- Música

func _update_music(delta: float) -> void:
	if _music_lock:
		return
	var aggro := 0
	for e in get_tree().get_nodes_in_group("enemy_ai"):
		if e.has_method("is_aggro") and e.is_aggro() and not e.is_boss():
			aggro += 1
	if aggro > 0:
		_combat_hold = 4.0
	else:
		_combat_hold = maxf(_combat_hold - delta, 0.0)
	if Game.boss_fight:
		if _boss != null and _boss.active:
			Audio.play_music("boss", 0.6)
	elif _combat_hold > 0.0:
		Audio.play_music("combat", 0.6)
	else:
		Audio.play_music("explore", 1.5)

# ------------------------------------------------------------------- Boss

func _check_boss_trigger() -> void:
	if _boss_started or _boss_done or _player.is_dead():
		return
	var lp: Vector2 = _world.to_local(_player.global_position)
	if LevelData.ARENA_TRIGGER.has_point(lp):
		_start_boss_fight()

func _start_boss_fight() -> void:
	_boss_started = true
	Game.boss_fight = true
	Game.input_locked = true
	_world.close_gate()
	Audio.sfx("gate")
	_player.shake(4.0, 0.4)
	Audio.stop_music(0.8)
	await get_tree().create_timer(0.9).timeout
	if _player.is_dead():
		return
	_hud.show_banner("CORONEL CASCAVEL", "O chefe dos bandidos", 3.0, true)
	Audio.sfx("boss_roar")
	_player.shake(3.0, 0.5)
	await get_tree().create_timer(2.4).timeout
	if _player.is_dead():
		return
	_hud.start_dialog(Dialogs.BOSS_INTRO)
	await _hud.dialog_finished
	if _player.is_dead():
		return
	Game.input_locked = false
	Audio.play_music("boss", 0.4)
	_hud.show_boss_bar("CORONEL CASCAVEL", _boss.hp, _boss.max_hp)
	_hud.set_objective("Derrote o Coronel Cascavel!")
	_boss.activate()

func _on_boss_died(_e) -> void:
	_boss_done = true
	_music_lock = true
	Game.running = false
	Game.input_locked = true
	_player.set("_invuln", 99.0)
	_hud.hide_boss_bar()
	Audio.stop_music(0.2)
	Audio.sfx("boss_die")
	Engine.time_scale = 0.3
	_player.shake(6.0, 0.9)
	var center: Vector2 = _boss.global_position + Vector2(0, -20)
	for i in 7:
		var c := Color(1.0, 0.6, 0.15) if i % 2 == 0 else Color(0.9, 0.2, 0.1)
		Fx.burst(_world, center + Vector2(randf_range(-22, 22), randf_range(-26, 14)), c, 14, 90.0, 0.7, 2.6, 40.0)
		await get_tree().create_timer(0.18, true, false, true).timeout
	Engine.time_scale = 1.0
	_hud.flash(Color(1, 1, 1), 0.9)
	await get_tree().create_timer(1.4).timeout
	_world.open_gate()
	Audio.play_music("victory", 0.2)
	_hud.show_banner("VITÓRIA!", "O Coronel Cascavel caiu.", 4.5, true)
	await get_tree().create_timer(3.2).timeout
	_hud.show_screen("win")

# ------------------------------------------------------- Morte / retorno

func _on_player_died() -> void:
	_music_lock = true
	Audio.stop_music(0.3)
	await get_tree().create_timer(0.5).timeout
	Audio.play_music("defeat", 0.2)
	await get_tree().create_timer(0.8).timeout
	_hud.show_screen("dead")

func _on_respawn() -> void:
	_hud.fade_to(1.0, 0.4)
	await get_tree().create_timer(0.45).timeout
	if _boss_started and not _boss_done:
		_boss.reset_boss()
		_world.open_gate()
		_boss_started = false
		Game.boss_fight = false
		_hud.hide_boss_bar()
	Game.input_locked = false
	Game.dialog_active = false
	_player.respawn(Game.checkpoint)
	_hud.show_screen("")
	_music_lock = false
	_combat_hold = 0.0
	Audio.play_music("explore", 0.5)
	_hud.fade_to(0.0, 0.5)
	_hud.show_message("De volta ao último checkpoint.", 2.5)

func _goto_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.stop_music(0.4)
	_hud.fade_to(1.0, 0.4)
	await get_tree().create_timer(0.45).timeout
	get_tree().change_scene_to_file("res://main.tscn")
