class_name Fighter
extends Node2D
## One fighter: movement, attacks, air attacks, specials, ultra, blocking, damage,
## push boxes (fighters never overlap) and a simple CPU brain.
## The node's position is the point between the fighter's feet.

signal health_changed(fighter: Fighter, value: int)
signal knocked_out(fighter: Fighter)
signal landed_hit(fighter: Fighter, blocked: bool)
signal quake(amount: float)
signal ultra_requested(fighter: Fighter)

const SPECIAL_COOLDOWN := 1.4
const KICK_SPECIAL_COOLDOWN := 1.2
const MOTION_WINDOW := 0.45   # seconds to finish down, down-forward, forward + button
const JUMP_TIME := 1.0
const HIT_TIME := 0.45
const BLOCKSTUN := 0.22
const CROUCH_POSE := 0.22     # where in the crouch-kick clip the crouch pose sits
const GUARD_POSE := 0.45      # where in the block clips the guard is fully up
const VICTORY_HOLD := {"rustam": 0.52, "babasher": 0.48, "tiago": 0.45, "meilin": 0.6}   # where each victory clip hits its pose
const METER_MAX := 100.0
const EXTRA_JUMP := 0.4       # extra jump height on top of the clip's own, in body heights
const WALK_BOOST := 1.2       # extra walking speed on top of the global game speed
const JUMP_DRIFT := 2.1       # sideways jump speed, in walk speeds: enough to jump over the opponent

const GROUND_ATTACKS := ["jab", "roundhouse", "crouch_punch", "crouch_kick", "kick_special"]
const AIR_ATTACKS := ["jump_punch", "jump_kick"]
const AIR_STATES := ["jump", "jump_punch", "jump_kick"]
const ATTACKING := ["jab", "roundhouse", "crouch_punch", "crouch_kick", "kick_special",
		"jump_punch", "jump_kick", "special", "ultra"]

# Filled from Characters.DATA in setup()
var char_id := "rustam"
var display_name := "RUSTAM"
var max_health := 1000
var walk_speed := 240.0
var push_width := 0.27
var attacks := {}
var special_kind := "fireball"
var special_time := 0.95
var special_release := 0.5
var ultra_time := 3.2
var ultra_release := 0.6
var voice_id := "rustam"
var voice_pitch := 1.0
var def := {}

var player := 1
var cpu := false
var cpu_level := 1        # 0 easy, 1 normal, 2 hard
var combo := 0            # hits taken in the current combo
var opponent: Fighter
var health := 1000
var meter := 0.0          # ultra meter, 0..METER_MAX
var facing := 1
var state := "idle"
var vel := Vector2.ZERO
var slide := 0.0
var floor_y := 640.0
var bounds := Vector2(70.0, 1210.0)
var locked := true
var frozen := false       # held still during the other fighter's ultra cut-in
var hit_landed := false
var special_spawned := false
var special_cd := 0.0
var kick_special_cd := 0.0
var flash := 0.0
var H := 300.0

var _counts := {}
var _fps := 12.0
var _visual: Node2D
var _sprite: AnimatedSprite2D
var _dir_log: Array = []      # [[token, time], ...]
var _last_dir := ""
var _time := 0.0
var _hits_done := 0
var _next_hit_at := 0.0
var _blockstun := 0.0
var _impact_done := false
var _props_hit: Array = []

# CPU brain state
var _cpu_held := {}
var _cpu_pressed := {}
var _cpu_timer := 0.0


func setup(p: int, id: String, data: Dictionary, tint: Color, pitch := 1.0) -> void:
	player = p
	char_id = id
	def = Characters.get_def(id)
	display_name = def["name"]
	max_health = def["health"]
	health = max_health
	walk_speed = def["walk_speed"] * WALK_BOOST
	push_width = def.get("push_width", 0.3)
	attacks = def["attacks"]
	special_kind = def["special"]
	special_time = def["special_time"]
	special_release = def["special_release"]
	ultra_time = def.get("ultra_time", 3.2)
	ultra_release = def.get("ultra_release", 0.6)
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
	kick_special_cd = 0.0
	combo = 0
	state = "idle"
	locked = true
	frozen = false
	_play("idle")
	health_changed.emit(self, health)


