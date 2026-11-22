class_name Fighter
extends Node2D
## One fighter: movement, attacks, hitboxes, blocking, damage, and a simple CPU brain.
## The node's position is the point between the fighter's feet.

signal health_changed(fighter: Fighter, value: int)
signal knocked_out(fighter: Fighter)
signal landed_hit(fighter: Fighter, blocked: bool)
signal quake(amount: float)

const SPECIAL_COOLDOWN := 1.4
const MOTION_WINDOW := 0.45   # seconds to finish down, down-forward, forward + punch
const JUMP_TIME := 1.0
const HIT_TIME := 0.45
const CROUCH_POSE := 0.22   # where in the crouch-kick clip the crouch pose sits

# Filled from Characters.DATA in setup()
var char_id := "rustam"
var display_name := "RUSTAM"
var max_health := 1000
var walk_speed := 240.0
var attacks := {}
var special_kind := "fireball"
var special_time := 0.95
var special_release := 0.5
var voice_id := "rustam"
var voice_pitch := 1.0

var player := 1
var cpu := false
var cpu_level := 1        # 0 easy, 1 normal, 2 hard
var combo := 0            # hits taken in the current combo
var opponent: Fighter
var health := 1000
var facing := 1
var state := "idle"
var vel := Vector2.ZERO
var slide := 0.0
var floor_y := 640.0
var bounds := Vector2(70.0, 1210.0)
var locked := true
var hit_landed := false
var special_spawned := false
var special_cd := 0.0
var flash := 0.0
var H := 300.0

var _counts := {}
var _fps := 12.0
var _visual: Node2D
var _sprite: AnimatedSprite2D
var _dir_log: Array = []      # [[token, time], ...]
var _last_dir := ""
var _time := 0.0

# CPU brain state
var _cpu_held := {}
var _cpu_pressed := {}
var _cpu_timer := 0.0


func setup(p: int, id: String, data: Dictionary, tint: Color, pitch := 1.0) -> void:
	player = p
	char_id = id
	var def := Characters.get_def(id)
	display_name = def["name"]
	max_health = def["health"]
	health = max_health
	walk_speed = def["walk_speed"]
	attacks = def["attacks"]
	special_kind = def["special"]
	special_time = def["special_time"]
	special_release = def["special_release"]
	voice_id = def["voice"]
	voice_pitch = pitch
	H = data["body_height"]
	_counts = data["counts"]
	_fps = data["fps"]
	_visual = Node2D.new()
	add_child(_visual)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = data["frames"]
	_sprite.centered = false
	_sprite.offset = -data["anchor"]
	_sprite.self_modulate = tint
	_visual.add_child(_sprite)
	_sprite.animation_finished.connect(_on_animation_finished)
	_play("idle")


func reset_for_round(x: float) -> void:
	position = Vector2(x, floor_y)
	health = max_health
	vel = Vector2.ZERO
	slide = 0.0
	special_cd = 0.0
	state = "idle"
	locked = true
	_play("idle")
	health_changed.emit(self, health)


# ---------------------------------------------------------------- input layer

func _held(a: String) -> bool:
	if cpu:
		return _cpu_held.get(a, false)
	return Input.is_action_pressed("p%d_%s" % [player, a])


func _pressed(a: String) -> bool:
	if cpu:
		return _cpu_pressed.get(a, false)
	return Input.is_action_just_pressed("p%d_%s" % [player, a])


func _forward() -> String:
	return "right" if facing == 1 else "left"


func _back() -> String:
	return "left" if facing == 1 else "right"


func _track_motion() -> void:
	var down := _held("down")
	var fwd := _held(_forward())
	var token := "df" if (down and fwd) else ("d" if down else ("f" if fwd else ""))
	if token != _last_dir and token != "":
		_dir_log.append([token, _time])
	_last_dir = token
	while _dir_log.size() > 0 and _time - _dir_log[0][1] > MOTION_WINDOW:
		_dir_log.pop_front()


func _did_quarter_circle() -> bool:
	var seq := []
	for e in _dir_log:
		seq.append(e[0])
	var need := ["d", "df", "f"]
	var i := 0
	for tok in seq:
		if i < need.size() and tok == need[i]:
			i += 1
	return i == need.size()


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	_time += delta
	special_cd = max(special_cd - delta, 0.0)
	if cpu and not locked:
		_cpu_think(delta)
	_track_motion()

	match state:
		"idle", "walk", "crouch":
			_grounded(delta)
		"jump":
			_airborne(delta)
		"jab", "roundhouse", "crouch_kick":
			_attacking()
		"special":
			_special()
		"hit", "ko", "block":
			pass

	# knockback slide
	if slide != 0.0:
		position.x += slide * delta
		slide = move_toward(slide, 0.0, 1400.0 * delta)
	_separate_from_opponent()
	position.x = clamp(position.x, bounds.x, bounds.y)

	flash = max(flash - delta, 0.0)
	_sprite.modulate = Color(2.2, 2.2, 2.2) if flash > 0.0 else Color.WHITE
	_cpu_pressed.clear()


