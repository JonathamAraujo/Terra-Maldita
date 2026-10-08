extends CharacterBody2D
## Inimigos (bandido, armado, rapido, guarda, capanga, capangaforte) e o CHEFE ("boss").
## Criado por código pelo level.gd. A IA é simples: patrulha -> alerta -> perseguição/ataque.
## O boss usa padrões com telegrafia (aviso visual + som) que o jogador consegue aprender:
##   RAJADA (3-5 tiros mirados) | LEQUE (tiros em arco, com brechas) | INVESTIDA (avisa e corre) | ANEL (fase 2)
##   Após a investida ou uma sequência ele DESCANSA: é a hora de causar mais dano.

const Catalog = preload("res://scripts/catalog.gd")
const BulletScript = preload("res://scripts/bullet.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const Fx = preload("res://scripts/fx.gd")

signal died(enemy)
signal hp_changed(current: float, maximum: float)
signal summon_requested(kind: String, pos: Vector2)
signal phase_changed(phase: int)

enum S { PATROL, ALERT, CHASE, DEAD }

## hp, speed (patrulha), chase, sprite, scale, sight, attack, cooldown, dmg, spread, range, bspeed, pellets, drop, hold, windup, melee
const KINDS := {
	"bandido": {"hp": 3.0, "speed": 30.0, "chase": 56.0, "sprite": "bandit0", "scale": 1.0, "sight": 125.0, "attack": "shoot",
		"cooldown": 1.8, "dmg": 1.0, "spread": 0.22, "range": 130.0, "bspeed": 165.0, "pellets": 1, "drop": 0.30, "hold": false, "windup": 0.30, "melee": 0.0},
	"armado": {"hp": 4.0, "speed": 28.0, "chase": 38.0, "sprite": "bandit3", "scale": 1.0, "sight": 170.0, "attack": "shoot",
		"cooldown": 1.25, "dmg": 1.0, "spread": 0.08, "range": 175.0, "bspeed": 215.0, "pellets": 1, "drop": 0.35, "hold": false, "windup": 0.35, "melee": 0.0},
	"rapido": {"hp": 2.0, "speed": 40.0, "chase": 105.0, "sprite": "bandit9", "scale": 0.95, "sight": 120.0, "attack": "melee",
		"cooldown": 0.9, "dmg": 1.0, "spread": 0.0, "range": 0.0, "bspeed": 0.0, "pellets": 0, "drop": 0.25, "hold": false, "windup": 0.0, "melee": 13.0},
	"guarda": {"hp": 5.0, "speed": 0.0, "chase": 0.0, "sprite": "bandit5", "scale": 1.0, "sight": 160.0, "attack": "shoot",
		"cooldown": 1.0, "dmg": 1.0, "spread": 0.06, "range": 170.0, "bspeed": 210.0, "pellets": 1, "drop": 0.40, "hold": true, "windup": 0.35, "melee": 0.0},
	"capanga": {"hp": 8.0, "speed": 28.0, "chase": 50.0, "sprite": "bandit21", "scale": 1.1, "sight": 150.0, "attack": "shoot",
		"cooldown": 1.55, "dmg": 1.0, "spread": 0.32, "range": 125.0, "bspeed": 185.0, "pellets": 3, "drop": 0.50, "hold": false, "windup": 0.40, "melee": 0.0},
	"capangaforte": {"hp": 14.0, "speed": 26.0, "chase": 46.0, "sprite": "bandit23", "scale": 1.2, "sight": 160.0, "attack": "shoot",
		"cooldown": 1.4, "dmg": 1.0, "spread": 0.42, "range": 130.0, "bspeed": 190.0, "pellets": 5, "drop": 0.70, "hold": false, "windup": 0.45, "melee": 0.0},
	"boss": {"hp": 60.0, "speed": 0.0, "chase": 0.0, "sprite": "bandit22", "scale": 1.9, "sight": 999.0, "attack": "boss",
		"cooldown": 1.0, "dmg": 1.0, "spread": 0.0, "range": 200.0, "bspeed": 160.0, "pellets": 1, "drop": 0.0, "hold": true, "windup": 0.0, "melee": 0.0},
}

@export var kind := "bandido"

var data: Dictionary
var hp := 3.0
var max_hp := 3.0
var state: int = S.PATROL
var patrol_points: Array[Vector2] = []   # posições GLOBAIS
var player: Node = null

var _sprite: Sprite2D
var _h := 30.0
var _cd := 1.0
var _windup := 0.0
var _alert_t := 0.0
var _los_t := 0.0
var _can_see := false
var _lost := 0.0
var _anim_t := randf() * 10.0
var _kb := Vector2.ZERO
var _kb_t := 0.0
var _pi := 0
var _wait := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck := 0.0
var _unstick := 0.0
var _tint := Color.WHITE

# --- boss ---
var active := false
var phase := 1
var arena := Rect2()           # área do boss (global)
var home := Vector2.ZERO
var summons: Array = []
var _gen := 0
var _dashing := false
var _dash_dir := Vector2.RIGHT
var _dash_t := 0.0
var _dash_hit := false
var _resting := false
var _stun := 0.0
var _speed_mult := 1.0
var _low_warned := false

func _ready() -> void:
	data = KINDS[kind]
	max_hp = float(data["hp"])
	hp = max_hp
	add_to_group("enemy")
	add_to_group("enemy_ai")
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 4.0 * (1.0 if kind != "boss" else 1.6)
	cs.shape = c
	cs.position = Vector2(0, -2)
	add_child(cs)
	_sprite = Catalog.make(String(data["sprite"]), float(data["scale"]))
	if kind == "boss":
		_tint = Color(1.0, 0.78, 0.78)
		add_to_group("boss")
	elif kind == "capangaforte":
		_tint = Color(1.0, 0.85, 0.85)
	_sprite.modulate = _tint
	add_child(_sprite)
	_h = _sprite.texture.get_height() * _sprite.scale.y
	_cd = randf_range(0.6, 1.6)
	home = global_position

# ----------------------------------------------------------------- Loop

func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	_cd = maxf(_cd - delta, 0.0)
	_anim_t += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if kind == "boss":
		_boss_physics(delta)
		return
	if _kb_t > 0.0:
		_kb_t -= delta
		velocity = _kb
		move_and_slide()
		_animate(false)
		return

	var pdead: bool = player == null or player.is_dead()
	var d := 99999.0
	if not pdead:
		d = global_position.distance_to(player.global_position)
		_los_t -= delta
		if _los_t <= 0.0:
			_los_t = 0.15
			_can_see = d <= float(data["sight"]) * 1.35 and _clear_to_player()
	else:
		_can_see = false

	var dir := Vector2.ZERO
	var spd := 0.0
	match state:
		S.PATROL:
			if _can_see and d <= float(data["sight"]):
				_set_alert(true)
			else:
				dir = _patrol_dir(delta)
				spd = float(data["speed"])
		S.ALERT:
			_alert_t -= delta
			if player != null:
				_sprite.flip_h = player.global_position.x < global_position.x
			if _alert_t <= 0.0:
				state = S.CHASE
		S.CHASE:
			if pdead:
				state = S.PATROL
			else:
				var r := _chase(delta, d)
				dir = r[0]
				spd = r[1]
	velocity = dir * spd
	move_and_slide()
	# detecta travamento em quinas e tenta contornar
	if dir != Vector2.ZERO and state == S.CHASE and get_real_velocity().length() < spd * 0.2:
		_stuck += delta
		if _stuck > 0.45:
			_stuck = 0.0
			_strafe = -_strafe
			_unstick = 0.6
	else:
		_stuck = maxf(_stuck - delta, 0.0)
	_animate(velocity.length() > 5.0)
	queue_redraw()

func _chase(delta: float, d: float) -> Array:
	var to: Vector2 = player.global_position - global_position
	var tdir := to.normalized()
	var spd := float(data["chase"])
	var dir := Vector2.ZERO
	_sprite.flip_h = to.x < 0.0
	if _unstick > 0.0:
		_unstick -= delta
		return [tdir.rotated(_strafe * 1.3), spd]
	if String(data["attack"]) == "melee":
		dir = tdir
		if d <= float(data["melee"]) and _cd <= 0.0:
			_melee()
		return [dir, spd]
	var rng := float(data["range"])
	var want := rng * 0.7
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			_fire()
		return [Vector2.ZERO, 0.0]
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.0, 2.2)
		_strafe = -_strafe
	if _can_see:
		_lost = 0.0
		if bool(data["hold"]):
			dir = Vector2.ZERO
		elif d > want:
			dir = tdir
		elif d < want * 0.4:
			dir = -tdir
		else:
			dir = tdir.orthogonal() * _strafe * 0.55
		if d <= rng and _cd <= 0.0:
			_windup = float(data["windup"])
			Fx.flash(_sprite, Color(1.6, 1.4, 0.6), _windup, _tint)
	else:
		_lost += delta
		if not bool(data["hold"]):
			dir = tdir
		if _lost > 6.0 and d > float(data["sight"]) * 1.6:
			state = S.PATROL
	return [dir, spd]

