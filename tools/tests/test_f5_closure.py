"""F5 closure: owned crew and groups, consumption accounting, kill-credit timing, sender fences,
support refusal evidence and LS-03 crew metadata.

Shipped SQF runs in SQF-VM with explicit substitutes for engine group/crew commands: groups are
VM objects, a unit's group/vehicle are object variables, and VM deleteVehicle is immediate (the
engine's completes at the end of the frame; the sweep's later passes cover that). This is
decision/bookkeeping evidence only: it does not qualify engine group deletion timing, AU's event
handlers, vendor scripts or the hosted economy (the F5 engine card does).
"""
import re
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, engine_substitutes
from test_f2cl_field_fixes import run_vm

PRELUDE = r'''
FPV_time=100; FPV_observed=200; FPV_frame=100; FPV_sender=2; FPV_jip=false; FPV_remote=false; FPV_isServer=true;
FPV_finite={_this isEqualType 0 && {abs _this < 1e38}};
FPV_getOrDefault={params ["_map","_args"];if ((_args # 0) in _map) then {_map get (_args # 0)} else {_args # 1}};
FPV_setVariable={params ["_o","_args"];_o setVariable [_args # 0,_args # 1];};
FPV_alive={!isNull _this && {_this getVariable ["alive",true]}};
FPV_local={_this getVariable ["local",true]};
FPV_crew={(_this getVariable ["crew",[]]) select {!isNull _x}};
FPV_group={if (isNull _this) then {objNull} else {_this getVariable ["group", objNull]}};
FPV_objectParent={if (isNull _this) then {objNull} else {_this getVariable ["parent", objNull]}};
FPV_effectiveCommander={((_this getVariable ["crew",[]]) select {!isNull _x}) param [0, objNull]};
FPV_netId={if (isNull _this) then {""} else {_this getVariable ["netId",""]}};
FPV_velocity={_this getVariable ["velocity",[0,0,0]]};
FPV_world=[]; FPV_deletedGroups=[]; FPV_groupLimit=false; FPV_crewCreated=0;
FPV_units={private _g=_this; FPV_world select {!isNull _x && {(_x getVariable ["group", objNull]) isEqualTo _g}}};
FPV_newGroup={params ["_name"]; private _g = "VMVehicle" createVehicle [0,0,0]; _g setVariable ["name", _name]; _g};
FPV_createGroup={if (FPV_groupLimit) then {grpNull} else {private _g = ["new"] call FPV_newGroup; _g setVariable ["deleteWhenEmpty", _this # 1]; _g}};
FPV_createVehicleCrew={
  private _uav=_this; private _g=["engine"] call FPV_newGroup; private _c=[];
  for "_i" from 1 to (_uav getVariable ["crewSlots", 1]) do {
    private _u="VMVehicle" createVehicle [0,0,0]; _u setVariable ["group",_g]; _u setVariable ["parent",_uav];
    _u setVariable ["class", "B_UAV_AI"]; FPV_world pushBack _u; _c pushBack _u; FPV_crewCreated=FPV_crewCreated+1;
  };
  _uav setVariable ["crew",_c]; _g
};
FPV_joinSilent={params ["_units","_g"]; {_x setVariable ["group",_g];} forEach _units;};
FPV_deleteGroup={FPV_deletedGroups pushBack (_this getVariable ["name",""]); deleteVehicle _this;};
FPV_markWhenEmpty={params ["_g","_on"]; _g setVariable ["deleteWhenEmpty",_on];};
private _assert={params ["_ok","_label"];if (!_ok) then {throw _label;};};
private _unit={params ["_group", ["_parent", objNull], ["_alive", true], ["_pool", "legacy"]];
  private _u="VMVehicle" createVehicle [0,0,0]; _u setVariable ["group",_group]; _u setVariable ["parent",_parent];
  _u setVariable ["alive",_alive]; _u setVariable ["A3A_resPool",_pool]; FPV_world pushBack _u; _u};
'''

COMMON = [
    (r'\bisServer\b', 'FPV_isServer'),
    (r'createGroup \[_side, true\]', '([_side, true] call FPV_createGroup)'),
    (r'createVehicleCrew _uav;', '(_uav call FPV_createVehicleCrew);'),
    (r'_crew joinSilent _group;', '[_crew, _group] call FPV_joinSilent;'),
    (r'_group selectLeader \(effectiveCommander _uav\);', ''),
    (r'_group addVehicle _uav;', ''),
    (r'deleteGroup _x;', '(_x call FPV_deleteGroup);'),
    (r'(_\w+) deleteGroupWhenEmpty true;', r'[\1, true] call FPV_markWhenEmpty;'),
    (r'\(units _x\)', '(_x call FPV_units)'),
    (r'_x isEqualType grpNull', '_x isEqualType objNull'),
    (r'damage _uav', '(_uav getVariable ["damage", 0])'),
    (r'_uav setDamage \[0, false\];', '_uav setVariable ["damage", 0];'),
    (r'\bsurfaceIsWater (_\w+)', r'(\1 call FPV_water)'),
    (r'typeOf _x', '(_x getVariable ["class", ""])'),
]


