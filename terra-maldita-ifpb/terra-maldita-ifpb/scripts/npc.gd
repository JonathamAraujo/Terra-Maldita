extends StaticBody2D
## NPC interativo (grupo "interactable"). Sprite vem do catálogo (Assets/05_sertanejos_civis etc.).

const Catalog = preload("res://scripts/catalog.gd")
const Dialogs = preload("res://scripts/dialogs.gd")

@export var npc_id := "tobias"
@export var sprite_name := "civ0"
@export var interaction_radius := 26.0
@export var secret := false

var _sprite: Sprite2D
var _focused := false
var _t := randf() * 5.0
var _talked := false

func _ready() -> void:
	add_to_group("interactable")
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(8, 5)
	cs.shape = r
	cs.position = Vector2(0, -2.5)
	add_child(cs)
	_sprite = Catalog.make(sprite_name)
	add_child(_sprite)

func can_interact() -> bool:
	return not Game.dialog_active

func _process(delta: float) -> void:
	_t += delta
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		_focused = player.get("focus") == self
		# vira para o jogador quando ele está perto
		if global_position.distance_to(player.global_position) < 70.0:
			_sprite.flip_h = player.global_position.x < global_position.x
	_sprite.position.y = -absf(sin(_t * 1.6)) * 0.6
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _focused:
		var font := ThemeDB.fallback_font
		var h := 34.0
		if _sprite != null:
			h = _sprite.texture.get_height() * _sprite.scale.y + 6.0
		draw_string_outline(font, Vector2(-30, -h), "[E] Falar", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, 3, Color(0.1, 0.05, 0.02))
		draw_string(font, Vector2(-30, -h), "[E] Falar", HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(1.0, 0.95, 0.7))

func interact(_player: Node) -> void:
	var lines: Array = Dialogs.NPC.get(npc_id, ["???|..."])
	if secret and not _talked:
		Game.secrets += 1
	_talked = true
	get_tree().call_group("hud", "start_dialog", lines)