func _patrol_dir(delta: float) -> Vector2:
	if patrol_points.size() < 2 or float(data["speed"]) <= 0.0:
		return Vector2.ZERO
	if _wait > 0.0:
		_wait -= delta
		return Vector2.ZERO
	var to := patrol_points[_pi] - global_position
	if to.length() < 4.0:
		_pi = (_pi + 1) % patrol_points.size()
		_wait = randf_range(0.8, 2.0)
		return Vector2.ZERO
	_sprite.flip_h = to.x < 0.0
	return to.normalized()

func _clear_to_player() -> bool:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(0, -_h * 0.5)
	var to: Vector2 = player.sprite.global_position
	var ex: Array[RID] = [get_rid(), player.get_rid()]
	var q := PhysicsRayQueryParameters2D.create(from, to, 1, ex)
	return space.intersect_ray(q).is_empty()

func _set_alert(propagate: bool) -> void:
	state = S.ALERT
	_alert_t = 0.35
	Fx.flash(_sprite, Color(1.5, 1.5, 1.5), 0.2, _tint)
	if propagate:
		get_tree().call_group("enemy_ai", "_on_ally_alert", global_position)

func _on_ally_alert(from: Vector2) -> void:
	if kind == "boss" or state != S.PATROL:
		return
	if global_position.distance_to(from) < 110.0:
		state = S.ALERT
		_alert_t = randf_range(0.3, 0.7)

