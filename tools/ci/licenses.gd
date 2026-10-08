extends SceneTree
## Writes LICENSES.txt for a build zip (16 §3, §6): the Godot Engine license, the copyright
## notices of the engine's third-party components with their license texts, and the bundled
## font's OFL. Run by tools/ci/export.sh:
##   $GODOT_BIN --headless --path game --script <repo>/tools/ci/licenses.gd -- <out file>

const FONT_LICENSE := "res://assets/fonts/OFL.txt"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("licenses: usage: -- <out file>")
		quit(2)
		return
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		push_error("licenses: cannot write %s" % args[0])
		quit(1)
		return
	f.store_string(text())
	f.close()
	quit(0)


static func text() -> String:
	var out := PackedStringArray()
	out.append("NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine.")
	out.append("")
	out.append("=== Godot Engine ===")
	out.append("")
	out.append(Engine.get_license_text())
	out.append("")
	out.append("=== Third-party components of the Godot Engine ===")
	for info: Dictionary in Engine.get_copyright_info():
		out.append("")
		out.append("- %s" % info.get("name", ""))
		for part: Dictionary in info.get("parts", []):
			for c: String in part.get("copyright", PackedStringArray()):
				out.append("  Copyright %s" % c)
			out.append("  License: %s" % part.get("license", ""))
	out.append("")
	out.append("=== License texts ===")
	var licenses: Dictionary = Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for n: String in names:
		out.append("")
		out.append("--- %s ---" % n)
		out.append("")
		out.append(String(licenses[n]))
	out.append("")
	out.append("=== Font: JetBrains Mono (SIL Open Font License 1.1) ===")
	out.append("")
	out.append(FileAccess.get_file_as_string(FONT_LICENSE))
	return "\n".join(out)
