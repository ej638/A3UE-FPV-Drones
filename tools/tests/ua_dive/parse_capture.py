"""Parse bounded UAQA SQF-array exports. Standard library; never modifies an RPT.

python tools/tests/ua_dive/parse_capture.py return-folder --out return-folder/summary
Accepts files/directories; writes .json, .md, and .records.jsonl. No eval, no extensions.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import re

TOKEN = re.compile(r'\s*(?:("(?:[^"\r\n]|"")*")|([-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)|(true|false)|([\[\],]))')


def sqf_array(text):
    """SQF str arrays use doubled quotes, not JSON backslash escaping."""
    tokens, pos = [], 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            if text[pos:].strip():
                raise ValueError(f"invalid SQF token at {pos}")
            break
        string, number, boolean, punct = m.groups()
        tokens.append(('value', string[1:-1].replace('""', '"')) if string is not None else
                      ('value', float(number)) if number is not None else
                      ('value', boolean == 'true') if boolean is not None else (punct, punct))
        pos = m.end()
    index = 0

    def value(depth=0):
        nonlocal index
        if depth > 32 or index >= len(tokens):
            raise ValueError("truncated/excessively nested array")
        kind, item = tokens[index]
        index += 1
        if kind == 'value':
            return item
        if kind != '[':
            raise ValueError("expected array/value")
        result = []
        if index < len(tokens) and tokens[index][0] == ']':
            index += 1
            return result
        while True:
            result.append(value(depth + 1))
            if index >= len(tokens):
                raise ValueError("unterminated array")
            kind = tokens[index][0]
            index += 1
            if kind == ']':
                return result
            if kind != ',':
                raise ValueError("expected comma")

    result = value()
    if index != len(tokens) or not isinstance(result, list):
        raise ValueError("trailing data/non-array")
    return result


def percentile(values, q):
    if not values:
        return None
    v = sorted(values)
    k = (len(v) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def stats(values, scale=1):
    return {"n": len(values), "p50": percentile(values, .5) * scale if values else None,
            "p95": percentile(values, .95) * scale if values else None,
            "max": max(values) * scale if values else None,
            "over_100ms": sum(x > .1001 for x in values) if scale == 1000 else None}


def magnitude(vector):
    return math.sqrt(sum(x * x for x in vector))


TERMINAL = ('TERMINAL_ATTACK', 'TERMINAL_VECTOR')
CLOCK_FIELDS = {
    'MOVE': [(0, '@diag', False), (1, '@diag', False)],
    'STEERING': [(2, '@mission', False), (3, '@diag', False)],
    'POSE': [(1, '@diag', False), (2, '@diag', False),
             (3, '@frame', False), (4, '@frame', False)],
    'AI_INTENT': [(0, '@diag', False)], 'DO_MOVE': [(0, '@diag', False)],
    'LOOP': [(0, '@diag', False), (2, '@mission', False), (3, '@mission', True),
             (4, '@mission', True), (5, '@mission', True), (7, '@diag', True)],
    'FUSE': [(2, '@diag', True)], 'STATE': [(15, '@diag', True)],
}
MIN_FIELDS = {'START': 12, 'END': 5, 'IDENTITY': 8, 'SAMPLE': 10, 'STATE': 27,
              'MOVE': 8, 'POSE': 8, 'STEERING': 12, 'TRAJECTORY': 4, 'AI_INTENT': 4, 'DO_MOVE': 2, 'LOOP': 10, 'FUSE': 5,
              'COMMIT': 4, 'BROKER': 5, 'RADIO': 3, 'GEOMETRY': 7,
              'GUIDANCE_WORK': 2, 'STRIKE': 1, 'MARK': 1, 'PARAMETERS': 15,
              'MODE': 5, 'CONTROL': 1, 'LINK': 8, 'CONTACT': 2, 'LOCALITY': 2,
              'KILLED': 0, 'DELETED': 0, 'INJECTION': 2, 'RECOVERY': 8, 'PURSUIT': 9, 'PHASE_CUE': 2, 'HUNT_TARGET': 6}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def integer(value, minimum=0):
    return number(value) and value >= minimum and int(value) == value


def validate_row(row):
    if not isinstance(row, list) or len(row) != 13 or (not integer(row[0], 1) or row[0] not in (1, 2)):
        raise ValueError('unknown/missing row schema (expected v1/v2, 13 fields)')
    if not all(isinstance(row[i], str) for i in (1, 3, 5, 9, 11)):
        raise ValueError('invalid record identity/event')
    if not all(integer(row[i], minimum) for i, minimum in ((2, 0), (4, 1), (8, 0), (10, -1))):
        raise ValueError('invalid process/sequence/frame/generation')
    if not all(number(row[i]) for i in (6, 7)) or not isinstance(row[12], list):
        raise ValueError('invalid clock/payload')
    if row[5] not in MIN_FIELDS or len(row[12]) < MIN_FIELDS[row[5]]:
        raise ValueError('unknown event or truncated event payload: ' + row[5])

    def finite_tree(value):
        if isinstance(value, list):
            return all(finite_tree(x) for x in value)
        return not isinstance(value, (int,float)) or isinstance(value,bool) or number(value)

    if not finite_tree(row[12]):
        raise ValueError('nonfinite event payload')
    kind, data = row[5], row[12]
    vectors = {'STEERING': (4,5,6,7), 'SAMPLE': (0,1), 'MOVE': (2,3), 'AI_INTENT': (3,), 'DO_MOVE': (1,),
               'PARAMETERS': (5,10), 'HUNT_TARGET': (1,2), 'STATE': (16,17)}.get(kind, ())
    if any(not isinstance(data[i],list) or len(data[i]) != 3 or not all(number(x) for x in data[i]) for i in vectors):
        raise ValueError('invalid position/velocity vector in ' + kind)
    numeric = {'SAMPLE': (2,3,4,6,9), 'MOVE': (4,5,6,7), 'AI_INTENT': (1,2),
               'LOOP': (1,6), 'FUSE': (1,), 'GEOMETRY': (0,), 'RADIO': (0,2),
               'GUIDANCE_WORK': (0,), 'END': (0,1,2,3,4)}.get(kind, ())
    if any(not number(data[i]) for i in numeric):
        raise ValueError('invalid numeric event field in ' + kind)
    booleans = {'STEERING': (8,9), 'SAMPLE': (5,), 'STATE': (0,2,3,8,13,22,24,25), 'CONTROL': (0,),
                'MODE': (2,), 'LOOP': (8,9), 'FUSE': (0,), 'LOCALITY': (0,)}.get(kind, ())
    if any(not isinstance(data[i], bool) for i in booleans):
        raise ValueError('invalid Boolean event field in ' + kind)
    if kind == 'COMMIT' and data[0] not in ('COMMITTED','REJECTED','DUPLICATE'):
        raise ValueError('unknown COMMIT outcome')
    if kind == 'START' and (data[7:10] != [.02,.5,60000] or not integer(data[11]) or data[11] > 3):
        raise ValueError('invalid START capture bounds/cadences')
    if kind == 'POSE' and (row[0] != 2 or len(data) != 8 or not integer(data[0], 1) or data[0] != 1
                           or not all(integer(data[i], 1 if i == 7 else 0) for i in (5,6,7))
                           or data[5] != row[10]):
        raise ValueError('invalid POSE version/identity/context')

    if kind == 'PURSUIT':
        if (len(data) != 9 or data[0] not in ('PURSUE', 'INVESTIGATE')
                or not isinstance(data[1], str) or not data[1]
                or any(not number(data[i]) or data[i] < 0 for i in (2, 3, 7, 8))
                or any(not isinstance(data[i], list) or len(data[i]) not in ((0, 3) if i == 6 else (3,))
                       or not all(number(x) for x in data[i]) for i in (4, 5, 6))):
            raise ValueError('invalid PURSUIT memory/goal')

    if kind == 'RECOVERY':
        writer = len(data) == 9 and data[0] == 'WRITER'
        if (len(data) != 8 and not writer or not all(isinstance(x, str) for x in data[:4])
                or not isinstance(data[4], list) or len(data[4]) not in (0, 5)
                or not all(number(x) for x in data[4]) or not number(data[7])
                or not isinstance(data[6], list) or len(data[6]) not in (0, 3)
                or not all(number(x) for x in data[6])):
            raise ValueError('invalid RECOVERY transition')
        if writer:
            ownership = data[8]
            if (not isinstance(ownership, list) or len(ownership) != 3
                    or not isinstance(ownership[0], bool)
                    or not isinstance(ownership[1], list) or len(ownership[1]) not in (0, 4)
                    or not all(integer(x) for x in ownership[1])
                    or not isinstance(ownership[2], list) or len(ownership[2]) not in (0, 2)
                    or ownership[2] and (not isinstance(ownership[2][0], str) or not number(ownership[2][1]))):
                raise ValueError('invalid RECOVERY writer ownership')
        rejection = data[5]
        if (not isinstance(rejection, list) or (rejection and
                (len(rejection) != 5 or rejection[0] not in ('OBJECT','TERRAIN','HEIGHT','ENVELOPE')
                 or not integer(rejection[1], -1)
                 or any(not isinstance(rejection[i], list) or len(rejection[i]) not in (0,3)
                        or not all(number(x) for x in rejection[i]) for i in (2,3))))):
            raise ValueError('invalid RECOVERY rejection')
    if kind == 'HUNT_TARGET' and (len(data) != 6 or not isinstance(data[0], str)
            or not isinstance(data[3], bool) or not number(data[4]) or not isinstance(data[5], list)
            or len(data[5]) > 2 or any(not isinstance(c,list) or len(c) != 3
                or not isinstance(c[0],str) or not isinstance(c[1],bool) or not number(c[2]) for c in data[5])):
        raise ValueError('invalid HUNT_TARGET')
    if kind == 'PHASE_CUE'  and (len(data) != 2 or not all(isinstance(x,str) for x in data)):
        raise ValueError('invalid PHASE_CUE')

    if kind == 'TRAJECTORY':
        if row[0] != 2 or len(data) != 4 or data[0] != 1 or not isinstance(data[2], str):
            raise ValueError('invalid TRAJECTORY version/payload')
        plan, seed = data[1], data[3]
        if (not isinstance(plan, list) or len(plan) != 5
                or not all(number(plan[i]) for i in (0,2,3,4))
                or not isinstance(plan[1], list) or len(plan[1]) not in (0,3)
                or not all(number(x) for x in plan[1])):
            raise ValueError('invalid TRAJECTORY plan')
        if (not isinstance(seed, list) or (seed and (len(seed) != 8 or not integer(seed[0],1)
                or not all(number(seed[i]) for i in (1,2,5,7)) or seed[7] != 0
                or not isinstance(seed[6],str)
                or any(not isinstance(seed[i],list) or len(seed[i]) != 3 or not all(number(x) for x in seed[i]) for i in (3,4))))):
            raise ValueError('invalid TRAJECTORY reconstruction')

    if kind == 'STEERING':
        if row[0] != 2 or data[0] != 1 or len(data) != 12 or not isinstance(data[1], list):
            raise ValueError('invalid STEERING version/payload')
        logical = data[1]
        if logical:
            if (len(logical) != 12 or not isinstance(logical[0], list) or len(logical[0]) != 9
                    or not integer(logical[5], 1) or not isinstance(logical[6], str)
                    or any(not number(logical[i]) for i in (3,7,10,11))
                    or logical[3] < 0 or not 0 <= logical[7] <= .25
                    or any(not isinstance(logical[i], list) or len(logical[i]) != 3
                           or not all(number(x) for x in logical[i]) for i in (1,2,4,8,9))):
                raise ValueError('invalid STEERING logical state')
        if not isinstance(data[10], list) or not isinstance(data[11], str):
            raise ValueError('invalid STEERING current identity/target')


def clock_fields(kind, data):
    if kind == 'STRIKE':
        return [(1, '@diag', True)] if data[0] == 'THROTTLED' else (
            [(3, '@diag', True)] if data[0] == 'PROPOSED' else [])
    return CLOCK_FIELDS.get(kind, [])


def normalized(rows, start):
    # Summary works in elapsed diag/server clocks; raw wire rows remain untouched.
    result = json.loads(json.dumps(rows))
    for row in result:
        validate_row(row)
        if row[0] == 1:
            row[6] -= start[6]
            row[7] -= start[7]
            row[8] -= start[8]
        data = row[12]
        for field, domain, deadline in clock_fields(row[5], data):
            value = data[field]
            if row[0] == 2:
                if deadline and number(value) and value <= 0:
                    continue
                if not isinstance(value, list) or len(value) != 2 or value[0] != domain or not number(value[1]):
                    raise ValueError(f'{row[5]}[{field}]: missing/wrong {domain} clock tag')
                if domain == '@frame' and not integer(value[1]):
                    raise ValueError('POSE: invalid relative frame')
                data[field] = value[1]
            elif domain == '@diag' and not (deadline and number(value) and value <= 0):
                data[field] -= start[6]
        if row[5] == 'POSE' and (data[2] < data[1] or data[4] < data[3]):
            raise ValueError('POSE: reversed setter bracket')
    return result


def pose_audit(rows):
    """Actual setter brackets only; diag intervals are not simulation-time gate measurements."""
    writes, pairs, previous = [], [], {}
    for r in rows:
        if r[5] != 'POSE':
            continue
        _, before, after, frame_before, frame_after, gen, episode, serial = r[12]
        context = (gen, episode, serial)
        writes.append({'sequence': r[4], 'generation': gen, 'episode': episode, 'entry_serial': serial,
                       'diag_before': before, 'diag_after': after,
                       'frame_before': frame_before, 'frame_after': frame_after,
                       'attribution': 'exact_recorded_frame' if frame_before == frame_after else 'ambiguous_frame_span'})
        if context in previous:
            a = previous[context]
            pairs.append({'from_sequence': a[4], 'to_sequence': r[4],
                          'generation': gen, 'episode': episode, 'entry_serial': serial,
                          'diag_after_to_before_ms': (before-a[12][2])*1000,
                          'frames_after_to_before': int(frame_before-a[12][4])})
        previous[context] = r
    return {'writes': writes, 'pairs': pairs, 'count': len(writes),
            'ambiguous_count': sum(w['attribution'] == 'ambiguous_frame_span' for w in writes)}


def overlap(intervals):
    events = defaultdict(list)
    for drone, begin, end in intervals:
        if end > begin:
            events[begin].append((drone, 1))
            events[end].append((drone, -1))
    active, windows, maximum = Counter(), [], 0
    times = sorted(events)
    for i, tick in enumerate(times):
        for drone, delta in events[tick]:
            active[drone] += delta
        roster = sorted(d for d, n in active.items() if n > 0)
        maximum = max(maximum, len(roster))
        if i + 1 < len(times) and len(roster) >= 2:
            windows.append({'begin': tick, 'end': times[i+1], 'drones': roster})
    return {'max_concurrency': maximum,
            'seconds_at_least_2': sum(w['end']-w['begin'] for w in windows),
            'seconds_at_least_3': sum(w['end']-w['begin'] for w in windows if len(w['drones']) >= 3),
            'windows': windows}


def motion_audit(rows, version):
    """Offline observations only. Never equate setVelocity readback with travel.

    One-second disjoint windows, no interpolation across a boundary or >100ms
    sample gap. Expected distance is trapezoidal *speed*, not net velocity, so
    turns do not cancel travel. State is sampled: even fresh flags cannot rule
    out an intervening change/writer. Sequence ranges refer to preserved rows.
    """
    limits = {'window_seconds': 1, 'minimum_seconds': .5, 'minimum_samples': 10,
              'maximum_sample_gap_seconds': .1, 'state_max_age_seconds': .75,
              'minimum_sampled_speed_mps': 5, 'minimum_expected_m': 2.5,
              'stall_ratio_below': .1, 'stall_observed_mps_below': 1,
              'stationary_step_m_below': .02}
    segments, current = [], None
    life = episode = owner = target = local = control = None
    state, state_at, contact_at, stopped = None, None, None, False
    for r in rows:
        event, d = r[5], r[12]
        boundary = event in ('IDENTITY', 'LOCALITY', 'CONTROL', 'MODE', 'CONTACT')
        if event in ('IDENTITY', 'STATE'):
            newlife, episode = d[1:3] if event == 'IDENTITY' else d[4:6]
            if life is not None and newlife != life:
                stopped, state, state_at, contact_at = False, None, None, None
                owner = target = local = control = None
            life = newlife
        if event == 'STATE':
            newstate = (d[2], d[3], d[13], d[14], d[10], d[11], d[12])
            boundary |= state != newstate or control != d[8]
            state, state_at, control = newstate, r[6], d[8]
            if not d[3] or d[13]:
                stopped = True  # delivery parking may precede COMMIT visibility
        if event == 'CONTROL':
            control = d[0]
        if event == 'LOCALITY':
            local, owner = d[:2]
        if event == 'CONTACT':
            contact_at = r[6]
        if event == 'SAMPLE':
            local, owner, target = d[5:8]
        key = (life, episode, r[10], r[11], owner, local, target, control, stopped, state)
        if current is None or boundary or key != current['key']:
            current = {'key': key, 'begin': r[6], 'end': r[6], 'rows': [], 'samples': []}
            segments.append(current)
        current['end'] = r[6]
        current['rows'].append(r)
        if event == 'SAMPLE':
            current['samples'].append((r, state_at, contact_at))
        if event in ('KILLED', 'DELETED') or (event == 'COMMIT' and d[0] == 'COMMITTED'):
            stopped = True
            current = None

    windows, cadence, exclusions, uncovered = [], [], [], []
    for index, seg in enumerate(segments, 1):
        life, episode, gen, mode, owner, local, target, control, stopped, state = seg['key']
        identity = dict(lifetime=life, episode=episode, generation=gen, mode=mode,
                        owner=owner, local=local, target=target, external_control=control,
                        segment=index)
        if stopped:
            exclusions.append({**identity, 'begin': seg['begin'], 'end': seg['end'],
                               'samples': len(seg['samples']), 'reason': 'POST_OUTCOME_OR_DETONATING'})
            continue
        moves = [r for r in seg['rows'] if r[5] == 'MOVE']
        pairs = [{'from_sequence': a[4], 'to_sequence': b[4], 'begin': a[12][0],
                  'end': b[12][0], 'milliseconds': (b[12][0]-a[12][0])*1000,
                  'relative_frames': int(b[8]-a[8])} for a, b in zip(moves, moves[1:])]
        if moves:
            cadence.append({**identity, 'milliseconds': stats([p['milliseconds'] for p in pairs]),
                            'frames': stats([p['relative_frames'] for p in pairs]),
                            'frame_histogram': dict(Counter(p['relative_frames'] for p in pairs)),
                            'serialization_precise': version == 2, 'pairs': pairs})
        ss = seg['samples']
        if not ss and seg['rows']:
            uncovered.append({**identity, 'begin': seg['begin'], 'end': seg['end'],
                              'reason': 'NO_SAMPLES_IN_SEGMENT'})
        for (a,_,_), (b,_,_) in zip(ss,ss[1:]):
            if not 0 < b[6]-a[6] <= .1:
                uncovered.append({**identity, 'begin': a[6], 'end': b[6],
                                  'from_sequence': a[4], 'to_sequence': b[4],
                                  'reason': 'LONG_OR_NONPOSITIVE_SAMPLE_GAP'})
        # Windows share only an endpoint; the uncovered final tail is reported.
        start = 0
        while start < len(ss):
            end = start
            while end+1 < len(ss) and ss[end+1][0][6]-ss[start][0][6] <= 1:
                end += 1
            chunk = ss[start:end+1]
            samples = [item[0] for item in chunk]
            gaps = [b[6]-a[6] for a,b in zip(samples,samples[1:])]
            span = samples[-1][6]-samples[0][6]
            speeds = [magnitude(r[12][1]) for r in samples]
            steps = [magnitude([y-x for x,y in zip(a[12][0],b[12][0])])
                     for a,b in zip(samples,samples[1:])]
            expected = sum((a+b)*.5*dt for a,b,dt in zip(speeds,speeds[1:],gaps))
            observed = sum(steps)
            unknown = []
            if span < .5 or len(samples) < 10:
                unknown.append('INADEQUATE_SAMPLE_COVERAGE')
            if any(dt <= 0 or dt > .1 for dt in gaps):
                unknown.append('LONG_OR_NONPOSITIVE_SAMPLE_GAP')
            if not integer(life) or not integer(episode) or gen < 0 or target in (None, '') or control is None or not integer(owner,1):
                unknown.append('UNKNOWN_IDENTITY_TARGET_OR_CONTROL')
            if state is None or any(at is None or not 0 <= r[6]-at <= .75 for r,at,_ in chunk):
                unknown.append('MISSING_OR_STALE_SIMULATION_STATE')
            if any(at is not None and 0 <= r[6]-at <= .5 for r,_,at in chunk):
                unknown.append('RECORDED_CONTACT_NEAR_WINDOW')
            if state is not None and (not state[0] or state[3]):
                unknown.append('SIMULATION_DISABLED_OR_RECORDED_FAILURE_REASON')
            if not local:
                unknown.append('NONLOCAL_OBSERVATION')
            if control:
                unknown.append('EXTERNAL_CONTROL')
            if version == 1:
                unknown.append('LEGACY_SERIALIZATION_PRECISION')
            # Commanded velocity is a separate diagnostic, never the denominator.
            command_speeds, command_covered, mi = [], 0, 0
            for r in samples:
                while mi+1 < len(moves) and moves[mi+1][12][0] <= r[6]:
                    mi += 1
                if moves and 0 <= r[6]-moves[mi][12][0] <= .1:
                    command_speeds.append(magnitude(moves[mi][12][2]))
                    command_covered += 1
            holds = bool(command_speeds) and min(command_speeds) < 1
            ratio = observed/expected if expected > 1e-6 else None
            if mode != 'TERMINAL_VECTOR':
                status = 'INAPPLICABLE_MODE'
            elif control:
                status = 'INAPPLICABLE_CONTROL'
            elif expected < 2.5 or min(speeds) < 5 or holds:
                status = 'LOW_EXPECTED_TRAVEL_OR_POSSIBLE_INTENTIONAL_HOLD'
            elif unknown:
                status = 'UNKNOWN'
            elif ratio < .1 and observed/span < 1:
                status = 'STALL_CANDIDATE'
            else:
                status = 'NO_SUSTAINED_STALL'
            chain = longest = 0
            for step, dt, a, b in zip(steps,gaps,speeds,speeds[1:]):
                chain = chain+dt if 0 < dt <= .1 and step < .02 and min(a,b) >= 5 else 0
                longest = max(longest,chain)
            windows.append({**identity, 'begin': samples[0][6], 'end': samples[-1][6],
                            'from_sequence': samples[0][4], 'to_sequence': samples[-1][4],
                            'from_frame': samples[0][8], 'to_frame': samples[-1][8],
                            'sample_count': len(samples), 'sample_gaps_ms': stats(gaps,1000),
                            'covered_seconds': sum(dt for dt in gaps if 0 < dt <= .1),
                            'observed_step_distance_m': observed, 'net_displacement_m': magnitude([
                                b-a for a,b in zip(samples[0][12][0],samples[-1][12][0])]),
                            'sampled_velocity_expected_travel_m': expected,
                            'observed_to_expected_ratio': ratio, 'sampled_speed_mps': stats(speeds),
                            'commanded_speed_mps': stats(command_speeds),
                            'fresh_command_sample_count': command_covered,
                            'longest_stationary_high_velocity_seconds': longest,
                            'status': status, 'unknowns': unknown,
                            'state': state, 'turning_observed': any(
                                sum(x*y for x,y in zip(a[12][1],b[12][1])) < .95*magnitude(a[12][1])*magnitude(b[12][1])
                                for a,b in zip([samples[0]]*len(samples),samples))})
            if end == len(ss)-1:
                break
            start = end if end > start else start+1
    return {'thresholds': limits, 'windows': windows, 'movement_write_cadence': cadence,
            'uncovered_segments': uncovered,
            'excluded': exclusions, 'status_counts': dict(Counter(w['status'] for w in windows)),
            'limitations': ['Sampled speeds estimate expected travel; command/readback velocities do not establish physical integration.',
                            'MOVE frame spacing uses the recorded after-command callback frame, not a physics-step clock or an atomic setter-frame stamp.',
                            'Sparse STATE rows cannot exclude intervening control, simulation, contact or competing writers. Unrecorded holds are unknown.',
                            'Each window is bounded by observed identity/state boundaries; no extrapolation across missing samples.']}


def summarize(records, footers=(), issues=()):
    warnings = list(issues)
    unique = {}
    for row in records:
        if row[4] in unique and unique[row[4]] != row:
            warnings.append('conflicting duplicate record at sequence ' + str(row[4]))
        unique.setdefault(row[4], row)
    rows = sorted(unique.values(), key=lambda r: r[4])
    starts = [r for r in rows if r[5] == 'START']
    ends = [r for r in rows if r[5] == 'END']
    for kind, found in [('START', starts), ('END', ends)]:
        if len(found) != 1:
            warnings.append(f'expected one {kind}; found {len(found)}')
    start = starts[0] if starts else rows[0]
    version = int(start[0])
    if len({r[0] for r in rows}) != 1 or (starts and start[12][0] != f'ua-dive-v{version}'):
        warnings.append('conflicting/unknown schema START')
    if starts and rows[0] != start:
        warnings.append('START is not first record')
    if ends and rows[-1] != ends[-1]:
        warnings.append('records after END')
    sequences = [int(r[4]) for r in rows]
    missing = sequences[0]-1 + sum(max(b-a-1, 0) for a, b in zip(sequences, sequences[1:]))
    if missing:
        warnings.append(f'{missing} missing sequence records')
    done = []
    for footer in footers:
        if footer not in done:
            done.append(footer)
    if len(done) != 1:
        warnings.append(f'expected one EXPORT_DONE; found {len(done)}' + (' (conflicting completion records)' if len(done) > 1 else ''))
    elapsed = ends[0][12][4] if ends else None
    dropped = ends[0][12][0] if ends else None
    if ends:
        data = ends[0][12]
        if not all(integer(data[i]) for i in (0, 1, 3)) or not number(elapsed) or elapsed < 0:
            warnings.append('invalid END counts/duration')
        if data[1] + 1 != len(rows):
            warnings.append('END retained-before-END count mismatch')
        if ends[0][4] != data[1] + 1 + data[0]:
            warnings.append('END sequence/count/drop mismatch')
        if data[1] > 60000 or (dropped and data[1] != 60000):
            warnings.append('END retained count violates producer buffer bounds')
        if dropped:
            warnings.append(f'buffer overflow: {dropped} dropped records')
        if version == 2 and (len(data) != 6 or data[5] not in ('duration', 'manual', 'cleanup')):
            warnings.append('invalid v2 END stop reason')
        if abs((ends[0][6]-start[6]) - elapsed) > (.11 if version == 1 else .02):
            warnings.append('END elapsed clock mismatch')
    if len(done) == 1:
        footer = done[0]
        if version == 1:
            if len(footer) != 4 or footer[1:3] != start[1:3] or not integer(footer[3]) or footer[3] != len(rows):
                warnings.append('EXPORT_DONE schema/identity/exported count mismatch')
        elif len(footer) != 8 or footer[1] != 2 or footer[2:5] != start[1:4] or not all(integer(x) for x in footer[5:]):
            warnings.append('EXPORT_DONE schema/identity/count mismatch')
        elif footer[5:] != [len(rows), rows[-1][4], dropped]:
            warnings.append('EXPORT_DONE exported/sequence/drop count mismatch')
    bases = None
    if version == 2 and starts:
        try:
            bases = start[12][12]
            if len(bases) != 4 or not all(isinstance(x, str) and re.fullmatch(r'-?\d+\.\d{6}' if i < 3 else r'\d+', x) for i, x in enumerate(bases)):
                raise ValueError()
            bases = dict(zip(('diag', 'server', 'mission', 'frame'), map(float, bases)))
            if not all(math.isfinite(x) for x in bases.values()):
                raise ValueError()
        except (IndexError, TypeError, ValueError):
            warnings.append('invalid/missing precise v2 clock bases')
            bases = None
    try:
        nr = normalized(rows, start)
    except (IndexError, TypeError, ValueError) as exc:
        warnings.append('malformed event payload: ' + str(exc))
        nr = []
    if any(b[6] < a[6] or b[8] < a[8] for a, b in zip(nr, nr[1:])):
        warnings.append('backward diag clock/frame')
    requested = start[12][6] if starts else None
    if not number(requested) or not 5 <= requested <= 180:
        warnings.append('invalid/missing requested duration')
    full = number(elapsed) and number(requested) and elapsed >= requested - .000001
    if version == 2 and ends and len(ends[0][12]) == 6 and ends[0][12][5] == 'duration' and not full:
        warnings.append('duration stop before requested duration')
    limitations = ['V2 preserves serialization precision, not precision already lost by engine Number clocks/positions. Mode and command spans do not prove uninterrupted per-frame guidance; observer video remains separate.'] if version == 2 else [
        'Legacy v1 absolute clocks/frames/positions use six significant figures. Rounded zero/100ms gaps are unverified command jitter; frame concurrency may be bucketed. Raw MOVE[5] is routine-entry dt, not movement-write timing.']
    drones, frames, modes, guidance = {}, defaultdict(set), [], []
    for drone_id in sorted({r[9] for r in nr if r[9]}):
        rr = [r for r in nr if r[9] == drone_id]
        identities = [r[12] for r in rr if r[5] == 'IDENTITY']
        if not identities:
            warnings.append(f'{drone_id}: missing IDENTITY')
        life, life_episode, stopped, external = None, None, False, False
        phase, segments, current = None, [], None
        observations, excluded = [], []
        for r in rr:
            kind, data = r[5], r[12]
            if kind == 'IDENTITY' or kind == 'STATE':
                newlife, newepisode = data[1:3] if kind == 'IDENTITY' else data[4:6]
                if life is not None and newlife != life:
                    stopped = False
                life, life_episode = newlife, newepisode
            if kind == 'CONTROL':
                external = data[0]
            if kind == 'STATE':
                external = data[8]
                if not data[3]:
                    stopped = True
            key = (life, life_episode, r[10], r[11], external, stopped)
            if key != phase:
                if current is not None and not current.get('closed'):
                    current['end'] = r[6]
                current = {'key': key, 'begin': r[6], 'end': r[6], 'rows': []}
                segments.append(current)
                phase = key
            current['end'] = r[6]
            current['rows'].append(r)
            if kind == 'SAMPLE':
                frames[r[8]].add(drone_id)
                (excluded if stopped else observations).append(r)
            if kind in ('KILLED', 'DELETED') or (kind == 'COMMIT' and data[0] == 'COMMITTED'):
                stopped = True
                current['closed'] = True
                # Outcomes remain separate from flight metrics, including rejected commits.
        phases, entries, work, wakes, late, displacements, stalls, ts, losses, slow_motion, sample_gaps = {}, {}, defaultdict(list), [], [], [], 0, [], [], [], []
        for i, segment in enumerate(segments, 1):
            life, ep, generation, mode, controlled, settled = segment['key']
            sr = segment['rows']
            label = f'life{life}/episode{ep}/gen{generation}/{mode}/segment{i}'
            if settled or controlled:
                continue
            ss = [r for r in sr if r[5] == 'SAMPLE']
            terminal = [r for r in ss if mode in TERMINAL and r[12][5]]
            speeds = [magnitude(r[12][1]) for r in terminal]
            ts.extend(speeds)
            losses.extend(max(a-b, 0) for a, b in zip(speeds, speeds[1:]))
            if mode in TERMINAL:
                modes.append((drone_id, segment['begin'], segment['end']))
            for kind in ('MOVE', 'AI_INTENT', 'DO_MOVE'):
                commands = [r for r in sr if r[5] == kind]
                times = [r[12][0] for r in commands]
                if any(b < a for a, b in zip(times, times[1:])):
                    warnings.append(f'{drone_id}: backward movement clock')
                if commands:
                    st = stats([b-a for a, b in zip(times, times[1:])], 1000)
                    st['serialization_precise'] = version == 2
                    st['fps_p05'] = percentile([r[12][2] for r in ss], .05)
                    phases[kind + '/' + label] = st
                    if (kind == 'MOVE' and mode == 'TERMINAL_VECTOR') or (kind == 'AI_INTENT' and mode == 'TERMINAL_ATTACK'):
                        guidance.append((drone_id, times[0], times[-1]))
                    if kind == 'MOVE':
                        entries[label] = stats([r[12][5] for r in commands if r[12][5] >= 0], 1000)
            for prev, r in zip(ss, ss[1:]):
                dt = r[6] - prev[6]
                sample_gaps.append(dt)
                displacement = magnitude([b-a for a, b in zip(prev[12][0], r[12][0])])
                displacements.append(displacement)
                stalls += int(mode in TERMINAL and r[12][5] and .015 <= dt <= .1 and displacement < .02)
            moves = [r for r in sr if r[5] == 'MOVE']
            mi = 0
            for sample in terminal:
                if not moves:
                    break
                while mi+1 < len(moves) and moves[mi+1][12][0] <= sample[6]:
                    mi += 1
                move = moves[mi]
                age = sample[6]-move[12][0]
                requested_speed, actual = magnitude(move[12][2]), magnitude(sample[12][1])
                if mode == 'TERMINAL_VECTOR' and 0 <= age <= .1 and requested_speed >= 5 and actual < requested_speed*.5:
                    slow_motion.append({'tick': sample[6], 'requested_mps': requested_speed, 'actual_mps': actual})
            for kind, field in [('RADIO', 0), ('GEOMETRY', 0), ('FUSE', 1), ('GUIDANCE_WORK', 0), ('LOOP', 1)]:
                work[kind + '_ms'].extend(r[12][field] for r in sr if r[5] == kind)
            loops = [r for r in sr if r[5] == 'LOOP']
            wakes.extend(b[12][0]-a[6] for a, b in zip(loops, loops[1:]))
            late.extend(max(b[12][0]-a[6]-a[12][6], 0) for a, b in zip(loops, loops[1:]))
        commits = [r for r in rr if r[5] == 'COMMIT']
        drones[drone_id] = {
            'derived_motion': motion_audit(rr, version),
            'identities': identities, 'application_intervals_ms': phases,
            'vector_routine_entry_intervals_ms': entries,
            'live_sample_count': len(observations), 'post_outcome_sample_count': len(excluded),
            'sample_intervals_ms': stats(sample_gaps,1000),
            'live_displacement_m': stats(displacements),
            'fps': {'p50': percentile([r[12][2] for r in observations], .5), 'p05': percentile([r[12][2] for r in observations], .05)},
            'speed_mps': stats([magnitude(r[12][1]) for r in observations]),
            'terminal_below_1mps_samples': sum(x < 1 for x in ts), 'terminal_position_stall_samples': stalls,
            'largest_terminal_speed_drop_mps': max(losses,default=None), 'low_motion_after_write': slow_motion,
            'phase_wall_time': {k: stats(v, 1000) for k,v in work.items()},
            'observed_wait_ms': stats(wakes,1000), 'wait_lateness_ms': stats(late,1000),
            'commits': [{'tick': r[6], 'outcome': r[12]} for r in commits],
            'commit_rejections': dict(Counter(r[12][1] for r in commits if r[12][0] == 'REJECTED')),
            'broker_rejections': dict(Counter(r[12][1] for r in rr if r[5] == 'BROKER')),
            'outcomes': [{'tick': r[6], 'event': r[5], 'data': r[12]} for r in rr if r[5] in ('COMMIT','KILLED','DELETED')],
            'strike_events': [{'tick': r[6], 'data': r[12]} for r in rr if r[5] == 'STRIKE'],
            'contacts': [{'tick': r[6], 'data': r[12]} for r in rr if r[5] == 'CONTACT'],
            'changes_mode_link_target_owner_generation': [{'tick': b[6], 'from': [a[11], a[12][8], a[12][7], a[12][6], a[10]],
                'to': [b[11], b[12][8], b[12][7], b[12][6], b[10]]} for a,b in zip(observations,observations[1:])
                if (a[11],a[12][8],a[12][7],a[12][6],a[10]) != (b[11],b[12][8],b[12][7],b[12][6],b[10])],
        }
        if any(r[5] == 'POSE' for r in rr):
            drones[drone_id]['pose_writes'] = pose_audit(rr)
    return {'run_id': rows[0][1], 'process': int(rows[0][2]), 'capture': rows[0][3], 'schema': version,
            'warnings': sorted(set(warnings)), 'limitations': limitations,
            'integrity': 'incomplete_corrupt_or_overflow' if warnings else ('complete_requested_duration' if full else 'complete_early_end'),
            'requested_seconds': requested, 'elapsed_seconds': elapsed,
            'stop_reason': ends[0][12][5] if version == 2 and ends and len(ends[0][12]) == 6 else None,
            'clock_bases': bases, 'records': len(rows), 'sequence_loss': missing, 'dropped': dropped,
            'export_done': done, 'end_sample_gap_and_misses': ends[0][12][2:4] if ends else None,
            'max_sampled_concurrency': max(map(len,frames.values()),default=0),
            'terminal_mode_overlap': overlap(modes), 'terminal_guidance_overlap': overlap(guidance),
            'start': start[12] if starts else None, 'parameters': [r[12] for r in nr if r[5] == 'PARAMETERS'],
            'markers': [{'tick': r[6], 'server_time': r[7], 'text': r[12]} for r in nr if r[5] == 'MARK'], 'drones': drones}


def session_key(values):
    if len(values) == 3 and isinstance(values[0], str) and integer(values[1]) and isinstance(values[2], str):
        return values[0], int(values[1]), values[2]
    return None


def collect(paths):
    sessions, footers, issues = defaultdict(list), defaultdict(list), defaultdict(list)
    failures, files, seen, fragments = [], [], {}, {}

    def admit(row):
        validate_row(row)
        key = (row[1], int(row[2]), row[3])
        identity = key + (int(row[4]),)
        variants = seen.setdefault(identity, [])
        if row not in variants:
            variants.append(row)
            sessions[key].append(row)  # retain conflicting raw variants, but never count them twice
        return key

    for path in paths:
        try:
            raw = path.read_bytes()
        except OSError as exc:
            failures.append(f'{path}: cannot read evidence: {exc}')
            continue
        files.append({'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})
        last, last_rows = {}, {}
        for line_number, line in enumerate(raw.decode('utf-8-sig',errors='replace').splitlines(),1):
            tag = next((t for t in ('A3UE_FPV_QA|','A3UE_FPV_QA_EXPORT_DONE','A3UE_FPV_QA_PART') if t in line), None)
            if tag is None:
                continue
            key = None
            try:
                wrapper = line.find('["' + tag + '"')
                value = sqf_array(line[wrapper:] if wrapper >= 0 else line.split(tag,1)[1])
                if tag == 'A3UE_FPV_QA|':
                    row = value[1] if wrapper >= 0 else value
                    if len(row) >= 4:
                        key = session_key(row[1:4])
                    key = admit(row)
                    last[key[:2]] = key
                    last_rows[key] = row
                elif tag == 'A3UE_FPV_QA_EXPORT_DONE':
                    if len(value) == 8 and value[1] == 2:
                        key = session_key(value[2:5])
                    elif len(value) == 4 and isinstance(value[1], str) and integer(value[2]):
                        key = last.get((value[1], int(value[2])))
                    if key is None:
                        raise ValueError('orphan/invalid EXPORT_DONE identity')
                    footers[key].append(value)
                    if key not in last_rows or last_rows[key][5] != 'END':
                        issues[key].append('EXPORT_DONE without preceding END in this copy')
                else:
                    if len(value) != 9 or value[1] != 2 or session_key(value[2:5]) is None or not all(integer(value[i], 1 if i in (5,7) else 0) for i in (3,5,6,7)) or not isinstance(value[8],str) or value[6] >= value[7]:
                        raise ValueError('invalid export fragment')
                    key = (value[2], int(value[3]), value[4])
                    identity = key + (int(value[5]),)
                    part = fragments.setdefault(identity, {'count': int(value[7]), 'parts': {}})
                    if part['count'] != value[7] or (value[6] in part['parts'] and part['parts'][value[6]] != value[8]):
                        raise ValueError('conflicting export fragment')
                    part['parts'][int(value[6])] = value[8]
                    if len(part['parts']) == part['count']:
                        row = sqf_array(''.join(part['parts'][i] for i in range(part['count'])))
                        if (row[1], int(row[2]), row[3], int(row[4])) != identity:
                            raise ValueError('fragment/record identity mismatch')
                        key = admit(row)
                        last_rows[key] = row
            except (ValueError, TypeError, IndexError, OverflowError) as exc:
                message = f'{path}:{line_number}: {exc}'
                failures.append(message)
                if key is not None:
                    issues[key].append(message)
    for identity, part in fragments.items():
        if len(part['parts']) != part['count']:
            issues[identity[:3]].append('truncated export fragments at sequence ' + str(identity[3]))
    for key in set(footers) | set(issues):
        if key not in sessions:
            failures.append(f'orphan completion/fragments/session errors: {key}')
    results = []
    for key, rows in sorted(sessions.items()):
        try:
            results.append(summarize(rows, footers[key], issues[key]))
        except (TypeError, ValueError, IndexError) as exc:
            failures.append(f'session {key}: malformed event payload: {exc}')
    if not sessions:
        failures.append('no telemetry records; instrumentation-off runs require manual FPS/video evidence')
    return {'parser_schema': 2, 'files': files, 'errors': failures, 'sessions': results}, sessions


def markdown(summary):
    out = ['# UA dive capture summary', '',
           'Command cadence, raw routine-entry dt, sampled motion and visual observations are distinct. Wall time includes scheduling. Overlap uses observed mode envelopes and first-to-last command spans, without extrapolation. Timing alone does not qualify smoothness or performance.', '']
    out += [f"- ERROR: {x}" for x in summary['errors']]
    for s in summary['sessions']:
        out += ['', f"## {s['run_id']} / process {s['process']} / capture {s['capture']}", '',
                f"Integrity: **{s['integrity']}**; elapsed/requested: {s['elapsed_seconds']}/{s['requested_seconds']} s; schema v{s['schema']}.",
                f"Records: {s['records']}; sequence loss: {s['sequence_loss']}; dropped: {s['dropped']}; sampled UAV count: {s['max_sampled_concurrency']}.",
                f"Terminal mode overlap: {s['terminal_mode_overlap']['max_concurrency']} max, {s['terminal_mode_overlap']['seconds_at_least_2']:.6f} s at least two.",
                f"Recorded terminal guidance overlap: {s['terminal_guidance_overlap']['max_concurrency']} max, {s['terminal_guidance_overlap']['seconds_at_least_2']:.6f} s at least two."]
        out += [f'- INCOMPLETE: {x}' for x in s['warnings']]
        out += [f'- LIMITATION: {x}' for x in s['limitations']]
        for drone, data in s['drones'].items():
            out += ['', f'### {drone}', '',
                    f"Live samples: {data['live_sample_count']}; post-outcome samples excluded: {data['post_outcome_sample_count']}; terminal below 1m/s: {data['terminal_below_1mps_samples']}.", '',
                    '| Command / lifetime / episode / generation / mode | n intervals | P50 ms | P95 ms | Max ms | Precise serialization |',
                    '|---|---:|---:|---:|---:|---|']
            for phase, st in data['application_intervals_ms'].items():
                fmt = lambda x: '-' if x is None else f'{x:.3f}'
                out.append(f"| {phase} | {st['n']} | {fmt(st['p50'])} | {fmt(st['p95'])} | {fmt(st['max'])} | {st['serialization_precise']} |")
            out += ['', f"Routine-entry dt: {data['vector_routine_entry_intervals_ms']}",
                    f"Displacement: {data['live_displacement_m']}; wait lateness ms: {data['wait_lateness_ms']}",
                    f"Commit rejections: {data['commit_rejections']}; outcomes: {data['outcomes']}"]
            if 'pose_writes' in data:
                p = data['pose_writes']
                out += ['', f"Actual POSE writes: {p['count']}; ambiguous setter frame spans: {p['ambiguous_count']}. Brackets and context-fenced pairs are in JSON; diag intervals do not measure the simulation-time gate."]
            audit = data['derived_motion']
            out += ['', f"Derived motion windows: {audit['status_counts']}. Full coverage, unknowns, identities and consecutive ms/frame pairs are in JSON.", '',
                    '| Status | Lifetime/episode/gen/mode | Window s | Samples | Step / expected m | Ratio | Unknowns |',
                    '|---|---|---|---:|---|---:|---|']
            for w in audit['windows']:
                if w['status'] == 'NO_SUSTAINED_STALL':
                    continue
                ratio = '-' if w['observed_to_expected_ratio'] is None else f"{w['observed_to_expected_ratio']:.4f}"
                out.append(f"| {w['status']} | {w['lifetime']}/{w['episode']}/{w['generation']}/{w['mode']} | {w['begin']:.6f}ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“{w['end']:.6f} | {w['sample_count']} | {w['observed_step_distance_m']:.4f} / {w['sampled_velocity_expected_travel_m']:.4f} | {ratio} | {', '.join(w['unknowns'])} |")
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='+', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    paths = sorted({p.resolve() for item in args.inputs for p in (item.rglob('*.rpt') if item.is_dir() else [item])})
    result, sessions = collect(paths)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.with_suffix('.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    args.out.with_suffix('.md').write_text(markdown(result), encoding='utf-8')
    with args.out.with_suffix('.records.jsonl').open('w', encoding='utf-8') as stream:
        for _, rows in sorted(sessions.items()):
            for row in sorted(rows, key=lambda r: r[4]):
                stream.write(json.dumps(row) + '\n')
    print(f"{len(result['sessions'])} captures; {len(result['errors'])} parse errors; output {args.out}.json/.md/.records.jsonl")
    return 2 if result['errors'] or any(s['warnings'] for s in result['sessions']) else 0


if __name__ == '__main__':
    raise SystemExit(main())