func has_anim(anim: String) -> bool:
	return _counts.has(anim)


func gain_meter(amount: float) -> void:
	meter = clamp(meter + amount, 0.0, METER_MAX)


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
	var need := ["d", "df", "f"]
	var i := 0
	for e in _dir_log:
		if i < need.size() and e[0] == need[i]:
			i += 1
	return i == need.size()


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if frozen:
		_sprite.speed_scale = 0.0
		return
	_sprite.speed_scale = 1.0
	_time += delta
	special_cd = max(special_cd - delta, 0.0)
	kick_special_cd = max(kick_special_cd - delta, 0.0)
	if cpu and not locked:
		_cpu_think(delta)
	_track_motion()

	match state:
		"idle", "walk", "crouch", "block", "crouch_block":
			_grounded(delta)
		"jump":
			_airborne(delta)
		"jump_punch", "jump_kick":
			_airborne(delta)
			_attacking()
		"jab", "roundhouse", "crouch_punch", "crouch_kick", "kick_special":
			_attacking()
			_move_during_attack(delta)
		"special":
			if special_kind == "dash":
				# Jaguar Shot: the special is a charging attack, not a projectile
				_attacking()
				_move_during_attack(delta)
			else:
				_special()
		"ultra":
			_ultra()
		"victory":
			# play into the pose, then hold it
			if has_anim("victory") and _sprite.animation == "victory" \
					and _progress() >= float(VICTORY_HOLD.get(char_id, 0.5)):
				_sprite.pause()

	# knockback slide
	if slide != 0.0:
		position.x += slide * delta
		slide = move_toward(slide, 0.0, 1400.0 * delta)
	_bump_props()
	position.x = clamp(position.x, bounds.x, bounds.y)
	_separate_from_opponent()

	flash = max(flash - delta, 0.0)
	_update_tint()
	_visual.position.y = -_extra_lift()
	_cpu_pressed.clear()


func _grounded(delta: float) -> void:
	if opponent:
		facing = 1 if opponent.position.x >= position.x else -1
		_visual.scale.x = facing
	if locked:
		_set_idle()
		return
	if _blockstun > 0.0:
		_blockstun -= delta
		return

	var fwd_held := _held(_forward())
	if _pressed("ultra") and meter >= METER_MAX and has_anim("ultra"):
		_request_ultra()
	elif _pressed("special") and fwd_held and kick_special_cd <= 0.0 and has_anim("kick_special"):
		_start_kick_special()
	elif _pressed("special") and special_cd <= 0.0:
		_start_special()
	elif _pressed("punch"):
		if _did_quarter_circle() and special_cd <= 0.0:
			_start_special()
		elif _held("down"):
			_start_attack("crouch_punch" if has_anim("crouch_punch") else "crouch_kick")
		else:
			_start_attack("jab")
	elif _pressed("kick"):
		if _did_quarter_circle() and kick_special_cd <= 0.0 and has_anim("kick_special"):
			_start_kick_special()
		else:
			_start_attack("crouch_kick" if _held("down") else "roundhouse")
	elif _held("up"):
		# The jump clip already contains the vertical motion, so the node stays
		# on the floor and only drifts sideways. The hurtbox follows the arc.
		var dir := int(_held("right")) - int(_held("left"))
		vel = Vector2(dir * walk_speed * JUMP_DRIFT, 0.0)
		state = "jump"
		_play("jump", _length("jump") / JUMP_TIME)
	elif _held(_back()) and _under_threat():
		_guard(_held("down"))
	elif _held("down"):
		if state != "crouch":
			state = "crouch"
			_hold_pose("crouch_kick", CROUCH_POSE)
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


## True when something is about to hit us, so holding back shows the guard.
func _under_threat() -> bool:
	if opponent == null:
		return false
	var dist: float = abs(opponent.position.x - position.x)
	if opponent.state in ATTACKING and dist < H * 1.6:
		return true
	for n in get_parent().get_children():
		if n is Fireball and n.owner_fighter == opponent:
			if abs(n.position.x - position.x) < H * 2.0:
				return true
	return false


