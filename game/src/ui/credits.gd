class_name Credits
extends RefCounted
## The credits (16 §6; CHANGELOG 2026-10-07: they live in Strings). Two readings (R17,
## CHANGELOG 2026-10-09, superseding the M2.15 roll content):
## - roll_entries(): what the ending rolls over the corridor (01 §8 step 4): 16 §6's lines
##   only: the AI disclosure, `Godot Engine. MIT license.`, the typeface line and its
##   copyright, the sound line (all synthesized; no CC0 recording is used, 03 §1), where the
##   full license texts are, and "Thank you for looking."
## - entries(): the full list for the LICENSES submenu (title settings, 16 §6) and the
##   Archive: the same lines plus the engine's MIT notice in full and every third-party
##   component the engine carries (name and license, from Engine.get_copyright_info(), the
##   notices tools/ci/licenses.gd writes into LICENSES.txt).
## Pure data: no nodes.

const STYLE_LINE := &"line"
const STYLE_HEADING := &"heading"
const STYLE_SMALL := &"small"
const STYLE_COMPONENT := &"component"
const STYLE_GAP := &"gap"
const STYLE_THANKS := &"thanks"
## The engine's own entry in its copyright list (its MIT text is printed in full instead).
const ENGINE_ENTRY := "Godot Engine"


## The ending's roll in order (16 §6's lines only): [{text, style}]. Gaps carry an empty text.
static func roll_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add(out, Strings.CREDITS_AI, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_GODOT, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_FONT, STYLE_LINE)
	_add(out, Strings.CREDITS_FONT_COPYRIGHT, STYLE_SMALL)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_SOUND, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_LICENSES_NOTE, STYLE_SMALL)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_THANKS, STYLE_THANKS)
	return out


## The full credits in order (the LICENSES submenu, the Archive): [{text, style}].
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add(out, Strings.CREDITS_AI, STYLE_LINE)
	_add(out, "", STYLE_GAP)
	_add(out, Strings.CREDITS_HEADING_ENGINE, STYLE_HEADING)
	_add(out, Strings.CREDITS_GODOT, STYLE_LINE)
	for l in license_paragraphs():
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


## Every text the full credits print, one per line (tests, the forbidden-words check).
static func text() -> String:
	return _join(entries())


## Every text the ending's roll prints, one per line.
static func roll_text() -> String:
	return _join(roll_entries())


static func _join(list: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	for e in list:
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


## The engine's MIT notice as paragraphs (M3.6): the text arrives hard-wrapped at 80
## columns, which a narrower column would wrap again into ragged pairs; each copyright line
## stays its own paragraph. Every original line is a substring of its paragraph.
static func license_paragraphs() -> Array[String]:
	var out: Array[String] = []
	var current := ""
	for l in Engine.get_license_text().split("\n"):
		var s := l.strip_edges()
		if s.is_empty() or s.begins_with("Copyright"):
			if not current.is_empty():
				out.append(current)
			current = s
			continue
		current = s if current.is_empty() else current + " " + s
	if not current.is_empty():
		out.append(current)
	return out


## One line per third-party component of the engine: `name · license` (the license ids of its
## parts, in order, without repeats).
static func component_lines() -> Array[String]:
	var out: Array[String] = []
	for c in components():
		out.append(Strings.CREDITS_COMPONENT_LINE.replace("{name}", c["name"]).replace("{license}", c["license"]))
	return out


## The engine's third-party components in its order: [{name, license}], the license being the
## ids of its parts, in order, without repeats, joined by ", ".
static func components() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for info: Dictionary in Engine.get_copyright_info():
		var n := String(info.get("name", ""))
		if n.is_empty() or n == ENGINE_ENTRY:
			continue
		var licenses: Array[String] = []
		for part: Dictionary in info.get("parts", []):
			var lic := String(part.get("license", ""))
			if not lic.is_empty() and not licenses.has(lic):
				licenses.append(lic)
		out.append({"name": n, "license": ", ".join(licenses)})
	return out


static func _add(out: Array[Dictionary], text_value: String, style: StringName) -> void:
	out.append({"text": text_value, "style": style})
