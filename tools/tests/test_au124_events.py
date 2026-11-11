"""AU 12.4 event route: which AU event API the addon subscribes through, and that AU 12.4's
CBA dispatch still delivers a site event inside the site worker's private context.

Shipped fn_addFPVEventListeners/fn_fpv_onLocationSpawned run in SQF-VM. The AU and CBA sides
are explicit substitutes:
- AU 12.0.3: A3A_fnc_addEventHandler already exists (builder/save CBA events), but these three
  events are raised through the legacy A3A_Events registry; Events.hpp has no CBA_Event entries.
- AU 12.4.1: same wrappers plus Events.hpp REPLACE_EVENT mapping (CBA_Event per legacy event),
  A3A_fnc_triggerLocalEvent -> `call CBA_fnc_localEvent` (AU fn_triggerLocalEvent.sqf), CBA
  3.19.0's CALL_EVENT macro (`args call _x` over a copy of the handler list), and the legacy
  listener API still present as a deprecated shim.
- A future AU without the legacy API or mapping.
This is source/decision evidence only. It does not qualify AU's real config, CBA's real event
namespace, or Arma's scheduler; the AU 12.4.1 engine smoke does that.
"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV

# AU 12.4.1 events/Events.hpp maps each legacy event to its CBA event (REPLACE_EVENT).
AU124_CONFIG = '''class A3A { class Events {
  class locationSpawned { CBA_Event = "%s"; };
  class AIVehInit { CBA_Event = "A3A_event_serverInitAiVehicle"; };
  class markerChange { CBA_Event = "A3A_event_serverMarkerChange"; };
}; };'''
# AU 12.0.3 events/Events.hpp: argument metadata only, no CBA_Event.
AU1203_CONFIG = '''class A3A { class Events {
  class locationSpawned { isLocal = 1; };
  class AIVehInit { isLocal = 1; };
  class markerChange { isLocal = 1; };
}; };'''
FUTURE_CONFIG = 'class A3A {};'

PRELUDE = r'''
FPV_isServer = true;
TEST_legacy = []; TEST_cba = []; TEST_intents = [];
private _assert = {params ["_ok", "_label"]; if (!_ok) then {throw _label;};};
A3UE_FPV_siteEpoch = "E";  // skip the per-mission reset block (server bookkeeping, not under test)
{ missionNamespace setVariable [_x, {}]; } forEach [
  "A3UE_fnc_fpv_reportAUAdapter", "A3UE_fnc_fpv_installTargetabilityAdapters",
  "A3UE_fnc_fpv_installCrocusSignalAdapter", "A3UE_fnc_fpv_installUaPayloadAdapter",
  "A3UE_fnc_fpv_installKvnPathAdapter", "A3UE_fnc_fpv_installKvnArchiveAdapter",
  "A3UE_fnc_fpv_installSiteHooks", "A3UE_fnc_fpv_installRivalsHooks",
  "A3UE_fnc_fpv_installOccupierInvaderSupportHooks", "A3UE_fnc_fpv_buildCompatCatalog",
  "A3UE_fnc_fpv_buildDoctrine", "A3UE_fnc_fpv_refreshManagedDrones",
  "A3UE_fnc_fpv_onAIVehInit", "A3UE_fnc_fpv_onMarkerChange"];
A3UE_fnc_fpv_receiveSiteIntent = { TEST_intents pushBack _this; true };
'''

# AU 12.0.3 events/functions: id-keyed registry; triggerEvent runs `_arguments call _callback`.
LEGACY_LISTENER = r'''
TEST_legacyHandlers = [];
A3A_Events_fnc_addEventListener = {
  params ["_event", "_id", "_callback"];
  TEST_legacy pushBack [_event, _id];
  private _i = TEST_legacyHandlers findIf {(_x # 1) == _id};
  if (_i < 0) then { TEST_legacyHandlers pushBack [_event, _id, _callback]; }
  else { TEST_legacyHandlers set [_i, [_event, _id, _callback]]; };
};
A3A_Events_fnc_triggerEvent = {
  params ["_event", "_arguments"];
  { if ((_x # 0) == _event) then { _arguments call (_x # 2); }; } forEach +TEST_legacyHandlers;
  true
};
'''

# AU core/functions/Events (12.0.3 and 12.4.1) + CBA 3.19.0 fnc_localEvent (CALL_EVENT).
CBA_CORE = r'''
TEST_events = createHashMap;
CBA_fnc_addEventHandler = {
  params ["_name", "_function"];
  if !(_name in TEST_events) then { TEST_events set [_name, []]; };
  (TEST_events get _name) pushBack _function;
  TEST_cba pushBack _name;
  count TEST_cba
};
CBA_fnc_localEvent = {
  params [["_eventName", ""], ["_params", []]];
  private _handlers = if (_eventName in TEST_events) then { +(TEST_events get _eventName) } else { [] };
  { if !(isNil "_x") then { _params call _x; }; } forEach _handlers;
};
A3A_fnc_addEventHandler = {
  params ["_eventName", "_eventFunc"];
  [_eventName, _eventFunc] call CBA_fnc_addEventHandler;
};
A3A_fnc_triggerLocalEvent = { params ["_eventName"]; call CBA_fnc_localEvent; nil; };
'''
AU1203_API = CBA_CORE + LEGACY_LISTENER
AU124_API = CBA_CORE + LEGACY_LISTENER
FUTURE_API = CBA_CORE


def shipped(name):
    s = (FPV / f'{name}.sqf').read_text()
    s = s.replace('isClass (missionConfigFile / "A3A")', 'true')
    s = re.sub(r'\bisServer\b', 'FPV_isServer', s)
    s = re.sub(r'\bisRemoteExecuted\b', 'false', s)
    s = re.sub(r'\bclientOwner\b', '2', s)
    return s


def run(script, config):
    with tempfile.TemporaryDirectory(prefix='fpv-au124-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(script + '\ndiag_log "AU124_TEST_OK";')
        c = Path(d) / 'config.cpp'
        c.write_text(config)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '40000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=60)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class AU124EventRoute(unittest.TestCase):
    def vm(self, api, body, config=AU124_CONFIG % 'A3A_event_serverSpawnLocation', server=True):
        script = PRELUDE + api + f'FPV_isServer = {str(server).lower()};\n'
        script += 'A3UE_fnc_addFPVEventListeners = {' + shipped('fn_addFPVEventListeners') + '};\n'
        script += 'A3UE_fnc_fpv_onLocationSpawned = {' + shipped('fn_fpv_onLocationSpawned') + '};\n'
        r = run(script + body, config)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('AU124_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    def test_au124_server_subscribes_once_through_cba_and_never_the_shim(self):
        out = self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
// A repeated registration (mission repair path) must not duplicate CBA handlers.
A3UE_FPV_registrationComplete = false;
[] call A3UE_fnc_addFPVEventListeners;
[TEST_legacy isEqualTo [], "legacy shim used"] call _assert;
[TEST_cba isEqualTo ["A3A_event_serverSpawnLocation", "A3A_event_serverInitAiVehicle",
  "A3A_event_serverMarkerChange"], format ["cba %1", TEST_cba]] call _assert;
[A3UE_FPV_auEventRoute == "CBA", "route"] call _assert;
[count A3UE_FPV_auEventIds == 3, "ids"] call _assert;
''')
        self.assertIn('auEvents route=CBA', out)

    def test_au124_client_skips_marker_change(self):
        self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
[TEST_cba isEqualTo ["A3A_event_serverSpawnLocation", "A3A_event_serverInitAiVehicle"],
  format ["client cba %1", TEST_cba]] call _assert;
[TEST_legacy isEqualTo [], "client legacy"] call _assert;
''', server=False)

    def test_au12_0_uses_legacy_listener_ids_although_cba_wrapper_exists(self):
        # AU 12.0.3 already ships A3A_fnc_addEventHandler; it must not pull us onto CBA events
        # that 12.0.3 never raises for sites, vehicles or markers.
        out = self.vm(AU1203_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
[TEST_legacy isEqualTo [["locationSpawned", "A3UE_FPV_locationSpawned"],
  ["AIVehInit", "A3UE_FPV_aivehInit"], ["markerChange", "A3UE_FPV_markerChange"]],
  format ["legacy %1", TEST_legacy]] call _assert;
[TEST_cba isEqualTo [], format ["12.0.3 cba %1", TEST_cba]] call _assert;
[A3UE_FPV_auEventRoute == "LEGACY", "route"] call _assert;
''', config=AU1203_CONFIG)
        self.assertIn('auEvents route=LEGACY', out)

    def test_future_au_without_legacy_api_uses_built_in_cba_names(self):
        self.vm(FUTURE_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
[TEST_cba isEqualTo ["A3A_event_serverSpawnLocation", "A3A_event_serverInitAiVehicle",
  "A3A_event_serverMarkerChange"], format ["future cba %1", TEST_cba]] call _assert;
[A3UE_FPV_auEventRoute == "CBA", "route"] call _assert;
''', config=FUTURE_CONFIG)

    def test_au_mapping_wins_over_built_in_name(self):
        self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
[(TEST_cba # 0) == "A3A_event_renamedSpawn", format ["mapped %1", TEST_cba]] call _assert;
''', config=AU124_CONFIG % 'A3A_event_renamedSpawn')

    def test_site_event_reaches_queue_inside_worker_context_via_cba_chain(self):
        self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
// AU createAIOutposts raises the event while running inside the FPV site worker's wrapper.
private _fnc_worker = {
  private _A3UE_FPV_siteWorkerContext = ["outpost_3", "Outpost", "Outpost", "E", 7];
  ["A3A_event_serverSpawnLocation", ["outpost_3", "Outpost", true]] call A3A_fnc_triggerLocalEvent;
};
call _fnc_worker;
[TEST_intents isEqualTo [["outpost_3", "Outpost", true, "E", 7, 2]], format ["intent %1", TEST_intents]] call _assert;
// Outside a worker (another mod raising it, or a different site) nothing is queued.
["A3A_event_serverSpawnLocation", ["outpost_3", "Outpost", false]] call A3A_fnc_triggerLocalEvent;
private _fnc_other = {
  private _A3UE_FPV_siteWorkerContext = ["outpost_3", "Outpost", "Outpost", "E", 7];
  ["A3A_event_serverSpawnLocation", ["airport_1", "Airport", true]] call A3A_fnc_triggerLocalEvent;
};
call _fnc_other;
[count TEST_intents == 1, format ["extra intents %1", TEST_intents]] call _assert;
''')

    def test_headless_client_never_sends_site_intent(self):
        # 1.0.6: HC-origin intents reached the server unauthenticated and were always refused;
        # the server's spawner check owns HC-run sites. No RPC, no queue, no log line.
        out = self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
TEST_rpc = [];
private _fnc_worker = {
  private _A3UE_FPV_siteWorkerContext = ["outpost_3", "Outpost", "Outpost", "E", 7];
  ["outpost_3", "Outpost", true] call A3UE_fnc_fpv_onLocationSpawned
};
[!(call _fnc_worker), "HC reported a send"] call _assert;
[TEST_intents isEqualTo [], format ["HC intent %1", TEST_intents]] call _assert;
''', server=False)
        self.assertNotIn('siteEvent', out)
        source = (FPV / 'fn_fpv_onLocationSpawned.sqf').read_text()
        code = '\n'.join(line.split('//')[0] for line in source.splitlines())
        self.assertNotIn('remoteExecCall', code)

    def test_non_site_locations_outside_a_worker_log_only_with_debug(self):
        out = self.vm(AU124_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
["Koroni", "City", true] call A3UE_fnc_fpv_onLocationSpawned;
["control_20", "control", true] call A3UE_fnc_fpv_onLocationSpawned;
["outpost_9", "Outpost", true] call A3UE_fnc_fpv_onLocationSpawned;
A3UE_FPV_debug = true;
["Galati", "City", true] call A3UE_fnc_fpv_onLocationSpawned;
[TEST_intents isEqualTo [], "queued outside worker"] call _assert;
''')
        self.assertEqual(out.count('reason=workerContext'), 2)
        self.assertIn('marker=outpost_9', out)
        self.assertIn('marker=Galati', out)
        self.assertNotIn('marker=Koroni', out)

    def test_reviewed_list_reports_12_0_3_and_12_4_1_and_gates_no_feature(self):
        # A3A_core versionStr = QUOTE(VERSION): "12.4.1", or "12.5" for a .0 patch level.
        helper = 'A3UE_fnc_fpv_auReviewedVersion = {' + shipped('fn_fpv_auReviewedVersion') + '};\n'
        for version, reviewed in [('12.0.3', True), ('12.4.1', True), ('12.4.2', False), ('12.5', False), ('', False)]:
            out = self.vm(AU124_API, helper + f'''
private _r = [] call A3UE_fnc_fpv_auReviewedVersion;
[(_r # 0) == "{version}" && {{(_r # 2) isEqualTo {str(reviewed).lower()}}}, format ["gate %1", _r]] call _assert;
''', config=f'class CfgPatches {{ class A3A_core {{ versionStr = "{version}"; }}; }};')
            self.assertNotIn('[ERR]', out)
        # 1.0.3: the list is informational. FPV supports and Rivals stay on for any AU version;
        # their structural checks (API, schema, provider and binding ownership) still apply.
        for name in ['fn_fpv_patchSupportRegistries', 'fn_fpv_installRivalsHooks']:
            source = shipped(name)
            for gate in ['auReviewedVersion', 'UNREVIEWED_AU_VERSION', 'versionStr']:
                self.assertNotIn(gate, source, name)
        report = shipped('fn_fpv_reportAUAdapter')
        self.assertIn('if !(_report get "versionReviewed") then {', report)
        self.assertIn('"all FPV features stay on; report problems with this RPT"', report)

    def test_au12_0_site_event_still_reaches_queue_through_legacy_registry(self):
        self.vm(AU1203_API, r'''
[] call A3UE_fnc_addFPVEventListeners;
private _fnc_worker = {
  private _A3UE_FPV_siteWorkerContext = ["resource_2", "Resource", "Factory", "E", 4];
  // AU 12.0.3 raises only the legacy event for sites (fn_createAIResources.sqf).
  ["locationSpawned", ["resource_2", "Resource", true]] call A3A_Events_fnc_triggerEvent;
};
call _fnc_worker;
[TEST_intents isEqualTo [["resource_2", "Factory", true, "E", 4, 2]], format ["intent %1", TEST_intents]] call _assert;
''', config=AU1203_CONFIG)


if __name__ == '__main__':
    unittest.main()
