class_name Vfx
extends AnimatedSprite2D
## Visual-effect animations (fire bursts, rock eruptions, energy beams, chi orbs).
## The effect frames were rendered on black, so they are drawn with additive blending:
## black adds nothing and only the glow shows.
## Sheets live in res://assets/vfx/<name>.png with <name>.json next to them.

static var _frames := {}
static var _meta := {}
static var _add_material: CanvasItemMaterial


static func available(fx_name: String) -> bool:
	return ResourceLoader.exists("res://assets/vfx/%s.png" % fx_name)


static func info(fx_name: String) -> Dictionary:
	_load(fx_name)
	return _meta.get(fx_name, {})


static func _load(fx_name: String) -> void:
	if _frames.has(fx_name) or not available(fx_name):
		return
	var meta: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/vfx/%s.json" % fx_name))
	var tex: Texture2D = load("res://assets/vfx/%s.png" % fx_name)
	var w := int(meta["frame_width"])
	var h := int(meta["frame_height"])
	var cols := int(meta["columns"])
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", float(meta["fps"]))
	sf.set_animation_loop("default", bool(meta["loop"]))
	for i in int(meta["frames"]):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * w, int(i / cols) * h, w, h)
		sf.add_frame("default", at)
	_frames[fx_name] = sf
	_meta[fx_name] = meta


## Spawn an effect. For one-shot effects the node frees itself when done.
## anchor "bottom" puts the effect's bottom edge on `pos` (for things that erupt from the floor).
static func spawn(parent: Node, fx_name: String, pos: Vector2, scl := 1.0, flip := false,
		z := 5, speed := 1.0) -> Vfx:
	_load(fx_name)
	if not _frames.has(fx_name) or parent == null:
		return null
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var meta: Dictionary = _meta[fx_name]
	var v := Vfx.new()
	v.sprite_frames = _frames[fx_name]
	v.material = _add_material
	v.position = pos
	v.scale = Vector2(scl * (-1.0 if flip else 1.0), scl)
	v.z_index = z
	if str(meta.get("anchor", "center")) == "bottom":
		v.offset = Vector2(0, -float(meta["frame_height"]) * 0.5)
	parent.add_child(v)
	v.play("default", speed)
	if not bool(meta["loop"]):
		v.animation_finished.connect(v.queue_free)
	return v