def adapt(name):
    s = (FPV / f'fn_fpv_{name}.sqf').read_text()
    for old, new in COMMON:
        s = re.sub(old, new, s)
    return engine_substitutes(s)


def code(name):
    return '\n'.join(line.split('//', 1)[0] for line in (FPV / f'fn_fpv_{name}.sqf').read_text().splitlines())


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class F5ClosureSQF(unittest.TestCase):
    def vm(self, names, body, real_access=False):
        script = PRELUDE
        if not real_access:
            script += 'A3UE_fnc_fpv_helperAccess={true};\n'
        for name in names:
            script += f'A3UE_fnc_fpv_{name}={{{adapt(name)}}};\n'
        r = run_vm(script + body + '\ndiag_log "F5_TEST_OK";')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('F5_TEST_OK', r.stdout, r.stdout[-3000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-3000:])
        return r.stdout

    # ---- C1/C2: owned crew group -------------------------------------------------------
    def test_owned_crew_group_and_engine_group_deleted(self):
        self.vm(['createUavCrew'], r'''
private _uav = "VMUAV" createVehicle [0,0,0]; _uav setVariable ["crewSlots", 2];
private _g = [west, _uav] call A3UE_fnc_fpv_createUavCrew;
private _crew = _uav call FPV_crew;
[count _crew == 2 && {FPV_crewCreated == 2}, "engine crew created once"] call _assert;
[(_g getVariable ["name", ""]) == "new" && {_g getVariable ["deleteWhenEmpty", false]}, "a new delete-when-empty group of the side"] call _assert;
[(_crew findIf {!((_x getVariable ["group", objNull]) isEqualTo _g)}) < 0, "every crew member joined it"] call _assert;
[FPV_deletedGroups isEqualTo ["engine"], format ["the emptied engine group is deleted at once %1", FPV_deletedGroups]] call _assert;
[(_uav getVariable ["A3UE_FPV_crewGroups", []]) isEqualTo [], "nothing left over to hand on"] call _assert;
// Membership still settling: the engine group is not empty yet, so it is marked and handed to the sweep.
FPV_joinSilent = {params ["_units", "_g"]; {_x setVariable ["pendingGroup", _g];} forEach _units;};
FPV_deletedGroups = [];
private _slow = "VMUAV" createVehicle [0,0,0];
private _gs = [west, _slow] call A3UE_fnc_fpv_createUavCrew;
private _handed = _slow getVariable ["A3UE_FPV_crewGroups", []];
[FPV_deletedGroups isEqualTo [] && {count _handed == 1} && {((_handed # 0) getVariable ["name", ""]) == "engine"}
  && {(_handed # 0) getVariable ["deleteWhenEmpty", false]}, format ["handed to the sweep %1", _handed]] call _assert;
FPV_joinSilent = {params ["_units","_g"]; {_x setVariable ["group",_g];} forEach _units;};
// An already crewed UAV gets no second crew.
private _uav2 = "VMUAV" createVehicle [0,0,0]; _uav2 setVariable ["crewSlots", 1];
(_uav2 call FPV_createVehicleCrew);
FPV_crewCreated = 0; FPV_deletedGroups = [];
private _g2 = [east, _uav2] call A3UE_fnc_fpv_createUavCrew;
[FPV_crewCreated == 0 && {count (_uav2 call FPV_crew) == 1} && {FPV_deletedGroups isEqualTo ["engine"]}, "existing crew reused"] call _assert;
// At the group limit the crew stay in the engine group, which is marked, never deleted.
FPV_groupLimit = true; FPV_deletedGroups = [];
private _uav3 = "VMUAV" createVehicle [0,0,0];
private _g3 = [west, _uav3] call A3UE_fnc_fpv_createUavCrew;
[(_g3 getVariable ["name", ""]) == "engine" && {_g3 getVariable ["deleteWhenEmpty", false]} && {FPV_deletedGroups isEqualTo []}, "group limit fallback"] call _assert;
FPV_groupLimit = false;
// No crew possible, bad input, or a refused sender: no group and nothing created.
private _empty = "VMUAV" createVehicle [0,0,0]; _empty setVariable ["crewSlots", 0];
[isNull ([west, _empty] call A3UE_fnc_fpv_createUavCrew), "no crew"] call _assert;
[isNull ([west, objNull] call A3UE_fnc_fpv_createUavCrew) && {isNull (["west", _empty] call A3UE_fnc_fpv_createUavCrew)}, "bad input"] call _assert;
''')

    # ---- C1/C3: sweep ----------------------------------------------------------------
    def test_sweep_deletes_groups_and_orphans_only(self):
        out = self.vm(['sweepCrew'], r'''
// Strike retirement: crew already deleted with the airframe, two empty local groups remain.
private _g1 = ["crewA"] call FPV_newGroup; private _g2 = ["engineA"] call FPV_newGroup;
private _gone = [_g1] call _unit; deleteVehicle _gone;
private _r = [[_gone], [_g1, _g2], "2:10", 20, 0] call A3UE_fnc_fpv_sweepCrew;
[_r isEqualTo [0, 2, 0] && {isNull _g1} && {isNull _g2}, format ["groups deleted on the first pass %1", _r]] call _assert;
// KVN's native detonation deleted only the airframe: two live crew outside any vehicle are orphans.
private _g3 = ["crewB"] call FPV_newGroup;
private _o1 = [_g3] call _unit; private _o2 = [_g3] call _unit;
_r = [[_o1, _o2], [_g3], "2:11", 20, 0] call A3UE_fnc_fpv_sweepCrew;
[_r isEqualTo [2, 1, 0] && {isNull _o1} && {isNull _o2} && {isNull _g3}, format ["orphans then their group %1", _r]] call _assert;
// Dead crew (killed with the airframe) are AU's post-mortem's: never deleted, group kept.
private _g4 = ["crewC"] call FPV_newGroup;
private _dead = [_g4, objNull, false] call _unit;
_r = [[_dead], [_g4], "2:12", 3, 0] call A3UE_fnc_fpv_sweepCrew;
[_r isEqualTo [0, 0, 1] && {!isNull _dead} && {!isNull _g4}, format ["dead crew left to AU %1", _r]] call _assert;
// A crew member still inside some vehicle, and a group local elsewhere, are not touched.
private _g5 = ["crewD"] call FPV_newGroup; _g5 setVariable ["local", false];
private _host = "VMVehicle" createVehicle [0,0,0];
private _seated = [_g5, _host] call _unit;
_r = [[_seated], [_g5], "2:13", 2, 0] call A3UE_fnc_fpv_sweepCrew;
[_r isEqualTo [0, 0, 1] && {!isNull _seated} && {!isNull _g5}, format ["seated crew, remote group %1", _r]] call _assert;
// Server only, typed input, bounded lists.
FPV_isServer = false;
[([[], [], "x"] call A3UE_fnc_fpv_sweepCrew) isEqualTo [0, 0, -1], "server only"] call _assert;
FPV_isServer = true;
[([objNull, [], "x"] call A3UE_fnc_fpv_sweepCrew) isEqualTo [0, 0, -1], "typed input"] call _assert;
''')
        # Orphans and leftovers are always logged; a clean sweep only with debug.
        lines = [l for l in out.splitlines() if 'crewCleanup' in l]
        self.assertEqual(len(lines), 3, lines)
        self.assertIn('id=2:11 crewDeleted=2 groupsDeleted=1 groupsLeft=0', lines[0])
        self.assertIn('groupsLeft=1', lines[1])

    # ---- A1: consumption -------------------------------------------------------------
    def test_consumption_switches_only_prepaid_assets(self):
        self.vm(['consumePool'], r'''
private _g = ["crew"] call FPV_newGroup;
private _uav = "VMUAV" createVehicle [0,0,0]; _uav setVariable ["A3A_resPool", "attack"]; _uav setVariable ["damage", 0.3];
private _c1 = [_g, _uav, true, "attack"] call _unit; private _c2 = [_g, _uav, true, "attack"] call _unit;
_uav setVariable ["crew", [_c1]]; _uav setVariable ["A3UE_FPV_crewUnits", [_c1, _c2]];
[([_uav] call A3UE_fnc_fpv_consumePool) == 3, "airframe and both crew (current and recorded)"] call _assert;
[([_uav, _c1, _c2] findIf {(_x getVariable ["A3A_resPool", ""]) != "legacy"}) < 0, "all now legacy"] call _assert;
[(_uav getVariable ["damage", 1]) == 0, "a prepaid airframe's damage is cleared (no legacy d*C)"] call _assert;
// Site stock is legacy already (AU-02): nothing changes, damage stays.
private _site = "VMUAV" createVehicle [0,0,0]; _site setVariable ["A3A_resPool", "legacy"]; _site setVariable ["damage", 0.4];
private _sc = [_g, _site, true, "legacy"] call _unit; _site setVariable ["crew", [_sc]];
[([_site] call A3UE_fnc_fpv_consumePool) == 0 && {(_site getVariable ["damage", 0]) == 0.4}, "site stock untouched"] call _assert;
// A defence-paid airframe that is not local switches pool but its damage is left alone.
private _remote = "VMUAV" createVehicle [0,0,0]; _remote setVariable ["A3A_resPool", "defence"]; _remote setVariable ["local", false]; _remote setVariable ["damage", 0.2];
[([_remote] call A3UE_fnc_fpv_consumePool) == 1 && {(_remote getVariable ["damage", 0]) == 0.2}, "remote airframe"] call _assert;
[([objNull] call A3UE_fnc_fpv_consumePool) == 0, "null"] call _assert;
''')

    # ---- S1: sender fences -------------------------------------------------------------
    def test_client_rpc_cannot_reach_new_or_f4_helpers(self):
        script_access = (FPV / 'fn_fpv_helperAccess.sqf').read_text()
        lifecycle = (FPV / 'fn_fpv_lifecycleAccess.sqf').read_text()
        extra = (f'A3UE_fnc_fpv_lifecycleAccess={{{engine_substitutes(re.sub(r"[!]?isServer", lambda m: "!FPV_isServer" if m.group().startswith("!") else "FPV_isServer", lifecycle))}}};\n'
                 f'A3UE_fnc_fpv_helperAccess={{{engine_substitutes(script_access)}}};\n'
                 'FPV_water={false};\n')
        self.vm(['launchSlot', 'consumePool', 'sweepCrew', 'createUavCrew'], extra + r'''
private _uav = "VMUAV" createVehicle [0,0,0]; _uav setVariable ["A3A_resPool", "attack"];
// A client's RPC (sender 5) is refused before any state change.
FPV_remote = true; FPV_sender = 5;
[([[10, 10, 35], 0] call A3UE_fnc_fpv_launchSlot) isEqualTo [[10, 10, 35], 0]
  && {(missionNamespace getVariable ["A3UE_FPV_launchSlots", []]) isEqualTo []}, "launchSlot refused"] call _assert;
[([_uav] call A3UE_fnc_fpv_consumePool) == 0 && {(_uav getVariable ["A3A_resPool", ""]) == "attack"}, "consumePool refused"] call _assert;
private _g = ["crew"] call FPV_newGroup;
[([[], [_g], "x"] call A3UE_fnc_fpv_sweepCrew) isEqualTo [0, 0, -1] && {!isNull _g}, "sweepCrew refused"] call _assert;
[isNull ([west, _uav] call A3UE_fnc_fpv_createUavCrew) && {FPV_crewCreated == 0}, "createUavCrew refused"] call _assert;
// JIP replay is refused even from the server.
FPV_sender = 2; FPV_jip = true;
[([_uav] call A3UE_fnc_fpv_consumePool) == 0, "JIP refused"] call _assert;
// The server's own forwarded call and a local call pass.
FPV_jip = false;
[([_uav] call A3UE_fnc_fpv_consumePool) == 1, "server-originated call"] call _assert;
FPV_remote = false;
[(([[10, 10, 35], 0] call A3UE_fnc_fpv_launchSlot) # 1) == 0 && {count (missionNamespace getVariable ["A3UE_FPV_launchSlots", []]) == 1}, "local call"] call _assert;
''', real_access=True)

    # ---- UA adapter --------------------------------------------------------------------
    def test_ua_native_destroy_logs_and_consumes_first(self):
        installer = (FPV / 'fn_fpv_installUaPayloadAdapter.sqf').read_text().replace('isServer', 'FPV_isServer')
        extra = f'A3UE_fnc_fpv_installUaPayloadAdapter={{{engine_substitutes(installer)}}};\n'
        self.vm([], extra + r'''
FPV_events = [];
UA_fnc_fpv_canChangePayload = {true}; UA_fnc_fpv_serverChangePayload = {objNull};
UA_fnc_fpv_onDestroy = {FPV_events pushBack ["NATIVE", +_this]; "native"};
UA_fnc_fpv_getPayloadType = {(_this # 0) getVariable ["payload", "OG7V"]};
A3UE_fnc_fpv_logDroneLoss = {FPV_events pushBack ["LOSS", +_this]; true};
A3UE_fnc_fpv_consumePool = {FPV_events pushBack ["CONSUME", +_this]; 1};
[call A3UE_fnc_fpv_installUaPayloadAdapter, "both payload service guards still decide the result"] call _assert;
[missionNamespace getVariable ["A3UE_FPV_uaDestroyAdapterInstalled", false], "destroy adapter installed"] call _assert;
call A3UE_fnc_fpv_installUaPayloadAdapter;
private _uav = "VMUAV" createVehicle [0,0,0]; _uav setVariable ["netId", "2:50"]; _uav setVariable ["A3UE_FPV_managed", true];
private _shooter = "VMVehicle" createVehicle [0,0,0];
A3UE_FPV_lifecycleIndex = createHashMapFromArray [["2:50", 4]];
[([_uav, _shooter, 0.3, objNull] call UA_fnc_fpv_onDestroy) == "native", "native result returned"] call _assert;
[FPV_events isEqualTo [["LOSS", [_uav, _shooter, objNull, 4, "UA_HIT"]], ["CONSUME", [_uav]], ["NATIVE", [_uav, _shooter, 0.3, objNull]]],
  format ["loss line with the shooter, then consumption, then UA's own detonation %1", FPV_events]] call _assert;
// UA will not detonate: non-explosive payload, no hit damage, already detonated, settling touch.
{
  _x params ["_label", "_setup", "_args"];
  FPV_events = [];
  private _d = "VMUAV" createVehicle [0,0,0]; _d setVariable ["A3UE_FPV_managed", true];
  [_d] call _setup;
  ([_d] + _args) call UA_fnc_fpv_onDestroy;
  [count FPV_events == 1 && {((FPV_events # 0) # 0) == "NATIVE"}, format ["%1: native only %2", _label, FPV_events]] call _assert;
} forEach [
  ["payload", {(_this # 0) setVariable ["payload", "AKS74"]}, [_shooter, 0.3, objNull]],
  ["no damage", {}, [_shooter, 0, objNull]],
  ["detonated", {(_this # 0) setVariable ["UA_FPV_Detonated", true]}, [_shooter, 0.3, objNull]],
  ["protected", {(_this # 0) setVariable ["UA_FPV_PayloadSwapProtected", true]}, [_shooter, 0.3, objNull]],
  ["settling", {(_this # 0) setVariable ["UA_FPV_PayloadSpawnSettling", true]}, [objNull, 0.3, objNull]],
  ["unmanaged", {(_this # 0) setVariable ["A3UE_FPV_managed", false]}, [_shooter, 0.3, objNull]]
];
// Odd argument types never break the native path; a client consumes but does not write the line.
FPV_events = []; FPV_isServer = false;
private _odd = "VMUAV" createVehicle [0,0,0]; _odd setVariable ["A3UE_FPV_managed", true];
[_odd, "x", 0.5, 7] call UA_fnc_fpv_onDestroy;
[FPV_events isEqualTo [["CONSUME", [_odd]], ["NATIVE", [_odd, "x", 0.5, 7]]], format ["client owner %1", FPV_events]] call _assert;
''')


    # ---- F5-1b: site-queue probe (diagnostics, read-only) ---------------------------------
    def test_site_queue_probe_snapshot(self):
        global COMMON
        saved = COMMON
        COMMON = COMMON + [
            (r'\bdiag_activeSQFScripts\b', 'FPV_activeScripts'),
            (r'scriptDone _worker', '(_worker getVariable ["done", false])'),
            (r'\bscriptNull\b', 'objNull'),
        ]
        try:
            self.vm(['siteQueueProbe'], r'''
FPV_activeScripts = [["A3UE_FPV_siteMonitor", "m.sqf", true, 9], ["A3UE_FPV_siteWorker", "w.sqf", true, 31], ["other", "o.sqf", true, 1]];
private _worker = "VMVehicle" createVehicle [0,0,0];
A3UE_FPV_siteWorker = _worker;
A3UE_FPV_siteBeat = [FPV_observed - 2.04, 41];
A3UE_FPV_siteLastResult = [true, FPV_observed - 1];
A3UE_FPV_siteStage = ["drone", "Outpost_7", FPV_observed - 3, 1, 2];
A3UE_FPV_spawnStage = ["vehInit", "2:5857", FPV_observed - 3, 12, "AIVEHINIT"];
A3UE_FPV_siteLastTxn = ["txn", "Outpost_7", FPV_observed - 4, "active", 1, -1];
A3UE_FPV_siteQueue = createHashMapFromArray [["Outpost_7", true]];
A3UE_FPV_siteTracked = createHashMapFromArray [["Outpost_7", true]];
A3UE_FPV_registrationComplete = true; serverInitDone = true; A3UE_FPV_siteReady = true;
spawner = "VMVehicle" createVehicle [0,0,0]; sidesX = "VMVehicle" createVehicle [0,0,0];
Occupants = west; Invaders = east; airportsX = []; outposts = []; resourcesX = [];
private _p = call A3UE_fnc_fpv_siteQueueProbe;
[count _p == 15 && {(_p # 0) == "SITEQ"}, format ["shape %1", _p]] call _assert;
[(_p # 1) == 2 && {(_p # 2) == 41} && {(_p # 3) isEqualTo true} && {(_p # 4) == 1}, format ["beat and result %1", _p]] call _assert;
[(_p # 5) isEqualTo ["drone", "Outpost_7", 3, 1, 2], format ["site stage as an age %1", _p # 5]] call _assert;
[(_p # 6) isEqualTo ["vehInit", "2:5857", 3, 12, "AIVEHINIT"], format ["spawn stage %1", _p # 6]] call _assert;
[(_p # 7) isEqualTo ["txn", "Outpost_7", 4, "active", 1, -1], format ["last transaction %1", _p # 7]] call _assert;
[(_p # 8) isEqualTo false && {(_p # 9) isEqualTo [["A3UE_FPV_siteWorker", "w.sqf", true, 31]]}, format ["worker %1 %2", _p # 8, _p # 9]] call _assert;
[(_p # 10) isEqualTo ["Outpost_7"] && {(_p # 11) isEqualTo ["Outpost_7"]}, "queue and tracked keys"] call _assert;
[(_p # 12) isEqualTo [true, true, true, true, true, true, true] && {(_p # 13) isEqualTo true}, format ["preflight %1", _p # 12]] call _assert;
// Read-only: the breadcrumbs keep their ticks.
[(A3UE_FPV_siteStage # 2) == FPV_observed - 3 && {(A3UE_FPV_siteLastTxn # 2) == FPV_observed - 4}, "probe copies, never writes"] call _assert;
// A dead worker and missing preflight inputs are reported, not hidden.
_worker setVariable ["done", true]; FPV_activeScripts = [];
serverInitDone = false; Invaders = civilian;
_p = call A3UE_fnc_fpv_siteQueueProbe;
[(_p # 8) isEqualTo true && {(_p # 9) isEqualTo []} && {(_p # 12) isEqualTo [true, false, true, true, true, false, true]}, format ["dead worker %1", _p]] call _assert;
// Server only, never for a client RPC.
FPV_remote = true; FPV_sender = 7;
[(call A3UE_fnc_fpv_siteQueueProbe) isEqualTo [], "client RPC refused"] call _assert;
FPV_remote = false; FPV_isServer = false;
[(call A3UE_fnc_fpv_siteQueueProbe) isEqualTo [], "not on a client"] call _assert;
''')
            # Nothing recorded yet (a fresh VM: SQF-VM keeps nil-assigned variables).
            self.vm(['siteQueueProbe'], r'''
A3UE_FPV_registrationComplete = true; spawner = "VMVehicle" createVehicle [0,0,0]; sidesX = "VMVehicle" createVehicle [0,0,0];
Occupants = west; Invaders = civilian; airportsX = []; outposts = []; resourcesX = []; FPV_activeScripts = [];
private _p = call A3UE_fnc_fpv_siteQueueProbe;
[(_p select [1, 13]) isEqualTo [-1, -1, "none", -1, [], [], [], "none", [], [], [], [true, false, true, true, true, false, true], false], format ["empty %1", _p]] call _assert;
''')
        finally:
            COMMON = saved


