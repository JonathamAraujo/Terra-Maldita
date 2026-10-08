extends CharacterBody2D
## Jogador (caçador de recompensas).
## Controles: WASD mover | Shift correr | Mouse mirar | Botão esquerdo atirar | R recarregar
##            E interagir (baús) | 1-4 ou roda do mouse trocar de arma

signal health_changed(current: int, maximum: int)
signal ammo_changed(in_mag: int, mag_size: int, reserve: int, weapon_name: String, reloading: bool)
signal inventory_changed(owned_ids: Array, current_id: String)
signal died

const Weapons = preload("res://scripts/weapons.gd")
const BulletScript = preload("res://scripts/bullet.gd")

@export var walk_speed := 80.0
@export var run_speed := 140.0
@export var max_health := 5
@export var invulnerable_time := 0.8

@onready var sprite: Sprite2D = $CangaceiroSpritesheet
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var camera: Camera2D = $Camera2D

var facing := "down"

var health := 5
var weapon_id := "pistola"
var owned: Array[String] = ["pistola"]
var _ammo := {} # id -> {"mag": int, "reserve": int}  (reserve -1 = infinita)

var aim_dir := Vector2.DOWN
var focus: Node = null # interagível mais próximo (baú, NPC...)

var _cooldown := 0.0
var _reload_left := 0.0
var _reloading := false
var _aim_hold := 0.0
var _invuln := 0.0
var _dead := false
var _dry_msg_cd := 0.0
var _step_t := 0.0

func _ready() -> void:
	add_to_group("player")
	_ensure_key("run", KEY_SHIFT)
	_ensure_key("reload", KEY_R)
	_ensure_key("interact", KEY_E)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("shoot", mb)
	health = max_health
	_init_weapon_state("pistola")
	camera.limit_left = -651
	camera.limit_top = -512
	camera.limit_right = 981
	camera.limit_bottom = 640

