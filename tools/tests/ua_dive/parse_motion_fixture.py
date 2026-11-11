"""Decode deferred motion-fixture fragments; never edits evidence.

python tools/tests/ua_dive/parse_motion_fixture.py session.rpt --out NEW/fixtures.json
PASS in the engine footer means fixture coverage, never a production fix.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
from parse_capture import magnitude, sqf_array, stats


def parse(paths):
    parts, footers, errors, files = {}, defaultdict(list), [], []
    for path in paths:
        raw = path.read_bytes()
        files.append({'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest()})
        for line_no, line in enumerate(raw.decode('utf-8-sig',errors='replace').splitlines(),1):
            tag = next((t for t in ('A3UE_FPV_QA_MOTION_PART','A3UE_FPV_QA_MOTION_EXPORT_DONE') if t in line),None)
            if not tag:
                continue
            try:
                value = sqf_array(line[line.index('["'+tag+'"'):])
                if tag.endswith('EXPORT_DONE'):
                    result, count = value[1:]
                    key = result[0]
                    if value not in footers[key]: footers[key].append(value)
                else:
                    _, key, process, seq, part, total, text = value
                    if not all(isinstance(x,(int,float)) and int(x)==x for x in (process,seq,part,total)) or not 0<=part<total<=128 or seq<1 or not isinstance(text,str):
                        raise ValueError('invalid fragment metadata')
                    item = parts.setdefault((key,process,seq),{'total':total,'parts':{}})
                    if total != item['total'] or (part in item['parts'] and item['parts'][part]!=text):
                        raise ValueError('conflicting fragment')
                    item['parts'][part] = text
            except (ValueError,IndexError,TypeError) as exc:
                errors.append(f'{path}:{line_no}: {exc}')
    runs = defaultdict(list)
    for (key,process,seq), item in sorted(parts.items()):
        try:
            if len(item['parts']) != item['total']:
                raise ValueError('incomplete fragments')
            row = sqf_array(''.join(item['parts'][i] for i in range(int(item['total']))))
            if len(row)!=5 or row[0]!=seq or not isinstance(row[4],list):
                raise ValueError('invalid row/sequence')
            runs[key].append(row)
        except (ValueError,IndexError,TypeError) as exc:
            errors.append(f'{key}/{seq}: {exc}')
    results = []
    for key in sorted(set(runs)|set(footers)):
        rows = runs[key]
        issues = []
        footer = footers[key]
        if len(footer)!=1: issues.append('missing/conflicting footer')
        if not rows or rows[0][1]!='BEGIN' or rows[-1][1]!='END': issues.append('missing BEGIN/END')
        if [r[0] for r in rows] != list(range(1,len(rows)+1)): issues.append('sequence loss')
        if len(footer)==1 and (footer[0][2]!=len(rows) or not rows or footer[0][1]!=rows[-1][4]): issues.append('footer count/result mismatch')
        phases = []
        for phase in sorted({tuple(r[4][0]) for r in rows if r[1]=='PHASE_BEGIN'}):
            observations = [r for r in rows if r[1]=='OBSERVE' and tuple(r[4][0])==phase]
            commands = [r for r in rows if r[1]=='COMMAND' and tuple(r[4][0])==phase]
            if any(r[4][3]<1 or r[4][2]<0 for r in observations): issues.append('observation not from later frame')
            gaps = [b[2]-a[2] for a,b in zip(observations,observations[1:])]
            expected = sum((magnitude(a[4][5])+magnitude(b[4][5]))*.5*dt for a,b,dt in zip(observations,observations[1:],gaps))
            observed = sum(magnitude([y-x for x,y in zip(a[4][4],b[4][4])]) for a,b in zip(observations,observations[1:]))
            phases.append({'phase':phase,'observations':len(observations),'commands':len(commands),
                           'subsequent_observation_gaps_ms':stats(gaps,1000),
                           'command_spacing_ms':stats([b[2]-a[2] for a,b in zip(commands,commands[1:])],1000),
                           'command_spacing_frames':stats([b[3]-a[3] for a,b in zip(commands,commands[1:])]),
                           'fps':stats([r[4][6] for r in observations]),
                           'observed_step_distance_m':observed,'sampled_velocity_expected_m':expected,
                           'observed_to_expected_ratio':observed/expected if expected>1e-6 else None,
                           'coverage': 'UNKNOWN' if len(observations)<10 or any(dt<=0 or dt>.1 for dt in gaps) else 'OBSERVED',
                           'verdict':'ENGINE_REVIEW_REQUIRED: matched masks/geometry/guards, turning, FPS and video remain separate'})
        results.append({'id':key,'integrity':'incomplete' if issues else 'complete_export',
                        'issues':issues,'result':footer[0][1] if len(footer)==1 else None,
                        'records':len(rows),'event_counts':dict(Counter(r[1] for r in rows)),
                        'phases':phases,'rows':rows})
    return {'files':files,'errors':errors,'runs':results}


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('inputs',nargs='+',type=Path); p.add_argument('--out',type=Path,required=True)
    args=p.parse_args(); result=parse(args.inputs)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(f"{len(result['runs'])} fixtures; {len(result['errors'])} errors; {args.out}")
    return 2 if not result['runs'] or result['errors'] or any(r['issues'] for r in result['runs']) else 0


if __name__=='__main__': raise SystemExit(main())
