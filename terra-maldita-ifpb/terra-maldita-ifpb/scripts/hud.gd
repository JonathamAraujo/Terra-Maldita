extends Control
## HUD completa desenhada por código: vida, arma, munição, slots, objetivo, boss, mensagens,
## diálogos, banners de área, fade, telas de morte/vitória/pausa e mira.
## Criada pelo main.gd dentro de um CanvasLayer.

signal dialog_finished
signal respawn_requested
signal menu_requested

const Weapons = preload("res://scripts/weapons.gd")
const Dialogs = preload("res://scripts/dialogs.gd")

const COLOR_TEXT := Color(0.98, 0.9, 0.7)
const COLOR_GOLD := Color(1.0, 0.85, 0.45)
const COLOR_OUTLINE := Color(0.12, 0.06, 0.03)
const PANEL := Color(0.16, 0.09, 0.05, 0.92)
const FONT_SIZE := 8

var health := 5
var max_health := 5
var weapon_name := ""
var ammo_in_mag := 0
var mag_size := 0
var reserve := -1
var reloading := false
var objective := ""
var message := ""
var _message_time := 0.0
var show_crosshair := true
var owned_ids: Array = ["pistola"]
var current_id := "pistola"
var secrets_total := 7

var _flash_color := Color.WHITE
var _flash_time := 0.0
var _flash_total := 1.0
var _fade_a := 1.0
var _t := 0.0

# banner
var _banner_title := ""
var _banner_sub := ""
var _banner_t := 0.0
var _banner_dur := 3.0
var _banner_big := false

# boss
var boss_bar := false
var boss_name := ""
var boss_hp := 1.0
var boss_max := 1.0

# dialogo
var _dlg_lines: Array = []
var _dlg_i := 0
var _dlg_chars := 0.0
var _dlg_blip := 0

# telas
var screen := ""   # "", "dead", "win"
var _screen_t := 0.0
var _paused := false

func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message = ""
	if _flash_time > 0.0:
		_flash_time -= delta
	if _banner_t > 0.0:
		_banner_t -= delta
	if screen != "":
		_screen_t += delta
	if Game.dialog_active and _dlg_i < _dlg_lines.size():
		var full := _dlg_text().length()
		if _dlg_chars < float(full):
			_dlg_chars += 48.0 * delta
			var shown := int(_dlg_chars)
			if shown / 3 != _dlg_blip:
				_dlg_blip = shown / 3
				if _dlg_speaker() != "":
					Audio.sfx("blip", -10.0, 1.0, 0.1)
	var cross := show_crosshair and screen == "" and not _paused and not Game.dialog_active
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if cross else Input.MOUSE_MODE_VISIBLE
	queue_redraw()

# ---------------------------------------------------------------- API

func set_health(current: int, maximum: int) -> void:
	health = current
	max_health = maximum

func set_ammo(in_mag: int, mag: int, reserve_ammo: int, wname: String, is_reloading: bool) -> void:
	ammo_in_mag = in_mag
	mag_size = mag
	reserve = reserve_ammo
	weapon_name = wname
	reloading = is_reloading

func set_inventory(ids: Array, current: String) -> void:
	owned_ids = ids
	current_id = current

func set_objective(text: String) -> void:
	objective = text

func show_message(text: String, duration: float = 3.0) -> void:
	message = text
	_message_time = duration

func flash(color: Color = Color(1, 0.9, 0.5), duration: float = 0.4) -> void:
	_flash_color = color
	_flash_time = duration
	_flash_total = duration

func show_banner(title: String, sub: String = "", duration: float = 3.0, big: bool = false) -> void:
	_banner_title = title
	_banner_sub = sub
	_banner_dur = duration
	_banner_t = duration
	_banner_big = big

func show_boss_bar(bname: String, current: float, maximum: float) -> void:
	boss_bar = true
	boss_name = bname
	boss_hp = current
	boss_max = maximum

func set_boss_hp(current: float, maximum: float) -> void:
	boss_hp = current
	boss_max = maximum

func hide_boss_bar() -> void:
	boss_bar = false

