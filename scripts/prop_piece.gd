class_name PropPiece
extends Sprite2D
## One flying fragment of a shattered prop: tumbles, bounces on the floor, fades out.

const GRAVITY := 2200.0
var vel := Vector2.ZERO
var spin := 0.0
var floor_y := 640.0
var life := 2.5
var _age := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON


func _physics_process(delta: float) -> void:
	_age += delta
	vel.y += GRAVITY * delta
	position += vel * delta
	rotation += spin * delta
	var half: float = texture.get_size().y * 0.4 if texture else 4.0
	if position.y + half > floor_y:
		position.y = floor_y - half
		vel.y = -vel.y * 0.3
		vel.x *= 0.7
		spin *= 0.6
	if _age > life - 0.6:
		modulate.a = clamp((life - _age) / 0.6, 0.0, 1.0)
	if _age >= life:
		queue_free()
