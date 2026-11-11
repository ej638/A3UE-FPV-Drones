"""LT-2 (2026-11-10): frame-driven attack, coordinated attack with overwatch, lean brains.
Shipped SQF in SQF-VM through the commitment harness, plus source contracts.
These pin decisions for given clocks and positions. They make no claim about the Arma
scheduler, frame times, AI flight or physics: that is the engine card's job."""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, script, engine_substitutes, adapt_helper

NEW = ['wingSettings', 'attackSlot', 'attackRelease', 'attackCrowd', 'overwatch', 'overwatchPoint',
       'scanTargets', 'controllerState', 'directorFrame', 'perfReport']
CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')


def run(body, extra='', timeout=120):
    text = script(body, extra)
    with tempfile.TemporaryDirectory(prefix='fpv-lt2-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(text)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '2000000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=timeout)


def source(name):
    return (FPV / f'fn_fpv_{name}.sqf').read_text()


def code(name):
    return '\n'.join(line.split('//', 1)[0] for line in source(name).splitlines())


def load(name, replacements=()):
    s = source(name)
    for old, new in replacements:
        assert old in s, (name, old)
        s = s.replace(old, new)
    return f'A3UE_fnc_fpv_{name}={{{adapt_helper(name, s)}}};\n'


# Three more drones on the harness target (a crewed vehicle at [250,0,1.2]).
DRONES = '''
private _drone={params ["_id","_range"];private _d=["VMUAV",_id] call _make;
 {_d setVariable [_x # 0,_x # 1];} forEach [["A3UE_FPV_managed",true],["A3UE_FPV_controllerRunning",true],
  ["A3UE_FPV_mode","TRACKING"],["A3UE_FPV_targetNetId","target"],["position",[250+_range,0,1.2]]];_d};
private _slot={[_this,_target] call A3UE_fnc_fpv_attackSlot};
private _record={(missionNamespace getVariable ["A3UE_FPV_attackBoard",createHashMap]) get "target"};
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class WingSQF(unittest.TestCase):
    def sqf(self, body, extra=''):
        r = run(body, extra)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_settings_defaults_clamps_and_tick_memo(self):
        self.sqf('''
