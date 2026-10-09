class_name UiLayoutCheck
extends RefCounted
## Layout audit for the readout UI (M3.6, 12 §2 UI scale, 12 §9 "no HUD overlap at UI scale
## 1.5 on 1280 × 720"): walks a laid-out Control tree and lists every visible Control that
## leaves the viewport, or leaves the Container that laid it out. The window's UI scale is a
## root content scale (SettingsApply.ui_scale), so a resolution and a UI scale meet the layout
## as one logical viewport size: logical_size() maps them.
## Exempt: zero-size and top_level controls. A plain Control may hang its children off its
## own rect (the HUD's caption anchor); only Containers promise to hold theirs. A
## ScrollContainer (MenuRows past its height cap) must fit; what scrolls inside it is clipped.

## Pixels of slack (sub-pixel rounding of centred and stretched layouts).
const TOLERANCE := 1.0


## The logical size the UI is laid out in for a window of `resolution` at `ui_scale`.
static func logical_size(resolution: Vector2i, ui_scale: float) -> Vector2i:
	var f := SettingsApply.content_scale(float(resolution.y), ui_scale)
	return Vector2i(roundi(resolution.x / f), roundi(resolution.y / f))


## One line per violation: `path: rect outside <what> rect`.
static func violations(root: Control, viewport: Rect2) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, root, viewport.grow(TOLERANCE), out)
	return out


static func _walk(root: Control, n: Node, view: Rect2, out: PackedStringArray) -> void:
	var c := n as Control
	if c != null:
		if not c.is_visible_in_tree():
			return
		var r := _rect(c)
		if not c.top_level and r.size.x > 0.5 and r.size.y > 0.5:
			if not view.encloses(r):
				out.append("%s: %s outside the viewport %s" % [_name(root, c), _fmt(r), _fmt(view.grow(-TOLERANCE))])
			var p := c.get_parent() as Container
			if p != null and p.is_visible_in_tree():
				var pr := _rect(p)
				if not pr.grow(TOLERANCE).encloses(r):
					out.append("%s: %s outside its container %s" % [_name(root, c), _fmt(r), _fmt(pr)])
	if n is ScrollContainer:
		return
	for ch in n.get_children():
		_walk(root, ch, view, out)


## The control's rect on its canvas, scale included (get_global_rect() leaves scale out).
static func _rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


static func _name(root: Node, c: Node) -> String:
	var s := String(root.get_path_to(c))
	if c is Label:
		s += " \"%s\"" % (c as Label).text.left(24)
	return s


static func _fmt(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
