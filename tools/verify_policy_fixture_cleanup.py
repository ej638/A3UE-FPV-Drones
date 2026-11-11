"""Compile only the two delivered standalone QA commands in a new isolated HEMTT project."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from verify_hemtt import read_pbo

ROOT = Path(__file__).resolve().parents[1]
# Local, git-ignored QA evidence tree.
SOURCES = ROOT / "docs/internal/experiments/crocus-at-policy-initialization-20261027/commands"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not SOURCES.is_dir():
        raise SystemExit(f"QA command sources not found: {SOURCES} (local docs/internal tree)")
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / ".hemttout/verification").resolve()):
        raise SystemExit("Isolated output must stay under .hemttout/verification")
    output.mkdir(parents=True, exist_ok=False)
    project = output / "project"
    addon = project / "addons/qa"
    addon.mkdir(parents=True)
    (project / ".hemtt").mkdir()
    (project / ".hemtt/project.toml").write_text(
        'name = "Policy cleanup QA syntax"\nprefix = "policy"\n'
        '[version]\nmajor = 1\nminor = 0\npatch = 0\ngit_hash = 0\n', encoding="utf-8")
    (addon / "$PBOPREFIX$").write_text("policy\\addons\\qa", encoding="utf-8")
    (addon / "config.cpp").write_text(
        "class CfgPatches {class policy_qa {units[] = {}; weapons[] = {}; "
        "requiredVersion = 2.14; requiredAddons[] = {};};};", encoding="utf-8")
    sources = sorted(SOURCES.glob("*.sqf"))
    assert len(sources) == 2
    for source in sources:
        shutil.copyfile(source, addon / source.name)
    commands = []
    for argv in (["hemtt", "--version"], ["hemtt", "check", "--no-color"], ["hemtt", "build", "--no-color"]):
        label = "version" if "--version" in argv else argv[1]
        result = subprocess.run(argv, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = output / (label + ".log")
        log.write_bytes(result.stdout)
        diagnostics = {}
        for severity in ("ERROR", "WARNING", "HELP"):
            diagnostics[severity.lower()] = len(re.findall(r"(?m)^" + severity + r"(?:\[|:)", result.stdout.decode("utf-8", errors="replace"), re.I))
        commands.append(dict(argv=argv, cwd=str(project), exit=result.returncode, log=str(log),
                             sha256=sha(log), diagnostics=diagnostics))
        print(label, result.returncode, diagnostics, flush=True)
        if label != "version" and result.returncode:
            (output / "commands.json").write_text(json.dumps(commands, indent=2) + "\n", encoding="utf-8")
            raise SystemExit("Native compilation failed; inspect new isolated logs")
    pbo = project / ".hemttout/build/addons/policy_qa.pbo"
    properties, entries = read_pbo(pbo)
    inputs = []
    for source in sources:
        assert entries[source.name] == source.read_bytes()
        compiled = entries[source.name + "c"]
        inputs.append(dict(source=str(source), sha256=sha(source),
                           sqfc_sha256=hashlib.sha256(compiled).hexdigest(), sqfc_bytes=len(compiled)))
    receipt = dict(createdUtc=datetime.now(timezone.utc).isoformat(), project=str(project),
                   commands=commands, inputs=inputs, pbo=str(pbo), pbo_sha256=sha(pbo),
                   properties=properties, engine="NOT RUN", deployment="NONE")
    (output / "compilation.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print("PASS: exact delivered source/SQFC pairs; QA PBO remains private and unloaded")


if __name__ == "__main__":
    main()