func _ensure_key(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _init_weapon_state(id: String) -> void:
	var w := Weapons.get_data(id)
	_ammo[id] = {"mag": int(w["mag"]), "reserve": int(w["start_reserve"])}

func _st() -> Dictionary:
	return _ammo[weapon_id]

func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector2.ZERO
		return
	if Game.dialog_active or Game.input_locked:
		velocity = Vector2.ZERO
		_play("idle")
		_aim_dir_update()
		return

	# --- Movimento (lógica original preservada) ---
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run") and dir != Vector2.ZERO
	velocity = dir * (run_speed if running else walk_speed)
	move_and_slide()

	# --- Passos ---
	if dir != Vector2.ZERO:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.26 if running else 0.38
			Audio.sfx("step", -14.0, 1.0, 0.15)

	# --- Mira ---
	_aim_dir_update()

	# Ao atirar, o personagem olha para onde está mirando por um instante.
	if _aim_hold > 0.0:
		_aim_hold -= delta
		_face_towards(aim_dir)
	elif dir != Vector2.ZERO:
		_face_towards(dir)

	var state := "idle"
	if dir != Vector2.ZERO:
		state = "run" if running else "walk"
	_play(state)

	# --- Timers ---
	_cooldown = maxf(_cooldown - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_dry_msg_cd = maxf(_dry_msg_cd - delta, 0.0)
	_update_reload(delta)

	# --- Interação ---
	_update_focus()
	if Input.is_action_just_pressed("interact") and focus != null and Game.dialog_cooldown <= 0.0:
		focus.interact(self)

	# --- Armas ---
	if Input.is_action_just_pressed("reload"):
		start_reload()

	var w := Weapons.get_data(weapon_id)
	var wants_shot := Input.is_action_pressed("shoot") if w["auto"] else Input.is_action_just_pressed("shoot")
	if wants_shot:
		try_shoot()

func _unhandled_input(event: InputEvent) -> void:
	if _dead or Game.dialog_active or Game.input_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.physical_keycode:
			KEY_1: slot = 0
			KEY_2: slot = 1
			KEY_3: slot = 2
			KEY_4: slot = 3
		if slot >= 0 and slot < Weapons.ORDER.size():
			equip(Weapons.ORDER[slot])
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)

func _update_focus() -> void:
	focus = null
	var best := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.has_method("can_interact") and n.can_interact():
			var d := global_position.distance_to(n.global_position)
			if d <= n.interaction_radius and d < best:
				best = d
				focus = n

func _aim_dir_update() -> void:
	var aim_vec := get_global_mouse_position() - sprite.global_position
	if aim_vec.length() > 1.0:
		aim_dir = aim_vec.normalized()

func _face_towards(v: Vector2) -> void:
	if absf(v.x) > absf(v.y):
		facing = "right"
		sprite.flip_h = v.x < 0
	else:
		facing = "up" if v.y < 0 else "down"

func _play(state: String) -> void:
	var anim_name := state + "_" + facing
	if not anim.has_animation(anim_name):
		anim_name = "idle_down" # fallback
	if anim.current_animation != anim_name:
		anim.play(anim_name)

# ---------------------------------------------------------------- Tiro

func try_shoot() -> void:
	if _dead or _reloading or _cooldown > 0.0:
		return
	var st := _st()
	if st["mag"] <= 0:
		if st["reserve"] == 0:
			_out_of_ammo()
		else:
			start_reload()
		return

	var w := Weapons.get_data(weapon_id)
	st["mag"] -= 1
	_cooldown = w["fire_rate"]
	Audio.sfx("shot_" + weapon_id, 0.0, 1.0, 0.05)
	_aim_hold = 0.35
	_face_towards(aim_dir)

	var origin := sprite.global_position + aim_dir * 8.0
	for i in int(w["pellets"]):
		var angle := aim_dir.angle() + randf_range(-w["spread"], w["spread"])
		_spawn_bullet(origin, Vector2.from_angle(angle), w)
	_spawn_flash(origin, aim_dir)
	shake(w["shake"], 0.1)
	_emit_ammo()
	if st["mag"] <= 0 and st["reserve"] != 0:
		start_reload() # recarrega automático ao esvaziar o pente

func _out_of_ammo() -> void:
	if weapon_id != "pistola":
		equip("pistola")
		get_tree().call_group("hud", "show_message", "Sem munição! Voltando para a pistola.", 2.0)
	elif _dry_msg_cd <= 0.0:
		_dry_msg_cd = 1.0
		Audio.sfx("click")
		get_tree().call_group("hud", "show_message", "*click* Sem munição!", 1.0)

func _spawn_bullet(pos: Vector2, dir: Vector2, w: Dictionary) -> void:
	var b = BulletScript.new()
	b.direction = dir
	b.speed = w["bullet_speed"]
	b.damage = w["damage"]
	b.max_distance = w["max_range"]
	b.shooter_group = "player"
	get_tree().current_scene.add_child(b)
	b.global_position = pos

func _spawn_flash(pos: Vector2, dir: Vector2) -> void:
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([Vector2(0, -3), Vector2(9, 0), Vector2(0, 3)])
	flash.color = Color(1.0, 0.85, 0.35)
	flash.z_index = 6
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	flash.rotation = dir.angle()
	get_tree().create_timer(0.05).timeout.connect(flash.queue_free)

# ------------------------------------------------------------- Recarga

func start_reload() -> void:
	if _dead or _reloading:
		return
	var w := Weapons.get_data(weapon_id)
	var st := _st()
	if st["mag"] >= int(w["mag"]) or st["reserve"] == 0:
		return
	_reloading = true
	_reload_left = w["reload"]
	Audio.sfx("reload")
	_emit_ammo()

func _update_reload(delta: float) -> void:
	if not _reloading:
		return
	_reload_left -= delta
	if _reload_left > 0.0:
		return
	var w := Weapons.get_data(weapon_id)
	var st := _st()
	var needed := int(w["mag"]) - int(st["mag"])
	if st["reserve"] < 0:
		st["mag"] += needed
	else:
		var taken := mini(needed, int(st["reserve"]))
		st["mag"] += taken
		st["reserve"] -= taken
	_reloading = false
	_emit_ammo()

func _emit_ammo() -> void:
	var w := Weapons.get_data(weapon_id)
	var st := _st()
	ammo_changed.emit(int(st["mag"]), int(w["mag"]), int(st["reserve"]), w["name"], _reloading)

# ------------------------------------------------------ Inventário de armas

func equip(id: String) -> void:
	if not owned.has(id) or id == weapon_id:
		return
	weapon_id = id
	_reloading = false # trocar de arma cancela a recarga
	_cooldown = 0.15
	Audio.sfx("click", -6.0, 1.3)
	_emit_ammo()
	inventory_changed.emit(owned, weapon_id)

func _cycle_weapon(step: int) -> void:
	# percorre em ordem de slots (ORDER), pulando armas que não possui
	var slot := Weapons.ORDER.find(weapon_id)
	for k in Weapons.ORDER.size():
		slot = posmod(slot + step, Weapons.ORDER.size())
		if owned.has(Weapons.ORDER[slot]):
			equip(Weapons.ORDER[slot])
			return

## Retorna true se a arma é nova (e já a equipa); se já tinha, vira munição extra.
func give_weapon(id: String) -> bool:
	var w := Weapons.get_data(id)
	if owned.has(id):
		var st: Dictionary = _ammo[id]
		if int(st["reserve"]) >= 0:
			st["reserve"] = mini(int(st["reserve"]) + int(w["ammo_pack"]), int(w["max_reserve"]))
		_emit_ammo()
		return false
	owned.append(id)
	_init_weapon_state(id)
	equip(id)
	return true

## Dá pacotes de munição para todas as armas com reserva finita. Retorna false se não há nenhuma.
func add_ammo_packs(packs: int = 1) -> bool:
	var any := false
	for id in owned:
		var st: Dictionary = _ammo[id]
		if int(st["reserve"]) < 0:
			continue
		var w := Weapons.get_data(id)
		st["reserve"] = mini(int(st["reserve"]) + int(w["ammo_pack"]) * packs, int(w["max_reserve"]))
		any = true
	_emit_ammo()
	return any

# ---------------------------------------------------------- Vida / dano

func take_damage(amount: float, _from_dir: Vector2 = Vector2.ZERO) -> void:
	if _dead or _invuln > 0.0:
		return
	health = maxi(health - int(ceil(amount)), 0)
	_invuln = invulnerable_time
	health_changed.emit(health, max_health)
	Audio.sfx("hurt")
	get_tree().call_group("hud", "flash", Color(0.9, 0.1, 0.1), 0.25)
	sprite.modulate = Color(1.0, 0.35, 0.35)
	var t := create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, invulnerable_time)
	shake(3.0, 0.2)
	if health <= 0:
		_die()