func _grounded(delta: float) -> void:
	if opponent:
		facing = 1 if opponent.position.x >= position.x else -1
		_visual.scale.x = facing
	if locked:
		_set_idle()
		return

	if _pressed("special") and special_cd <= 0.0:
		_start_special()
	elif _pressed("punch"):
		if _did_quarter_circle() and special_cd <= 0.0:
			_start_special()
		elif _held("down"):
			_start_attack("crouch_kick")
		else:
			_start_attack("jab")
	elif _pressed("kick"):
		_start_attack("crouch_kick" if _held("down") else "roundhouse")
	elif _held("up"):
		# The jump clip already contains the vertical motion, so the node stays
		# on the floor and only drifts sideways. The hurtbox follows the arc.
		var dir := int(_held("right")) - int(_held("left"))
		vel = Vector2(dir * walk_speed * 1.1, 0.0)
		state = "jump"
		_play("jump", _length("jump") / JUMP_TIME)
	elif _held("down"):
		if state != "crouch":
			state = "crouch"
			_sprite.play("crouch_kick")
			_sprite.pause()
			_sprite.frame = int(_counts["crouch_kick"] * CROUCH_POSE)
	else:
		var dir := int(_held("right")) - int(_held("left"))
		if dir != 0:
			var backwards := dir != facing
			position.x += dir * walk_speed * (0.75 if backwards else 1.0) * delta
			var speed := -1.0 if backwards else 1.0
			if state != "walk" or _sprite.animation != "walk" or sign(_sprite.get_playing_speed()) != sign(speed):
				state = "walk"
				_play("walk", speed)
		else:
			_set_idle()


func _set_idle() -> void:
	if state != "idle" or _sprite.animation != "idle":
		state = "idle"
		_play("idle")


func _airborne(delta: float) -> void:
	var p := _progress()
	if p > 0.15 and p < 0.85:
		position.x += vel.x * delta


func _jump_lift() -> float:
	## How far above the floor the body is right now, following the clip's arc.
	if state != "jump":
		return 0.0
	var p := clampf((_progress() - 0.15) / 0.7, 0.0, 1.0)
	return sin(p * PI) * H * 0.75


func _start_attack(name: String) -> void:
	state = name
	hit_landed = false
	_play(name, _length(name) / attacks[name]["time"])
	Sound.sfx("whoosh", -4.0)
	if name == "jab":
		say("jab_shout", 0.45)
	else:
		say("kick_shout", 0.6)


## Speak one of this fighter's voice lines.
func say(line: String, chance := 1.0) -> void:
	Sound.voice(voice_id, player, line, chance, voice_pitch)


func _attacking() -> void:
	var atk: Dictionary = attacks[state]
	var p := _progress()
	var active: Vector2 = atk["active"]
	if hit_landed or p < active.x or p > active.y or opponent == null:
		return
	if get_hitbox(atk["box"]).intersects(opponent.get_hurtbox()):
		hit_landed = true
		if opponent.take_hit(atk["damage"], atk["push"], atk["hitstun"], facing):
			Sound.sfx(atk["sfx"])


func _start_special() -> void:
	state = "special"
	special_spawned = false
	special_cd = SPECIAL_COOLDOWN
	_play("special", _length("special") / special_time)
	say("special_shout")


func _special() -> void:
	if not special_spawned and _progress() >= special_release:
		special_spawned = true
		var shot := Fireball.new()
		shot.owner_fighter = self
		shot.direction = facing
		shot.kind = special_kind
		if special_kind == "shockwave":
			# rolls along the floor from where his fists hit the ground
			shot.position = Vector2(position.x + facing * H * 0.45, floor_y)
			Sound.sfx("ground_pound", 0.0, 0.03)
			quake.emit(14.0)
		else:
			shot.position = position + Vector2(facing * H * 0.55, -H * 0.62)
			Sound.sfx("fireball_launch", -2.0, 0.03)
		get_parent().add_child(shot)


# ---------------------------------------------------------------- getting hit

