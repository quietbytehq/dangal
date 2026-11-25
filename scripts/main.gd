extends Node2D
## DANGAL — game flow:
## title -> character select -> stage select -> versus close-ups -> rounds (intro, fight, ko)
## -> victory close-ups. Also: pause menu, hit-stop, combo counter, ultra meter + cut-in,
## animated stage backgrounds, CPU difficulty.

const GAME_TITLE := "DANGAL"
## Overall fight speed: 1.0 is the clips' natural pace; higher is snappier arcade action.
const GAME_SPEED := 1.3
const FLOOR_Y := 640.0
const ROUND_TIME := 99.0
const WINS_NEEDED := 2
const STAGES := [
	{"name": "KARACHI ROOFTOP", "image": "res://assets/stage/karachi_rooftop.png", "music": "stage_karachi",
		"video": "res://assets/stage/karachi_loop.ogv",
		"props": [["crate", 105.0], ["matka", 235.0], ["drum", 1165.0], ["crate", 1045.0]]},
	{"name": "HUNZA VALLEY", "image": "res://assets/stage/hunza_valley.png", "music": "stage_hunza",
		"video": "res://assets/stage/hunza_loop.ogv",
		"props": [["firewood", 120.0], ["basket", 250.0], ["copper_pot", 1170.0], ["basket", 1050.0]]},
]
const LEVELS := ["EASY", "NORMAL", "HARD"]
const TITLE_ITEMS := ["ARCADE  (vs CPU)", "VERSUS  (2 players)", "HOW TO PLAY", "CPU", "QUIT"]
const PAUSE_ITEMS := ["RESUME", "HOW TO PLAY", "CHARACTER SELECT", "TITLE SCREEN"]

## How to Play: [action, player 1 keys, player 2 keys, joypad]
const HELP_CONTROLS := [
	["Move / jump / crouch", "W A S D", "Arrow keys", "D-pad or left stick"],
	["Punch", "J", "Numpad 1", "X  /  Square"],
	["Kick", "K", "Numpad 2", "A  /  Cross"],
	["Special", "L", "Numpad 3", "B  /  Circle"],
	["Ultra (meter full)", "I", "Numpad 4", "Y  /  Triangle"],
	["Pause / menu", "Enter", "Enter", "Start"],
]
## [move, how to do it]. "Forward" means towards your opponent.
const HELP_MOVES := [
	["Jab / Palm strike", "Punch"],
	["Roundhouse / Push kick", "Kick"],
	["Crouch punch", "Hold Down + Punch"],
	["Low sweep", "Hold Down + Kick"],
	["Jump attack", "Jump (Up), then Punch or Kick in the air"],
	["Jump over", "Jump towards your opponent to land behind him"],
	["Block", "Hold Back (away from your opponent). Hold Back + Down to block crouching"],
	["Special", "Special   or   Down, Down-Forward, Forward + Punch"],
	["Kick special", "Forward + Special   or   Down, Down-Forward, Forward + Kick"],
	["Ultra", "Fill the blue meter, then press Ultra"],
]

var p1: Fighter
var p2: Fighter
var phase := "title"   # title, select, stage, versus, intro, fight, ko, victory
var phase_time := 0.0
var round_num := 1
var wins := {1: 0, 2: 0}
var clock := ROUND_TIME
var banner := ""
var winner_text := ""
var shake := 0.0
var hud: Control
var world: Node2D
var bg: Sprite2D
var bg_video: VideoStreamPlayer
var ambience: Ambience
var title_show: TitleShow
var _icon_tex: Texture2D
var _portraits := {}
var _ultra_user: Fighter
var _ultra_t := -1.0
var _champ: Fighter
var _help_open := false
var _shot_n := 0
var _help_page := 0
var p2_cpu := true
var cpu_level := 1
var stage_idx := 0
var paused := false
var _menu_idx := 0
var _pause_idx := 0
var _cues := {}
var _round_winner: Fighter
var _sprite_cache := {}
var _stage_tex := {}
var _combo := {1: [0, 0.0], 2: [0, 0.0]}   # player -> [hits, time left on screen]
var _hitstop_token := 0

# character select state
var _cursor := {1: 0, 2: 1}
var _locked_in := {1: false, 2: false}
var _cpu_pick_at := -1.0


func _ready() -> void:
	randomize()
	Engine.time_scale = GAME_SPEED
	process_mode = Node.PROCESS_MODE_ALWAYS     # menus keep working while paused
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	bg = Sprite2D.new()
	bg.centered = false
	bg.z_index = -11          # behind the video, props (-1) and fighters (0)
	world.add_child(bg)
	# looping animated background on top of the still image (falls back to the image)
	bg_video = VideoStreamPlayer.new()
	bg_video.z_index = -10
	bg_video.size = Vector2(1280, 720)
	bg_video.expand = true
	bg_video.loop = true
	bg_video.volume_db = -80.0
	bg_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(bg_video)
	# code-drawn life on top of the background: kites, birds, petals, lights
	ambience = Ambience.new()
	world.add_child(ambience)
	_icon_tex = load("res://icon.png") if ResourceLoader.exists("res://icon.png") else null
	for st in STAGES:
		var path: String = st["image"]
		_stage_tex[path] = load(path) if ResourceLoader.exists(path) else null
	_set_stage(0)

	for id in Characters.ROSTER:
		var def := Characters.get_def(id)
		_sprite_cache[id] = SpriteLibrary.load_character(def["sprites"], def["json"])
		_portraits[id] = {}
		for kind in ["callout", "win", "beaten"]:
			var path := "res://assets/portraits/%s_%s.jpg" % [id, kind]
			_portraits[id][kind] = load(path) if ResourceLoader.exists(path) else null

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)

	if "--smoke" in OS.get_cmdline_user_args():
		_smoke_test()
	elif "--shots" in OS.get_cmdline_user_args():
		_shots()
	else:
		_enter_title()


## CI self-test: CPU vs CPU on every stage for a few seconds each, then quit.
## Any script/runtime error shows up in the log and fails the build.
func _smoke_test() -> void:
	var t := 0.0
	for st in STAGES.size():
		_clear_match()
		_set_stage(st)
		# newest fighter first: stage 0 is Tiago vs Rustam, then the others take turns
		var n := Characters.ROSTER.size()
		_cursor = {1: (st + n - 1) % n, 2: st % n}
		p2_cpu = true
		cpu_level = 2
		_start_match()
		p1.cpu = true
		p1.cpu_level = 2
		p1.meter = 100.0    # exercise the ultra path too
		p2.meter = 100.0
		phase = "fight"
		p1.locked = false
		p2.locked = false
		# throw some props around so their physics run too
		for prop in get_tree().get_nodes_in_group("props"):
			prop.hit(Vector2(randf_range(-600, 600), -500), 200)
		await get_tree().create_timer(8.0, true, false, true).timeout
		print("SMOKE stage %d ok: p1 %d hp, p2 %d hp" % [st, p1.health, p2.health])
	print("SMOKE PASSED")
	get_tree().quit()


