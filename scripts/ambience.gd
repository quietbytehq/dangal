class_name Ambience
extends Node2D
## Cheap, code-drawn life for the stage backgrounds: no extra art, no credits.
## Sits just in front of the background (and its video loop) and behind props and fighters.
## Positions are in the 1280x720 stage space and match the painted backgrounds.

var stage := 0          # 0 = Karachi Rooftop, 1 = Hunza Valley
var t := 0.0
var _items: Array = []  # moving things: kites, birds, petals, clouds...
var _twinkles: Array = []
var _plane_x := -200.0


func setup(stage_idx: int) -> void:
	stage = stage_idx
	t = 0.0
	_items.clear()
	_twinkles.clear()
	z_index = -9
	if stage == 0:
		# kites (patang) bobbing in the night sky
		for i in 4:
			_items.append({"kind": "kite", "x": randf_range(380, 1200), "y": randf_range(60, 200),
					"phase": randf() * TAU, "drift": randf_range(-6, 6), "size": randf_range(14, 22),
					"col": [Color(1, 0.3, 0.4), Color(0.3, 0.9, 0.5), Color(1, 0.85, 0.2), Color(0.5, 0.6, 1)][i]})
		# crows crossing
		for i in 3:
			_items.append(_new_bird(true))
		# city window lights twinkling across the skyline
		for i in 70:
			_twinkles.append({"p": Vector2(randf_range(380, 1240), randf_range(130, 390)),
					"phase": randf() * TAU, "speed": randf_range(0.6, 3.0), "col": Color(1, 0.85, 0.5)})
		# fairy-light string, top left
		for i in 14:
			var x: float = 10.0 + i * 26.0
			_twinkles.append({"p": Vector2(x, 140.0 + sin(i * 0.9) * 8.0), "phase": randf() * TAU,
					"speed": randf_range(2.0, 5.0), "big": true,
					"col": [Color(1, 0.3, 0.3), Color(0.3, 1, 0.5), Color(0.4, 0.6, 1), Color(1, 0.85, 0.3)][i % 4]})
	else:
		for i in 5:
			_items.append({"kind": "cloud", "x": randf_range(-100, 1300), "y": randf_range(20, 170),
					"speed": randf_range(6, 14), "w": randf_range(90, 180), "a": randf_range(0.10, 0.22)})
		for i in 2:
			_items.append(_new_bird(false))
		for i in 26:
			_items.append(_new_petal(true))
		# sunlight sparkle on the river
		for i in 18:
			_twinkles.append({"p": Vector2(randf_range(850, 950), randf_range(560, 610)), "phase": randf() * TAU,
					"speed": randf_range(2.0, 6.0), "col": Color(1, 1, 0.9)})
		# dust motes in the golden light
		for i in 30:
			_items.append({"kind": "mote", "x": randf_range(0, 1280), "y": randf_range(200, 640),
					"phase": randf() * TAU, "speed": randf_range(4, 12)})


func _new_bird(crow: bool) -> Dictionary:
	var left: bool = randf() < 0.5
	return {"kind": "crow" if crow else "eagle", "x": -40.0 if left else 1320.0,
			"y": randf_range(40, 220), "vx": (1.0 if left else -1.0) * randf_range(60, 110),
			"phase": randf() * TAU, "wait": randf_range(0, 9), "cx": randf_range(500, 900),
			"r": randf_range(60, 120)}


func _new_petal(anywhere: bool) -> Dictionary:
	# blossom trees stand at the left and right edges of the courtyard
	var from_left: bool = randf() < 0.7
	var x: float = randf_range(0, 380) if from_left else randf_range(1150, 1280)
	return {"kind": "petal", "x": x, "y": randf_range(0, 650) if anywhere else randf_range(60, 380),
			"vx": randf_range(10, 45) * (1.0 if from_left else -1.0), "vy": randf_range(25, 55),
			"phase": randf() * TAU, "spin": randf_range(2, 6),
			"col": Color(1, randf_range(0.75, 0.9), randf_range(0.75, 0.85), 0.9)}


func _process(delta: float) -> void:
	t += delta
	for it in _items:
		match it["kind"]:
			"kite":
				it["x"] += it["drift"] * delta
				if it["x"] < 360 or it["x"] > 1240:
					it["drift"] = -it["drift"]
			"crow":
				if it["wait"] > 0.0:
					it["wait"] -= delta
				else:
					it["x"] += it["vx"] * delta
					if it["x"] < -60 or it["x"] > 1340:
						it.merge(_new_bird(true), true)
			"eagle":
				it["phase"] += delta * 0.35
			"cloud":
				it["x"] += it["speed"] * delta
				if it["x"] - it["w"] > 1280:
					it["x"] = -it["w"] * 1.5
			"petal":
				it["x"] += (it["vx"] + sin(t * 1.3 + it["phase"]) * 20.0) * delta
				it["y"] += it["vy"] * delta
				if it["y"] > 700 or it["x"] < -20 or it["x"] > 1300:
					it.merge(_new_petal(false), true)
			"mote":
				it["y"] -= it["speed"] * delta
				if it["y"] < 180:
					it["y"] = 640.0
	_plane_x += 45.0 * delta
	if _plane_x > 1500:
		_plane_x = -300.0
	queue_redraw()


