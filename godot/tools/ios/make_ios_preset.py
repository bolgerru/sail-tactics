#!/usr/bin/env python3
"""Merge the iOS export preset (ios_preset.cfg, beside this script) into export_presets.cfg.

The preset is kept out of export_presets.cfg because an open Godot editor rewrites that file from
memory whenever it exports, dropping presets it never loaded. CI runs this just before exporting:

    python3 godot/tools/ios/make_ios_preset.py --team-id ABCDE12345 --build 12 \
        --profile-uuid <uuid> --profile-name "Sail Tactics App Store" [--version 1.0.1]

Any iOS preset already in the file is replaced. The other presets are renumbered so the indices
stay contiguous, because Godot stops reading presets at the first missing index.
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
PRESET_HEADER = re.compile(r"^\[preset\.(\d+)(\.options)?\]$")
UNESCAPED_QUOTE = re.compile(r'(?<!\\)"')
VERSION = re.compile(r"\d+(\.\d+){0,2}")


def fail(message):
    sys.exit("make_ios_preset: " + message)


def sections(text):
    """[(header, body lines)], header None for a preamble. Multi-line string values (the ssh deploy
    scripts) are tracked, so a line starting with "[" inside one is never taken for a header."""
    result = [(None, [])]
    in_string = False
    for line in text.splitlines():
        if not in_string and line.startswith("[") and line.rstrip().endswith("]"):
            result.append((line.strip(), []))
            continue
        result[-1][1].append(line)
        if len(UNESCAPED_QUOTE.findall(line)) % 2:
            in_string = not in_string
    return result


def trimmed(lines):
    lines = list(lines)
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def set_option(lines, key, value):
    encoded = '%s="%s"' % (key, value.replace("\\", "\\\\").replace('"', '\\"'))
    for i, line in enumerate(lines):
        if line.startswith(key + "="):
            lines[i] = encoded
            return
    lines.append(encoded)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--presets", type=pathlib.Path, default=HERE.parents[1] / "export_presets.cfg")
    parser.add_argument("--team-id", required=True, help="10-character Apple team ID")
    parser.add_argument("--build", required=True, help="CFBundleVersion; must rise with every upload")
    parser.add_argument("--version", default="", help="CFBundleShortVersionString (default: the preset's)")
    parser.add_argument("--profile-uuid", default="")
    parser.add_argument("--profile-name", default="")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        fail("team ID %r should be 10 capital letters and digits" % args.team_id)
    if not VERSION.fullmatch(args.build):
        fail("build number %r should look like 12 or 1.0.12" % args.build)
    if args.version and not VERSION.fullmatch(args.version):
        fail("version %r should look like 1.0.1" % args.version)

    others, presets = [], {}
    existing = args.presets.read_text(encoding="utf-8") if args.presets.exists() else ""
    for header, body in sections(existing):
        match = PRESET_HEADER.match(header or "")
        if match:
            part = "options" if match.group(2) else "main"
            presets.setdefault(int(match.group(1)), {})[part] = body
        elif header is not None or trimmed(body):
            others.append((header, body))
    kept = [p for _, p in sorted(presets.items()) if 'platform="iOS"' not in "\n".join(p.get("main", []))]

    ios = {}
    for header, body in sections((HERE / "ios_preset.cfg").read_text(encoding="utf-8")):
        if header in ("[preset]", "[preset.options]"):
            ios["options" if header == "[preset.options]" else "main"] = [l for l in body if not l.startswith(";")]
    options = ios["options"]
    set_option(options, "application/app_store_team_id", args.team_id)
    set_option(options, "application/version", args.build)
    if args.version:
        set_option(options, "application/short_version", args.version)
    if args.profile_uuid:
        set_option(options, "application/provisioning_profile_uuid_release", args.profile_uuid)
    if args.profile_name:
        set_option(options, "application/provisioning_profile_specifier_release", args.profile_name)
    kept.append(ios)

    chunks = []
    for header, body in others:
        chunks.append("\n\n".join(part for part in (header, "\n".join(trimmed(body))) if part))
    for index, preset in enumerate(kept):
        for suffix, part in (("", "main"), (".options", "options")):
            chunks.append("[preset.%d%s]\n\n%s" % (index, suffix, "\n".join(trimmed(preset.get(part, [])))))
    with open(args.presets, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n\n".join(chunks) + "\n")

    short_version = next(l for l in options if l.startswith("application/short_version=")).split("=", 1)[1]
    print("iOS is preset.%d: version %s build %s, team %s, profile %s"
          % (len(kept) - 1, short_version.strip('"'), args.build, args.team_id, args.profile_name or "(none)"))


if __name__ == "__main__":
    main()