## CI screenshot tour (needs a real renderer, e.g. under xvfb): plays the real flow
## CPU vs CPU and saves PNGs to the folder given after --shots.
func _shots() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[args.find("--shots") + 1] if args.size() > args.find("--shots") + 1 else "/tmp/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	_enter_title()
	_shot_n = 0
	var snap := func(label: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%02d_%s.png" % [dir, _shot_n, label])
		_shot_n += 1
	var wait := func(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	await wait.call(1.0)
	await snap.call("title")
	await wait.call(1.6)
	await snap.call("title_b")
	await wait.call(1.3)
	await snap.call("title_c")
	_open_help()
	await wait.call(0.2)
	await snap.call("help_controls")
	_help_page = 1
	await wait.call(0.2)
	await snap.call("help_moves")
	_help_open = false
	_enter_select()
	_cursor = {1: 2, 2: 0}
	p2_cpu = true
	await wait.call(0.5)
	await snap.call("select")
	for st in STAGES.size():
		_clear_match()
		_set_stage(st)
		# newest fighter first: stage 0 is Tiago vs Rustam, then the others take turns
		var n := Characters.ROSTER.size()
		_cursor = {1: (st + n - 1) % n, 2: st % n}
		p2_cpu = true
		cpu_level = 2
		phase = "versus"
		phase_time = 0.0
		_cues.clear()
		await wait.call(0.8)
		await snap.call("s%d_versus" % st)
		_start_match()
		p1.cpu = true
		p1.cpu_level = 2
		await wait.call(0.4)
		await snap.call("s%d_intro_a" % st)
		await wait.call(1.6)
		await snap.call("s%d_intro_b" % st)
		await wait.call(1.2)
		print("SHOTS stage %d video playing=%s pos=%.2f" % [st, bg_video.is_playing(), bg_video.stream_position])
		if st == 0:
			# scripted cross-up: player 1 jumps over a standing player 2
			p2.locked = true
			p1.locked = true
			p1.position.x = p2.position.x - 260.0
			var before := "p1 x=%d facing=%d | p2 x=%d" % [p1.position.x, p1.facing, p2.position.x]
			p1.state = "jump"
			p1.vel = Vector2(p1.facing * p1.walk_speed * Fighter.JUMP_DRIFT, 0.0)
			p1._play("jump", p1._length("jump") / Fighter.JUMP_TIME)
			await wait.call(0.35)
			await snap.call("s0_jump_over_mid")
			await wait.call(0.9)
			p1.locked = false
			p2.locked = false
			await wait.call(0.2)
			await snap.call("s0_jump_over_landed")
			print("SHOTS cross-up before: %s  after: p1 x=%d facing=%d | p2 x=%d facing=%d" % [
					before, p1.position.x, p1.facing, p2.position.x, p2.facing])
		for k in 6:
			if k == 3:
				p1.meter = 100.0
			await snap.call("s%d_fight_%d" % [st, k])
			await wait.call(1.0)
		# finish the match: player 1 already has a round, knock player 2 out
		wins[1] = WINS_NEEDED - 1
		p2.locked = true      # can't block this one
		p2.take_hit(5000, 300.0, 0.5, p1.facing)
		await wait.call(0.6)
		await snap.call("s%d_ko" % st)
		await wait.call(3.4)
		await snap.call("s%d_after_ko" % st)
		await wait.call(1.2)
		await snap.call("s%d_victory_a" % st)
		await wait.call(3.5)
		await snap.call("s%d_victory_b" % st)
	print("SHOTS DONE %d" % _shot_n)
	get_tree().quit()


func _set_stage(i: int) -> void:
	stage_idx = i
	var tex: Texture2D = _stage_tex.get(STAGES[i]["image"])
	if tex == null:
		tex = _stage_tex.get(STAGES[0]["image"])
	bg.texture = tex
	if tex:
		bg.scale = Vector2(1280.0, 720.0) / tex.get_size()
	ambience.setup(i)
	var vpath: String = STAGES[i].get("video", "")
	if vpath != "" and ResourceLoader.exists(vpath):
		bg_video.stream = load(vpath)
		bg_video.visible = true
		bg_video.play()
	else:
		bg_video.stop()
		bg_video.visible = false


func _pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)


# ---------------------------------------------------------------- title

func _enter_title() -> void:
	_clear_match()
	phase = "title"
	phase_time = 0.0
	_menu_idx = 0
	_set_stage(randi() % STAGES.size())
	# attract mode: the two fighters trade blows behind the menu
	title_show = TitleShow.new()
	world.add_child(title_show)
	title_show.setup(_sprite_cache[Characters.ROSTER[0]], _sprite_cache[Characters.ROSTER[1]])
	title_show.impact.connect(func(amount: float): shake = max(shake, amount))
	if ResourceLoader.exists("res://assets/audio/music/title.ogg"):
		Sound.play_music("title")
	else:
		Sound.play_music(STAGES[stage_idx]["music"])
	Sound.music_volume(-12.0)


func _process_title() -> void:
	if _help_open:
		_process_help()
		return
	if _pressed("p1_up") or _pressed("p2_up"):
		_menu_idx = (_menu_idx - 1 + TITLE_ITEMS.size()) % TITLE_ITEMS.size()
		Sound.sfx("whoosh", -12.0)
	elif _pressed("p1_down") or _pressed("p2_down"):
		_menu_idx = (_menu_idx + 1) % TITLE_ITEMS.size()
		Sound.sfx("whoosh", -12.0)
	elif TITLE_ITEMS[_menu_idx] == "CPU" and (_pressed("p1_left") or _pressed("p1_right")):
		cpu_level = (cpu_level + (1 if _pressed("p1_right") else -1) + LEVELS.size()) % LEVELS.size()
		Sound.sfx("block", -6.0)
	elif _pressed("p1_punch") or _pressed("start"):
		match TITLE_ITEMS[_menu_idx]:
			"ARCADE  (vs CPU)":
				p2_cpu = true
				Sound.sfx("punch")
				_enter_select()
			"VERSUS  (2 players)":
				p2_cpu = false
				Sound.sfx("punch")
				_enter_select()
			"HOW TO PLAY":
				_open_help()
			"CPU":
				cpu_level = (cpu_level + 1) % LEVELS.size()
			"QUIT":
				get_tree().quit()


# ---------------------------------------------------------------- character select

func _clear_match() -> void:
	_set_paused(false)
	if title_show:
		title_show.queue_free()
		title_show = null
	_ultra_t = -1.0
	_ultra_user = null
	_champ = null
	for f in [p1, p2]:
		if f:
			f.queue_free()
	p1 = null
	p2 = null
	for n in world.get_children():
		if n is Fireball or n is Prop or n is PropPiece:
			n.queue_free()
	banner = ""
	winner_text = ""
	_cues.clear()


func _enter_select() -> void:
	_clear_match()
	phase = "select"
	phase_time = 0.0
	_locked_in = {1: false, 2: false}
	_cpu_pick_at = -1.0
	Sound.music_volume(-14.0)


func _select_input(p: int) -> void:
	if _locked_in[p]:
		if _pressed("p%d_kick" % p):
			_locked_in[p] = false     # kick = back out
		return
	if p == 1 and not _locked_in[2] and _pressed("p1_kick"):
		_enter_title()
		return
	var n := Characters.ROSTER.size()
	if _pressed("p%d_left" % p):
		_cursor[p] = (_cursor[p] - 1 + n) % n
		Sound.sfx("whoosh", -10.0)
	elif _pressed("p%d_right" % p):
		_cursor[p] = (_cursor[p] + 1) % n
		Sound.sfx("whoosh", -10.0)
	elif _pressed("p%d_up" % p) or _pressed("p%d_down" % p):
		var step := -SELECT_COLS if _pressed("p%d_up" % p) else SELECT_COLS
		var nxt: int = _cursor[p] + step
		if nxt >= 0 and nxt < n:
			_cursor[p] = nxt
			Sound.sfx("whoosh", -10.0)
	elif _pressed("p%d_punch" % p) or (p == 1 and _pressed("start")):
		_locked_in[p] = true
		var id: String = Characters.ROSTER[_cursor[p]]
		Sound.voice(Characters.get_def(id)["voice"], p, "intro")


func _process_select() -> void:
	_select_input(1)
	if phase != "select":
		return
	if p2_cpu:
		if _locked_in[1] and _cpu_pick_at < 0.0:
			_cpu_pick_at = phase_time + 0.8
			# the CPU picks the other fighter most of the time
			_cursor[2] = (_cursor[1] + 1) % Characters.ROSTER.size() if randf() < 0.75 \
					else randi() % Characters.ROSTER.size()
		if _cpu_pick_at > 0.0 and phase_time >= _cpu_pick_at and not _locked_in[2]:
			_locked_in[2] = true
		if not _locked_in[1]:
			_locked_in[2] = false
			_cpu_pick_at = -1.0
	else:
		_select_input(2)

	if _locked_in[1] and _locked_in[2]:
		if not _cues.has("go"):
			_cues["go"] = phase_time
		elif phase_time - float(_cues["go"]) > 1.2:
			_cues.clear()
			phase = "stage"
			phase_time = 0.0


# ---------------------------------------------------------------- stage select

func _process_stage() -> void:
	if _pressed("p1_left") or _pressed("p1_right"):
		var dir := 1 if _pressed("p1_right") else -1
		_set_stage((stage_idx + dir + STAGES.size()) % STAGES.size())
		Sound.sfx("whoosh", -10.0)
	elif _pressed("p1_kick"):
		_locked_in[1] = false
		_locked_in[2] = false
		phase = "select"
	elif phase_time > 0.2 and (_pressed("p1_punch") or _pressed("start")):
		Sound.sfx("punch")
		phase = "versus"
		phase_time = 0.0
		_cues.clear()
		Sound.music_volume(-18.0)


# ---------------------------------------------------------------- versus close-ups

func _id(p: int) -> String:
	return Characters.ROSTER[_cursor[p]]


func _process_versus() -> void:
	var id1 := _id(1)
	var id2 := _id(2)
	if _cue("challenger", 0.05):
		Sound.announce("new_challenger")
	if _cue("slam", 0.45):
		Sound.sfx("ground_pound", -2.0, 0.0)
		shake = 10.0
	if _cue("call1", 2.0):
		Sound.voice(Characters.get_def(id1)["voice"], 1, "callout")
	if _cue("call2", 5.0):
		Sound.voice(Characters.get_def(id2)["voice"], 2, "callout", 1.0, 0.9 if id1 == id2 else 1.0)
	var skip := phase_time > 0.6 and (_pressed("start") or _pressed("p1_punch"))
	if phase_time > 8.2 or skip:
		Sound.music_volume(-9.0)
		_start_match()


func _start_match() -> void:
	var id1: String = Characters.ROSTER[_cursor[1]]
	var id2: String = Characters.ROSTER[_cursor[2]]
	var mirror := id1 == id2
	p1 = _spawn(1, id1, Color.WHITE, 1.0)
	# mirror match: player 2 gets a cooler palette and a slightly deeper voice
	p2 = _spawn(2, id2, Color(0.78, 0.9, 1.25) if mirror else Color.WHITE, 0.9 if mirror else 1.0)
	p1.opponent = p2
	p2.opponent = p1
	p2.cpu = p2_cpu
	p2.cpu_level = cpu_level
	wins = {1: 0, 2: 0}
	round_num = 1
	Sound.play_music(STAGES[stage_idx]["music"])
	_start_round()


func _spawn(p: int, id: String, tint: Color, pitch: float) -> Fighter:
	var f := Fighter.new()
	f.floor_y = FLOOR_Y
	world.add_child(f)
	f.setup(p, id, _sprite_cache[id], tint, pitch)
	f.knocked_out.connect(_on_ko)
	f.landed_hit.connect(_on_hit)
	f.quake.connect(func(amount: float): shake = max(shake, amount))
	f.ultra_requested.connect(_on_ultra)
	return f


# ---------------------------------------------------------------- rounds

func _start_round() -> void:
	for n in world.get_children():
		if n is Fireball or n is Prop or n is PropPiece:
			n.queue_free()
	for spec in STAGES[stage_idx].get("props", []):
		var prop := Prop.new()
		world.add_child(prop)
		prop.setup(spec[0], spec[1], FLOOR_Y)
	p1.reset_for_round(400.0)
	p2.reset_for_round(880.0)
	clock = ROUND_TIME
	_ultra_t = -1.0
	_ultra_user = null
	phase = "intro"
	phase_time = 0.0
	_cues.clear()
	_combo = {1: [0, 0.0], 2: [0, 0.0]}
	var final: bool = wins[1] == WINS_NEEDED - 1 and wins[2] == WINS_NEEDED - 1
	banner = "FINAL ROUND" if final else "ROUND %d" % round_num
	winner_text = ""
	Sound.music_volume(-9.0)


## Runs a cue once, the first time phase_time passes `at` in the current phase.
func _cue(id: String, at: float) -> bool:
	if phase_time >= at and not _cues.has(id):
		_cues[id] = true
		return true
	return false


func _process(delta: float) -> void:
	# keep menus and timers in real time even during hit-stop
	var real: float = delta / max(Engine.time_scale, 0.001)
	if paused:
		_process_pause()
		hud.queue_redraw()
		return
	phase_time += real
	match phase:
		"title":
			_process_title()
		"select":
			_process_select()
		"stage":
			_process_stage()
		"versus":
			_process_versus()
		"intro":
			if round_num == 1 and _cue("taunt", 0.1):
				p2.say("intro")
			if _cue("round", 1.3 if round_num == 1 else 0.2):
				var final := banner == "FINAL ROUND"
				Sound.announce("final_round" if final else ("round1" if round_num == 1 else "round2"))
			if _cue("fight", 2.3):
				banner = "FIGHT!"
				Sound.announce("fight")
			if phase_time > 3.0:
				banner = ""
				phase = "fight"
				p1.locked = false
				p2.locked = false
		"fight":
			if _ultra_t >= 0.0:
				_process_ultra_cutin(real)
			else:
				clock = max(clock - real, 0.0)
				if clock <= 0.0:
					_end_round(_leader(), "TIME")
		"ko":
			var match_over: bool = wins[1] >= WINS_NEEDED or wins[2] >= WINS_NEEDED
			if _round_winner and _cue("celebrate", 1.0):
				_round_winner.celebrate()
			if _round_winner and _cue("win_line", 1.6):
				_round_winner.say("win2" if randf() < 0.5 else "win1")
			if match_over and _round_winner and _cue("result", 2.6):
				banner = _result_text(_round_winner)
				winner_text = ""
				if p2_cpu:
					Sound.announce("you_win" if _round_winner.player == 1 else "you_lose")
				else:
					Sound.announce("p%d_wins" % _round_winner.player)
			if phase_time > (5.2 if match_over else 3.6):
				if wins[1] >= WINS_NEEDED or wins[2] >= WINS_NEEDED:
					phase = "victory"
					phase_time = 0.0
					_cues.clear()
					_champ = p1 if wins[1] > wins[2] else p2
					banner = ""
					winner_text = ""
					Sound.music_volume(-18.0)
				else:
					round_num += 1
					_start_round()
		"victory":
			if _cue("tease", 1.4):
				_champ.say("tease")
			if _cue("groan", 4.2):
				_champ.opponent.say("groan")
			if phase_time > 1.5:
				if _pressed("start") or _pressed("p1_punch"):
					wins = {1: 0, 2: 0}
					round_num = 1
					_start_round()
				elif _pressed("p1_kick"):
					_enter_select()

	if phase in ["intro", "fight", "ko"] and _pressed("start"):
		_set_paused(true)

	for p in [1, 2]:
		_combo[p][1] = max(float(_combo[p][1]) - real, 0.0)

	shake = max(shake - real * 30.0, 0.0)
	world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	hud.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F2:
		p2_cpu = not p2_cpu
		if p2:
			p2.cpu = p2_cpu
			p2.cpu_level = cpu_level
	elif event.physical_keycode == KEY_ESCAPE:
		if paused:
			_set_paused(false)
		elif phase in ["intro", "fight", "ko"]:
			_set_paused(true)


# ---------------------------------------------------------------- pause

func _set_paused(on: bool) -> void:
	paused = on
	_help_open = false
	get_tree().paused = on
	Engine.time_scale = GAME_SPEED
	_pause_idx = 0
	if on:
		Sound.music_volume(-20.0)
	elif phase in ["intro", "fight"]:
		Sound.music_volume(-9.0)


func _process_pause() -> void:
	if _help_open:
		_process_help()
		return
	if _pressed("p1_up"):
		_pause_idx = (_pause_idx - 1 + PAUSE_ITEMS.size()) % PAUSE_ITEMS.size()
	elif _pressed("p1_down"):
		_pause_idx = (_pause_idx + 1) % PAUSE_ITEMS.size()
	elif _pressed("p1_kick"):
		_set_paused(false)
	elif _pressed("p1_punch") or _pressed("start"):
		match PAUSE_ITEMS[_pause_idx]:
			"RESUME":
				_set_paused(false)
			"HOW TO PLAY":
				_open_help()
			"CHARACTER SELECT":
				_enter_select()
			"TITLE SCREEN":
				_enter_title()


# ---------------------------------------------------------------- how to play

func _open_help() -> void:
	_help_open = true
	_help_page = 0
	Sound.sfx("punch", -6.0)


func _process_help() -> void:
	if _pressed("p1_left") or _pressed("p1_right") or _pressed("p2_left") or _pressed("p2_right"):
		_help_page = 1 - _help_page
		Sound.sfx("whoosh", -10.0)
	elif _pressed("p1_kick") or _pressed("p1_punch") or _pressed("start"):
		_help_open = false
		Sound.sfx("block", -6.0)


func _draw_help(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.01, 0.05, 0.98))
	_neon(font, Vector2(0, 80), "HOW TO PLAY", 56, Color(1, 0.3, 0.8))
	var tabs: Array[String] = ["CONTROLS", "MOVES"]
	for i in 2:
		var col := Color(1, 0.85, 0.3) if i == _help_page else Color(1, 1, 1, 0.35)
		hud.draw_string(font, Vector2(340 + i * 360, 130), tabs[i], HORIZONTAL_ALIGNMENT_CENTER, 240, 26, col)
	hud.draw_line(Vector2(340 + _help_page * 360, 140), Vector2(580 + _help_page * 360, 140), Color(1, 0.85, 0.3), 3.0)
	if _help_page == 0:
		var cols: Array[float] = [90.0, 470.0, 700.0, 930.0]
		var heads: Array[String] = ["", "PLAYER 1", "PLAYER 2", "JOYPAD"]
		for c in 4:
			hud.draw_string(font, Vector2(cols[c], 200), heads[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
					Color(0.3, 0.9, 1.0))
		for r in HELP_CONTROLS.size():
			var y := 250.0 + r * 56.0
			hud.draw_rect(Rect2(70, y - 32, 1140, 46), Color(1, 1, 1, 0.04 if r % 2 == 0 else 0.0))
			for c in 4:
				hud.draw_string(font, Vector2(cols[c], y), HELP_CONTROLS[r][c], HORIZONTAL_ALIGNMENT_LEFT,
						-1, 24 if c == 0 else 22, Color.WHITE if c == 0 else Color(1, 0.9, 0.6))
	else:
		for r in HELP_MOVES.size():
			var y := 195.0 + r * 46.0
			hud.draw_rect(Rect2(70, y - 30, 1140, 40), Color(1, 1, 1, 0.04 if r % 2 == 0 else 0.0))
			hud.draw_string(font, Vector2(90, y), HELP_MOVES[r][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
			hud.draw_string(font, Vector2(420, y), HELP_MOVES[r][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
					Color(1, 0.9, 0.6))
		var names := "Rustam:  Storm Fist  ·  Hurricane Kick  ·  Lightning Storm          Baba Sher:  Earthquake  ·  Avalanche  ·  Mountain Breaker"
		hud.draw_string(font, Vector2(0, 668), names, HORIZONTAL_ALIGNMENT_CENTER, 1280, 17, Color(0.3, 0.9, 1.0))
	hud.draw_string(font, Vector2(0, 706), "Left / Right: switch page      Punch or Kick: back",
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 16, Color(1, 1, 1, 0.55))


# ---------------------------------------------------------------- hits, KO

func _leader() -> Fighter:
	var a := float(p1.health) / p1.max_health
	var b := float(p2.health) / p2.max_health
	if is_equal_approx(a, b):
		return null
	return p1 if a > b else p2


func _on_ko(loser: Fighter) -> void:
	if phase == "fight":
		_hitstop(0.35)
		_end_round(loser.opponent, "K.O.")


func _end_round(winner: Fighter, why: String) -> void:
	phase = "ko"
	phase_time = 0.0
	p1.locked = true
	p2.locked = true
	_cues.clear()
	_round_winner = winner
	banner = why
	if winner and winner.health == winner.max_health:
		banner = "PERFECT!"
	if winner:
		wins[winner.player] += 1
		winner_text = "%s WINS THE ROUND" % winner.display_name
	else:
		winner_text = "DRAW"

	if why == "K.O.":
		Sound.announce("perfect" if banner == "PERFECT!" else "ko")
		Sound.sfx("crowd", -3.0, 0.0)
	elif winner == null:
		Sound.announce("draw")
	else:
		Sound.announce("time")
	Sound.music_volume(-15.0)


## "YOU WIN!" / "YOU LOSE!" against the CPU, "PLAYER 1 WINS!" in versus.
func _result_text(winner: Fighter) -> String:
	if p2_cpu:
		return "YOU WIN!" if winner.player == 1 else "YOU LOSE!"
	return "PLAYER %d WINS!" % winner.player


func _on_hit(target: Fighter, blocked: bool) -> void:
	shake = max(shake, 3.0 if blocked else 8.0)
	if blocked:
		_hitstop(0.04)
		return
	_hitstop(0.07 if target.combo < 3 else 0.1)
	if target.combo >= 2:
		var attacker := target.opponent.player
		_combo[attacker] = [target.combo, 1.4]


# ---------------------------------------------------------------- ultra cut-in

func _on_ultra(f: Fighter) -> void:
	if phase != "fight" or _ultra_t >= 0.0:
		f.meter = Fighter.METER_MAX     # refund: not allowed right now
		f.state = "idle"
		return
	_ultra_user = f
	_ultra_t = 0.0
	f.frozen = true
	f.opponent.frozen = true
	Sound.announce("ultra")
	Sound.sfx("ultra_charge", 0.0, 0.0)
	Sound.music_volume(-20.0)


func _process_ultra_cutin(real: float) -> void:
	_ultra_t += real
	var f := _ultra_user
	if f == null or not is_instance_valid(f):
		_ultra_t = -1.0
		return
	if f.frozen and _ultra_t > 1.15:
		f.frozen = false
		f.begin_ultra()
	# the opponent is released the moment the ultra's blast comes out
	if not f.frozen and (f.special_spawned or f.state != "ultra"):
		f.opponent.frozen = false
		_ultra_t = -1.0
		Sound.music_volume(-9.0)


## Freeze the action for a moment on impact, the way arcade fighters do.
func _hitstop(seconds: float) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.05 * GAME_SPEED
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hitstop_token and not paused:
		Engine.time_scale = GAME_SPEED


# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	match phase:
		"title":
			_draw_title(font)
			if _help_open:
				_draw_help(font)
			return
		"versus":
			_draw_versus(font)
			return
		"victory":
			_draw_victory(font)
			return
		"select":
			_draw_select(font)
			return
		"stage":
			_draw_stage_select(font)
			return
	var w := 1280.0
	_health_bar(Rect2(40, 30, 500, 28), p1, false)
	_health_bar(Rect2(w - 540, 30, 500, 28), p2, true)
	hud.draw_string(font, Vector2(40, 82), p1.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	var p2_name := p2.display_name + (" (CPU %s)" % LEVELS[cpu_level] if p2.cpu else "")
	hud.draw_string(font, Vector2(w - 540, 82), p2_name, HORIZONTAL_ALIGNMENT_RIGHT, 500, 22, Color.WHITE)
	_meter_bar(Rect2(40, 122, 300, 12), p1, false)
	_meter_bar(Rect2(w - 340, 122, 300, 12), p2, true)
	_win_marks(Vector2(40, 96), wins[1])
	_win_marks(Vector2(w - 40 - 22 * WINS_NEEDED, 96), wins[2])

	hud.draw_string(font, Vector2(w / 2 - 50, 64), "%02d" % int(ceil(clock)),
			HORIZONTAL_ALIGNMENT_CENTER, 100, 44, Color(1, 0.85, 0.3))

	# combo counters, on the attacker's side
	for p in [1, 2]:
		if float(_combo[p][1]) > 0.0:
			var a: float = clamp(float(_combo[p][1]) / 0.4, 0.0, 1.0)
			var x := 60.0 if p == 1 else w - 360.0
			_neon(font, Vector2(x, 190), "%d HITS" % int(_combo[p][0]), 46,
					Color(1.0, 0.25, 0.8, a), 300, HORIZONTAL_ALIGNMENT_LEFT if p == 1 else HORIZONTAL_ALIGNMENT_RIGHT)

	if banner != "":
		_outlined(font, Vector2(0, 330), banner, 84, Color(1, 0.8, 0.2))
	if winner_text != "":
		_outlined(font, Vector2(0, 400), winner_text, 28, Color.WHITE)

	if _ultra_t >= 0.0 and _ultra_user:
		_draw_ultra_cutin(font)

	if paused:
		_draw_pause(font)
		if _help_open:
			_draw_help(font)


func _draw_title(font: Font) -> void:
	# darken top and bottom, keep the fight on the right readable
	for i in 12:
		var a := 0.06 * (12 - i)
		hud.draw_rect(Rect2(0, i * 12, 1280, 12), Color(0.02, 0.0, 0.05, a))
		hud.draw_rect(Rect2(0, 720 - (i + 1) * 12, 1280, 12), Color(0.02, 0.0, 0.05, a))
	# left panel for the menu, slanted neon edge
	var panel := PackedVector2Array([Vector2(0, 0), Vector2(600, 0), Vector2(470, 720), Vector2(0, 720)])
	hud.draw_colored_polygon(panel, Color(0.03, 0.01, 0.08, 0.72))
	hud.draw_line(Vector2(600, 0), Vector2(470, 720), Color(1, 0.3, 0.75, 0.9), 4.0)
	hud.draw_line(Vector2(612, 0), Vector2(482, 720), Color(0.3, 0.9, 1.0, 0.5), 2.0)

	# logo slams in, then pulses
	var t := phase_time
	var slam: float = clamp(t / 0.35, 0.0, 1.0)
	var sc: float = lerp(2.6, 1.0, 1.0 - pow(1.0 - slam, 3.0)) + 0.025 * sin(t * 6.0) * float(slam >= 1.0)
	var logo_at := Vector2(335, 150)
	if _icon_tex:
		var isz := 112.0 * sc
		hud.draw_texture_rect(_icon_tex, Rect2(Vector2(84, 132) - Vector2(isz, isz) * 0.5, Vector2(isz, isz)),
				false, Color(1, 1, 1, slam))
	hud.draw_set_transform(logo_at, -0.06, Vector2(sc, sc))
	var fire: Array[Color] = [Color(1, 0.15, 0.05), Color(1, 0.45, 0.05), Color(1, 0.85, 0.2)]
	for k in 3:
		var o := Vector2(0, (2 - k) * 4)
		for d in [Vector2(-4, 0), Vector2(4, 0), Vector2(0, -4), Vector2(0, 4)]:
			hud.draw_string(font, Vector2(-300, 70) + o + d, GAME_TITLE, HORIZONTAL_ALIGNMENT_CENTER, 600, 104,
					Color(0, 0, 0, 0.6 * slam))
		hud.draw_string(font, Vector2(-300, 70) + o, GAME_TITLE, HORIZONTAL_ALIGNMENT_CENTER, 600, 104,
				Color(fire[k].r, fire[k].g, fire[k].b, slam))
	hud.draw_string(font, Vector2(-300, 70), GAME_TITLE, HORIZONTAL_ALIGNMENT_CENTER, 600, 104,
			Color(1, 1, 0.85, 0.35 * slam))
	hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if slam >= 1.0 and t < 0.6:
		hud.draw_rect(Rect2(0, 0, 1280, 720), Color(1, 0.8, 0.5, (0.6 - t) * 1.5))
	_neon(font, Vector2(0, 268), "STREET FIGHTS  ·  KARACHI  VS  HUNZA", 20, Color(0.3, 0.9, 1.0, 0.9), 580)

	for i in TITLE_ITEMS.size():
		var label: String = TITLE_ITEMS[i]
		if label == "CPU":
			label = "CPU LEVEL:  < %s >" % LEVELS[cpu_level]
		var sel := i == _menu_idx
		var y := 350.0 + i * 54.0
		var x := 60.0 - i * 9.0      # follow the slanted panel edge
		if sel:
			var bar := PackedVector2Array([Vector2(x - 20, y - 36), Vector2(x + 440, y - 36),
					Vector2(x + 425, y + 12), Vector2(x - 35, y + 12)])
			hud.draw_colored_polygon(bar, Color(1, 0.3, 0.75, 0.25 + 0.1 * sin(t * 8.0)))
			_neon(font, Vector2(x, y), "» " + label, 34, Color(1, 0.95, 0.6), 440, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			hud.draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, 440, 28, Color(0.78, 0.78, 0.9))
	var blink := 0.45 + 0.35 * sin(t * 4.0)
	hud.draw_string(font, Vector2(30, 680), "↑/↓ choose    ←/→ change    Punch / Enter: select",
			HORIZONTAL_ALIGNMENT_LEFT, 460, 17, Color(1, 1, 1, blink + 0.2))
	hud.draw_string(font, Vector2(30, 708), "a QuietByte game", HORIZONTAL_ALIGNMENT_LEFT, 460, 14, Color(1, 1, 1, 0.4))


## Where each fighter's face sits in his call-out close-up (fractions of the image), for square tiles.
const FACE_FOCUS := {"rustam": Vector2(0.6, 0.38), "babasher": Vector2(0.6, 0.38), "tiago": Vector2(0.62, 0.3)}
const SELECT_COLS := 2
const TILE := 150.0


func _tile_rect(i: int) -> Rect2:
	var n := Characters.ROSTER.size()
	var rows := int(ceil(float(n) / SELECT_COLS))
	var gap := 14.0
	var w := SELECT_COLS * TILE + (SELECT_COLS - 1) * gap
	var h := rows * TILE + (rows - 1) * gap
	var x0 := 640.0 - w / 2.0
	var y0 := 400.0 - h / 2.0
	return Rect2(x0 + (i % SELECT_COLS) * (TILE + gap), y0 + (i / SELECT_COLS) * (TILE + gap), TILE, TILE)


## Square crop of a fighter's close-up around his face.
func _face_tile(id: String, r: Rect2, tint := Color.WHITE) -> void:
	var tex: Texture2D = _portraits.get(id, {}).get("callout")
	if tex == null:
		_portrait(id, "callout", r, false, tint)
		return
	var ts := tex.get_size()
	var side: float = ts.y * 0.78
	var f: Vector2 = FACE_FOCUS.get(id, Vector2(0.5, 0.4))
	var c := Vector2(ts.x * f.x, ts.y * f.y)
	var src := Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
	src.position.x = clamp(src.position.x, 0.0, ts.x - side)
	src.position.y = clamp(src.position.y, 0.0, ts.y - side)
	hud.draw_texture_rect_region(tex, r, src, tint)


func _draw_facts(font: Font, id: String, x: float, p: int) -> void:
	var def := Characters.get_def(id)
	var col := Color(0.3, 0.6, 1.0) if p == 1 else Color(1.0, 0.35, 0.35)
	var panel := Rect2(x, 120, 390, 560)
	hud.draw_rect(panel, Color(0.06, 0.03, 0.12, 0.88))
	hud.draw_rect(panel, Color(col.r, col.g, col.b, 0.8), false, 3.0)
	# fighter, full body, standing in the panel
	var frames: SpriteFrames = _sprite_cache[id]["frames"]
	var tex := frames.get_frame_texture("idle", 0)
	if tex:
		# crop the frame to the body: the sprite cells have lots of empty space
		var anchor: Vector2 = _sprite_cache[id]["anchor"]
		var bh: float = _sprite_cache[id]["body_height"]
		var src := Rect2(anchor.x - bh * 0.6, anchor.y - bh * 1.08, bh * 1.2, bh * 1.12)
		var sc: float = 235.0 / src.size.y
		var size := src.size * sc
		var pos := Vector2(x + (390 - size.x) / 2.0, 140)
		if p == 2:
			hud.draw_set_transform(Vector2(pos.x + size.x, pos.y), 0.0, Vector2(-1, 1))
			hud.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src)
			hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			hud.draw_texture_rect_region(tex, Rect2(pos, size), src)
	var tag := ("%dP" % p) + (" CPU" if p == 2 and p2_cpu else "") + ("   READY" if _locked_in[p] else "")
	hud.draw_string(font, Vector2(x + 14, 148), tag, HORIZONTAL_ALIGNMENT_LEFT, 360, 18, col)
	var y := 392.0
	hud.draw_string(font, Vector2(x, y), def["name"], HORIZONTAL_ALIGNMENT_CENTER, 390, 34, Color.WHITE)
	y += 26
	hud.draw_string(font, Vector2(x, y), "%s  ·  %s" % [def.get("country", ""), str(def["from"]).to_upper()],
			HORIZONTAL_ALIGNMENT_CENTER, 390, 16, Color(1, 0.85, 0.4))
	y += 24
	hud.draw_string(font, Vector2(x, y), "%s   ·   Age %s   ·   %s" % [def.get("style", ""), def.get("age", "?"),
			def.get("height", "")], HORIZONTAL_ALIGNMENT_CENTER, 390, 15, Color(0.85, 0.85, 0.95))
	y += 14
	var stats: Dictionary = def.get("stats", {})
	for k in stats:
		y += 22
		hud.draw_string(font, Vector2(x + 24, y), str(k), HORIZONTAL_ALIGNMENT_LEFT, 100, 14, Color(0.8, 0.8, 0.9))
		for b in 5:
			var on: bool = b < int(stats[k])
			hud.draw_rect(Rect2(x + 120 + b * 48, y - 12, 42, 12),
					Color(col.r, col.g, col.b, 0.95) if on else Color(1, 1, 1, 0.12))
	y += 30
	hud.draw_string(font, Vector2(x + 24, y), "MOVES", HORIZONTAL_ALIGNMENT_LEFT, 100, 14, Color(0.8, 0.8, 0.9))
	hud.draw_multiline_string(font, Vector2(x + 120, y), "%s  ·  %s  ·  %s" % [def["special_name"],
			def.get("kick_special_name", ""), def.get("ultra_name", "")], HORIZONTAL_ALIGNMENT_LEFT, 250, 13, 2,
			Color(0.4, 0.9, 1.0))
	y += 40
	hud.draw_multiline_string(font, Vector2(x + 24, y), str(def.get("fact", "")), HORIZONTAL_ALIGNMENT_LEFT,
			342, 14, 3, Color(1, 1, 1, 0.75))


func _draw_select(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.03, 0.1, 0.78))
	_neon(font, Vector2(0, 76), "CHOOSE YOUR FIGHTER", 50, Color(1, 0.3, 0.8))
	_draw_facts(font, Characters.ROSTER[_cursor[1]], 20, 1)
	_draw_facts(font, Characters.ROSTER[_cursor[2]], 870, 2)
	for i in Characters.ROSTER.size():
		var id: String = Characters.ROSTER[i]
		var r := _tile_rect(i)
		hud.draw_rect(r.grow(3), Color(0, 0, 0, 0.8))
		_face_tile(id, r)
		hud.draw_rect(Rect2(r.position.x, r.end.y - 24, r.size.x, 24), Color(0, 0, 0, 0.65))
		hud.draw_string(font, Vector2(r.position.x, r.end.y - 6), Characters.get_def(id)["name"],
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color.WHITE)
		for p in [1, 2]:
			if _cursor[p] != i:
				continue
			var col := Color(0.3, 0.6, 1.0) if p == 1 else Color(1.0, 0.3, 0.3)
			var pulse := 0.6 + 0.4 * sin(phase_time * 8.0)
			var g := 4.0 if p == 1 else 9.0
			hud.draw_rect(r.grow(g), Color(col.r, col.g, col.b, 1.0 if _locked_in[p] else pulse), false,
					5.0 if _locked_in[p] else 3.0)
			hud.draw_string(font, Vector2(r.position.x + (4 if p == 1 else r.size.x - 34), r.position.y + 18),
					"%dP" % p, HORIZONTAL_ALIGNMENT_LEFT, 30, 15, col)
	if _locked_in[1] and _locked_in[2]:
		_neon(font, Vector2(0, 640), "VS", 56, Color(1, 0.85, 0.3))
	_outlined(font, Vector2(0, 706), "Arrows choose    Punch / Enter: select    Kick: back    F2: toggle CPU",
			16, Color(1, 1, 1, 0.7))


func _draw_stage_select(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 140), Color(0.03, 0.01, 0.08, 0.75))
	hud.draw_rect(Rect2(0, 600, 1280, 120), Color(0.03, 0.01, 0.08, 0.75))
	_neon(font, Vector2(0, 80), "CHOOSE STAGE", 52, Color(0.3, 0.9, 1.0))
	_neon(font, Vector2(0, 660), "<   %s   >" % STAGES[stage_idx]["name"], 40, Color(1, 0.85, 0.3))
	_outlined(font, Vector2(0, 705), "←/→ change    Punch / Enter: fight!    Kick: back", 18, Color(1, 1, 1, 0.75))


func _draw_pause(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.6))
	_neon(font, Vector2(0, 250), "PAUSED", 80, Color(0.3, 0.9, 1.0))
	for i in PAUSE_ITEMS.size():
		var sel := i == _pause_idx
		var label: String = PAUSE_ITEMS[i]
		var y := 350.0 + i * 54.0
		if sel:
			_neon(font, Vector2(0, y), "»  " + label + "  «", 34, Color(1, 0.3, 0.8))
		else:
			hud.draw_string(font, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, Color(0.8, 0.8, 0.9))


func _meter_bar(r: Rect2, f: Fighter, right_side: bool) -> void:
	hud.draw_rect(r.grow(2), Color(0, 0, 0, 0.7))
	var frac: float = f.meter / Fighter.METER_MAX
	var fill := Rect2(r.position, Vector2(r.size.x * frac, r.size.y))
	if right_side:
		fill.position.x = r.end.x - fill.size.x
	var full := frac >= 1.0
	var pulse := 0.6 + 0.4 * sin(phase_time * 10.0)
	var col := Color(0.3, 0.9, 1.0, pulse) if full else Color(0.2, 0.55, 1.0)
	hud.draw_rect(fill, col)
	if full:
		var font := ThemeDB.fallback_font
		var label := "ULTRA READY  [ I / Y ]" if f.player == 1 else "ULTRA READY  [ Num4 / Y ]"
		hud.draw_string(font, Vector2(r.position.x, r.end.y + 18), label,
				HORIZONTAL_ALIGNMENT_RIGHT if right_side else HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 14,
				Color(0.4, 0.95, 1.0, pulse))


## Which way each close-up faces as drawn: -1 left, 1 right.
const PORTRAIT_FACING := {"rustam_callout": -1, "babasher_callout": -1,
		"rustam_win": -1, "babasher_win": 1, "rustam_beaten": 1, "babasher_beaten": -1,
		"tiago_callout": -1, "tiago_win": 1, "tiago_beaten": -1}


## True if the close-up must be mirrored so it faces `want` (-1 left, 1 right).
func _mirror_for(id: String, kind: String, want: int) -> bool:
	return int(PORTRAIT_FACING.get("%s_%s" % [id, kind], 1)) != want


## A portrait panel: the close-up image cropped to fill `r`, optionally mirrored and tinted.
func _portrait(id: String, kind: String, r: Rect2, mirror: bool, tint := Color.WHITE) -> void:
	var tex: Texture2D = _portraits.get(id, {}).get(kind)
	if tex == null:
		# fall back to the idle sprite if the close-up is missing
		var frames: SpriteFrames = _sprite_cache[id]["frames"]
		tex = frames.get_frame_texture("idle", 0)
	if tex == null:
		return
	var ts := tex.get_size()
	var s: float = max(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / s
	var src := Rect2((ts - src_size) * 0.5, src_size)
	if mirror:
		# flip with a transform: a negative-width rect draws nothing
		hud.draw_set_transform(Vector2(r.position.x + r.size.x, r.position.y), 0.0, Vector2(-1, 1))
		hud.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, r.size), src, tint)
		hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		hud.draw_texture_rect_region(tex, r, src, tint)


