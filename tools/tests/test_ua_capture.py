"""Producer-shaped wire regressions. Compilation is separate from Arma execution."""
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PATH = Path(__file__).parent / 'ua_dive/parse_capture.py'
spec = importlib.util.spec_from_file_location('ua_capture', PATH)
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)
BASES = [15000.125, 23000.25, 8000.5, 1000001]


def wire(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (float, int)):
        return f'{value:.6f}'
    if isinstance(value, str):
        return '"' + value.replace('"', '""') + '"'
    return '[' + ','.join(map(wire, value)) + ']'


class Fixture:
    def __init__(self, version=2, nonce='c1', process=2):
        self.version, self.nonce, self.process, self.rows = version, nonce, process, []
        data = [f'ua-dive-v{version}', True, True, ['Arma 3','Arma3',222,154089],
                'vt7', 'FPV_Baseline', 5, .02, .5, 60000, False, 0]
        if version == 2:
            data.append([f'{x:.6f}' if i < 3 else str(x) for i,x in enumerate(BASES)])
        self.add('START', 0, data=data, gen=-1)

    def add(self, kind, tick, drone='', mode='', data=None, gen=1, frame=None):
        data = json.loads(json.dumps(data or []))
        if self.version == 2:
            for field, domain, deadline in capture.clock_fields(kind,data):
                v = data[field]
                if not deadline or v > 0:
                    base = BASES[{'@diag': 0, '@mission': 2, '@frame': 3}[domain]]
                    data[field] = [domain, v-base]
        r = [self.version,'run1',self.process,self.nonce,len(self.rows)+1,kind,
             tick if self.version == 2 else BASES[0]+tick,
             tick if self.version == 2 else BASES[1]+tick,
             (frame if frame is not None else (self.rows[-1][8] - (0 if self.version == 2 else BASES[3]) + 1 if self.rows else 0)) + (0 if self.version == 2 else BASES[3]),
             drone,gen,mode,data]
        self.rows.append(r)
        return r

    def identity(self, drone='u', tick=0, life=10, episode=1, gen=1):
        return self.add('IDENTITY', tick, drone, data=['class',life,episode,'fpv_ua','AT','ammo','','event'],gen=gen)

    def move(self, tick, drone='u', gen=1, dt=.02):
        return self.add('MOVE',tick,drone,'TERMINAL_VECTOR',
                        [BASES[0]+tick-.001, BASES[0]+tick-.002, [10,0,-5], [10,0,-5], .02, dt, 80, 100],gen=gen)

    def sample(self, tick, drone='u', mode='TERMINAL_VECTOR', pos=None, velocity=None, frame=None, gen=1):
        return self.add('SAMPLE',tick,drone,mode,
                        [pos or [12000.123047,11768.712891,45.125], velocity or [10,0,-5],60,.016,.02,True,2,'target','OK',1],gen=gen,frame=frame)

    def finish(self, elapsed=5, reason='duration', dropped=0):
        # Real END retained count excludes END; footer exported count includes END.
        data = [dropped,len(self.rows),.02,0,elapsed]
        if self.version == 2:
            data.append(reason)
        if dropped and len(self.rows) != 60000:
            raise ValueError('producer drops only after its retained buffer is full')
        end = self.add('END',elapsed,data=data,gen=-1)
        end[4] += dropped
        footer = ['A3UE_FPV_QA_EXPORT_DONE',self.version,'run1',self.process,self.nonce,len(self.rows),end[4],dropped] if self.version == 2 else ['A3UE_FPV_QA_EXPORT_DONE','run1',self.process,len(self.rows)]
        return footer

    def state(self, tick, drone='u', episode=1, life=10, simulation=True, controlled=False, gen=1):
        return self.add('STATE',tick,drone,'TERMINAL_VECTOR',
            [True,0,simulation,True,life,episode,[],[],controlled,[],'','','',False,'',0,
             [0,0,0],[0,0,0],[],'CARELESS','FULL','BLUE',True,'',True,False,gen],gen=gen)

    def text(self, footer=None, fragments=False):
        lines=[]
        for r in self.rows:
            full=wire(['A3UE_FPV_QA|',r])
            if fragments and len(full)>900:
                text=wire(r); chunks=[text[i:i+256] for i in range(0,len(text),256)]
                lines.extend(wire(['A3UE_FPV_QA_PART',2,r[1],r[2],r[3],r[4],i,len(chunks),c]) for i,c in enumerate(chunks))
            else:
                lines.append(full)
        if footer:
            lines.append(wire(footer))
        return '\n'.join('12:00:00 '+s for s in lines)+'\n'


