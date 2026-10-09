#!/usr/bin/env python3
"""Small VDF (Valve KeyValues) parser and checker for the Steam build files.

  check_vdf.py FILE...              parse each file and check the NOCLIP shape
  check_vdf.py --templates FILE...  also require the placeholders of 16 section 3
  check_vdf.py --generated FILE...  also fail if any {PLACEHOLDER} remains
  check_vdf.py --selftest           prove the parser accepts good and rejects bad input

Only the subset steamcmd build scripts use: quoted keys and values, braces, // comments.
Exit 0 ok, 1 bad file, 2 usage.
"""
import re
import sys

PLACEHOLDERS = ["{APP_ID}", "{DEPOT_WIN}", "{DEPOT_LINUX}", "{BUILD_DIR}", "{DESCRIPTION}"]
TOKEN = re.compile(r'\s+|//[^\n]*|"((?:[^"\\\n]|\\.)*)"|([{}])|(.)', re.S)


class VdfError(Exception):
    pass


def tokenize(text):
    line = 1
    for m in TOKEN.finditer(text):
        raw = m.group(0)
        if m.group(1) is not None:
            yield ("str", m.group(1), line)
        elif m.group(2):
            yield (m.group(2), m.group(2), line)
        elif m.group(3):
            raise VdfError("line %d: unquoted text %r" % (line, m.group(3)))
        line += raw.count("\n")


def parse(text):
    """The document as a list of (key, value) pairs; a value is a str or a list of pairs."""
    toks = list(tokenize(text))
    pos = 0

    def block(top):
        nonlocal pos
        out = []
        while True:
            if pos >= len(toks):
                if top:
                    return out
                raise VdfError("unexpected end of file: missing }")
            kind, val, line = toks[pos]
            if kind == "}":
                if top:
                    raise VdfError("line %d: unmatched }" % line)
                pos += 1
                return out
            if kind != "str":
                raise VdfError("line %d: expected a key, found %s" % (line, kind))
            pos += 1
            if pos >= len(toks):
                raise VdfError("line %d: key %r has no value" % (line, val))
            k2, v2, l2 = toks[pos]
            pos += 1
            if k2 == "str":
                out.append((val, v2))
            elif k2 == "{":
                out.append((val, block(False)))
            else:
                raise VdfError("line %d: key %r followed by %s" % (l2, val, k2))

    return block(True)


def get(pairs, key):
    return [v for k, v in pairs if k.lower() == key.lower()]


def check_shape(doc, name):
    """The NOCLIP build files: an appbuild with two depots, or a DepotBuildConfig."""
    if len(doc) != 1:
        raise VdfError("%s: expected one root block" % name)
    root, body = doc[0]
    if not isinstance(body, list):
        raise VdfError("%s: root has no block" % name)
    if root.lower() == "appbuild":
        for key in ("appid", "desc", "contentroot", "depots"):
            if not get(body, key):
                raise VdfError("%s: appbuild lacks %s" % (name, key))
        depots = get(body, "depots")[0]
        if len(depots) != 2 or not all(isinstance(v, str) and v.endswith(".vdf") for _, v in depots):
            raise VdfError("%s: depots must map two ids to two depot build files" % name)
        if get(body, "setlive") != [""]:
            raise VdfError("%s: setlive must stay empty (the human sets a build live in Steamworks)" % name)
    elif root.lower() == "depotbuildconfig":
        for key in ("depotid", "contentroot", "filemapping"):
            if not get(body, key):
                raise VdfError("%s: depot build lacks %s" % (name, key))
    else:
        raise VdfError("%s: unknown root %r" % (name, root))


def selftest():
    good = '"a"\n{\n\t"k" "v" // note\n\t"b" { "x" "1" }\n}\n'
    assert parse(good) == [("a", [("k", "v"), ("b", [("x", "1")])])]
    for bad in ('"a" { "k" "v" ', '"a" "v" }', '"a" { k "v" }', '"a" { "k" }', '"a" { "k" "v }'):
        try:
            parse(bad)
        except VdfError:
            continue
        raise AssertionError("accepted bad VDF: %r" % bad)
    try:
        check_shape(parse('"appbuild" { "appid" "1" }'), "x")
    except VdfError:
        pass
    else:
        raise AssertionError("accepted an incomplete appbuild")
    print("check_vdf: selftest ok")


def main(argv):
    if "--selftest" in argv:
        selftest()
        return 0
    templates = "--templates" in argv
    generated = "--generated" in argv
    files = [a for a in argv if not a.startswith("--")]
    if not files:
        print(__doc__)
        return 2
    for path in files:
        text = open(path, encoding="utf-8").read()
        try:
            check_shape(parse(text), path)
            if templates:
                if "windows" in path:
                    need = ["{DEPOT_WIN}", "{BUILD_DIR}"]
                elif "linux" in path:
                    need = ["{DEPOT_LINUX}", "{BUILD_DIR}"]
                else:
                    need = PLACEHOLDERS
                missing = [p for p in need if p not in text]
                if missing:
                    raise VdfError("%s: missing placeholders %s" % (path, ", ".join(missing)))
            if generated and re.search(r"\{[A-Z_]+\}", text):
                raise VdfError("%s: an unfilled placeholder remains" % path)
        except VdfError as e:
            print("check_vdf: " + str(e), file=sys.stderr)
            return 1
        print("check_vdf: %s ok" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