# -------------------------------------------------------------- Ataques

func _muzzle() -> Vector2:
	return global_position + Vector2(0, -_h * 0.55)

func _fire() -> void:
	if player == null or player.is_dead():
		return
	var from := _muzzle()
	var aim: Vector2 = (player.sprite.global_position - from).normalized()
	var pellets := int(data["pellets"])
	var spread := float(data["spread"])
	for i in pellets:
		var off := 0.0
		if pellets == 1:
			off = randf_range(-spread, spread)
		else:
			off = lerpf(-spread, spread, float(i) / float(pellets - 1)) + randf_range(-0.03, 0.03)
		_spawn_bullet(from + aim * 8.0, aim.rotated(off), float(data["bspeed"]), float(data["dmg"]), float(data["range"]) * 1.3, Color(1.0, 0.5, 0.2))
	var dist := global_position.distance_to(player.global_position)
	Audio.sfx("shot_enemy", -clampf((dist - 40.0) / 7.0, 0.0, 16.0), 1.0, 0.08)
	Fx.burst(get_parent(), from + aim * 8.0, Color(1.0, 0.8, 0.3), 4, 40.0, 0.12, 1.5, 0.0, 40.0, aim)
	_cd = float(data["cooldown"]) * randf_range(0.85, 1.25)

func _melee() -> void:
	_cd = float(data["cooldown"])
	player.take_damage(float(data["dmg"]), (player.global_position - global_position).normalized())
	var t := create_tween()
	t.tween_property(_sprite, "scale", _sprite.scale * 1.25, 0.06)
	t.tween_property(_sprite, "scale", _sprite.scale, 0.1)

func _spawn_bullet(pos: Vector2, dir: Vector2, spd: float, dmg: float, dist: float, col: Color) -> void:
	var b = BulletScript.new()
	b.direction = dir
	b.speed = spd
	b.damage = dmg
	b.max_distance = dist
	b.shooter_group = "enemy"
	b.target_group = "player"
	b.color = col
	b.round_shot = true
	get_tree().current_scene.add_child(b)
	b.global_position = pos

