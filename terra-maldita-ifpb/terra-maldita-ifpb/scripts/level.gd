extends Node2D
## "World": constrói o nível (props, NPCs, baús, inimigos, boss, portão) a partir de level_data.gd.
## Todas as coordenadas de level_data.gd são locais a este nó (que fica alinhado ao mapa teste.tscn).
## Este nó usa y-sort: jogador, inimigos e objetos se ordenam pela posição Y (profundidade).

const LevelData = preload("res://scripts/level_data.gd")
const Catalog = preload("res://scripts/catalog.gd")
const ChestScript = preload("res://scripts/chest.gd")
const NpcScript = preload("res://scripts/npc.gd")
const WellScript = preload("res://scripts/well.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const DummyScript = preload("res://scripts/target_dummy.gd")

var boss: Node = null
var gate: StaticBody2D
var gate_closed := false
var secrets_total := 0

func build() -> void:
	y_sort_enabled = true
	_build_ground_detail()
	_build_mood()
	_build_props()
	_build_npcs()
	_build_chests()
	_build_enemies()
	_build_boss()
	_build_gate()
	for d in LevelData.DUMMIES:
		var dm := DummyScript.new()
		dm.position = d
		add_child(dm)
	var well := WellScript.new()
	well.position = LevelData.WELL_POS
	add_child(well)

# ------------------------------------------------- Visual do terreno

## Textura de detalhes sobre o chão (grãos, pedrinhas, tufos secos, manchas) para o deserto não ficar chapado.
func _build_ground_detail() -> void:
	var ox := -620
	var oy := -535
	var w := 1670
	var h := 1180
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 140: # manchas de terra mais escura/clara
		var cx := rng.randi_range(0, w - 1)
		var cy := rng.randi_range(0, h - 1)
		var rw := rng.randi_range(5, 16)
		var rh := rng.randi_range(2, 6)
		var dark := rng.randf() < 0.6
		var col := Color(0.55, 0.30, 0.12, 0.10) if dark else Color(1.0, 0.85, 0.5, 0.10)
		for yy in range(-rh, rh + 1):
			for xx in range(-rw, rw + 1):
				if float(xx * xx) / float(rw * rw) + float(yy * yy) / float(rh * rh) <= 1.0:
					var px := cx + xx
					var py := cy + yy
					if px >= 0 and py >= 0 and px < w and py < h:
						img.set_pixel(px, py, col)
	for i in 16000: # grãos
		var px := rng.randi_range(0, w - 1)
		var py := rng.randi_range(0, h - 1)
		var r := rng.randf()
		var col2 := Color(0.62, 0.36, 0.16, 0.45) if r < 0.5 else (Color(1.0, 0.88, 0.55, 0.40) if r < 0.85 else Color(0.45, 0.25, 0.12, 0.5))
		img.set_pixel(px, py, col2)
	for i in 900: # tufos de capim seco
		var px := rng.randi_range(2, w - 3)
		var py := rng.randi_range(4, h - 2)
		var c3 := Color(0.52, 0.48, 0.18, 0.9) if rng.randf() < 0.6 else Color(0.62, 0.52, 0.2, 0.9)
		img.set_pixel(px, py, c3)
		img.set_pixel(px, py - 1, c3)
		img.set_pixel(px - 1, py - 2, c3)
		img.set_pixel(px + 1, py - 3, c3)
	for i in 500: # pedrinhas
		var px := rng.randi_range(1, w - 3)
		var py := rng.randi_range(1, h - 3)
		img.set_pixel(px, py, Color(0.70, 0.55, 0.42, 0.9))
		img.set_pixel(px + 1, py, Color(0.52, 0.38, 0.28, 0.9))
		img.set_pixel(px, py + 1, Color(0.40, 0.28, 0.2, 0.7))
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(ox, -9000) # y-sort: fica atrás de tudo
	spr.offset = Vector2(0, 9000 + oy)
	add_child(spr)

## Tom quente de fim de tarde sobre todo o mundo.
func _build_mood() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(1.0, 0.93, 0.84)
	get_parent().add_child.call_deferred(cm)

func _make_shadow_texture() -> ImageTexture:
	var img := Image.create(32, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 32:
			var dx := (x - 15.5) / 16.0
			var dy := (y - 5.5) / 6.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0.15, 0.06, 0.02, 0.32))
	return ImageTexture.create_from_image(img)

var _shadow_tex: ImageTexture

func _add_shadow(parent: Node2D, width: float) -> void:
	if _shadow_tex == null:
		_shadow_tex = _make_shadow_texture()
	var sh := Sprite2D.new()
	sh.texture = _shadow_tex
	sh.show_behind_parent = true
	sh.scale = Vector2(maxf(width / 32.0, 0.3), maxf(width / 32.0, 0.3))
	sh.position = Vector2(0, -1)
	parent.add_child(sh)

# ------------------------------------------------------------------ Props

func _build_props() -> void:
	for p in LevelData.PROPS:
		var sname := String(p[0])
		var pos := Vector2(float(p[1]), float(p[2]))
		var sc := float(p[3])
		var solid := bool(p[4])
		var spr := Catalog.make(sname, sc / Catalog.base_scale(sname))
		var nat_size: Vector2 = Catalog.SPR[sname][1].size
		var sw: float = nat_size.x * sc * 0.9
		var casts_shadow: bool = not sname.begins_with("scn") and sname != "camp3"
		if solid:
			var body := StaticBody2D.new()
			body.position = pos
			var cs := CollisionShape2D.new()
			var r := RectangleShape2D.new()
			var nat: Vector2 = Catalog.SPR[sname][1].size
			r.size = Vector2(maxf(nat.x * sc * 0.8, 6.0), 6.0)
			cs.shape = r
			cs.position = Vector2(0, -3)
			body.add_child(cs)
			body.add_child(spr)
			if casts_shadow:
				_add_shadow(body, sw)
			add_child(body)
		else:
			spr.position = pos
			add_child(spr)
			if casts_shadow:
				_add_shadow(spr, sw / maxf(spr.scale.x, 0.01))
		if sname == "camp3":
			_make_fire(spr, pos)

