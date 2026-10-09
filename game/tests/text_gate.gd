extends RefCounted
## The text gate's engine (M3.7). One place that knows what "player-facing text" is and what
## the rules are, so tests/unit/test_text_gate.gd can prove the rules fire on a planted fixture
## and that nothing shipped trips them.
##
## Rules:
## - 01 §2 and the GLOSSARY: the forbidden words never appear in game text, code literals,
##   scenes, data, the README that ships, or the store page facts ("liminal" is allowed on the
##   store page only, as a genre word).
## - 01 §6 rule 1 and 04: no exclamation marks, no ellipses, no double spaces in UI text.
##   The single-character "!" literal is the colour-blind danger mark (12 §6), not a sentence.
## - CLAUDE.md and 16 §6: no model name anywhere that ships; the AI is "an AI (Claude, Anthropic)".

const FORBIDDEN := "\\b(backrooms|liminal|level 0|almond water|entity|entities|smiler|bacteria|partygoer|monsters?|enem(y|ies))\\b"
## Model identifiers. Case-insensitive; "claude" followed by a digit or hyphen is a model id.
const MODEL_NAMES := "(?i)\\b(sonnet|opus|haiku|gpt-?[0-9]|gemini|llama|fable|claude[- ][0-9a-z])"
## The one phrase that may name the AI (16 §6).
const AI_PHRASE := "an AI (Claude, Anthropic)"
const STORE_SCOPE_FILE := "../docs/design/16_release_and_steam.md"
const README_FILE := "../tools/ci/README.txt.in"

static var _forbidden_re: RegEx
static var _model_re: RegEx


static func forbidden_re() -> RegEx:
	if _forbidden_re == null:
		_forbidden_re = RegEx.create_from_string("(?i)" + FORBIDDEN)
	return _forbidden_re


static func model_re() -> RegEx:
	if _model_re == null:
		_model_re = RegEx.create_from_string(MODEL_NAMES)
	return _model_re


## Forbidden words in `text`: ["entity", ...]. `allow_liminal` is for the store page.
static func forbidden_hits(text: String, allow_liminal: bool = false) -> PackedStringArray:
	var out: PackedStringArray = []
	for m in forbidden_re().search_all(text):
		var w := m.get_string().to_lower()
		if allow_liminal and w == "liminal":
			continue
		out.append(w)
	return out


## 01 §6 / 04 punctuation: ["exclamation mark", "ellipsis", "double space"].
## `spacing` is false for pre-formatted text (the README's columns).
static func style_hits(text: String, spacing: bool = true) -> PackedStringArray:
	var out: PackedStringArray = []
	if text.length() > 1 and text.contains("!"):
		out.append("exclamation mark")
	if text.contains("…") or text.contains("..."):
		out.append("ellipsis")
	if spacing and text.contains("  "):
		out.append("double space")
	return out


## Every model identifier in `text`, and every use of "Claude" or "Anthropic" outside the one
## allowed phrase.
static func model_hits(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for m in model_re().search_all(text):
		out.append(m.get_string())
	var rest := text.replace(AI_PHRASE, "")
	for word in ["Claude", "Anthropic"]:
		if rest.contains(word):
			out.append(word + " outside the AI phrase")
	return out


## The string literals of GDScript source, comments removed: [{line, text}].
## Handles escapes and both quote styles; docstring triple quotes are treated as plain.
static func code_literals(source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines := source.split("\n")
	for i in lines.size():
		var s := lines[i]
		var j := 0
		var quote := ""
		var buf := ""
		while j < s.length():
			var c := s[j]
			if quote.is_empty():
				if c == "#":
					break
				if c == "\"" or c == "'":
					quote = c
					buf = ""
			elif c == "\\":
				buf += s.substr(j, 2)
				j += 1
			elif c == quote:
				out.append({"line": i + 1, "text": buf})
				quote = ""
			else:
				buf += c
			j += 1
	return out


# ------------------------------------------------------------------------------ the corpus

## Every text the player can read, as [{src, text, kind}]. kind is "ui" (full style rules),
## "doc" (README: no double-space rule) or "store" ("liminal" allowed). Code literals and
## scene files are separate (code_corpus, file_corpus): they are scanned for forbidden words
## on all literals but for style only where a literal is a sentence.
static func ui_corpus() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var strings: Dictionary = (load("res://src/core/strings.gd") as GDScript).get_script_constant_map()
	for name in strings:
		_collect("Strings." + String(name), strings[name], out)
	for n in DataRegistry.notes():
		out.append({"src": "note " + String(n.id), "text": n.text, "kind": "ui"})
	for e in DataRegistry.errors():
		for t in [e.display_name, e.rule, e.counter, e.tell, e.cost, e.codex_text]:
			out.append({"src": "error " + String(e.id), "text": t, "kind": "ui"})
	for i in DataRegistry.items():
		out.append({"src": "item " + String(i.kind), "text": i.display_name, "kind": "ui"})
	for l in DataRegistry.loadouts():
		out.append({"src": "loadout " + String(l.id), "text": l.display_name, "kind": "ui"})
		out.append({"src": "loadout " + String(l.id), "text": l.description, "kind": "ui"})
	for s in DataRegistry.strata():
		out.append({"src": "stratum " + String(s.id), "text": s.display_name, "kind": "ui"})
	for line in (load("res://src/ui/credits.gd") as GDScript).call("entries"):
		out.append({"src": "credits", "text": String(line["text"]), "kind": "ui"})
	for s in (load("res://src/core/ending.gd") as GDScript).call("printed_texts"):
		out.append({"src": "ending", "text": String(s), "kind": "ui"})
	return out


static func _collect(label: String, value: Variant, out: Array[Dictionary]) -> void:
	if value is String or value is StringName:
		out.append({"src": label, "text": String(value), "kind": "ui"})
	elif value is Array:
		for i in (value as Array).size():
			_collect("%s[%d]" % [label, i], (value as Array)[i], out)
	elif value is Dictionary:
		for k in (value as Dictionary):
			_collect("%s[%s]" % [label, k], (value as Dictionary)[k], out)


## Text files that ship or that the game's page of facts reproduces: [{src, text, kind}].
## Missing files are reported as an empty text with kind "missing".
static func file_corpus() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := ProjectSettings.globalize_path("res://")
	var readme := FileAccess.get_file_as_string(root.path_join(README_FILE))
	out.append({"src": "README.txt.in", "text": readme, "kind": "doc" if not readme.is_empty() else "missing"})
	var design := FileAccess.get_file_as_string(root.path_join(STORE_SCOPE_FILE))
	var store := store_page_facts(design)
	out.append({"src": "store page facts (16 §5)", "text": store, "kind": "store" if not store.is_empty() else "missing"})
	return out


## 16 §5, the text between its heading and the next one.
static func store_page_facts(design_doc: String) -> String:
	var a := design_doc.find("## 5. Store page facts")
	if a < 0:
		return ""
	var b := design_doc.find("\n## ", a + 4)
	return design_doc.substr(a, b - a if b > 0 else -1)


## Every .gd, .tscn and .tres under the shipped folders, as [path]. Tests are not shipped
## and carry the planted words on purpose.
static func shipped_files(exts: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = []
	for dir in ["res://src", "res://scenes", "res://data", "res://shaders"]:
		_walk(dir, exts, out)
	out.sort()
	return out


static func _walk(dir: String, exts: Array[String], out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if exts.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), exts, out)
