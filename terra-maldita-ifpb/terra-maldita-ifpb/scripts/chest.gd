extends StaticBody2D
## Baú interativo (grupo "interactable"). Sprite provisório: caixa de madeira de Assets/10_objetos_sertao.png.
## loot_type: "weapon" (dá weapon_id), "ammo" (pacotes de munição), "heal" (cura amount blocos)
## ou "maxhp" (relicário: +amount de vida máxima). secret = baú escondido (conta como segredo).

const Weapons = preload("res://scripts/weapons.gd")
const SHEET := "res://Assets/10_objetos_sertao.png"
const CRATE_REGION := Rect2(0, 97, 26, 31)

@export var loot_type := "weapon"
@export var weapon_id := "revolver"
@export var amount := 1
@export var interaction_radius := 22.0
@export var secret := false

var opened := false
var _sprite: Sprite2D
var _focused := false

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("chest")

	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(12, 6)
	cs.shape = r
	cs.position = Vector2(0, -3)
	add_child(cs)

	var tex := AtlasTexture.new()
	tex.atlas = load(SHEET)
	tex.region = CRATE_REGION
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(0.5, 0.5) # assets de Assets/ têm o dobro da resolução do mundo
	_sprite.position = Vector2(0, -7.75)
	add_child(_sprite)

func can_interact() -> bool:
	return not opened

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var now_focused: bool = player != null and player.get("focus") == self
	if now_focused != _focused:
		_focused = now_focused
	if not opened:
		queue_redraw() # brilho piscando + prompt

func _draw() -> void:
	if opened:
		return
	var t := Time.get_ticks_msec() / 1000.0
	# halo dourado pulsando + seta saltitante: o baú precisa ser fácil de achar
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	draw_circle(Vector2(0, -6), 13.0, Color(1.0, 0.85, 0.3, 0.12 + 0.12 * pulse))
	draw_circle(Vector2(0, -6), 9.0, Color(1.0, 0.85, 0.3, 0.12 + 0.12 * pulse))
	var bob := sin(t * 5.0) * 1.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3, -21 + bob), Vector2(3, -21 + bob), Vector2(0, -17 + bob)
	]), Color(1.0, 0.9, 0.4))
	if _focused:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-30, -27), "[E] Abrir", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, 3, Color(0.1, 0.05, 0.02))
		draw_string(font, Vector2(-30, -27), "[E] Abrir", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(1.0, 0.95, 0.7))

func interact(player: Node) -> void:
	if opened:
		return
	opened = true
	_sprite.modulate = Color(0.55, 0.45, 0.4)
	queue_redraw()
	Audio.sfx("chest_open")
	Game.chests_opened += 1
	_burst()

	match loot_type:
		"weapon":
			var w := Weapons.get_data(weapon_id)
			var is_new: bool = player.give_weapon(weapon_id)
			_popup_icon(Weapons.icon_texture(weapon_id))
			if is_new:
				Audio.sfx("weapon_get")
				_hud("ARMA NOVA!\n%s\n%s" % [w["name"], w["tip"]], 3.5)
				get_tree().call_group("hud", "flash", Color(1.0, 0.85, 0.4), 0.45)
				player.shake(3.0, 0.2)
			else:
				_hud("Munição: %s" % w["name"], 2.0)
		"ammo":
			var got: bool = player.add_ammo_packs(maxi(amount, 1))
			_hud("Munição encontrada!" if got else "Baú vazio... (só pistola)", 2.0)
		"heal":
			player.heal(maxi(amount, 1))
			Audio.sfx("heal")
			_hud("Você se sente melhor. (+%d vida)" % maxi(amount, 1), 2.0)
		"maxhp":
			player.add_max_health(maxi(amount, 1))
			Audio.sfx("weapon_get")
			get_tree().call_group("hud", "flash", Color(1.0, 0.4, 0.4), 0.45)
			_hud("RELICÁRIO! Vida máxima +%d" % maxi(amount, 1), 3.0)
	if secret:
		Game.secrets += 1
		Audio.sfx("checkpoint")
		get_tree().call_group("hud", "show_banner", "SEGREDO ENCONTRADO!", "", 2.2, false)

func _hud(text: String, duration: float) -> void:
	get_tree().call_group("hud", "show_message", text, duration)

func _popup_icon(tex: Texture2D) -> void:
	var ico := Sprite2D.new()
	ico.texture = tex
	ico.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ico.scale = Vector2(0.6, 0.6)
	ico.z_index = 8
	get_parent().add_child(ico)
	ico.global_position = global_position + Vector2(0, -20)
	var t := ico.create_tween()
	t.tween_property(ico, "position:y", ico.position.y - 22.0, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.5)
	t.tween_property(ico, "modulate:a", 0.0, 0.3)
	t.tween_callback(ico.queue_free)

func _burst() -> void:
	for i in 8:
		var p := ColorRect.new()
		p.size = Vector2(2, 2)
		p.color = Color(1.0, 0.85, 0.4)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_parent().add_child(p)
		p.global_position = global_position + Vector2(0, -8)
		var dest := p.position + Vector2.from_angle(randf() * TAU) * randf_range(8.0, 18.0)
		var t := p.create_tween()
		t.set_parallel(true)
		t.tween_property(p, "position", dest, 0.35)
		t.tween_property(p, "modulate:a", 0.0, 0.35)
		t.chain().tween_callback(p.queue_free)
