extends Area2D

const Fx = preload("res://scripts/fx.gd")
## Projétil. Criado por código (jogador, inimigos e boss).
## Personagens são atingidos por teste de proximidade (hit_test), paredes por colisão.

var direction := Vector2.RIGHT
var speed := 320.0
var damage := 1.0
var max_distance := 170.0
var shooter_group := "player"
var target_group := "enemy"
var color := Color(1.0, 0.92, 0.45)
var round_shot := false # true = bala redonda (inimigos/boss)

var _traveled := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 # paredes, props, baús (jogador também, mas é ignorado aqui)
	var shape := CircleShape2D.new()
	shape.radius = 2.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	z_index = 5

func _physics_process(delta: float) -> void:
	var prev := global_position
	var step := direction * speed * delta
	global_position += step
	_traveled += step.length()
	for pt in [prev + step * 0.5, global_position]:
		for n in get_tree().get_nodes_in_group(target_group):
			if n.has_method("hit_test") and pt.distance_squared_to(n.global_position) < 2500.0 and n.hit_test(pt):
				n.take_damage(damage, direction)
				_spark(Color(0.8, 0.1, 0.05) if target_group == "enemy" else Color(1.0, 0.5, 0.3), 5)
				queue_free()
				return
	if _traveled >= max_distance:
		queue_free()

func _draw() -> void:
	if round_shot:
		draw_circle(Vector2.ZERO, 2.2, color)
		draw_circle(Vector2.ZERO, 1.0, Color(1, 1, 0.85))
	else:
		draw_rect(Rect2(-4, -1, 6, 2), color)
		draw_rect(Rect2(2, -1, 2, 2), Color(1.0, 1.0, 0.9))

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") or body.is_in_group("enemy"):
		return # personagens: tratados por hit_test
	_spark(Color(0.95, 0.8, 0.5), 4)
	queue_free()

func _spark(c: Color, count: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	Fx.burst(parent, global_position, c, count, 45.0, 0.25, 1.4)
