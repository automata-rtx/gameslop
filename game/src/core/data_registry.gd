class_name DataRegistry
extends RefCounted
## Read-only access to the authored data resources under res://data (14 §6).
## Resources are shared: callers must never mutate them (duplicate(true) for runtime copies).
## Folders are listed with ResourceLoader.list_directory, which resolves the .remap files of
## exported builds. Order is canonical (the order the design documents list things in), not
## filesystem order.

const NOTES_DIR := "res://data/notes"
const ITEMS_DIR := "res://data/items"
const STRATA_DIR := "res://data/strata"
const ERRORS_DIR := "res://data/errors"
const LOADOUTS_DIR := "res://data/loadouts"

const STRATUM_ORDER: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]
const ITEM_ORDER: Array[StringName] = [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse", &"keycard"]
const ERROR_ORDER: Array[StringName] = [&"static", &"still", &"flicker", &"echo", &"null"]
const LOADOUT_ORDER: Array[StringName] = [&"faller", &"cartographer", &"lightbearer", &"diver"]

static var _notes: Array[NoteData] = []
static var _items: Array[ItemData] = []
static var _strata: Array[StratumData] = []
static var _errors: Array[ErrorData] = []
static var _loadouts: Array[LoadoutData] = []
static var _loaded: bool = false

## All 36 notes in stratum order (H1..H6, P1..P6, ..., U1..U6).
static func notes() -> Array[NoteData]:
	_ensure_loaded()
	return _notes

## The note with this id, or null.
static func note(id: StringName) -> NoteData:
	_ensure_loaded()
	for n in _notes:
		if n.id == id:
			return n
	return null

## The notes of one stratum, in id order.
static func notes_for(stratum: StringName) -> Array[NoteData]:
	_ensure_loaded()
	var out: Array[NoteData] = []
	for n in _notes:
		if n.stratum == stratum:
			out.append(n)
	return out

## The six belt items plus the keycard.
static func items() -> Array[ItemData]:
	_ensure_loaded()
	return _items

## The item of this kind, or null.
static func item(kind: StringName) -> ItemData:
	_ensure_loaded()
	for i in _items:
		if i.kind == kind:
			return i
	return null

static func strata() -> Array[StratumData]:
	_ensure_loaded()
	return _strata

## The stratum with this id (&"halls" ...), or null.
static func stratum(id: StringName) -> StratumData:
	_ensure_loaded()
	for s in _strata:
		if s.id == id:
			return s
	return null

static func errors() -> Array[ErrorData]:
	_ensure_loaded()
	return _errors

## The error with this id (&"static", &"still", &"flicker", &"echo", &"null"), or null.
static func error(id: StringName) -> ErrorData:
	_ensure_loaded()
	for e in _errors:
		if e.id == id:
			return e
	return null

static func loadouts() -> Array[LoadoutData]:
	_ensure_loaded()
	return _loadouts

## The loadout with this id (&"faller" ...), or null.
static func loadout(id: StringName) -> LoadoutData:
	_ensure_loaded()
	for l in _loadouts:
		if l.id == id:
			return l
	return null

## Drops the cache so the next call reloads from disk (tests, hot edits).
static func reload() -> void:
	_notes = []
	_items = []
	_strata = []
	_errors = []
	_loadouts = []
	_loaded = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	for res in _load_dir(NOTES_DIR):
		if res is NoteData:
			_notes.append(res)
	_notes.sort_custom(_note_before)
	for res in _load_dir(ITEMS_DIR):
		if res is ItemData:
			_items.append(res)
	_items.sort_custom(func(a: ItemData, b: ItemData) -> bool: return _rank(ITEM_ORDER, a.kind) < _rank(ITEM_ORDER, b.kind))
	for res in _load_dir(STRATA_DIR):
		if res is StratumData:
			_strata.append(res)
	_strata.sort_custom(func(a: StratumData, b: StratumData) -> bool: return _rank(STRATUM_ORDER, a.id) < _rank(STRATUM_ORDER, b.id))
	for res in _load_dir(ERRORS_DIR):
		if res is ErrorData:
			_errors.append(res)
	_errors.sort_custom(func(a: ErrorData, b: ErrorData) -> bool: return _rank(ERROR_ORDER, a.id) < _rank(ERROR_ORDER, b.id))
	for res in _load_dir(LOADOUTS_DIR):
		if res is LoadoutData:
			_loadouts.append(res)
	_loadouts.sort_custom(func(a: LoadoutData, b: LoadoutData) -> bool: return _rank(LOADOUT_ORDER, a.id) < _rank(LOADOUT_ORDER, b.id))
	_loaded = true

static func _note_before(a: NoteData, b: NoteData) -> bool:
	var ra := _rank(STRATUM_ORDER, a.stratum)
	var rb := _rank(STRATUM_ORDER, b.stratum)
	if ra != rb:
		return ra < rb
	return String(a.id) < String(b.id)

static func _rank(order: Array[StringName], id: StringName) -> int:
	var i := order.find(id)
	return i if i != -1 else order.size()

## Loads every resource directly inside `dir`. Exported builds list `.tres` files as
## `.tres.remap` or `.res`; list_directory returns loadable names either way.
static func _load_dir(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var names := ResourceLoader.list_directory(dir)
	if names.is_empty():
		push_error("DataRegistry: no resources found in %s" % dir)
		return out
	for entry in names:
		if entry.ends_with("/") or entry.ends_with(".uid"):
			continue
		var res := ResourceLoader.load(dir.path_join(entry))
		if res == null:
			push_error("DataRegistry: failed to load %s/%s" % [dir, entry])
			continue
		out.append(res)
	return out
