class_name Fireball
extends Node2D
## A special-move projectile.
##  - "fireball": Rustam's chi blast. Flies at chest height.
##  - "shockwave": Baba Sher's ground pound. Rolls along the floor and must be jumped over.

var kind := "fireball"
var owner_fighter: Fighter
var direction := 1
var t := 0.0
var _rocks: Array = []


func _speed() -> float:
	return 620.0 if kind == "fireball" else 470.0


func _damage() -> int:
	return 90 if kind == "fireball" else 115


func _hit_shape() -> Rect2:
	if kind == "fireball":
		return Rect2(position - Vector2(30, 30), Vector2(60, 60))
	# low and wide: hits anything standing on the floor, misses jumpers
	return Rect2(position.x - 45, position.y - 70, 90, 70)


func _physics_process(delta: float) -> void:
	t += delta
	position.x += _speed() * direction * delta
	if kind == "shockwave" and fmod(t, 0.05) < delta:
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
				other.queue_free()
				queue_free()
				return

	var target := owner_fighter.opponent
	if target and _hit_shape().intersects(target.get_hurtbox()):
		if target.take_hit(_damage(), 220.0, 0.45, direction, kind == "shockwave"):
			Sound.sfx("fireball_hit" if kind == "fireball" else "kick", 0.0, 0.03)
		queue_free()
	elif position.x < -100 or position.x > 1380:
		queue_free()


func _draw() -> void:
	if kind == "fireball":
		_draw_fireball()
	else:
		_draw_shockwave()


func _draw_fireball() -> void:
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
