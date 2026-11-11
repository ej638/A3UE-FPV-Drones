"""F2 correction file observer. No engine/UI/process control. Standard library.

PowerShell is the operator entry point. The manifest pins the compatible capture parser.
Raw RPT snapshots can contain private startup information; summaries never echo it.
"""
import argparse
import codecs
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('f2r_capture', HERE.parent / 'ua_dive/parse_capture.py')
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, data, exclusive=False):
    with Path(path).open('x' if exclusive else 'w', encoding='utf-8') as stream:
        json.dump(data, stream, indent=2, allow_nan=False)


def canonical(path):
    return str(path).replace('/', '\\').rstrip('\\').casefold()


def startup_identity(text, manifest):
    # Read actual loaded-addon inventory, never the launch command's requested -mod list.
    inventories = text.split('==== Loaded addons ====')
    if len(inventories) != 2:
        raise ValueError('missing/ambiguous startup addon inventory')
    loaded = re.findall(r'^\d+:\d+:\d+\s+(.+?\.pbo)\s+-\s+[^\r\n]+$', inventories[1].split('=======================', 1)[0], re.M | re.I)
    fpv = [p for p in loaded if re.search(r'(?:^|[\\/])fpv_ai_drones\.pbo$', p, re.I)]
    if len(fpv) != 1 or canonical(fpv[0]) != canonical(manifest['candidate_pbo']):
        raise ValueError('startup candidate path mismatch or duplicate FPV addon')
    for provider in manifest.get('required_loaded', []):
        if sum(canonical(p) == canonical(provider['path']) for p in loaded) != 1:
            raise ValueError('required provider/map inventory mismatch')
    return {'loaded_addon_path': fpv[0], 'duplicate_fpv_count': len(fpv)}


def disk_identity(manifest):
    for key, hash_key in [('candidate_pbo', 'candidate_sha256'), ('rollback_pbo', 'rollback_sha256')]:
        if sha(manifest[key]) != manifest[hash_key]:
            raise ValueError(key + ' hash mismatch')
    for provider in manifest.get('required_loaded', []):
        if sha(provider['path']) != provider['sha256']:
            raise ValueError('required provider/map hash changed; recipe compatibility needs review')
    verified = []
    for mission in manifest['missions'].values():
        root = Path(mission['path'])
        for rel, digest in mission['helpers'].items():
            file = root / Path(rel)
            if file.with_suffix('.sqfc').exists() or sha(file) != digest:
                raise ValueError('deployed helper hash mismatch or SQFC shadow: ' + rel)
            verified.append({'mission': str(root), 'helper': rel, 'sha256': digest})
    if sha(HERE.parent / 'ua_dive/parse_capture.py') != manifest['parser_sha256']:
        raise ValueError('capture parser identity mismatch')
    return verified


