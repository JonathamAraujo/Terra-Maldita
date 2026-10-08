extends Node2D
## Item solto no chão (drop de inimigos). kind: "heal" (+1 vida) ou "ammo" (pacote de munição).

var kind := "heal"
var amount := 1
var _t := 0.0
var _life := 30.0

func _ready() -> void:
	add_to_group("pickup")
	z_index = 3

func _process(delta: float) -> void:
	_t += delta
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	queue_redraw()
	var p = get_tree().get_first_node_in_group("player")
	if p == null or p.is_dead():
		return
	if global_position.distance_to(p.global_position) > 14.0:
		return
	if kind == "heal":
		if p.health >= p.max_health:
			return
		p.heal(amount)
		get_tree().call_group("hud", "show_message", "+%d vida" % amount, 1.2)
	else:
		if not p.add_ammo_packs(1):
			return
		get_tree().call_group("hud", "show_message", "Munição!", 1.2)
	Audio.sfx("pickup")
	queue_free()

func _draw() -> void:
	if _life < 5.0 and int(_t * 8.0) % 2 == 0:
		return # pisca antes de sumir
	var bob := sin(_t * 5.0) * 1.5
	draw_circle(Vector2(0, 1), 4.0, Color(0, 0, 0, 0.25))
	if kind == "heal":
		var c := Color(0.9, 0.12, 0.15)
		draw_rect(Rect2(-3, -9 + bob, 2, 2), c)
		draw_rect(Rect2(1, -9 + bob, 2, 2), c)
		draw_rect(Rect2(-4, -8 + bob, 8, 3), c)
		draw_rect(Rect2(-3, -5 + bob, 6, 2), c)
		draw_rect(Rect2(-1, -3 + bob, 2, 1), c)
	else:
		draw_rect(Rect2(-4, -8 + bob, 8, 6), Color(0.75, 0.55, 0.2))
		draw_rect(Rect2(-4, -8 + bob, 8, 6), Color(0.15, 0.08, 0.03), false, 1.0)
		draw_rect(Rect2(-2, -6 + bob, 4, 2), Color(1.0, 0.85, 0.4))