func _guard(crouching: bool) -> void:
	var s := "crouch_block" if crouching else "block"
	if state != s:
		state = s
		var anim := s if has_anim(s) else ("crouch_kick" if crouching else "idle")
		_hold_pose(anim, GUARD_POSE if has_anim(s) else CROUCH_POSE)


func _hold_pose(anim: String, at: float) -> void:
	_sprite.play(anim)
	_sprite.pause()
	_sprite.frame = int(_counts.get(anim, 1) * at)


func _set_idle() -> void:
	if state != "idle" or _sprite.animation != "idle" or not _sprite.is_playing():
		state = "idle"
		_play("idle")


func _airborne(delta: float) -> void:
	var p := _progress()
	if p > 0.15 and p < 0.85:
		position.x += vel.x * delta
	# attack in the air: punch / kick switch to the matching jump attack mid-flight
	if state == "jump" and not locked:
		var air := ""
		if _pressed("punch"):
			air = "jump_punch"
		elif _pressed("kick"):
			air = "jump_kick"
		if air != "" and has_anim(air):
			state = air
			hit_landed = false
			_hits_done = 0
			_props_hit.clear()
			_play(air, _length(air) / float(attacks[air]["time"]))
			_sprite.frame = int(clampf(p, 0.0, 0.4) * _counts[air])
			Sound.sfx("whoosh", -4.0)
			say("jab_shout" if air == "jump_punch" else "kick_shout", 0.5)


func _jump_lift() -> float:
	## How far above the floor the body is right now: the clip's own arc plus the extra lift.
	if not state in AIR_STATES:
		return 0.0
	var p := clampf((_progress() - 0.15) / 0.7, 0.0, 1.0)
	return sin(p * PI) * H * (0.75 + EXTRA_JUMP)


## The part of the jump height the clip doesn't contain: the sprite is raised by this much.
func _extra_lift() -> float:
	if not state in AIR_STATES:
		return 0.0
	var p := clampf((_progress() - 0.15) / 0.7, 0.0, 1.0)
	return sin(p * PI) * H * EXTRA_JUMP


func _start_attack(atk_name: String) -> void:
	state = atk_name
	hit_landed = false
	_hits_done = 0
	_impact_done = false
	_props_hit.clear()
	_play(atk_name, _length(atk_name) / float(attacks[atk_name]["time"]))
	Sound.sfx("whoosh", -4.0)
	if atk_name in ["jab", "crouch_punch"]:
		say("jab_shout", 0.45)
	else:
		say("kick_shout", 0.6)


func _start_kick_special() -> void:
	_start_attack("kick_special")
	kick_special_cd = KICK_SPECIAL_COOLDOWN
	say("kick_special_shout")
	if char_id == "rustam":
		Sound.sfx("spin_whoosh", 0.0, 0.05)


## Speak one of this fighter's voice lines.
func say(line: String, chance := 1.0) -> void:
	Sound.voice(voice_id, player, line, chance, voice_pitch)


func _move_during_attack(delta: float) -> void:
	var atk: Dictionary = attacks.get(state, {})
	if not atk.has("move"):
		return
	var active: Vector2 = atk["active"]
	var p := _progress()
	if p >= active.x * 0.8 and p <= active.y:
		position.x += facing * float(atk["move"]) * delta


func _attacking() -> void:
	var atk: Dictionary = attacks[state]
	var p := _progress()
	var active: Vector2 = atk["active"]
	if p < active.x or p > active.y or opponent == null:
		return
	var box := get_hitbox(atk["box"])
	box.position.y -= _jump_lift()
	# heavy kicks shake the ground once when they land
	if atk.has("quake") and not _impact_done:
		_impact_done = true
		quake.emit(float(atk["quake"]))
		Sound.sfx("ground_pound", -4.0, 0.05)
		if atk.has("vfx"):
			Vfx.spawn(get_parent(), str(atk["vfx"]), Vector2(box.get_center().x, floor_y), 0.7, facing < 0)
	# attacks also smash stage props
	for prop in get_tree().get_nodes_in_group("props"):
		if not prop.broken and not _props_hit.has(prop) and box.intersects(prop.get_rect()):
			_props_hit.append(prop)
			prop.hit(Vector2(facing * float(atk["push"]) * 2.2, -260.0), int(atk["damage"]))
	var hits := int(atk.get("hits", 1))
	if _hits_done >= hits or _time < _next_hit_at:
		return
	if box.intersects(opponent.get_hurtbox()):
		_hits_done += 1
		_next_hit_at = _time + 0.18
		hit_landed = true
		var contact := (box.get_center() + opponent.get_hurtbox().get_center()) * 0.5
		var landed := opponent.take_hit(atk["damage"], atk["push"], atk["hitstun"], facing,
				bool(atk.get("low", false)))
		if landed:
			Sound.sfx(atk["sfx"])
			gain_meter(9.0)
			Vfx.spawn(get_parent(), str(atk.get("vfx", "fire_burst")), contact,
					0.55 if atk.has("vfx") else 0.32)
		else:
			gain_meter(3.0)


