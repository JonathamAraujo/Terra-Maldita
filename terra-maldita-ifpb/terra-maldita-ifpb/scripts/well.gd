extends StaticBody2D
## Poço da vila: beber água cura toda a vida (uma vez).

const Catalog = preload("res://scripts/catalog.gd")

var interaction_radius := 26.0
var used := false
var _focused := false

func _ready() -> void:
	add_to_group("interactable")
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(12, 6)
	cs.shape = r
	cs.position = Vector2(0, -3)
	add_child(cs)
	add_child(Catalog.make("obj20", 1.2))

func can_interact() -> bool:
	return not used and not Game.dialog_active

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var f: bool = player != null and player.get("focus") == self
	if f != _focused:
		_focused = f
		queue_redraw()

func _draw() -> void:
	if _focused and not used:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-40, -22), "[E] Beber água", HORIZONTAL_ALIGNMENT_CENTER, 80, 8, 3, Color(0.1, 0.05, 0.02))
		draw_string(font, Vector2(-40, -22), "[E] Beber água", HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color(1.0, 0.95, 0.7))

func interact(player: Node) -> void:
	if used:
		return
	used = true
	player.heal(player.max_health)
	Audio.sfx("heal")
	get_tree().call_group("hud", "show_message", "Água fresca! Vida restaurada.", 2.5)
	get_tree().call_group("hud", "flash", Color(0.5, 0.8, 1.0), 0.4)
	queue_redraw()
