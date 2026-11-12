"""User settings (1.0.7): CBA Addon Options registration, validated reads and their effects.

Shipped SQF runs in SQF-VM with the F2C-L harness. CBA itself is stubbed: these tests cover
what the mod registers and how it reads and applies the values, not CBA's menu, saving or
server synchronisation (those are engine checks on the 1.0.7 card).
"""
import re
import unittest
import xml.dom.minidom
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT
from test_f2cl_field_fixes import PRELUDE, adapt, run_vm

SETTINGS = ['A3UE_FPV_siteFrequency', 'A3UE_FPV_sitePerSite', 'A3UE_FPV_siteStockRefillSeconds',
            'A3UE_FPV_supportEnabled', 'A3UE_FPV_supportMinWarTier', 'A3UE_FPV_rivalsEnabled', 'A3UE_FPV_debug']


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class UserSettingsSQF(unittest.TestCase):
    def vm(self, names, body):
        # SQF-VM has no localize: a stand-in returns the key, so text lookups stay visible.
        script = PRELUDE + 'FPV_localize={_this};\n'
        for name in names:
            source = adapt(name)
            source = re.sub(r'\blocalize (format \[[^\]]*\])', r'((\1) call FPV_localize)', source)
            source = re.sub(r'\blocalize ("[^"]+")', r'(\1 call FPV_localize)', source)
            source = re.sub(r'\blocalize (_\w+)', r'(\1 call FPV_localize)', source)
            script += f'A3UE_fnc_fpv_{name}={{{source}}};\n'
        r = run_vm(script + body + '\ndiag_log "SETTINGS_TEST_OK";')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('SETTINGS_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_reader_defaults_validation_and_ranges(self):
        self.vm(['userSetting'], r'''
private _s = {[_this] call A3UE_fnc_fpv_userSetting};
// Nothing set (no CBA): shipped defaults.
[("siteFrequency" call _s) == "NORMAL","frequency default"] call _assert;
[("sitePerSite" call _s) == "NORMAL","per-site default"] call _assert;
[("siteRefillSeconds" call _s) == 900,"refill default"] call _assert;
[("supportEnabled" call _s),"support default"] call _assert;
[("supportMinWarTier" call _s) == 3,"war tier default"] call _assert;
[("rivalsEnabled" call _s),"rivals default"] call _assert;
[!("debug" call _s),"debug default"] call _assert;
// Every valid value passes through.
{missionNamespace setVariable ["A3UE_FPV_siteFrequency",_x]; [("siteFrequency" call _s) == _x,_x] call _assert;} forEach ["OFF","LESS","NORMAL","MORE","ALWAYS"];
{missionNamespace setVariable ["A3UE_FPV_sitePerSite",_x]; [("sitePerSite" call _s) == _x,_x] call _assert;} forEach ["FEWER","NORMAL","MORE"];
{missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",_x]; [("siteRefillSeconds" call _s) == _x,str _x] call _assert;} forEach [0,900,1800,3600];
missionNamespace setVariable ["A3UE_FPV_supportEnabled",false]; [!("supportEnabled" call _s),"support off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_rivalsEnabled",false]; [!("rivalsEnabled" call _s),"rivals off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_debug",true]; [("debug" call _s),"debug on"] call _assert;
// Invalid values fall back to the defaults; numbers are clamped.
missionNamespace setVariable ["A3UE_FPV_siteFrequency","always"]; [("siteFrequency" call _s) == "NORMAL","case-exact list"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency",4]; [("siteFrequency" call _s) == "NORMAL","wrong type"] call _assert;
missionNamespace setVariable ["A3UE_FPV_sitePerSite","LOTS"]; [("sitePerSite" call _s) == "NORMAL","unknown per-site"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",30]; [("siteRefillSeconds" call _s) == 900,"too short"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",99999]; [("siteRefillSeconds" call _s) == 900,"too long"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds","900"]; [("siteRefillSeconds" call _s) == 900,"string"] call _assert;
missionNamespace setVariable ["A3UE_FPV_supportEnabled",1]; [("supportEnabled" call _s),"non-Boolean"] call _assert;
{missionNamespace setVariable ["A3UE_FPV_supportMinWarTier",_x # 0]; [("supportMinWarTier" call _s) == (_x # 1),str _x] call _assert;}
 forEach [[0,1],[-5,1],[11,10],[2.6,3],[7,7],["5",3]];
[isNil {["unknown"] call A3UE_fnc_fpv_userSetting},"unknown name"] call _assert;
''')

    def test_frequency_changes_the_roll(self):
        self.vm(['profileValue', 'userSetting', 'siteStock'], r'''
TEST_site = 0;
private _roll = {
  params ["_chance", ["_n", 400]];
  private _skips = 0;
  for "_i" from 1 to _n do {
    TEST_site = TEST_site + 1;
    private _r = ["OPEN", format ["S_%1", TEST_site], east, createHashMapFromArray [["spawnChance",_chance],["stock",[1,1]]]] call A3UE_fnc_fpv_siteStock;
    if (_r # 2) then {_skips = _skips + 1;};
  };
  _skips / _n
};
// OFF: no drones and nothing recorded, so the site rolls later when the setting is back on.
missionNamespace setVariable ["A3UE_FPV_siteFrequency","OFF"];
private _off = ["OPEN","Site_A",east,createHashMapFromArray [["spawnChance",1],["stock",[3,3]]]] call A3UE_fnc_fpv_siteStock;
[_off isEqualTo [0,0,true,1],format ["off %1",_off]] call _assert;
[!("Site_A" in A3UE_FPV_siteStock),"off records nothing"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency","NORMAL"];
private _later = ["OPEN","Site_A",east,createHashMapFromArray [["spawnChance",1],["stock",[3,3]]]] call A3UE_fnc_fpv_siteStock;
[(_later # 0) == 3 && {!(_later # 2)},format ["rolls after re-enable %1",_later]] call _assert;
// OFF does not touch a site that already rolled.
missionNamespace setVariable ["A3UE_FPV_siteFrequency","OFF"];
private _kept = ["OPEN","Site_A",east,createHashMap] call A3UE_fnc_fpv_siteStock;
[(_kept # 0) == 3,"rolled stock kept"] call _assert;
// ALWAYS: every site, no roll (spawn roll 0), even with zero chance.
missionNamespace setVariable ["A3UE_FPV_siteFrequency","ALWAYS"];
private _always = ["OPEN","Site_B",east,createHashMapFromArray [["spawnChance",0],["stock",[2,2]]]] call A3UE_fnc_fpv_siteStock;
[_always isEqualTo [2,2,false,0],format ["always %1",_always]] call _assert;
[([0] call _roll) == 0,"always never skips"] call _assert;
// NORMAL / LESS / MORE scale the chance (statistical bounds over 400 sites).
missionNamespace setVariable ["A3UE_FPV_siteFrequency","NORMAL"];
private _normal = [0.6] call _roll; [_normal > 0.3 && {_normal < 0.5},format ["normal skip %1",_normal]] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency","LESS"];
private _less = [0.6] call _roll; [_less > 0.6 && {_less < 0.8},format ["less skip %1 (chance 0.3)",_less]] call _assert;
[([1] call _roll) > 0.35,"less halves even a certain site"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency","MORE"];
private _more = [0.4] call _roll; [_more > 0.3 && {_more < 0.5},format ["more skip %1 (chance 0.6)",_more]] call _assert;
[([0.8] call _roll) == 0,"more caps at certain"] call _assert;
''')

    def test_drones_per_site_shifts_the_range(self):
        self.vm(['profileValue', 'userSetting', 'siteStock'], r'''
missionNamespace setVariable ["A3UE_FPV_siteFrequency","ALWAYS"];
private _range = {
  params ["_stock", ["_n", 120]];
  private _lo = 99; private _hi = -1;
  for "_i" from 1 to _n do {
    private _r = ["OPEN", format ["R_%1_%2_%3", A3UE_FPV_sitePerSite, _stock, _i], east, createHashMapFromArray [["spawnChance",1],["stock",_stock]]] call A3UE_fnc_fpv_siteStock;
    _lo = _lo min (_r # 1); _hi = _hi max (_r # 1);
  };
  [_lo, _hi]
};
A3UE_FPV_sitePerSite = "NORMAL"; [([[2,4]] call _range) isEqualTo [2,4],"normal 2-4"] call _assert;
A3UE_FPV_sitePerSite = "FEWER";  [([[2,4]] call _range) isEqualTo [1,3],"fewer 1-3"] call _assert;
[([[1,1]] call _range) isEqualTo [1,1],"fewer keeps at least one"] call _assert;
[([[1,2]] call _range) isEqualTo [1,1],"fewer outpost 1-1"] call _assert;
A3UE_FPV_sitePerSite = "MORE";   [([[2,4]] call _range) isEqualTo [3,5],"more 3-5"] call _assert;
[([[1,1]] call _range) isEqualTo [2,2],"more resource 2"] call _assert;
[([[2]] call _range) isEqualTo [3,3],"single-value range shifts once"] call _assert;
''')

    def test_refill_never_and_back(self):
        self.vm(['profileValue', 'userSetting', 'siteStock'], r'''
missionNamespace setVariable ["A3UE_FPV_siteFrequency","ALWAYS"];
private _p = createHashMapFromArray [["spawnChance",1],["stock",[3,3]]];
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",0];
FPV_time = 0; ["OPEN","Site_N",east,_p] call A3UE_fnc_fpv_siteStock; ["SPEND","Site_N",east,2] call A3UE_fnc_fpv_siteStock;
[((A3UE_FPV_siteStock get "Site_N") get "refillAt") == -1,"never runs no timer"] call _assert;
FPV_time = 50000;
[((["OPEN","Site_N",east,_p] call A3UE_fnc_fpv_siteStock) # 0) == 1,"never refills"] call _assert;
[(["RETURN","Site_N",east,1] call A3UE_fnc_fpv_siteStock) == 2,"intact drones still return"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",900];
["OPEN","Site_N",east,_p] call A3UE_fnc_fpv_siteStock;
[((A3UE_FPV_siteStock get "Site_N") get "refillAt") == 50900,"timer starts when switched back"] call _assert;
FPV_time = 50900;
[((["OPEN","Site_N",east,_p] call A3UE_fnc_fpv_siteStock) # 0) == 3,"refills after the interval"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds",1800];
["SPEND","Site_N",east,1] call A3UE_fnc_fpv_siteStock;
[((A3UE_FPV_siteStock get "Site_N") get "refillAt") == 52700,"longer interval applies live"] call _assert;
''')

    def test_support_gate(self):
        self.vm(['userSetting', 'supportAllowed'], r'''
private _g = {call A3UE_fnc_fpv_supportAllowed};
tierWar = 3; [(call _g) isEqualTo [true,""],"default at war tier 3"] call _assert;
tierWar = 2; [(call _g) isEqualTo [false,"WAR_TIER_TOO_LOW"],"below default tier"] call _assert;
missionNamespace setVariable ["A3UE_FPV_supportMinWarTier",1]; [(call _g) # 0,"tier 1 setting"] call _assert;
missionNamespace setVariable ["A3UE_FPV_supportMinWarTier",8]; tierWar = 7;
[(call _g) isEqualTo [false,"WAR_TIER_TOO_LOW"],"tier 8 setting"] call _assert;
tierWar = 10; [(call _g) # 0,"tier 10 passes"] call _assert;
missionNamespace setVariable ["A3UE_FPV_supportEnabled",false];
[(call _g) isEqualTo [false,"DISABLED_BY_SETTING"],"strikes off"] call _assert;
tierWar = "x"; missionNamespace setVariable ["A3UE_FPV_supportEnabled",true]; missionNamespace setVariable ["A3UE_FPV_supportMinWarTier",1];
[(call _g) # 0,"bad tierWar treated as 1"] call _assert;
''')

    def test_registration_declares_seven_global_settings(self):
        out = self.vm(['registerSettings'], r'''
[!(call A3UE_fnc_fpv_registerSettings),"no CBA: nothing registered, no error"] call _assert;
TEST_settings = [];
CBA_fnc_addSetting = {TEST_settings pushBack _this; true};
[call A3UE_fnc_fpv_registerSettings,"registered"] call _assert;
[count TEST_settings == 7,format ["count %1",count TEST_settings]] call _assert;
{
  _x params ["_name","_type","_title","_category","_valueInfo","_global","_script"];
  [_global isEqualTo 1,_name + " not global"] call _assert;
  [_title isEqualType [] && {count _title == 2},_name + " title/tooltip"] call _assert;
  [_category isEqualType [] && {count _category == 2},_name + " category"] call _assert;
  [_script isEqualType {},_name + " script"] call _assert;
  diag_log format ["SETTING %1 %2 %3", _name, _type, _valueInfo];
  _x # 6;
} forEach TEST_settings;
private _byName = createHashMapFromArray (TEST_settings apply {[_x # 0, _x]});
private _default = {
  params ["_n"]; private _e = _byName get _n; private _v = _e # 4;
  switch (_e # 1) do {case "LIST": {(_v # 0) select (_v # 2)}; case "SLIDER": {_v # 2}; default {_v}}
};
[(["A3UE_FPV_siteFrequency"] call _default) == "NORMAL","frequency default"] call _assert;
[(["A3UE_FPV_sitePerSite"] call _default) == "NORMAL","per-site default"] call _assert;
[(["A3UE_FPV_siteStockRefillSeconds"] call _default) == 900,"refill default"] call _assert;
[(["A3UE_FPV_supportEnabled"] call _default),"support default"] call _assert;
[(["A3UE_FPV_supportMinWarTier"] call _default) == 3,"war tier default"] call _assert;
[(["A3UE_FPV_rivalsEnabled"] call _default),"rivals default"] call _assert;
[!(["A3UE_FPV_debug"] call _default),"debug default"] call _assert;
[((_byName get "A3UE_FPV_supportMinWarTier") # 4) isEqualTo [1,10,3,0],"war tier slider 1-10"] call _assert;
[(((_byName get "A3UE_FPV_siteFrequency") # 4) # 0) isEqualTo ["OFF","LESS","NORMAL","MORE","ALWAYS"],"frequency values"] call _assert;
[(((_byName get "A3UE_FPV_siteStockRefillSeconds") # 4) # 0) isEqualTo [0,900,1800,3600],"refill values"] call _assert;
// The server logs a change (CBA calls the script with the new value).
"ALWAYS" call ((_byName get "A3UE_FPV_siteFrequency") # 6);
''')
        names = re.findall(r'SETTING (\S+) ', out)
        self.assertEqual(sorted(names), sorted(SETTINGS))
        self.assertIn('[A3UE_FPV] setting siteFrequency=ALWAYS', out)


class UserSettingsContracts(unittest.TestCase):
    def src(self, name):
        return (FPV / f'fn_fpv_{name}.sqf').read_text()

    def code(self, text):
        return re.sub(r'//[^\n]*', '', text)

    def test_config_registers_functions_and_cba_preinit(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in ['userSetting', 'registerSettings', 'supportAllowed']:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)
        block = config.split('class Extended_PreInit_EventHandlers {', 1)[1].split('\n};', 1)[0]
        self.assertIn("call compileScript ['\\fpv_ai_drones\\functions\\fpv\\fn_fpv_registerSettings.sqf']", block)
        self.assertNotIn('\x0c', config)
        # No new hard dependency: AU already loads CBA; the patch keeps its two requirements.
        self.assertIn('requiredAddons[] = {"A3A_core", "A3_Weapons_F_Tank"};', config)

    def test_every_setting_has_text(self):
        reg = self.src('registerSettings')
        keys = set(re.findall(r'STR_A3UE_FPV_SET_[A-Z0-9_]+', reg))
        for short in re.findall(r'"([A-Z]+)" call _text', reg):
            keys |= {f'STR_A3UE_FPV_SET_{short}', f'STR_A3UE_FPV_SET_{short}_TIP'}
        table = (ROOT / 'addons/drones/stringtable.xml').read_text(encoding='utf-8')
        xml.dom.minidom.parseString(table.encode('utf-8'))
        for key in keys:
            self.assertIn(f'<Key ID="{key}">', table, key)

    def test_reader_names_match_registered_names(self):
        reg = self.src('registerSettings')
        reader = self.src('userSetting')
        for var in SETTINGS:
            self.assertIn(f'"{var}"', reg, var)
            self.assertIn(f'"{var}"', reader, var)

    def test_settings_are_wired_where_they_apply(self):
        stock = self.code(self.src('siteStock'))
        self.assertIn('["siteFrequency"] call A3UE_fnc_fpv_userSetting', stock)
        self.assertIn('["sitePerSite"] call A3UE_fnc_fpv_userSetting', stock)
        self.assertNotIn('A3UE_FPV_debug', stock)  # debug logs only; it no longer forces spawns
        resolve = self.code(self.src('resolveSupportPackage'))
        self.assertIn('call A3UE_fnc_fpv_supportAllowed', resolve)
        self.assertNotIn('"minWarTier", 3]', resolve)
        rivals = self.src('rivalsEventAvailable')
        self.assertLess(rivals.index('["rivalsEnabled"] call A3UE_fnc_fpv_userSetting'),
                        rivals.index('A3UE_FPV_rivalsHooksInstalled'))
        waved = (FPV / 'au_overrides' / 'fn_wavedAttack.sqf').read_text()
        line = next(l for l in waved.splitlines() if '_possibles append ["FPV"' in l or '"FPV" in _airSupports) &&' in l)
        self.assertIn('call A3UE_fnc_fpv_supportAllowed', line)
        for name in ['userSetting', 'supportAllowed', 'registerSettings']:
            self.assertNotRegex(self.code(self.src(name)),
                                r'\b(spawn|sleep|execVM|waitUntil|addMissionEventHandler|remoteExec\w*|publicVariable|setVariable)\b', name)


if __name__ == '__main__':
    unittest.main()