func fade_to(alpha: float, duration: float = 0.5) -> void:
	var t := create_tween()
	t.tween_property(self, "_fade_a", alpha, duration)

func show_screen(kind: String) -> void:
	screen = kind
	_screen_t = 0.0

func is_busy() -> bool:
	return Game.dialog_active or screen != "" or _paused

func start_dialog(lines: Array) -> void:
	if lines.is_empty():
		return
	_dlg_lines = lines
	_dlg_i = 0
	_dlg_chars = 0.0
	Game.dialog_active = true
	Audio.sfx("ui_select", -8.0)

func _dlg_speaker() -> String:
	var parts := String(_dlg_lines[_dlg_i]).split("|", true, 1)
	return parts[0] if parts.size() > 1 else ""

func _dlg_text() -> String:
	var parts := String(_dlg_lines[_dlg_i]).split("|", true, 1)
	return parts[1] if parts.size() > 1 else parts[0]

func _end_dialog() -> void:
	Game.dialog_active = false
	Game.dialog_cooldown = 0.3
	_dlg_lines = []
	dialog_finished.emit()

# ------------------------------------------------------------- Entrada

func _unhandled_input(event: InputEvent) -> void:
	if Game.dialog_active:
		var adv: bool = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			adv = true
		if adv:
			get_viewport().set_input_as_handled()
			if _dlg_chars < float(_dlg_text().length()):
				_dlg_chars = float(_dlg_text().length())
			else:
				_dlg_i += 1
				_dlg_chars = 0.0
				if _dlg_i >= _dlg_lines.size():
					_end_dialog()
		return
	if screen == "dead" and _screen_t > 1.2 and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		respawn_requested.emit()
		return
	if screen == "win" and _screen_t > 1.5 and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		menu_requested.emit()
		return
	if screen == "":
		if event.is_action_pressed("ui_cancel"):
			_set_paused(not _paused)
			get_viewport().set_input_as_handled()
		elif _paused and event is InputEventKey and event.pressed and event.physical_keycode == KEY_M:
			_set_paused(false)
			menu_requested.emit()
		elif _paused and event.is_action_pressed("ui_accept"):
			_set_paused(false)

func _set_paused(v: bool) -> void:
	_paused = v
	get_tree().paused = v
	Audio.sfx("ui_move", -6.0)

# ------------------------------------------------------------- Desenho

func _text(pos: Vector2, text: String, color: Color = COLOR_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, fsize: int = FONT_SIZE) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, text, align, width, fsize, 3, COLOR_OUTLINE)
	draw_string(font, pos, text, align, width, fsize, color)

func _mtext(pos: Vector2, text: String, width: float, color: Color = COLOR_TEXT, fsize: int = FONT_SIZE, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := ThemeDB.fallback_font
	draw_multiline_string_outline(font, pos, text, align, width, fsize, -1, 3, COLOR_OUTLINE)
	draw_multiline_string(font, pos, text, align, width, fsize, -1, color)

func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL)
	draw_rect(r, COLOR_GOLD, false, 1.0)
	draw_rect(r.grow(-2), Color(0.45, 0.3, 0.15), false, 1.0)

func _draw() -> void:
	var s := size
	if _flash_time > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(_flash_color.r, _flash_color.g, _flash_color.b, 0.35 * (_flash_time / _flash_total)))

	if screen == "":
		_draw_hud(s)
	_draw_banner(s)
	if Game.dialog_active and _dlg_i < _dlg_lines.size():
		_draw_dialog(s)
	if screen == "dead":
		_draw_dead(s)
	elif screen == "win":
		_draw_win(s)
	if _paused:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
		_text(Vector2(0, s.y * 0.38), "PAUSADO", COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER, s.x, 16)
		_text(Vector2(0, s.y * 0.38 + 18), "ESC / ENTER: continuar", COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		_text(Vector2(0, s.y * 0.38 + 30), "M: reiniciar o jogo", COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	if _fade_a > 0.001:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, _fade_a))
	if show_crosshair and screen == "" and not _paused and not Game.dialog_active:
		_draw_crosshair()