func _speech(font: Font, at: Vector2, text: String, width: float, col: Color) -> void:
	var box := Rect2(at - Vector2(12, 34), Vector2(width + 24, 52))
	hud.draw_rect(box, Color(0, 0, 0, 0.75))
	hud.draw_rect(box, col, false, 3.0)
	hud.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 22, Color.WHITE)


func _draw_versus(font: Font) -> void:
	var id1 := _id(1)
	var id2 := _id(2)
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.02, 0.08, 1.0))
	var slide: float = clamp(phase_time / 0.35, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - slide, 3.0)
	# P1 faces right, P2 faces left. The close-ups were drawn Rustam facing right and
	# Baba Sher facing left, so mirror whichever one is on the wrong side.
	var left := Rect2(-640.0 + 640.0 * eased, 0, 640, 720)
	var right := Rect2(1280.0 - 640.0 * eased, 0, 640, 720)
	_portrait(id1, "callout", left, _mirror_for(id1, "callout", 1))
	_portrait(id2, "callout", right, _mirror_for(id2, "callout", -1),
			Color(0.8, 0.9, 1.2) if id1 == id2 else Color.WHITE)
	# neon split line
	hud.draw_line(Vector2(640, 0), Vector2(640, 720), Color(1, 0.3, 0.8, 0.9), 6.0)
	if phase_time > 0.45:
		var pop: float = clamp((phase_time - 0.45) / 0.15, 0.0, 1.0)
		_neon(font, Vector2(0, 400), "VS", int(lerp(260.0, 150.0, pop)), Color(1, 0.85, 0.2))
	_outlined(font, Vector2(-320, 680), Characters.get_def(id1)["name"], 46, Color(0.4, 0.75, 1.0))
	_outlined(font, Vector2(320, 680), Characters.get_def(id2)["name"], 46, Color(1.0, 0.4, 0.4))
	if phase_time > 2.0 and phase_time < 5.0:
		_speech(font, Vector2(40, 120), Characters.get_def(id1)["callout_text"], 560, Color(0.4, 0.75, 1.0))
	if phase_time > 5.0:
		_speech(font, Vector2(680, 120), Characters.get_def(id2)["callout_text"], 560, Color(1.0, 0.4, 0.4))
	hud.draw_string(font, Vector2(0, 712), "Punch / Enter to skip", HORIZONTAL_ALIGNMENT_CENTER,
			1280, 14, Color(1, 1, 1, 0.45))