func heal(amount: int) -> void:
	if _dead:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)

## Usado pelos projéteis inimigos (bullet.gd) para saber se acertaram o jogador.
func hit_test(p: Vector2) -> bool:
	if _dead:
		return false
	return absf(p.x - global_position.x) <= 6.0 and p.y >= global_position.y - 30.0 and p.y <= global_position.y + 3.0

func add_max_health(n: int) -> void:
	max_health += n
	health = max_health
	health_changed.emit(health, max_health)

## Revive no checkpoint (mundo, armas e baús abertos são mantidos).
func respawn(pos: Vector2) -> void:
	_dead = false
	health = max_health
	global_position = pos
	_invuln = 2.0
	_reloading = false
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	for k in _ammo.keys():
		var st: Dictionary = _ammo[k]
		var w := Weapons.get_data(k)
		st["mag"] = int(w["mag"])
		if int(st["reserve"]) >= 0:
			st["reserve"] = maxi(int(st["reserve"]), int(w["ammo_pack"]))
	health_changed.emit(health, max_health)
	refresh_hud()

func _die() -> void:
	Audio.sfx("enemy_die", 2.0, 0.7)
	_dead = true
	velocity = Vector2.ZERO
	anim.stop()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(sprite, "rotation", PI / 2.0, 0.4)
	t.tween_property(sprite, "modulate", Color(0.4, 0.1, 0.1, 0.9), 0.4)
	died.emit()

func is_dead() -> bool:
	return _dead

# ------------------------------------------------------------------ Câmera

func shake(strength: float = 2.0, duration: float = 0.12) -> void:
	if camera == null:
		return
	var step := duration / 5.0
	var t := create_tween()
	for i in 4:
		t.tween_property(camera, "offset", Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength, step)
	t.tween_property(camera, "offset", Vector2.ZERO, step)

# ------------------------------------------------------------------- HUD

## Reenvia o estado atual (usado pela HUD ao iniciar).
func refresh_hud() -> void:
	health_changed.emit(health, max_health)
	_emit_ammo()
	inventory_changed.emit(owned, weapon_id)
