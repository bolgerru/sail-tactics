class_name SoundManager
extends Node
## Procedurally generated sound effects (no audio assets).

const RATE := 22050
const WIND_BASE := 0.05
const WIND_GUST := 0.15

var enabled := true

var _beeps := {}
var _gun: AudioStreamWAV
var _tack: AudioStreamWAV
var _fx_players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _wind_player: AudioStreamPlayer
var _wind_gain := WIND_BASE
var _wind_target := WIND_BASE


func _ready() -> void:
	_gun = _make_gun()
	_tack = _make_tack()
	for freq in [440, 540, 640]:
		_beeps[freq] = _make_beep(freq)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_fx_players.append(p)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = _make_wind()
	add_child(_wind_player)
	_wind_player.play()
	_apply_wind_volume()


func _process(delta: float) -> void:
	# Smooth towards the target volume (time constant 0.1s).
	_wind_gain = lerpf(_wind_gain, _wind_target, 1.0 - exp(-delta / 0.1))
	_apply_wind_volume()


func set_wind_volume(vol: float) -> void:
	_wind_target = vol


func play_start_beep(freq: int = 440) -> void:
	_play(_beeps.get(freq, _beeps[440]))


func play_start_gun() -> void:
	_play(_gun)


func play_tack() -> void:
	_play(_tack)


func _play(stream: AudioStream) -> void:
	if not enabled or stream == null:
		return
	var p := _fx_players[_next_player]
	_next_player = (_next_player + 1) % _fx_players.size()
	p.stream = stream
	p.play()


func _apply_wind_volume() -> void:
	if _wind_player == null:
		return
	var v := _wind_gain if enabled else 0.0
	_wind_player.volume_db = linear_to_db(maxf(v, 0.0001))


func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _make_beep(freq: float) -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		# Exponential fade 0.3 -> 0.01 over 0.5s.
		var gain := 0.3 * pow(0.01 / 0.3, t / 0.5)
		s[i] = sin(TAU * freq * t) * gain
	return _to_wav(s)


func _make_gun() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gain := 0.4 if t < 0.15 else 0.4 * (1.0 - (t - 0.15) / 0.05)
		s[i] = sin(TAU * 660.0 * t) * gain
	return _to_wav(s)


func _make_tack() -> AudioStreamWAV:
	# Low-passed white noise burst, like a sail snapping.
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var alpha := 1.0 - exp(-TAU * 800.0 / RATE)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += alpha * ((randf() * 2.0 - 1.0) - lp)
		s[i] = lp * 0.5 * pow(0.01 / 0.5, t / 0.2) * 2.0
	return _to_wav(s)


func _make_wind() -> AudioStreamWAV:
	# Looping brown-ish noise. A linear drift is removed so the last sample
	# meets the first and the loop is click-free.
	var n := RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var last := 0.0
	for i in n:
		last = (last + 0.02 * (randf() * 2.0 - 1.0)) / 1.02
		s[i] = last * 3.5
	var drift := s[n - 1] - s[0]
	for i in n:
		s[i] -= drift * float(i) / (n - 1)
	return _to_wav(s, true)