func _draw_victory(font: Font) -> void:
	if _champ == null:
		return
	var loser := _champ.opponent
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.02, 0.06, 0.92))
	var champ_left := _champ.player == 1
	var big := Rect2(0 if champ_left else 480, 0, 800, 720)
	var small := Rect2(860 if champ_left else 40, 150, 380, 420)
	# the winner faces the loser's panel
	_portrait(_champ.char_id, "win", big, _mirror_for(_champ.char_id, "win", 1 if champ_left else -1))
	hud.draw_rect(small.grow(4), Color(0.3, 0.4, 0.6, 0.9), false, 4.0)
	_portrait(loser.char_id, "beaten", small,
			_mirror_for(loser.char_id, "beaten", -1 if champ_left else 1), Color(0.75, 0.8, 0.95))
	var name_x := -240.0 if champ_left else 240.0
	# dark band so the title reads over the close-up
	hud.draw_rect(Rect2(big.position.x, 0, big.size.x, 150), Color(0, 0, 0, 0.55))
	_neon(font, Vector2(name_x, 70), _result_text(_champ), 64, Color(1, 0.85, 0.2))
	_outlined(font, Vector2(name_x, 120), "%s WINS THE DANGAL" % _champ.display_name, 26, Color.WHITE)
	if phase_time > 1.4:
		var sx := 40.0 if champ_left else 520.0
		_speech(font, Vector2(sx, 640), _champ.def["tease_text"], 720, Color(1, 0.8, 0.2))
	if phase_time > 4.2:
		_speech(font, Vector2(small.position.x - 10, small.end.y + 48), loser.def["groan_text"],
				400, Color(0.5, 0.6, 0.8))
	if phase_time > 1.5:
		hud.draw_string(font, Vector2(0, 712), "Enter / Start: rematch      Kick: character select",
				HORIZONTAL_ALIGNMENT_CENTER, 1280, 16, Color(1, 1, 1, 0.7))