# --------------------------------------------------------------- Dano

func hit_test(p: Vector2) -> bool:
	if state == S.DEAD:
		return false
	var sc := float(data["scale"])
	return absf(p.x - global_position.x) <= 6.0 * sc and p.y >= global_position.y - _h and p.y <= global_position.y + 3.0

func take_damage(amount: float, dir: Vector2 = Vector2.ZERO) -> void:
	if state == S.DEAD:
		return
	if kind == "boss":
		if not active:
			return
		if _resting or _stun > 0.0:
			amount *= 1.3
	hp -= amount
	var boss_hit := kind == "boss"
	Audio.sfx("boss_hit" if boss_hit else "hit", -3.0, 1.0, 0.1)
	Fx.flash(_sprite, Color(1.8, 1.8, 1.8), 0.1, _tint)
	Fx.burst(get_parent(), global_position + Vector2(0, -_h * 0.5), Color(0.7, 0.08, 0.05), 5 if not boss_hit else 8, 55.0, 0.35, 1.5, 80.0, 90.0, -dir)
	if not boss_hit:
		_kb = dir.normalized() * 70.0
		_kb_t = 0.09
		if state == S.PATROL:
			_set_alert(true)
			_alert_t = 0.1
		elif state == S.ALERT:
			_alert_t = minf(_alert_t, 0.1)
	hp_changed.emit(maxf(hp, 0.0), max_hp)
	if hp <= 0.0:
		_die()
		return
	if boss_hit:
		if phase == 1 and hp <= max_hp * 0.5:
			_enter_phase2()
		if not _low_warned and hp <= max_hp * 0.2:
			_low_warned = true
			_speed_mult = 1.25
			Audio.sfx("boss_roar", -2.0, 1.2)
			get_tree().call_group("hud", "show_message", "O Coronel está ferido! Acabe com ele!", 2.5)

