"""Render reviewed material from a preserved inspection; never accept new pins.

python tools/tests/ua_dive/generate_motion_policy.py --inspection PATH
Checks provider/file SHA256 and the original selected-span fingerprints first.
This copies reviewed source text for engine equality; it does not execute SQF or
claim to reproduce the engine preprocessor/compiler.
"""
import argparse
import hashlib
import json
from pathlib import Path
from motion_admission import ROOT, fingerprint, load_policy, render_policy


def enrich(policy, inspection):
    sources = json.loads((inspection / 'sources.json').read_text(encoding='utf-8'))
    index = {}
    for source in sources:
        for entry in source['entries']:
            virtual = '\\' + source['properties']['prefix'] + '\\' + entry['entry']
            index[virtual.lower()] = (source, entry, inspection/'sources'/Path(source['pbo']).stem/entry['entry'].replace('\\', '/'))
    for pin in policy['pins']:
        provider, entry, path = index[pin['path'].lower()]
        raw = path.read_bytes()
        if provider['pbo_sha256'] != pin['pbo_sha256'] or hashlib.sha256(raw).hexdigest() != pin['source_sha256']:
            raise ValueError('Changed reviewed provider/source: ' + pin['path'])
        text = raw.decode('utf-8-sig').replace('\r', '')
        if pin['span']:
            marker, length = pin['span']
            start = text.index(marker) + len(marker)
            text = text[start:start+length]
        if fingerprint(text) != pin['fingerprint']:
            raise ValueError('Changed reviewed span: ' + pin['path'])
        pin['source_lf'] = text
    return policy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inspection', required=True, type=Path)
    args = parser.parse_args()
    policy = enrich(load_policy(), args.inspection)
    (ROOT/'motion_policy.json').write_text(json.dumps(policy, indent=2)+'\n', encoding='utf-8')
    (ROOT/'motion_policy_data.sqf').write_text(render_policy(policy), encoding='utf-8')
    print('PASS: reviewed provider/source/span pins retained; generated', len(policy['pins']), 'exact LF comparisons; engine NOT RUN')


if __name__ == '__main__':
    main()