func _draw_ultra_cutin(font: Font) -> void:
	var f := _ultra_user
	var t := _ultra_t
	var a: float = clamp(t / 0.15, 0.0, 1.0) * clamp((1.25 - t) / 0.2, 0.0, 1.0)
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.55 * a))
	# diagonal band with the fighter's close-up sweeping across
	var band := Rect2(0, 200, 1280, 280)
	hud.draw_rect(band, Color(0.05, 0.02, 0.1, 0.85 * a))
	var dir := 1.0 if f.player == 1 else -1.0
	var x: float = lerp(-700.0, 300.0, clamp(t / 0.35, 0.0, 1.0)) if dir > 0 \
			else lerp(1980.0, 980.0, clamp(t / 0.35, 0.0, 1.0)) - 700.0
	_portrait(f.char_id, "callout", Rect2(x, 200, 700, 280),
			_mirror_for(f.char_id, "callout", 1 if dir > 0 else -1), Color(1, 1, 1, a))
	hud.draw_line(Vector2(0, 200), Vector2(1280, 200), Color(0.3, 0.9, 1.0, a), 4.0)
	hud.draw_line(Vector2(0, 480), Vector2(1280, 480), Color(0.3, 0.9, 1.0, a), 4.0)
	_neon(font, Vector2(0, 560), str(f.def.get("ultra_name", "ULTRA")), 72, Color(0.4, 0.95, 1.0, a))


