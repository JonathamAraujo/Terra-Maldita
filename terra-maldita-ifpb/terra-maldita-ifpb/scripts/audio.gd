extends Node
## Autoload "Audio": efeitos e músicas SINTETIZADOS POR CÓDIGO (placeholders).
## Para trocar por áudio real, coloque arquivos em res://Audio/ com o NOME abaixo
## (.ogg, .wav ou .mp3). O arquivo tem prioridade sobre o som sintetizado.
##   SFX   : shot_pistola shot_revolver shot_espingarda shot_rifle shot_enemy click reload hit hurt
##           enemy_die chest_open pickup weapon_get heal step boss_roar boss_hit boss_die boss_charge
##           boss_tele blip gate checkpoint bird1 bird2 ui_move ui_select
##   MÚSICA: menu explore combat boss victory defeat   (ambiente: wind, crackle)

const SFX_RATE := 22050
const MUS_RATE := 11025
const AUDIO_DIR := "res://Audio/"
const MUSIC_DB := -9.0
const SFX_DB := -3.0

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _pidx := 0
var _mus: Array[AudioStreamPlayer] = []
var _mus_active := 0
var _cur_music := ""
var _wanted_music := ""
var _wind: AudioStreamPlayer
var _thread: Thread
var _tb := PackedFloat32Array() # buffer de trabalho da música (usado só na thread)
var _rng := RandomNumberGenerator.new()
var muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -60.0
		add_child(m)
		_mus.append(m)
	_wind = AudioStreamPlayer.new()
	add_child(_wind)
	_build_sfx()
	_wind.stream = _load_override("wind", _make_wind())
	_wind.volume_db = -22.0
	_wind.play()
	_thread = Thread.new()
	_thread.start(_build_music_thread)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

func _load_override(sound_name: String, fallback: AudioStream) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var path := "%s%s.%s" % [AUDIO_DIR, sound_name, ext]
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				return res
	return fallback

# ------------------------------------------------------------------ API

func sfx(sound_name: String, vol_db: float = 0.0, pitch: float = 1.0, pitch_var: float = 0.0) -> void:
	if muted or not _sfx.has(sound_name):
		return
	var p := _players[_pidx]
	_pidx = (_pidx + 1) % _players.size()
	p.stream = _sfx[sound_name]
	p.volume_db = SFX_DB + vol_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_var, pitch_var), 0.1)
	p.play()

func sfx_stream(sound_name: String) -> AudioStream:
	return _sfx.get(sound_name, null)

func crackle_stream() -> AudioStream:
	return _sfx.get("crackle", null)

func play_music(track: String, fade: float = 1.0) -> void:
	_wanted_music = track
	if track == _cur_music:
		return
	if not _music.has(track):
		return # ainda sendo gerada; _on_track_ready toca quando ficar pronta
	_cur_music = track
	var old := _mus[_mus_active]
	_mus_active = 1 - _mus_active
	var nw := _mus[_mus_active]
	nw.stream = _music[track]
	nw.volume_db = -60.0
	nw.play()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(nw, "volume_db", -80.0 if muted else MUSIC_DB, fade)
	if old.playing:
		t.tween_property(old, "volume_db", -60.0, fade)
		t.chain().tween_callback(old.stop)

func stop_music(fade: float = 1.0) -> void:
	_wanted_music = ""
	_cur_music = ""
	for m in _mus:
		if m.playing:
			var t := create_tween()
			t.tween_property(m, "volume_db", -60.0, fade)
			t.tween_callback(m.stop)

func current_music() -> String:
	return _cur_music

func set_wind(db: float) -> void:
	_wind.volume_db = db

func _on_track_ready(track: String, stream: AudioStream) -> void:
	_music[track] = stream
	if _wanted_music == track and _cur_music != track:
		play_music(track, 0.5)

# ------------------------------------------------------------ SFX synth

