"""Execute shipped site queue/ingress and lifecycle receivers in SQF-VM.

Engine roles, clocks, markers and RPC delivery are explicit substitutes. The optional
atomic-context loss is fault injection, NOT evidence that Arma isNil loses context.
No physics, real HC authentication, timing or network qualification is claimed.
"""
import re
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, engine_substitutes
from test_f2cl_field_fixes import PRELUDE, run_vm


SETUP = PRELUDE + r'''
FPV_isServer=true; FPV_inside=false; FPV_dropContext=false; FPV_replies=[];
FPV_owner={_this getVariable ["owner",2]}; FPV_local={false}; FPV_netId={"uav"};
spawner="VMVehicle" createVehicle [0,0,0]; sidesX="VMVehicle" createVehicle [0,0,0];
private _hc="VMVehicle" createVehicle [0,0,0]; _hc setVariable ["owner",4];
FPV_hcs=[_hc]; hcArray=[4]; Occupants=east; Invaders=independent;
airportsX=[]; outposts=["site"]; resourcesX=[];
FPV_markers set ["site",[0,0,0]]; spawner setVariable ["site",0]; sidesX setVariable ["site",east];
A3UE_FPV_siteEpoch="E"; A3UE_FPV_siteLifecycle=createHashMap; A3UE_FPV_siteTracked=createHashMap;
A3UE_FPV_siteQueue=createHashMap; A3UE_FPV_registry=createHashMap;
A3UE_FPV_registrationComplete=true; serverInitDone=true; A3UE_FPV_siteReady=true;
A3UE_FPV_siteHCs=[4]; A3UE_FPV_siteMarkers=["site"]; A3UE_FPV_integrationHooksEnabled=false;
TEST_calls=[]; TEST_dispatch=[];
A3UE_FPV_originalScheduler={TEST_dispatch pushBack _this;7};
A3UE_fnc_fpv_resolveSiteType={"Outpost"};
A3UE_fnc_fpv_siteStock={true}; A3UE_fnc_fpv_cleanupDrone={true};
A3UE_fnc_fpv_managerEvaluateSite={
 TEST_calls pushBack _this;
 if (_this # 2) then {A3UE_FPV_registry set [_this # 0,createHashMapFromArray [["status","active"],["drones",[]]]];}
 else {A3UE_FPV_registry deleteAt (_this # 0);}; true
};
A3UE_fnc_fpv_rejectLifecycle={false};
A3UE_fnc_fpv_lifecycleAccess={!(FPV_remote && {!FPV_inside || {!FPV_dropContext}}) || {FPV_sender==2}};
private _schedule={FPV_remote=false;FPV_inside=false; [["site"],"A3A_fnc_createAIOutposts"] call A3UE_fnc_fpv_scheduleSite;};
private _queue={FPV_remote=false;FPV_inside=false; call A3UE_fnc_fpv_processSiteQueue;};
private _intent={FPV_inside=false; _this call A3UE_fnc_fpv_receiveSiteIntent;};
'''


