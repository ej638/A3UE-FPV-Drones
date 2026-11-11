"""Verify AU-04's reviewed source boundary; never update pins automatically.

python tools/verify_au_adapter.py [--upstream PATH_TO_AU_CORE]
The ignored local AU reference is checked when present. An explicit missing
candidate fails; a source-free checkout still verifies the recorded patches.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PIN = Path("compat/antistasi-12.0.3")
REFERENCE = Path("external/A3-Antistasi-Ultimate-12.0.3/A3A/addons/core")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def normalized(path):
    # Git's Windows line-ending conversion and a missing final newline are not
    # body drift. Whitespace/comments inside the body are deliberately retained.
    return path.read_text(encoding="utf-8-sig").rstrip("\n") + "\n"


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def reverse_patch(source, patch):
    """Strictly reconstruct reviewed AU text from adapter + intentional diff.

    No fuzzy offsets, ignored hunks or external patch executable. Any unrecorded
    edit fails context matching or the reconstructed upstream SHA-256.
    """
    lines = source.splitlines()
    diff = patch.splitlines()
    require(diff[:1] and diff[0].startswith("--- ") and diff[1].startswith("+++ "), "Invalid patch header")
    output = []
    cursor = 0
    index = 2
    hunks = 0
    while index < len(diff):
        match = re.fullmatch(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@.*", diff[index])
        require(match is not None, "Invalid patch hunk")
        old_start, old_count, new_start, new_count = (int(value or 1) for value in match.groups())
        position = new_start - 1 if new_count else new_start
        require(cursor <= position <= len(lines), "Overlapping/out-of-range patch")
        output.extend(lines[cursor:position])
        cursor = position
        require(len(output) == (old_start - 1 if old_count else old_start), "Invalid old hunk offset")
        consumed = restored = 0
        index += 1
        while index < len(diff) and not diff[index].startswith("@@ "):
            item = diff[index]
            require(item and item[0] in " +-", "Invalid patch line")
            if item[0] in " +":
                require(cursor < len(lines) and lines[cursor] == item[1:], "Unrecorded adapter drift in patch context")
                cursor += 1
                consumed += 1
            if item[0] in " -":
                output.append(item[1:])
                restored += 1
            index += 1
        require((restored, consumed) == (old_count, new_count), "Patch hunk length mismatch")
        hunks += 1
    require(hunks > 0, "Empty intentional diff")
    output.extend(lines[cursor:])
    return "\n".join(output) + "\n"


def config_block(text, name):
    match = re.search(r"\bclass\s+" + re.escape(name) + r"\s*\{", text)
    require(match is not None, f"Missing config class {name}")
    start = match.end()
    depth = 1
    for position in range(start, len(text)):
        depth += (text[position] == "{") - (text[position] == "}")
        if depth == 0:
            return text[start:position]
    raise ValueError(f"Unclosed config class {name}")


def verify(root=ROOT, upstream=None):
    manifest = json.loads((root / PIN / "manifest.json").read_text())
    require(manifest["schema"] == 1 and manifest["version"] == "12.0.3", "Unreviewed manifest version")
    functions = manifest["overrides"]
    expected = {"singleAttack", "wavedAttack", "attackHQ", "invaderPunish",
                "showInterceptedSetupCall", "showInterceptedSupportCall"}
    require({row["name"] for row in functions} == expected and len(functions) == 6, "Override allowlist changed")
    config = config_block(config_block((root / "addons/drones/config.cpp").read_text(), "CfgFunctions"), "A3A")
    require("A3UEFPVOverrides" not in config, "Duplicate override category returned")
    if upstream is not None:
        require(upstream.is_dir(), f"Missing candidate AU core: {upstream}")
    else:
        candidate = root / REFERENCE
        upstream = candidate if candidate.is_dir() else None

    for row in functions:
        name = row["name"]
        source = root / row["adapter"]
        restored = reverse_patch(normalized(source), normalized(root / PIN / row["patch"]))
        require(digest(restored) == row["upstream_sha256_lf"], f"Unrecorded body drift: {name}")
        require(row["intent"], f"Missing intent for {name}")
        category = "Supports" if name.startswith("showIntercepted") else "CREATE"
        require(row["category"] == category, f"Wrong original category: {name}")
        declaration = config_block(config_block(config, category), name)
        virtual = "\\fpv_ai_drones\\" + str(source.relative_to(root / "addons/drones")).replace("/", "\\")
        require(f'file = "{virtual}";' in declaration, f"Changed function path: {name}")
        require(len(re.findall(r"\bclass\s+" + name + r"\s*\{", config)) == 1, f"Duplicate public declaration: {name}")
        if upstream is not None:
            require(digest(normalized(upstream / row["upstream"])) == row["upstream_sha256_lf"],
                    f"Changed candidate upstream body: {name}; review before updating pins")

    # A candidate must match one reviewed contract set as a whole. Later reviewed AU
    # versions list only the contracts that changed; the rest inherit the base pins.
    matched = None
    if upstream is not None:
        base = {row["path"]: row["sha256_lf"] for row in manifest["contracts"]}
        sets = [("12.0.3", base)]
        for review in manifest.get("also_reviewed", []):
            require(review.get("version") and review.get("reviewed") and review.get("source"),
                    "Incomplete also_reviewed entry")
            changed = {row["path"]: row["sha256_lf"] for row in review["contracts"]}
            require(set(changed) <= set(base), f"Unknown contract in review {review['version']}")
            sets.append((review["version"], {**base, **changed}))
        actual = {path: digest(normalized(upstream / path)) for path in base}
        for version, expected in sets:
            if actual == expected:
                matched = version
                break
        if matched is None:
            drift = sorted(path for path in base if all(actual[path] != expected[path] for _, expected in sets))
            require(False, f"Changed AU contract: {', '.join(drift) or 'mixed reviewed versions'}")
    for row in manifest["build_headers"]:
        require(digest(normalized(root / row["path"])) == row["sha256_lf"], f"Changed build header: {row['path']}")

    result = {"reviewed_version": "12.0.3", "override_count": len(functions),
              "upstream_checked": str(upstream) if upstream is not None else "NOT SUPPLIED",
              "upstream_matches": matched or "NOT CHECKED",
              "manifest_sha256": hashlib.sha256((root / PIN / "manifest.json").read_bytes()).hexdigest()}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path)
    args = parser.parse_args()
    try:
        print("PASS: AU adapter " + json.dumps(verify(upstream=args.upstream)))
    except (ValueError, OSError, KeyError, IndexError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
