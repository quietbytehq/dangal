class_name Fireball
extends Node2D
## A special-move projectile.
##  - "fireball": Rustam's chi blast. Flies at chest height.
##  - "shockwave": Baba Sher's ground pound. Rolls along the floor and must be jumped over.
##  - "phoenix": Mei Lin's Phoenix Palm. Flies at chest height like the fireball, burning orange.

var kind := "fireball"
var owner_fighter: Fighter
var direction := 1
var t := 0.0
var _rocks: Array = []
var _orb: Vfx
var _next_burst := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	z_index = 4
	if kind != "shockwave":
		_orb = Vfx.spawn(self, "chi_orb", Vector2.ZERO, 0.42, direction < 0, 4)
		if _orb and kind == "phoenix":
			_orb.modulate = Color(1.8, 0.75, 0.3)
		elif _orb and kind == "data":
			_orb.modulate = Color(0.45, 1.2, 2.0)


func _speed() -> float:
	return 470.0 if kind == "shockwave" else (660.0 if kind == "phoenix" else 620.0)


func _damage() -> int:
	return 115 if kind == "shockwave" else 90


func _hit_shape() -> Rect2:
	if kind != "shockwave":
		return Rect2(position - Vector2(30, 30), Vector2(60, 60))
	# low and wide: hits anything standing on the floor, misses jumpers
	return Rect2(position.x - 45, position.y - 70, 90, 70)


func _physics_process(delta: float) -> void:
	t += delta
	position.x += _speed() * direction * delta
	if kind == "shockwave":
		_next_burst -= delta
		if _next_burst <= 0.0:
			_next_burst = 0.075
			if Vfx.available("rock_burst"):
				Vfx.spawn(get_parent(), "rock_burst", position + Vector2(randf_range(-10, 10), 0),
						randf_range(0.42, 0.55), randf() < 0.5, 3, 1.3)
			else:
				_rocks.append({"x": position.x, "age": 0.0, "h": randf_range(18, 46), "w": randf_range(14, 30)})
	for r in _rocks:
		r["age"] += delta
	_rocks = _rocks.filter(func(r): return r["age"] < 0.45)
	queue_redraw()

	# Two specials cancel each other out.
	for other in get_parent().get_children():
		if other != self and other is Fireball and other.owner_fighter != owner_fighter:
			if _hit_shape().intersects(other._hit_shape()):
				Sound.sfx("fireball_hit", -3.0, 0.1)
				Vfx.spawn(get_parent(), "fire_burst", (position + other.position) * 0.5, 0.9)
				other.queue_free()
				queue_free()
				return

	# specials blast stage props out of the way and keep going
	for prop in get_tree().get_nodes_in_group("props"):
		if not prop.broken and _hit_shape().intersects(prop.get_rect()):
			prop.hit(Vector2(direction * 650.0, -420.0), 90 if kind == "shockwave" else 120)

	var target := owner_fighter.opponent
	if target and _hit_shape().intersects(target.get_hurtbox()):
		if target.take_hit(_damage(), 220.0, 0.45, direction, kind == "shockwave"):
			Sound.sfx("kick" if kind == "shockwave" else "fireball_hit", 0.0, 0.03)
			owner_fighter.gain_meter(8.0)
		Vfx.spawn(get_parent(), "rock_burst" if kind == "shockwave" else "fire_burst",
				position, 0.75 if kind == "shockwave" else 0.8)
		queue_free()
	elif position.x < -100 or position.x > 1380:
		queue_free()


func _draw() -> void:
	if kind != "shockwave":
		_draw_fireball()
	else:
		_draw_shockwave()


func _draw_fireball() -> void:
	if _orb:
		# soft glow under the generated orb animation
		draw_circle(Vector2.ZERO, 46.0 * (1.0 + 0.1 * sin(t * 30.0)), Color(1.0, 0.45, 0.1, 0.22))
		return
	var radius := 34.0
	var pulse := 1.0 + 0.12 * sin(t * 30.0)
	for i in 5:
		var off := Vector2(-direction * (14 + i * 14), sin(t * 20 + i) * 4)
		draw_circle(off, radius * (0.7 - i * 0.11) * pulse, Color(1.0, 0.45, 0.1, 0.35 - i * 0.06))
	draw_circle(Vector2.ZERO, radius * 1.35 * pulse, Color(1.0, 0.4, 0.05, 0.25))
	draw_circle(Vector2.ZERO, radius * pulse, Color(1.0, 0.55, 0.1, 0.85))
	draw_circle(Vector2.ZERO, radius * 0.6 * pulse, Color(1.0, 0.85, 0.4, 1.0))
	draw_circle(Vector2.ZERO, radius * 0.3, Color(1, 1, 0.9, 1))


func _draw_shockwave() -> void:
	if Vfx.available("rock_burst"):
		draw_circle(Vector2(0, -20), 38.0, Color(1.0, 0.8, 0.35, 0.2))
		return
	# trail of rock spikes bursting up from the floor behind the wave front
	for r in _rocks:
		var k: float = 1.0 - r["age"] / 0.45
		var x: float = r["x"] - position.x
		var h: float = r["h"] * sin(k * PI)
		var w: float = r["w"]
		var pts := PackedVector2Array([Vector2(x - w * 0.5, 0), Vector2(x, -h), Vector2(x + w * 0.5, 0)])
		draw_colored_polygon(pts, Color(0.55, 0.45, 0.35, k))
		draw_polyline(pts, Color(0.25, 0.2, 0.15, k), 2.0)
	# glowing wave front
	var pulse := 1.0 + 0.15 * sin(t * 25.0)
	draw_circle(Vector2(0, -18), 40 * pulse, Color(0.95, 0.75, 0.35, 0.25))
	var front := PackedVector2Array([
		Vector2(-direction * 50, 0), Vector2(-direction * 10, -62 * pulse),
		Vector2(direction * 22, -30), Vector2(direction * 30, 0)])
	draw_colored_polygon(front, Color(0.9, 0.7, 0.35, 0.85))
	# dust puffs
	for i in 4:
		var px := -direction * (20 + i * 22) + sin(t * 15 + i) * 6
		draw_circle(Vector2(px, -8 - i * 3), 14 - i * 2, Color(0.8, 0.72, 0.6, 0.45 - i * 0.08))
