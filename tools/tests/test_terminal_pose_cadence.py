"""D1 application-logic regressions; these do not execute Arma physics."""
from pathlib import Path
import math
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT / 'addons/drones/functions/fpv'
SOURCE = (FPV / 'fn_fpv_runTerminalVector.sqf').read_text()


def source_gate(ready, now, frame, last_time=-1, last_frame=-1):
    # Exercise the shipped SQF Boolean gate, including both authored thresholds.
    expression = re.search(r'private _poseDue = (.*?);', SOURCE, re.S)[1]
    for a, b in {'(_poseContext # 4)': 'last_time', '(_poseContext # 5)': 'last_frame',
                 '_poseReady': 'ready', '_poseFrame': 'frame', '_poseNow': 'now',
                 '&&': ' and ', '||': ' or ', '{': '(', '}': ')'}.items():
        expression = expression.replace(a, b)
    return eval(expression, {'__builtins__': {}}, dict(ready=ready, now=now, frame=frame,
                                                   last_time=last_time, last_frame=last_frame))


class EpochHarness:
    """Reset/admission specification, paired with source integration contracts below."""
    def __init__(self):
        self.context = None
        self.serial = self.velocity = self.guidance = self.fuse = 0

    def update(self, now, frame, identity=(10,2,1,1), target='t', entry=1, admitted=True):
        if not admitted or len(identity) != 4 or any(isinstance(v,bool) or not isinstance(v,(int,float))
                or not math.isfinite(v) or v < 0 or int(v) != v for v in identity):
            return False
        key = (identity,target,entry)
        rollback = self.context and (now < self.context['seen_time'] or frame < self.context['seen_frame'])
        if rollback:
            self.context = None
        elif self.context is None or self.context['key'] != key:
            self.serial += 1
            self.context = dict(key=key,last_time=-1,last_frame=-1,seen_time=now,seen_frame=frame)
        pose = not rollback and source_gate(True,now,frame,self.context['last_time'],self.context['last_frame'])
        if self.context:
            self.context.update(seen_time=now,seen_frame=frame)
            if pose:
                self.context.update(last_time=now,last_frame=frame)
        self.velocity += 1
        self.guidance += 1
        self.fuse += 1
        return pose