func _draw_hud(s: Vector2) -> void:
	# Vida
	_text(Vector2(6, 12), "VIDA")
	for i in max_health:
		var r := Rect2(30 + i * 10, 5, 8, 8)
		draw_rect(r, Color(0.15, 0.03, 0.03))
		if i < health:
			draw_rect(r.grow(-1), Color(0.85, 0.15, 0.12))
			draw_rect(Rect2(r.position.x + 1, r.position.y + 1, 3, 1), Color(1, 0.55, 0.5))
		draw_rect(r, COLOR_OUTLINE, false, 1.0)
	# Objetivo e contadores
	if objective != "":
		_text(Vector2(0, 12 if not boss_bar else 34), objective, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	_text(Vector2(s.x - 74, 12), "Abates: %d" % Game.kills, COLOR_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 68)
	# Arma e munição
	if weapon_name != "":
		_text(Vector2(6, s.y - 18), weapon_name)
		var ammo_text := "Munição: %d/%d" % [ammo_in_mag, mag_size]
		if reserve >= 0:
			ammo_text += "  (+%d)" % reserve
		var low := ammo_in_mag == 0 and reserve == 0
		_text(Vector2(6, s.y - 7), ammo_text, Color(1.0, 0.4, 0.3) if low else COLOR_TEXT)
		if reloading:
			_text(Vector2(0, s.y * 0.5 + 26), "RECARREGANDO...", Color(1.0, 0.7, 0.3), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	# Slots de armas
	for i in Weapons.ORDER.size():
		var id: String = Weapons.ORDER[i]
		var has := owned_ids.has(id)
		var box := Rect2(s.x - 6 - (Weapons.ORDER.size() - i) * 15, s.y - 18, 13, 13)
		draw_rect(box, Color(0.15, 0.08, 0.04, 0.85) if has else Color(0.1, 0.1, 0.1, 0.4))
		draw_rect(box, COLOR_GOLD if id == current_id else COLOR_OUTLINE, false, 1.0)
		_text(Vector2(box.position.x + 4, box.position.y + 10), str(i + 1), COLOR_TEXT if has else Color(0.5, 0.45, 0.4))
	# Barra do boss
	if boss_bar:
		var w := 190.0
		var x := (s.x - w) * 0.5
		_text(Vector2(0, 14), boss_name, Color(1.0, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER, s.x)
		draw_rect(Rect2(x - 1, 18, w + 2, 9), COLOR_OUTLINE)
		draw_rect(Rect2(x, 19, w, 7), Color(0.2, 0.02, 0.02))
		draw_rect(Rect2(x, 19, w * clampf(boss_hp / boss_max, 0.0, 1.0), 7), Color(0.85, 0.12, 0.1))
		draw_rect(Rect2(x, 19, w * clampf(boss_hp / boss_max, 0.0, 1.0), 2), Color(1.0, 0.5, 0.4))
	# Mensagem central
	if message != "" and not Game.dialog_active:
		var lines := message.split("\n")
		for i in lines.size():
			_text(Vector2(0, s.y * 0.30 + i * 11), lines[i], COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, s.x)

func _draw_banner(s: Vector2) -> void:
	if _banner_t <= 0.0:
		return
	var el := _banner_dur - _banner_t
	var a := minf(el / 0.4, 1.0) * minf(_banner_t / 0.7, 1.0)
	var y := s.y * 0.30
	var tsize := 16 if _banner_big else 12
	draw_rect(Rect2(0, y - 16, s.x, 34 if _banner_sub != "" else 24), Color(0, 0, 0, 0.45 * a))
	var col := Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, a)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(0, y), _banner_title, HORIZONTAL_ALIGNMENT_CENTER, s.x, tsize, 4, Color(COLOR_OUTLINE.r, COLOR_OUTLINE.g, COLOR_OUTLINE.b, a))
	draw_string(font, Vector2(0, y), _banner_title, HORIZONTAL_ALIGNMENT_CENTER, s.x, tsize, col)
	if _banner_sub != "":
		draw_string_outline(font, Vector2(0, y + 13), _banner_sub, HORIZONTAL_ALIGNMENT_CENTER, s.x, FONT_SIZE, 3, Color(COLOR_OUTLINE.r, COLOR_OUTLINE.g, COLOR_OUTLINE.b, a))
		draw_string(font, Vector2(0, y + 13), _banner_sub, HORIZONTAL_ALIGNMENT_CENTER, s.x, FONT_SIZE, Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, a))