func _health_bar(r: Rect2, f: Fighter, right_side: bool) -> void:
	hud.draw_rect(r.grow(3), Color(0, 0, 0, 0.7))
	hud.draw_rect(r, Color(0.45, 0.05, 0.05))
	var frac := float(f.health) / f.max_health
	var fill := Rect2(r.position, Vector2(r.size.x * frac, r.size.y))
	if right_side:
		fill.position.x = r.end.x - fill.size.x
	var col := Color(1, 0.8, 0.15) if frac > 0.3 else Color(1, 0.3, 0.1)
	hud.draw_rect(fill, col)


func _win_marks(at: Vector2, n: int) -> void:
	for i in WINS_NEEDED:
		var c := Color(1, 0.8, 0.2) if i < n else Color(0.2, 0.2, 0.2, 0.8)
		hud.draw_circle(at + Vector2(i * 22 + 8, 8), 8, c)


func _outlined(font: Font, at: Vector2, text: String, size: int, col: Color) -> void:
	for o in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
		hud.draw_string(font, at + o, text, HORIZONTAL_ALIGNMENT_CENTER, 1280, size, Color.BLACK)
	hud.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 1280, size, col)


## Neon-sign text: soft coloured glow layers under a bright core.
func _neon(font: Font, at: Vector2, text: String, size: int, col: Color,
		width := 1280.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var glow := Color(col.r, col.g, col.b, col.a * 0.18)
	for r in [6.0, 4.0, 2.0]:
		for o in [Vector2(-r, 0), Vector2(r, 0), Vector2(0, -r), Vector2(0, r)]:
			hud.draw_string(font, at + o, text, align, width, size, glow)
	hud.draw_string(font, at, text, align, width, size, col)
	hud.draw_string(font, at, text, align, width, size, Color(1, 1, 1, col.a * 0.35))
