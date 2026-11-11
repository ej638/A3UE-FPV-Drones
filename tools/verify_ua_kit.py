"""Compile mission fixtures in an isolated ignored HEMTT project; never edits external/.

python tools/verify_ua_kit.py --output .hemttout/verification/NEW-RECEIPT/fixtures-check
Builds a disposable QA PBO (NOT the candidate addon) and extracts mission SQFCs.
Copy extracted *.sqfc beside mission *.sqf ONLY for the compiled-fixture comparison.
"""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
from verify_hemtt import read_pbo

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='new receipt directory under .hemttout/verification')
    args = parser.parse_args()
    output_root = (args.output or ROOT/'.hemttout/verification'/('ua-kit-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))).resolve()
    if not output_root.is_relative_to((ROOT/'.hemttout/verification').resolve()):
        raise SystemExit('FAIL: isolated output must stay under .hemttout/verification')
    output_root.mkdir(parents=True, exist_ok=False)  # preserve previous receipts
    gameplay = ROOT/'.hemttout/build/addons/fpv_ai_drones.pbo'
    before = hashlib.sha256(gameplay.read_bytes()).hexdigest()
    project = output_root/'fixtures'
    addon = project/'addons/qa'
    addon.mkdir(parents=True,exist_ok=True)
    (project/'.hemtt').mkdir(exist_ok=True)
    (project/'.hemtt/project.toml').write_text('name = "UA dive mission fixtures"\nprefix = "uaqa"\n[version]\nmajor = 1\nminor = 0\npatch = 0\ngit_hash = 0\n',encoding='utf-8')
    (addon/'$PBOPREFIX$').write_text('uaqa\\addons\\qa',encoding='utf-8')
    (addon/'config.cpp').write_text('class CfgPatches {class uaqa_fixtures {units[] = {}; weapons[] = {}; requiredVersion = 2.14; requiredAddons[] = {};};};',encoding='utf-8')
    scripts = sorted((ROOT/'tools/tests/ua_dive').glob('*.sqf')) + [ROOT/'tools/tests/v03_payload_commit.sqf',ROOT/'tools/tests/v04_payload_contracts.sqf']
    for source in scripts:
        shutil.copyfile(source,addon/source.name)
    version_result = subprocess.run(['hemtt','--version'],capture_output=True,text=True)
    version = (version_result.stdout+version_result.stderr).strip()
    (output_root/'hemtt-version.log').write_text(version+'\n',encoding='utf-8')
    for command in ('check','build'):
        result = subprocess.run(['hemtt',command,'--no-color'],cwd=project,capture_output=True,text=True)
        (project.parent/f'fixtures-{command}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:
            raise SystemExit(f'FAIL: fixture {command}; inspect {project.parent}')
    _, entries = read_pbo(project/'.hemttout/build/addons/uaqa_qa.pbo')
    output = project.parent/'compiled-mission-scripts'
    output.mkdir(exist_ok=True)
    receipts = []
    for source in scripts:
        assert entries[source.name] == source.read_bytes(),source
        compiled = entries[source.name+'c']
        (output/(source.name+'c')).write_bytes(compiled)
        receipts.append({'name':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                         'sqfc_sha256':hashlib.sha256(compiled).hexdigest()})
    (project.parent/'fixtures.json').write_text(json.dumps(receipts,indent=2)+'\n',encoding='utf-8')
    after = hashlib.sha256(gameplay.read_bytes()).hexdigest()
    if before != after:
        raise SystemExit('FAIL: gameplay PBO changed during fixture verification')
    (output_root/'verification.json').write_text(json.dumps({
        'gameplay_before_sha256': before, 'gameplay_after_sha256': after,
        'fixture_pbo': str(project/'.hemttout/build/addons/uaqa_qa.pbo'),
        'fixture_pbo_sha256': hashlib.sha256((project/'.hemttout/build/addons/uaqa_qa.pbo').read_bytes()).hexdigest(),
        'fixture_count': len(scripts), 'hemtt_version': version, 'hemtt_version_exit': version_result.returncode, 'engine_execution': 'NOT RUN',
    },indent=2)+'\n',encoding='utf-8')
    print(f'PASS: {len(scripts)} fixture SQF/SQFC; {output}; gameplay unchanged; engine behavior NOT RUN')


if __name__ == '__main__':
    main()