func _draw() -> void:
	for tw in _twinkles:
		var a: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * tw["speed"] + tw["phase"]))
		var c: Color = tw["col"]
		if tw.get("big", false):
			draw_circle(tw["p"], 7.0, Color(c.r, c.g, c.b, 0.18 * a))
			draw_circle(tw["p"], 3.0, Color(c.r, c.g, c.b, a))
		elif stage == 1:
			draw_circle(tw["p"], 1.6, Color(c.r, c.g, c.b, a * a * 0.9))
		else:
			draw_rect(Rect2(tw["p"], Vector2(2, 2)), Color(c.r, c.g, c.b, a * 0.6))
	if stage == 0:
		# sea glint under the moon
		for i in 6:
			var x: float = 1040.0 + i * 38.0 + sin(t * 0.7 + i) * 10.0
			var a: float = 0.25 + 0.25 * sin(t * 2.3 + i * 1.7)
			draw_line(Vector2(x, 236 + i % 2 * 6), Vector2(x + 20, 236 + i % 2 * 6), Color(1, 1, 0.85, a), 2.0)
		# a plane crossing high up, blinking
		var blink: float = 1.0 if fmod(t, 1.2) < 0.15 else 0.25
		draw_circle(Vector2(_plane_x, 46), 2.5, Color(1, 0.2, 0.2, blink))
		draw_circle(Vector2(_plane_x + 8, 46), 1.5, Color(1, 1, 1, 0.7))
	for it in _items:
		match it["kind"]:
			"kite":
				var bob: float = sin(t * 1.4 + it["phase"]) * 10.0
				var sway: float = sin(t * 0.9 + it["phase"]) * 0.25
				var p: Vector2 = Vector2(it["x"], it["y"] + bob)
				var s: float = it["size"]
				var pts: PackedVector2Array = PackedVector2Array([p + Vector2(0, -s).rotated(sway), p + Vector2(s * 0.8, 0).rotated(sway),
						p + Vector2(0, s).rotated(sway), p + Vector2(-s * 0.8, 0).rotated(sway)])
				var c: Color = it["col"]
				draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.85))
				# tail and string
				var tail: Vector2 = pts[2]
				for k in 5:
					var q: Vector2 = tail + Vector2(sin(t * 3.0 + k + it["phase"]) * 5.0, k * 7.0)
					draw_line(tail, q, Color(c.r, c.g, c.b, 0.6), 1.5)
					tail = q
				draw_line(pts[2], pts[2] + Vector2(-140, 300), Color(1, 1, 1, 0.12), 1.0)
			"crow":
				if it["wait"] <= 0.0:
					_draw_bird(Vector2(it["x"], it["y"] + sin(t * 2.0 + it["phase"]) * 6.0), 9.0,
							t * 9.0 + it["phase"], Color(0.05, 0.05, 0.08, 0.9))
			"eagle":
				var c: Vector2 = Vector2(it["cx"], 120.0) + Vector2(cos(it["phase"]), sin(it["phase"]) * 0.35) * it["r"]
				_draw_bird(c, 13.0, t * 2.5 + it["phase"], Color(0.15, 0.1, 0.08, 0.8))
			"cloud":
				var a: float = it["a"]
				var w: float = it["w"]
				for k in 4:
					draw_circle(Vector2(it["x"] + (k - 1.5) * w * 0.3, it["y"] + (0 if k % 3 else 8)),
							w * 0.28, Color(1, 0.95, 0.92, a))
			"petal":
				var r: float = 3.5
				var ang: float = t * it["spin"] + it["phase"]
				var p: Vector2 = Vector2(it["x"], it["y"])
				draw_set_transform(p, ang, Vector2(1.0, 0.45 + 0.4 * abs(sin(ang))))
				draw_circle(Vector2.ZERO, r, it["col"])
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"mote":
				var a: float = 0.25 + 0.25 * sin(t * 1.5 + it["phase"])
				draw_circle(Vector2(it["x"] + sin(t * 0.8 + it["phase"]) * 12.0, it["y"]), 1.6,
						Color(1, 0.9, 0.6, a))


func _draw_bird(p: Vector2, s: float, flap: float, col: Color) -> void:
	var w: float = sin(flap) * 0.6
	draw_line(p, p + Vector2(-s, -s * w), col, 2.0)
	draw_line(p, p + Vector2(s, -s * w), col, 2.0)