class TerminalPoseTests(unittest.TestCase):
    def test_frame_and_simulation_time_gates_are_both_required(self):
        for frame, now, due in [(2,.1,False),(3,.049,False),(3,.05,True),(100,.001,False),(0,1,False)]:
            self.assertEqual(source_gate(True,now,frame,0,0),due)
        self.assertTrue(source_gate(True,0,0))
        self.assertFalse(source_gate(False,100,100))

    def test_30_45_60_90_160_and_360_fps_scheduled_updates(self):
        for fps in (30,45,60,90,160,360):
            h=EpochHarness(); writes=[]; updates=0
            # First available frame after the unchanged 20 ms controller sleep floor.
            stride=math.ceil(.02*fps)
            for frame in range(0,60*fps,stride):
                now=frame/fps; updates+=1
                if h.update(now,frame): writes.append((now,frame))
            with self.subTest(fps=fps):
                self.assertGreater(len(writes),1)
                self.assertLess(len(writes),updates)
                self.assertTrue(all(b[1]-a[1]>=3 and b[0]-a[0]>=.05 for a,b in zip(writes,writes[1:])))
                self.assertLessEqual(len(writes),1201)
                self.assertEqual((h.velocity,h.guidance,h.fuse),(updates,)*3)

    def test_first_entry_skips_and_no_catchup_burst(self):
        h=EpochHarness(); self.assertTrue(h.update(0,0))
        self.assertFalse(h.update(.022,1)); self.assertFalse(h.update(.044,2))
        self.assertTrue(h.update(10,500))
        self.assertFalse(h.update(10,500)); self.assertFalse(h.update(10.001,501))
        self.assertEqual((h.velocity,h.guidance,h.fuse),(6,6,6))

    def test_owner_generation_episode_lifetime_target_and_same_frame_pass_resets(self):
        cases=[dict(identity=x) for x in ((11,2,1,1),(10,3,1,1),(10,2,2,1),(10,2,1,2))]
        cases += [dict(target='replacement'),dict(entry=2)]
        for change in cases:
            h=EpochHarness(); self.assertTrue(h.update(1,100))
            self.assertTrue(h.update(1,100,**change),change)
            self.assertEqual(h.serial,2)
            self.assertFalse(h.update(1,100,**change))

    def test_time_and_frame_rollback_skip_pose_keep_velocity_then_fresh_epoch(self):
        for now,frame in ((.9,101),(1.01,99)):
            h=EpochHarness(); h.update(1,100)
            self.assertFalse(h.update(now,frame))
            self.assertIsNone(h.context)
            self.assertEqual((h.velocity,h.guidance,h.fuse),(2,2,2))
            self.assertTrue(h.update(now,frame)); self.assertEqual(h.serial,2)

    def test_missing_invalid_or_revoked_identity_never_reinitializes(self):
        for identity in ((),(1,2,3),(1,2,3,-1),(1,2,3,float('nan')),(1,2,3,True)):
            h=EpochHarness()
            self.assertFalse(any(h.update(i,i,identity=identity) for i in range(10)))
            self.assertEqual(h.serial,0)
        h=EpochHarness(); self.assertFalse(h.update(1,100,admitted=False)); self.assertEqual(h.serial,0)

    def test_runtime_keeps_positive_dt_velocity_guidance_fuse_and_logical_basis(self):
        block=SOURCE.split('if (_poseDue) then {',1)[1].split('\n};',1)
        self.assertEqual(block[0].count('setVectorDirAndUp'),1)
        self.assertNotIn('setVelocity',block[0])
        self.assertIn('_uav setVelocity _desiredVelocity;',block[1])
        self.assertIn('["A3UE_FPV_terminalVectorLastUpdateAt", _vectorUpdateAt]',SOURCE)
        self.assertIn('private _normalizedCurrentDir = _state # 3;',SOURCE)
        self.assertIn('_state # 4',(FPV/'fn_fpv_trajectorySteering.sqf').read_text())
        self.assertNotIn('vectorUp _uav',SOURCE)
        controller=(FPV/'fn_fpv_runController.sqf').read_text()
        after=controller.split('call A3UE_fnc_fpv_runTerminalVector',1)[1]
        self.assertIn('[_target,_guidanceRevision] call _evaluateFuse',after)
        self.assertIn('_generation, _controllerIdentity] call A3UE_fnc_fpv_runTerminalVector',controller)

    def test_actual_setter_clocks_and_buffered_evidence_only(self):
        block=SOURCE.split('if (_poseDue) then {',1)[1].split('\n};',1)[0]
        order=['_poseDiagBefore =','_poseFrameBefore =','setVectorDirAndUp','_poseFrameAfter =','_poseDiagAfter =','_poseTimeAfter =','_poseContext set [4, _poseTimeAfter]','_poseContext set [5, _poseFrameAfter]']
        indices=[block.index(s) for s in order]; self.assertEqual(indices,sorted(indices))
        self.assertIn('if (_qaMove) then {_poseEvidence = [1,',block)
        self.assertNotIn('diag_log',SOURCE); self.assertNotIn('copyToClipboard',SOURCE)
        for line in SOURCE.splitlines():
            if 'setVariable ["A3UE_FPV_terminalPose' in line:
                self.assertNotIn(', true]',line)
        self.assertIn('if (count _this < 5) then',SOURCE)  # supplied invalid identity cannot silently rebind
        self.assertGreaterEqual(SOURCE.count('call A3UE_fnc_fpv_hasCurrentLifecycle'),2)

    def test_reset_integration_and_no_new_worker(self):
        for name,minimum in [('runController',1),('bootstrapLocal',2),('deleteLocal',1)]:
            s=(FPV/f'fn_fpv_{name}.sqf').read_text()
            self.assertGreaterEqual(s.count('["A3UE_FPV_terminalPoseContext", []]'),minimum,name)
        controller=(FPV/'fn_fpv_runController.sqf').read_text()
        self.assertEqual(controller.count('call _clearTerminalPoseContext;'),4)
        self.assertIn('isEqualTo _controllerIdentity}) then',controller)
        # A transient suspension seen inside the vector call also invalidates history immediately.
        suspension=SOURCE.split('if ([_uav] call A3UE_fnc_fpv_isExternallyControlled',1)[1].split('private _impactPointAsl',1)[0]
        self.assertIn('call _clearSteeringSnapshot;',suspension)
        self.assertIn('setVariable ["A3UE_FPV_terminalPoseContext", []]',SOURCE)
        self.assertNotRegex(SOURCE,r'\b(spawn|sleep|EachFrame|remoteExec|setPos|enableSimulation)\b')

    def test_capture_budget_under_existing_cap(self):
        # Provisional steady-pass ceiling, not an admission guarantee for unlimited reentries.
        self.assertLess(47343+3*(math.ceil(60/.05)+1)+3*(math.ceil(60/.1)+1),60000)
        cap=(ROOT/'tools/tests/ua_dive/capture.sqf').read_text()
        self.assertIn('["limit", 60000]',cap)
        self.assertIn('case "POSE": {[[1,0,false],[2,0,false]]}',cap)
        self.assertIn('["@frame", (_data # _x) - (_bases # 3)]',cap)


if __name__ == '__main__':
    unittest.main()
