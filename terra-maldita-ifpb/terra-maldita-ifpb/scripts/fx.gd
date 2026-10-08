extends RefCounted
## Efeitos visuais reutilizáveis (partículas e flashes). Uso: const Fx = preload("res://scripts/fx.gd")

## Explosão de partículas de um tiro só.
static func burst(parent: Node, pos: Vector2, color: Color, count: int = 8, speed: float = 60.0, life: float = 0.4, size: float = 1.5, gravity: float = 0.0, spread: float = 180.0, dir: Vector2 = Vector2.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.amount = maxi(count, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	p.z_index = 7
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

## Pisca o sprite com uma cor e volta ao normal.
static func flash(item: CanvasItem, color: Color, duration: float = 0.12, back: Color = Color.WHITE) -> void:
	if item == null or not item.is_inside_tree():
		return
	item.modulate = color
	var t := item.create_tween()
	t.tween_property(item, "modulate", back, duration)

## Texto flutuante curto (ex.: "+1").
static func float_text(parent: Node, pos: Vector2, text: String, color: Color = Color(1, 0.9, 0.5)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", 3)
	l.z_index = 20
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.global_position = pos - Vector2(l.size.x * 0.5, 0)
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 16.0, 0.9)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	t.chain().tween_callback(l.queue_free)