## Returns true if the hit connected, false if it was blocked or ignored.
## `low` hits (the shockwave) can only be blocked crouching: hold back + down.
func take_hit(damage: int, push: float, hitstun: float, from_dir: int, low := false) -> bool:
	if state == "ko":
		return false
	var blocking: bool = state in ["idle", "walk", "crouch", "block"] and not locked \
			and _held(_back()) and (not low or _held("down"))
	if blocking:
		health = max(health - int(damage * 0.1), 1)
		slide = push * 0.6 * from_dir
		flash = 0.05
		Sound.sfx("block")
		landed_hit.emit(self, true)
		health_changed.emit(self, health)
		return false

	# hits that land while already stunned chain into a combo
	combo = combo + 1 if state == "hit" else 1
	health = max(health - damage, 0)
	slide = push * from_dir
	flash = 0.08
	vel = Vector2.ZERO
	position.y = floor_y
	health_changed.emit(self, health)
	landed_hit.emit(self, false)
	if health <= 0:
		state = "ko"
		_play("knockdown")
		say("ko_cry")
		get_tree().create_timer(_length("knockdown") * 0.55).timeout.connect(
				func(): Sound.sfx("body_fall", 0.0, 0.02))
		knocked_out.emit(self)
	else:
		state = "hit"
		_play("hit", _length("hit") / max(hitstun, HIT_TIME))
		say("hurt1" if randf() < 0.5 else "hurt2", 0.7)
	return true


func _on_animation_finished() -> void:
	if state in ["jab", "roundhouse", "crouch_kick", "special", "hit", "jump"]:
		state = "idle"
		_play("idle")


# ---------------------------------------------------------------- boxes

func get_hurtbox() -> Rect2:
	var h := H * (0.62 if state in ["crouch", "crouch_kick"] else 0.95)
	if state == "ko":
		h = H * 0.25
	if state == "jump":
		h = H * 0.6   # tucked
	var lift := _jump_lift()
	return Rect2(position.x - H * 0.2, position.y - h - lift, H * 0.4, h)


func get_hitbox(box: Rect2) -> Rect2:
	var x := box.position.x * H
	var w := box.size.x * H
	var left := position.x + (x if facing == 1 else -x - w)
	return Rect2(left, position.y + box.position.y * H, w, box.size.y * H)


func _separate_from_opponent() -> void:
	if opponent == null or state == "jump" or opponent.state == "jump":
		return
	var min_gap := H * 0.38
	var gap := position.x - opponent.position.x
	if abs(gap) < min_gap:
		var push: float = (min_gap - abs(gap)) * 0.5
		position.x += push * (1.0 if gap >= 0.0 else -1.0)


# ---------------------------------------------------------------- animation helpers

func _play(anim: String, speed := 1.0) -> void:
	# A negative speed plays the clip backwards (used for walking backwards).
	_sprite.play(anim, speed, speed < 0.0)


func _length(anim: String) -> float:
	return float(_counts.get(anim, 12)) / _fps


func _progress() -> float:
	var n := float(_counts.get(_sprite.animation, 1))
	return (_sprite.frame + _sprite.frame_progress) / n


# ---------------------------------------------------------------- CPU brain

func _cpu_think(delta: float) -> void:
	_cpu_timer -= delta
	if _cpu_timer > 0.0 or opponent == null:
		return
	var think: Array = [[0.35, 0.70], [0.18, 0.45], [0.10, 0.26]][cpu_level]
	var block_chance: float = [0.25, 0.55, 0.82][cpu_level]
	var special_chance: float = [0.15, 0.30, 0.40][cpu_level]
	_cpu_timer = randf_range(think[0], think[1])
	_cpu_held.clear()
	var dist: float = abs(opponent.position.x - position.x)
	var fwd := _forward()
	var back := _back()

	# Deal with incoming specials: jump a shockwave, block a fireball.
	for n in get_parent().get_children():
		if n is Fireball and n.owner_fighter == opponent:
			var gap: float = (n.position.x - position.x) * -n.direction
			if gap > 0.0 and gap < H * 1.3 and randf() < block_chance:
				if n.kind == "shockwave":
					_cpu_held["up"] = true
				else:
					_cpu_held[back] = true
				return

	# Block when the opponent is attacking up close.
	if opponent.state in ["jab", "roundhouse", "crouch_kick"] and dist < H * 1.0 and randf() < block_chance:
		_cpu_held[back] = true
		if opponent.state == "crouch_kick":
			_cpu_held["down"] = true
		return

	if dist > H * 1.6:
		if special_cd <= 0.0 and randf() < special_chance:
			_cpu_pressed["special"] = true
		elif randf() < 0.12:
			_cpu_held["up"] = true
			_cpu_held[fwd] = true
		else:
			_cpu_held[fwd] = true
	elif dist > H * 0.75:
		var r := randf()
		if r < 0.45:
			_cpu_held[fwd] = true
		elif r < 0.65:
			_cpu_pressed["kick"] = true
		elif r < 0.80:
			_cpu_held["down"] = true
			_cpu_pressed["kick"] = true
	else:
		var r := randf()
		if r < 0.35:
			_cpu_pressed["punch"] = true
		elif r < 0.55:
			_cpu_pressed["kick"] = true
		elif r < 0.70:
			_cpu_held["down"] = true
			_cpu_pressed["kick"] = true
		else:
			_cpu_held[back] = true