def shipped(name):
    s = (FPV / f'fn_fpv_{name}.sqf').read_text()
    s = s.replace('toLowerANSI', 'toLower')  # fixture identifiers are ASCII
    s = re.sub(r'\bisServer\b', 'FPV_isServer', s)
    s = s.replace('entities "HeadlessClient_F"', 'FPV_hcs')
    s = re.sub(r'\bmarkerShape (_\w+)', r'(\1 call FPV_markerShape)', s)
    s = s.replace('admin _sender == 2', 'false')
    # Fault injection affects engine reads inside atomic code, not captured locals.
    s = re.sub(r'\bisRemoteExecuted\b', '(FPV_remote && {!FPV_inside || {!FPV_dropContext}})', s)
    s = re.sub(r'\bremoteExecutedOwner\b', '([FPV_sender,0] select (FPV_inside && {FPV_dropContext}))', s)
    s = s.replace('isNil {', 'isNil { FPV_inside=true;')
    s = re.sub(r'_reply remoteExecCall \["A3UE_fnc_fpv_acceptLifecycle", _actualOwner\]',
               'FPV_replies pushBack [_reply,_actualOwner]', s)
    return engine_substitutes(s)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class HCSiteActivation(unittest.TestCase):
    def vm(self, body, extra=()):
        names = ['isTrustedSupportCaller', 'scheduleSite', 'receiveSiteIntent', 'reconcileSites', 'processSiteQueue']
        script = SETUP
        for name in names + list(extra):
            script += f'A3UE_fnc_fpv_{name}={{' + shipped(name) + '};\n'
        result = run_vm(script + body + '\ndiag_log "HC_TEST_OK";')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('HC_TEST_OK', result.stdout, result.stdout + result.stderr)
        self.assertNotIn('[ERR]', result.stdout, result.stdout)
        return result.stdout

    def test_missing_event_recovers_after_grace_once(self):
        out = self.vm(r'''
call _schedule; call _queue;
[TEST_calls isEqualTo [],"early deployment"] call _assert;
FPV_time=104.99; call _queue; [TEST_calls isEqualTo [],"grace"] call _assert;
FPV_time=105; call _queue; call _queue;
[TEST_calls isEqualTo [["site","Outpost",true]],"single recovery"] call _assert;
[(A3UE_FPV_siteLifecycle get "site") get "producer" == -1,"invented producer"] call _assert;
''')
        self.assertEqual(out.count('siteRecover marker='), 1)

    def test_recovery_fences(self):
        for mutation in [
            'spawner setVariable ["site",2];', 'FPV_markers deleteAt "site";',
            'sidesX setVariable ["site",west];', 'sidesX setVariable ["site",independent];',
            '_state set ["phase","closed"];', '_state set ["captured",true];',
            '_state set ["epoch","OLD"];', '_state set ["appliedGeneration",1];',
            '_state set ["producer",4];', '_state deleteAt "scheduledAt";',
            '_state set ["siteSide",sideUnknown];',
        ]:
            with self.subTest(mutation=mutation):
                self.vm('call _schedule; private _state=A3UE_FPV_siteLifecycle get "site";'
                        + mutation + 'FPV_time=110; call _queue; [TEST_calls isEqualTo [],"fence"] call _assert;')

    def test_inactive_then_active_cannot_revive_closed_generation(self):
        self.vm(r'''
call _schedule; spawner setVariable ["site",2]; call _queue;
spawner setVariable ["site",0]; FPV_time=110; call _queue;
call A3UE_fnc_fpv_reconcileSites; call _queue;
[TEST_calls isEqualTo [],"revived closed site"] call _assert;
call _schedule; FPV_time=115; call _queue;
[count TEST_calls==1,"fresh generation cannot recover"] call _assert;
''')

    def test_membership_reconcile_does_not_bypass_grace_or_capture(self):
        self.vm(r'''
call _schedule; call A3UE_fnc_fpv_reconcileSites; call _queue;
[TEST_calls isEqualTo [],"reconcile bypassed grace"] call _assert;
sidesX setVariable ["site",independent]; call A3UE_fnc_fpv_reconcileSites;
FPV_time=110; call _queue; [TEST_calls isEqualTo [],"reconcile relabeled captured site"] call _assert;
''')

    def test_delayed_hc_event_binds_producer_without_second_deployment(self):
        self.vm(r'''
call _schedule; FPV_time=105; call _queue;
FPV_remote=true; FPV_sender=0;
[["site","Outpost",true,"E",1,4] call _intent,"late HC"] call _assert;
call _queue; [count TEST_calls==1,"double deployment"] call _assert;
FPV_hcs=[]; call _queue;
[TEST_calls isEqualTo [["site","Outpost",true],["site","Outpost",false]],"HC disconnect retirement"] call _assert;
''')

    def test_fast_paths_capture_authority_before_atomic_context(self):
        for remote, sender, producer in [(False, 0, 2), (True, 2, 2), (True, 0, 4), (True, 4, 4)]:
            with self.subTest(remote=remote, sender=sender):
                self.vm(f'''
call _schedule; FPV_remote={str(remote).lower()}; FPV_sender={sender}; FPV_dropContext=true;
[["site","Outpost",true,"E",1,{producer}] call _intent,"fast path"] call _assert;
call _queue; FPV_time=110; call _queue; [count TEST_calls==1,"duplicate fast path"] call _assert;
''')

    def test_untrusted_jip_stale_and_fabricated_requests_never_mutate(self):
        cases = [
            ('FPV_remote=true;FPV_sender=3;', '["site","Outpost",true,"E",1,4]'),
            ('FPV_remote=true;FPV_sender=0;hcArray=[];', '["site","Outpost",true,"E",1,4]'),
            ('FPV_remote=true;FPV_sender=0;FPV_hcs=[];', '["site","Outpost",true,"E",1,4]'),
            ('FPV_remote=true;FPV_sender=0;', '["site","Outpost",true,"E",1,2]'),
            ('FPV_remote=false;', '["site","Outpost",true,"E",1,4]'),
            ('FPV_jip=true;', '["site","Outpost",true,"E",1,2]'),
            ('', '["site","Outpost",true,"OLD",1,2]'),
            ('', '["site","Outpost",true,"E",0,2]'),
            ('', '["site","Airport",true,"E",1,2]'),
            ('', '["fabricated","Outpost",true,"E",1,2]'),
            ('', '["site","Outpost",{},"E",1,2]'),
            ('', '42'),
        ]
        for context, args in cases:
            with self.subTest(context=context, args=args):
                out = self.vm('call _schedule; FPV_dropContext=true;' + context
                              + f'[!({args} call _intent),"accepted bad request"] call _assert;'
                              + '[(A3UE_FPV_siteLifecycle get "site") get "phase" == "pending","mutated"] call _assert;')
                self.assertIn('siteIntent refused marker=', out)

    def test_refusal_logs_are_bounded_per_server_generation(self):
        out = self.vm(r'''
call _schedule;
for "_i" from 1 to 20 do {["site","Outpost",true,"E",0,2] call _intent;};
[A3UE_FPV_siteIngressRejected==20,"lost rejection count"] call _assert;
call _schedule; ["site","Outpost",true,"E",0,2] call _intent;
''')
        self.assertEqual(out.count('siteIntent refused marker='), 2)

    def test_late_event_for_closed_generation_is_refused_quietly(self):
        # 1.0.6: the server's spawner check closed the generation first; AU's own event
        # arrives late. Refused as before, but neither counted nor logged as a fault.
        for remote, sender in [(False, 0), (True, 2)]:
            with self.subTest(remote=remote, sender=sender):
                out = self.vm(f'''
call _schedule; spawner setVariable ["site",2]; call _queue;
[(A3UE_FPV_siteLifecycle get "site") get "phase" == "closed","not closed"] call _assert;
FPV_remote={str(remote).lower()}; FPV_sender={sender};
[!(["site","Outpost",false,"E",1,2] call _intent),"late despawn accepted"] call _assert;
[!(["site","Outpost",true,"E",1,2] call _intent),"late spawn accepted"] call _assert;
[(missionNamespace getVariable ["A3UE_FPV_siteIngressRejected",0])==0,"late duplicate counted"] call _assert;
[(A3UE_FPV_siteLifecycle get "site") get "phase" == "closed","late duplicate reopened"] call _assert;
call _queue; [TEST_calls isEqualTo [],"late duplicate deployed"] call _assert;
A3UE_FPV_debug=true; ["site","Outpost",true,"E",1,2] call _intent;
''')
                self.assertNotIn('siteIntent refused marker=', out)
                self.assertEqual(out.count('siteIntent late marker=site'), 1)

    def test_closed_generation_from_other_producer_is_still_logged(self):
        out = self.vm(r'''
call _schedule; FPV_remote=true; FPV_sender=0;
[["site","Outpost",true,"E",1,4] call _intent,"HC bind"] call _assert;
call _queue; spawner setVariable ["site",2]; call _queue;
FPV_remote=false;
[!(["site","Outpost",false,"E",1,2] call _intent),"producer mismatch accepted"] call _assert;
''')
        self.assertIn('siteIntent refused marker=site reason=phaseOrProducer', out)

    def test_old_active_stock_retires_before_recovered_generation(self):
        self.vm(r'''
call _schedule; ["site","Outpost",true,"E",1,2] call _intent; call _queue;
call _schedule; FPV_time=105; call _queue; call _queue;
[TEST_calls isEqualTo [["site","Outpost",true],["site","Outpost",false],["site","Outpost",true]],"retirement order"] call _assert;
''')

    def test_lifecycle_receivers_keep_sender_and_token_fences_under_context_loss(self):
        for name, args in [('claimLifecycle', '[_uav,1,1]'), ('reportLifecycle', '[1,1,1,"release","secret",[]]')]:
            self.vm(r'''
private _uav="VMVehicle" createVehicle [0,0,0]; _uav setVariable ["owner",4];
private _record=createHashMapFromArray [["phase","live"],["object",_uav],["owner",4],["episode",1],
 ["generation",1],["token","secret"],["sequences",createHashMap],["released",false]];
A3UE_FPV_lifecycleIndex=createHashMapFromArray [["uav",1]];
A3UE_FPV_lifecycles=createHashMapFromArray [["1",_record]];
FPV_remote=true; FPV_sender=3; FPV_inside=false; FPV_dropContext=true;
''' + f'[!({args} call A3UE_fnc_fpv_{name}),"unauthorized lifecycle accepted"] call _assert;'
                         + r'''[!(_record get "released") && {!("challenge" in _record)},"lifecycle mutated"] call _assert;''', extra=[name])

    def test_hc_lifecycle_challenge_and_release_still_work(self):
        self.vm(r'''
private _uav="VMVehicle" createVehicle [0,0,0]; _uav setVariable ["owner",4];
private _record=createHashMapFromArray [["phase","live"],["object",_uav],["owner",2],["episode",1],
 ["generation",1],["token","secret"],["sequences",createHashMap],["released",false]];
A3UE_FPV_lifecycleIndex=createHashMapFromArray [["uav",1]];
A3UE_FPV_lifecycles=createHashMapFromArray [["1",_record]];
FPV_remote=true; FPV_sender=0; FPV_dropContext=true; FPV_inside=false;
[[_uav,1,1] call A3UE_fnc_fpv_claimLifecycle,"HC challenge"] call _assert;
[count (_record get "challenge")==4 && {count FPV_replies==1},"no challenge"] call _assert;
_record set ["released",false]; _record set ["owner",4]; FPV_inside=false;
[[1,1,1,"release","secret",[]] call A3UE_fnc_fpv_reportLifecycle,"HC release"] call _assert;
FPV_inside=false;
[!([1,1,1,"release","secret",[]] call A3UE_fnc_fpv_reportLifecycle),"duplicate release"] call _assert;
''', extra=['claimLifecycle', 'reportLifecycle'])


if __name__ == '__main__':
    unittest.main()