func _start_special() -> void:
	state = "special"
	special_spawned = false
	special_cd = SPECIAL_COOLDOWN
	hit_landed = false
	_hits_done = 0
	_impact_done = false
	_props_hit.clear()
	if special_kind == "dash":
		Sound.sfx("spin_whoosh", -2.0, 0.05)
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


# ---------------------------------------------------------------- ultra

## Hit flash, or the glowing aura while an ultra powers up.
func _update_tint() -> void:
	if flash > 0.0:
		_sprite.modulate = Color(2.2, 2.2, 2.2)
	elif state in ["ultra", "ultra_wait"] and not special_spawned:
		var pulse := 0.75 + 0.25 * sin(_time * 22.0)
		var auras := {"beam": Color(0.55, 0.8, 1.6), "quake": Color(1.6, 1.15, 0.45), "rush": Color(0.75, 1.6, 0.6), "dragon": Color(1.7, 1.35, 0.4)}
		var aura: Color = auras.get(str(def.get("ultra", "beam")), Color(1.6, 1.15, 0.45))
		_sprite.modulate = Color.WHITE.lerp(aura, pulse * 0.5)
	else:
		_sprite.modulate = Color.WHITE


func _request_ultra() -> void:
	meter = 0.0
	state = "ultra_wait"
	special_spawned = false
	_hold_pose("ultra", 0.0)
	_update_tint()
	ultra_requested.emit(self)


## Called by main after the cut-in: play the ultra animation for real.
func begin_ultra() -> void:
	state = "ultra"
	special_spawned = false
	_play("ultra", _length("ultra") / ultra_time)
	say("ultra_shout")
	Sound.sfx("ultra_charge", 0.0, 0.0)


func _ultra() -> void:
	if not special_spawned and _progress() >= ultra_release:
		special_spawned = true
		var fx := UltraFx.new()
		fx.owner_fighter = self
		fx.kind = str(def.get("ultra", "beam"))
		fx.damage = int(def.get("ultra_damage", 300))
		get_parent().add_child(fx)


## Round won: strike this fighter's own victory pose.
func celebrate() -> void:
	if state == "ko":
		return
	locked = true
	state = "victory"
	vel = Vector2.ZERO
	slide = 0.0
	if opponent:
		facing = 1 if opponent.position.x >= position.x else -1
		_visual.scale.x = facing
	_play("victory" if has_anim("victory") else "idle")


# ---------------------------------------------------------------- getting hit

## Returns true if the hit connected, false if it was blocked or ignored.
## Every attack can be blocked by holding back, standing or crouching.
func take_hit(damage: int, push: float, hitstun: float, from_dir: int, low := false) -> bool:
	if state == "ko":
		return false
	var can_guard: bool = state in ["idle", "walk", "crouch", "block", "crouch_block"] and not locked
	# any attack can be blocked by holding back, standing or crouching
	var blocking: bool = can_guard and _held(_back())
	if blocking:
		health = max(health - int(damage * 0.1), 1)
		slide = push * 0.6 * from_dir
		flash = 0.05
		_blockstun = BLOCKSTUN
		_guard(_held("down"))
		gain_meter(2.0)
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
	gain_meter(5.0)
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
	if state in GROUND_ATTACKS or state in AIR_STATES or state in ["special", "hit", "ultra"]:
		state = "idle"
		_play("idle")


# ---------------------------------------------------------------- boxes