func _die() -> void:
	state = S.DEAD
	_gen += 1
	remove_from_group("enemy")
	remove_from_group("enemy_ai")
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	Game.kills += 1
	died.emit(self)
	var parent := get_parent()
	var center := global_position + Vector2(0, -_h * 0.5)
	if kind == "boss":
		for s in summons:
			if is_instance_valid(s) and s.state != S.DEAD:
				s.take_damage(99.0, Vector2.ZERO)
		_sprite.modulate = _tint
		var t := create_tween()
		t.tween_property(_sprite, "rotation", PI / 2.0, 0.6)
		queue_redraw()
		return
	Audio.sfx("enemy_die", -2.0, 1.0, 0.1)
	Fx.burst(parent, center, Color(0.7, 0.08, 0.05), 10, 70.0, 0.5, 1.6, 120.0)
	Fx.burst(parent, global_position, Color(0.85, 0.7, 0.45), 8, 35.0, 0.6, 2.0, 0.0, 180.0)
	if randf() < float(data["drop"]):
		var pk := PickupScript.new()
		pk.kind = "heal" if randf() < 0.4 else "ammo"
		parent.add_child(pk)
		pk.global_position = global_position + Vector2(randf_range(-4, 4), 2)
	var side := -1.0 if randf() < 0.5 else 1.0
	var tw := create_tween()
	tw.tween_property(_sprite, "rotation", side * PI / 2.0, 0.22)
	tw.tween_property(_sprite, "modulate", Color(_tint.r * 0.6, _tint.g * 0.6, _tint.b * 0.6, 1.0), 0.2)
	tw.tween_interval(4.0)
	tw.tween_property(_sprite, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
	queue_redraw()

# ------------------------------------------------------------- Visual

func _animate(moving: bool) -> void:
	var f := 10.0 if moving else 2.0
	_sprite.position.y = -absf(sin(_anim_t * f)) * (1.6 if moving else 0.4)
	_sprite.rotation = sin(_anim_t * f) * 0.05 if moving else 0.0

func _draw() -> void:
	var sc := float(data["scale"]) if data.size() > 0 else 1.0
	if state != S.DEAD:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 7.0 * sc, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state == S.DEAD or kind == "boss":
		return
	if hp < max_hp:
		var w := 14.0 * sc
		draw_rect(Rect2(-w * 0.5, -_h - 5.0, w, 2.0), Color(0.15, 0.0, 0.0))
		draw_rect(Rect2(-w * 0.5, -_h - 5.0, w * clampf(hp / max_hp, 0.0, 1.0), 2.0), Color(0.85, 0.15, 0.1))
	if state == S.ALERT:
		draw_rect(Rect2(-1, -_h - 12.0, 2, 5), Color(1.0, 0.2, 0.1))
		draw_rect(Rect2(-1, -_h - 5.0, 2, 2), Color(1.0, 0.2, 0.1))

# =========================================================== CHEFE (boss)

func is_boss() -> bool:
	return kind == "boss"

func is_aggro() -> bool:
	return state == S.ALERT or state == S.CHASE

func activate() -> void:
	if active or state == S.DEAD:
		return
	active = true
	state = S.CHASE
	hp_changed.emit(hp, max_hp)
	_boss_loop()

func reset_boss() -> void:
	_gen += 1
	active = false
	state = S.PATROL
	hp = max_hp
	phase = 1
	_speed_mult = 1.0
	_low_warned = false
	_dashing = false
	_resting = false
	_stun = 0.0
	_tint = Color(1.0, 0.78, 0.78)
	_sprite.modulate = _tint
	global_position = home
	for s in summons:
		if is_instance_valid(s):
			s.queue_free()
	summons.clear()
	hp_changed.emit(hp, max_hp)

func register_summon(e: Node) -> void:
	summons.append(e)

func _enter_phase2() -> void:
	phase = 2
	_speed_mult = 1.1
	_tint = Color(1.0, 0.55, 0.5)
	_sprite.modulate = _tint
	Audio.sfx("boss_roar", 0.0, 0.9)
	var cam = get_tree().get_first_node_in_group("player")
	if cam != null:
		cam.shake(4.0, 0.4)
	get_tree().call_group("hud", "flash", Color(1.0, 0.2, 0.1), 0.35)
	get_tree().call_group("hud", "show_message", "O Coronel se enfurece!", 2.5)
	phase_changed.emit(2)
	for i in 2:
		var pk := PickupScript.new()
		pk.kind = "heal"
		get_parent().add_child(pk)
		pk.global_position = arena.get_center() + Vector2(-40 + 80 * i, 10)
	summon_requested.emit("rapido", Vector2(arena.position.x + 8.0, arena.position.y + 10.0))
	summon_requested.emit("rapido", Vector2(arena.end.x - 8.0, arena.position.y + 10.0))

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec / _speed_mult).timeout

func _alive(gen: int) -> bool:
	return gen == _gen and state != S.DEAD and active and player != null and is_instance_valid(player) and not player.is_dead()

func _boss_loop() -> void:
	var gen := _gen
	await _sleep(0.8)
	while gen == _gen and state != S.DEAD and active:
		await _sleep(0.25)
		if not _alive(gen):
			await _sleep(0.5)
			continue
		var seq: Array = ["burst", "fan", "dash", "rest"] if phase == 1 else ["fan", "ring", "burst", "dash", "rest"]
		for p in seq:
			if not _alive(gen):
				break
			match p:
				"burst": await _pat_burst(gen)
				"fan": await _pat_fan(gen)
				"ring": await _pat_ring(gen)
				"dash": await _pat_dash(gen)
				"rest": await _pat_rest(gen)

func _telegraph(color: Color, dur: float, sound: String) -> void:
	Audio.sfx(sound)
	_sprite.modulate = color
	await _sleep(dur)
	if state != S.DEAD:
		_sprite.modulate = _tint

func _boss_aim() -> Vector2:
	return (player.sprite.global_position - _muzzle()).normalized()

func _boss_shot(angle: float, spd: float, col: Color = Color(1.0, 0.35, 0.15)) -> void:
	_spawn_bullet(_muzzle() + Vector2.from_angle(angle) * 10.0, Vector2.from_angle(angle), spd, 1.0, 420.0, col)

func _pat_burst(gen: int) -> void:
	await _telegraph(Color(1.7, 1.5, 0.6), 0.45, "boss_tele")
	var n := 3 if phase == 1 else 5
	for i in n:
		if not _alive(gen):
			return
		_boss_shot(_boss_aim().angle() + randf_range(-0.05, 0.05), 200.0)
		Audio.sfx("shot_enemy", 0.0, 0.8)
		await _sleep(0.27)
	await _sleep(0.3)