func _wav(buf: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w

func _reg(sound_name: String, buf: PackedFloat32Array, loop: bool = false) -> void:
	_sfx[sound_name] = _load_override(sound_name, _wav(buf, SFX_RATE, loop))

## Tiro: ruído filtrado + "pancada" grave com queda de frequência.
func _shot(dur: float, decay: float, lp: float, thump_f: float, thump_amt: float, noise_amt: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var low := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		low += ((_rng.randf() * 2.0 - 1.0) - low) * lp
		ph += TAU * (thump_f * exp(-t * 9.0) + 28.0) / SFX_RATE
		b[i] = (low * noise_amt * exp(-t * decay) + sin(ph) * thump_amt * exp(-t * decay * 0.6)) * 0.9
	return b

func _tone_sweep(dur: float, f0: float, f1: float, decay: float, noise_amt: float = 0.0, square: bool = false) -> PackedFloat32Array:
	var n := int(dur * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var f := lerpf(f0, f1, t / dur)
		ph += TAU * f / SFX_RATE
		var s := sin(ph)
		if square:
			s = 1.0 if s >= 0.0 else -1.0
			s *= 0.5
		b[i] = (s * 0.7 + (_rng.randf() * 2.0 - 1.0) * noise_amt) * exp(-t * decay)
	return b

func _concat_notes(freqs: Array, note_len: float, tail: float, harmonic: float = 0.3) -> PackedFloat32Array:
	var total := int((note_len * freqs.size() + tail) * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(total)
	for k in freqs.size():
		var start := int(k * note_len * SFX_RATE)
		var nlen := int((note_len + tail) * SFX_RATE)
		for i in nlen:
			var pos := start + i
			if pos >= total:
				break
			var t := float(i) / SFX_RATE
			var f: float = freqs[k]
			b[pos] += (sin(TAU * f * t) + sin(TAU * f * 2.0 * t) * harmonic) * exp(-t * 7.0) * 0.4
	return b

func _clicks(times: Array, ring_f: float) -> PackedFloat32Array:
	var total := int((float(times[times.size() - 1]) + 0.12) * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(total)
	for tm in times:
		var start := int(float(tm) * SFX_RATE)
		for i in int(0.1 * SFX_RATE):
			var pos := start + i
			if pos >= total:
				break
			var t := float(i) / SFX_RATE
			b[pos] += ((_rng.randf() * 2.0 - 1.0) * 0.7 + sin(TAU * ring_f * t) * 0.4) * exp(-t * 70.0)
	return b

func _build_sfx() -> void:
	_rng.seed = 12345
	_reg("shot_pistola", _shot(0.22, 24.0, 0.55, 150.0, 0.6))
	_reg("shot_revolver", _shot(0.30, 16.0, 0.42, 120.0, 0.8))
	_reg("shot_espingarda", _shot(0.50, 10.0, 0.28, 85.0, 1.0))
	_reg("shot_rifle", _shot(0.55, 9.0, 0.75, 95.0, 0.7))
	_reg("shot_enemy", _shot(0.20, 26.0, 0.33, 105.0, 0.5, 0.8))
	_reg("click", _clicks([0.0], 2500.0))
	_reg("reload", _clicks([0.0, 0.32, 0.55], 1800.0))
	_reg("hit", _shot(0.10, 40.0, 0.5, 220.0, 0.6))
	_reg("hurt", _tone_sweep(0.30, 320.0, 110.0, 7.0, 0.25, true))
	_reg("enemy_die", _tone_sweep(0.45, 240.0, 55.0, 5.0, 0.35))
	_reg("pickup", _concat_notes([988.0, 1319.0], 0.08, 0.15))
	_reg("weapon_get", _concat_notes([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.11, 0.45, 0.5))
	_reg("heal", _tone_sweep(0.35, 440.0, 880.0, 5.0))
	_reg("checkpoint", _concat_notes([659.0, 880.0], 0.14, 0.4, 0.2))
	_reg("blip", _tone_sweep(0.045, 520.0, 480.0, 25.0, 0.0, true))
	_reg("ui_move", _tone_sweep(0.04, 700.0, 700.0, 30.0, 0.0, true))
	_reg("ui_select", _concat_notes([523.0, 784.0], 0.07, 0.15))
	_reg("bird1", _tone_sweep(0.16, 2600.0, 3400.0, 14.0))
	_reg("bird2", _concat_notes([3000.0, 2500.0, 3200.0], 0.06, 0.08, 0.0))
	_reg("boss_hit", _shot(0.16, 28.0, 0.4, 170.0, 0.9))
	_reg("boss_tele", _concat_notes([440.0, 440.0], 0.12, 0.1, 0.6))
	_reg("boss_charge", _tone_sweep(0.55, 90.0, 520.0, 3.0, 0.45))
	_reg("boss_roar", _roar())
	_reg("boss_die", _shot(1.8, 2.8, 0.18, 60.0, 1.0))
	_reg("step", _shot(0.07, 55.0, 0.18, 70.0, 0.35, 0.5))
	_reg("gate", _shot(0.7, 6.0, 0.15, 55.0, 1.0))
	_reg("chest_open", _chest_open())
	_sfx["crackle"] = _load_override("crackle", _wav(_make_crackle(), SFX_RATE, true))

func _roar() -> PackedFloat32Array:
	var n := int(1.3 * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	var low := 0.0
	for i in n:
		var t := float(i) / SFX_RATE
		var f := 72.0 + sin(t * 24.0) * 9.0 + t * 12.0
		ph += TAU * f / SFX_RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		low += ((_rng.randf() * 2.0 - 1.0) - low) * 0.2
		var env := minf(t * 8.0, 1.0) * exp(-maxf(t - 0.5, 0.0) * 2.8)
		b[i] = (saw * 0.6 + low * 0.7) * env
	return b

func _chest_open() -> PackedFloat32Array:
	var creak := int(0.30 * SFX_RATE)
	var spark := _concat_notes([880.0, 1175.0, 1480.0], 0.07, 0.25, 0.3)
	var b := PackedFloat32Array()
	b.resize(creak + spark.size())
	var low := 0.0
	for i in creak:
		var t := float(i) / SFX_RATE
		low += ((_rng.randf() * 2.0 - 1.0) - low) * 0.08
		b[i] = low * (0.6 + 0.4 * sin(t * 110.0)) * (1.0 - t / 0.30) * 1.6
	for i in spark.size():
		b[creak + i] = spark[i]
	return b

func _make_crackle() -> PackedFloat32Array:
	var n := int(3.0 * SFX_RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var low := 0.0
	var pop := 0.0
	for i in n:
		low += ((_rng.randf() * 2.0 - 1.0) - low) * 0.05
		if _rng.randf() < 0.0012:
			pop = _rng.randf_range(0.4, 1.0)
		pop *= 0.985
		b[i] = low * 0.35 + (_rng.randf() * 2.0 - 1.0) * pop * 0.5
	for i in 400: # emenda suave do loop
		var k := float(i) / 400.0
		b[i] *= k
		b[n - 1 - i] *= k
	return b

func _make_wind() -> AudioStream:
	var n := MUS_RATE * 6
	var b := PackedFloat32Array()
	b.resize(n)
	var low := 0.0
	var low2 := 0.0
	for i in n:
		var t := float(i) / MUS_RATE
		low += ((_rng.randf() * 2.0 - 1.0) - low) * 0.06
		low2 += (low - low2) * 0.2
		var gust := 0.55 + 0.45 * sin(TAU * t / 6.0 * 1.0) * sin(TAU * t / 3.0 + 1.0)
		b[i] = low2 * gust * 3.2
	for i in 600:
		var k := float(i) / 600.0
		b[i] *= k
		b[n - 1 - i] *= k
	return _wav(b, MUS_RATE, true)

# ---------------------------------------------------------- Music synth

func _build_music_thread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_rng_local = rng
	for track in ["menu", "explore", "combat", "boss", "victory", "defeat"]:
		var stream: AudioStream = _load_override(track, null)
		if stream == null:
			stream = _compose(track)
		call_deferred("_on_track_ready", track, stream)

var _rng_local: RandomNumberGenerator

func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

func _new_track(seconds: float) -> void:
	_tb = PackedFloat32Array()
	_tb.resize(int(seconds * MUS_RATE))

## Corda dedilhada (Karplus-Strong): soa como viola/violão. Envolve o fim do buffer (loop sem emenda).
func _pluck(start_s: float, midi: int, dur: float, vol: float, decay: float = 0.997) -> void:
	var f := _hz(midi)
	var n := maxi(int(MUS_RATE / f), 2)
	var ring := PackedFloat32Array()
	ring.resize(n)
	var prev := 0.0
	for i in n:
		var r := _rng_local.randf() * 2.0 - 1.0
		prev = (prev + r) * 0.5
		ring[i] = prev
	var start := int(start_s * MUS_RATE)
	var count := int(dur * MUS_RATE)
	var size := _tb.size()
	var idx := 0
	for k in count:
		var a := ring[idx]
		var nx := ring[(idx + 1) % n]
		_tb[(start + k) % size] += a * vol
		ring[idx] = (a + nx) * 0.5 * decay
		idx = (idx + 1) % n

func _drum_kick(start_s: float, vol: float) -> void:
	var start := int(start_s * MUS_RATE)
	var size := _tb.size()
	var ph := 0.0
	for k in int(0.22 * MUS_RATE):
		var t := float(k) / MUS_RATE
		ph += TAU * (45.0 + 90.0 * exp(-t * 28.0)) / MUS_RATE
		_tb[(start + k) % size] += sin(ph) * exp(-t * 12.0) * vol

func _drum_noise(start_s: float, dur: float, vol: float, lp: float) -> void:
	var start := int(start_s * MUS_RATE)
	var size := _tb.size()
	var low := 0.0
	for k in int(dur * MUS_RATE):
		var t := float(k) / MUS_RATE
		low += ((_rng_local.randf() * 2.0 - 1.0) - low) * lp
		_tb[(start + k) % size] += low * exp(-t / dur * 6.0) * vol

func _drone(midi: int, vol: float) -> void:
	var f := _hz(midi)
	var size := _tb.size()
	var ph := 0.0
	var ph2 := 0.0
	for k in size:
		var t := float(k) / MUS_RATE
		ph += TAU * f / MUS_RATE
		ph2 += TAU * f * 1.5 * 1.002 / MUS_RATE
		_tb[k] += (sin(ph) + 0.5 * sin(ph2)) * vol * (0.8 + 0.2 * sin(TAU * t / (float(size) / MUS_RATE)))

func _echo(delay_s: float, gain: float) -> void:
	var size := _tb.size()
	var d := int(delay_s * MUS_RATE)
	var out := _tb.duplicate()
	for k in size:
		out[(k + d) % size] += _tb[k] * gain
	_tb = out

func _finish(loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in _tb:
		peak = maxf(peak, absf(v))
	var g := 0.85 / peak
	for i in _tb.size():
		_tb[i] *= g
	return _wav(_tb, MUS_RATE, loop)

func _compose(track: String) -> AudioStream:
	match track:
		"menu": return _comp_menu()
		"explore": return _comp_explore()
		"combat": return _comp_combat()
		"boss": return _comp_boss()
		"victory": return _comp_victory()
		_: return _comp_defeat()

## Menu: lento, misterioso (A frígio dominante), viola solitária + drone.
func _comp_menu() -> AudioStream:
	var beat := 60.0 / 62.0
	_new_track(beat * 16.0)
	_drone(45, 0.18)
	var phrase := [[0, 69, 3.0], [3, 70, 1.5], [4.5, 73, 1.5], [6, 74, 2.5], [9, 73, 1.0], [10, 70, 1.5], [12, 69, 3.5]]
	for n in phrase:
		_pluck(float(n[0]) * beat, int(n[1]), 2.4, 0.5, 0.998)
	for b in [0, 4, 8, 12]:
		_pluck(b * beat, 45, 2.8, 0.55, 0.998)
		_pluck(b * beat + 0.05, 52, 2.4, 0.3, 0.998)
	_echo(beat * 0.75, 0.35)
	return _finish(true)

## Exploração: baião tranquilo em Lá mixolídio, 4 compassos.
func _comp_explore() -> AudioStream:
	var bpm := 84.0
	var step := 60.0 / bpm / 2.0 # colcheia
	_new_track(step * 32.0)
	var roots := [45, 43, 50, 45] # A G D A
	var thirds := [61, 59, 54, 61]
	var fifths := [64, 62, 57, 64]
	for bar in 4:
		var t0: float = bar * 8.0 * step
		for s in [0, 3, 4, 6]:
			_pluck(t0 + s * step, int(roots[bar]), 0.5, 0.55, 0.994)
		_pluck(t0, int(roots[bar]) + 12, 0.8, 0.28, 0.996)
		_pluck(t0 + 0.02, int(thirds[bar]), 0.9, 0.25, 0.997)
		_pluck(t0 + 0.04, int(fifths[bar]), 0.9, 0.25, 0.997)
		_pluck(t0 + 4.0 * step, int(thirds[bar]), 0.6, 0.18, 0.996)
		_drum_noise(t0 + 2.0 * step, 0.07, 0.10, 0.5)
		_drum_noise(t0 + 6.0 * step, 0.07, 0.10, 0.5)
	var mel := [
		[[0, 76, 1.2], [2, 74, 0.5], [3, 73, 0.5], [4, 71, 1.0], [6, 69, 0.8]],
		[[0, 74, 1.2], [2, 71, 0.5], [3, 67, 0.5], [4, 71, 1.4]],
		[[0, 78, 1.0], [2, 76, 0.5], [3, 74, 0.5], [4, 73, 1.0], [6, 74, 0.8]],
		[[0, 73, 0.8], [2, 71, 0.5], [3, 69, 0.5], [4, 69, 2.2]],
	]
	for bar in 4:
		for n in mel[bar]:
			_pluck(bar * 8.0 * step + float(n[0]) * step, int(n[1]), float(n[2]) + 0.3, 0.42, 0.997)
	_echo(step * 3.0, 0.3)
	return _finish(true)

## Combate: mais rápido, baixo em colcheias (Mi frígio) + bumbo e caixa.
func _comp_combat() -> AudioStream:
	var bpm := 136.0
	var step := 60.0 / bpm / 2.0
	_new_track(step * 32.0)
	var bass := [40, 40, 41, 40, 40, 43, 41, 40]
	for bar in 4:
		var t0: float = bar * 8.0 * step
		for s in 8:
			_pluck(t0 + s * step, int(bass[s]) + (0 if bar != 3 else 2 * (s % 2)), 0.28, 0.6, 0.992)
		for s in [0, 4]:
			_drum_kick(t0 + s * step, 0.9)
		for s in [2, 6]:
			_drum_noise(t0 + s * step, 0.12, 0.45, 0.6)
		for s in [1, 3, 5, 7]:
			_drum_noise(t0 + s * step, 0.04, 0.18, 0.9)
		var riff := [[0, 64], [1, 65], [2, 64], [3, 68], [4, 65], [5, 64], [6, 61]] if bar % 2 == 0 else [[0, 68], [1, 69], [2, 68], [3, 65], [4, 64], [5, 65], [6, 64]]
		for n in riff:
			_pluck(t0 + float(n[0]) * step, int(n[1]) + 12, 0.25, 0.35, 0.993)
	return _finish(true)

## Boss: drone grave, pancadas e acordes cromáticos tensos (Ré).
func _comp_boss() -> AudioStream:
	var bpm := 118.0
	var beat := 60.0 / bpm
	_new_track(beat * 16.0)
	_drone(38, 0.35)
	_drone(50, 0.12)
	for b in 16:
		var t: float = b * beat
		if b % 2 == 0:
			_drum_kick(t, 1.0)
		if b % 4 == 2:
			_drum_noise(t, 0.16, 0.6, 0.55)
		_drum_noise(t + beat * 0.5, 0.04, 0.2, 0.9)
		_pluck(t, 38 + (1 if b % 8 >= 6 else 0), 0.4, 0.6, 0.993)
	var stabs := [[0, 62], [2, 63], [4, 62], [6, 65], [8, 62], [10, 63], [12, 68], [14, 67]]
	for s in stabs:
		_pluck(float(s[0]) * beat, int(s[1]), 0.9, 0.45, 0.996)
		_pluck(float(s[0]) * beat + 0.02, int(s[1]) + 6, 0.7, 0.2, 0.996)
	_echo(beat * 0.75, 0.3)
	return _finish(true)

func _comp_victory() -> AudioStream:
	var beat := 60.0 / 104.0
	_new_track(beat * 12.0)
	var notes := [[0, 60], [1, 64], [2, 67], [3, 72], [4, 71], [4.5, 72], [5, 76], [6, 74], [7, 76], [8, 79]]
	for n in notes:
		var m := int(n[1])
		_pluck(float(n[0]) * beat, m, 2.0, 0.55, 0.997)
		_pluck(float(n[0]) * beat, m - 12, 2.0, 0.3, 0.997)
	for c in [[0, 48], [4, 53], [8, 48]]:
		_pluck(float(c[0]) * beat, int(c[1]), 3.0, 0.5, 0.998)
		_pluck(float(c[0]) * beat + 0.03, int(c[1]) + 7, 3.0, 0.3, 0.998)
		_pluck(float(c[0]) * beat + 0.06, int(c[1]) + 16, 3.0, 0.25, 0.998)
	_drum_kick(8 * beat, 0.8)
	_echo(beat * 0.5, 0.3)
	return _finish(false)

func _comp_defeat() -> AudioStream:
	var beat := 60.0 / 60.0
	_new_track(beat * 8.0)
	_drone(40, 0.2)
	for n in [[0, 64], [1.5, 62], [3, 60], [4.5, 59], [6, 52]]:
		_pluck(float(n[0]) * beat, int(n[1]), 2.4, 0.6, 0.998)
	_pluck(0.0, 40, 6.0, 0.5, 0.999)
	_echo(beat * 0.9, 0.35)
	return _finish(false)
