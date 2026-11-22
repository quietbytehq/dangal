class_name SpriteLibrary
extends RefCounted
## Builds a SpriteFrames resource from the sprite sheets plus their JSON metadata.


static func load_character(dir: String, json_name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(dir.path_join(json_name))
	var meta: Dictionary = JSON.parse_string(text)
	var w := int(meta["frame_width"])
	var h := int(meta["frame_height"])
	var fps := float(meta["fps"])

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var counts := {}
	var anims: Dictionary = meta["animations"]
	for anim_name in anims:
		var a: Dictionary = anims[anim_name]
		var tex: Texture2D = load(dir.path_join(str(a["file"])))
		var cols := int(a["columns"])
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, bool(a["loop"]))
		for i in int(a["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2((i % cols) * w, int(i / cols) * h, w, h)
			frames.add_frame(anim_name, at)
		counts[anim_name] = int(a["frames"])

	var anchor: Dictionary = meta["feet_anchor"]
	return {
		"frames": frames,
		"fps": fps,
		"counts": counts,
		"anchor": Vector2(float(anchor["x"]), float(anchor["y"])),
		"body_height": float(meta.get("body_height", h * 0.8)),
	}