class CaptureTests(unittest.TestCase):
    def test_f1_steering_wire_empty_held_and_logical_frame(self):
        f = Fixture()
        logical = [[[10,2,1,1],'u','target','TERMINAL_VECTOR',['epoch','marker','EAST'],1,
                    ['GROUND','target','vehicle'],'',''], [1,0,0], [0,0,1], 10, [0,0,1],
                   2, 'INIT', .02, [0,1,0], [10,0,-5], .01, .01]
        for tick, state, held in [(0, [], True), (.1, logical, False)]:
            f.add('STEERING', tick, 'u', 'TERMINAL_VECTOR',
                  [1, state, BASES[2]+tick, BASES[0]+tick, [0,0,10], [10,0,-5],
                   [1,0,0], [0,0,1], True, held, [10,2,1,1], 'target'])
        footer = f.finish()
        result, raw = self.parse([f.text(footer, fragments=True)])
        self.assertEqual(result['errors'], [])
        # This optional event does not change historical motion/outcome scoring.
        self.assertIn('STEERING', capture.MIN_FIELDS)
        self.assertEqual(capture.clock_fields('STEERING', []), [(2,'@mission',False),(3,'@diag',False)])

    def test_f1_steering_rejects_bad_state_and_keeps_legacy_schema(self):
        row = Fixture().add('STEERING', 0, 'u', data=[1, [], 0, 0, [0,0,0], [0,0,0],
            [1,0,0], [0,0,1], True, False, [], ''])
        capture.validate_row(row)
        for field, bad in [(0,2), (1,[False]), (4,[1,2]), (8,1), (11,False)]:
            changed = json.loads(json.dumps(row)); changed[12][field] = bad
            with self.assertRaises(ValueError): capture.validate_row(changed)
        row[0] = 1
        with self.assertRaises(ValueError): capture.validate_row(row)

    def parse(self, texts):
        with tempfile.TemporaryDirectory() as temp:
            paths=[]
            for i,text in enumerate(texts):
                p=Path(temp)/f'{i}.rpt'; p.write_text(text,encoding='utf-8'); paths.append(p)
            return capture.collect(paths)

    def test_sqf_string_bool_and_reject_code_truncation(self):
        self.assertEqual(capture.sqf_array('[1,"quote ""yes"" C:\\mods",true,[],[-1.2e-3]]'),
                         [1.0,'quote "yes" C:\\mods',True,[],[-.0012]])
        for source in ('[call foo]','[1','[1] trailing','[1,,2]'):
            with self.subTest(source=source), self.assertRaises(ValueError): capture.sqf_array(source)

    def test_pose_brackets_precision_attribution_and_context(self):
        f=Fixture(); f.identity()
        for tick, before, after, serial in [(1,100,100,1),(1.067,103,104,1),(1.068,105,105,2)]:
            f.add('POSE',tick,'u','TERMINAL_VECTOR',
                  [1,BASES[0]+tick-.000122,BASES[0]+tick-.000061,
                   BASES[3]+before,BASES[3]+after,1,1,serial],frame=after)
            f.move(tick+.0001)
        result,raw=self.parse([f.text(f.finish(),fragments=True)])
        s=result['sessions'][0]; self.assertEqual(s['warnings'],[])
        audit=s['drones']['u']['pose_writes']
        self.assertEqual((audit['count'],audit['ambiguous_count']),(3,1))
        self.assertEqual(audit['writes'][0]['frame_before'],100)
        self.assertEqual(audit['writes'][1]['attribution'],'ambiguous_frame_span')
        self.assertEqual(len(audit['pairs']),1)  # no interval across entry epochs
        self.assertEqual(audit['pairs'][0]['frames_after_to_before'],3)
        self.assertAlmostEqual(audit['writes'][0]['diag_after']-audit['writes'][0]['diag_before'],.000061,places=6)
        pose=next(r for r in next(iter(raw.values())) if r[5]=='POSE')
        self.assertEqual(pose[12][3],['@frame',100])
        self.assertEqual(pose[12][1][0],'@diag')

    def test_pose_rejects_wrong_version_tags_types_and_reversed_brackets(self):
        for failure in ('version','extra','gen','episode','serial','frame_tag','diag_tag','fractional_frame','reverse_time','reverse_frame','nonfinite'):
            f=Fixture(); f.identity()
            r=f.add('POSE',1,'u','TERMINAL_VECTOR',
                    [1,BASES[0]+.999,BASES[0]+1,BASES[3]+99,BASES[3]+100,1,1,1],frame=100)
            d=r[12]
            if failure=='version': d[0]=2
            if failure=='extra': d.append(0)
            if failure=='gen': d[5]=2
            if failure=='episode': d[6]=True
            if failure=='serial': d[7]=0
            if failure=='frame_tag': d[3][0]='@diag'
            if failure=='diag_tag': d[1][0]='@frame'
            if failure=='fractional_frame': d[3][1]=99.5
            if failure=='reverse_time': d[2][1]=.5
            if failure=='reverse_frame': d[4][1]=98
            if failure=='nonfinite': d[1][1]=float('inf')
            result,_=self.parse([f.text(f.finish())])
            self.assertTrue(result['errors'] or result['sessions'][0]['warnings'],failure)

    def test_pose_fragment_reassembly_and_physical_line_budget(self):
        f=Fixture(nonce='n'*128); f.identity()
        pose=f.add('POSE',1,'u','TERMINAL_VECTOR',
                   [1,BASES[0]+.999,BASES[0]+1,BASES[3]+99,BASES[3]+100,1,1,1],frame=100)
        self.assertLessEqual(len(wire(['A3UE_FPV_QA|',pose])),900)
        footer=f.finish(); text=f.text(footer)
        original='12:00:00 '+wire(['A3UE_FPV_QA|',pose])
        logical=wire(pose); chunks=[logical[i:i+256] for i in range(0,len(logical),256)]
        parts=[wire(['A3UE_FPV_QA_PART',2,pose[1],pose[2],pose[3],pose[4],i,len(chunks),chunk]) for i,chunk in enumerate(chunks)]
        self.assertTrue(all(len(part)<1000 for part in parts))
        result,raw=self.parse([text.replace(original,'\n'.join(parts))])
        self.assertEqual(result['sessions'][0]['warnings'],[])
        self.assertIn(capture.sqf_array(wire(pose)),next(iter(raw.values())))

    def test_pose_does_not_change_existing_metrics(self):
        f=Fixture(); f.identity(); f.move(1); f.sample(1.001,frame=100); f.move(1.067); f.sample(1.068,frame=103)
        base=capture.summarize(f.rows,[f.finish()])
        # Insert a callback row inside existing bounds. Only wire counts/sequences and additive audit differ.
        g=Fixture(); g.identity(); g.move(1); g.sample(1.001,frame=100)
        g.add('POSE',1.002,'u','TERMINAL_VECTOR',[1,BASES[0]+.999,BASES[0]+1,BASES[3]+100,BASES[3]+100,1,1,1],frame=100)
        g.move(1.067); g.sample(1.068,frame=103)
        candidate=capture.summarize(g.rows,[g.finish()])
        for key in ('application_intervals_ms','vector_routine_entry_intervals_ms','live_displacement_m','speed_mps','terminal_position_stall_samples'):
            self.assertEqual(base['drones']['u'][key],candidate['drones']['u'][key],key)

    def test_large_clocks_frames_and_embedded_commands(self):
        f=Fixture(); f.identity(); f.move(1); f.sample(1.001,frame=101)
        f.move(1.022); f.sample(1.023,frame=102)
        result,raw=self.parse([f.text(f.finish())]); s=result['sessions'][0]
        self.assertEqual(s['warnings'],[])
        self.assertEqual(s['clock_bases']['frame'],1000001)
        self.assertEqual(s['integrity'],'complete_requested_duration')
        st=next(iter(s['drones']['u']['application_intervals_ms'].values()))
        self.assertAlmostEqual(st['max'],22,places=5)
        records=next(iter(raw.values())); self.assertEqual(records[3][8],101)
        self.assertEqual(records[2][12][0][0],'@diag')
        self.assertEqual(records[2][12][4],.02)
        self.assertTrue(st['serialization_precise'])

    def test_all_clock_domains_and_sentinels(self):
        f=Fixture(); f.identity()
        f.add('AI_INTENT',1,'u','TERMINAL_ATTACK',[BASES[0]+.999,30,20,[1,2,3]])
        f.add('DO_MOVE',1.02,'u','TERMINAL_ATTACK',[BASES[0]+1.019,[12000.123047,11768.712891,2]])
        f.add('LOOP',1.03,'u','TERMINAL_ATTACK',[BASES[0]+1,.03,BASES[2]+1.03,BASES[2]+1.04,0,-1,.02,BASES[0]+1.5,False,True])
        f.add('STRIKE',1.04,'u',data=['PROPOSED','reason','NONE',BASES[0]+1.5])
        f.add('STRIKE',1.05,'u',data=['THROTTLED',BASES[0]+1.5])
        f.add('FUSE',1.06,'u',data=[False,.003,0,'NONE','NONE'])
        state=[True,0,True,True,10,1,[],[],False,[],'','','',False,'',BASES[0]+1.5,[1,2,3],[0,0,0],[], 'AWARE','NORMAL','YELLOW',True,'',True,False,1]
        f.add('STATE',1.1,'u',data=state)
        n=capture.normalized(f.rows,f.rows[0]); loop=n[4][12]
        self.assertAlmostEqual(loop[0],1); self.assertAlmostEqual(loop[2],1.03)
        self.assertEqual(loop[4:7],[0,-1,.02]); self.assertAlmostEqual(loop[7],1.5)
        self.assertEqual(n[7][12][1:3],[.003,0]); self.assertAlmostEqual(n[8][12][15],1.5)
        self.assertEqual(n[3][12][1],[12000.123047,11768.712891,2])
        footer=f.finish(); result,_=self.parse([f.text(footer)]); self.assertFalse(result['sessions'][0]['warnings'])
        f.rows[4][12][2][0]='@diag'
        result,_=self.parse([f.text(footer)]); self.assertTrue(any('clock tag' in w for w in result['sessions'][0]['warnings']))

    def test_position_displacement_precision_and_dt_is_not_command_clock(self):
        f=Fixture(); f.identity(); f.move(1,dt=.0215); f.sample(1.001,pos=[12000.123047,0,45])
        f.move(1.231,dt=.0215); f.sample(1.251,pos=[12000.148438,0,45])
        result,_=self.parse([f.text(f.finish())]); d=result['sessions'][0]['drones']['u']
        self.assertAlmostEqual(d['live_displacement_m']['max'],.025391,places=6)
        self.assertAlmostEqual(next(iter(d['application_intervals_ms'].values()))['max'],231)
        self.assertAlmostEqual(next(iter(d['vector_routine_entry_intervals_ms'].values()))['max'],21.5)
        self.assertEqual(d['terminal_position_stall_samples'],0)

    def test_v1_v2_mixed_and_legacy_precision_limit(self):
        f=Fixture(1); f.identity(); f.move(1); f.move(1.02); footer=f.finish()
        # Emulate v1 six-significant-digit serialization, without changing historical files.
        old=f.text(footer).replace('15001.019000','15001.0').replace('15000.999000','15001.0')
        g=Fixture(2,nonce='v2'); g.identity()
        result,_=self.parse([old+g.text(g.finish())])
        self.assertEqual(len(result['sessions']),2)
        self.assertTrue(all(not s['warnings'] for s in result['sessions']))
        legacy=next(s for s in result['sessions'] if s['schema']==1)
        self.assertTrue(legacy['limitations'])
        self.assertFalse(next(iter(legacy['drones']['u']['application_intervals_ms'].values()))['serialization_precise'])

    def test_missing_end_footer_and_uninterrupted_prefix(self):
        for missing in ('END','footer','both'):
            f=Fixture(); f.identity(); footer=f.finish()
            if missing in ('END','both'): f.rows.pop()
            result,_=self.parse([f.text(None if missing in ('footer','both') else footer)])
            self.assertEqual(result['sessions'][0]['integrity'],'incomplete_corrupt_or_overflow')

    def test_counts_overflow_sequence_and_conflicting_completion(self):
        for failure in ('retained','exported','sequence','schema','completion'):
            f=Fixture(); f.identity(); footer=f.finish()
            if failure=='retained': f.rows[-1][12][1]+=1
            if failure=='exported': footer[5]+=1
            if failure=='sequence': f.rows[1][4]=9
            if failure=='schema': f.rows[0][12][0]='ua-dive-v99'
            text=f.text(footer)
            if failure=='completion':
                other=footer.copy(); other[5]+=1; text+=wire(other)+'\n'
            result,_=self.parse([text]); self.assertTrue(result['sessions'][0]['warnings'],failure)

    def test_real_overflow_count_semantics(self):
        f=Fixture()
        for i in range(59999):
            f.add('MARK',i*.00005,data=['bounded'])
        footer=f.finish(dropped=2)
        s=capture.summarize(f.rows,[footer])
        self.assertEqual(s['records'],60001)
        self.assertEqual(s['sequence_loss'],2)
        self.assertEqual(s['dropped'],2)
        self.assertIn('buffer overflow: 2 dropped records',s['warnings'])
        self.assertFalse(any('count mismatch' in w or 'buffer bounds' in w for w in s['warnings']))

    def test_footer_order_identity_and_numeric_integrity(self):
        f=Fixture(); f.identity(); f.move(1); footer=f.finish()
        result,_=self.parse([wire(footer)+'\n'+f.text()])
        self.assertTrue(result['sessions'][0]['warnings'])
        bad=footer.copy(); bad[4]='another-capture'
        result,_=self.parse([f.text(bad)])
        self.assertTrue(result['errors']); self.assertTrue(result['sessions'][0]['warnings'])
        f.rows[2][12][2][0]='invalid coordinate'
        result,_=self.parse([f.text(footer)])
        self.assertTrue(result['errors']); self.assertTrue(result['sessions'][0]['warnings'])

    def test_early_stop_full_duration_and_cleanup(self):
        for elapsed,reason,status in [(2,'manual','complete_early_end'),(2,'cleanup','complete_early_end'),(5.01,'duration','complete_requested_duration'),(2,'duration','incomplete_corrupt_or_overflow')]:
            f=Fixture(); f.identity(); result,_=self.parse([f.text(f.finish(elapsed,reason))])
            self.assertEqual(result['sessions'][0]['integrity'],status)

    def test_partial_final_copies_deduplicate_but_conflicts_survive(self):
        f=Fixture(); f.identity(); partial=f.text(); footer=f.finish(); final=f.text(footer)
        result,raw=self.parse([partial,final,final]); s=result['sessions'][0]
        self.assertFalse(s['warnings']); self.assertEqual(s['records'],3)
        self.assertEqual(len(next(iter(raw.values()))),3)
        f.rows[1][12][0]='different'
        result,raw=self.parse([final,f.text(footer)])
        self.assertTrue(any('conflicting duplicate' in w for w in result['sessions'][0]['warnings']))
        self.assertEqual(len(next(iter(raw.values()))),4)

    def test_fragment_lengths_reassembly_conflict_and_truncation(self):
        f=Fixture(nonce='2026-10-13-12-59-59-999:1000001:15000.125000:10'); f.identity()
        f.add('MARK',1,data=['"'*2400]); footer=f.finish()
        for r in f.rows: r[1]='"'*128
        footer[2]='"'*128
        text=f.text(footer,fragments=True)
        self.assertTrue(all(len(line)<1000 for line in text.splitlines()))
        result,raw=self.parse([text,text]); self.assertFalse(result['sessions'][0]['warnings'])
        self.assertEqual(next(iter(raw.values()))[2][12][0],'"'*2400)
        lines=text.splitlines(); index=next(i for i,line in enumerate(lines) if 'QA_PART' in line)
        truncated='\n'.join(lines[:index]+lines[index+1:])
        result,_=self.parse([truncated]); self.assertTrue(result['sessions'][0]['warnings'])
        result,_=self.parse([truncated,text]); self.assertFalse(result['sessions'][0]['warnings'])
        bad=next(line for line in lines if 'QA_PART' in line and 'MARK' in line).replace('MARK','MORK')
        result,_=self.parse([text,bad+'\n']); self.assertTrue(result['errors'])

    def test_truncated_record_does_not_hide_valid_session(self):
        f=Fixture(); f.identity(); text=f.text(f.finish())
        g=Fixture(nonce='bad'); g.identity(); broken=g.text(g.finish()).splitlines()
        broken[1]=broken[1][:-6]
        result,_=self.parse([text+'\n'.join(broken)])
        self.assertTrue(result['errors'])
        self.assertEqual(next(s for s in result['sessions'] if s['capture']=='c1')['integrity'],'complete_requested_duration')
        self.assertEqual(next(s for s in result['sessions'] if s['capture']=='bad')['integrity'],'incomplete_corrupt_or_overflow')

    def test_success_deletion_death_and_rejection_live_window(self):
        for event,data,excluded in [('COMMIT',['COMMITTED','ammo',10,2],1),('COMMIT',['REJECTED','SNAPSHOT_VALUES',10,2],0),('DELETED',[],1),('KILLED',[],1)]:
            f=Fixture(); f.identity(); f.move(1); f.sample(1.01)
            f.add(event,1.02,'u','TERMINAL_VECTOR',data)
            f.sample(1.04,velocity=[0.0000001,0,0]); result,_=self.parse([f.text(f.finish())]); d=result['sessions'][0]['drones']['u']
            self.assertEqual(d['post_outcome_sample_count'],excluded)
            self.assertEqual(d['terminal_below_1mps_samples'],1-excluded)
            self.assertEqual(d['terminal_position_stall_samples'],1-excluded)
            self.assertEqual(d['sample_intervals_ms']['n'],1-excluded)

    def test_sequential_vs_genuine_terminal_guidance_overlap(self):
        for concurrent in (False,True):
            f=Fixture(); f.identity('a'); f.identity('b')
            f.move(1,'a'); f.move(1.2,'a')
            f.add('MODE',1.3,'a','RECOVERING',['TERMINAL_VECTOR','RECOVERING',False,'OK',''])
            tick=1.1 if concurrent else 2
            f.move(tick,'b'); f.move(tick+.3,'b')
            # Arrange wire sequence in actual time order.
            f.rows.sort(key=lambda r:r[6])
            for i,r in enumerate(f.rows,1): r[4]=i
            f.sample(3,'a',mode='RECOVERING',frame=200); f.sample(3,'b',mode='RECOVERING',frame=200)
            result,_=self.parse([f.text(f.finish())]); s=result['sessions'][0]
            self.assertEqual(s['max_sampled_concurrency'],2)
            self.assertEqual(s['terminal_guidance_overlap']['max_concurrency'],2 if concurrent else 1)
            self.assertAlmostEqual(s['terminal_guidance_overlap']['seconds_at_least_2'],.1 if concurrent else 0)
            self.assertEqual(s['terminal_mode_overlap']['max_concurrency'],2 if concurrent else 1)

    def test_generation_lifetime_episode_and_mode_boundaries(self):
        f=Fixture(); f.identity(); f.move(1); f.move(1.02)
        f.move(2,gen=2); f.identity(tick=2.01,life=11,episode=2,gen=2); f.move(2.02,gen=2)
        result,_=self.parse([f.text(f.finish())]); d=result['sessions'][0]['drones']['u']
        self.assertEqual(len(d['application_intervals_ms']),3)
        self.assertEqual(sum(st['n'] for st in d['application_intervals_ms'].values()),1)

    def test_cli_failure_status_still_reports_good_session(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'test.rpt'; out=Path(temp)/'summary'
            f=Fixture(); f.identity(); g=Fixture(nonce='partial'); g.identity()
            p.write_text(f.text(f.finish())+g.text(),encoding='utf-8')
            result=subprocess.run([sys.executable,str(PATH),str(p),'--out',str(out)],capture_output=True)
            self.assertEqual(result.returncode,2)
            parsed=json.loads(out.with_suffix('.json').read_text())
            self.assertEqual(len(parsed['sessions']),2)
            self.assertEqual(parsed['sessions'][0]['integrity'],'complete_requested_duration')

    def test_corrupt_identity_and_fragment_metadata_are_reported_without_crash(self):
        f=Fixture(); f.identity(); footer=f.finish()
        for bad in ([2,[],2,[],1,'MARK',0,0,0,'',-1,'',['bad']],
                    ['A3UE_FPV_QA_PART',2,[],2,[],1,0,1,'broken'],
                    ['A3UE_FPV_QA_EXPORT_DONE',2,[],2,[],3,3,0]):
            line=wire(['A3UE_FPV_QA|',bad]) if bad[0]==2 else wire(bad)
            result,_=self.parse([line+'\n'+f.text(footer)])
            self.assertTrue(result['errors'])
            self.assertEqual(result['sessions'][0]['integrity'],'complete_requested_duration')

    def test_unreadable_evidence_is_reported(self):
        result,_=capture.collect([Path('missing-regression-file.rpt')])
        self.assertIn('cannot read evidence',result['errors'][0])

    def diagnostic_fixture(self, motion='stationary', version=2):
        f=Fixture(version); f.identity()
        # STATE is a slow sample, just as in the producer. No fake per-frame flags.
        for i in range(101):
            t=i*.02
            if i % 25 == 0: f.state(t)
            f.move(t)
            if motion == 'turning':
                angle=t*math.pi
                pos=[10/math.pi*math.sin(angle),10/math.pi*(1-math.cos(angle)),45]
                vel=[10*math.cos(angle),10*math.sin(angle),0]
            else:
                pos=[10*t if motion == 'smooth' else 0,0,45]; vel=[10,0,0]
            f.sample(t+.001,pos=pos,velocity=vel,frame=i*3+1)
        return f

    def audit(self, f, complete=True):
        result,_=self.parse([f.text(f.finish() if complete else None)])
        return result['sessions'][0]

    def test_stationary_high_velocity_and_exact_frame_cadence(self):
        s=self.audit(self.diagnostic_fixture()); a=s['drones']['u']['derived_motion']
        stalls=[w for w in a['windows'] if w['status']=='STALL_CANDIDATE']
        self.assertGreaterEqual(sum(w['end']-w['begin'] for w in stalls),1.9)
        w=stalls[0]; self.assertEqual(w['observed_step_distance_m'],0)
        self.assertGreater(w['sampled_velocity_expected_travel_m'],9)
        self.assertEqual((w['lifetime'],w['episode'],w['generation'],w['owner'],w['target']),(10,1,1,2,'target'))
        pairs=next(c['pairs'] for c in a['movement_write_cadence'] if c['pairs'])
        self.assertAlmostEqual(pairs[0]['milliseconds'],20)
        self.assertEqual(pairs[0]['relative_frames'],3)

    def test_smooth_and_turning_use_path_distance_not_net_distance(self):
        for motion in ('smooth','turning'):
            a=self.audit(self.diagnostic_fixture(motion))['drones']['u']['derived_motion']
            self.assertNotIn('STALL_CANDIDATE',a['status_counts'])
            windows=[w for w in a['windows'] if w['status']=='NO_SUSTAINED_STALL']
            self.assertTrue(windows)
            self.assertGreater(min(w['observed_to_expected_ratio'] for w in windows),.99)
            if motion=='turning':
                self.assertGreater(windows[0]['observed_step_distance_m'],windows[0]['net_displacement_m']*1.4)

    def test_sparse_missing_and_long_gaps_report_unknown(self):
        for sparse in (True,False):
            f=self.diagnostic_fixture()
            f.rows=[r for r in f.rows if r[5]!='SAMPLE' or (r[4]%10==0 if sparse else not .2<r[6]<.5)]
            for i,r in enumerate(f.rows,1): r[4]=i
            a=self.audit(f)['drones']['u']['derived_motion']
            self.assertTrue(any('LONG_OR_NONPOSITIVE_SAMPLE_GAP' in w['unknowns'] for w in a['windows']))
            self.assertNotEqual(a['windows'][0]['status'],'STALL_CANDIDATE')
        f=Fixture(); f.identity(); f.move(1)
        a=self.audit(f)['drones']['u']['derived_motion']
        self.assertTrue(a['uncovered_segments'])

    def test_transitions_never_bridge_motion_or_cadence(self):
        for change in ('owner','target','control','mode','generation','episode','life','contact','simulation'):
            f=self.diagnostic_fixture()
            for r in f.rows:
                if r[6] < 1: continue
                if change=='owner' and r[5]=='SAMPLE': r[12][6]=3; r[12][5]=False
                if change=='target' and r[5]=='SAMPLE': r[12][7]='newtarget'
                if change=='control' and r[5]=='STATE': r[12][8]=True
                if change=='mode': r[11]='HOLD'
                if change=='generation': r[10]=2
                if change=='episode' and r[5]=='STATE': r[12][5]=2
                if change=='life' and r[5]=='STATE': r[12][4]=11
                if change=='simulation' and r[5]=='STATE': r[12][2]=False
            if change=='contact':
                f.add('CONTACT',1,'u','TERMINAL_VECTOR',['wall',10]); f.rows.sort(key=lambda r:r[6])
                for i,r in enumerate(f.rows,1): r[4]=i
            a=self.audit(f)['drones']['u']['derived_motion']
            self.assertFalse(any(w['begin']<1<w['end'] for w in a['windows']),change)
            self.assertFalse(any(p['begin']<.999<p['end'] for c in a['movement_write_cadence'] for p in c['pairs']),change)

    def test_delivery_parking_and_post_outcome_excluded(self):
        for event in ('COMMIT','STATE'):
            f=self.diagnostic_fixture('smooth')
            f.rows=[r for r in f.rows if r[6]<1]
            if event=='COMMIT': f.add('COMMIT',1,'u','TERMINAL_VECTOR',['COMMITTED','ammo',10,2])
            else:
                row=f.state(1); row[12][13]=True
            f.sample(1.02,pos=[0,0,1045],velocity=[28,0,0])
            a=self.audit(f)['drones']['u']['derived_motion']
            self.assertTrue(a['excluded'])
            self.assertLess(max(w['observed_step_distance_m'] for w in a['windows']),11)

    def test_incomplete_export_keeps_diagnostic_and_integrity(self):
        s=self.audit(self.diagnostic_fixture(),complete=False)
        self.assertEqual(s['integrity'],'incomplete_corrupt_or_overflow')
        self.assertIn('STALL_CANDIDATE',s['drones']['u']['derived_motion']['status_counts'])

    def test_holds_near_zero_missing_state_and_legacy_are_explicit(self):
        for condition in ('hold','zero','state','legacy'):
            f=self.diagnostic_fixture(version=1 if condition=='legacy' else 2)
            for r in f.rows:
                if condition=='hold' and r[5]=='MOVE': r[12][2]=[0,0,0]
                if condition=='zero' and r[5]=='SAMPLE': r[12][1]=[0,0,0]
            if condition=='state': f.rows=[r for r in f.rows if r[5]!='STATE']
            for i,r in enumerate(f.rows,1): r[4]=i
            a=self.audit(f)['drones']['u']['derived_motion']
            self.assertNotIn('STALL_CANDIDATE',a['status_counts'])
            self.assertIn('UNKNOWN' if condition in ('state','legacy') else 'LOW_EXPECTED_TRAVEL_OR_POSSIBLE_INTENTIONAL_HOLD',a['status_counts'])

    def test_motion_fixture_subsequent_frame_and_incomplete_exports(self):
        # Fixture decoder must retain next-frame motion separately from commands.
        phase=['VELOCITY_ONLY',False,'u']; result=['motion','ACTUATION','NOT RUN',1,0,5,True,'test-prefix']
        rows=[[1,'BEGIN',0,0,[]],[2,'PHASE_BEGIN',0,0,[phase]],
              [3,'COMMAND',0,0,[phase,1,0,False,[1,0,0],[10,0,0],[10,0,0],'readback']],
              [4,'OBSERVE',.02,1,[phase,1,.02,1,[0,0,45],[10,0,0],60,.02,True,2,True,True,0]],
              [5,'OBSERVE',.04,2,[phase,1,.04,2,[0,0,45],[10,0,0],60,.02,True,2,True,True,0]],
              [6,'END',1,3,result]]
        with tempfile.TemporaryDirectory() as temp:
            for condition in ('complete','partial','same-frame'):
                local=json.loads(json.dumps(rows))
                if condition=='same-frame': local[3][4][3]=0
                lines=[wire(['A3UE_FPV_QA_MOTION_PART','motion',2,r[0],0,1,wire(r)]) for r in local]
                if condition!='partial': lines.append(wire(['A3UE_FPV_QA_MOTION_EXPORT_DONE',result,len(local)]))
                path=Path(temp)/f'{condition}.rpt'; out=Path(temp)/f'{condition}.json'
                path.write_text('\n'.join(lines))
                command=subprocess.run([sys.executable,str(PATH.with_name('parse_motion_fixture.py')),str(path),'--out',str(out)],capture_output=True)
                self.assertEqual(command.returncode,0 if condition=='complete' else 2,command.stderr)
                parsed=json.loads(out.read_text()); p=parsed['runs'][0]['phases'][0]
                self.assertEqual(p['observed_step_distance_m'],0)
                self.assertAlmostEqual(p['sampled_velocity_expected_m'],.2)
                self.assertEqual(p['coverage'],'UNKNOWN')


class F2TrajectoryCaptureTests(unittest.TestCase):
    def test_bounded_plan_and_latched_seed_round_trip(self):
        data=[1,[.1,[100,200,1.2],.5,.02,22],"FEASIBLE",
              [2,.1,.12,[-5,4,-1],[-.7715,.6172,-.1543],6.48,"INIT",0]]
        row=Fixture().add('TRAJECTORY',1,'u','TERMINAL_VECTOR',data)
        capture.validate_row(row)
        decoded=capture.parse_sqf_array(wire(row)) if hasattr(capture,'parse_sqf_array') else json.loads(json.dumps(row))
        self.assertEqual(decoded[12],data)
        held=Fixture().add('TRAJECTORY',2,'u','IDLE',[1,[-1,[],0,0,0],"NONE",data[3]])
        capture.validate_row(held)  # last seed is not a claim of active steering while controlled
        for bad in [[1,[.1,[1,2],0,0,0],"BAD",[]], [1,[-1,[],0,0,0],"NONE",[2,0,0,[1,0,0],[1,0,0],1,"INIT",.02]]]:
            with self.assertRaises(ValueError): capture.validate_row(Fixture().add('TRAJECTORY',1,data=bad))

    def test_capture_remains_deferred_and_fixed_size(self):
        source=PATH.with_name('capture.sqf').read_text()
        block=source.split('if (_trajectoryDue) then {\n            private _trajectory',1)[1].split('if (_steeringDue)',1)[0]
        self.assertNotRegex(block,r'\b(diag_log|copyToClipboard|spawn|remoteExec|nearestObjects)\b')
        self.assertIn('_now + 0.2',source)
        self.assertIn('["limit", 60000]',source)


if __name__ == '__main__':
    unittest.main()