func get_hurtbox() -> Rect2:
	var low: bool = state in ["crouch", "crouch_kick", "crouch_punch", "crouch_block"]
	var h := H * (0.62 if low else 0.95)
	if state == "ko":
		h = H * 0.25
	if state in AIR_STATES:
		h = H * 0.6   # tucked
	var lift := _jump_lift()
	return Rect2(position.x - H * 0.2, position.y - h - lift, H * 0.4, h)


func get_hitbox(box: Rect2) -> Rect2:
	var x := box.position.x * H
	var w := box.size.x * H
	var left := position.x + (x if facing == 1 else -x - w)
	return Rect2(left, position.y + box.position.y * H, w, box.size.y * H)


## A fighter sent flying crashes through props; a walking fighter nudges them along.
func _bump_props() -> void:
	var me := get_hurtbox()
	for prop in get_tree().get_nodes_in_group("props"):
		if prop.broken or not me.intersects(prop.get_rect()):
			continue
		if state in ["hit", "ko"] and abs(slide) > 120.0:
			prop.hit(Vector2(slide * 1.4, -320.0), 45)
		elif state == "walk":
			var dir: float = sign(prop.position.x - position.x)
			prop.hit(Vector2(dir * 90.0, -40.0), 0, true)


## Push boxes: the two fighters never overlap, on the ground or in the air.
## Each pushes half the overlap; against a wall the other one takes all of it.
func _separate_from_opponent() -> void:
	if opponent == null or state == "ko" or opponent.state == "ko":
		return
	# a jumping fighter sails over the other one's head; push apart only once he lands
	if _jump_lift() > H * 0.3 or opponent._jump_lift() > opponent.H * 0.3:
		return
	var min_gap: float = H * push_width + opponent.H * opponent.push_width
	var gap := position.x - opponent.position.x
	if abs(gap) >= min_gap:
		return
	var side := 1.0 if gap > 0.0 else (-1.0 if gap < 0.0 else float(-facing))
	var overlap: float = min_gap - abs(gap)
	var mine := clampf(position.x + side * overlap * 0.5, bounds.x, bounds.y)
	var moved: float = abs(mine - position.x)
	position.x = mine
	var theirs := clampf(opponent.position.x - side * (overlap - moved), opponent.bounds.x, opponent.bounds.y)
	opponent.position.x = theirs


# ---------------------------------------------------------------- animation helpers

func _play(anim: String, speed := 1.0) -> void:
	# A negative speed plays the clip backwards (used for walking backwards).
	if not has_anim(anim):
		anim = "idle"
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

	if meter >= METER_MAX and randf() < 0.6:
		_cpu_pressed["ultra"] = true
		return

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
	if opponent.state in ATTACKING and dist < H * 1.1 and randf() < block_chance:
		_cpu_held[back] = true
		if opponent.state == "crouch_kick":
			_cpu_held["down"] = true
		return

	if dist > H * 1.6:
		if special_cd <= 0.0 and randf() < special_chance:
			_cpu_pressed["special"] = true
		elif randf() < 0.14:
			_cpu_held["up"] = true
			_cpu_held[fwd] = true
		else:
			_cpu_held[fwd] = true
	elif dist > H * 0.75:
		var r := randf()
		if r < 0.35:
			_cpu_held[fwd] = true
		elif r < 0.50:
			_cpu_pressed["kick"] = true
		elif r < 0.62 and kick_special_cd <= 0.0:
			_cpu_held[fwd] = true
			_cpu_pressed["special"] = true
		elif r < 0.75:
			_cpu_held["down"] = true
			_cpu_pressed["kick"] = true
		elif r < 0.85:
			_cpu_held["up"] = true
			_cpu_held[fwd] = true
	else:
		var r := randf()
		if r < 0.25:
			_cpu_pressed["punch"] = true
		elif r < 0.42:
			_cpu_pressed["kick"] = true
		elif r < 0.55:
			_cpu_held["down"] = true
			_cpu_pressed["punch"] = true
		elif r < 0.68:
			_cpu_held["down"] = true
			_cpu_pressed["kick"] = true
		else:
			_cpu_held[back] = true
	# press an attack while already airborne
	if state == "jump" and randf() < 0.5:
		_cpu_pressed["kick" if randf() < 0.5 else "punch"] = true
