"""F4-2 field fix: launch slots and the KVN loss line (9 November 2026 engine run).

Every drone of one site deployment was placed on the same standoff point (support launches
4 m apart). A KVN pair collided at launch and KVN's native hit handler detonated and deleted
both, so they never flew and never reached MPKilled. launchSlot gives each spawn its own point;
the KVN onDestroy adapter now writes the droneLost line for that native path.

Shipped SQF runs in SQF-VM with the F2C-L harness substitutes (water, isServer, time).
Geometry/decision evidence only: no Arma physics, collision, AI flight or vendor-mod claim.
"""
import re
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT
from test_f2cl_field_fixes import PRELUDE, adapt, run_vm

STUBS = r'''
FPV_local={_this getVariable ["local",true]};
FPV_netId={if (isNull _this) then {""} else {_this getVariable ["netId",""]}};
A3UE_fnc_fpv_helperAccess={true};
private _slot = {params ["_p", "_d"]; [_p, _d] call A3UE_fnc_fpv_launchSlot};
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LaunchSlotSQF(unittest.TestCase):
    def vm(self, names, body):
        script = PRELUDE + STUBS
        for name in names:
            script += f'A3UE_fnc_fpv_{name}={{{adapt(name)}}};\n'
        r = run_vm(script + body + '\ndiag_log "F42_SLOT_OK";')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('F42_SLOT_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_a_batch_never_shares_a_launch_point(self):
        out = self.vm(['launchSlot'], r'''
