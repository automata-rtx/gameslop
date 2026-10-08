class_name Credits
extends RefCounted
## The credits (16 §6; CHANGELOG 2026-10-07: they live in Strings): the AI disclosure, the
## Godot Engine with its MIT notice in full, every third-party component the engine carries
## (name and license, from Engine.get_copyright_info(), the notices tools/ci/licenses.gd
## writes into LICENSES.txt), the bundled typeface with its copyright line, the sound (all
## synthesized; no CC0 recording is used, so none is listed, 03 §1), where the full license
## texts are, and "Thank you for looking." Shown by the ending (CreditsRoll); the Archive can
## show the same entries. Pure data: no nodes.

const STYLE_LINE := &"line"
const STYLE_HEADING := &"heading"
const STYLE_SMALL := &"small"
const STYLE_COMPONENT := &"component"
const STYLE_GAP := &"gap"
const STYLE_THANKS := &"thanks"
## The engine's own entry in its copyright list (its MIT text is printed in full instead).
const ENGINE_ENTRY := "Godot Engine"


## The credits in order: [{text, style}]. Gaps carry an empty text.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add(out, Strings.CREDITS_AI, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_HEADING_ENGINE, STYLE_HEADING)
	_add(out, Strings.CREDITS_GODOT, STYLE_LINE)
	for l in godot_license_lines():
		_add(out, l, STYLE_SMALL)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_HEADING_COMPONENTS, STYLE_HEADING)
	for l in component_lines():
		_add(out, l, STYLE_COMPONENT)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_HEADING_TYPEFACE, STYLE_HEADING)
	_add(out, Strings.CREDITS_FONT, STYLE_LINE)
	_add(out, Strings.CREDITS_FONT_COPYRIGHT, STYLE_SMALL)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_HEADING_SOUND, STYLE_HEADING)
	_add(out, Strings.CREDITS_SOUND, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_LICENSES_NOTE, STYLE_SMALL)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_THANKS, STYLE_THANKS)
	return out


## Every text the credits print, one per line (tests, the forbidden-words check).
static func text() -> String:
	var lines := PackedStringArray()
	for e in entries():
		if e["style"] != STYLE_GAP:
			lines.append(String(e["text"]))
	return "\n".join(lines)


## The engine's MIT notice, line by line (16 §6: required to be included), blank lines kept
## out so the roll stays even.
static func godot_license_lines() -> Array[String]:
	var out: Array[String] = []
	for l in Engine.get_license_text().split("\n"):
		var s := l.strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


## One line per third-party component of the engine: `name · license` (the license ids of its
## parts, in order, without repeats).
static func component_lines() -> Array[String]:
	var out: Array[String] = []
	for info: Dictionary in Engine.get_copyright_info():
		var n := String(info.get("name", ""))
		if n.is_empty() or n == ENGINE_ENTRY:
			continue
		var licenses: Array[String] = []
		for part: Dictionary in info.get("parts", []):
			var lic := String(part.get("license", ""))
			if not lic.is_empty() and not licenses.has(lic):
				licenses.append(lic)
		out.append(Strings.CREDITS_COMPONENT_LINE.replace("{name}", n).replace("{license}", ", ".join(licenses)))
	return out


static func _add(out: Array[Dictionary], text_value: String, style: StringName) -> void:
	out.append({"text": text_value, "style": style})
