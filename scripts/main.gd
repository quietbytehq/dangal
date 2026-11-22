extends Node2D
## NEON KNUCKLE — game flow:
## title -> character select -> stage select -> rounds (intro, fight, ko) -> match over.
## Also: pause menu, hit-stop, combo counter, CPU difficulty.

const GAME_TITLE := "NEON KNUCKLE"
const FLOOR_Y := 640.0
const ROUND_TIME := 99.0
const WINS_NEEDED := 2
const STAGES := [
	{"name": "KARACHI ROOFTOP", "image": "res://assets/stage/karachi_rooftop.png", "music": "stage_karachi",
		"props": [["crate", 105.0], ["matka", 235.0], ["drum", 1165.0], ["crate", 1045.0]]},
	{"name": "HUNZA VALLEY", "image": "res://assets/stage/hunza_valley.png", "music": "stage_hunza",
		"props": [["firewood", 120.0], ["basket", 250.0], ["copper_pot", 1170.0], ["basket", 1050.0]]},
]
const LEVELS := ["EASY", "NORMAL", "HARD"]
const TITLE_ITEMS := ["ARCADE  (vs CPU)", "VERSUS  (2 players)", "CPU", "QUIT"]
const PAUSE_ITEMS := ["RESUME", "CHARACTER SELECT", "TITLE SCREEN"]

var p1: Fighter
var p2: Fighter
var phase := "title"   # title, select, stage, intro, fight, ko, match_over
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
	process_mode = Node.PROCESS_MODE_ALWAYS     # menus keep working while paused
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	bg = Sprite2D.new()
	bg.centered = false
	bg.z_index = -10          # behind props (-1) and fighters (0)
	world.add_child(bg)
	for st in STAGES:
		var path: String = st["image"]
		_stage_tex[path] = load(path) if ResourceLoader.exists(path) else null
	_set_stage(0)

	for id in Characters.ROSTER:
		var def := Characters.get_def(id)
		_sprite_cache[id] = SpriteLibrary.load_character(def["sprites"], def["json"])

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)

	_enter_title()


func _set_stage(i: int) -> void:
	stage_idx = i
	var tex: Texture2D = _stage_tex.get(STAGES[i]["image"])
	if tex == null:
		tex = _stage_tex.get(STAGES[0]["image"])
	bg.texture = tex
	if tex:
		bg.scale = Vector2(1280.0, 720.0) / tex.get_size()


func _pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)


# ---------------------------------------------------------------- title

func _enter_title() -> void:
	_clear_match()
	phase = "title"
	phase_time = 0.0
	_menu_idx = 0
	_set_stage(randi() % STAGES.size())
	Sound.play_music(STAGES[stage_idx]["music"])
	Sound.music_volume(-12.0)


func _process_title() -> void:
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
			"CPU":
				cpu_level = (cpu_level + 1) % LEVELS.size()
			"QUIT":
				get_tree().quit()


# ---------------------------------------------------------------- character select

func _clear_match() -> void:
	_set_paused(false)
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
			clock = max(clock - delta, 0.0)
			if clock <= 0.0:
				_end_round(_leader(), "TIME")
		"ko":
			if _round_winner and _cue("win_line", 1.6):
				_round_winner.say("win2" if randf() < 0.5 else "win1")
			if phase_time > 3.6:
				if wins[1] >= WINS_NEEDED or wins[2] >= WINS_NEEDED:
					phase = "match_over"
					phase_time = 0.0
					_cues.clear()
					var champ := p1 if wins[1] > wins[2] else p2
					banner = "%s WINS!" % champ.display_name
					winner_text = "Enter / Start: rematch      Kick: character select"
					Sound.announce("p%d_wins" % champ.player)
					Sound.music_volume(-16.0)
				else:
					round_num += 1
					_start_round()
		"match_over":
			if _cue("champ_line", 1.6):
				var champ := p1 if wins[1] > wins[2] else p2
				champ.say("win1")
			if phase_time > 0.6:
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
	get_tree().paused = on
	Engine.time_scale = 1.0
	_pause_idx = 0
	if on:
		Sound.music_volume(-20.0)
	elif phase in ["intro", "fight"]:
		Sound.music_volume(-9.0)


func _process_pause() -> void:
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
			"CHARACTER SELECT":
				_enter_select()
			"TITLE SCREEN":
				_enter_title()


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


func _on_hit(target: Fighter, blocked: bool) -> void:
	shake = max(shake, 3.0 if blocked else 8.0)
	if blocked:
		_hitstop(0.04)
		return
	_hitstop(0.07 if target.combo < 3 else 0.1)
	if target.combo >= 2:
		var attacker := target.opponent.player
		_combo[attacker] = [target.combo, 1.4]


## Freeze the action for a moment on impact, the way arcade fighters do.
func _hitstop(seconds: float) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hitstop_token and not paused:
		Engine.time_scale = 1.0


# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	match phase:
		"title":
			_draw_title(font)
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

	if paused:
		_draw_pause(font)


func _draw_title(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.01, 0.08, 0.78))
	# flickering neon sign
	var flick := 1.0 if fmod(phase_time, 4.0) > 0.12 or fmod(phase_time * 30.0, 2.0) > 1.0 else 0.35
	_neon(font, Vector2(0, 230), GAME_TITLE, 110, Color(1.0, 0.2, 0.75, flick))
	_neon(font, Vector2(0, 290), "KARACHI  VS  HUNZA", 26, Color(0.3, 0.9, 1.0, 0.9))

	for i in TITLE_ITEMS.size():
		var label: String = TITLE_ITEMS[i]
		if label == "CPU":
			label = "CPU LEVEL:  < %s >" % LEVELS[cpu_level]
		var sel := i == _menu_idx
		var col := Color(0.3, 0.95, 1.0) if sel else Color(0.75, 0.75, 0.85)
		var y := 390.0 + i * 52.0
		if sel:
			_neon(font, Vector2(0, y), "»  " + label + "  «", 34, col)
		else:
			hud.draw_string(font, Vector2(0, y), label, HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, col)
	_outlined(font, Vector2(0, 680), "↑/↓ choose    ←/→ change    Punch / Enter: select", 18, Color(1, 1, 1, 0.7))
	hud.draw_string(font, Vector2(0, 708), "a QuietByte game", HORIZONTAL_ALIGNMENT_CENTER, 1280, 14, Color(1, 1, 1, 0.4))


func _draw_select(font: Font) -> void:
	hud.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.03, 0.1, 0.72))
	_neon(font, Vector2(0, 86), "CHOOSE YOUR FIGHTER", 52, Color(1, 0.3, 0.8))

	var n := Characters.ROSTER.size()
	var card := Vector2(360, 440)
	var gap := 60.0
	var x0 := (1280.0 - (n * card.x + (n - 1) * gap)) / 2.0
	for i in n:
		var id: String = Characters.ROSTER[i]
		var def := Characters.get_def(id)
		var r := Rect2(x0 + i * (card.x + gap), 130, card.x, card.y)
		hud.draw_rect(r, Color(0.12, 0.08, 0.2, 0.9))
		# portrait: first idle frame, scaled to fit the card
		var frames: SpriteFrames = _sprite_cache[id]["frames"]
		var tex := frames.get_frame_texture("idle", 0)
		if tex:
			var ts := tex.get_size()
			var s: float = min((card.x - 20) / ts.x, (card.y - 90) / ts.y)
			var size := ts * s
			hud.draw_texture_rect(tex, Rect2(r.position + Vector2((card.x - size.x) / 2, 10), size), false)
		hud.draw_string(font, r.position + Vector2(0, card.y - 50), def["name"],
				HORIZONTAL_ALIGNMENT_CENTER, card.x, 34, Color.WHITE)
		hud.draw_string(font, r.position + Vector2(0, card.y - 18), def["from"],
				HORIZONTAL_ALIGNMENT_CENTER, card.x, 20, Color(0.8, 0.8, 0.9))

		for p in [1, 2]:
			if _cursor[p] != i:
				continue
			var col := Color(0.3, 0.6, 1.0) if p == 1 else Color(1.0, 0.3, 0.3)
			var grow := 6.0 if p == 1 else 12.0
			var width := 6.0 if _locked_in[p] else 3.0
			hud.draw_rect(r.grow(grow), col, false, width)
			var tag := ("%dP" % p) + (" CPU" if p == 2 and p2_cpu else "") + (" READY" if _locked_in[p] else "")
			var tx := r.position.x + (6.0 if p == 1 else card.x - 170.0)
			hud.draw_string(font, Vector2(tx, r.position.y - 14), tag,
					HORIZONTAL_ALIGNMENT_LEFT if p == 1 else HORIZONTAL_ALIGNMENT_RIGHT, 164, 22, col)

	if _locked_in[1] and _locked_in[2]:
		_neon(font, Vector2(0, 640), "%s  VS  %s" % [
				Characters.get_def(Characters.ROSTER[_cursor[1]])["name"],
				Characters.get_def(Characters.ROSTER[_cursor[2]])["name"]], 48, Color(1, 0.85, 0.3))
	else:
		_outlined(font, Vector2(0, 640), "←/→ choose    Punch / Enter: select    Kick: back    F2: toggle CPU",
				20, Color(1, 1, 1, 0.85))
	_outlined(font, Vector2(0, 690),
			"P1: A/D move  W jump  S crouch  J punch  K kick  L special   |   P2: arrows + numpad 1/2/3   |   joypads work too",
			15, Color(1, 1, 1, 0.6))


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
