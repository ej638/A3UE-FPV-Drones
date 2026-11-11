"""Verify this project's packed HEMTT output without invoking Steam.

Usage: python tools/verify_hemtt.py [build|release] [--output NEW_EVIDENCE_DIRECTORY]
Requires Python 3.11+ and HEMTT on PATH. Writes evidence under .hemttout/verification.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tomllib
import zipfile

from verify_au_adapter import verify as verify_au_adapter


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons/drones"
WORKSHOP_ID = 3735346298
MOD_LOGOS = ("logo.paa", "logo_small.paa")
# Upstream license notices ship with the mod (MIT requires them with every copy).
MOD_NOTICES = ("THIRD-PARTY-NOTICES.txt",)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_pbo(path):
    """Read the uncompressed PBO entries HEMTT produces; validate its checksum."""
    raw = path.read_bytes()
    position = 0

    def string():
        nonlocal position
        end = raw.index(b"\0", position)
        value = raw[position:end].decode("utf-8")
        position = end + 1
        return value

    properties = {}
    headers = []
    while True:
        name = string()
        method, original, reserved, timestamp, size = struct.unpack_from("<5I", raw, position)
        position += 20
        if not name:
            if method == 0x56657273:  # Vers: PBO properties extension
                while key := string():
                    properties[key] = string()
                continue
            require(method == 0 and size == 0, "Unexpected PBO header")
            break
        require(method == 0, f"Unexpected compression for {name}")
        headers.append((name, size))

    entries = {}
    for name, size in headers:
        require(name not in entries, f"Duplicate PBO entry: {name}")
        entries[name] = raw[position:position + size]
        require(len(entries[name]) == size, f"Truncated PBO entry: {name}")
        position += size
    require(raw[position:position + 1] == b"\0", "Missing PBO checksum separator")
    require(len(raw) == position + 21, "Unexpected data after PBO entries")
    require(hashlib.sha1(raw[:position]).digest() == raw[position + 1:], "PBO checksum mismatch")
    return properties, entries


def verify(mode, evidence=None):
    require(mode in ("build", "release"), "Expected build or release")
    au_adapter = verify_au_adapter()
    output = ROOT / ".hemttout" / mode
    if evidence is None:
        evidence = ROOT / ".hemttout/verification"
        evidence.mkdir(parents=True, exist_ok=True)
    else:
        evidence = evidence.resolve()
        require(evidence.is_relative_to((ROOT / ".hemttout/verification").resolve()),
                "Evidence output must stay under .hemttout/verification")
        evidence.mkdir(parents=True, exist_ok=False)
    pbo = output / "addons/fpv_ai_drones.pbo"
    require(list(output.rglob("*.pbo")) == [pbo], "Expected exactly fpv_ai_drones.pbo")
    properties, entries = read_pbo(pbo)
    require(properties.get("prefix") == "fpv_ai_drones", "Virtual addon prefix changed")
    require((ADDON / "$PBOPREFIX$").read_text().strip() == "fpv_ai_drones", "Source prefix changed")

    source_files = sorted((ADDON / "functions").rglob("*.sqf"))
    sqf_names = {str(path.relative_to(ADDON)).replace("/", "\\") for path in source_files}
    expected = sqf_names | {name + "c" for name in sqf_names} | {"config.bin", "stringtable.bin"}
    require(set(entries) == expected, "Unexpected/missing PBO entries: " + str(set(entries) ^ expected))
    for source in source_files:
        name = str(source.relative_to(ADDON)).replace("/", "\\")
        require(entries[name] == source.read_bytes(), f"Packaged SQF differs from source: {name}")
        require(entries[name + "c"], f"Empty SQFC: {name}")
    require(entries["config.bin"].startswith(b"\0raP"), "Config is not rapified")
    require(entries["stringtable.bin"], "Empty binary stringtable")

    config_bin = evidence / f"{mode}-config.bin"
    config_cpp = evidence / f"{mode}-config.cpp"
    config_bin.write_bytes(entries["config.bin"])
    subprocess.run(["hemtt", "utils", "config", "derapify", str(config_bin), str(config_cpp)],
                   cwd=ROOT, check=True, capture_output=True)
    source_config = (ADDON / "config.cpp").read_text()
    packed_config = config_cpp.read_text()
    require(re.sub(r"\s+", "", source_config) == re.sub(r"\s+", "", packed_config),
            "Packaged config differs from source")
    file_paths = re.findall(r'file\s*=\s*"([^"]+)"', packed_config)
    for virtual_path in file_paths:
        require(virtual_path.startswith("\\fpv_ai_drones\\"), f"Changed CfgFunctions path: {virtual_path}")
        relative = virtual_path.removeprefix("\\fpv_ai_drones\\")
        require(relative in entries or any(name.startswith(relative + "\\") for name in entries),
                f"Missing CfgFunctions path: {virtual_path}")
    category = re.search(r"class FPV\s*\{(.*?)\n\s*\};", source_config, re.S).group(1)
    functions = re.findall(r"class\s+(\w+)\s*\{", category)
    for function in functions:
        require(f"functions\\fpv\\fn_{function}.sqf" in entries, f"Unresolved function: {function}")

    require((output / "mod.cpp").read_bytes() == (ROOT / "mod.cpp").read_bytes(), "Metadata mismatch: mod.cpp")
    # Mod logos (referenced by mod.cpp) ship byte-identical to the committed source copies.
    for logo in MOD_LOGOS + MOD_NOTICES:
        require((output / logo).read_bytes() == (ROOT / logo).read_bytes(), f"Mod file mismatch: {logo}")
    meta = (ROOT / "meta.cpp").read_text()
    packed_meta = (output / "meta.cpp").read_text()
    # HEMTT release appends an Arma timestamp to the output copy only.
    packed_meta_without_timestamp = re.sub(r"timestamp\s*=\s*\d+;", "", packed_meta)
    require(re.sub(r"\s+", "", packed_meta_without_timestamp) == re.sub(r"\s+", "", meta),
            "Packaged Workshop metadata changed")
    require(re.search(r"protocol\s*=\s*1;", meta), "Unexpected meta.cpp protocol")
    # HEMTT 1.22.0 get_id() uses this same regex and parses the result as u64.
    ids = re.findall(r"publishedid\s*=\s*(\d+);", meta)
    require(ids == [str(WORKSHOP_ID)], "Workshop ID is missing, ambiguous, or changed")

    project = tomllib.loads((ROOT / ".hemtt/project.toml").read_text())
    expected_output = {"addons/fpv_ai_drones.pbo", "mod.cpp", "meta.cpp", *MOD_LOGOS, *MOD_NOTICES}
    signatures = []
    keys = []
    archives = []
    if mode == "release":
        signatures = list(output.rglob("*.bisign"))
        keys = list(output.rglob("*.bikey"))
        require(len(signatures) == len(keys) == 1, "Expected one signature and public key")
        subprocess.run(["hemtt", "utils", "verify", str(pbo), str(keys[0])],
                       cwd=ROOT, check=True, capture_output=True)
        expected_output |= {str(path.relative_to(output)).replace("\\", "/") for path in signatures + keys}
        version = project["version"]
        version_string = f'{version["major"]}.{version["minor"]}.{version["patch"]}'
        folder = project["hemtt"]["release"]["folder"]
        for suffix in ("latest", version_string):
            # In HEMTT 1.22.0 the archive filename uses prefix; folder sets its inner @mod directory.
            archive = ROOT / "releases" / f'{project["prefix"]}-{suffix}.zip'
            with zipfile.ZipFile(archive) as release_zip:
                files = {name for name in release_zip.namelist() if not name.endswith("/")}
                require(files == {f"@{folder}/{name}" for name in expected_output}, "Unexpected release archive layout")
                for name in expected_output:
                    require(release_zip.read(f"@{folder}/{name}") == (output / name).read_bytes(),
                            f"Archive file differs: {name}")
            archives.append(str(archive.relative_to(ROOT)))
    actual_output = {str(path.relative_to(output)).replace("\\", "/") for path in output.rglob("*") if path.is_file()}
    require(actual_output == expected_output, "Unexpected mod-level files: " + str(actual_output ^ expected_output))

    result = {"mode": mode, "au_adapter": au_adapter, "pbo": str(pbo.relative_to(ROOT)), "pbo_sha256": hashlib.sha256(pbo.read_bytes()).hexdigest(),
              "properties": properties, "entry_count": len(entries), "sqf_count": len(source_files),
              "sqfc_count": len(sqf_names), "cfgfunctions_count": len(functions) + len(file_paths) - 1,
              "workshop_id": WORKSHOP_ID, "signature_verified": mode == "release", "archives": archives,
              "output_files": sorted(actual_output), "pbo_entries": sorted(entries)}
    (evidence / f"{mode}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"PASS: {mode}; prefix=fpv_ai_drones; {len(source_files)} unchanged SQF; "
          f"{len(entries)} PBO entries; Workshop {WORKSHOP_ID}" + ("; signature and archives verified" if mode == "release" else ""))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', nargs='?', default='build', choices=('build', 'release'))
    parser.add_argument('--output', type=Path, help='new evidence directory under .hemttout/verification')
    args = parser.parse_args()
    try:
        verify(args.mode, args.output)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