class F5ClosureSource(unittest.TestCase):
    NEW = ['createUavCrew', 'sweepCrew', 'consumePool']
    FENCED = ['attackEngagement', 'attackPass', 'attackNavigation', 'attackReversal', 'attackApproach',
              'transitHeight', 'attackClearLine', 'launchSlot', 'logDroneLoss'] + NEW

    def test_registered(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in self.NEW:
            self.assertIn(f'class fpv_{name} {{}};', config)

    def test_fence_is_the_first_check_after_params(self):
        for name in self.FENCED:
            s = code(name)
            after = s.split('params ', 1)[1]
            after = after.split('];', 1)[1].lstrip()
            self.assertTrue(after.startswith('if !(call A3UE_fnc_fpv_helperAccess) exitWith {'), name)

    def test_new_helpers_are_cheap_and_local(self):
        for name in self.NEW:
            s = code(name)
            self.assertNotRegex(s, r'\b(allUnits|allGroups|vehicles|entities|nearEntities|nearestObjects|allDeadMen)\b', name)
            self.assertNotRegex(s, r'\b(remoteExec|remoteExecCall|publicVariable|addEventHandler|addMissionEventHandler|random)\b', name)
        sweep = code('sweepCrew')
        self.assertIn('select [0, 8]', sweep)
        self.assertIn('for "_pass" from 1 to (_passes max 1) do {', sweep)
        self.assertIn('if (canSuspend && {_interval > 0}) then {sleep _interval;};', sweep)

    def test_spawn_owns_crew_and_records_it(self):
        s = code('spawnManagedDrone')
        self.assertIn('_crewGroup = [_side, _uav] call A3UE_fnc_fpv_createUavCrew;', s)
        self.assertLess(s.index('if (unitIsUAV _uav) then {'), s.index('A3UE_fnc_fpv_createUavCrew'))
        stamp = s.index('_x setVariable ["unitType", typeOf _x, true];')
        self.assertLess(s.index('if (_vehicleInitMode isEqualTo "AIVEHINIT") then {'), stamp)
        self.assertLess(stamp, s.index('[_uav, _crewGroup, _resourcePool] call (_spec get "postCrewInit");'))
        record = s.index('_uav setVariable ["A3UE_FPV_crewGroups", _crewGroups];')
        self.assertIn('private _crewGroups = (_uav getVariable ["A3UE_FPV_crewGroups", []]) select {!isNull _x};', s)
        self.assertLess(s.index('case "AIVEHINIT": {'), record)
        self.assertNotIn('crewFactory', code('managerSpawnDrone'))

    def test_deletion_starts_the_sweep(self):
        deleted = code('registerLifecycle').split('"Deleted"', 1)[1].split('"MPKilled"', 1)[0]
        sweep = deleted.index('[_crew, +_crewGroups, netId _vehicle] spawn A3UE_fnc_fpv_sweepCrew;')
        self.assertLess(deleted.index('if (isServer && {_crewGroups isNotEqualTo []}) then {'), sweep)
        self.assertLess(sweep, deleted.index('[_id, "delete"] call A3UE_fnc_fpv_endLifecycle;'))

    def test_commit_consumes_and_keeps_the_shot_parent(self):
        commit = code('commitDetonation')
        consume = commit.index('[_uav] call A3UE_fnc_fpv_consumePool;')
        self.assertLess(commit.index('_uav setVariable ["A3UE_FPV_detonationCommitted", true];'), consume)
        self.assertLess(consume, commit.index('triggerAmmo _missile;'))
        self.assertLess(consume, commit.index('[_uav] call A3UE_fnc_fpv_cleanupDrone;'))
        worker = code('cleanupDrone').split('[_uav] spawn {', 1)[1]
        delay = worker.index('if (_uav getVariable ["A3UE_FPV_detonationCommitted", false]) then {sleep 1.5;};')
        self.assertLess(delay, worker.index('while {!isNull _uav} do {'))

    def test_native_destroy_adapters_consume_before_native(self):
        kvn = code('installKvnArchiveAdapter').split('DB_kvn_fnc_fpv_onDestroy = {', 1)[1]
        consume = kvn.index('[_uav] call A3UE_fnc_fpv_consumePool;')
        self.assertLess(kvn.index('"KVN_HIT"] call A3UE_fnc_fpv_logDroneLoss;'), consume)
        self.assertLess(consume, kvn.index('_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeOnDestroy");\n\t\tif (!isNull _uav)'))
        ua = code('installUaPayloadAdapter').split('UA_fnc_fpv_onDestroy isEqualType {}', 1)[1]
        self.assertLess(ua.index('"UA_HIT"] call A3UE_fnc_fpv_logDroneLoss;'), ua.index('[_uav] call A3UE_fnc_fpv_consumePool;'))
        self.assertLess(ua.index('[_uav] call A3UE_fnc_fpv_consumePool;'), ua.index('_this call (missionNamespace getVariable "A3UE_FPV_uaNativeOnDestroy")'))
        # The installer's result is still the two payload-service guards only.
        tail = code('installUaPayloadAdapter').rstrip().splitlines()[-2:]
        self.assertIn('A3UE_FPV_uaPayloadUiAdapterInstalled', tail[0])
        self.assertIn('A3UE_FPV_uaPayloadServerAdapterInstalled', tail[1])

    def test_support_refusals_are_logged(self):
        sup = (FPV / 'au_support/fn_SUP_FPV.sqf').read_text()
        failure = sup.split('private _supportFailure = {', 1)[1].split('};', 1)[0]
        self.assertIn('diag_log format ["[A3UE_FPV] supportRefused name=%1 side=%2 pool=%3 reason=%4 target=%5",', failure)
        self.assertNotRegex(sup, r'\bhint(Silent|C)?\b')


    # ---- F5-1b: site-queue diagnostics (no behaviour change) ------------------------------
    def test_site_queue_probe_registered_and_read_only(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        self.assertIn('class fpv_siteQueueProbe {};', config)
        probe = code('siteQueueProbe')
        first = [line for line in probe.splitlines() if line.strip()][0]
        self.assertEqual(first, 'if (!isServer || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {[]};')
        self.assertNotRegex(probe, r'\b(setVariable|publicVariable|remoteExec|remoteExecCall|terminate|spawn|execVM|deleteAt|pushBack|sleep|waitUntil|diag_log)\b')
        self.assertNotIn(' set [', probe.replace('_copy set [2,', ''))

    def test_site_worker_is_named_with_heartbeat_and_unchanged_cadence(self):
        hooks = code('installSiteHooks')
        worker = hooks.split('missionNamespace setVariable ["A3UE_FPV_siteWorker", [] spawn {', 1)[1].split('}];', 1)[0]
        self.assertIn('scriptName "A3UE_FPV_siteWorker";', worker)
        beat = worker.index('missionNamespace setVariable ["A3UE_FPV_siteBeat", [diag_tickTime, _passes]];')
        call = worker.index('private _result = [call A3UE_fnc_fpv_processSiteQueue] param [0, "nil"];')
        result = worker.index('missionNamespace setVariable ["A3UE_FPV_siteLastResult", [_result, diag_tickTime]];')
        self.assertLess(beat, call)
        self.assertLess(call, result)
        self.assertLess(result, worker.index('sleep 1;'))
        self.assertEqual(worker.count('call A3UE_fnc_fpv_processSiteQueue'), 1)

    def test_site_monitor_reports_and_never_restarts(self):
        hooks = code('installSiteHooks')
        monitor = hooks.split('scriptName "A3UE_FPV_siteMonitor";', 1)[1].split('_installed = true;', 1)[0]
        self.assertIn('sleep 5;', monitor)
        self.assertIn('case (_beatAge > 15): {"STALE"};', monitor)
        self.assertIn('case (_queued && {_txnAge > 15}): {"QUEUE_IDLE"};', monitor)
        self.assertIn('if (_now != _fault) then {', monitor)
        self.assertNotRegex(monitor, r'\b(terminate|spawn|execVM|processSiteQueue|setVariable|remoteExec|remoteExecCall|publicVariable|allUnits|allGroups|entities)\b')

    def test_site_breadcrumbs_wrap_the_existing_steps(self):
        queue = code('processSiteQueue')
        txn = queue.split('_queue deleteAt _markerX;', 1)[1]
        evaluate = txn.index('[_markerX, _siteType, true] call A3UE_fnc_fpv_managerEvaluateSite;')
        self.assertLess(txn.index('missionNamespace setVariable ["A3UE_FPV_siteLastTxn", ["txn", _markerX, diag_tickTime, _phase, _generation, _state get "appliedGeneration"]];'), evaluate)
        self.assertLess(txn.index('["evaluate", _markerX, diag_tickTime]'), evaluate)
        self.assertLess(txn.index('["txnEnd", _markerX, diag_tickTime]'), txn.index('diag_log format ["[A3UE_FPV] siteApply'))
        deploy = code('managerDeployStock')
        self.assertLess(deploy.index('["drone", _markerX, diag_tickTime, _index, _count]'), deploy.index('call A3UE_fnc_fpv_managerSpawnDrone;'))
        self.assertLess(deploy.index('["deployLine", _markerX, diag_tickTime, count _spawned, _count]'), deploy.index('diag_log format ["[A3UE_FPV] siteDeploy'))
        spawn = code('spawnManagedDrone')
        steps = [spawn.index(f'missionNamespace setVariable ["A3UE_FPV_spawnStage", ["{step}"') for step in
                 ['create', 'created', 'crew', 'postCrew', 'vehInit', 'recorded']]
        self.assertEqual(steps, sorted(steps))
        create = spawn.index('_uav = createVehicle [_uavClass, _spawnPosATL, [], 0, "FLY"];')
        self.assertLess(steps[0], create)
        self.assertLess(create, steps[1])
        self.assertLess(steps[2], spawn.index('call A3UE_fnc_fpv_createUavCrew;'))
        self.assertLess(steps[3], spawn.index('[_uav, _crewGroup, _resourcePool] call (_spec get "postCrewInit");'))
        self.assertLess(steps[4], spawn.index('[_uav, _side, _resourcePool] call A3A_fnc_AIVEHinit;'))
        self.assertLess(spawn.index('_uav setVariable ["A3UE_FPV_crewGroups", _crewGroups];'), steps[5])
        # Breadcrumbs are server-local: never broadcast.
        names = ['A3UE_FPV_siteStage', 'A3UE_FPV_spawnStage', 'A3UE_FPV_siteLastTxn', 'A3UE_FPV_siteBeat', 'A3UE_FPV_siteLastResult', 'A3UE_FPV_siteWorker"']
        for name in ['processSiteQueue', 'managerDeployStock', 'spawnManagedDrone', 'installSiteHooks']:
            for line in code(name).splitlines():
                if any(n in line for n in names):
                    self.assertNotRegex(line, r'(, true\]\]?;|publicVariable|remoteExec)', line)


if __name__ == '__main__':
    unittest.main()