func _make_fire(spr: Sprite2D, pos: Vector2) -> void:
	var t := spr.create_tween().set_loops()
	t.tween_property(spr, "scale", spr.scale * Vector2(0.92, 1.1), 0.18)
	t.tween_property(spr, "scale", spr.scale * Vector2(1.05, 0.95), 0.22)
	var em := CPUParticles2D.new()
	em.position = pos + Vector2(0, -8)
	em.amount = 5
	em.lifetime = 0.9
	em.direction = Vector2.UP
	em.spread = 25.0
	em.initial_velocity_min = 8.0
	em.initial_velocity_max = 18.0
	em.gravity = Vector2.ZERO
	em.scale_amount_min = 0.8
	em.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.2, 1.0))
	g.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	em.color_ramp = g
	em.z_index = 6
	add_child(em)
	em.emitting = true
	var snd := AudioStreamPlayer2D.new()
	var st: AudioStream = Audio.crackle_stream()
	if st != null:
		snd.stream = st
		snd.position = pos
		snd.max_distance = 170.0
		snd.volume_db = -7.0
		add_child(snd)
		snd.play()

# ------------------------------------------------------------- NPCs/baús

func _build_npcs() -> void:
	for n in LevelData.NPCS:
		var npc := NpcScript.new()
		npc.npc_id = String(n[0])
		npc.sprite_name = String(n[1])
		npc.secret = String(n[0]) == "cruz"
		npc.position = Vector2(float(n[2]), float(n[3]))
		if npc.secret:
			secrets_total += 1
		add_child(npc)

func _build_chests() -> void:
	for c in LevelData.CHESTS:
		var ch := ChestScript.new()
		ch.loot_type = String(c[0])
		if String(c[1]) != "":
			ch.weapon_id = String(c[1])
		ch.amount = int(c[2])
		ch.secret = bool(c[5])
		ch.position = Vector2(float(c[3]), float(c[4]))
		if ch.secret:
			secrets_total += 1
		add_child(ch)

# --------------------------------------------------------------- Inimigos

func _build_enemies() -> void:
	for e in LevelData.ENEMIES:
		var en := EnemyScript.new()
		en.kind = String(e[0])
		en.position = Vector2(float(e[1]), float(e[2]))
		var a := int(e[3])
		var b := int(e[4])
		if a != b:
			var pts: Array[Vector2] = [to_global(LevelData.PATH[a]), to_global(LevelData.PATH[b])]
			en.patrol_points = pts
		add_child(en)

func _build_boss() -> void:
	boss = EnemyScript.new()
	boss.kind = "boss"
	boss.position = LevelData.BOSS_POS
	add_child(boss)
	boss.arena = Rect2(to_global(LevelData.ARENA_RECT.position), LevelData.ARENA_RECT.size)
	boss.home = to_global(LevelData.BOSS_POS)
	boss.summon_requested.connect(_on_summon)

func _on_summon(kind: String, gpos: Vector2) -> void:
	var en := EnemyScript.new()
	en.kind = kind
	add_child(en)
	en.global_position = gpos
	en.state = 2 # CHASE
	boss.register_summon(en)
	Audio.sfx("pickup", -4.0, 0.6)

# ----------------------------------------------------------------- Portão

func _build_gate() -> void:
	gate = StaticBody2D.new()
	gate.position = LevelData.GATE_POS
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var r := RectangleShape2D.new()
	r.size = Vector2(LevelData.GATE_HALF_WIDTH * 2.0, 7.0)
	cs.shape = r
	cs.disabled = true
	gate.add_child(cs)
	var n := int(LevelData.GATE_HALF_WIDTH * 2.0 / 14.0) + 1
	for i in n:
		var spr := Catalog.make("scn0")
		spr.position = Vector2(-LevelData.GATE_HALF_WIDTH + 7.0 + i * 14.0, 4.0)
		spr.visible = false
		spr.add_to_group("gate_piece")
		gate.add_child(spr)
	add_child(gate)

func close_gate() -> void:
	if gate_closed:
		return
	gate_closed = true
	gate.get_node("Shape").set_deferred("disabled", false)
	var i := 0
	for spr in gate.get_children():
		if spr is Sprite2D:
			spr.visible = true
			var y: float = spr.position.y
			spr.position.y = y - 30.0
			var t := spr.create_tween()
			t.tween_property(spr, "position:y", y, 0.25).set_delay(float(i) * 0.05)
			i += 1

func open_gate() -> void:
	gate_closed = false
	gate.get_node("Shape").set_deferred("disabled", true)
	for spr in gate.get_children():
		if spr is Sprite2D:
			spr.visible = false

# ------------------------------------------------------------------ Zonas

func nearest_path_index(gpos: Vector2) -> int:
	var lp := to_local(gpos)
	var best := 0
	var bd := INF
	for i in LevelData.PATH.size():
		var d := lp.distance_squared_to(LevelData.PATH[i])
		if d < bd:
			bd = d
			best = i
	return best

func zone_at(idx: int) -> Array:
	for z in LevelData.ZONES:
		if idx >= int(z[0]) and idx <= int(z[1]):
			return z
	return LevelData.ZONES[LevelData.ZONES.size() - 1]
