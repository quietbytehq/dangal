class_name Prop
extends Node2D
## A breakable / movable stage object (crate, clay pot, barrel ...).
## Simple custom physics: gravity, bounce, friction, spin. Hits from attacks,
## knocked-back fighters, specials and other flying props push it around;
## breakable props shatter into tumbling pieces when their health runs out.

const GRAVITY := 2200.0
const KINDS := {
	# material: sound + how it reacts. hp < 0 means unbreakable (it just tumbles).
	"crate":      {"hp": 110, "mass": 1.3, "bounce": 0.25, "sound": "break_wood",   "pieces": Vector2i(3, 3)},
	"matka":      {"hp": 35,  "mass": 1.0, "bounce": 0.2,  "sound": "break_pot",    "pieces": Vector2i(4, 3)},
	"drum":       {"hp": -1,  "mass": 1.1, "bounce": 0.45, "sound": "break_barrel", "pieces": Vector2i(1, 1)},
	"basket":     {"hp": 60,  "mass": 0.8, "bounce": 0.3,  "sound": "break_wood",   "pieces": Vector2i(4, 3)},
	"copper_pot": {"hp": -1,  "mass": 0.9, "bounce": 0.5,  "sound": "break_barrel", "pieces": Vector2i(1, 1)},
	"firewood":   {"hp": 90,  "mass": 1.5, "bounce": 0.2,  "sound": "break_wood",   "pieces": Vector2i(2, 4)},
}

var kind := "crate"
var hp := 100
var mass := 1.0
var bounce := 0.3
var vel := Vector2.ZERO
var spin := 0.0
var floor_y := 640.0
var size := Vector2(100, 100)
var broken := false
var _cooldown := 0.0
var _flash := 0.0
var _sprite: Sprite2D
var _tex: Texture2D


func setup(k: String, x: float, ground_y: float) -> void:
	kind = k
	var d: Dictionary = KINDS[k]
	hp = d["hp"]
	mass = d["mass"]
	bounce = d["bounce"]
	floor_y = ground_y
	_tex = load("res://assets/props/%s.png" % k)
	_sprite = Sprite2D.new()
	_sprite.texture = _tex
	add_child(_sprite)
	size = _tex.get_size() if _tex else Vector2(100, 100)
	position = Vector2(x, floor_y - size.y / 2.0)   # origin at the prop's centre
	z_index = -1
	add_to_group("props")


func get_rect() -> Rect2:
	return Rect2(position - size / 2.0, size)


## Push the prop. force is a velocity change in px/s (scaled by mass); damage wears it down.
func hit(force: Vector2, damage: int, quiet := false) -> void:
	if broken or _cooldown > 0.0:
		return
	_cooldown = 0.12
	vel += force / mass
	spin += force.x / mass * 0.012 + randf_range(-2.0, 2.0)
	if not quiet:
		_flash = 0.08
	if hp >= 0:
		hp -= damage
		if hp <= 0:
			_shatter(force)
			return
	if not quiet:
		Sound.sfx(KINDS[kind]["sound"], -8.0 if hp >= 0 else -4.0, 0.15)


func _physics_process(delta: float) -> void:
	if broken:
		return
	_cooldown = max(_cooldown - delta, 0.0)
	_flash = max(_flash - delta, 0.0)
	_sprite.modulate = Color(1.8, 1.8, 1.8) if _flash > 0.0 else Color.WHITE

	vel.y += GRAVITY * delta
	position += vel * delta
	rotation += spin * delta

	# floor contact: half-height grows towards half-width as the prop tips over
	var tip: float = abs(sin(rotation))
	var half: float = lerp(size.y / 2.0, size.x / 2.0, tip)
	if position.y + half >= floor_y:
		position.y = floor_y - half
		if vel.y > 120.0:
			vel.y = -vel.y * bounce
			if vel.y < -150.0:
				Sound.sfx(KINDS[kind]["sound"], -16.0, 0.2)
		else:
			vel.y = 0.0
		vel.x = move_toward(vel.x, 0.0, 900.0 * delta)        # friction
		spin = move_toward(spin, 0.0, 10.0 * delta)
		# settle upright, or onto a side, when it has nearly stopped
		if abs(spin) < 1.5 and abs(vel.x) < 60.0:
			var target: float = round(rotation / (PI / 2.0)) * (PI / 2.0)
			rotation = lerp_angle(rotation, target, 8.0 * delta)

	# stage walls
	if position.x < 20.0 + size.x / 2.0 or position.x > 1260.0 - size.x / 2.0:
		position.x = clamp(position.x, 20.0 + size.x / 2.0, 1260.0 - size.x / 2.0)
		vel.x = -vel.x * 0.5
		spin = -spin * 0.5

	# a fast-moving prop knocks into the others
	if abs(vel.x) > 220.0:
		for other in get_tree().get_nodes_in_group("props"):
			if other != self and not other.broken and get_rect().intersects(other.get_rect()):
				other.hit(Vector2(vel.x * 0.7, -180.0), 30)
				vel.x *= 0.4


func _shatter(force: Vector2) -> void:
	broken = true
	Sound.sfx(KINDS[kind]["sound"], 0.0, 0.1)
	var grid: Vector2i = KINDS[kind]["pieces"]
	var cell := size / Vector2(grid)
	for gx in grid.x:
		for gy in grid.y:
			var piece := PropPiece.new()
			var at := AtlasTexture.new()
			at.atlas = _tex
			at.region = Rect2(Vector2(gx, gy) * cell, cell)
			piece.texture = at
			piece.z_index = -1
			var local := (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell - size / 2.0
			piece.position = position + local.rotated(rotation)
			piece.rotation = rotation
			piece.floor_y = floor_y
			piece.vel = Vector2(force.x * randf_range(0.3, 0.9) + local.x * randf_range(3.0, 6.0),
					-randf_range(350.0, 800.0) + local.y * 2.0)
			piece.spin = randf_range(-12.0, 12.0)
			get_parent().add_child(piece)
	if kind == "matka":
		_splash()
	queue_free()


func _splash() -> void:
	for i in 14:
		var drop := PropPiece.new()
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.75, 1.0, 0.85))
		drop.texture = ImageTexture.create_from_image(img)
		drop.position = position
		drop.floor_y = floor_y
		drop.vel = Vector2(randf_range(-300, 300), -randf_range(200, 600))
		drop.life = 0.8
		get_parent().add_child(drop)
