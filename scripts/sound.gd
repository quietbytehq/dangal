extends Node
## Sound manager (autoload "Sound"): sound effects, fighter voices, the announcer and music.

const ROOT := "res://assets/audio/"
const SFX_VOICES := 10

var _cache := {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _next := 0
var _announcer: AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice := {}   # one voice channel per player, so shouts don't pile up


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # music keeps playing in the pause menu
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_announcer = AudioStreamPlayer.new()
	_announcer.volume_db = 2.0
	add_child(_announcer)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)
	for player in [1, 2]:
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voice[player] = v


func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(ROOT + path + ".ogg") if ResourceLoader.exists(ROOT + path + ".ogg") else null
	return _cache[path]


## A sound effect with a little random pitch so repeats don't sound identical.
func sfx(name: String, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	var s := _stream("sfx/" + name)
	# a second take ("punch_2") is picked half the time so repeated hits vary
	if randf() < 0.5:
		var alt := _stream("sfx/" + name + "_2")
		if alt != null:
			s = alt
	if s == null:
		return
	var p := _sfx_players[_next]
	_next = (_next + 1) % SFX_VOICES
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## A fighter voice line from assets/audio/<who>/. Each player has one voice channel,
## so a new line cuts the old one.
func voice(who: String, player: int, line: String, chance := 1.0, pitch := 1.0) -> void:
	if randf() > chance:
		return
	var s := _stream(who + "/" + line)
	if s == null:
		return
	var v: AudioStreamPlayer = _voice[player]
	v.stream = s
	v.pitch_scale = pitch
	v.play()


func announce(line: String) -> void:
	var s := _stream("announcer/" + line)
	if s:
		_announcer.stream = s
		_announcer.play()


func play_music(track: String) -> void:
	var s := _stream("music/" + track)
	if s == null or (_music.playing and _music.stream == s):
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	_music.stream = s
	_music.play()


func music_volume(db: float) -> void:
	var t := create_tween()
	t.tween_property(_music, "volume_db", db, 0.6)