func _pat_fan(gen: int) -> void:
	await _telegraph(Color(1.8, 1.0, 0.5), 0.6, "boss_tele")
	var volleys := 1 if phase == 1 else 2
	var count := 7 if phase == 1 else 9
	var arc := 1.25 if phase == 1 else 1.6
	var base := 0.0
	for v in volleys:
		if not _alive(gen):
			return
		if v == 0:
			base = _boss_aim().angle()
		var shift := 0.0 if v == 0 else arc / float(count - 1) * 0.5
		for i in count:
			_boss_shot(base + lerpf(-arc * 0.5, arc * 0.5, float(i) / float(count - 1)) + shift, 140.0)
		Audio.sfx("shot_espingarda", -4.0, 0.9)
		get_tree().call_group("player", "shake", 1.5, 0.1)
		await _sleep(0.55)
	await _sleep(0.2)

func _pat_ring(gen: int) -> void:
	await _telegraph(Color(1.4, 0.7, 1.6), 0.55, "boss_tele")
	var n := 14
	for r in 2:
		if not _alive(gen):
			return
		var off := float(r) * (TAU / float(n) * 0.5)
		for i in n:
			_boss_shot(off + TAU * float(i) / float(n), 105.0, Color(0.9, 0.3, 0.9))
		Audio.sfx("shot_revolver", -3.0, 0.8)
		await _sleep(0.75)

func _pat_dash(gen: int) -> void:
	await _telegraph(Color(2.0, 0.45, 0.45), 0.75, "boss_charge")
	if not _alive(gen):
		return
	_dash_dir = (player.global_position - global_position).normalized()
	_dashing = true
	_dash_t = 0.6
	_dash_hit = false
	while _dashing and _alive(gen):
		await get_tree().process_frame
	_dashing = false

func _pat_rest(gen: int) -> void:
	_resting = true
	_sprite.modulate = Color(0.75, 0.8, 1.2)
	await _sleep(1.7)
	_resting = false
	if state != S.DEAD:
		_sprite.modulate = _tint

func _boss_physics(delta: float) -> void:
	if not active:
		velocity = Vector2.ZERO
		_animate(false)
		queue_redraw()
		return
	var dir := Vector2.ZERO
	var spd := 0.0
	if _stun > 0.0:
		_stun -= delta
	if _dashing:
		_dash_t -= delta
		velocity = _dash_dir * 235.0 * _speed_mult
		move_and_slide()
		if not _dash_hit and player != null and not player.is_dead() and global_position.distance_to(player.global_position) < 17.0:
			_dash_hit = true
			player.take_damage(2.0, _dash_dir)
		if get_slide_collision_count() > 0 and _dash_t < 0.5:
			_dashing = false
			_stun = 1.5
			Audio.sfx("gate", -2.0, 1.2)
			get_tree().call_group("player", "shake", 3.5, 0.25)
			Fx.burst(get_parent(), global_position, Color(0.85, 0.7, 0.45), 12, 60.0, 0.6, 2.0)
		elif _dash_t <= 0.0:
			_dashing = false
		_clamp_arena()
		_animate(true)
		queue_redraw()
		return
	if player != null and not player.is_dead():
		_sprite.flip_h = player.global_position.x < global_position.x
		var to: Vector2 = player.global_position - global_position
		if _resting or _stun > 0.0:
			dir = Vector2.ZERO
		elif to.length() > 110.0:
			dir = to.normalized()
			spd = 30.0
		elif to.length() < 55.0:
			dir = -to.normalized()
			spd = 30.0
	velocity = dir * spd * _speed_mult
	move_and_slide()
	_clamp_arena()
	_animate(velocity.length() > 5.0)
	queue_redraw()

func _clamp_arena() -> void:
	if arena.size == Vector2.ZERO:
		return
	global_position.x = clampf(global_position.x, arena.position.x + 10.0, arena.end.x - 10.0)
	global_position.y = clampf(global_position.y, arena.position.y + 14.0, arena.end.y - 4.0)
