class_name UltraFx
extends Node2D
## The payoff of an ultra.
##  - "beam":  Rustam's LIGHTNING STORM, a screen-wide lightning beam at chest height.
##  - "quake": Baba Sher's MOUNTAIN BREAKER, rock eruptions sweeping the whole floor.
##  - "dragon": Mei Lin's DRAGON DANCE, the beam's golden twin: a dragon of light across the screen.
##  - "rush":  Tiago's RIO SUBMISSION, a green-energy charge across the floor that slams into the opponent.
##  - "lion":  Jameel's LION OF DAGESTAN, the rush in gold: he storms in and finishes with a flying knee.
## Both can be blocked for chip damage (the quake only crouching); jumping dodges the quake.

const BEAM_TIME := 1.25
const QUAKE_SPEED := 1150.0
const RUSH_TIME := 0.75
const RUSH_SPEED := 980.0

var owner_fighter: Fighter
var kind := "beam"
var damage := 300
var t := 0.0
var _hit := false
var _beam: Vfx
var _x0 := 0.0
var _y := 0.0
var _dir := 1
var _wave_x := 0.0
var _next_rock := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	z_index = 6
	var f := owner_fighter
	_dir = f.facing
	if kind in ["beam", "dragon"]:
		_x0 = f.position.x + _dir * f.H * 0.45
		_y = f.position.y - f.H * 0.62
		Sound.sfx("beam_blast", 2.0, 0.0)
		f.quake.emit(10.0)
		var length := 1500.0
		_beam = Vfx.spawn(self, "lightning_beam", Vector2(_x0 + _dir * length * 0.5, _y), 1.0, _dir < 0, 6)
		if _beam:
			var w := float(Vfx.info("lightning_beam")["frame_width"])
			_beam.scale = Vector2(length / w * _dir, 1.25)
			if kind == "dragon":
				_beam.modulate = Color(1.8, 1.3, 0.35)
		Vfx.spawn(self, "fire_burst", Vector2(_x0, _y), 0.9)
	elif kind in ["rush", "lion"]:
		Sound.sfx("spin_whoosh", 2.0, 0.0)
	else:
		_wave_x = f.position.x + _dir * f.H * 0.4
		Sound.sfx("ground_pound", 3.0, 0.0)
		f.quake.emit(24.0)


func _beam_rect() -> Rect2:
	var length := 1500.0
	var band := owner_fighter.H * 0.32
	var left := _x0 if _dir > 0 else _x0 - length
	return Rect2(left, _y - band * 0.5, length, band)


func _physics_process(delta: float) -> void:
	t += delta
	var f := owner_fighter
	if f == null or not is_instance_valid(f):
		queue_free()
		return
	var o := f.opponent
	if kind in ["beam", "dragon"]:
		var r := _beam_rect()
		if not _hit and t > 0.06 and o and r.intersects(o.get_hurtbox()):
			_hit = true
			if o.take_hit(damage, 520.0, 0.8, _dir):
				Vfx.spawn(get_parent(), "fire_burst", o.get_hurtbox().get_center(), 1.1)
		for prop in get_tree().get_nodes_in_group("props"):
			if not prop.broken and r.intersects(prop.get_rect()):
				prop.hit(Vector2(_dir * 900.0, -500.0), 999)
		if _beam:
			_beam.modulate.a = clampf((BEAM_TIME - t) / 0.3, 0.0, 1.0)
		queue_redraw()
		if t >= BEAM_TIME:
			queue_free()
	elif kind in ["rush", "lion"]:
		_rush(delta, f, o)
	else:
		_wave_x += _dir * QUAKE_SPEED * delta
		_next_rock -= delta
		if _next_rock <= 0.0:
			_next_rock = 0.045
			Vfx.spawn(get_parent(), "rock_burst", Vector2(_wave_x + randf_range(-20, 20), f.floor_y),
					randf_range(0.7, 0.95), randf() < 0.5, 6, 1.4)
			if fmod(t, 0.2) < 0.05:
				f.quake.emit(10.0)
		for prop in get_tree().get_nodes_in_group("props"):
			if not prop.broken and abs(prop.position.x - _wave_x) < 60.0:
				prop.hit(Vector2(_dir * 500.0, -900.0), 999)
		if not _hit and o and abs(o.position.x - _wave_x) < 70.0:
			_hit = true
			if o._jump_lift() < o.H * 0.2:
				o.take_hit(damage, 420.0, 0.8, _dir, true)
		queue_redraw()
		if _wave_x < -150.0 or _wave_x > 1430.0:
			queue_free()


