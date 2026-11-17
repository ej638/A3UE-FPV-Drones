"""EN-02 LOW_RUN, lowest line LL-1: the low-level attack profile and the any-contact fuse (design
docs/internal/FPV_LowLine_Design_20261116.md; it replaces the accept-or-decline path check of LR-1 to
LR-1d after four engine sessions: docs/internal/FPV_LowRun_Reassessment_20261116.md).

One rule: the drone flies the lowest safe line over what is in front of it. A survey measures that
line (skim height over the ground, 0.7 m over anything in the corridor, climbing at most 15 deg and
coming down at most 30 deg); it never blocks, and nothing declines or rises one way.

Shipped SQF runs in SQF-VM through the commitment harness (f2_commitment_vm) and its explicit
engine substitutes. The world is axis-aligned boxes over an analytic terrain; the engine queries
the VM lacks (map-object search, bounding boxes, the sea surface, entity search) are stand-ins with
the same call shapes. Closed-loop runs integrate the writer's own commanded velocity, a perfect
actuator. This is geometry and decision evidence only: no claim about Arma physics, AI flight,
airframe response, rendering, the scheduler or how it looks (EJ's review and the engine sessions
decide that).
"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, script, engine_substitutes, adapt_helper

BASE = 'ab82bd1'  # main, released 1.0.7 (+ README link): the regression boundary
CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')
LOW = ['lowRunSettings', 'lowRunStage', 'lowRunTrack', 'lowRunCheck', 'lowRunAim', 'lowRunEnd', 'lowRunLineAt', 'surfaceZ',
       'contactFence', 'lowRunWaiter']
# The low run's own code (the fuse and the wiring in 1.0.7 files are counted elsewhere). LL-1 halved
# it after four sessions of growth; this budget makes any further growth a decision, not a drift.
LOW_CODE = ['lowRunSettings', 'lowRunStage', 'lowRunTrack', 'lowRunCheck', 'lowRunAim', 'lowRunEnd', 'lowRunLineAt',
            'lowRunWaiter']
LOW_CODE_BUDGET = 800

# Engine queries the VM does not implement, replaced by stand-ins with the same call shape.
REPLACE = {
    'lowRunCheck': [
        ('nearestTerrainObjects [[_queryAt # 0, _queryAt # 1], _types, 30, false, true]',
         '([[_queryAt # 0, _queryAt # 1], _types, 30] call FPV_nearestTerrainObjects)'),
        ('boundingBoxReal _object', '(_object getVariable ["box", [[-0.5,-0.5,-0.5],[0.5,0.5,0.5],1]])'),
        ('boundingBoxReal _unit', '(_unit getVariable ["box", [[-0.5,-0.5,-0.5],[0.5,0.5,0.5],1]])'),
        ('(_queryAt nearEntities [["Man", "LandVehicle", "Ship", "StaticWeapon", "Air"], 30])',
         '([_queryAt, 30] call FPV_nearEntitiesLow)'),
        ('(getModelInfo _object) param [0, ""]', '(_object getVariable ["model", ""])'),
    ],
    'lowRunTrack': [('boundingBoxReal _uav', '(_uav getVariable ["box", [[-0.3,-0.3,-0.15],[0.3,0.3,0.1],0.4]])')],
}

PRE = r'''
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
missionNamespace setVariable ["A3UE_FPV_QA_seed", 11];
missionNamespace setVariable ["A3UE_FPV_attackReversal", false];
_uav setVariable ["A3UE_FPV_targetNetId", "person"];
_uav setVariable ["A3UE_FPV_vendorId", "kvn"]; _uav setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
_uav setVariable ["box", [[-0.3,-0.3,-0.15],[0.3,0.3,0.1],0.4]];
_person setVariable ["position", [400,0,10]]; _person setVariable ["velocity", [0,0,0]];
_profile = createHashMapFromArray [["familyId","kvn"],["roleId","AP"],["terminalVectorMaxSpeed",200]];
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
// ---- The world: an analytic terrain (default flat at 10 m ASL) and boxes.
FPV_ground = {10};
FPV_getTerrainHeightASL = {_this call FPV_ground};
A3UE_fnc_fpv_surfaceZ = {_this call FPV_ground};
FPV_world = []; FPV_rays = 0; FPV_reads = 0;
// [id, centre ASL, box [[min],[max],r], kinds, map type ("" = not a map object), side]. An object's
// "box" is its bounding box (what boundingBoxReal reports); the rays meet its "geom" when it has one
// (a power-line wire: a box from the ground to the top of the span, but a thin cable).
private _place = {
  params ["_id", "_centre", "_half", ["_kinds", []], ["_type", ""], ["_side", civilian]];
  private _class = ["VMVehicle", "VMMan"] select ("Man" in _kinds);
  private _o = _class createVehicle [0,0,0];
  _o setVariable ["netId", _id]; _o setVariable ["position", +_centre]; _o setVariable ["kinds", _kinds];
  _o setVariable ["box", [[-(_half # 0), -(_half # 1), -(_half # 2)], [_half # 0, _half # 1, _half # 2], vectorMagnitude _half]];
  _o setVariable ["type", _type]; _o setVariable ["side", _side]; _o setVariable ["direction", [0,1,0]]; _o setVariable ["crew", []];
  _o setVariable ["model", _id + ".p3d"];
  FPV_objects pushBack _o; FPV_world pushBack _o; _o
};
FPV_nearestTerrainObjects = {
  params ["_centre", "_types", "_radius"];
  FPV_world select {((_x getVariable ["type", ""]) in _types) && {((_x getVariable "position") distance2D [_centre # 0, _centre # 1, 0]) <= _radius}}
};
FPV_nearEntitiesLow = {
  params ["_centre", "_radius"];
  FPV_world select {("AllVehicles" in (_x getVariable ["kinds", []])) && {((_x getVariable "position") distance2D [_centre # 0, _centre # 1, 0]) <= _radius}}
};
// Rays: the boxes (slab test) and the ground (0.25 m steps), sorted, like lineIntersectsSurfaces.
FPV_lineIntersectsSurfaces = {
  params ["_from", "_to", ["_i1", objNull], ["_i2", objNull], ["_sorted", true], ["_max", 1]];
  FPV_rays = FPV_rays + 1;
  private _d = _to vectorDiff _from;
  private _hits = [];
  {
    private _o = _x;
    if (!(_o isEqualTo _i1) && {!(_o isEqualTo _i2)} && {_o getVariable ["alive", true]}) then {
      private _c = _o getVariable "position"; private _b = _o getVariable ["geom", _o getVariable "box"];
      private _lo = _c vectorAdd (_b # 0); private _hi = _c vectorAdd (_b # 1);
      private _t0 = 0; private _t1 = 1; private _ok = true;
      for "_k" from 0 to 2 do {
        private _dk = _d # _k; private _fk = _from # _k;
        if (abs _dk < 1e-9) then {
          if (_fk < (_lo # _k) || {_fk > (_hi # _k)}) then {_ok = false;};
        } else {
          private _a = ((_lo # _k) - _fk) / _dk; private _bb = ((_hi # _k) - _fk) / _dk;
          _t0 = _t0 max (_a min _bb); _t1 = _t1 min (_a max _bb);
        };
      };
      if (_ok && {_t0 <= _t1}) then {_hits pushBack [_t0, [_from vectorAdd (_d vectorMultiply _t0), [0,0,1], _o, objNull]];};
    };
  } forEach FPV_world;
  private _length = vectorMagnitude _d;
  private _steps = ceil ((_length / 0.25) max 1);
  for "_s" from 0 to _steps do {
    private _t = _s / _steps;
    private _p = _from vectorAdd (_d vectorMultiply _t);
    if ((_p # 2) <= ([_p # 0, _p # 1] call FPV_ground)) exitWith {_hits pushBack [_t, [_p, [0,0,1], objNull, objNull]];};
  };
  _hits sort true;
  (_hits apply {_x # 1}) select [0, _max]
};
'''


def run(body, extra='', timeout=600):
    text = script(engine_substitutes(PRE + body), extra)
    with tempfile.TemporaryDirectory(prefix='fpv-low-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(text)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '50000000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=timeout)


def source(name):
    return (FPV / f'fn_fpv_{name}.sqf').read_text(encoding='utf-8')


def code(name):
    return '\n'.join(line.split('//', 1)[0] for line in source(name).splitlines())


def load(names):
    out = ''
    for name in names:
        s = source(name)
        for old, new in REPLACE.get(name, []):
            assert old in s, (name, old)
            s = s.replace(old, new)
        out += f'A3UE_fnc_fpv_{name}={{{adapt_helper(name, s)}}};\n'
    return out


def base_source(name):
    return subprocess.check_output(['git', 'show', f'{BASE}:addons/drones/functions/fpv/fn_fpv_{name}.sqf'],
                                   cwd=ROOT, text=True)


# Survey scene helpers: run one survey to the end, counting calls and per-call work; read the line.
SCENE = r'''
private _scene = {
  params ["_origin", "_targetAt", ["_glide", 0], ["_height", 1.5]];
  private _record = createHashMapFromArray [["height", _height], ["check", createHashMap], ["result", []]];
  private _settings = call A3UE_fnc_fpv_lowRunSettings;
  FPV_rays = 0;
  private _status = [_uav, _person, _record, _settings, [_origin, _targetAt, _glide]] call A3UE_fnc_fpv_lowRunCheck;
  private _calls = 1; private _maxRays = FPV_rays;
  while {_status == "RUNNING" && {_calls < 500}} do {
    FPV_rays = 0;
    _status = [_uav, _person, _record, _settings] call A3UE_fnc_fpv_lowRunCheck;
    _calls = _calls + 1; _maxRays = _maxRays max FPV_rays;
  };
  [_status, _calls, _maxRays, _record get "result", _record]
};
// The surveyed line at s metres along (the nearest station).
private _lineAt = {params ["_r", "_s"]; private _plan = (_r # 3) # 3; _plan # (((round (_s / 5)) max 0) min (count _plan - 1))};
// Its steepest climb and descent per metre (whole 5 m stations).
private _slopes = {
  params ["_r"];
  private _plan = (_r # 3) # 3; private _up = 0; private _down = 0;
  for "_i" from 1 to (count _plan - 2) do {
    _up = _up max (((_plan # _i) - (_plan # (_i - 1))) / 5); _down = _down max (((_plan # (_i - 1)) - (_plan # _i)) / 5);
  };
  [_up, _down]
};
private _flat = {params ["_r", "_z"]; (((_r # 3) # 3) findIf {abs (_x - _z) > 0.01}) < 0};
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LowRunSurveySQF(unittest.TestCase):
    EXTRA = load(LOW)

    def vm(self, body):
        r = run(SCENE + body, self.EXTRA)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-6000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-6000:])
        return r.stdout

    def test_open_field_is_skim_height_within_the_budget(self):
        out = self.vm(r'''
private _r = [[100,0,11.5], [400,0,10]] call _scene;
private _res = _r # 3;
diag_log ["OPEN", _r select [0, 3], _res select [4, 4]];
[(_r # 0) == "DONE" && {[_r, 11.5] call _flat} && {(_res # 6) == 0} && {(_res # 7) == ""}, format ["skim height all the way %1", _r select [0, 3]]] call _assert;
[(_r # 1) >= 5 && {(_r # 2) <= 20}, format ["spread over calls, at most ~16 rays a call: %1", _r select [1, 2]]] call _assert;
[count _res == 8 && {(_res # 1) isEqualTo [100,0,11.5]} && {(_res # 0) == FPV_time} && {count (_res # 3) == 61} && {(_res # 4) == 0}
  && {(_res # 5) == 0} && {((_r # 4) get "surveys") == 1} && {((_r # 4) get "sliceMsMax") >= 0}, format ["result shape %1", _res select [0, 3]]] call _assert;
// A smaller budget only spreads the same work over more calls.
missionNamespace setVariable ["A3UE_FPV_lowRunCheckUnits", 4];
private _slow = [[100,0,11.5], [400,0,10]] call _scene;
[(_slow # 0) == "DONE" && {(_slow # 1) > (_r # 1)} && {(_slow # 2) <= 8} && {((_slow # 3) # 3) isEqualTo (_res # 3)},
  format ["budget 4: the same line over more calls %1", _slow select [0, 3]]] call _assert;
''')
        self.assertIn('OPEN', out)

    def test_terrain_is_followed_and_never_blocks(self):
        self.vm(r'''
// A 42 deg rise from 10 m to 19 m: the line climbs at 15 deg ahead of it (LR-1d: TERRAIN declined).
FPV_ground = {params ["_x0"]; if (_x0 < 200) then {10} else {if (_x0 < 210) then {10 + 0.9 * (_x0 - 200)} else {19}}};
private _steep = [[100,0,11.5], [400,0,19]] call _scene;
private _sl = [_steep] call _slopes;
private _above = true;
{if (_x < (([100 + ((5 * _forEachIndex) min 299.5), 0] call FPV_ground) + 1.5 - 0.001)) then {_above = false;};} forEach ((_steep # 3) # 3);
[(_steep # 0) == "DONE" && {([_steep, 110] call _lineAt) >= 20.49} && {abs (([_steep, 80] call _lineAt) - (20.5 - (tan 15) * 30)) < 0.02}
  && {(_sl # 0) <= (tan 15) + 1e-4} && {_above}, format ["steep rise climbed early %1 %2", _steep select [0, 3], _sl]] call _assert;
// A 22 deg climb to a 20 m crest with a cliff behind it: over the crest, down at 30 deg after it.
FPV_ground = {params ["_x0"]; if (_x0 < 150) then {10} else {if (_x0 < 200) then {10 + 0.4 * (_x0 - 150)} else {if (_x0 < 260) then {30} else {10}}}};
private _cliff = [[100,0,11.5], [400,0,10]] call _scene;
_sl = [_cliff] call _slopes;
[(_cliff # 0) == "DONE" && {([_cliff, 155] call _lineAt) >= 31.49} && {([_cliff, 50] call _lineAt) > 17.9} && {abs (([_cliff, 210] call _lineAt) - 11.5) < 0.01}
  && {(_sl # 0) <= (tan 15) + 1e-4} && {(_sl # 1) <= (tan 30) + 1e-4}, format ["crest and cliff %1 %2", _cliff select [0, 3], _sl]] call _assert;
// The sea is flown over at its surface plus the wave margin (surfaceZ), not the sea bed.
FPV_ground = {-20};
A3UE_fnc_fpv_surfaceZ = {0.5};
private _sea = [[100,0,2], [400,0,0.5]] call _scene;
[(_sea # 0) == "DONE" && {[_sea, 2] call _flat}, format ["sea %1", _sea select [0, 3]]] call _assert;
''')

    def test_map_objects_are_flown_over(self):
        self.vm(r'''
// A low wall across the line: flown 0.7 m over, and named for the RPT line.
["wall", [250,0,10.6], [0.2,10,0.6], [], "WALL"] call _place;
private _r = [[100,0,11.5], [400,0,10]] call _scene;
[(_r # 0) == "DONE" && {abs (([_r, 150] call _lineAt) - 11.9) < 0.01} && {abs (((_r # 3) # 6) - 1.2) < 0.01} && {((_r # 3) # 7) == "wall.p3d"},
  format ["low wall %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// A 14 m tree on the line (engine session 1d: 15 m pines declined two first drones): flown over,
// climbing at 15 deg before it and down at 30 deg after it, at skim height again 50 m on.
private _tree = ["tree", [250,0,17], [2,2,7], [], "TREE"] call _place;
_r = [[100,0,11.5], [400,0,10]] call _scene;
private _sl = [_r] call _slopes;
[(_r # 0) == "DONE" && {abs (([_r, 150] call _lineAt) - 24.7) < 0.01} && {abs (([_r, 100] call _lineAt) - (24.7 - (tan 15) * 45)) < 0.02}
  && {abs (([_r, 200] call _lineAt) - 11.5) < 0.01} && {abs (((_r # 3) # 6) - 14) < 0.01} && {((_r # 3) # 7) == "tree.p3d"}
  && {(_sl # 0) <= (tan 15) + 1e-4} && {(_sl # 1) <= (tan 30) + 1e-4}, format ["tree on the line %1 %2", (_r # 3) select [5, 3], _sl]] call _assert;
// Beside the line inside the corridor (weaveCap 3.5 + 1.5 = 5 m): flown over too. Outside it: not.
_tree setVariable ["position", [250,4.5,17]];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[abs (([_r, 150] call _lineAt) - 24.7) < 0.01, format ["2.5 m beside: over it %1", (_r # 3) select [5, 3]]] call _assert;
_tree setVariable ["position", [250,7.5,17]];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, format ["5.5 m beside: not in the way %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// The bush the target stands in and a low wall just in front of it: the fuse's, not the line's.
["bush", [400,0,11], [1.5,1.5,1], [], "BUSH"] call _place;
["cover", [398.8,0,10.75], [0.15,3,0.75], [], "WALL"] call _place;
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, format ["at the target %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// A power-line wire: its box runs from the ground to the top of the span (engine session 1d: four
// declines). Passed under by its box; a cable that really hangs at the line's height is met by the
// rays and flown over.
private _wire = ["highvoltagecolumnwire_f", [250,0,19], [0.2,40,9], [], "POWER LINES"] call _place;
_wire setVariable ["geom", [[-0.2,-40,2.9],[0.2,40,3.1],1]];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, format ["under the wire %1", (_r # 3) select [5, 3]]] call _assert;
_wire setVariable ["geom", [[-0.2,-40,-8.1],[0.2,40,-7.7],1]];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[abs (([_r, 150] call _lineAt) - 12.0) < 0.01, format ["a cable at the line's height is flown over %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// A bridge: its deck well above the line is passed under.
["deck", [250,0,17], [3,10,0.5], [], "BUILDING"] call _place;
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, format ["under the bridge %1", (_r # 3) select [5, 3]]] call _assert;
''')

    def test_people_animals_vehicles_and_what_only_the_rays_see(self):
        self.vm(r'''
// A soldier hostile to the drone is ignored (contact with him is a hit); anyone else alive is flown
// over at head height + 0.7 m.
private _man = ["friend", [250,1,10.9], [0.3,0.3,0.9], ["Man","AllVehicles"], "", east] call _place;
private _r = [[100,0,11.5], [400,0,10]] call _scene;
[abs (([_r, 150] call _lineAt) - 13.5) < 0.01 && {((_r # 3) # 7) == "friend.p3d"}, format ["friendly flown over %1", (_r # 3) select [5, 3]]] call _assert;
_man setVariable ["side", west];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, "hostile soldier ignored"] call _assert;
_man setVariable ["side", east]; _man setVariable ["alive", false];
_r = [[100,0,11.5], [400,0,10]] call _scene;
[[_r, 11.5] call _flat, "a dead man is not flown over"] call _assert;
FPV_world = [];
// A parked car 1.8 m beside the line: flown over.
["car", [250,4,11], [1,2.2,1], ["LandVehicle","Car","AllVehicles"]] call _place;
_r = [[100,0,11.5], [400,0,10]] call _scene;
[abs (([_r, 150] call _lineAt) - 12.7) < 0.01, format ["parked car %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// LR-1d (engine session 1c: two runs rose for a rabbit counted as a 1.9 m man): an animal counts at
// its own size. A rabbit stays under a 1 m skim; a sheep is flown over.
["rabbit", [250,0.5,10.15], [0.15,0.3,0.15], ["Man","Animal","AllVehicles"], "", east] call _place;
_r = [[100,0,11], [400,0,10], 0, 1.0] call _scene;
[[_r, 11] call _flat && {((_r # 3) # 6) < 0.5}, format ["rabbit under the line %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
["sheep", [250,0.5,10.55], [0.6,0.3,0.55], ["Man","Animal","AllVehicles"], "", civilian] call _place;
_r = [[100,0,11], [400,0,10], 0, 1.0] call _scene;
[abs (([_r, 150] call _lineAt) - 11.8) < 0.01, format ["sheep flown over %1", (_r # 3) select [5, 3]]] call _assert;
FPV_world = [];
// Sandbags with no map type: only the rays see them; their top comes from a ray down.
["bags", [250,0,10.7], [0.4,6,0.7]] call _place;
_r = [[100,0,11.5], [400,0,10]] call _scene;
[abs (([_r, 150] call _lineAt) - 12.1) < 0.01, format ["sandbags %1", (_r # 3) select [5, 3]]] call _assert;
''')

    def test_glide_and_what_pokes_out_of_it(self):
        self.vm(r'''
// The glide from 35 m above the ground at tan 18 deg (about 0.325) meets skim height 105 m in.
private _r = [[100,0,45], [400,0,10], 0.325, 1.5] call _scene;
[(_r # 0) == "DONE" && {((_r # 3) # 5) == 105} && {abs (([_r, 50] call _lineAt) - (45 - 0.325 * 50)) < 0.01} && {([_r, 120] call _lineAt) == 11.5},
  format ["glide %1", (_r # 3) select [4, 4]]] call _assert;
// A 15 m tree 30 m in is under the glide: nothing changes, nothing is flown over.
private _tree = ["tree", [130,0,17.5], [2,2,7.5], [], "TREE"] call _place;
private _r2 = [[100,0,45], [400,0,10], 0.325, 1.5] call _scene;
[((_r2 # 3) # 3) isEqualTo ((_r # 3) # 3) && {((_r2 # 3) # 6) == 0}, format ["under the glide %1", (_r2 # 3) select [4, 4]]] call _assert;
// 80 m in it pokes out of the glide (LR-1c: a decline): the line goes over it.
_tree setVariable ["position", [180,0,17.5]];
_r2 = [[100,0,45], [400,0,10], 0.325, 1.5] call _scene;
[(_r2 # 0) == "DONE" && {abs (([_r2, 80] call _lineAt) - 25.7) < 0.01} && {abs (((_r2 # 3) # 6) - 15) < 0.01}, format ["out of the glide %1", (_r2 # 3) select [4, 4]]] call _assert;
''')

    def test_a_wood_is_a_treetop_line_within_the_budget(self):
        out = self.vm(r'''
// 30 trees 12-16 m tall, 8 m apart, up to 5 m either side of the line (an Altis outpost's olive
// grove). Never blocked: the line flies 0.7 m over every one, within the work budget per call.
private _trees = [];
for "_i" from 0 to 29 do {
  private _h = 12 + (_i mod 5);
  _trees pushBack (["t" + str _i, [130 + 8 * _i, ((_i mod 5) - 2) * 2.5, 10 + _h / 2], [2,2,_h / 2], [], "TREE"] call _place);
};
private _r = [[100,0,11.5], [400,0,10]] call _scene;
private _over = true;
{
  private _c = _x getVariable "position"; private _b = _x getVariable "box";
  private _top = (_c # 2) + ((_b # 1) # 2);
  for "_s" from ((_c # 0) - 102) to ((_c # 0) - 98) step 1 do {
    if (([_r, _s] call _lineAt) < _top + 0.7 - 0.01) then {_over = false;};
  };
} forEach _trees;
private _sl = [_r] call _slopes;
diag_log ["FOREST", _r select [0, 3], (_r # 3) select [5, 3], _sl];
[(_r # 0) == "DONE" && {_over} && {(_r # 2) <= 20} && {(_sl # 0) <= (tan 15) + 1e-4}, format ["treetop line %1 %2", _r select [0, 3], _sl]] call _assert;
''')
        self.assertIn('FOREST', out)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LowRunDecisionSQF(unittest.TestCase):
    EXTRA = (load(LOW) + load(['evaluateImpactWindow', 'shouldDetonateNow', 'shouldEnterTerminal'])
             + f'FPV_baseEngagement={{{adapt_helper("attackEngagement", base_source("attackEngagement"))}}};\n')

    def vm(self, body):
        r = run(SCENE + body, self.EXTRA)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-6000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-6000:])
        return r.stdout

    def test_settings_defaults_and_sanitising(self):
        self.vm(r'''
private _s = call A3UE_fnc_fpv_lowRunSettings;
// LL-1: 13 tunables; the rest are design constants.
[(_s get "enabled") && {(_s get "weight") == 0} && {(_s get "minRange") == 300} && {(_s get "handoff") == 350}
  && {(_s get "handoffMax") == 500} && {(_s get "floor") == 1} && {(_s get "max") == 4} && {(_s get "skimSpeed") isEqualTo [15, 20]}
  && {(_s get "weaveCap") == 3.5} && {(_s get "waitRing") == 500} && {(_s get "checkUnits") == 16} && {(_s get "contactAny")}
  && {(_s get "forcedHeight") == -1} && {(_s get "sprintM") == 60} && {(_s get "sprintS") == 2.2} && {(_s get "recheck") == 1}
  && {(_s get "skimFrom") == 200} && {(_s get "levelOut") == 50} && {(_s get "glideMax") == 30} && {(_s get "over") == 0.7}
  && {abs ((_s get "climb") - (tan 15)) < 1e-6} && {abs ((_s get "descent") - (tan 30)) < 1e-6} && {count _s == 22},
  format ["defaults %1", _s]] call _assert;
// Gone with the accept-or-decline check.
[(["clutterTop", "tallHop", "tallHopFrom", "recheckOnLine", "linkMin", "linkRise", "ignoreBlock"] findIf {_x in _s}) < 0, "no decline settings"] call _assert;
missionNamespace setVariable ["A3UE_FPV_lowRunSkimSpeed", [25, 12]];
missionNamespace setVariable ["A3UE_FPV_lowRunMaxM", 0.2];
missionNamespace setVariable ["A3UE_FPV_lowRunWeight", 7];
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 0.05];
missionNamespace setVariable ["A3UE_FPV_lowRun", "yes"];
missionNamespace setVariable ["A3UE_FPV_lowRunWeaveCapM", 20];
_s = call A3UE_fnc_fpv_lowRunSettings;
[(_s get "skimSpeed") isEqualTo [12, 25] && {(_s get "max") == 1} && {(_s get "weight") == 1} && {(_s get "forcedHeight") == 0.2}
  && {_s get "enabled"} && {(_s get "weaveCap") == 8}, format ["sanitised %1", _s]] call _assert;
missionNamespace setVariable ["A3UE_FPV_lowRunSkimSpeed", [30, "x"]];
[((call A3UE_fnc_fpv_lowRunSettings) get "skimSpeed") isEqualTo [15, 20], "malformed speed range"] call _assert;
// Tick memo: one read per controller tick.
private _fpvTick = createHashMap;
private _first = call A3UE_fnc_fpv_lowRunSettings;
missionNamespace setVariable ["A3UE_FPV_lowRunWeight", 0.5];
[(call A3UE_fnc_fpv_lowRunSettings) isEqualTo _first, "memoised in a tick"] call _assert;
_fpvTick = nil;
[((call A3UE_fnc_fpv_lowRunSettings) get "weight") == 0.5, "live outside a tick"] call _assert;
// The forced profile accepts LOW_RUN and LOW_RUN_WING.
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
[((call A3UE_fnc_fpv_attackSettings) # 7) == "LOW_RUN", "QA force LOW_RUN"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN_WING"];
[((call A3UE_fnc_fpv_attackSettings) # 7) == "LOW_RUN_WING", "QA force LOW_RUN_WING"] call _assert;
''')

    def test_appended_draw_keeps_every_seed_and_the_natural_share(self):
        out = self.vm(r'''
_uav setVariable ["position", [0,0,50]];
private _sample = {
  params ["_seed", "_function"];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  [_uav, _person, _identity, true] call _function
};
// Weight 0 (forced only) and the master switch off: every seed picks today's profile and parameters.
private _same = true; private _n = 0;
for "_s" from 0 to 4095 step 7 do {
  if !((([_s, A3UE_fnc_fpv_attackEngagement] call _sample) select [1, 3]) isEqualTo (([_s, FPV_baseEngagement] call _sample) select [1, 3])) then {_same = false;};
  _n = _n + 1;
};
[_same, "weight 0: identical to 1.0.7 for every seed"] call _assert;
missionNamespace setVariable ["A3UE_FPV_lowRunWeight", 0.15];
private _low = 0; private _othersOk = true; private _paramsOk = true;
for "_s" from 0 to 4095 step 7 do {
  private _base = [_s, FPV_baseEngagement] call _sample;
  private _new = [_s, A3UE_fnc_fpv_attackEngagement] call _sample;
  if ((_new # 1) == "LOW_RUN") then {
    _low = _low + 1;
    (_new # 2) params ["_h", "_v", "_g"];
    if !(count (_new # 2) == 3 && {_h >= 1} && {_h <= 4} && {_v >= 15} && {_v <= 20} && {_g >= 15} && {_g <= 20}) then {_paramsOk = false;};
  } else {
    if !((_new select [1, 3]) isEqualTo (_base select [1, 3])) then {_othersOk = false;};
  };
};
diag_log ["LOW_SHARE", _low, _n];
[abs ((_low / _n) - 0.15) < 0.05, format ["about 15%% low runs: %1 of %2", _low, _n]] call _assert;
[_othersOk, "every other seed is exactly the profile 1.0.7 picks"] call _assert;
[_paramsOk, "sampled skim height, speed and glide in range; nothing else carried"] call _assert;
// LL-1: a radio drone never goes low (EJ: fiber only); every seed is 1.0.7's.
_uav setVariable ["A3UE_FPV_linkModel", "RADIO"];
_same = true;
for "_s" from 0 to 4095 step 31 do {
  if !((([_s, A3UE_fnc_fpv_attackEngagement] call _sample) select [1, 3]) isEqualTo (([_s, FPV_baseEngagement] call _sample) select [1, 3])) then {_same = false;};
};
[_same, "radio drone: identical to 1.0.7"] call _assert;
_uav setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
missionNamespace setVariable ["A3UE_FPV_lowRun", false];
_same = true;
for "_s" from 0 to 4095 step 31 do {
  if !(([_s, A3UE_fnc_fpv_attackEngagement] call _sample) select [1, 3] isEqualTo (([_s, FPV_baseEngagement] call _sample) select [1, 3])) then {_same = false;};
};
[_same, "master switch off: identical to 1.0.7"] call _assert;
''')
        self.assertIn('LOW_SHARE', out)

    def test_eligibility(self):
        self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
private _profileFor = {
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  ([_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement) param [1, ""]
};
_uav setVariable ["position", [0,0,50]];
["LOW_RUN" == (call _profileFor), "a man on foot 400 m out"] call _assert;
// LL-1 (EJ, 16 November): fiber-optic drones only; a radio drone attacks as it would, even forced.
_uav setVariable ["A3UE_FPV_linkModel", "RADIO"];
["LOW_RUN" != (call _profileFor), "a radio drone"] call _assert;
_uav setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
_uav setVariable ["position", [150,0,50]];
["LOW_RUN" != (call _profileFor), "under 300 m"] call _assert;
_uav setVariable ["position", [0,0,50]];
_person setVariable ["position", [400,0,13]];
["LOW_RUN" != (call _profileFor), "3 m above the ground (a roof)"] call _assert;
_person setVariable ["position", [400,0,10]];
_person setVariable ["parent", _target];
["LOW_RUN" != (call _profileFor), "in a vehicle"] call _assert;
_person setVariable ["parent", objNull];
_uav setVariable ["A3UE_FPV_supportSafetyRadius", 50];
["LOW_RUN" != (call _profileFor), "support strike with a safety radius"] call _assert;
_uav setVariable ["A3UE_FPV_supportSafetyRadius", 0];
_person setVariable ["kinds", ["Air","AllVehicles"]];
["LOW_RUN" != (call _profileFor), "an aircraft"] call _assert;
// A parked vehicle may be a low run; a moving one never.
_person setVariable ["kinds", ["LandVehicle","Car","AllVehicles"]];
["LOW_RUN" == (call _profileFor), "a parked vehicle"] call _assert;
_person setVariable ["velocity", [3,0,0]];
["LOW_RUN" != (call _profileFor), "a moving vehicle"] call _assert;
_person setVariable ["velocity", [0,0,0]]; _person setVariable ["kinds", ["Man","AllVehicles"]];
// Forced height, and the record reuse: one draw per engagement.
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 2.5];
_uav setVariable ["A3UE_FPV_attackEngagement", []];
private _e = [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
[(_e # 1) == "LOW_RUN" && {((_e # 2) # 0) == 2.5} && {([_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement) isEqualTo _e}, "forced height; sampled once"] call _assert;
// Profiles off or the run off: never low.
missionNamespace setVariable ["A3UE_FPV_attackProfiles", false];
["LOW_RUN" != (call _profileFor), "profiles off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackProfiles", true];
missionNamespace setVariable ["A3UE_FPV_lowRun", false];
["LOW_RUN" != (call _profileFor), "low run off"] call _assert;
''')

    def test_track_surveys_and_hands_off(self):
        out = self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
_uav setVariable ["A3UE_FPV_mode", "TRACKING"];
_uav setVariable ["position", [-80,0,45]];
_uav setVariable ["A3UE_FPV_attackEngagement", []];
[_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
private _track = {[_uav, _person, _identity] call A3UE_fnc_fpv_lowRunTrack};
// 480 m out: nominated, no survey yet (surveys start 100 m before this drone's hand-off).
[(call _track) == "CHECKING" && {count ((_uav getVariable "A3UE_FPV_lowRun") get "check") == 0}, "no survey beyond 460 m"] call _assert;
// Closing at 22 m/s, guidance every 0.1 s, as the AI flies the transit.
private _handoffAt = -1; private _stages = [];
for "_i" from 0 to 200 do {
  if (_handoffAt < 0) then {
    FPV_time = FPV_time + 0.1; FPV_observed = FPV_observed + 0.1;
    private _p = _uav getVariable "position"; _uav setVariable ["position", _p vectorAdd [2.2,0,0]];
    private _stage = call _track;
    if ((_stages param [count _stages - 1, ""]) != _stage) then {_stages pushBack _stage;};
    if ([_uav, _person, _profile] call A3UE_fnc_fpv_shouldEnterTerminal) then {_handoffAt = 400 - ((_uav getVariable "position") # 0);};
  };
};
private _record = _uav getVariable "A3UE_FPV_lowRun";
diag_log ["HANDOFF", _handoffAt, _stages, _record get "surveys", _record get "handoffRun"];
// LR-1c: 35 m up, the drawn glide reaches the ground 250 m out from about 360 m.
private _run = _record get "handoffRun";
[_run > 350 && {_run < 380} && {_handoffAt <= _run} && {_handoffAt >= _run - 50}, format ["hands off at its own range %1: %2", _run, _handoffAt]] call _assert;
[_stages isEqualTo ["CHECKING", "READY"] && {(_record get "surveys") >= 2}, format ["surveyed, then ready: %1", _stages]] call _assert;
''')
        self.assertIn('HANDOFF', out)

    def test_high_arrival_hands_off_earlier_on_the_drawn_glide(self):
        out = self.vm(r'''
// LR-1c (engine session 1b), kept: the glide must be down at skim height 250 m out (skimFrom 200 +
// levelOut 50) over the real ground there, from the airframe's own height. The drawn 15-20 deg is
// kept by handing off farther out (350 m at least, 500 m at most); steeper (at most 30 deg) only
// beyond 500 m. Ground 10 m, skim 1 m: the line is down at 11 m; airframe bottom 0.15 m below.
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
_uav setVariable ["A3UE_FPV_mode", "TRACKING"];
private _lineFor = {
  params ["_z", "_x0"];
  _uav setVariable ["position", [_x0,0,_z]];
  _uav setVariable ["A3UE_FPV_lowRun", createHashMap];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
  for "_i" from 0 to 40 do {FPV_time = FPV_time + 0.1; [_uav, _person, _identity] call A3UE_fnc_fpv_lowRunTrack;};
  private _r = _uav getVariable "A3UE_FPV_lowRun";
  private _res = _r get "result";
  // [surveyed tan, drawn tan, stage, H (range of the surveyed start), handoffRun, start height]
  [_res param [4, -1], tan (_r get "glide"), _r get "stage", 400 - ((_res param [1, [1e9]]) # 0), _r get "handoffRun", (_res param [1, [0,0,-1]]) # 2]
};
private _low = [30, -40] call _lineFor;
private _at35 = [45, -50] call _lineFor;
private _at60 = [70, -130] call _lineFor;
private _at90 = [100, -190] call _lineFor;
private _at160 = [170, -190] call _lineFor;
diag_log ["GLIDE", _low, _at35, _at60, _at90, _at160];
private _drawn = _at35 # 1;
[abs ((_low # 0) - _drawn) < 1e-6 && {abs ((_low # 3) - 350) < 0.05} && {(_low # 2) == "READY"}, format ["20 m up: 350 m, the drawn angle %1", _low]] call _assert;
[abs ((_at35 # 0) - _drawn) < 1e-6 && {abs ((_at35 # 3) - (250 + 33.85 / _drawn)) < 0.05} && {abs ((_at35 # 4) - (_at35 # 3)) < 0.05}
  && {abs ((_at35 # 5) - 44.85) < 0.01} && {(_at35 # 2) == "READY"}, format ["35 m up: hands off a little farther out, the drawn angle %1", _at35]] call _assert;
[abs ((_at60 # 0) - _drawn) < 1e-6 && {abs ((_at60 # 3) - (250 + 58.85 / _drawn)) < 0.05} && {(_at60 # 3) > 440}, format ["60 m up: farther out still %1", _at60]] call _assert;
[abs ((_at90 # 0) - (88.85 / 250)) < 1e-5 && {abs ((_at90 # 3) - 500) < 0.05} && {(_at90 # 2) == "READY"}, format ["90 m up: 500 m, steepened %1", _at90]] call _assert;
[abs ((_at160 # 0) - (tan 30)) < 1e-6 && {abs ((_at160 # 3) - 500) < 0.05}, format ["160 m up: capped at 30 deg %1", _at160]] call _assert;
// Surveys start 100 m before this drone's own hand-off, not before.
_uav setVariable ["position", [-70,0,45]];
_uav setVariable ["A3UE_FPV_lowRun", createHashMap];
_uav setVariable ["A3UE_FPV_attackEngagement", []];
[_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
for "_i" from 0 to 20 do {FPV_time = FPV_time + 0.1; [_uav, _person, _identity] call A3UE_fnc_fpv_lowRunTrack;};
private _idle = _uav getVariable "A3UE_FPV_lowRun";
[(_idle get "result") isEqualTo [] && {count (_idle get "check") == 0} && {(_idle get "stage") == "CHECKING"}, "35 m up, 470 m out: no survey yet"] call _assert;
// From a hill: the ground falls 40 m from 500 m out to 250 m out. 50 m over the hill is 89 m above
// the ground where the glide must be down; it starts at the airframe's own height.
FPV_ground = {params ["_x0"]; if (_x0 < -100) then {50} else {if (_x0 < 150) then {50 - 0.16 * (_x0 + 100)} else {10}}};
private _hill = [100, -190] call _lineFor;
diag_log ["HILL", _hill];
[abs ((_hill # 0) - (88.85 / 250)) < 1e-5 && {abs ((_hill # 3) - 500) < 0.05} && {abs ((_hill # 5) - 99.85) < 0.01} && {(_hill # 2) == "READY"},
  format ["hill: the drop to the field counts %1", _hill]] call _assert;
FPV_ground = {10};
// The far limit is a setting (surveys then start 500 m out).
missionNamespace setVariable ["A3UE_FPV_lowRunHandoffMaxM", 400];
private _near = [80, -90] call _lineFor;
[abs ((_near # 3) - 400) < 0.05 && {abs ((_near # 0) - (68.85 / 150)) < 1e-5}, format ["handoffMax 400 %1", _near]] call _assert;
''')
        self.assertIn('GLIDE', out)

    def test_waiting_drones_can_go_low(self):
        out = self.vm(r'''
// LR-1c (EJ, 16 November: every drone may go low, the second of a pair too). A waiting drone that
// would be low when cleared waits on the outer ring: the same draw attackEngagement makes then
// (peek: nothing stored, the range minimum not applied), decided once per engagement key.
_uav setVariable ["position", [250,0,50]];
private _waiter = {
  _uav setVariable ["A3UE_FPV_lowWaiter", []];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  [_uav, _person, _identity] call A3UE_fnc_fpv_lowRunWaiter
};
[!(call _waiter), "natural share off: waits on the 140 m ring"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
[call _waiter, "forced: waits on the outer ring, 150 m out now"] call _assert;
[(_uav getVariable ["A3UE_FPV_attackEngagement", []]) isEqualTo [], "the peek stores no engagement"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", ""];
[[_uav, _person, _identity] call A3UE_fnc_fpv_lowRunWaiter, "decided once per key"] call _assert;
_uav setVariable ["A3UE_FPV_targetRevision", 7];
[!([_uav, _person, _identity] call A3UE_fnc_fpv_lowRunWaiter), "a new target revision decides again"] call _assert;
_uav setVariable ["A3UE_FPV_targetRevision", 0];
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
_person setVariable ["parent", _target];
[!(call _waiter), "a man in a vehicle: never"] call _assert;
_person setVariable ["parent", objNull];
_uav setVariable ["A3UE_FPV_linkModel", "RADIO"];
[!(call _waiter), "a radio drone: never (LL-1)"] call _assert;
_uav setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
missionNamespace setVariable ["A3UE_FPV_lowRun", false];
[!(call _waiter), "master switch off: never"] call _assert;
missionNamespace setVariable ["A3UE_FPV_lowRun", true];
// LOW_RUN_WING: only a drone waiting behind another drone's attack is nominated, and it is low when
// cleared 500 m out; the first drone (it never waited) attacks as it would. LR-1d: every pair starts
// with a short wait for both (the board's follow-up delay); with nobody attacking yet nothing is decided.
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN_WING"];
[!(call _waiter) && {(_uav getVariable ["A3UE_FPV_lowWaiter", []]) isEqualTo []}, "LOW_RUN_WING: nobody attacking, not decided"] call _assert;
private _lead = ["VMUAV", "lead"] call _make;
missionNamespace setVariable ["A3UE_FPV_attackBoard", createHashMapFromArray [["person",
  createHashMapFromArray [["holders", [[_uav, 0, -1]]], ["queue", []]]]]];
[!(call _waiter), "LOW_RUN_WING: itself the attacker, not a waiter"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackBoard", createHashMapFromArray [["person",
  createHashMapFromArray [["holders", [[_lead, 0, -1]]], ["queue", [_uav]]]]]];
[call _waiter, "LOW_RUN_WING: waiting behind the lead's attack, it goes low"] call _assert;
_uav setVariable ["position", [-100,0,50]];
_uav setVariable ["A3UE_FPV_attackEngagement", []];
private _e = [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
[(_e # 1) == "LOW_RUN", format ["low when cleared on the outer ring: %1", _e # 1]] call _assert;
_uav setVariable ["A3UE_FPV_lowWaiter", []];
_uav setVariable ["A3UE_FPV_attackEngagement", []];
_e = [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
[(_e # 1) != "LOW_RUN", format ["the first drone attacks as it would: %1", _e # 1]] call _assert;
// Natural share: the nomination while waiting is exactly the draw it gets when cleared 500 m out.
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", ""];
missionNamespace setVariable ["A3UE_FPV_lowRunWeight", 0.15];
private _same = true; private _nominated = 0; private _n = 0;
for "_s" from 0 to 4095 step 13 do {
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _s];
  _uav setVariable ["position", [250,0,50]];
  private _w = call _waiter;
  _uav setVariable ["position", [-100,0,50]];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  private _low = (([_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement) # 1) == "LOW_RUN";
  if !(_w isEqualTo _low) then {_same = false;};
  if (_w) then {_nominated = _nominated + 1;};
  _n = _n + 1;
};
diag_log ["WAIT_SHARE", _nominated, _n];
[_same, "nominated while waiting = low when cleared, for every seed"] call _assert;
[_nominated > 0 && {abs ((_nominated / _n) - 0.15) < 0.06}, format ["about 15%% of waiting drones: %1 of %2", _nominated, _n]] call _assert;
''')
        self.assertIn('WAIT_SHARE', out)
        waits = [line for line in out.splitlines() if '[A3UE_FPV] lowWait ' in line]
        self.assertGreaterEqual(len(waits), 3, out[-3000:])
        self.assertRegex(waits[0], r'lowWait id=\S+ target=person ringM=500 rangeM=150$')
        self.assertFalse([line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line])

    def test_nothing_declines_and_a_paused_run_carries_on(self):
        out = self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
missionNamespace setVariable ["A3UE_FPV_QA_seed", 300];
_uav setVariable ["A3UE_FPV_mode", "TRACKING"];
private _start = {
  params ["_x0"];
  _uav setVariable ["position", [_x0,0,45]];
  _uav setVariable ["A3UE_FPV_lowRun", createHashMap];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement
};
private _track = {[_uav, _person, _identity] call A3UE_fnc_fpv_lowRunTrack};
// A 14 m tree on the line (LR-1d: declined, and the FLANK fallback drifted 550 m out, engine session
// 1d): surveyed, READY, the line over the tree; the engagement stays a low run.
["tree", [250,0,17], [2,2,7], [], "TREE"] call _place;
private _e = [60] call _start;
private _stages = [];
for "_i" from 0 to 60 do {FPV_time = FPV_time + 0.1; _stages pushBackUnique (call _track);};
private _record = _uav getVariable "A3UE_FPV_lowRun";
private _res = _record get "result";
[_stages isEqualTo ["CHECKING", "READY"] && {!(_record get "logged")} && {((_uav getVariable "A3UE_FPV_attackEngagement") # 1) == "LOW_RUN"}
  && {abs ((_res # 6) - 14) < 0.01} && {(_res # 7) == "tree.p3d"}, format ["flown over, not declined: %1 %2", _stages, _res select [5, 3]]] call _assert;
// A turn lost to another drone (LR-1d: ended, back on the fallback): nothing ends; 20 s later on the
// ring and cleared again, it surveys afresh and is ready again.
private _surveys = _record get "surveys";
FPV_time = FPV_time + 20;
private _again = [];
for "_i" from 0 to 15 do {FPV_time = FPV_time + 0.1; _again pushBackUnique (call _track);};
[_again isEqualTo ["READY"] && {(_record get "surveys") > _surveys} && {!(_record get "logged")}, format ["carries on %1", _again]] call _assert;
FPV_world = [];
// No survey back by 250 m (a starved scheduler): LATE. Nothing is rewritten: the engagement stays
// LOW_RUN, which the dive flies like DIRECT (straight in, no FLANK leg).
missionNamespace setVariable ["A3UE_FPV_lowRunCheckUnits", 2];
for "_i" from 0 to 29 do {["b" + str _i, [130 + 8 * _i, 0, 11], [1,1,1], [], "BUSH"] call _place;};
_e = [80] call _start;
call _track;
_uav setVariable ["position", [155,0,45]];
FPV_time = FPV_time + 0.1;
[(call _track) == "" && {((_uav getVariable "A3UE_FPV_lowRun") get "reason") == "LATE"} && {((_uav getVariable "A3UE_FPV_attackEngagement") # 1) == "LOW_RUN"}
  && {([_uav, _person, _identity, [1,2,3]] call A3UE_fnc_fpv_attackApproach) isEqualTo [1,2,3]}, "late: ended, flown straight in"] call _assert;
missionNamespace setVariable ["A3UE_FPV_lowRunCheckUnits", 16];
FPV_world = [];
// The master switch off after nomination.
_e = [60] call _start;
missionNamespace setVariable ["A3UE_FPV_lowRun", false];
[(call _track) == "" && {((_uav getVariable "A3UE_FPV_lowRun") get "reason") == "OFF"}, "switched off"] call _assert;
[!([_uav, _person, "", "OFF"] call A3UE_fnc_fpv_lowRunEnd), "ends once"] call _assert;
''')
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 2, out[-3000:])
        self.assertIn('result=ENDED reason=LATE ', lines[0])
        self.assertIn('result=ENDED reason=OFF ', lines[1])
        for line in lines:
            self.assertRegex(line, r'lowRun id=\S+ target=person result=ENDED reason=[A-Z]+ heightM=[\d.]+ handoffM=-1 glideDeg=-1 skimFromM=-1 '
                                   r'under5M=-1 minClearM=-1 hopTopM=[\d.]+ hopBy=\S+ surveys=\d+ sliceMsMax=[\d.]+ waited=0$')
        self.assertFalse(re.search(r'DECLINED|RISEN', out))

    def test_sweep_ends_what_is_over(self):
        out = self.vm(r'''
private _fresh = {
  params ["_stage"];
  _uav setVariable ["A3UE_FPV_lowRun", createHashMapFromArray [["key", [+_identity, "person", _uav getVariable ["A3UE_FPV_targetRevision", 0]]],
    ["stage", _stage], ["logged", false], ["height", 1.5], ["skim", 18], ["check", createHashMap], ["result", []]]];
};
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
"SKIM" call _fresh;
[!([_uav, objNull, "SWEEP", ""] call A3UE_fnc_fpv_lowRunEnd) && {([_uav, _person] call A3UE_fnc_fpv_lowRunStage) == "SKIM"}, "a current low run is left alone"] call _assert;
[[_uav, objNull, "SWEEP", "CONTROL"] call A3UE_fnc_fpv_lowRunEnd && {([_uav, _person] call A3UE_fnc_fpv_lowRunStage) == ""}, "control taken"] call _assert;
"SKIM" call _fresh;
_uav setVariable ["A3UE_FPV_targetRevision", 7];
[[_uav, objNull, "SWEEP", ""] call A3UE_fnc_fpv_lowRunEnd, "target changed"] call _assert;
_uav setVariable ["A3UE_FPV_targetRevision", 0];
"SPRINT" call _fresh;
[[_uav, _person, "", "MISSED"] call A3UE_fnc_fpv_lowRunEnd, "missed after the commit"] call _assert;
"SPRINT" call _fresh;
_uav setVariable ["A3UE_FPV_detonating", true]; _uav setVariable ["A3UE_FPV_lastDetonationReason", "DIRECT_CONTACT"];
[[_uav, objNull, "SWEEP", "STOPPED"] call A3UE_fnc_fpv_lowRunEnd, "stopped after its strike"] call _assert;
''')
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 4, out[-3000:])
        self.assertIn('result=ENDED reason=CONTROL ', lines[0])
        self.assertIn('result=ENDED reason=TARGET ', lines[1])
        self.assertIn('result=COMMITTED reason=MISSED ', lines[2])
        self.assertIn('result=COMMITTED reason=DIRECT_CONTACT ', lines[3])

    def test_contact_fence(self):
        self.vm(r'''
private _fence = {[_uav, _this] call A3UE_fnc_fpv_contactFence};
{
  _x params ["_vendor", "_flag"];
  _uav setVariable ["A3UE_FPV_vendorId", _vendor]; _uav setVariable [_flag, false]; _uav setVariable ["A3UE_FPV_contactFence", []];
  [!("NATIVE" call _fence), "nothing fired yet"] call _assert;
  ["SET" call _fence && {(_uav getVariable _flag) isEqualTo true} && {!("NATIVE" call _fence)}, format ["%1 fenced, ours", _vendor]] call _assert;
  ["RELEASE" call _fence && {(_uav getVariable _flag) isEqualTo false} && {(_uav getVariable "A3UE_FPV_contactFence") isEqualTo []}, "released"] call _assert;
  // The pack fired first: our fuse yields and never clears the pack's own flag.
  _uav setVariable [_flag, true];
  ["NATIVE" call _fence && {!("SET" call _fence)} && {!("RELEASE" call _fence)} && {(_uav getVariable _flag) isEqualTo true}, "native first"] call _assert;
  _uav setVariable [_flag, false];
  // A fence whose commit never came is lifted after 0.75 s, unless the drone is detonating.
  "SET" call _fence;
  [!("TICK" call _fence), "not yet"] call _assert;
  FPV_time = FPV_time + 1;
  _uav setVariable ["A3UE_FPV_detonating", true];
  [!("TICK" call _fence) && {(_uav getVariable _flag) isEqualTo true}, "kept while detonating"] call _assert;
  _uav setVariable ["A3UE_FPV_detonating", false];
  ["TICK" call _fence && {(_uav getVariable _flag) isEqualTo false}, "lifted"] call _assert;
} forEach [["fpv_ua", "UA_FPV_Detonated"], ["kvn", "kvn_detonated"], ["armafpv", "DB_fpv_isDetonating"]];
_uav setVariable ["A3UE_FPV_vendorId", "other"];
[!("SET" call _fence) && {!("NATIVE" call _fence)}, "no pack, no fence"] call _assert;
_uav setVariable ["local", false]; _uav setVariable ["A3UE_FPV_vendorId", "kvn"];
[!("SET" call _fence), "owner only"] call _assert;
''')

    def test_any_contact_fuse(self):
        self.vm(r'''
FPV_lastSend = [];
A3UE_fnc_fpv_sendLifecycle = {FPV_lastSend = +_this; true};
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
private _fuse = {
  params ["_pos", "_vel"];
  _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  private _e = [_uav, _person, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;
  [_e get "approved", _e get "detonationReason", _e get "contactPointASL"]
};
// A wall 0.8 m ahead: contact, at the wall.
private _wall = ["wall", [100.95,0,12], [0.15,3,2]] call _place;
private _r = [[100,0,12],[20,0,0]] call _fuse;
[(_r # 0) && {(_r # 1) == "SURFACE_CONTACT"} && {abs (((_r # 2) # 0) - 100.8) < 0.01}, format ["wall %1", _r]] call _assert;
// Through shouldDetonateNow and the proposal: the warhead goes 0.2 m short of the wall.
[[_uav, _person, _profile] call A3UE_fnc_fpv_shouldDetonateNow, "approved"] call _assert;
[[_uav, _person, "SURFACE_CONTACT", "NONE", _revision] call A3UE_fnc_fpv_detonateCompat, "proposal sent"] call _assert;
private _strike = FPV_lastSend # 2 # 0;
private _delivery = _strike get "deliveryPosASL";
[abs ((_delivery # 0) - 100.6) < 0.01 && {(_strike get "deliveryMode") == "CONTACT_POINT"} && {(_strike get "strikePathClass") == "SURFACE_CONTACT"}
  && {(_strike get "approvalPolicyClass") == "SURFACE_PRIMARY"} && {_strike get "deliveryPolicyMatch"}, format ["delivery %1", _strike]] call _assert;
// 2 m away it is not contact yet (one frame's travel plus margin, at least 1 m).
[!(([[98.5,0,12],[20,0,0]] call _fuse) # 0), "not yet"] call _assert;
// The drone's own crew is never contact.
_uav setVariable ["crew", [_wall]];
[!(([[100,0,12],[20,0,0]] call _fuse) # 0), "crew skipped"] call _assert;
_uav setVariable ["crew", []];
// The switch off: today's rules exactly.
missionNamespace setVariable ["A3UE_FPV_contactFuseAny", false];
[!(([[100,0,12],[20,0,0]] call _fuse) # 0), "switch off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_contactFuseAny", true];
// Not while the AI flies (TRACKING).
_uav setVariable ["A3UE_FPV_mode", "TRACKING"];
[!(([[100,0,12],[20,0,0]] call _fuse) # 0), "only the controller's attack"] call _assert;
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
FPV_world = [];
// The ground far from the target (the near-target ground rule does not apply there).
private _ground = [[100,0,10.3],[20,0,-10]] call _fuse;
[(_ground # 0) && {(_ground # 1) == "SURFACE_CONTACT"}, format ["ground %1", _ground]] call _assert;
// The sea: its surface plus a 0.5 m wave margin.
FPV_ground = {-5};
private _sea = [[100,0,0.4],[20,0,-2]] call _fuse;
[(_sea # 0) && {(_sea # 1) == "SURFACE_CONTACT"}, format ["sea %1", _sea]] call _assert;
FPV_ground = {10};
// A person in the way is contact too (hostile or not); the target itself is DIRECT_CONTACT first.
["soldier", [100.9,0,11], [0.3,0.3,0.9], ["Man","AllVehicles"], "", west] call _place;
[(([[100,0,11],[20,0,0]] call _fuse) # 1) == "SURFACE_CONTACT", "a soldier in the way"] call _assert;
FPV_world = [];
_uav setVariable ["A3UE_FPV_lastImpactValid", true]; _uav setVariable ["A3UE_FPV_lastImpactTargetNetId", "person"];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "DIRECT_BODY"]; _uav setVariable ["A3UE_FPV_impactAnchorObject", _person];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", [400,0,11.15]];
["body", [400,0,11], [0.3,0.3,0.9], ["Man","AllVehicles"], "", west] call _place;
[(([[399.5,0,11.15],[20,0,0]] call _fuse) # 1) == "DIRECT_CONTACT", "the target: DIRECT_CONTACT wins"] call _assert;
''')

    def test_low_fuse_rules(self):
        self.vm(r'''
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
_uav setVariable ["A3UE_FPV_lowRun", createHashMapFromArray [["key", [+_identity, "person", _revision]], ["stage", "SKIM"], ["logged", false],
  ["height", 1], ["skim", 18], ["check", createHashMap], ["result", []]]];
private _fuse = {
  params ["_pos", "_vel", ["_stage", "SKIM"]];
  (_uav getVariable "A3UE_FPV_lowRun") set ["stage", _stage];
  _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  private _e = [_uav, _person, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;
  [_e get "approved", _e get "detonationReason"]
};
// 15 deg downhill to the target: skimming 0.9 m above the slope at 25 m/s inside 15 m.
FPV_ground = {params ["_x0"]; 10 + 0.268 * (400 - _x0)};
private _vel = [25 * 0.966, 0, -25 * 0.259];
private _low = [[390,0,10 + 0.268 * 10 + 0.9], _vel] call _fuse;
[!(_low # 0), format ["low: the slope is not a dive into the ground %1", _low]] call _assert;
private _dive = [[390,0,10 + 0.268 * 10 + 0.9], _vel, "CHECKING"] call _fuse;
[(_dive # 0) && {(_dive # 1) == "GROUND_CONTACT"}, format ["not low: world sink rule as before %1", _dive]] call _assert;
FPV_ground = {10};
// Cover the drone has not reached: the obstruction fallback waits for real contact while low.
_uav setVariable ["A3UE_FPV_lastImpactValid", true]; _uav setVariable ["A3UE_FPV_lastImpactTargetNetId", "person"];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "OBSTRUCTION_SURFACE"]; _uav setVariable ["A3UE_FPV_impactAnchorObject", objNull];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", [200,0,11.5]];
[!(([[190,0,11.5],[18,0,0]] call _fuse) # 0), "low: no early burst at a bush on the line"] call _assert;
private _normal = [[190,0,11.5],[18,0,0], "CHECKING"] call _fuse;
[(_normal # 0) && {(_normal # 1) == "OBSTRUCTION_FALLBACK"}, format ["not low: cover rule as before %1", _normal]] call _assert;
''')


# Closed loop: the AI transit at 35 m (recorded, flown by the test) until the hand-off gate opens,
# then the controller's TERMINAL_VECTOR order every 50 ms with a perfect actuator: navigation,
# missed-pass rule, planning, the writer and the fuse at the current position, then 50 ms of motion
# checked in 10 ms steps against the body, the ground and the boxes. Scripted events fire when the
# drone passes an x.
FLY = r'''
_person setVariable ["box", [[-0.25,-0.25,0],[0.25,0.25,1.85],1]]; _person setVariable ["side", west];
FPV_world pushBack _person;
private _fly = {
  params ["_seed", "_intent", ["_events", []], ["_steps", 900], ["_transit", 35.15], ["_from", 430]];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", _intent];
  missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
  FPV_moves = []; FPV_poses = [];
  {_uav setVariable [_x, []];} forEach ["A3UE_FPV_trajectory","A3UE_FPV_terminalSteeringState",
    "A3UE_FPV_terminalPoseContext","A3UE_FPV_terminalPoseAttitude","A3UE_FPV_nativeControl"];
  {_uav setVariable [_x, createHashMap];} forEach ["A3UE_FPV_attackPass", "A3UE_FPV_attackReversal", "A3UE_FPV_lowRun"];
  {_uav setVariable [_x, 0];} forEach ["A3UE_FPV_terminalSteeringSerial","A3UE_FPV_terminalPoseSerial"];
  _uav setVariable ["A3UE_FPV_trajectoryAttemptAt", -1];
  _uav setVariable ["A3UE_FPV_mode", "TRACKING"];
  private _tp = _person getVariable "position";
  private _body = _tp vectorAdd [0,0,1.15];
  private _p = [(_tp # 0) - _from, 0, 0];
  _p set [2, ([_p # 0, 0] call FPV_ground) + _transit];
  _uav setVariable ["position", +_p]; _uav setVariable ["velocity", [22,0,0]];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement;
  private _gate = false;
  for "_i" from 0 to 400 do {
    if (!_gate) then {
      FPV_time = FPV_time + 0.1; FPV_observed = FPV_observed + 0.1; FPV_frame = FPV_frame + 6;
      _p = _p vectorAdd [2.2, 0, 0]; _p set [2, ([_p # 0, 0] call FPV_ground) + _transit];
      _uav setVariable ["position", +_p];
      [_uav, _person, _identity] call A3UE_fnc_fpv_lowRunTrack;
      _gate = [_uav, _person, _profile] call A3UE_fnc_fpv_shouldEnterTerminal;
    };
  };
  private _m = createHashMapFromArray [["end", "RUN"], ["handoffM", (_tp # 0) - (_p # 0)], ["closest", 1e9], ["refused", 0],
    ["minClear", 1e9], ["maxSkimClear", -1e9], ["maxDrift", 0], ["maxSkimSpeed", 0], ["maxSpeed", 0], ["stages", []],
    ["sprintM", -1], ["skimM", -1], ["maxZ", -1e9], ["path", []], ["descendS", -1], ["descendMaxSpeed", 0], ["skimEntrySpeed", -1],
    ["under5M", -1]];
  if (!_gate) exitWith {_m set ["end", "NO_HANDOFF"]; _m};
  _uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
  _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", FPV_time];
  _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
  private _enteredAt = FPV_time;
  private _v = [22, 0, 0];
  for "_i" from 0 to _steps do {
    if ((_m get "end") != "RUN") exitWith {};
    FPV_time = FPV_time + 0.05; FPV_observed = FPV_observed + 0.05; FPV_frame = FPV_frame + 3;
    {
      if (!(_x param [2, false]) && {(_p # 0) >= (_x # 0)}) then {_x set [2, true]; call (_x # 1);};
    } forEach _events;
    // The impact solution resolveImpactPoint would give for a man in the open: his body.
    {_uav setVariable [_x # 0, _x # 1];} forEach [["A3UE_FPV_lastImpactValid", true], ["A3UE_FPV_lastImpactTargetNetId", "person"],
      ["A3UE_FPV_terminalImpactMode", "DIRECT_BODY"], ["A3UE_FPV_impactAnchorObject", _person],
      ["A3UE_FPV_lastImpactPointASL", +_body], ["A3UE_FPV_lastImpactTelemetryAt", FPV_time]];
    private _nav = [_uav, _person, _identity] call A3UE_fnc_fpv_targetNavigation;
    private _current = _p vectorDistance (_nav # 5);
    private _last = _uav getVariable ["A3UE_FPV_lastTerminalVectorDistance", _current];
    if (_last < 0) then {_last = _current;};
    if (FPV_time > (_enteredAt + 0.15) && {_current > (_last + 8)}) then {
      _m set ["end", "MISSED"];
    } else {
      [_uav, _person, _profile, _identity # 3, _identity] call A3UE_fnc_fpv_prepareTrajectory;
      private _n = count FPV_moves;
      private _driven = [_uav, _person, _profile, _identity # 3, _identity] call A3UE_fnc_fpv_runTerminalVector;
      if (!_driven) then {_m set ["refused", (_m get "refused") + 1];};
      if (count FPV_moves > _n) then {_v = FPV_moves select (count FPV_moves - 1);};
      _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _last min _current];
      private _e = [_uav, _person, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;
      if (_e get "approved") then {
        _m set ["end", "FUSE"]; _m set ["reason", _e get "detonationReason"]; _m set ["at", +_p];
        if ((_e get "detonationReason") == "SURFACE_CONTACT") then {_m set ["at", _e get "contactPointASL"];};
        // As runController does once the strike is committed.
        [_uav, _person, "", _e get "detonationReason"] call A3UE_fnc_fpv_lowRunEnd;
      };
    };
    if ((_m get "end") == "RUN") then {
      for "_k" from 1 to 5 do {
        if ((_m get "end") == "RUN") then {
          private _pk = _p vectorAdd (_v vectorMultiply (0.01 * _k));
          private _d = _pk vectorDistance _body;
          if (_d < (_m get "closest")) then {_m set ["closest", _d];};
          if (_d <= 1.0) then {_m set ["end", "HIT"]; _m set ["at", +_pk];};
          if (((_pk # 2) - 0.15) <= ([_pk # 0, _pk # 1] call FPV_ground)) then {_m set ["end", "GROUND"]; _m set ["at", +_pk];};
          if ((FPV_world findIf {
            private _c = _x getVariable "position"; private _b = _x getVariable ["geom", _x getVariable "box"];
            !(_x isEqualTo _person) && {_x getVariable ["alive", true]}
              && {(_pk # 0) >= (_c # 0) + (_b # 0 # 0)} && {(_pk # 0) <= (_c # 0) + (_b # 1 # 0)}
              && {(_pk # 1) >= (_c # 1) + (_b # 0 # 1)} && {(_pk # 1) <= (_c # 1) + (_b # 1 # 1)}
              && {(_pk # 2) >= (_c # 2) + (_b # 0 # 2)} && {(_pk # 2) <= (_c # 2) + (_b # 1 # 2)}
          }) >= 0) then {_m set ["end", "COLLISION"]; _m set ["at", +_pk];};
        };
      };
      _p = _p vectorAdd (_v vectorMultiply 0.05);
      _uav setVariable ["position", +_p]; _uav setVariable ["velocity", +_v];
      if ((_p # 0) > (_tp # 0) + 30) then {_m set ["end", "PAST"];};
    };
    // Evidence: stages, clearance under the airframe, drift off the line, speeds.
    private _stage = (_uav getVariable ["A3UE_FPV_lowRun", createHashMap]) getOrDefault ["stage", ""];
    if ((_m get "stages") param [count (_m get "stages") - 1, ""] != _stage) then {
      (_m get "stages") pushBack _stage;
      if (_stage == "SKIM") then {
        _m set ["skimM", (_tp # 0) - (_p # 0)];
        _m set ["descendS", FPV_time - _enteredAt]; _m set ["skimEntrySpeed", vectorMagnitude _v];
      };
      if (_stage == "SPRINT") then {_m set ["sprintM", (_tp # 0) - (_p # 0)]; _m set ["sprintTtg", ((_tp # 0) - (_p # 0)) / ((vectorMagnitude _v) max 1)];};
    };
    private _clear = ((_p # 2) - 0.15) - ([_p # 0, _p # 1] call FPV_ground);
    private _range = _p distance2D _tp;
    if (_stage in ["SKIM", "SPRINT"] && {_range > 15}) then {
      _m set ["minClear", (_m get "minClear") min _clear];
      _m set ["maxDrift", (_m get "maxDrift") max (abs (_p # 1))];
    };
    if (_stage == "SKIM") then {
      _m set ["maxSkimClear", (_m get "maxSkimClear") max _clear];
      _m set ["maxSkimSpeed", (_m get "maxSkimSpeed") max (vectorMagnitude _v)];
    };
    if (_stage == "DESCEND") then {_m set ["descendMaxSpeed", (_m get "descendMaxSpeed") max (vectorMagnitude _v)];};
    if ((_m get "under5M") < 0 && {_stage in ["DESCEND", "SKIM", "SPRINT"]} && {_clear <= 5}) then {_m set ["under5M", _range];};
    _m set ["maxSpeed", (_m get "maxSpeed") max (vectorMagnitude _v)];
    _m set ["maxZ", (_m get "maxZ") max ((_p # 2) - ([_p # 0, _p # 1] call FPV_ground))];
    if (_i mod 10 == 0) then {(_m get "path") pushBack [round (_p # 0), (round ((_p # 1) * 10)) / 10, (round (_clear * 10)) / 10, _stage];};
  };
  _m set ["low", +(_uav getVariable ["A3UE_FPV_lowRun", createHashMap])];
  _m set ["pass", +(_uav getVariable ["A3UE_FPV_attackPass", createHashMap])];
  _m
};
private _brief = {params ["_m"]; [_m get "end", _m getOrDefault ["reason", ""], (round ((_m get "closest") * 100)) / 100,
  round (_m get "handoffM"), round (_m get "skimM"), round (_m get "sprintM"), (round ((_m get "minClear") * 100)) / 100,
  (round ((_m get "maxSkimClear") * 100)) / 100, (round ((_m get "maxDrift") * 100)) / 100, (round ((_m get "maxSkimSpeed") * 10)) / 10,
  (round ((_m get "maxSpeed") * 10)) / 10, _m get "refused", _m get "stages", (_m get "low") getOrDefault ["height", -1],
  (_m get "low") getOrDefault ["skim", -1], (_m get "low") getOrDefault ["reason", ""], (round ((_m get "maxZ") * 10)) / 10]};
// Clearance over the ground when the drone passes an x (set by an event).
FPV_marks = createHashMap;
private _mark = {params ["_x0", "_name"]; [_x0, compile format ["FPV_marks set ['%1', (_p # 2) - 0.15 - ([_p # 0, _p # 1] call FPV_ground)];", _name]]};
'''


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LowRunFlightSQF(unittest.TestCase):
    EXTRA = load(LOW) + load(['evaluateImpactWindow', 'shouldEnterTerminal'])

    def vm(self, body):
        r = run(SCENE + FLY + body, self.EXTRA, timeout=900)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-8000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-8000:])
        return r.stdout

    def test_open_field_direct_low_run(self):
        out = self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
private _rows = [];
{
  _profile = createHashMapFromArray [["familyId", _x],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  private _m = [11, "DIRECT"] call _fly;
  private _b = [_m] call _brief;
  _rows pushBack [_x, _b];
  private _skim = (_m get "low") get "skim";
  [(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]}, format ["%1 hits: %2", _x, _b]] call _assert;
  [(_m get "stages") isEqualTo ["DESCEND", "SKIM", "SPRINT", "ENDED"] || {(_m get "stages") isEqualTo ["DESCEND", "SKIM", "SPRINT"]}, format ["%1 stages %2", _x, _m get "stages"]] call _assert;
  // LR-1c: 35 m up, the drawn glide is down 250 m out from about 362 m.
  [(_m get "handoffM") <= 362.5 && {(_m get "handoffM") >= 340}, format ["%1 hand-off %2", _x, _m get "handoffM"]] call _assert;
  // Clearance held at the 1 m skim height (perfect actuator) and the drift within the corridor.
  [(_m get "minClear") >= 0.6 && {(_m get "maxSkimClear") <= 2.2}, format ["%1 clearance %2", _x, _b]] call _assert;
  [(_m get "maxDrift") <= 4.5, format ["%1 drift %2", _x, _m get "maxDrift"]] call _assert;
  // Skim at the sampled 15-20 m/s, then the sprint from about 60 m at attack speed.
  [(_m get "maxSkimSpeed") <= _skim + 0.5 && {(_m get "maxSpeed") > _skim + 4}, format ["%1 speeds %2", _x, _b]] call _assert;
  [(_m get "sprintM") <= 62 && {(_m get "sprintM") >= 40}, format ["%1 sprint from %2 m", _x, _m get "sprintM"]] call _assert;
  [(_m get "refused") == 0, format ["%1 refused steps %2", _x, _m get "refused"]] call _assert;
  [((_m get "low") get "logged") && {((_m get "low") get "minClear") >= 0.6}, "logged with its clearance"] call _assert;
  // The drawn 15-20 deg glide; the line down 250 m out and the level-out flown at the skim speed.
  private _glide = (_m get "low") getOrDefault ["glideUsed", -1];
  [_glide >= 15 && {_glide <= 20} && {(_m get "skimM") >= 215}, format ["%1 glide %2 deg, skim from %3 m", _x, _glide, _m get "skimM"]] call _assert;
} forEach ["kvn", "armafpv", "fpv_ua"];
diag_log ["OPEN_ROWS", _rows];
''')
        self.assertIn('OPEN_ROWS', out)
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 3, out[-3000:])
        for line in lines:
            self.assertRegex(line, r'result=COMMITTED reason=(DIRECT_CONTACT|PREDICTED_IMPACT) heightM=1 handoffM=3[4-6]\d glideDeg=(1[5-9]|20)(\.\d)? '
                                   r'skimFromM=2[1-4]\d under5M=2[3-7]\d minClearM=[\d.]+ hopTopM=0 hopBy=none surveys=\d+ sliceMsMax=[\d.]+ waited=0$')

    def test_high_arrival_glides_down_early_and_fast(self):
        out = self.vm(r'''
// LR-1c, from engine sessions 1 and 1b, kept: the AI hands over 90 m up (and a hill outpost adds the
// fall of the ground to the field). The glide must be down 250 m out over the ground there; the
// hand-off moves out (here to its 500 m limit) and the glide is steepened only as needed (89 m in
// 250 m: 19.6 deg); attack speed high up, braked to the skim speed by the start of the level-out.
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
private _rows = [];
private _check = {
  params ["_label", "_m", "_glideWant"];
  private _b = [_m] call _brief;
  private _low = _m get "low";
  private _skim = _low get "skim";
  private _row = [_label, _b, _low getOrDefault ["glideUsed", -1], _m get "descendS", _m get "descendMaxSpeed", _m get "skimEntrySpeed", _m get "under5M"];
  _rows pushBack _row;
  [(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]}, format ["%1 hits: %2", _label, _b]] call _assert;
  [abs ((_low getOrDefault ["glideUsed", -1]) - _glideWant) < 0.2 && {(_m get "handoffM") >= 480} && {(_m get "handoffM") <= 500},
    format ["%1 glide and hand-off %2", _label, _row]] call _assert;
  [(_m get "under5M") >= 220 && {(_m get "skimM") >= 195}, format ["%1 under 5 m from %2 m, skim from %3 m", _label, _m get "under5M", _m get "skimM"]] call _assert;
  [(_m get "descendS") >= 0 && {(_m get "descendS") <= 14}, format ["%1 descent %2 s", _label, _m get "descendS"]] call _assert;
  [(_m get "descendMaxSpeed") >= _skim + 6 && {(_m get "skimEntrySpeed") <= _skim + 1.5},
    format ["%1 fast glide, braked to the skim speed (%2 m/s): %3", _label, _skim, _row]] call _assert;
  [(_m get "minClear") >= 0.6 && {(_m get "maxSkimClear") <= 2.2}, format ["%1 clearance %2", _label, _b]] call _assert;
  [(_m get "refused") == 0, format ["%1 refused steps %2", _label, _m get "refused"]] call _assert;
};
{
  _profile = createHashMapFromArray [["familyId", _x],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  [_x, [11, "DIRECT", [], 1200, 90.15, 650] call _fly, atan (89 / 250)] call _check;
} forEach ["kvn", "armafpv", "fpv_ua"];
// EJ's outpost 1 (session 1b): the outpost on a hill, a fairly steep fall to a flat field, then
// level to the player. The AI keeps 90 m over the ground, so the glide starts 130 m above the field.
FPV_ground = {params ["_x0"]; if (_x0 < -50) then {50} else {if (_x0 < 150) then {50 - 0.2 * (_x0 + 50)} else {10}}};
_profile = createHashMapFromArray [["familyId", "kvn"],["roleId","AP"],["terminalVectorMaxSpeed",200]];
["hill", [11, "DIRECT", [], 1200, 90.15, 650] call _fly, atan (129 / 250)] call _check;
diag_log ["HIGH_ROWS", _rows];
''')
        self.assertIn('HIGH_ROWS', out)
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 4, out[-3000:])
        for line in lines[:3]:
            self.assertRegex(line, r'handoffM=(4[89]\d|500) glideDeg=19\.[5-7] skimFromM=(19[5-9]|2\d\d) ')
        self.assertRegex(lines[3], r'handoffM=(4[89]\d|500) glideDeg=27\.[2-4] skimFromM=(19[5-9]|2\d\d) ')

    def test_a_tree_on_the_line_is_hopped_and_the_drone_settles_back_down(self):
        out = self.vm(r'''
// EJ's favourite moment (session 1c): an 8 m tree on the line 200 m out, climbed on a 15 deg ramp,
// flown over, and back to skim height 50 m on.
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
["olive", [200,0,14], [2.5,2.5,4], [], "TREE"] call _place;
private _rows = [];
{
  _profile = createHashMapFromArray [["familyId", _x],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  FPV_marks = createHashMap;
  private _m = [11, "DIRECT", [[198, "over"] call _mark, [250, "after"] call _mark]] call _fly;
  private _b = [_m] call _brief;
  _rows pushBack [_x, _b, FPV_marks];
  [(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]} && {(_m get "refused") == 0}, format ["%1 hops and hits: %2", _x, _b]] call _assert;
  [(FPV_marks getOrDefault ["over", -1]) >= 8.2, format ["%1 over the tree at %2 m", _x, FPV_marks]] call _assert;
  [(FPV_marks getOrDefault ["after", -1]) >= 0.6 && {(FPV_marks getOrDefault ["after", 9]) <= 3}, format ["%1 back down 150 m out %2", _x, FPV_marks]] call _assert;
  [("SPRINT" in (_m get "stages")) && {(_m get "sprintM") >= 40} && {(_m get "minClear") >= 0.6}, format ["%1 sprints %2", _x, _b]] call _assert;
} forEach ["kvn", "armafpv", "fpv_ua"];
diag_log ["TALL_HOP_ROWS", _rows];
''')
        self.assertIn('TALL_HOP_ROWS', out)
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 3, out[-3000:])
        for line in lines:
            self.assertRegex(line, r'result=COMMITTED .* hopTopM=8 hopBy=olive\.p3d surveys=\d+ sliceMsMax=[\d.]+ waited=0$')

    def test_session_1d_blockers_are_flown(self):
        out = self.vm(r'''
// Engine session 1d declined 11 of 13 low runs. The same kinds of obstacle, flown (KVN, 1 m):
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
private _rows = [];
private _case = {
  params ["_label", "_build", ["_events", []], ["_ends", ["FUSE"]]];
  FPV_world = [_person]; FPV_marks = createHashMap;
  call _build;
  private _m = [11, "DIRECT", _events] call _fly;
  private _b = [_m] call _brief;
  _rows pushBack [_label, _b, FPV_marks, (_m get "low") getOrDefault ["hopTop", 0], (_m get "low") getOrDefault ["hopBy", ""]];
  [(_m get "end") in _ends && {!((_m get "end") in ["COLLISION", "GROUND", "NO_HANDOFF"])}, format ["%1: %2", _label, _b]] call _assert;
  [(_m get "refused") == 0, format ["%1: refused steps %2", _label, _b]] call _assert;
  _m
};
// A 15 m pine on the line 150 m out (2:2512): over it and back down.
private _m = ["pine", {["t_pinuss2s_f", [250,0,17.5], [2.5,2.5,7.5], [], "TREE"] call _place;}, [[248, "over"] call _mark, [320, "after"] call _mark]] call _case;
[(FPV_marks get "over") >= 15.2 && {(FPV_marks get "after") <= 3}, format ["pine %1", FPV_marks]] call _assert;
// An 11 m fig 14 m in front of the player (2:2926): it comes over the tree and down at him, or just
// over his head and flips (a miss is a pass, never a collision with the tree).
_m = ["fig near", {["t_ficusb1s_f", [386,0,15.5], [2,2,5.5], [], "TREE"] call _place;}, [[386, "over"] call _mark], ["FUSE", "MISSED", "PAST"]] call _case;
[(FPV_marks get "over") >= 11.2, format ["over the fig %1", FPV_marks]] call _assert;
// A power-line wire across the line 112 m out (2:1741), its cable 8 m up: skimmed under.
_m = ["wire", {
  private _w = ["highvoltagecolumnwire_f", [288,0,19.4], [0.2,40,9.4], [], "POWER LINES"] call _place;
  _w setVariable ["geom", [[-0.2,-40,-1.5],[0.2,40,-1.3],1]];
}, [[288, "under"] call _mark]] call _case;
[(FPV_marks get "under") <= 2.5 && {(_m get "maxSkimClear") <= 2.2}, format ["under the wire %1", FPV_marks]] call _assert;
// An 18 m oak 3 m beside the line (2:2428, engine session 1c): inside the corridor, flown over.
_m = ["oak beside", {["t_quercusir2s_f", [250,9,19.1], [6,6,9.1], [], "TREE"] call _place;}, [[250, "beside"] call _mark]] call _case;
[(FPV_marks get "beside") >= 18.2, format ["over the oak %1", FPV_marks]] call _assert;
// The same oak 6 m beside the line: outside the corridor, passed low.
_m = ["oak outside", {["t_quercusir2s_f", [250,12,19.1], [6,6,9.1], [], "TREE"] call _place;}, [[250, "beside"] call _mark]] call _case;
[(FPV_marks get "beside") <= 2.5 && {(_m get "maxSkimClear") <= 2.2}, format ["past the oak, low %1", FPV_marks]] call _assert;
// A wood (an olive grove on the line, 100-250 m out): a treetop run, then down for the finish.
_m = ["wood", {
  for "_i" from 0 to 15 do {["olive" + str _i, [150 + 10 * _i, ((_i mod 3) - 1) * 3, 16], [2.5,2.5,6], [], "TREE"] call _place;};
}, [[230, "in"] call _mark, [340, "out"] call _mark]] call _case;
// (The planned path answers 1-1.5 s late: 60 m out, 20 m past the line's foot, it is still settling.)
[(FPV_marks get "in") >= 12.2 && {(FPV_marks get "out") <= 5}, format ["treetop, then low %1", FPV_marks]] call _assert;
diag_log ["BLOCKER_ROWS", _rows];
''')
        self.assertIn('BLOCKER_ROWS', out)
        # Five strikes logged here; the fig's pass over the head is a miss, which the controller logs
        # (reason=MISSED) and follows with the 1.0.7 flip and re-dive.
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 5, out[-3000:])
        self.assertIn('hopBy=t_pinuss2s_f.p3d', lines[0])
        self.assertIn('hopTopM=0 hopBy=none', lines[1])
        self.assertIn('hopBy=t_quercusir2s_f.p3d', lines[2])
        # Outside the corridor: at most a ray grazing its edge (the line a little off the true centre
        # as the pilot's estimate moves); never flown over.
        self.assertRegex(lines[3], r'hopTopM=(0|0\.\d) ')
        # The wood: a treetop run; within 5 m of the ground only after it.
        self.assertRegex(lines[4], r'under5M=\d+ minClearM=[\d.]+ hopTopM=12 hopBy=olive\d+\.p3d ')

    def test_uphill_to_the_target_is_climbed_low(self):
        out = self.vm(r'''
// Engine session 1d (2:9117): TERRAIN declined, the ground rising 43 m to the player. A 23 deg slope
// from 200 m out: the line climbs at 15 deg ahead of it and follows it up, then low to the target.
FPV_ground = {params ["_x0"]; if (_x0 < 200) then {10} else {if (_x0 < 300) then {10 + 0.43 * (_x0 - 200)} else {53}}};
_person setVariable ["position", [400,0,53]];
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
FPV_marks = createHashMap;
private _m = [11, "DIRECT", [[250, "slope"] call _mark, [340, "top"] call _mark]] call _fly;
private _b = [_m] call _brief;
diag_log ["UPHILL", _b, FPV_marks, (_m get "path") select {(_x # 0) > 100}];
[(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]} && {(_m get "refused") == 0}, format ["climbs and hits %1", _b]] call _assert;
[(FPV_marks get "slope") >= 0.6 && {(FPV_marks get "slope") <= 25} && {(FPV_marks get "top") >= 0.6} && {(FPV_marks get "top") <= 3}, format ["up the slope, low on top %1", FPV_marks]] call _assert;
''')
        self.assertIn('UPHILL', out)

    def test_skim_range_is_recorded_over_bushes(self):
        out = self.vm(r'''
// LR-1d, engine session 1c (2:3777): over a field of bushes the skim range went unrecorded. The line
// flies 0.7 m over each bush; the skim begins where the glide meets that line.
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
for "_i" from 0 to 15 do {["b" + str _i, [140 + 14 * _i, 0.8 * ((_i mod 3) - 1), 11.1], [0.8,0.8,1.1], [], "BUSH"] call _place;};
private _rows = [];
{
  _profile = createHashMapFromArray [["familyId", _x],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  private _m = [11, "DIRECT"] call _fly;
  private _b = [_m] call _brief;
  private _low = _m get "low";
  _rows pushBack [_x, _b, _low getOrDefault ["skimFrom", -1], _m get "under5M"];
  [(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]} && {(_m get "refused") == 0}, format ["%1 hits over the bushes %2", _x, _b]] call _assert;
  [(_low getOrDefault ["skimFrom", -1]) >= 200 && {(_m get "under5M") >= 220}, format ["%1 skim from %2 m, under 5 m from %3 m", _x, _low getOrDefault ["skimFrom", -1], _m get "under5M"]] call _assert;
} forEach ["kvn", "armafpv", "fpv_ua"];
diag_log ["BUSH_ROWS", _rows];
''')
        self.assertIn('BUSH_ROWS', out)
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 3, out[-3000:])
        for line in lines:
            self.assertRegex(line, r'skimFromM=2\d\d .* hopTopM=2\.2 hopBy=b\d+\.p3d ')

    def test_terrain_following_hops_and_intents(self):
        out = self.vm(r'''
// Rising 4% to x = 200, a 4 m hump at 230, flat, then 8.5 deg down to the target at x = 400.
FPV_ground = {params ["_x0"];
  private _z = 20 + 0.04 * (_x0 min 200) + 4 * (exp (-(((_x0 - 230) / 25) ^ 2)));
  if (_x0 > 280) then {_z = _z - 0.15 * (_x0 - 280);};
  _z};
_person setVariable ["position", [400, 0, [400, 0] call FPV_ground]];
// A 1.5 m wall across the path at x = 330 (flown over).
["wall", [330, 0, ([330, 0] call FPV_ground) + 0.75], [0.2, 12, 0.75], [], "WALL"] call _place;
private _rows = [];
{
  _x params ["_seed", "_intent", "_ends"];
  missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", -1];
  private _m = [_seed, _intent] call _fly;
  private _b = [_m] call _brief;
  _rows pushBack [_seed, _intent, _b];
  private _h = (_m get "low") get "height";
  [(_m get "end") in _ends, format ["%1 seed %2 ends %3", _intent, _seed, _b]] call _assert;
  [(_m get "minClear") >= (_h - 0.6) min 0.6 && {(_m get "minClear") > 0.3}, format ["%1 clearance %2 (h %3)", _intent, _m get "minClear", _h]] call _assert;
  [(_m get "refused") == 0, "no refused steps on the hump and the hop"] call _assert;
  [(_m get "maxDrift") <= 4.5, format ["drift %1", _m get "maxDrift"]] call _assert;
  if (_intent == "GROUND_SHORT") then {
    // From a skim the last descent is shallow, so the near-target ground rule (0.6 m) fires a few
    // metres before the aimed point.
    private _at = _m get "at";
    [(_at distance2D (_person getVariable "position")) <= 7, format ["ground strike near the target %1", _at]] call _assert;
  };
  if (_intent == "OVER_TOP") then {
    // Down an 8.5 deg slope the steering lag carries the pass about 0.3-0.5 m higher than on the flat.
    [(_m get "closest") >= 1.0 && {(_m get "closest") <= 2.2}, format ["just over the head: %1 m", _m get "closest"]] call _assert;
  };
} forEach [[11, "DIRECT", ["FUSE"]], [300, "DIRECT", ["FUSE"]], [2047, "GROUND_SHORT", ["FUSE"]], [11, "OVER_TOP", ["PAST", "MISSED"]]];
diag_log ["TERRAIN_ROWS", _rows];
''')
        self.assertIn('TERRAIN_ROWS', out)

    def test_near_misses_on_flat_ground(self):
        out = self.vm(r'''
// The dive's near-miss bands (F4-2c): just over the head 1.05-1.6 m from the body point, beside it
// 1.2-1.9 m, from any skim height: the sprint flies at the pass height before the last second.
// LL-1: over the head up to 1.7 m (LR-1d: 1.56-1.57; LL-1 1.6-1.65, the 3.5 m weave reach moving
// where the drone sits sideways as it passes; 0.1 m on a pass about 1 m over the head).
private _rows = [];
{
  _x params ["_seed", "_intent", "_h", "_low", "_high"];
  missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", _h];
  private _m = [_seed, _intent] call _fly;
  private _b = [_m] call _brief;
  _rows pushBack [_intent, _seed, _h, _b];
  [(_m get "end") in ["MISSED", "PAST"] && {(_m get "closest") >= _low} && {(_m get "closest") <= _high},
    format ["%1 from %2 m: %3", _intent, _h, _b]] call _assert;
} forEach [[11, "OVER_TOP", 1.0, 1.05, 1.7], [11, "OVER_TOP", 4.0, 1.05, 1.7], [300, "OVER_SIDE", 1.0, 1.2, 1.9], [2047, "OVER_SIDE", 2.3, 1.2, 1.9]];
diag_log ["NEAR_MISS_ROWS", _rows];
''')
        self.assertIn('NEAR_MISS_ROWS', out)

    def test_a_soldier_who_walks_into_the_line_is_flown_over(self):
        out = self.vm(r'''
// LR-1d: a friendly soldier walking into the lane mid-run made the run rise one way. Now the next
// survey (about once a second) raises the line over him and the drone comes back down after him.
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.0];
private _friend = ["friend", [-1000, 0, 10.9], [0.3, 0.3, 0.9], ["Man","AllVehicles"], "", east] call _place;
FPV_marks = createHashMap;
private _m = [11, "DIRECT", [[180, {_friend setVariable ["position", [290, 0.5, 10.9]];}], [289, "over"] call _mark, [330, "after"] call _mark]] call _fly;
private _b = [_m] call _brief;
diag_log ["WALK_IN", _b, FPV_marks];
[(_m get "end") == "FUSE" && {(_m get "reason") in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]}, format ["flown over him, and still hit %1", _b]] call _assert;
[(FPV_marks get "over") >= 2.4 && {(FPV_marks get "after") <= 3}, format ["over his head, then down %1", FPV_marks]] call _assert;
''')
        self.assertIn('WALK_IN', out)
        self.assertFalse(re.search(r'RISEN', out))


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LowRunControllerSQF(unittest.TestCase):
    """The whole controller tick (LT-2 harness): tracking, the survey, the hand-off gate, the low
    flight through the director, and the end of the run. Native AI orders are stand-ins."""
    EXTRA = None

    @classmethod
    def setUpClass(cls):
        import test_lt2_wing as lt2
        controller = [('_uav forceSpeed (_native # 2);', 'FPV_restores=FPV_restores+1;'),
                      ('if (_externalControl != (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {',
                       'if (_externalControl isNotEqualTo (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {'),
                      ('_surfaceObject worldToModel (ASLToAGL _impactPointAsl)', '(_impactPointAsl vectorDiff (getPosASL _surfaceObject))'),
                      ('_anchorObject modelToWorldWorld _anchor', '((getPosASL _anchorObject) vectorAdd _anchor)')]
        overwatch = [('_uav enableAI "ALL";', ''), ('_uav setBehaviour "CARELESS";', ''), ('_uav setCombatMode "BLUE";', ''),
                     ('_uav setSpeedMode "NORMAL";', ''), ('_uav flyInHeight _height;', 'FPV_fly pushBack _height;'),
                     ('_uav forceSpeed _speed;', 'FPV_speeds pushBack _speed;'), ('_uav doMove _moveTargetAtl;', 'FPV_moveTo pushBack _moveTargetAtl;')]
        cls.TICK = lt2.TICK_SETUP
        cls.EXTRA = (lt2.load('runController', controller) + lt2.load('overwatch', overwatch) + lt2.load('directorFrame')
                     + lt2.load('perfReport', [('round diag_fps', '33')])
                     + lt2.load('controllerState', [('addMissionEventHandler ["EachFrame", {call A3UE_fnc_fpv_directorFrame}]', '7')])
                     + ''.join(lt2.load(n) for n in ['controllerSleep', 'shouldEnterTerminal', 'emptyImpactSolution', 'resolveImpactPoint',
                                                     'traceAttackRay', 'isAlliedAttacker', 'shouldDetonateNow', 'evaluateImpactWindow'])
                     + load(LOW)
                     + f'FPV_realEngagement={{{adapt_helper("attackEngagement", source("attackEngagement"))}}};\n')

    def sqf(self, body):
        r = run(self.TICK + r'''
A3UE_fnc_fpv_attackEngagement = FPV_realEngagement;
A3UE_fnc_fpv_isTargetObstructed = {createHashMapFromArray [["blocked", false]]};
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN"];
missionNamespace setVariable ["A3UE_FPV_QA_lowRunHeight", 1.5];
{_x setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];} forEach [_uav];
_person setVariable ["position", [400,0,10]];
_uav setVariable ["position", [-60,0,45]]; _uav setVariable ["velocity", [22,0,0]];
// The AI's transit (tracking, 10 passes a second) is flown by the test at 22 m/s and 35 m.
private _transit = {
  FPV_time = FPV_time + 0.1; FPV_observed = FPV_observed + 0.1; FPV_frame = FPV_frame + 4;
  private _p = (_uav getVariable "position") vectorAdd [2.2, 0, 0]; _p set [2, 45];
  _uav setVariable ["position", _p];
  [_uav, _state] call _tick
};
// Director frames (33 ms) with the writer's velocity applied, as the airframe would.
private _fly = {
  private _n = count FPV_moves;
  call _frame;
  if (count FPV_moves > _n) then {_uav setVariable ["velocity", FPV_moves select (count FPV_moves - 1)];};
  _uav setVariable ["position", (_uav getVariable "position") vectorAdd ((_uav getVariable "velocity") vectorMultiply 0.03)];
};
private _stage = {(_uav getVariable ["A3UE_FPV_lowRun", createHashMap]) getOrDefault ["stage", ""]};
''' + body, self.EXTRA, timeout=900)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-8000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-8000:])
        return r.stdout

    def test_controller_surveys_hands_off_low_and_ends_on_a_lost_target(self):
        out = self.sqf(r'''
// Search and adopt, then track in at transit height while the path is surveyed.
[_uav, _state] call _tick;
private _entry = -1; private _stages = [];
for "_i" from 0 to 160 do {
  if (_entry < 0) then {
    call _transit;
    _stages pushBackUnique (call _stage);
    if ((_uav call _mode) == "TERMINAL_VECTOR") then {_entry = 400 - ((_uav getVariable "position") # 0);};
  };
};
diag_log ["ENTRY", _entry, _stages, (_uav getVariable "A3UE_FPV_lowRun") get "surveys"];
// The harness acquires the man at about 350 m, so the run is nominated there, surveyed once and
// handed off in the tick its survey comes back (READY and DESCEND in one tick).
[("CHECKING" in _stages) && {((_uav getVariable "A3UE_FPV_lowRun") get "surveys") >= 1}, format ["surveyed first %1", _stages]] call _assert;
[_entry <= 350 && {_entry >= 300}, format ["the low-run gate hands off at %1 m", _entry]] call _assert;
// The director flies it: glide, then skim, with the writer the dive uses (no new writer).
for "_i" from 1 to 300 do {call _fly;};
private _p = _uav getVariable "position";
diag_log ["LOW", call _stage, _p];
[(call _stage) == "SKIM" && {((_p # 2) - 10) < 3} && {(_uav call _mode) == "TERMINAL_VECTOR"}, format ["skimming %1 at %2", call _stage, _p]] call _assert;
[(_uav getVariable ["A3UE_FPV_nativeControl", []]) isNotEqualTo [], "every step written"] call _assert;
// The target dies: the tick drops the dive and the run ends with its line.
_person setVariable ["alive", false];
call _fly;
[(call _stage) == "ENDED" && {((_uav getVariable "A3UE_FPV_lowRun") get "reason") == "TARGET"}, format ["ended %1", call _stage]] call _assert;
''')
        self.assertIn('ENTRY', out)
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 1, out[-3000:])
        self.assertIn('result=ENDED reason=TARGET ', lines[0])

    def test_second_drone_waits_on_the_outer_ring_and_goes_low(self):
        out = self.sqf(r'''
// LR-1c, EJ's scenario under the QA switch LOW_RUN_WING: the first drone attacks the normal way,
// the second waits on the low run's 500 m ring (not the 140 m one) and is low when cleared.
// (The harness acquires the man inside about 350 m, so both start there.)
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN_WING"];
private _step = {params ["_dt"]; FPV_time = FPV_time + _dt; FPV_observed = FPV_observed + _dt; FPV_frame = FPV_frame + 3;};
_uav setVariable ["position", [60,0,45]];
private _d2 = ["VMUAV", "d2"] call _make; _d2 setVariable ["position", [55,10,45]];
private _s2 = [_d2, "d2", 3] call _ready;
_d2 setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
[_uav, _state] call _tick; [0.1] call _step; [_uav, _state] call _tick;
private _first = _uav getVariable ["A3UE_FPV_attackEngagement", []];
[(_uav getVariable ["A3UE_FPV_attackRole", ""]) == "ATTACK" && {(_first param [1, ""]) != "LOW_RUN"},
  format ["first drone cleared, not low: %1 %2", _uav getVariable ["A3UE_FPV_attackRole", ""], _first param [1, ""]]] call _assert;
[_d2, _s2] call _tick; [0.1] call _step;
FPV_moveTo = [];
[_d2, _s2] call _tick;
[(_d2 getVariable ["A3UE_FPV_attackRole", ""]) == "OVERWATCH" && {count FPV_moveTo == 1}, format ["second drone waits %1", FPV_moveTo]] call _assert;
private _order = FPV_moveTo # 0;
[abs (([_order # 0, _order # 1, 0] distance2D [400,0,0]) - 500) < 0.5, format ["on the 500 m ring: %1", _order]] call _assert;
// The first drone is shot down; after the follow-up delay the second is cleared, and is low.
_uav setVariable ["alive", false];
[_uav, _state] call _tick;
[0.5] call _step; [_d2, _s2] call _tick;
[(_d2 getVariable ["A3UE_FPV_attackRole", ""]) == "OVERWATCH", "not during the follow-up delay"] call _assert;
[3.1] call _step; [_d2, _s2] call _tick;
private _second = _d2 getVariable ["A3UE_FPV_attackEngagement", []];
[(_d2 getVariable ["A3UE_FPV_attackRole", ""]) == "ATTACK" && {(_second param [1, ""]) == "LOW_RUN"} && {([_d2, _person] call A3UE_fnc_fpv_lowRunStage) in ["CHECKING", "READY"]},
  format ["cleared and low: %1 %2", _second param [1, ""], [_d2, _person] call A3UE_fnc_fpv_lowRunStage]] call _assert;
''')
        self.assertRegex(out, r'lowWait id=d2 target=person ringM=500 rangeM=345')
        self.assertRegex(out, r'wing target=person event=CLEARED id=d2 rangeM=34\d ')

    def test_opening_wait_nominates_only_the_second_drone(self):
        out = self.sqf(r'''
// LR-1d, engine session 1c (W1); engine session 1d: 5 of 5 first drones attacked normally. An earlier
// attack on the same target left its holder on the board, so each pair starts with the follow-up
// delay and both drones wait. Under LOW_RUN_WING neither is nominated then; the first one cleared
// attacks as it would, and only the one waiting behind it goes low.
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "LOW_RUN_WING"];
private _step = {params ["_dt"]; FPV_time = FPV_time + _dt; FPV_observed = FPV_observed + _dt; FPV_frame = FPV_frame + 3;};
private _old = ["VMUAV", "old"] call _make; _old setVariable ["alive", false];
missionNamespace setVariable ["A3UE_FPV_attackBoard", createHashMapFromArray [["person", createHashMapFromArray [
  ["holders", [[_old, 0, -1]]], ["queue", []], ["nextGrantAt", 0], ["grants", 1], ["target", _person]]]]];
_uav setVariable ["position", [60,0,45]];
private _d2 = ["VMUAV", "d2"] call _make; _d2 setVariable ["position", [55,10,45]];
private _s2 = [_d2, "d2", 3] call _ready;
_d2 setVariable ["A3UE_FPV_linkModel", "FIBER_VISUAL"];
[_uav, _state] call _tick; [_d2, _s2] call _tick; [0.1] call _step;
[_uav, _state] call _tick; [_d2, _s2] call _tick;
[(_uav getVariable ["A3UE_FPV_attackRole", ""]) == "OVERWATCH" && {(_d2 getVariable ["A3UE_FPV_attackRole", ""]) == "OVERWATCH"},
  format ["both wait out the delay: %1 %2", _uav getVariable ["A3UE_FPV_attackRole", ""], _d2 getVariable ["A3UE_FPV_attackRole", ""]]] call _assert;
[(_uav getVariable ["A3UE_FPV_lowWaiter", []]) isEqualTo [] && {(_d2 getVariable ["A3UE_FPV_lowWaiter", []]) isEqualTo []}, "nobody nominated in the delay"] call _assert;
for "_i" from 1 to 8 do {[0.5] call _step; [_uav, _state] call _tick; [_d2, _s2] call _tick;};
private _first = _uav getVariable ["A3UE_FPV_attackEngagement", []];
[(_uav getVariable ["A3UE_FPV_attackRole", ""]) == "ATTACK" && {(_first param [1, ""]) != "LOW_RUN"},
  format ["the first drone attacks as it would: %1", _first param [1, ""]]] call _assert;
[(_d2 getVariable ["A3UE_FPV_attackRole", ""]) == "OVERWATCH" && {((_d2 getVariable ["A3UE_FPV_lowWaiter", []]) param [1, false])},
  "the drone waiting behind it is nominated"] call _assert;
''')
        waits = [line for line in out.splitlines() if '[A3UE_FPV] lowWait ' in line]
        self.assertEqual(len(waits), 1, out[-3000:])
        self.assertIn('lowWait id=d2 ', waits[0])

    def test_control_takeover_ends_the_low_run(self):
        out = self.sqf(r'''
[_uav, _state] call _tick;
for "_i" from 0 to 160 do {if ((_uav call _mode) != "TERMINAL_VECTOR") then {call _transit;};};
for "_i" from 1 to 60 do {call _fly;};
[(call _stage) in ["DESCEND", "SKIM"], format ["low %1", call _stage]] call _assert;
// A player takes the drone: autonomy suspends, the low run ends and is never resumed.
_uav setVariable ["controlled", true];
call _fly; [_uav, _state] call _tick;
[(_uav call _mode) == "IDLE" && {(call _stage) == "ENDED"} && {((_uav getVariable "A3UE_FPV_lowRun") get "reason") == "CONTROL"}, format ["control %1", call _stage]] call _assert;
_uav setVariable ["controlled", false];
FPV_time = FPV_time + 0.6; [_uav, _state] call _tick;
[([_uav, _person] call A3UE_fnc_fpv_lowRunStage) == "", "released: not low again"] call _assert;
''')
        lines = [line for line in out.splitlines() if '[A3UE_FPV] lowRun ' in line]
        self.assertEqual(len(lines), 1, out[-3000:])
        self.assertIn('result=ENDED reason=CONTROL ', lines[0])


class LowRunSource(unittest.TestCase):
    def test_functions_registered_and_present(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text(encoding='utf-8')
        for name in LOW:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)
        # LL-1: the stall watchdog is gone (shelved with LR-1d; the only hang followed a decline).
        self.assertNotIn('attackStallWatch', config)
        self.assertFalse((FPV / 'fn_fpv_attackStallWatch.sqf').exists())

    def test_the_low_run_stays_small(self):
        # EJ, 16 November: "how complex is this getting just for low flight?" LL-1 replaced about
        # 1,130 lines of decision code with about 785. Growing past the budget is a decision to take
        # with EJ, not a side effect of a fix.
        lines = sum(len(source(name).splitlines()) for name in LOW_CODE)
        self.assertLessEqual(lines, LOW_CODE_BUDGET, lines)

    def test_no_workers_broadcasts_random_suspension_or_movement(self):
        for name in LOW:
            s = code(name)
            self.assertNotRegex(s, r'\b(sleep|uiSleep|waitUntil|spawn|execVM|remoteExec|remoteExecCall|publicVariable'
                                   r'|hint|hintSilent|hintC|addMissionEventHandler|random)\b', name)
            # Nothing is broadcast (the three-element form); the fence's own local flag write is two elements.
            self.assertNotRegex(s, r'setVariable \[[^\],]*,[^\]]*,\s*true\]', name)
            # No new movement writer: the TERMINAL_VECTOR writer flies every low stage.
            self.assertNotRegex(s, r'\b(setVelocity|setVectorDirAndUp|setPos\w*|doMove|flyInHeight|forceSpeed|enableAI|disableAI)\b', name)
        # The sender fence comes before any state is touched.
        for name in ['lowRunTrack', 'lowRunCheck', 'lowRunAim', 'lowRunEnd', 'contactFence']:
            s = code(name)
            first = min(i for i in (s.find(' set ['), s.find('setVariable [')) if i >= 0)
            self.assertLess(s.index('call A3UE_fnc_fpv_helperAccess'), first, name)
        # The world queries are bounded per call.
        check = code('lowRunCheck')
        self.assertIn('while {_i < _n && {_units < _budget}} do {', check)
        self.assertIn('while {_k < _steps && {_units < _budget}} do {', check)
        self.assertIn('while {_line < 5 && {_units < _budget}} do {', check)

    def test_nothing_declines_or_rises(self):
        # LL-1: one rule, the lowest safe line. No decline, no one-way rise, no fallback rewrite, no
        # radio-link check (fiber drones only), anywhere in the low run.
        for name in LOW_CODE:
            s = code(name)
            self.assertNotRegex(s, r'"(DECLINED|RISEN|BLOCKED|CLEAR|NARROW|COVER|LINK|JAMMER)"', name)
        self.assertNotIn('_fallback', code('lowRunEnd'))
        self.assertNotIn('sampleRadioLink', code('lowRunCheck'))
        # Wires are passed under by their box; the rays still meet a real cable.
        self.assertIn('!("wire" in (toLower ([_object] call _nameOf)))', code('lowRunCheck'))

    def test_draw_is_appended_fiber_only_and_carries_no_fallback(self):
        s = code('attackEngagement')
        self.assertEqual(s.count('random'), 1)
        self.assertLess(s.index('private _b = call _draw;'), s.index('private _lowDraw = call _draw;'))
        self.assertLess(s.index('private _parameters = switch (_profile) do {'), s.index('private _lowDraw = call _draw;'))
        self.assertIn('_parameters = [_height, _skim, _glide];', s)
        self.assertIn('&& {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) != "RADIO"}', s)
        self.assertIn('case ((_settings # 7) in ["DIRECT", "HIGH_DIVE", "FLANK"]): {_settings # 7};', s)

    def test_controller_wiring(self):
        c = code('runController')
        tracking = c.split('case "TRACKING": {', 1)[1].split('case "LOST_TARGET": {', 1)[0]
        overwatch, attack = tracking.split('if (_role == "OVERWATCH") then {', 1)[1].split('} else {', 1)
        # LL-1: a turn lost to another drone keeps the low run (LR-1d ended it on its fallback).
        self.assertNotIn('lowRunEnd', overwatch)
        self.assertLess(overwatch.index('call A3UE_fnc_fpv_lowRunWaiter);'), overwatch.index('call A3UE_fnc_fpv_overwatch;'))
        self.assertIn('_guidanceRevision, _ring] call A3UE_fnc_fpv_overwatch;', overwatch)
        self.assertLess(attack.index('fpv_attackEngagement'), attack.index('fpv_lowRunTrack'))
        self.assertLess(attack.index('fpv_lowRunTrack'), attack.index('fpv_shouldEnterTerminal'))
        self.assertNotIn('StallWatch', c)
        self.assertNotIn('"refused"', c)
        vector = c.split('case "TERMINAL_VECTOR": {', 1)[1].split('default {', 1)[0]
        self.assertIn('[_uav, _target, "", "MISSED_FLIP"] call A3UE_fnc_fpv_lowRunEnd;', vector)
        self.assertIn('[_uav, _target, "", "MISSED"] call A3UE_fnc_fpv_lowRunEnd;', vector)
        self.assertLess(c.index('[_uav, "SET"] call A3UE_fnc_fpv_contactFence;'), c.index('call _tryStrike;'))
        self.assertLess(c.index('call _tryStrike;'), c.index('if (clientOwner == 2) then {[_uav, "RELEASE"] call A3UE_fnc_fpv_contactFence;};'))
        self.assertIn('&& {!([_uav, "NATIVE"] call A3UE_fnc_fpv_contactFence)}) then {', c)
        self.assertIn('[_uav, objNull, "SWEEP", ["", "CONTROL"] select _externalControl] call A3UE_fnc_fpv_lowRunEnd;', c)
        stopped = c.split('if (!_running) then {', 1)[1]
        self.assertIn('[_uav, objNull, "SWEEP", "STOPPED"] call A3UE_fnc_fpv_lowRunEnd;', stopped)

    def test_waiting_drone_wiring(self):
        # LR-1c: the waiting drone's nomination is the engagement's own draw, peeked, never stored.
        e = code('attackEngagement')
        self.assertLess(e.index('if (_peek) exitWith {_record};'), e.index('_uav setVariable ["A3UE_FPV_attackEngagement", _record];'))
        self.assertIn('{_force == "LOW_RUN" || {_force == "LOW_RUN_WING" && {_peek || _waited}} || {_lowDraw < (_low get "weight")}}', e)
        self.assertIn('{_peek || {_horizontal >= (_low get "minRange")}}', e)
        w = code('lowRunWaiter')
        self.assertIn('[_uav, _target, _controllerIdentity, true, true] call A3UE_fnc_fpv_attackEngagement;', w)
        self.assertEqual(w.count('diag_log'), 1)
        # LR-1d: under LOW_RUN_WING only a drone waiting behind another drone's attack is decided.
        gate = 'getOrDefault ["holders", []]) findIf {!((_x # 0) isEqualTo _uav)}) < 0}) exitWith {false};'
        self.assertIn(gate, w)
        self.assertLess(w.index(gate), w.index('call A3UE_fnc_fpv_attackEngagement;'))
        self.assertLess(w.index(gate), w.index('_uav setVariable ["A3UE_FPV_lowWaiter"'))
        self.assertIn('[_settings # 4, _ring] select (_ring > 0)', code('overwatch'))
        self.assertIn('"LOW_RUN", "LOW_RUN_WING"]] call _choice,', code('attackSettings'))
        # A low run is far out on purpose: a closer waiting drone never takes its slot.
        swap = code('attackSlot').split('private _swap = _holders findIf {', 1)[1].split('};', 1)[0]
        self.assertIn('call A3UE_fnc_fpv_lowRunStage) in ["CHECKING", "READY"])}', swap)
        self.assertIn('(_waiter param [1, false])', swap)
        # The hand-off gate uses this drone's own hand-off range and a fresh survey.
        enter = code('shouldEnterTerminal')
        self.assertIn('_lowRecord getOrDefault ["handoffRun",', enter)
        self.assertIn('{count _lowResult == 8}', enter)

    def test_dive_path_fuse_and_commit_wiring(self):
        nav = code('attackNavigation')
        self.assertLess(nav.index('private _aim = (_weave vectorMultiply _envelope)'), nav.index('call A3UE_fnc_fpv_lowRunAim;'))
        self.assertLess(nav.index('call A3UE_fnc_fpv_lowRunAim;'), nav.index('if (_settings # 11) then {'))
        self.assertIn('if (!_low && {_settings # 6}', nav)
        # The obstacle probe leaves alone what the line already clears, and hops the rest as in 1.0.7.
        probe = nav.split('if (_settings # 11) then {', 1)[1]
        self.assertIn('private _line = if (_lowNow) then {[_uav, _hitPos] call A3UE_fnc_fpv_lowRunLineAt} else {[]};', probe)
        self.assertIn('if (count _line != 4 || {(_found # 1) > (_line # 0) - 0.3}) then {', probe)
        self.assertNotIn('unrecorded', nav)
        fuse = code('evaluateImpactWindow')
        self.assertIn('lineIntersectsSurfaces [_from, _to, _uav, objNull, true, 3, "GEOM", "NONE"]', fuse)
        contact = fuse.split('if (_contactOnly) then {', 1)[1].split('} else {\n', 1)[0]
        self.assertLess(contact.index('"GROUND_CONTACT";'), contact.index('"SURFACE_CONTACT";'))
        self.assertIn('case ((_impactMode == "OBSTRUCTION_SURFACE") && {!_low} && {_fallbackSurfaceQualified}): {', contact)
        self.assertIn('"SURFACE_CONTACT"]', code('commitDetonation'))
        self.assertIn('_deliveryMode = "CONTACT_POINT";', code('detonateCompat'))
        kvn = code('installKvnArchiveAdapter')
        self.assertLess(kvn.index('"A3UE_FPV_contactFence", []]) isNotEqualTo []) exitWith {};'),
                        kvn.index('_uav setVariable ["A3UE_FPV_kvnDestroyHandled", true];'))
        limits = code('attackLimits')
        self.assertLess(limits.index('if (_lowStage in ["DESCEND", "SKIM"]) exitWith'), limits.index('A3UE_FPV_attackReversal'))
        self.assertIn('call A3UE_fnc_fpv_lowRunStage;', limits)
        # LR-1b: the glide's limit brakes to the skim speed with 70% of the family's deceleration.
        self.assertIn('sqrt ((_cruise ^ 2) + 1.4 * (_limits # 2) * ((_low getOrDefault ["descentLeft", 0]) max 0))', limits)
        enter = code('shouldEnterTerminal')
        self.assertLess(enter.index('call A3UE_fnc_fpv_lowRunStage;'), enter.index('call A3UE_fnc_fpv_trajectoryLimits;'))

    def test_rpt_line_is_info_level_and_bounded(self):
        s = code('lowRunEnd')
        self.assertEqual(s.count('diag_log'), 1)
        self.assertIn('[A3UE_FPV] lowRun id=%1 target=%2 result=%3 reason=%4 heightM=%5 handoffM=%6 glideDeg=%7 skimFromM=%8 '
                      'under5M=%9 minClearM=%10 hopTopM=%11 hopBy=%12 surveys=%13 sliceMsMax=%14 waited=%15"', s)


if __name__ == '__main__':
    unittest.main()