private _base = [1000, 1000, 35];
private _copy = +_base;
// A three-drone batch on one standoff point, launch heading east (90): slots go right
// (south) then left (north), 30 m apart and 5 m higher per step.
private _a = [_base, 90] call _slot; private _b = [_base, 90] call _slot; private _c = [_base, 90] call _slot;
diag_log ["SLOTS", _a, _b, _c];
[_base isEqualTo _copy, "input untouched"] call _assert;
[(_a # 1) == 0 && {(_a # 0) isEqualTo [1000, 1000, 35]}, "first drone keeps the point"] call _assert;
[(_b # 1) == 1 && {((_b # 0) vectorDistance [1000, 970, 40]) < 0.01}, format ["second 30 m right, 5 m up %1", _b]] call _assert;
[(_c # 1) == 2 && {((_c # 0) vectorDistance [1000, 1030, 40]) < 0.01}, format ["third 30 m left %1", _c]] call _assert;
private _all = [_a # 0, _b # 0, _c # 0];
{private _p = _x; {[(_p distance2D _x) >= 20 || {_p isEqualTo _x}, "20 m apart"] call _assert;} forEach _all;} forEach _all;
// A point 5 m off a reserved one is still too close; a point 100 m away is free.
[(([[1003, 1004, 35], 90] call _slot) # 1) > 0, "near point moves"] call _assert;
[(([[1100, 1000, 35], 90] call _slot) # 1) == 0, "far point stays"] call _assert;
// Reservations expire after 30 s: by then the earlier drones have flown off.
FPV_time = FPV_time + 31;
[(([_base, 90] call _slot) # 1) == 0, "expired reservations free the point"] call _assert;
''')
        self.assertIn('SLOTS', out)

    def test_water_saturation_and_bounds(self):
        self.vm(['launchSlot'], r'''
// Water to the south: the right-hand slot is skipped.
FPV_water = {(_this # 1) < 990};
private _first = [[2000, 1000, 35], 90] call _slot;
private _second = [[2000, 1000, 35], 90] call _slot;
[(_second # 1) == 2 && {((_second # 0) # 1) > 1000}, format ["water slot skipped %1", _second]] call _assert;
FPV_water = {false};
// Saturation: more drones than slots still get the least crowded one, never a crash,
// and the reservation list stays bounded.
private _seen = [];
for "_i" from 1 to 40 do {_seen pushBack (([[5000, 5000, 35], 0] call _slot) # 1);};
[(_seen select [0, 9]) isEqualTo [0, 1, 2, 3, 4, 5, 6, 7, 8], format ["all nine slots used first %1", _seen]] call _assert;
[count (missionNamespace getVariable ["A3UE_FPV_launchSlots", []]) <= 32, "bounded reservations"] call _assert;
// Bad input passes through without a reservation.
missionNamespace setVariable ["A3UE_FPV_launchSlots", []];
[([[], 0] call _slot) isEqualTo [[], 0] && {([["x", 1], 0] call _slot) isEqualTo [["x", 1], 0]}, "invalid input"] call _assert;
[count (missionNamespace getVariable ["A3UE_FPV_launchSlots", []]) == 0, "no reservation for invalid input"] call _assert;
[(([[10, 10], "x"] call _slot) # 0) isEqualTo [10, 10, 0], "2D point and bad heading tolerated"] call _assert;
''')

    def test_kvn_native_destroy_writes_the_loss_line_once(self):
        self.vm(['installKvnArchiveAdapter'], r'''
A3UE_FPV_kvnCreatedEH = 1;
// SQF-VM objects have no class name (typeOf is ""): that is the KVN class list here.
DB_kvn_fpv_dronesArray = [typeOf ("VMUAV" createVehicle [0,0,0])];
FPV_events = [];
DB_kvn_fnc_fpv_onDestroy = {FPV_events pushBack ["NATIVE", +_this]; "native"};
A3UE_fnc_fpv_logDroneLoss = {FPV_events pushBack ["LOSS", +_this]; true};
A3UE_fnc_fpv_consumePool = {FPV_events pushBack ["CONSUME", +_this]; 1};
A3UE_fnc_fpv_sendLifecycle = {true};
[call A3UE_fnc_fpv_installKvnArchiveAdapter, "adapter installed"] call _assert;
private _uav = "VMUAV" createVehicle [0,0,0]; _uav setVariable ["netId", "2:44"]; _uav setVariable ["A3UE_FPV_managed", true];
private _other = "VMUAV" createVehicle [0,0,0];
A3UE_FPV_lifecycleIndex = createHashMapFromArray [["2:44", 9]];
// KVN's config hit handler: [unit, source, damage, instigator].
private _r = [_uav, _other, 0.4, objNull] call DB_kvn_fnc_fpv_onDestroy;
[_r == "native", "native destroy still runs"] call _assert;
[FPV_events isEqualTo [["LOSS", [_uav, _other, objNull, 9, "KVN_HIT"]], ["CONSUME", [_uav]], ["NATIVE", [_uav, _other, 0.4, objNull]]],
  format ["loss line and consumption (F5) before the native destroy %1", FPV_events]] call _assert;
// A repeated hit on the same airframe is ignored by the adapter's own fence.
[_uav, _other, 0.4, objNull] call DB_kvn_fnc_fpv_onDestroy;
[count FPV_events == 3, "once per airframe"] call _assert;
// An unmanaged (player-placed) KVN, and odd argument types, never break the native path.
FPV_events = [];
private _native = "VMUAV" createVehicle [0,0,0];
[_native, _other, 0.4, objNull] call DB_kvn_fnc_fpv_onDestroy;
[FPV_events isEqualTo [["NATIVE", [_native, _other, 0.4, objNull]]], format ["unmanaged %1", FPV_events]] call _assert;
FPV_events = [];
private _odd = "VMUAV" createVehicle [0,0,0]; _odd setVariable ["A3UE_FPV_managed", true];
[_odd, "x", 0.4, 5] call DB_kvn_fnc_fpv_onDestroy;
[((FPV_events # 0) # 1) isEqualTo [_odd, objNull, objNull, -1, "KVN_HIT"], format ["typed arguments %1", FPV_events]] call _assert;
''')


class LaunchSlotSource(unittest.TestCase):
    def code(self, name):
        return '\n'.join(line.split('//', 1)[0] for line in (FPV / f'fn_fpv_{name}.sqf').read_text().splitlines())

    def test_registered_and_cheap(self):
        self.assertIn('class fpv_launchSlot {};', (ROOT / 'addons/drones/config.cpp').read_text())
        s = self.code('launchSlot')
        self.assertNotRegex(s, r'\b(remoteExec|remoteExecCall|spawn|sleep|publicVariable|random|hint|hintSilent'
                               r'|allUnits|vehicles|entities|nearEntities|nearestObjects|lineIntersectsSurfaces)\b')
        self.assertNotRegex(s, r'setVariable \["[^"]*",[^\]]*,\s*true\]')
        self.assertIn('while {count _slots > 32} do {_slots deleteAt 0;};', s)
        self.assertIn('(_now - (_x # 3)) < 30', s)

    def test_every_managed_spawn_takes_a_slot(self):
        s = self.code('spawnManagedDrone')
        slot = s.index('private _launchSlot = [_spawnPosATL, _launchDir] call A3UE_fnc_fpv_launchSlot;')
        self.assertLess(s.index('if (_familyId isEqualTo "fpv_ua" && {!(call A3UE_fnc_fpv_installUaPayloadAdapter)}) exitWith {objNull};'), slot)
        self.assertLess(slot, s.index('_spawnPosATL = _launchSlot # 0;'))
        self.assertLess(s.index('_spawnPosATL = _launchSlot # 0;'), s.index('createVehicle [_uavClass, _spawnPosATL, [], 0, "FLY"]'))
        self.assertLess(s.index('_spawnPosATL = _launchSlot # 0;'), s.index('_uav setPosATL _spawnPosATL;'))
        self.assertIn('_uav setVariable ["A3UE_FPV_launchSlot", _launchSlot # 1];', s)
        deploy = self.code('managerDeployStock')
        self.assertIn('classes=%15 slots=%16', deploy)
        self.assertIn('_launchSlots pushBack (_uav getVariable ["A3UE_FPV_launchSlot", 0]);', deploy)

    def test_kvn_loss_hook_order(self):
        s = self.code('installKvnArchiveAdapter')
        wrapper = s.split('DB_kvn_fnc_fpv_onDestroy = {', 1)[1]
        fence = wrapper.index('_uav setVariable ["A3UE_FPV_kvnDestroyHandled", true];')
        loss = wrapper.index('"KVN_HIT"] call A3UE_fnc_fpv_logDroneLoss;')
        native = wrapper.index('_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeOnDestroy");\n\t\tif (!isNull _uav)')
        self.assertLess(fence, loss)
        self.assertLess(loss, native)
        self.assertIn('if (isServer && {_uav getVariable ["A3UE_FPV_managed", false]}) then {', wrapper)
        # UA detonates and deletes natively too: the lifecycle's Deleted handler logs it first.
        deleted = self.code('registerLifecycle').split('"Deleted"', 1)[1].split('"MPKilled"', 1)[0]
        self.assertIn('if (_vehicle getVariable ["UA_FPV_Detonated", false]) then {', deleted)
        self.assertLess(deleted.index('"UA_HIT"] call A3UE_fnc_fpv_logDroneLoss;'), deleted.index('[_id, "delete"] call A3UE_fnc_fpv_endLifecycle;'))
        loss_code = self.code('logDroneLoss')
        self.assertIn('via=%14', loss_code)
        self.assertLess(loss_code.index('!= "live"'), loss_code.index('_uav setVariable ["A3UE_FPV_lossLogged", true];'))


if __name__ == '__main__':
    unittest.main()
