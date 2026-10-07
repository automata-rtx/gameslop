class_name CliArgs
extends RefCounted
## Debug launch flags after `--` on the command line (14 §9):
##   --seed N --depth D --stratum S   launch straight into a generated level
##   --smoke                          boot, generate depth 1, wait 2 s, quit 0
##   --tour [out_dir]                 screenshot tour (needs a GPU)
##   --validate-levels N              generate and validate N levels per stratum
## Both `--flag value` and `--flag=value` are accepted. Bad values warn and are ignored.

## GLOSSARY: the six strata ids.
const STRATA: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]
const DEFAULT_TOUR_DIR := "build/tour"

var has_seed: bool = false
var run_seed: int = 0
## 0 when not given.
var depth: int = 0
## &"" when not given.
var stratum: StringName = &""
var smoke: bool = false
var tour: bool = false
var tour_dir: String = ""
## 0 when not given.
var validate_levels: int = 0


## The flags of this process (OS.get_cmdline_user_args()).
static func current() -> CliArgs:
	return parse(OS.get_cmdline_user_args())


static func parse(args: PackedStringArray) -> CliArgs:
	var out := CliArgs.new()
	var i := 0
	while i < args.size():
		var flag := args[i]
		var value := ""
		var has_inline := false
		var eq := flag.find("=")
		if flag.begins_with("--") and eq != -1:
			value = flag.substr(eq + 1)
			flag = flag.substr(0, eq)
			has_inline = true
		var next_is_value := not has_inline and i + 1 < args.size() and not args[i + 1].begins_with("--")
		if next_is_value:
			value = args[i + 1]
		var consumed := 1
		match flag:
			"--seed":
				if value.is_valid_int():
					out.has_seed = true
					out.run_seed = value.to_int()
				else:
					push_warning("CliArgs: --seed needs an integer, got '%s'" % value)
				consumed = 2 if next_is_value else 1
			"--depth":
				if value.is_valid_int() and value.to_int() >= 1:
					out.depth = value.to_int()
				else:
					push_warning("CliArgs: --depth needs an integer >= 1, got '%s'" % value)
				consumed = 2 if next_is_value else 1
			"--stratum":
				var s := StringName(value.to_lower())
				if STRATA.has(s):
					out.stratum = s
				else:
					push_warning("CliArgs: --stratum must be one of %s, got '%s'" % [STRATA, value])
				consumed = 2 if next_is_value else 1
			"--smoke":
				out.smoke = true
			"--tour":
				out.tour = true
				out.tour_dir = value if not value.is_empty() else DEFAULT_TOUR_DIR
				consumed = 2 if next_is_value else 1
			"--validate-levels":
				if value.is_valid_int() and value.to_int() > 0:
					out.validate_levels = value.to_int()
				else:
					push_warning("CliArgs: --validate-levels needs a positive integer, got '%s'" % value)
				consumed = 2 if next_is_value else 1
		i += consumed
	return out


## True when the flags ask to launch straight into a level (skipping the title).
func wants_direct_level() -> bool:
	return has_seed or depth > 0 or stratum != &""