class LiveLines:
    """Incremental BOM-aware decoder. Incomplete bytes/lines are never admitted."""
    def __init__(self):
        self.decoder = None
        self.initial = b''
        self.pending = ''
        self.count = 0

    def feed(self, raw):
        if self.decoder is None:
            self.initial += raw
            if len(self.initial) < 3:
                return []
            encoding = 'utf-16' if self.initial[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig'
            self.decoder = codecs.getincrementaldecoder(encoding)(errors='replace')
            raw, self.initial = self.initial, b''
        self.pending += self.decoder.decode(raw, final=False)
        lines = self.pending.split('\n')
        self.pending = lines.pop()
        self.count += len(lines)
        if len(self.pending) > 1024 * 1024:
            raise ValueError('unbounded/invalid RPT line')
        return [line.rstrip('\r') for line in lines]


def auto_event(line):
    # MARK payloads also contain F2R_AUTO. Only a root array is an activity event;
    # consuming a nested MARK here would skip a valid capture sequence record.
    root = re.match(r'^\s*(?:\d{1,2}:\d{2}:\d{2}\s+)?(\["F2R_AUTO",)', line)
    if root is None:
        return None
    start = root.start(1)
    event = capture.sqf_array(line[start:])
    if len(event) != 6 or event[:2] != ['F2R_AUTO', 1] or not isinstance(event[2], str) or not isinstance(event[3], str) or not capture.number(event[4]) or not isinstance(event[5], list):
        raise ValueError('invalid F2R event schema')
    return event


def ref(row):
    return {'run': row[1], 'process': row[2], 'capture': row[3], 'sequence': row[4],
            'event': row[5], 'drone': row[9], 'generation': row[10]}


def event_ref(event):
    return {'ticket': event[2], 'event': event[3], 'diag': event[4], 'data': event[5]}


def finding(status='NOT OBSERVED', evidence=(), detail=''):
    return {'status': status, 'evidence': list(evidence), 'detail': detail}


def commanded_stalls(rows):
    """Disjoint >=1-second physical windows, independent of reported velocity."""
    start = next((r for r in rows if r[5] == 'START'), None)
    if start is None:
        return []
    normalized = capture.normalized(rows, start)
    stalls = []
    for drone in {r[9] for r in normalized if r[9]}:
        move = state = first = last = key = None
        path = 0
        for r in (r for r in normalized if r[9] == drone):
            d = r[12]
            if r[5] == 'MOVE':
                move = r
            if r[5] == 'STATE':
                state = r
            if r[5] in ('CONTROL','MODE','LOCALITY','CONTACT','COMMIT','KILLED','DELETED','IDENTITY'):
                first = last = key = None
                path = 0
                if r[5] in ('CONTROL','CONTACT','COMMIT','KILLED','DELETED','IDENTITY'):
                    state = move = None
            if r[5] != 'SAMPLE':
                continue
            phase = (r[10], r[11], d[6], d[7])
            eligible = (move and state and r[11] == 'TERMINAL_VECTOR' and d[5] and not state[12][8]
                        and state[12][2] and state[12][3] and not state[12][13]
                        and 0 <= r[6] - state[6] <= .75 and 0 <= r[6] - move[12][0] <= .1
                        and capture.magnitude(move[12][2]) >= 5)
            if not eligible:
                first = last = key = None
                path = 0
                continue
            if key != phase or last and not 0 < r[6] - last[6] <= .1:
                first = last = None
                path = 0
            if first is None:
                first, key = r, phase
            if last:
                path += capture.magnitude([b-a for a,b in zip(last[12][0], d[0])])
            last = r
            if r[6] - first[6] >= 1:
                if path < .25:
                    stalls.append({'drone': drone, 'from': ref(first), 'to': ref(r), 'path_m': path,
                                   'seconds': r[6] - first[6], 'criterion': 'fresh command >=5m/s, physical path <0.25m for >=1s'})
                first = last = key = None
                path = 0
    return stalls


def score(rows, summary, events, parser_errors=()):
    """Conservative independent dimensions, each linked to original evidence identities."""
    admitted = [e for e in events if e[3] == 'ADMITTED']
    finish = [e for e in events if e[3] == 'FINISH']
    result = {'visual_flight_quality': finding('NOT ASSESSED', detail='Human video/foreground observation required.'),
              'fixture_completion': finding('INCOMPLETE', map(event_ref, finish)),
              'fixture_admission': finding(evidence=map(event_ref, admitted)),
              'capture_integrity': finding('INCOMPLETE'),
              'physical_progress': finding(), 'sustained_stalls': finding(),
              'target_commitment': finding(), 'vehicle_dismount': finding(),
              'control_suspension': finding(), 'active_attack_release': finding(),
              'payload_receipts': finding(), 'lifecycle_outcome': finding(), 'target_effects': finding(), 'natural_objects_at_observation': finding(), 'natural_group_plus_10': finding()}
    if finish:
        result['fixture_completion'] = finding('COMPLETE' if finish[-1][5][0] in ('FIXTURE_COMPLETE', 'REVIEW_COMPLETE') and finish[-1][5][1] == 'RESTORED' else 'INCOMPLETE', [event_ref(finish[-1])], 'Fixture completion does not establish flight PASS.')
    effects = [e for e in events if e[3] == 'EFFECTS']
    result['target_effects'] = finding('OBSERVED' if effects else 'NOT OBSERVED', map(event_ref, effects), 'Original target and crew damage/baselines; explosions alone establish no hit.')
    outcomes = [e for e in events if e[3] == 'OUTCOME']
    if outcomes:
        receipts = outcomes[-1][5][4]
        result['payload_receipts'] = finding('OBSERVED' if len(receipts) <= 1 else 'FAIL', map(event_ref, outcomes), 'Receipt count=' + str(len(receipts)) + '; contact/prediction, target damage and settlement are separate.')
        result['lifecycle_outcome'] = finding('OBSERVED', map(event_ref, outcomes), 'Exact original lifetime phase/outcome/closure; no support/accounting PASS is inferred from this transient fixture.')
    retention = [e for e in events if e[3] == 'NATURAL_RETENTION']
    if retention:
        status = 'NOT OBSERVED'
        for e in retention:
            d=e[5];delta=d[3]-d[4]
            if d[4] >= 0 and delta >= 10:
                if not all(d[7]):status='FAIL'
                elif delta <= 11 and d[7] and status != 'FAIL':status='PASS'
        result['natural_objects_at_observation'] = finding('OBSERVED', map(event_ref, retention), 'Exact drone/crew/group/script-handle absence at recorded closure age. The marker is a QA anchor requiring explicit teardown, not a natural support marker gate.')
        result['natural_group_plus_10'] = finding(status, map(event_ref, retention), 'Late absence cannot establish the deadline. Explicit teardown never qualifies natural retention. Earlier known group+10 failures remain open.')
    if len(admitted) != 1 or not summary:
        return result
    a = admitted[0][5]
    run, nonce, drone, life, target_a, target_b, ready, activity = a[:8]
    identity = [r for r in rows if r[5] == 'IDENTITY' and r[9] == drone and r[12][1] == life]
    result['fixture_admission'] = finding('OBSERVED' if ready and identity else 'INCOMPLETE', [event_ref(admitted[0])] + list(map(ref, identity)))
    good = (summary['integrity'] == 'complete_requested_duration' and not parser_errors and len(identity) == 1
            and summary['run_id'] == run and summary['capture'] == nonce)
    integrity_rows = [r for r in rows if r[5] in ('START', 'END')]
    result['capture_integrity'] = finding('PASS' if good else 'INCOMPLETE', map(ref, integrity_rows),
        json.dumps({k: summary[k] for k in ('integrity', 'elapsed_seconds', 'requested_seconds', 'sequence_loss', 'dropped', 'end_sample_gap_and_misses', 'warnings')}))
    # Cross-lifetime or incomplete captures may retain observations, never qualify functional PASS.
    if not good:
        return result
    rr = [r for r in rows if r[9] == drone]
    audit = summary['drones'].get(drone, {}).get('derived_motion', {})
    windows = audit.get('windows', [])
    progress = [w for w in windows if w['status'] == 'NO_SUSTAINED_STALL' and w['observed_step_distance_m'] >= 2.5]
    stalls = [w for w in windows if w['status'] == 'STALL_CANDIDATE' or w['longest_stationary_high_velocity_seconds'] >= 1]
    commanded = commanded_stalls(rows)
    def wref(w):
        return {'run': run, 'capture': nonce, 'drone': drone, 'lifetime': w['lifetime'], 'generation': w['generation'],
                'sequences': [w['from_sequence'], w['to_sequence']], 'path_m': w['observed_step_distance_m'],
                'target': w['target'], 'begin': w['begin'], 'end': w['end']}
    result['physical_progress'] = finding('OBSERVED' if progress else 'NOT OBSERVED', map(wref, progress))
    result['sustained_stalls'] = finding('FAIL' if stalls or commanded else ('NO STALL IN COVERED WINDOWS' if windows else 'NOT OBSERVED'), list(map(wref, stalls)) + commanded, 'See parser derived_motion.uncovered_segments and UNKNOWN windows; absence of a candidate is not blanket flight PASS.')
    marks = [r for r in rows if r[5] == 'MARK' and len(r[12]) == 4 and r[12][:2] == ['F2R_AUTO', admitted[0][2]]]
    result['target_commitment'] = finding('REVIEW REQUIRED' if any(r[12][2] == 'COMMITMENT_PLAYER' for r in marks) else 'NOT OBSERVED',
        map(ref, marks), 'Review sampled obstruction, continuous eligible target ID, MOVE and actual SAMPLE displacement. Collision/spend is separate from target effects.')
    dismount = [r for r in marks if r[12][2].startswith('DISMOUNT') or r[12][2] == 'TARGET_ELIGIBILITY']
    result['vehicle_dismount'] = finding('REVIEW REQUIRED' if any(r[12][2] == 'DISMOUNT_ISSUED' for r in dismount) else 'NOT OBSERVED',
        map(ref, dismount), 'Command issue is not actual exit. Review original crew parent IDs, current resolved target, partial control, old intent rejection and timing/inertia.')
    control = [r for r in rr if r[5] in ('CONTROL','STEERING','TRAJECTORY')]
    result['active_attack_release'] = finding('REVIEW REQUIRED' if any(r[5] == 'CONTROL' and r[12][0] for r in control) else 'NOT OBSERVED',
        map(ref, control), 'Require active steering before real takeover, no autonomous movement/fuse under control, new serial/real-state zero-dt seed and resumed actual progress. No synthetic control flags.')
    return result


def preflight(args, manifest):
    args.evidence.mkdir(parents=True, exist_ok=False)
    decoder, startup = LiveLines(), []
    with args.rpt.open('rb') as stream:
        prefix = stream.read(65536)
        raw = prefix
        while raw:
            for line in decoder.feed(raw):
                if (e := auto_event(line)) and e[2] == args.session:
                    raise ValueError('stale session ticket already exists; select a new ticket/evidence directory')
                if stream.tell() <= 2 * 1024 * 1024:
                    startup.append(line)
            raw = stream.read(65536)
        stat = os.fstat(stream.fileno())
    receipt = {'session': args.session, 'rpt': str(args.rpt.resolve()), 'file_identity': [stat.st_dev, stat.st_ino], 'startup_prefix_bytes': len(prefix),
               'startup_prefix_sha256': hashlib.sha256(prefix).hexdigest(),
               'helpers': disk_identity(manifest), 'manifest_sha256': sha(args.manifest),
               'identity': startup_identity('\n'.join(startup), manifest), 'engine_activity': 'NOT RUN by tooling'}
    write_json(args.evidence / 'preflight.json', receipt, True)
    print('PREFLIGHT VERIFIED: candidate, rollback, deployed helpers and startup inventory. Arm only the selected activity.')


def verify_preflight(args, manifest, current_deployment=True):
    p = json.loads((args.evidence / 'preflight.json').read_text(encoding='utf-8'))
    if p['session'] != args.session or p['rpt'] != str(args.rpt.resolve()) or current_deployment and p['manifest_sha256'] != sha(args.manifest):
        raise ValueError('preflight session/RPT/manifest mismatch')
    with args.rpt.open('rb') as f:
        stat = os.fstat(f.fileno())
        if [stat.st_dev, stat.st_ino] != p['file_identity']:
            raise ValueError('RPT file identity changed since preflight')
        if hashlib.sha256(f.read(p['startup_prefix_bytes'])).hexdigest() != p['startup_prefix_sha256']:
            raise ValueError('RPT replaced/truncated since preflight')
    if current_deployment:
        disk_identity(manifest)
    return p


def monitor(args, manifest):
    verify_preflight(args, manifest)
    events, admitted, done, parser_errors = [], None, False, []
    decoder = LiveLines()
    started = time.monotonic()
    activity_file = args.evidence / 'capture.rpt'
    position, line_number, finish = 0, 0, None
    terminal = 'RUNNING'
    raw_path = args.evidence / 'live-source.rpt'
    with args.rpt.open('rb') as source, raw_path.open('xb') as snapshot, activity_file.open('x', encoding='utf-8') as selected, (args.evidence / 'events.jsonl').open('x', encoding='utf-8') as event_file:
        while time.monotonic() - started < args.timeout:
            stat = args.rpt.stat()
            handle_stat = os.fstat(source.fileno())
            if stat.st_size < position or (stat.st_dev, stat.st_ino) != (handle_stat.st_dev, handle_stat.st_ino):
                terminal = 'INTERRUPTED_RPT_TRUNCATED'
                break
            chunk = source.read(65536)
            if chunk:
                position += len(chunk)
                snapshot.write(chunk)
                for line in decoder.feed(chunk):
                    line_number += 1
                    try:
                        e = auto_event(line)
                    except ValueError:
                        if args.session in line:
                            parser_errors.append('Malformed activity event at source line ' + str(line_number))
                        continue
                    if e and e[2] == args.session:
                        events.append(e)
                        event_file.write(json.dumps(e) + '\n')
                        event_file.flush()  # rare phase boundaries, outside the flight/capture producer
                        if len(events) > 512:
                            raise ValueError('activity event bound exceeded')
                        if e[3] == 'ADMITTED':
                            if admitted is not None:
                                parser_errors.append('duplicate ADMITTED')
                            admitted = e[5]
                            if canonical(admitted[8]) != canonical(manifest['missions']['installed']['path']):
                                raise ValueError('actual mission path mismatch')
                        if e[3] == 'SESSION' and (e[5][:2] != ['EJ_FPV_QA','vt7'] or canonical(e[5][2]) != canonical(manifest['missions']['installed']['path'])):
                            raise ValueError('actual session mission/profile/world mismatch')
                        if e[3] == 'FINISH':
                            finish = e
                    if admitted and any(t in line for t in ('A3UE_FPV_QA|', 'A3UE_FPV_QA_PART', 'A3UE_FPV_QA_EXPORT_DONE')):
                        tag = next(t for t in ('A3UE_FPV_QA|', 'A3UE_FPV_QA_PART', 'A3UE_FPV_QA_EXPORT_DONE') if t in line)
                        try:
                            v = capture.sqf_array(line[line.index('["' + tag + '"'):])
                            key = v[1][1:4] if tag == 'A3UE_FPV_QA|' else v[2:5]
                            if key == [admitted[0], 2, admitted[1]]:
                                selected.write(line + '\n')
                                if tag == 'A3UE_FPV_QA_EXPORT_DONE':
                                    done = True
                        except (ValueError, IndexError, TypeError):
                            if admitted[0] in line or admitted[1] in line:
                                parser_errors.append('Malformed capture input at line ' + str(line_number))
                    if 'Memory should be free now.' in line and not finish:
                        terminal = 'INTERRUPTED_SHUTDOWN'
                if finish:
                    terminal = 'EXPORT_COMPLETE' if done else ('ACTIVITY_STOPPED' if admitted is None else 'INCOMPLETE_EXPORT')
                    break
                if terminal != 'RUNNING':
                    break
            else:
                write_json(args.evidence / 'status.json', {'status': 'RUNNING', 'bytes_read': position, 'session': args.session, 'export_done_seen': done})
                time.sleep(.5)
        else:
            terminal = 'TIMED_OUT_INCOMPLETE_EXPORT' if not done else 'TIMED_OUT_FINALIZATION'
    result, rows = None, []
    if done:
        try:
            parsed, sessions = capture.collect([activity_file])  # exactly one parser invocation
            parser_errors += parsed['errors']
            result = next((s for s in parsed['sessions'] if s['run_id'] == admitted[0] and s['capture'] == admitted[1]), None)
            rows = sessions.get((admitted[0], 2, admitted[1]), [])
            write_json(args.evidence / 'parser.json', parsed, True)
            (args.evidence / 'parser.md').write_text(capture.markdown(parsed), encoding='utf-8')
            with (args.evidence / 'capture.records.jsonl').open('x', encoding='utf-8') as f:
                for row in rows:
                    f.write(json.dumps(row) + '\n')
        except Exception as exc:
            parser_errors.append('capture parser failed: ' + type(exc).__name__)
            terminal = 'PARSER_FAILED'
    dimensions = score(rows, result, events, parser_errors)
    report = {'session': args.session, 'status': terminal, 'source_bytes_collected': position,
              'snapshot_sha256': sha(raw_path), 'partial_line_characters': len(decoder.pending),
              'partial_encoded_bytes': len(decoder.decoder.getstate()[0]) if decoder.decoder else len(decoder.initial),
              'errors': parser_errors, 'dimensions': dimensions, 'events': events,
              'shutdown_archive': 'PENDING; use Archive after normal user exit. Do not wait to review this activity.'}
    write_json(args.evidence / 'findings.json', report, True)
    write_json(args.evidence / 'status.json', {'status': terminal, 'session': args.session})
    lines = [f'F2C {args.session}: {terminal}', '', 'Fixture, flight, effects, visual quality and natural retention are independent.', '']
    lines += [f'- {name}: {value["status"]}' for name, value in dimensions.items()]
    lines += ['', 'Evidence references and limitations: findings.json; capture metrics: parser.json when complete.', 'Original source remains untouched. Shutdown archive pending normal user exit.']
    (args.evidence / 'summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('\n'.join(lines[:4] + lines[4:]))
    return 0 if terminal in ('EXPORT_COMPLETE','ACTIVITY_STOPPED') and not parser_errors else 2


def archive(args, manifest):
    verify_preflight(args, manifest, current_deployment=False)
    # One explicit later collection, no indefinite wait. Preserve the complete raw bytes.
    stamp = str(time.time_ns())
    destination = args.evidence / ('shutdown-' + stamp + '.rpt')
    before = args.rpt.stat().st_size
    with args.rpt.open('rb') as source, destination.open('xb') as dest:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            dest.write(block)
    after = args.rpt.stat().st_size
    decoder = LiveLines()
    shutdown = False
    with destination.open('rb') as f:
        for raw in iter(lambda: f.read(65536), b''):
            shutdown |= any('Memory should be free now.' in line for line in decoder.feed(raw))
    complete = before == after == destination.stat().st_size and shutdown and not decoder.pending
    receipt = {'path':str(destination),'complete_shutdown_archive': complete, 'bytes': destination.stat().st_size,
        'sha256': sha(destination), 'source_unchanged': before == after}
    write_json(args.evidence / ('shutdown-' + stamp + '.json'), receipt, True)
    write_json(args.evidence / 'shutdown.json', receipt)
    print('SHUTDOWN ARCHIVED' if complete else 'INCOMPLETE SHUTDOWN SNAPSHOT: retained, no qualification')
    return 0 if complete else 2


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode', choices=['Preflight','Monitor','Archive'], required=True)
    p.add_argument('--rpt', type=Path, required=True)
    p.add_argument('--session', required=True)
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('--manifest', type=Path, default=HERE / 'manifest.json')
    p.add_argument('--timeout', type=int, default=360)
    args = p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]{8,64}', args.session) or not 1 <= args.timeout <= 900:
        p.error('unique 8..64 character session ticket and bounded timeout required')
    try:
        manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
        if args.mode == 'Preflight':
            preflight(args, manifest)
            return 0
        if args.mode == 'Monitor':
            return monitor(args, manifest)
        if args.mode == 'Archive':
            return archive(args, manifest)
        raise ValueError("unsupported mode")
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        # Do not echo file contents, account/command lines or arbitrary exception strings.
        print('F2C REFUSED: ' + (str(exc) if isinstance(exc, ValueError) else type(exc).__name__), file=sys.stderr)
        if args.evidence.is_dir():
            write_json(args.evidence / ('refusal-' + str(time.time_ns()) + '.json'), {'status':'REFUSED','exception':type(exc).__name__}, True)
            if not (args.evidence / 'findings.json').exists():
                write_json(args.evidence / 'status.json', {'status':'REFUSED','session':args.session,'exception':type(exc).__name__})
        return 2


if __name__ == '__main__':
    sys.exit(main())