private _s=call A3UE_fnc_fpv_wingSettings;
[_s isEqualTo [true,2.5,1,2.5,140,true,true,true,20,700,false,25],str _s] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",2.9];
missionNamespace setVariable ["A3UE_FPV_frameBudgetMs",99];
missionNamespace setVariable ["A3UE_FPV_overwatchRadius","far"];
missionNamespace setVariable ["A3UE_FPV_frameDriver",0];
_s=call A3UE_fnc_fpv_wingSettings;
[(_s # 2)==2 && {(_s # 1)==10} && {(_s # 4)==140} && {(_s # 0) isEqualTo true},str _s] call _assert;
private _fpvTick=createHashMap;
private _inTick=call A3UE_fnc_fpv_wingSettings;
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",5];
[((call A3UE_fnc_fpv_wingSettings) # 2)==2,"one read per tick"] call _assert;
[_inTick isEqualTo (call A3UE_fnc_fpv_wingSettings),"same array"] call _assert;
_fpvTick=nil;
[((call A3UE_fnc_fpv_wingSettings) # 2)==5,"live outside a tick"] call _assert;
''')

    def test_one_attacker_others_wait_and_the_closest_goes_after_the_outcome(self):
        out = self.sqf(DRONES + '''
private _d1=["d1",200] call _drone; private _d2=["d2",300] call _drone; private _d3=["d3",100] call _drone;
[(_d1 call _slot) isEqualTo ["ATTACK",0,1],"first drone is cleared"] call _assert;
[(_d2 call _slot) isEqualTo ["WAIT",0,1],"second waits"] call _assert;
[(_d3 call _slot) isEqualTo ["WAIT",1,2],"third waits behind it (the attacker is committed inside 250 m)"] call _assert;
[(_d1 call _slot) # 0=="ATTACK","the attacker keeps its slot"] call _assert;
[([_target,_d2] call A3UE_fnc_fpv_attackCrowd)==2 && {([_target,objNull] call A3UE_fnc_fpv_attackCrowd)==3},"crowd count"] call _assert;
// The attack ends: its drone drops the target.
[_d1] call A3UE_fnc_fpv_clearTarget;
[(_d1 getVariable ["A3UE_FPV_wingTarget","x"])=="","released"] call _assert;
private _wait=((call _record) get "nextGrantAt")-FPV_time;
[_wait >= 2.5 && {_wait <= 3.5},format ["follow-up delay %1",_wait]] call _assert;
[(_d2 call _slot) # 0=="WAIT","nobody is cleared during the follow-up delay"] call _assert;
FPV_time=FPV_time+3.6;
[(_d2 call _slot) isEqualTo ["WAIT",0,1],"the slot goes to the closest waiting drone, not the first to ask"] call _assert;
[(_d3 call _slot) isEqualTo ["ATTACK",0,1],"d3 (100 m) attacks next"] call _assert;
''')
        self.assertRegex(out, r'wing target=target event=CLEARED id=d1')
        self.assertRegex(out, r'wing target=target event=TARGET_DROPPED id=d1 attackers=0 waiting=2 nextInS=3')
        self.assertRegex(out, r'wing target=target event=CLEARED id=d3')

    def test_attack_that_ends_without_a_release_starts_the_delay(self):
        self.sqf(DRONES + '''
private _d1=["d1",200] call _drone; private _d2=["d2",300] call _drone;
_d1 call _slot; _d2 call _slot;
_d1 setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];
[(_d2 call _slot) # 0=="WAIT","diving attacker keeps the slot"] call _assert;
// It strikes (or is shot down): gone without calling release.
_d1 setVariable ["alive",false];
[(_d2 call _slot) # 0=="WAIT","the outcome starts the follow-up delay"] call _assert;
[((call _record) get "nextGrantAt") > FPV_time+2,"delay set"] call _assert;
FPV_time=FPV_time+3.6;
[(_d2 call _slot) isEqualTo ["ATTACK",0,1],"then the next drone goes in"] call _assert;
// A spent, uncontrolled, remote or retargeted drone is no member either.
private _d3=["d3",100] call _drone; _d3 call _slot;
{_d2 setVariable [_x # 0,_x # 1];FPV_time=FPV_time+4;
 [(_d3 call _slot) # 0=="ATTACK",_x # 0] call _assert;
 _d2 setVariable [_x # 0,_x # 2];_d3 setVariable ["A3UE_FPV_mode","LOST_TARGET"];_d2 call _slot;_d3 setVariable ["A3UE_FPV_mode","TRACKING"];
 FPV_time=FPV_time+4;[(_d2 call _slot) # 0=="ATTACK","back"] call _assert;_d3 call _slot;
} forEach [["A3UE_FPV_detonating",true,false],["A3UE_FPV_controllerRunning",false,true],["local",false,true],["A3UE_FPV_cleanupPending",true,false]];
''')

    def test_far_attacker_gives_way_to_a_much_closer_drone(self):
        out = self.sqf(DRONES + '''
private _far=["far",600] call _drone; private _near=["near",200] call _drone; private _mid=["mid",520] call _drone;
[(_far call _slot) # 0=="ATTACK","first to see the target"] call _assert;
[(_mid call _slot) # 0=="WAIT","80 m closer is not enough"] call _assert;
[(_near call _slot) isEqualTo ["ATTACK",0,1],"400 m closer takes the slot, no delay"] call _assert;
[(_far call _slot) # 0=="WAIT","the far one now waits"] call _assert;
// Not from a committed attacker: inside 250 m, or diving.
private _closest=["closest",40] call _drone;
[(_closest call _slot) # 0=="WAIT","a committed attacker keeps its slot"] call _assert;
''')
        self.assertRegex(out, r'event=SWAP id=near')

    def test_cleared_drone_that_never_dives_gives_way_and_stands_back(self):
        out = self.sqf(DRONES + '''
private _d1=["d1",150] call _drone; private _d2=["d2",300] call _drone;
_d1 call _slot; _d2 call _slot;
FPV_time=FPV_time+19;[(_d1 call _slot) # 0=="ATTACK","inside the timeout"] call _assert;
FPV_time=FPV_time+2;
[(_d1 call _slot) # 0=="WAIT","close for 20 s without diving: gives way"] call _assert;
[(_d2 call _slot) isEqualTo ["ATTACK",0,1],"the other drone is cleared at once (no outcome, no delay)"] call _assert;
// Alone on the target it would simply be cleared again.
[_d2] call A3UE_fnc_fpv_clearTarget; FPV_time=FPV_time+4;
[(_d1 call _slot) # 0=="ATTACK","only drone left"] call _assert;
// Far out, the clock does not run: transit is not a refusal to dive.
private _d3=["d3",900] call _drone;
[_d1] call A3UE_fnc_fpv_clearTarget; FPV_time=FPV_time+40;
[(_d3 call _slot) # 0=="ATTACK","cleared"] call _assert;
private _d4=["d4",880] call _drone; _d4 call _slot;
FPV_time=FPV_time+60;[(_d3 call _slot) # 0=="ATTACK","still its slot after a long transit"] call _assert;
''')
        self.assertRegex(out, r'event=TIMEOUT id=d1')

    def test_limit_zero_is_the_old_behaviour_and_two_allows_two(self):
        self.sqf(DRONES + '''
private _d1=["d1",200] call _drone; private _d2=["d2",240] call _drone; private _d3=["d3",100] call _drone;
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",0];
{[(_x call _slot) isEqualTo ["ATTACK",0,1],"no limit"] call _assert;} forEach [_d1,_d2,_d3];
[count (missionNamespace getVariable ["A3UE_FPV_attackBoard",createHashMap])==0 && {(_d1 getVariable ["A3UE_FPV_wingTarget",""])==""},"no board"] call _assert;
[([_target,_d1] call A3UE_fnc_fpv_attackCrowd)==0,"no crowd"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",2];
[(_d1 call _slot) # 0=="ATTACK" && {(_d2 call _slot) isEqualTo ["ATTACK",1,2]} && {(_d3 call _slot) isEqualTo ["WAIT",0,1]},"two at once"] call _assert;
// A remote sender never touches the board.
FPV_remote=true;FPV_sender=5;A3UE_fnc_fpv_helperAccess={false};
[(_d3 call _slot) isEqualTo ["ATTACK",0,1] && {!([_d1] call A3UE_fnc_fpv_attackRelease)},"fenced"] call _assert;
A3UE_fnc_fpv_helperAccess={true};
[count ((call _record) get "holders")==2,"board untouched"] call _assert;
''')

    def test_targets_standing_together_share_one_attack_at_a_time(self):
        self.sqf(DRONES + '''
// Two men 8 m apart (one warhead reaches both), a third 120 m away.
private _man={params ["_id","_pos"];private _m=["VMMan",_id] call _make;_m setVariable ["side",west];_m setVariable ["position",_pos];_m};
private _a=["a",[250,0,1.2]] call _man;private _b=["b",[258,0,1.2]] call _man;private _c=["c",[250,120,1.2]] call _man;
private _on={params ["_d","_t"];_d setVariable ["A3UE_FPV_targetNetId",_t getVariable "netId"];[_d,_t] call A3UE_fnc_fpv_attackSlot};
private _d1=["d1",100] call _drone;private _d2=["d2",120] call _drone;private _d3=["d3",140] call _drone;
[([_d1,_a] call _on) # 0=="ATTACK","first man is attacked"] call _assert;
[([_d2,_b] call _on) # 0=="WAIT","his neighbour's drone waits although its own slot is free"] call _assert;
[([_d3,_c] call _on) # 0=="ATTACK","the man 120 m away is attacked at the same time"] call _assert;
// The first attack ends: the neighbour's drone is cleared at once (it needs seconds to arrive).
[_d1] call A3UE_fnc_fpv_clearTarget;
[([_d2,_b] call _on) # 0=="ATTACK","the neighbour is attacked next"] call _assert;
FPV_time=FPV_time+3.6;
[([_d1,_a] call _on) # 0=="WAIT","and the first man's next drone waits for that attack, its own delay long over"] call _assert;
// A dead attacker nobody asks about never blocks its neighbours.
_d2 setVariable ["alive",false];
[([_d1,_a] call _on) # 0=="ATTACK","stale neighbour ignored"] call _assert;
// The neighbour's own record: its attack ended (delay), then it waits for the first man's attacker.
private _d4=["d4",90] call _drone;
[([_d4,_b] call _on) # 0=="WAIT","own follow-up delay"] call _assert;
FPV_time=FPV_time+4;
[([_d4,_b] call _on) # 0=="WAIT","neighbour under attack"] call _assert;
// A neighbour's drone that was cleared but has not dived after the slot timeout stops blocking;
// one that is diving always blocks.
_d1 setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];FPV_time=FPV_time+30;
[([_d4,_b] call _on) # 0=="WAIT","a diving neighbour blocks however long it takes"] call _assert;
_d1 setVariable ["A3UE_FPV_mode","TRACKING"];
[([_d4,_b] call _on) # 0=="ATTACK","a neighbour that never dived does not"] call _assert;
// Spacing off: neighbours are attacked independently.
[_d4] call A3UE_fnc_fpv_clearTarget;FPV_time=FPV_time+4;
_d1 setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];
[([_d4,_b] call _on) # 0=="WAIT","blocked again"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackSpacing",0];
[([_d4,_b] call _on) # 0=="ATTACK","spacing off"] call _assert;
''')

    def test_a_man_who_boards_changes_the_board_key(self):
        self.sqf(DRONES + '''
private _d1=["d1",200] call _drone; private _d2=["d2",300] call _drone;
_d1 call _slot; _d2 call _slot;
// d1 now resolves to another object (its man boarded a vehicle): it leaves the old record.
private _other=["VMVehicle","truck"] call _make; _other setVariable ["position",[260,0,1.2]];
[([_d1,_other] call A3UE_fnc_fpv_attackSlot) # 0=="ATTACK","cleared on the new target"] call _assert;
[(_d1 getVariable ["A3UE_FPV_wingTarget",""])=="truck","new key"] call _assert;
[count ((call _record) get "holders")==0,"old slot released (with the follow-up delay)"] call _assert;
''')

    def test_selection_spreads_over_targets_by_crowd(self):
        self.sqf(DRONES + '''
missionNamespace setVariable ["A3UE_FPV_attackRun",true];
private _p2=["VMMan","p2"] call _make;_p2 setVariable ["side",west];
_uav setVariable ["A3UE_FPV_targetNetId",""];_uav setVariable ["A3UE_FPV_mode","SEARCHING"];
// Two equal men; two drones are already on the first.
private _d1=["d1",0] call _drone; private _d2=["d2",0] call _drone;
{_x setVariable ["A3UE_FPV_targetNetId","person"];[_x,_person] call A3UE_fnc_fpv_attackSlot;} forEach [_d1,_d2];
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
[([_uav,_profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _p2,"the free target wins"] call _assert;
[((_uav getVariable ["A3UE_FPV_lastTargetScoreBreakdown",createHashMap]) get "crowdPenalty")==0,"no penalty on it"] call _assert;
// Without the other target, the crowded one is still chosen.
_p2 setVariable ["alive",false];
missionNamespace setVariable ["A3UE_FPV_scanCache",createHashMap];
[([_uav,_profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _person,"only target"] call _assert;
[((_uav getVariable ["A3UE_FPV_lastTargetScoreBreakdown",createHashMap]) get "crowdPenalty")==1400,"two drones, 700 each"] call _assert;
// Coordination off: no penalty.
_p2 setVariable ["alive",true];missionNamespace setVariable ["A3UE_FPV_scanCache",createHashMap];
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",0];
[_uav,_profile] call A3UE_fnc_fpv_selectTarget;
[((_uav getVariable ["A3UE_FPV_lastTargetScoreBreakdown",createHashMap]) get "crowdPenalty")==0,"off"] call _assert;
''')

    def test_site_scan_is_shared_filtered_and_bounded(self):
        self.sqf('''
private _key="outpost_1/500";
private _a=[_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets;
[FPV_scans==1 && {_a isEqualTo [_target,_person]},str [FPV_scans,_a apply {_x getVariable "netId"}]] call _assert;
// A second drone of the site, same instant and half a second later: no new scan.
[_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets;FPV_time=FPV_time+0.5;
private _b=[_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets;
[FPV_scans==1,"shared within the TTL"] call _assert;
_b deleteAt 0;[count ([_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets)==2,"callers get a copy"] call _assert;
FPV_time=FPV_time+1.1;[_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets;
[FPV_scans==2,"refreshed after the TTL"] call _assert;
// Legality is filterTarget's: empty vehicle, captive, dead and managed drones are not candidates.
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];_person setVariable ["captive",true];
FPV_time=FPV_time+2;
[([_key,[0,0,0],500,1.5,[west]] call A3UE_fnc_fpv_scanTargets) isEqualTo [],"none legal"] call _assert;
// Radius, a moved centre, another side set and another key are separate scans.
private _n=FPV_scans;
[_key,[0,0,0],400,1.5,[west]] call A3UE_fnc_fpv_scanTargets;
[_key,[30,0,0],400,1.5,[west]] call A3UE_fnc_fpv_scanTargets;
[_key,[30,0,0],400,1.5,[east]] call A3UE_fnc_fpv_scanTargets;
["uav/local",[30,0,0],400,1,[west]] call A3UE_fnc_fpv_scanTargets;
[FPV_scans==_n+4,str FPV_scans] call _assert;
[([_key,[0,0,0],0,1,[west]] call A3UE_fnc_fpv_scanTargets) isEqualTo [] && {(["",[0,0,0],5,1,[west]] call A3UE_fnc_fpv_scanTargets) isEqualTo []}
 && {([_key,[0,0,0],5,1,[]] call A3UE_fnc_fpv_scanTargets) isEqualTo []} && {FPV_scans==_n+4},"invalid input scans nothing"] call _assert;
// Old per-drone entries are dropped once the cache is large.
for "_i" from 0 to 70 do {[format ["gone%1/local",_i],[0,0,0],50,1,[west]] call A3UE_fnc_fpv_scanTargets;};
FPV_time=FPV_time+40;["fresh/local",[0,0,0],50,1,[west]] call A3UE_fnc_fpv_scanTargets;
[count (missionNamespace getVariable "A3UE_FPV_scanCache") <= 2,"swept"] call _assert;
''')

    def test_select_target_uses_the_shared_scan_and_the_switch_restores_the_old_caches(self):
        self.sqf('''
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",0];
_uav setVariable ["A3UE_FPV_targetNetId",""];
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
[([_uav,_profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _person,"shared scan finds the man"] call _assert;
// Unmarked drone: site circle (350 m) around itself, so its local circle (250 m) is inside it.
[FPV_scans==1,format ["one scan, local circle skipped: %1",FPV_scans]] call _assert;
[_uav,_profile] call A3UE_fnc_fpv_selectTarget;
[FPV_scans==1,"second selection inside the TTL scans nothing"] call _assert;
[(_uav getVariable ["A3UE_FPV_siteCandidateCache",[]]) isEqualTo [],"old per-drone cache unused"] call _assert;
// Switch off: the 1.0.3 per-drone caches (pre-filled here, as nearestObjects is not in the VM).
missionNamespace setVariable ["A3UE_FPV_sharedScan",false];
_uav setVariable ["A3UE_FPV_siteCandidateCache",[100,[0,0,50],350,[_target,_person]]];
_uav setVariable ["A3UE_FPV_localCandidateCache",[100,[0,0,50],250,[_target,_person]]];
[([_uav,_profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _person && {FPV_scans==1},"legacy path"] call _assert;
''')

    def test_only_the_six_best_candidates_are_traced(self):
        self.sqf('''
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",0];
_uav setVariable ["A3UE_FPV_targetNetId",""];
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
for "_i" from 1 to 9 do {private _m=["VMMan",format ["m%1",_i]] call _make;_m setVariable ["side",west];};
FPV_traces=0;
A3UE_fnc_fpv_isTargetObstructed={FPV_traces=FPV_traces+1;createHashMapFromArray [["blocked",false],["obstructionCount",0]]};
[!isNull ([_uav,_profile] call A3UE_fnc_fpv_selectTarget),"a target"] call _assert;
[FPV_traces==6,format ["ten hostile men, six traced: %1",FPV_traces]] call _assert;
''')

    def test_overwatch_ring_geometry(self):
        self.sqf('''
private _p={[_this # 0,[0,0,0],_this # 2,140,_this # 1] call A3UE_fnc_fpv_overwatchPoint};
private _near={params ["_a","_b"];abs (_a-_b) < 0.01};
// On the ring, due north of the target: 45 deg ahead, clockwise for even places.
private _r=[[0,140,40],0,[0,0,0]] call _p;
[[_r # 0,140*sin 45] call _near && {[_r # 1,140*cos 45] call _near},str _r] call _assert;
[(_r # 2)==0 && {(_r # 3)==14} && {_r # 4},"index 0: no stagger, loiter speed, on the ring"] call _assert;
// The middle ring goes the other way, 15 m wider; the next height is 6 m up.
_r=[[0,155,40],1,[0,0,0]] call _p;
[[_r # 0,-155*sin 45] call _near && {[_r # 1,155*cos 45] call _near} && {(_r # 2)==6},str _r] call _assert;
// Rings repeat by 3 (outer and inner the same way round), heights by 4.
[(([[0,140,40],3,[0,0,0]] call _p) # 0) > 0 && {(([[0,170,40],2,[0,0,0]] call _p) # 0) > 0} && {(([[0,155,40],4,[0,0,0]] call _p) # 0) < 0},"ring directions"] call _assert;
[(([[0,170,40],2,[0,0,0]] call _p) # 2)==12 && {(([[0,140,40],3,[0,0,0]] call _p) # 2)==18} && {(([[0,155,40],4,[0,0,0]] call _p) # 2)==0},"height stagger"] call _assert;
// Far outside: small lead (flies in), not on the ring.
_r=[[0,1400,40],0,[0,0,0]] call _p;
[!(_r # 4) && {(_r # 0) < 17} && {(_r # 1) > 139},str _r] call _assert;
// Every ordered point is on the drone's ring, at least 100 m ahead on it.
{private _q=[_x,0,[0,0,0]] call _p;
 [[vectorMagnitude [_q # 0,_q # 1,0],140] call _near,"on the ring"] call _assert;} forEach [[30,10,40],[-200,90,40],[0,0,40],[500,-500,40]];
[(([[0,140,40],0,[0,0,0]] call _p) select [0,2]) distance2D [0,140] > 100,"ahead"] call _assert;
// A moving target: the ring is centred 2 s ahead and the loiter speed keeps up, within bounds.
_r=[[20,140,40],0,[10,0,0]] call _p;
[[_r # 0,20+140*sin 45] call _near && {(_r # 3)==18},str _r] call _assert;
[(([[0,140,40],0,[60,0,0]] call _p) # 3)==40,"speed cap"] call _assert;
''')

    def test_tick_memo_keeps_spent_and_identity_checks_live(self):
        self.sqf('''
// Outside a tick every call is live.
[[_uav,_identity] call A3UE_fnc_fpv_canActuate,"baseline"] call _assert;
_uav setVariable ["controlled",true];
[!([_uav,_identity] call A3UE_fnc_fpv_canActuate),"control seen at once"] call _assert;
_uav setVariable ["controlled",false];
FPV_checks=0;
A3UE_fnc_fpv_isExternallyControlled={FPV_checks=FPV_checks+1;(_this # 0) getVariable ["controlled",false]};
private _fpvTick=createHashMap;
[[_uav,_identity] call A3UE_fnc_fpv_canActuate && {[_uav,_identity] call A3UE_fnc_fpv_canActuate} && {FPV_checks==1},"control read once per tick"] call _assert;
// What this tick can change itself is never memoised.
{_uav setVariable [_x # 0,_x # 1];
 [!([_uav,_identity] call A3UE_fnc_fpv_canActuate),_x # 0] call _assert;
 _uav setVariable [_x # 0,_x # 2];
 [[_uav,_identity] call A3UE_fnc_fpv_canActuate,"restored"] call _assert;
} forEach [["A3UE_FPV_detonating",true,false],["A3UE_FPV_cleanupPending",true,false],["A3UE_FPV_controllerRunning",false,true],
 ["alive",false,true],["local",false,true],["A3UE_FPV_controllerGeneration",2,1],["A3UE_FPV_controllerIdentity",[1,2,1,2],[1,2,1,1]]];
[!([_uav,[1,2,1,2]] call A3UE_fnc_fpv_canActuate),"another identity is not served from the memo"] call _assert;
private _other=["VMUAV","other"] call _make;
[!([_other,_identity] call A3UE_fnc_fpv_canActuate),"another drone is not served from the memo"] call _assert;
// A new tick reads again.
_uav setVariable ["controlled",true];
_fpvTick=createHashMap;
[!([_uav,_identity] call A3UE_fnc_fpv_canActuate),"next tick sees control"] call _assert;
''')

    def test_tick_memo_of_the_target_follows_id_revision_and_death(self):
        self.sqf('''
FPV_filters=0;private _filter=A3UE_fnc_fpv_filterTarget;
A3UE_fnc_fpv_filterTarget={FPV_filters=FPV_filters+1;_this call _filter};
private _fpvTick=createHashMap;
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target && {([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target} && {FPV_filters==1},"resolved once per tick"] call _assert;
_uav setVariable ["A3UE_FPV_targetNetId","person"];
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _person,"a new id is resolved"] call _assert;
_uav setVariable ["A3UE_FPV_targetNetId","target"];
[_uav] call A3UE_fnc_fpv_clearTarget;
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"cleared"] call _assert;
_uav setVariable ["A3UE_FPV_targetNetId","target"];
private _n=FPV_filters;
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target && {FPV_filters==_n+1},"same id, new revision: resolved again"] call _assert;
// The target dies inside the tick (this drone's own strike): never served from the memo.
_target setVariable ["alive",false];
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"dead target"] call _assert;
// Illegal results are not kept either.
_target setVariable ["alive",true];_person setVariable ["captive",true];
_fpvTick=createHashMap;
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"captive commander"] call _assert;
_person setVariable ["captive",false];
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target,"legal again in the same tick"] call _assert;
''')

    def test_tick_memo_of_settings_and_limits_matches_the_live_values(self):
        self.sqf('''
missionNamespace setVariable ["A3UE_FPV_attackRun",true];
private _liveSettings=call A3UE_fnc_fpv_attackSettings;
private _liveLimits=[_profile] call A3UE_fnc_fpv_trajectoryLimits;
private _fpvTick=createHashMap;
[(call A3UE_fnc_fpv_attackSettings) isEqualTo _liveSettings && {([_profile] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo _liveLimits},"same values in a tick"] call _assert;
missionNamespace setVariable ["A3UE_FPV_weaveScale",0.3];
missionNamespace setVariable ["A3UE_FPV_attackSpeedScale",0.5];
[(call A3UE_fnc_fpv_attackSettings) isEqualTo _liveSettings && {([_profile] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo _liveLimits},"one read per tick"] call _assert;
// attackLimits must not write into the memoised limits.
_uav setVariable ["A3UE_FPV_attackReversal",createHashMapFromArray [["phase","PULL"],["key",[+_identity,"target",0,9]]]];
private _flip=[_uav,_target,_identity,_profile,[_profile] call A3UE_fnc_fpv_trajectoryLimits] call A3UE_fnc_fpv_attackLimits;
[!(_flip isEqualTo _liveLimits) && {([_profile] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo _liveLimits},"flip limits are a copy"] call _assert;
_fpvTick=nil;
[((call A3UE_fnc_fpv_attackSettings) # 2)==0.3 && {!(([_profile] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo _liveLimits)},"live outside a tick"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun",false];
[!((call A3UE_fnc_fpv_attackSettings) # 0),"master switch"] call _assert;
''')


DIRECTOR = '''
A3UE_FPV_perf=[0,0,0,0,0,0,0,0,0,0,0,FPV_observed];
A3UE_FPV_controllerStates=[];
missionNamespace setVariable ["A3UE_FPV_perfNextAt",1e9];
FPV_ticks=[];FPV_tickCost=0.002;
// Stand-in for the controller tick: costs FPV_tickCost and asks for the next pass in 20 ms.
A3UE_fnc_fpv_runController={params ["_u","_g","_s"];FPV_ticks pushBack (_s get "id");FPV_observed=FPV_observed+FPV_tickCost;
 _s set ["dueAt",FPV_time+0.02];_s set ["tickedAt",FPV_observed];
 if ((_s get "id") in FPV_finishing) then {_s set ["hot",false];};[true,0.02]};
FPV_finishing=[];
private _state={createHashMapFromArray [["id",_this],["uav",_uav],["generation",1],["running",true],["hot",true],["listed",true],["dueAt",0],["tickedAt",-1]]};
private _frame={FPV_ticks=[];FPV_time=FPV_time+0.03;FPV_observed=FPV_observed+0.03;call A3UE_fnc_fpv_directorFrame;+FPV_ticks};
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class DirectorSQF(unittest.TestCase):
    EXTRA = None

    @classmethod
    def setUpClass(cls):
        cls.EXTRA = (load('directorFrame') + load('perfReport', [('round diag_fps', '33')])
                     + load('controllerState', [('addMissionEventHandler ["EachFrame", {call A3UE_fnc_fpv_directorFrame}]', '7')]))

    def sqf(self, body):
        r = run(DIRECTOR + body, self.EXTRA)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_idle_director_does_nothing(self):
        self.sqf('''
A3UE_FPV_directorStates=[];
[(call _frame) isEqualTo [] && {(A3UE_FPV_perf select [0,11]) isEqualTo [0,0,0,0,0,0,0,0,0,0,0]},"idle"] call _assert;
''')

    def test_every_attacker_is_ticked_each_frame_inside_the_budget(self):
        self.sqf('''
FPV_tickCost=0.0005;
A3UE_FPV_directorStates=["a" call _state,"b" call _state,"c" call _state];
[(call _frame) isEqualTo ["a","b","c"],"all three"] call _assert;
[(call _frame) isEqualTo ["a","b","c"],"and again next frame"] call _assert;
[(A3UE_FPV_perf # 0)==6 && {(A3UE_FPV_perf # 3)==0} && {(A3UE_FPV_perf # 4)==2} && {(A3UE_FPV_perf # 5)==3},str A3UE_FPV_perf] call _assert;
[abs ((A3UE_FPV_perf # 1)-0.003) < 1e-5 && {abs ((A3UE_FPV_perf # 10)-0.0015) < 1e-5},"cost sums"] call _assert;
// Simulation time standing still (pause): nothing is due, nothing runs.
FPV_ticks=[];FPV_observed=FPV_observed+0.03;call A3UE_fnc_fpv_directorFrame;
[FPV_ticks isEqualTo [],"no tick without simulation time"] call _assert;
''')

    def test_over_budget_the_rest_go_first_next_frame(self):
        self.sqf('''
// 2 ms a tick against 2.5 ms: two fit (the second starts inside the budget), the third waits.
A3UE_FPV_directorStates=["a" call _state,"b" call _state,"c" call _state];
[(call _frame) isEqualTo ["a","b"],"budget"] call _assert;
[(call _frame) isEqualTo ["c","a"],"the one that waited goes first"] call _assert;
[(call _frame) isEqualTo ["b","c"],"round robin"] call _assert;
[(A3UE_FPV_perf # 3)==3,"frames over budget counted"] call _assert;
// One tick always runs, whatever it costs.
FPV_tickCost=0.02;
[count (call _frame)==1,"at least one"] call _assert;
// A larger budget takes all three.
FPV_tickCost=0.002;missionNamespace setVariable ["A3UE_FPV_frameBudgetMs",8];
[count (call _frame)==3,"budget setting"] call _assert;
''')

    def test_finished_and_stopped_controllers_leave_the_director(self):
        self.sqf('''
private _a="a" call _state;private _b="b" call _state;private _c="c" call _state;
missionNamespace setVariable ["A3UE_FPV_frameBudgetMs",8];
A3UE_FPV_directorStates=[_a,_b,_c];
FPV_finishing=["b"];
[(call _frame) isEqualTo ["a","b","c"],"b's dive ends in this tick"] call _assert;
[!(_b get "listed") && {(A3UE_FPV_directorStates apply {_x get "id"}) isEqualTo ["a","c"]},"handed back to its script at once"] call _assert;
_c set ["running",false];
[(call _frame) isEqualTo ["a"] && {!(_c get "listed")} && {count A3UE_FPV_directorStates==1},"a stopped controller is dropped untouched"] call _assert;
// Switched off: everything goes back to the scheduled scripts.
missionNamespace setVariable ["A3UE_FPV_frameDriver",false];
[(call _frame) isEqualTo [] && {A3UE_FPV_directorStates isEqualTo []} && {!(_a get "listed")},"director off"] call _assert;
''')

    def test_state_and_director_install_once_and_the_evidence_line(self):
        out = self.sqf('''
A3UE_FPV_directorHandler=nil;A3UE_FPV_directorStates=nil;
_uav setVariable ["A3UE_FPV_nativeControl",[_identity,[],-1]];
A3UE_fnc_fpv_getProfile={_profile};
private _s1=[_uav,1] call A3UE_fnc_fpv_controllerState;
[A3UE_FPV_directorHandler==7 && {A3UE_FPV_directorStates isEqualTo []} && {count A3UE_FPV_controllerStates==1}
 && {(missionNamespace getVariable "A3UE_FPV_perfNextAt")==FPV_observed+10},"installed; first evidence line after a full window"] call _assert;
A3UE_FPV_directorHandler=8;
private _s2=[_uav,1] call A3UE_fnc_fpv_controllerState;
[A3UE_FPV_directorHandler==8 && {count A3UE_FPV_controllerStates==2},"once per machine"] call _assert;
[(_s1 get "identity") isEqualTo _identity && {(_s1 get "running")} && {!(_s1 get "hot")} && {!(_s1 get "listed")}
 && {_s1 get "aiRecoveryPending"} && {_s1 get "targetabilitySuspended"} && {!(_s1 get "impactCacheReady")} && {(_s1 get "nextGuidance")==0},"initial state"] call _assert;
_uav setVariable ["A3UE_FPV_controllerIdentity",[9,9,9,9]];
[(_s1 get "identity") isEqualTo _identity,"the state keeps its original ticket"] call _assert;
FPV_remote=true;A3UE_fnc_fpv_helperAccess={false};
[count ([_uav,1] call A3UE_fnc_fpv_controllerState)==0 && {count A3UE_FPV_controllerStates==2},"fenced"] call _assert;
A3UE_fnc_fpv_helperAccess={true};
// Evidence line: one per window, only when something ran, then the counters start again.
_s2 set ["running",false];
A3UE_FPV_perf=[40,0.02,0.004,3,30,2,10,0.5,0.2,10,0.006,FPV_observed-10];
missionNamespace setVariable ["A3UE_FPV_scanCount",7];
call A3UE_fnc_fpv_perfReport;
[(A3UE_FPV_perf select [0,11]) isEqualTo [0,0,0,0,0,0,0,0,0,0,0] && {count A3UE_FPV_controllerStates==1}
 && {(missionNamespace getVariable "A3UE_FPV_perfNextAt")==FPV_observed+60} && {(missionNamespace getVariable "A3UE_FPV_scanCount")==0},"window reset"] call _assert;
missionNamespace setVariable ["A3UE_FPV_perfLog",true];
call A3UE_fnc_fpv_perfReport;
[(missionNamespace getVariable "A3UE_FPV_perfNextAt")==FPV_observed+10,"10 s with A3UE_FPV_perfLog"] call _assert;
''')
        lines = [line for line in out.splitlines() if '[A3UE_FPV] director' in line]
        self.assertEqual(len(lines), 1, out)
        self.assertIn('windowS=10 fps=33 controllers=1 | attackFrames=30 attackersMax=2 ticks=40 meanMs=0.5 maxMs=4 '
                      'frameMaxMs=6 overBudget=3 | scheduled wakes=10 ticks=10 lateMeanMs=50 lateMaxMs=200 | scans=7', lines[0])


# The whole controller tick in the VM. Native AI orders, payload, radio and lost-target search are
# stand-ins; target legality, coordination, the dive writer, the fuse path and every state
# transition are the shipped code. Object-to-object `distance` is 0 in the VM (ranges come from
# the "position" variables only where the harness substitutes them), so entry gates are open.
TICK_SETUP = '''
FPV_holds=0;FPV_guides=[];FPV_fly=[];FPV_speeds=[];FPV_moveTo=[];FPV_restores=0;FPV_profile=_profile;
A3UE_fnc_fpv_getProfile={FPV_profile};
A3UE_fnc_fpv_cacheLinkState={"OK"};
A3UE_fnc_fpv_applyTargetability={true};
A3UE_fnc_fpv_holdPattern={FPV_holds=FPV_holds+1;true};
A3UE_fnc_fpv_applyGuidance={FPV_guides pushBack (_this # 0);true};
A3UE_fnc_fpv_runLostTarget={objNull};
A3UE_fnc_fpv_computeIntercept={(_this # 1) getVariable ["position",[0,0,0]]};
A3UE_fnc_fpv_attackEngagement={[]};
A3UE_fnc_fpv_attackApproach={_this # 3};
A3UE_FPV_directorHandler=nil;
private _ready={params ["_d","_id","_lifecycle"];
 {_d setVariable [_x # 0,_x # 1];} forEach [["A3UE_FPV_targetNetId",""],["A3UE_FPV_mode","SEARCHING"],
  ["A3UE_FPV_controllerIdentity",[_lifecycle,2,1,1]],["A3UE_FPV_lifecycleId",_lifecycle],["A3UE_FPV_lifecycleEpisode",1],
  ["A3UE_FPV_controllerGeneration",1],["A3UE_FPV_managed",true],["A3UE_FPV_controllerRunning",true],["A3UE_FPV_netId",_id],
  ["A3UE_FPV_payloadRole","AP"],["A3UE_FPV_terminalVectorEnteredAt",-1]];
 [_d,1] call A3UE_fnc_fpv_controllerState};
private _tick={params ["_d","_s"];[_d,1,_s] call A3UE_fnc_fpv_runController};
private _mode={_this getVariable ["A3UE_FPV_mode",""]};
private _frame={FPV_time=FPV_time+0.03;FPV_observed=FPV_observed+0.03;FPV_frame=FPV_frame+1;call A3UE_fnc_fpv_directorFrame;};
// One hostile man 250 m out; the harness vehicle is empty (not a target).
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
_person setVariable ["position",[250,0,0]];_person setVariable ["velocity",[0,0,0]];
private _state=[_uav,"uav",1] call _ready;
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class TickSQF(unittest.TestCase):
    EXTRA = None

    @classmethod
    def setUpClass(cls):
        controller = [('_uav forceSpeed (_native # 2);', 'FPV_restores=FPV_restores+1;'),
                      # The VM has no Boolean != (Arma has).
                      ('if (_externalControl != (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {',
                       'if (_externalControl isNotEqualTo (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {'),
                      ('_surfaceObject worldToModel (ASLToAGL _impactPointAsl)', '(_impactPointAsl vectorDiff (getPosASL _surfaceObject))'),
                      ('_anchorObject modelToWorldWorld _anchor', '((getPosASL _anchorObject) vectorAdd _anchor)')]
        overwatch = [('_uav enableAI "ALL";', ''), ('_uav setBehaviour "CARELESS";', ''), ('_uav setCombatMode "BLUE";', ''),
                     ('_uav setSpeedMode "NORMAL";', ''), ('_uav flyInHeight _height;', 'FPV_fly pushBack _height;'),
                     ('_uav forceSpeed _speed;', 'FPV_speeds pushBack _speed;'), ('_uav doMove _moveTargetAtl;', 'FPV_moveTo pushBack _moveTargetAtl;')]
        cls.EXTRA = (load('runController', controller) + load('overwatch', overwatch) + load('directorFrame')
                     + load('perfReport', [('round diag_fps', '33')])
                     + load('controllerState', [('addMissionEventHandler ["EachFrame", {call A3UE_fnc_fpv_directorFrame}]', '7')])
                     + ''.join(load(n) for n in ['controllerSleep', 'shouldEnterTerminal', 'emptyImpactSolution', 'resolveImpactPoint',
                                                 'traceAttackRay', 'isAlliedAttacker', 'shouldDetonateNow', 'evaluateImpactWindow']))

    def sqf(self, body):
        r = run(TICK_SETUP + body, self.EXTRA, timeout=240)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_search_attack_dive_and_handoff_to_the_director(self):
        out = self.sqf('''
private _r=[_uav,_state] call _tick;
[_r # 0 && {(_uav call _mode)=="TRACKING"} && {(_uav getVariable "A3UE_FPV_targetNetId")=="person"} && {FPV_holds==1},"search pass adopts the man"] call _assert;
[!(_state get "hot") && {!(_state get "listed")} && {(_state get "dueAt") > FPV_time},"still with its scheduled script"] call _assert;
FPV_time=FPV_time+0.1;FPV_observed=FPV_observed+0.1;FPV_frame=FPV_frame+3;
_r=[_uav,_state] call _tick;
[(_uav call _mode)=="TERMINAL_VECTOR" && {(_uav getVariable "A3UE_FPV_attackRole")=="ATTACK"},"cleared (alone) and into the dive"] call _assert;
[(_state get "hot") && {(_state get "listed")} && {A3UE_FPV_directorStates isEqualTo [_state]},"now the director's"] call _assert;
[(_r # 1) <= 0.021,"asks for the next pass at once"] call _assert;
// Ten frames: one dive pass each, steering written by the same writer as before.
for "_i" from 1 to 10 do {call _frame;};
[(A3UE_FPV_perf # 0)==10 && {count FPV_moves>=9} && {(_uav call _mode)=="TERMINAL_VECTOR"},format ["frames ticked %1, velocity writes %2",A3UE_FPV_perf # 0,count FPV_moves]] call _assert;
[(_uav getVariable ["A3UE_FPV_nativeControl",[]]) isNotEqualTo [],"owns the airframe"] call _assert;
[((_uav getVariable "A3UE_FPV_terminalSteeringState") # 8) in ["INIT","STEP"] && {abs ((_uav getVariable "A3UE_FPV_terminalVectorDt")-0.03) < 0.001},"frame steps, never late"] call _assert;
// The man dies: the same frame's tick drops the dive and hands the airframe back.
_person setVariable ["alive",false];
call _frame;
[(_uav call _mode)=="SEARCHING" && {FPV_restores==1} && {(_uav getVariable ["A3UE_FPV_nativeControl",[1]]) isEqualTo []},"dive dropped atomically"] call _assert;
[!(_state get "hot") && {!(_state get "listed")} && {A3UE_FPV_directorStates isEqualTo []},"back to its scheduled script"] call _assert;
[(_uav getVariable "A3UE_FPV_attackRole")=="" && {(_uav getVariable "A3UE_FPV_wingTarget")==""},"left the board"] call _assert;
private _n=A3UE_FPV_perf # 0;call _frame;[(A3UE_FPV_perf # 0)==_n,"no more director ticks"] call _assert;
''')
        self.assertRegex(out, r'wing target=person event=CLEARED id=uav')
        self.assertRegex(out, r'wing target=person event=TARGET_DROPPED id=uav')

    def test_second_drone_watches_then_attacks_after_the_first_is_gone(self):
        out = self.sqf('''
private _d2=["VMUAV","d2"] call _make;_d2 setVariable ["position",[400,0,50]];
private _s2=[_d2,"d2",3] call _ready;
// First drone: search, then dive.
[_uav,_state] call _tick;FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;[_uav,_state] call _tick;
[(_uav call _mode)=="TERMINAL_VECTOR","first drone dives"] call _assert;
// Second drone: finds the same man, is told to wait, and gets a ring order instead of an attack.
[_d2,_s2] call _tick;FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;
private _r=[_d2,_s2] call _tick;
[(_d2 call _mode)=="TRACKING" && {(_d2 getVariable "A3UE_FPV_attackRole")=="OVERWATCH"},"second drone waits"] call _assert;
[count FPV_moveTo==1 && {FPV_guides isEqualTo []},"one ring order, no attack order"] call _assert;
private _order=FPV_moveTo # 0;
[abs (([_order # 0,_order # 1,0] distance2D [250,0,0])-140) < 0.5 && {(_order # 2)==48},format ["drone 3: the 140 m ring, 30 m floor + 18 m stagger: %1",_order]] call _assert;
[!(_s2 get "hot") && {!(_s2 get "listed")} && {abs ((_r # 1)-0.25) < 0.001},"a waiting drone is not the director's; next pass in 0.25 s at most"] call _assert;
[abs ((_s2 get "nextGuidance")-(FPV_time+0.5)) < 0.001,"overwatch guidance twice a second"] call _assert;
// Its passes while waiting: still waiting, orders at most once a second.
for "_i" from 1 to 4 do {FPV_time=FPV_time+0.5;[_d2,_s2] call _tick;};
[(_d2 getVariable "A3UE_FPV_attackRole")=="OVERWATCH" && {count FPV_moveTo==3},format ["orders %1",count FPV_moveTo]] call _assert;
// The first drone is shot down mid-dive: its own tick ends the attack and starts the delay.
_uav setVariable ["alive",false];
_r=[_uav,_state] call _tick;
[!(_r # 0) && {!(_state get "running")} && {!(_state get "hot")},"controller stopped"] call _assert;
FPV_time=FPV_time+0.5;[_d2,_s2] call _tick;
[(_d2 getVariable "A3UE_FPV_attackRole")=="OVERWATCH","not during the follow-up delay"] call _assert;
FPV_time=FPV_time+3.1;[_d2,_s2] call _tick;
[(_d2 call _mode)=="TERMINAL_VECTOR" && {(_d2 getVariable "A3UE_FPV_attackRole")=="ATTACK"} && {_s2 get "listed"},"then it goes in"] call _assert;
call _frame;
[(A3UE_FPV_directorStates apply {_x get "uav"}) isEqualTo [_d2],"the stopped controller left the director, the new attacker is in"] call _assert;
''')
        self.assertRegex(out, r'event=STOPPED id=uav attackers=0 waiting=1')
        self.assertRegex(out, r'event=CLEARED id=d2')

    def test_waiting_drone_leaves_a_crowded_target_for_a_free_one(self):
        out = self.sqf('''
// Seven drones are on the man already (one attacking, six waiting). A waiting drone gives up
// its target only for a clearly better one: the stay bonuses are worth about five drones.
for "_i" from 1 to 7 do {private _d=["VMUAV",format ["x%1",_i]] call _make;
 {_d setVariable [_x # 0,_x # 1];} forEach [["A3UE_FPV_managed",true],["A3UE_FPV_controllerRunning",true],["A3UE_FPV_mode","TRACKING"],["A3UE_FPV_targetNetId","person"]];
 [_d,_person] call A3UE_fnc_fpv_attackSlot;};
[_uav,_state] call _tick;FPV_time=FPV_time+0.1;[_uav,_state] call _tick;
[(_uav getVariable "A3UE_FPV_attackRole")=="OVERWATCH" && {(_uav getVariable "A3UE_FPV_targetNetId")=="person"},"eighth drone waits on the only target"] call _assert;
// A second man appears. Nothing happens before the drone's retarget time (4-7 s after it began to wait).
private _p2=["VMMan","p2"] call _make;_p2 setVariable ["side",west];_p2 setVariable ["position",[200,100,0]];
FPV_time=FPV_time+2;[_uav,_state] call _tick;
[(_uav getVariable "A3UE_FPV_targetNetId")=="person","not yet"] call _assert;
FPV_time=FPV_time+6;[_uav,_state] call _tick;
[(_uav getVariable "A3UE_FPV_targetNetId")=="p2" && {(_uav call _mode)=="TRACKING"},"left for the free target"] call _assert;
[([_person,objNull] call A3UE_fnc_fpv_attackCrowd)==7 && {(_uav getVariable "A3UE_FPV_targetRevision")==1},"released the old one; new engagement revision"] call _assert;
FPV_time=FPV_time+0.1;[_uav,_state] call _tick;
[(_uav getVariable "A3UE_FPV_attackRole")=="ATTACK" && {(_uav call _mode)=="TERMINAL_VECTOR"},"and attacks it"] call _assert;
''')
        self.assertRegex(out, r'wing id=uav event=RETARGET from=person to=p2')

    def test_switches_restore_the_1_0_3_behaviour(self):
        self.sqf('''
missionNamespace setVariable ["A3UE_FPV_frameDriver",false];
missionNamespace setVariable ["A3UE_FPV_attackersPerTarget",0];
missionNamespace setVariable ["A3UE_FPV_leanBrain",false];
private _d2=["VMUAV","d2"] call _make;private _s2=[_d2,"d2",2] call _ready;
{[_x # 0,_x # 1] call _tick;} forEach [[_uav,_state],[_d2,_s2]];
FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;
private _r=[_uav,_state] call _tick;[_d2,_s2] call _tick;
[(_uav call _mode)=="TERMINAL_VECTOR" && {(_d2 call _mode)=="TERMINAL_VECTOR"},"both dive at once"] call _assert;
[!(_state get "hot") && {!(_state get "listed")} && {A3UE_FPV_directorStates isEqualTo []},"no director: the scheduled script keeps the dive"] call _assert;
[abs ((_r # 1)-0.02) < 0.001,"at its 20 ms request"] call _assert;
[count (missionNamespace getVariable ["A3UE_FPV_attackBoard",createHashMap])==0,"no board"] call _assert;
// 1.0.3 search cadence.
_person setVariable ["alive",false];
FPV_time=FPV_time+0.05;[_uav,_state] call _tick;
[(_uav call _mode)=="SEARCHING","target gone"] call _assert;
FPV_time=FPV_time+0.6;[_uav,_state] call _tick;
[abs ((_state get "nextScan")-(FPV_time+0.35)) < 0.001,"scan every 0.35 s"] call _assert;
missionNamespace setVariable ["A3UE_FPV_leanBrain",true];
FPV_time=FPV_time+0.6;[_uav,_state] call _tick;
[abs ((_state get "nextScan")-(FPV_time+1)) < 0.001,"lean: once a second"] call _assert;
''')

    def test_cleared_attacker_stays_with_the_director_through_its_approach(self):
        self.sqf('''
// Not yet at its dive point: cleared, closing under native guidance.
A3UE_fnc_fpv_shouldEnterTerminal={false};
[_uav,_state] call _tick;FPV_time=FPV_time+0.1;[_uav,_state] call _tick;
[(_uav call _mode)=="TRACKING" && {(_uav getVariable "A3UE_FPV_attackRole")=="ATTACK"} && {count FPV_guides==1},"cleared and closing"] call _assert;
[(_state get "hot") && {_state get "listed"} && {abs ((_state get "nextGuidance")-(FPV_time+0.1)) < 0.001},"the director's, ten guidance passes a second"] call _assert;
// A tick between guidance passes (nothing due but the clock) does not hand it back.
FPV_time=FPV_time+0.05;[_uav,_state] call _tick;
[(_state get "hot") && {count FPV_guides==1},"still hot, no extra order"] call _assert;
// The director ticks it only when it is due: three guidance passes in ten 30 ms frames.
for "_i" from 1 to 10 do {call _frame;};
[count FPV_guides==4 && {(A3UE_FPV_perf # 0) < 10} && {_state get "listed"},format ["orders %1 director ticks %2",count FPV_guides,A3UE_FPV_perf # 0]] call _assert;
// Its dive point comes: the same frame enters the dive.
A3UE_fnc_fpv_shouldEnterTerminal={true};
for "_i" from 1 to 4 do {call _frame;};
[(_uav call _mode)=="TERMINAL_VECTOR" && {_state get "listed"},"dive entered by a director tick"] call _assert;
''')

    def test_deleted_drone_ends_its_controller_state(self):
        self.sqf('''
[_uav,_state] call _tick;FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;[_uav,_state] call _tick;
[(_state get "listed") && {_state get "running"},"diving"] call _assert;
// The airframe is deleted (struck): pacer and director both see a stopped controller.
private _r=[objNull,1,_state] call A3UE_fnc_fpv_runController;
[(_r isEqualTo false) && {!(_state get "running")} && {!(_state get "hot")},"state stopped"] call _assert;
call _frame;
[A3UE_FPV_directorStates isEqualTo [] && {!(_state get "listed")},"dropped by the director"] call _assert;
''')

    def test_external_control_stops_the_dive_in_the_same_tick(self):
        self.sqf('''
[_uav,_state] call _tick;FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;[_uav,_state] call _tick;
call _frame;call _frame;
private _writes=count FPV_moves;
[(_uav call _mode)=="TERMINAL_VECTOR" && {_writes>=1},"diving"] call _assert;
_uav setVariable ["controlled",true];
call _frame;
[(_uav call _mode)=="IDLE" && {count FPV_moves==_writes} && {(_uav getVariable "A3UE_FPV_targetNetId")==""},"a player took it: no write, target dropped"] call _assert;
[!(_state get "listed") && {(_uav getVariable "A3UE_FPV_wingTarget")==""},"off the director and the board"] call _assert;
''')


class WingSource(unittest.TestCase):
    def test_functions_registered_and_present(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in NEW:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)

    def test_sender_fence_comes_first_in_everything_that_writes(self):
        for name in ['attackSlot', 'attackRelease', 'overwatch', 'scanTargets', 'controllerState']:
            prefix = source(name).split('call A3UE_fnc_fpv_helperAccess', 1)[0]
            self.assertNotRegex(prefix, r'\b(setVariable|set|pushBack|enableAI|doMove|addMissionEventHandler)\b', name)
            self.assertEqual(prefix.count('call A3UE_fnc_'), 0, name)

    def test_cost_contracts(self):
        for name in NEW:
            s = code(name)
            self.assertNotRegex(s, r'\b(remoteExec|remoteExecCall|spawn|execVM|sleep|uiSleep|waitUntil|publicVariable|hint|hintSilent|hintC|random)\b', name)
            self.assertNotRegex(s, r'\b(allUnits|allPlayers|vehicles|entities|nearestObjects|nearObjects|nearestTerrainObjects|lineIntersectsSurfaces|terrainIntersectASL)\b', name)
            if name != 'scanTargets':
                self.assertNotIn('nearEntities', s, name)
            if name != 'controllerState':
                self.assertNotIn('addMissionEventHandler', s, name)
        self.assertEqual(code('scanTargets').count('nearEntities'), 1)
        self.assertEqual(code('controllerState').count('addMissionEventHandler ["EachFrame"'), 1)
        # Per frame: no logging, no world queries, no broadcasts; the evidence line is in perfReport.
        director = code('directorFrame')
        self.assertNotRegex(director, r'\b(diag_log|setVariable \[[^\]]*true\]|distance|getPos\w*)\b')
        self.assertIn('if (_states isNotEqualTo []) then {', director)
        self.assertEqual(code('perfReport').count('diag_log'), 1)
        # Nothing new is broadcast except the role, on change.
        for name in NEW:
            self.assertFalse(re.findall(r'setVariable \["[^"]*",[^\]]*,\s*true\]', code(name)), name)
        controller = code('runController')
        self.assertEqual(controller.count('_uav setVariable ["A3UE_FPV_attackRole", _role, true];'), 1)
        self.assertIn('if (_role != (_uav getVariable ["A3UE_FPV_attackRole", ""])) then {', controller)

    def test_pacer_runs_every_pass_as_one_unscheduled_tick(self):
        s = source('runController')
        pacer = s.split('if (count _state == 0) exitWith {', 1)[1].split('// LT-2 tick: one controller pass.', 1)[0]
        self.assertIn('_state = [_uav, _generation] call A3UE_fnc_fpv_controllerState;', pacer)
        self.assertIn('isNil {_sleepFor = ([_uav, _generation, _state] call A3UE_fnc_fpv_runController) param [1, 0.25];};', pacer)
        self.assertIn('if (!(_state get "listed") || {diag_tickTime - (_state get "tickedAt") > 0.5}) then {', pacer)
        self.assertEqual(pacer.count('sleep '), 1)
        tick = s.split('// LT-2 tick: one controller pass.', 1)[1]
        # The tick itself never suspends and no longer loops.
        self.assertNotRegex(re.sub(r'//[^\n]*', '', tick), r'\b(sleep|uiSleep|waitUntil|spawn|execVM|while)\b')
        self.assertIn('private _fpvTick = createHashMap;', tick)
        self.assertIn('if (_running) then {', tick)
        self.assertTrue(tick.rstrip().endswith('[_running, _tickSleep]'))
        for local, key in [('_nextGuidanceTick', 'nextGuidance'), ('_nextTargetScanTick', 'nextScan'), ('_nextLinkEvalTick', 'nextLink'),
                           ('_nextStrikeRetryTick', 'nextStrikeRetry'), ('_nextTargetabilityCheckAt', 'nextTargetability'),
                           ('_targetabilitySuspended', 'targetabilitySuspended'), ('_terminalAIRecoveryPending', 'aiRecoveryPending'),
                           ('_impactCacheReady', 'impactCacheReady'), ('_nextRetargetTick', 'nextRetarget'), ('_wingRole', 'role'),
                           ('_wingHot', 'wingHot')]:
            self.assertIn(f'private {local} = _state get "{key}";', tick)
            self.assertIn(f'_state set ["{key}", {local}];', tick)
            self.assertIn(f'["{key}", ', source('controllerState'))
        # The stopped branch keeps the original owner-fenced epilogue and leaves the board.
        stopped = tick.split('if (!_running) then {', 1)[1]
        self.assertLess(stopped.index('isEqualTo _controllerIdentity}) then {'), stopped.index('[_uav, "STOPPED"] call A3UE_fnc_fpv_attackRelease;'))
        self.assertIn('_state set ["running", false];', stopped)

    def test_director_takes_attacking_drones_only(self):
        tick = source('runController').split('// LT-2 tick: one controller pass.', 1)[1]
        self.assertIn('private _hot = (_wing # 0) && {!isNil "A3UE_FPV_directorHandler"}', tick)
        self.assertIn('{_activeMode in ["TERMINAL_VECTOR", "TERMINAL_ATTACK"] || {_activeMode == "TRACKING" && {_wingRole == "ATTACK"} && {_wingHot}}};', tick)
        tracking = tick.split('case "TRACKING": {', 1)[1].split('case "LOST_TARGET": {', 1)[0]
        overwatch, attack = tracking.split('if (_role == "OVERWATCH") then {', 1)[1].split('} else {', 1)
        self.assertIn('call A3UE_fnc_fpv_overwatch;', overwatch)
        self.assertIn('_wingHot = false;', overwatch)
        self.assertNotRegex(overwatch, r'fpv_(shouldEnterTerminal|applyGuidance|attackEngagement)')
        for term in ['A3UE_fnc_fpv_attackEngagement', 'A3UE_fnc_fpv_shouldEnterTerminal', '_attemptIngress', 'A3UE_fnc_fpv_applyGuidance',
                     '_wingHot = (_uav distance _target) <= 450;']:
            self.assertIn(term, attack)
        self.assertLess(tracking.index('call A3UE_fnc_fpv_attackSlot;'), tracking.index('if (_role == "OVERWATCH") then {'))
        # The dive itself is unchanged: still the LT-1 slice, now reached every frame.
        vector = tick.split('case "TERMINAL_VECTOR": {', 1)[1]
        self.assertIn('_nextGuidanceTick = _now + 0.01;', vector)
        self.assertIn('// LT-1: plan, step and progress share one unscheduled slice', vector)

    def test_lean_rates_and_their_switch(self):
        tick = source('runController').split('// LT-2 tick: one controller pass.', 1)[1]
        self.assertIn('_nextGuidanceTick = _now + (if (_entered) then {0.01} else {[0.05, [0.1, 0.5] select (_role == "OVERWATCH")] select (_wing # 6)});', tick)
        self.assertEqual(tick.count('_nextTargetScanTick = _now + ([0.35, 1] select (_wing # 6));'), 3)
        self.assertIn('_nextGuidanceTick = _now + ([0.08, 0.2] select (_wing # 6));', tick)
        self.assertIn('_nextTargetScanTick = _now + ([0.2, 0.5] select (_wing # 6));', tick)
        self.assertIn("_now + ([0.35, 1] select ((call A3UE_fnc_fpv_wingSettings) # 6))", source('cacheLinkState'))
        link = source('evaluateLinkState')
        self.assertIn('time - (_relayCache # 0) < 10', link)
        self.assertIn('[_positionATL, _controlPosAtl, _familyData, _uav, -1, _relayCache # 2] call A3UE_fnc_fpv_sampleRadioLink', link)
        sample = code('sampleRadioLink')
        self.assertNotIn('setVariable', sample)
        self.assertIn('if (isNil "_knownRetranslators") then {', sample)
        self.assertEqual(sample.count('nearObjects'), 1)

    def test_everything_a_tick_can_reach_never_suspends(self):
        names = set(NEW) | {
            'canActuate', 'resolveTarget', 'filterTarget', 'getHostileSides', 'isSiteDroneActive', 'isExternallyControlled',
            'hasCurrentLifecycle', 'helperAccess', 'publishTelemetry', 'cacheLinkState', 'evaluateLinkState', 'sampleRadioLink',
            'applyTargetability', 'holdPattern', 'selectTarget', 'isTargetObstructed', 'traceAttackRay', 'isAlliedAttacker',
            'supportEngagementReason', 'supportPassesSafetyRing', 'clearTarget', 'runLostTarget', 'applyGuidance', 'computeIntercept',
            'transitHeight', 'obstacleProbe', 'attackClearLine', 'attackEngagement', 'attackApproach', 'shouldEnterTerminal',
            'prepareTrajectory', 'planTrajectory', 'followTrajectory', 'runTerminalVector', 'terminalSteeringStatus',
            'trajectorySteering', 'stepTerminalSteering', 'terminalPresentationUp', 'trajectoryLimits', 'attackLimits',
            'attackSettings', 'attackPass', 'attackPassSummary', 'attackAimOffset', 'attackNavigation', 'attackReversal',
            'targetNavigation', 'resolveImpactPoint', 'emptyImpactSolution', 'shouldDetonateNow', 'evaluateImpactWindow',
            'detonateCompat', 'getClassDescriptor', 'sendLifecycle', 'controllerSleep', 'profileValue'}
        for name in sorted(names):
            s = re.sub(r'//[^\n]*', '', source(name))
            self.assertNotRegex(s, r'\b(sleep|uiSleep|waitUntil|execVM)\b', name)
            if name not in ('controllerState',):
                self.assertNotRegex(s, r'\bspawn\b', name)
        # Every A3UE helper the controller calls is in that list (so a new call cannot slip past it).
        called = set(re.findall(r'A3UE_fnc_fpv_(\w+)', source('runController'))) - {'runController', 'lifecycleAccess'}
        self.assertFalse(called - names, called - names)

    def test_selection_and_target_drop_hooks(self):
        select = source('selectTarget')
        self.assertIn('[_siteKey, _scanCenter, _siteScanRadius, 1.5, _hostileSides] call A3UE_fnc_fpv_scanTargets', select)
        self.assertIn('if (((_localScanCenter distance2D _scanCenter) + _localRadius) > _siteScanRadius) then {', select)
        self.assertIn('format ["%1/%2", _siteMarker, _siteScanRadius]', select)
        self.assertIn('- _losPenalty - _obstructionPenalty - _crowdPenalty;', select)
        legacy = select.split('} else {\n\t_candidateObjects = ["A3UE_FPV_siteCandidateCache"', 1)[1]
        self.assertIn('["A3UE_FPV_localCandidateCache", _localScanCenter, _localRadius, 0.25] call _getCandidates', legacy)
        clear = source('clearTarget')
        self.assertLess(clear.index('call A3UE_fnc_fpv_helperAccess'), clear.index('[_uav, "TARGET_DROPPED"] call A3UE_fnc_fpv_attackRelease;'))
        self.assertLess(clear.index('A3UE_fnc_fpv_attackRelease'), clear.index('_uav setVariable ["A3UE_FPV_targetNetId", "", true];'))

    def test_overwatch_is_a_native_order_behind_the_same_fences_as_guidance(self):
        s = source('overwatch')
        boundary = s.index('private _applied = false;\nisNil {')
        self.assertNotRegex(s[:boundary], r'\b(enableAI|disableAI|setVelocity|setVectorDirAndUp|doMove|forceSpeed|flyInHeight)\b')
        effect = s[boundary:]
        self.assertLess(effect.index('call A3UE_fnc_fpv_canActuate'), re.search(r'\b(enableAI|doMove)\b', effect).start())
        for fence in ['(_uav getVariable ["A3UE_FPV_mode", ""]) != "TRACKING"', '"A3UE_FPV_nativeControl"',
                      'isNotEqualTo _targetNetId', '!= _targetRevision', 'call A3UE_fnc_fpv_supportEngagementReason']:
            self.assertLess(effect.index(fence), effect.index('_uav doMove _moveTargetAtl;'), fence)
        self.assertNotRegex(s, r'\b(setVelocity|setVectorDirAndUp|setPos\w*)\b')
        self.assertIn('time - (_order # 0) >= 1', effect)
        self.assertIn('_uav setVariable ["A3UE_FPV_lastMoveUpdate", -1];', effect)
        # Callers hand the helpers their original identity the way applyGuidance gets it.
        self.assertIn('private _helperIdentity = if (isNil "_controllerIdentity") then {', s)


if __name__ == '__main__':
    unittest.main()
