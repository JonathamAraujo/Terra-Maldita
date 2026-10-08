extends StaticBody2D
## ALVO DE TREINO (área inicial). Nunca morre: ao zerar a vida, ele se recupera.

var max_hp := 10.0
var hp := 10.0
var _flash := 0.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("dummy")
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(12, 6)
	cs.shape = r
	cs.position = Vector2(0, -3)
	add_child(cs)

func hit_test(p: Vector2) -> bool:
	return absf(p.x - global_position.x) <= 7.0 and p.y >= global_position.y - 22.0 and p.y <= global_position.y + 3.0

func take_damage(amount: float, _dir: Vector2 = Vector2.ZERO) -> void:
	hp -= amount
	_flash = 0.1
	Audio.sfx("hit", -4.0, 1.2, 0.1)
	if hp <= 0.0:
		hp = max_hp
		Audio.sfx("pickup", -6.0)
	queue_redraw()

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()

func _draw() -> void:
	var body_color := Color(1, 1, 1) if _flash > 0.0 else Color(0.62, 0.42, 0.24)
	draw_rect(Rect2(-1, -22, 2, 22), Color(0.35, 0.22, 0.12))     # poste
	draw_rect(Rect2(-7, -20, 14, 12), body_color)                  # alvo
	draw_rect(Rect2(-7, -20, 14, 12), Color(0.1, 0.05, 0.02), false, 1.0)
	draw_circle(Vector2(0, -14), 4.0, Color(0.85, 0.15, 0.1))
	draw_circle(Vector2(0, -14), 1.8, Color(0.98, 0.9, 0.7))
	draw_rect(Rect2(-8, -27, 16, 2), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(-8, -27, 16.0 * hp / max_hp, 2), Color(0.85, 0.15, 0.1))
