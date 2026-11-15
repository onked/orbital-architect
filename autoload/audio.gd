extends Node

signal voice_cue(text: String)
signal voice_cue_cleared

const DI := "res://assets/audio/interface/"
const UI := "res://assets/audio/ui/"
const SF := "res://assets/audio/scifi/"

const HOVER := UI + "rollover2.wav"
const CLICK := DI + "click_002.wav"
const BACK := DI + "back_001.wav"
const CONFIRM := DI + "confirmation_001.wav"
const ERROR := DI + "error_001.wav"
const BONG := DI + "bong_001.wav"
const BURN := SF + "space_engine_000.ogg"
const THRUST := SF + "thruster_fire_000.ogg"
const EXPLOSION := SF + "explosion_crunch_000.ogg"
const TRANSMIT := SF + "computer_noise_001.ogg"
const AMBIENCE := SF + "space_engine_low_000.ogg"
const MUSIC_MENU := "res://assets/audio/music/menu_light_years.ogg"
const MUSIC_FLIGHT := "res://assets/audio/music/flight_cold_moon.ogg"

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _voice_path: String = ""
var _music_path: String = ""
var _fade: Tween
var _cache: Dictionary = {}

func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	_ensure_bus("Music")
	_ensure_bus("Voice")
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	_ambience.stream = _stream(AMBIENCE)
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	_voice.finished.connect(_on_voice_finished)
	apply_all()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var result: AudioStream = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is AudioStream:
			result = res
	_cache[path] = result
	return result

func play(path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _stream(path)
	if stream == null or _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func ui_hover() -> void:
	play(HOVER, -20.0, randf_range(0.96, 1.04))

func ui_click() -> void:
	play(CLICK, -9.0, randf_range(0.97, 1.03))

func ui_confirm() -> void:
	play(CONFIRM, -7.0)

func ui_error() -> void:
	play(ERROR, -6.0)

func achievement() -> void:
	play(BONG, -5.0)

func burn() -> void:
	play(BURN, -8.0)
	play(THRUST, -12.0, 0.9)

func explosion() -> void:
	play(EXPLOSION, -3.0)

func transmit() -> void:
	play(TRANSMIT, -11.0)

func rewind() -> void:
	play(BACK, -8.0, 0.8)

func play_music(key: String) -> void:
	var path: String = MUSIC_FLIGHT if key == "flight" else MUSIC_MENU
	if path == _music_path and _music.playing:
		return
	var stream := _stream(path)
	if stream == null:
		return
	_music_path = path
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if _music.playing:
		_fade = create_tween()
		_fade.tween_property(_music, "volume_db", -40.0, 0.35)
		_fade.tween_callback(func() -> void:
			_music.stream = stream
			_music.play())
		_fade.tween_property(_music, "volume_db", 0.0, 0.9)
	else:
		_music.stream = stream
		_music.volume_db = 0.0
		_music.play()

func play_voice(path: String, subtitle: String = "") -> void:
	var stream := _stream(path)
	if stream == null:
		return
	_voice.stop()
	_voice.stream = stream
	_voice_path = path
	_voice.play()
	if subtitle.strip_edges() == "":
		voice_cue_cleared.emit()
	else:
		voice_cue.emit(subtitle)
	if _music != null and _music.playing:
		create_tween().tween_property(_music, "volume_db", -9.0, 0.15)

func stop_voice() -> void:
	if _voice != null and _voice.playing:
		_voice.stop()
	_voice_path = ""
	voice_cue_cleared.emit()
	_restore_music()

func _on_voice_finished() -> void:
	voice_cue_cleared.emit()
	_restore_music()

func voice_path() -> String:
	return _voice_path

func _restore_music() -> void:
	if _music != null and _music.playing:
		create_tween().tween_property(_music, "volume_db", 0.0, 0.35)

func set_ambience(on: bool) -> void:
	if _ambience == null:
		return
	if on and not _ambience.playing:
		_ambience.play()
	elif not on and _ambience.playing:
		_ambience.stop()

func set_volume(key: String, value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	var db := linear_to_db(maxf(v, 0.0001))
	match key:
		"vol_master":
			AudioServer.set_bus_volume_db(0, db)
		"vol_sfx":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
		"vol_ambience":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), db)
		"vol_music":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
		"vol_voice":
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), db)

func apply_all() -> void:
	var s: Dictionary = GameState.settings
	set_volume("vol_master", float(s.get("vol_master", 0.8)))
	set_volume("vol_sfx", float(s.get("vol_sfx", 0.8)))
	set_volume("vol_ambience", float(s.get("vol_ambience", 0.35)))
	set_volume("vol_music", float(s.get("vol_music", 0.5)))
	set_volume("vol_voice", float(s.get("vol_voice", 1.0)))