## Tiago charges forward until he reaches the opponent (or the charge runs out), then the slam.
func _rush(delta: float, f: Fighter, o: Fighter) -> void:
	if not _hit and t < RUSH_TIME:
		f.position.x = clamp(f.position.x + _dir * RUSH_SPEED * delta, f.bounds.x, f.bounds.y)
		var reach := Rect2(f.position.x + (0.0 if _dir > 0 else -f.H * 0.8), f.position.y - f.H * 0.95,
				f.H * 0.8, f.H * 0.95)
		if o and reach.intersects(o.get_hurtbox()):
			_hit = true
			var contact := (reach.get_center() + o.get_hurtbox().get_center()) * 0.5
			if o.take_hit(damage, 560.0, 0.9, _dir):
				Vfx.spawn(get_parent(), "fire_burst", contact, 1.25)
				# second, green burst (one-shot effect; looping ones like chi_orb never free themselves)
				var green := Vfx.spawn(get_parent(), "fire_burst", contact + Vector2(_dir * 30.0, -20.0), 1.0, _dir < 0, 6)
				if green:
					green.modulate = Color(1.8, 1.35, 0.35) if kind == "lion" else Color(0.5, 1.6, 0.45)
				Sound.sfx("ground_pound", 3.0, 0.0)
			f.quake.emit(22.0)
		for prop in get_tree().get_nodes_in_group("props"):
			if not prop.broken and reach.intersects(prop.get_rect()):
				prop.hit(Vector2(_dir * 800.0, -600.0), 999)
	queue_redraw()
	if t >= RUSH_TIME + 0.4:
		queue_free()


func _draw() -> void:
	# simple glow fallback, also adds punch under the video effects
	if kind in ["beam", "dragon"]:
		var r := _beam_rect()
		var a := clampf((BEAM_TIME - t) / 0.3, 0.0, 1.0)
		var core := Rect2(r.position.x, _y - r.size.y * 0.18, r.size.x, r.size.y * 0.36)
		var glow := Color(1.0, 0.75, 0.25) if kind == "dragon" else Color(0.4, 0.7, 1.0)
		var hot := Color(1.0, 0.95, 0.7) if kind == "dragon" else Color(0.85, 0.95, 1.0)
		draw_rect(r, Color(glow, 0.18 * a))
		draw_rect(core, Color(hot, 0.55 * a))
	elif kind in ["rush", "lion"]:
		# green-gold (or all-gold) streak trailing behind the charge
		if _hit or t >= RUSH_TIME:
			return
		var f := owner_fighter
		var left: float = f.position.x - f.H * 1.2 if _dir > 0 else f.position.x
		var trail := Color(1.0, 0.7, 0.2, 0.24) if kind == "lion" else Color(0.35, 1.0, 0.35, 0.22)
		draw_rect(Rect2(left, f.position.y - f.H * 0.72, f.H * 1.2, f.H * 0.5), trail)
		draw_rect(Rect2(left, f.position.y - f.H * 0.55, f.H * 1.2, f.H * 0.16), Color(1.0, 0.95, 0.4, 0.35))
	else:
		draw_circle(Vector2(_wave_x, owner_fighter.floor_y - 30.0), 60.0, Color(1.0, 0.8, 0.3, 0.25))
