class_name TitleShow
extends Node2D
## Attract mode behind the title menu: the two fighters trade blows on the right
## half of the screen, with impact bursts, flashes and rising embers.

signal impact(strength: float)

const LEFT_X := 760.0
const RIGHT_X := 1080.0
const FLOOR := 650.0
const SCALE := 1.12

## Exchanges: [attacker side (0 left, 1 right), attack anim, defender anim, effect, delay to impact]
const SCRIPT := [
	[0, "jab", "block", "", 0.25],
	[1, "jab", "hit", "fire_burst", 0.3],
	[0, "roundhouse", "hit", "fire_burst", 0.4],
	[1, "kick_special", "block", "rock_burst", 0.6],
	[0, "special", "hit", "fire_burst", 0.55],
	[1, "roundhouse", "crouch_block", "", 0.4],
	[0, "kick_special", "hit", "fire_burst", 0.45],
	[1, "special", "jump", "rock_burst", 0.55],
	[0, "jump_kick", "hit", "fire_burst", 0.5],
	[1, "victory", "idle", "", 0.0],
	[0, "victory", "idle", "", 0.0],
]

var _sprites: Array[AnimatedSprite2D] = []
var _counts: Array = []
var _step := 0
var _next := 0.6
var _t := 0.0
var _embers: Array = []
var _flash := 0.0
var _pending := -1.0
var _pending_fx := ""


func setup(left: Dictionary, right: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_sprites.clear()
	_counts.clear()
	z_index = 3
	var datas := [left, right]
	for i in 2:
		var d: Dictionary = datas[i]
		var holder := Node2D.new()
		holder.position = Vector2(LEFT_X if i == 0 else RIGHT_X, FLOOR)
		holder.scale = Vector2(SCALE * (1 if i == 0 else -1), SCALE)
		add_child(holder)
		var s := AnimatedSprite2D.new()
		s.sprite_frames = d["frames"]
		s.centered = false
		s.offset = -d["anchor"]
		holder.add_child(s)
		s.play("idle")
		_sprites.append(s)
		_counts.append(d["counts"])
	_embers.clear()
	for i in 60:
		_embers.append(_new_ember(true))
	_step = 0
	_next = 0.8


func _new_ember(anywhere: bool) -> Dictionary:
	return {"p": Vector2(randf_range(0, 1280), randf_range(0, 720) if anywhere else 740.0),
			"v": Vector2(randf_range(-15, 15), randf_range(-70, -30)), "r": randf_range(1.0, 2.8),
			"ph": randf() * TAU, "hot": randf() < 0.6}


func _anim(i: int, anim: String) -> void:
	var s := _sprites[i]
	if not _counts[i].has(anim):
		anim = "idle"
	s.play(anim)


func _process(delta: float) -> void:
	_t += delta
	_flash = max(_flash - delta * 3.0, 0.0)
	for e in _embers:
		e["p"] += (e["v"] + Vector2(sin(_t * 1.7 + e["ph"]) * 12.0, 0)) * delta
		if e["p"].y < -10:
			e.merge(_new_ember(false), true)
	if _sprites.size() < 2:
		return
	# return to stance once an attack finishes
	for i in 2:
		var s := _sprites[i]
		if not s.is_playing() and s.animation != "victory":
			s.play("idle")
	if _pending >= 0.0:
		_pending -= delta
		if _pending < 0.0:
			_hit()
	_next -= delta
	if _next <= 0.0:
		var ex: Array = SCRIPT[_step % SCRIPT.size()]
		_step += 1
		var att: int = ex[0]
		_anim(att, ex[1])
		_anim(1 - att, "idle")
		_pending = float(ex[4]) if str(ex[3]) != "" or ex[2] != "idle" else -1.0
		_pending_fx = str(ex[3])
		set_meta("defend", [1 - att, ex[2]])
		_next = 2.4 if ex[1] == "victory" else randf_range(1.1, 1.5)
		if ex[1] in ["special", "kick_special"]:
			Sound.sfx("whoosh", -14.0)
	queue_redraw()


func _hit() -> void:
	var d: Array = get_meta("defend", [1, "hit"])
	_anim(d[0], d[1])
	var center := Vector2((LEFT_X + RIGHT_X) * 0.5, FLOOR - 230.0)
	if _pending_fx != "" and Vfx.available(_pending_fx):
		var at := center if _pending_fx == "fire_burst" else Vector2(center.x, FLOOR)
		Vfx.spawn(self, _pending_fx, at, 0.9, false, 6)
	var strong: bool = d[1] == "hit"
	_flash = 0.5 if strong else 0.25
	Sound.sfx("punch" if strong else "block", -12.0)
	impact.emit(10.0 if strong else 4.0)


func _draw() -> void:
	# floor glow under the fighters
	draw_circle(Vector2((LEFT_X + RIGHT_X) * 0.5, FLOOR + 10), 260, Color(1, 0.35, 0.1, 0.10))
	for e in _embers:
		var a: float = 0.4 + 0.4 * sin(_t * 3.0 + e["ph"])
		var c := Color(1, 0.55, 0.15, a) if e["hot"] else Color(0.4, 0.8, 1, a * 0.7)
		draw_circle(e["p"], e["r"] * 2.2, Color(c.r, c.g, c.b, a * 0.15))
		draw_circle(e["p"], e["r"], c)
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(1, 0.9, 0.7, _flash * 0.35))