func _draw_dialog(s: Vector2) -> void:
	var r := Rect2(10, s.y - 60, s.x - 20, 52)
	_panel(r)
	var speaker := _dlg_speaker()
	if speaker != "":
		var tag := Rect2(r.position.x + 6, r.position.y - 6, speaker.length() * 5.0 + 12.0, 12)
		_panel(tag)
		_text(Vector2(tag.position.x + 6, tag.position.y + 9), speaker, COLOR_GOLD)
	var txt := _dlg_text().substr(0, int(_dlg_chars))
	_mtext(Vector2(r.position.x + 8, r.position.y + 18), txt, r.size.x - 16.0)
	var done := _dlg_chars >= float(_dlg_text().length())
	if done and int(_t * 2.5) % 2 == 0:
		_text(Vector2(r.end.x - 40, r.end.y - 5), "[E] >>", COLOR_GOLD)

func _stats_text() -> String:
	return "Tempo: %s   Abates: %d\nBaús: %d   Segredos: %d/%d" % [Game.time_text(), Game.kills, Game.chests_opened, Game.secrets, secrets_total]

func _draw_dead(s: Vector2) -> void:
	var a := minf(_screen_t / 0.8, 1.0)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.25, 0.0, 0.0, 0.6 * a))
	_text(Vector2(0, s.y * 0.33), "VOCÊ MORREU", Color(0.95, 0.25, 0.2, a), HORIZONTAL_ALIGNMENT_CENTER, s.x, 16)
	_text(Vector2(0, s.y * 0.33 + 16), "O sertão não perdoa...", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, a), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	if _screen_t > 1.2 and int(_t * 2.0) % 2 == 0:
		_text(Vector2(0, s.y * 0.33 + 40), "ENTER: voltar ao último checkpoint", COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER, s.x)

func _draw_win(s: Vector2) -> void:
	var a := minf(_screen_t / 1.2, 1.0)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.03, 0.01, 0.8 * a))
	_text(Vector2(0, s.y * 0.20), "VITÓRIA!", Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, a), HORIZONTAL_ALIGNMENT_CENTER, s.x, 16)
	var lines := Dialogs.WIN_TEXT.split("\n")
	for i in lines.size():
		_text(Vector2(0, s.y * 0.20 + 18 + i * 10), lines[i], Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, a), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	var st := _stats_text().split("\n")
	for i in st.size():
		_text(Vector2(0, s.y * 0.20 + 58 + i * 11), st[i], Color(1.0, 0.95, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	_text(Vector2(0, s.y * 0.20 + 90), "Obrigado por jogar TERRA MALDITA", Color(COLOR_GOLD.r, COLOR_GOLD.g, COLOR_GOLD.b, a), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	if _screen_t > 1.5 and int(_t * 2.0) % 2 == 0:
		_text(Vector2(0, s.y * 0.20 + 108), "ENTER: jogar de novo", COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, s.x)

func _draw_crosshair() -> void:
	var m := get_viewport().get_mouse_position()
	var c := Color(1.0, 0.95, 0.7)
	draw_rect(Rect2(m.x - 5, m.y - 0.5, 3, 1), c)
	draw_rect(Rect2(m.x + 2, m.y - 0.5, 3, 1), c)
	draw_rect(Rect2(m.x - 0.5, m.y - 5, 1, 3), c)
	draw_rect(Rect2(m.x - 0.5, m.y + 2, 1, 3), c)
	draw_rect(Rect2(m.x - 0.5, m.y - 0.5, 1, 1), Color(1, 0.3, 0.2))
