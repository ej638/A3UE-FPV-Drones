"""Focused source-driven teardown gates with mocked resources/clock; not Arma execution."""
from dataclasses import dataclass, field
from pathlib import Path
import re
import unittest

from test_tracking_order_policy import boolean

ROOT = Path(__file__).resolve().parents[2]
# The QA commands under test live in the local, git-ignored docs/internal tree.
EXPERIMENTS = ROOT / "docs/internal/experiments"
if not EXPERIMENTS.is_dir():
    raise unittest.SkipTest("local QA experiments (docs/internal/experiments) are not present")
OLD = (EXPERIMENTS / "crocus-at-policy-20261026/commands/10-policy-context-contract.sqf").read_text()
NEW = (EXPERIMENTS / "crocus-at-policy-initialization-20261027/commands/10-policy-context-contract.sqf").read_text()
RECOVERY = (EXPERIMENTS / "crocus-at-policy-initialization-20261027/commands/10a-cleanup-recovery.sqf").read_text()
STEP = NEW.split("private _step = {", 1)[1].split("isNil {call _step;};", 1)[0]


def gate(expression, replacements, values):
    for before, after in sorted(replacements.items(), key=lambda item: -len(item[0])):
        expression = expression.replace(before, after)
    return boolean(expression, values)


def issue(reason, occurrence=0):
    prefixes = NEW.split(') then {_bad pushBack "' + reason + '";')[:-1]
    return prefixes[occurrence].rsplit('if (', 1)[1]


@dataclass(eq=False)
class Resource:
    null: bool = False
    local: bool = True
    owner: int = 2
    player: bool = False
    issued: bool = False
    members: list = field(default_factory=list)


DEADLINE = re.search(r"if \((diag_tickTime >= _until)\)", STEP)[1]
OBJECT_DUE = re.search(r"if \((!isNull \(_x # 0\).*?)\) then", STEP)[1]
GROUP_DUE = re.search(r"if \((!isNull \(_x # 0\).*?units.*?)\) then", STEP, re.S)[1]
# The object expression is one line; start the group extraction at its own loop.
GROUP_DUE = GROUP_DUE[GROUP_DUE.rfind("!isNull"):]


def due(resource, group=False):
    return gate(GROUP_DUE if group else OBJECT_DUE, {
        "isNull (_x # 0)": "null", "(_x # 5)": "issued", "(_x # 4)": "issued",
        "local (_x # 0)": "local", "units (_x # 0) isEqualTo []": "empty",
    }, dict(null=resource.null, issued=resource.issued, local=resource.local, empty=not resource.members))


class CleanupModel:
    """Mock only engine settling, applying the delivered deadline and deletion predicates."""
    def __init__(self):
        self.crew = Resource()
        self.uav = Resource()
        self.group = Resource(members=[self.crew])
        self.effects = []

    def step(self, now, until=3):
        if boolean(DEADLINE, dict(diag_tickTime=now, _until=until)):
            return
        # The production source's entire-roster admission is evaluated before effects.
        for resource in (self.crew, self.uav, self.group):
            expr = issue("locality/owner", int(resource is self.group))
            if gate(expr, {
                "local _object": "local", "owner _object": "owner",
                "local _group": "local", "groupOwner _group": "owner",
                '(_state get "owner")': "client",
            }, dict(local=resource.local, owner=resource.owner, _owner=2, client=2, _initializing=False)):
                return
        predicate = re.search(r'\(\(\(units _group\) findIf \{(.*?)\}\) >= 0\)', NEW)[1]
        if any(gate(predicate, {"isPlayer _x": "player"},
                    dict(_x=member, _crew=[self.crew], player=member.player)) for member in self.group.members):
            return
        for name, resource, group in (("crew", self.crew, False), ("uav", self.uav, False), ("group", self.group, True)):
            if due(resource, group):
                resource.issued = True
                self.effects.append((now, name))


class CleanupTests(unittest.TestCase):
    def test_all_original_policy_checks_cleanup_assertion_and_end_unchanged(self):
        start = '        ["current local admission",_ready] call _check;'
        self.assertEqual(OLD.split(start)[1].split("        {deleteVehicle")[0],
                         NEW.split(start)[1].split("        private _complete")[0])
        start = '        ["exact fixture cleanup"'
        end = "        copyToClipboard str _result;"
        self.assertEqual(OLD.split(start)[1].split(end)[0], NEW.split(start)[1].split(end)[0])
        old_setup = OLD.split('forEach [["A3UE_FPV_managed",true]')[1].split('private _ready')[0]
        new_setup = NEW.split('forEach [["A3UE_FPV_managed",true]')[1].split('_state set ["ticket"')[0]
        self.assertEqual("".join(old_setup.split()), "".join(new_setup.split()))

    def test_every_locality_owner_combination_for_objects_and_groups(self):
        for occurrence in (0, 1):
            for local in (False, True):
                for owner in (2, 3):
                    for saved in (2, 3):
                        rejected = gate(issue("locality/owner", occurrence), {
                            "local _object": "local", "owner _object": "owner",
                            "local _group": "local", "groupOwner _group": "owner",
                            '(_state get "owner")': "client",
                        }, dict(local=local, owner=owner, _owner=saved, client=2, _initializing=False))
                        self.assertEqual(rejected, not (local and owner == saved == 2))

    def test_changed_identity_player_group_and_vehicle_are_rejected(self):
        cases = [
            ("identity", {"netId _object": "live_id", "typeOf _object": "live_class"},
             dict(live_id="a", _id="a", live_class="class", _class="class", _initializing=False),
             [("live_id", "b"), ("live_class", "other")]),
            ("player", {"isPlayer _object": "player"}, dict(player=False), [("player", True)]),
            ("changed group", {"group _object": "current_group"}, dict(current_group="a", _group="a", _groups=["a"]),
             [("current_group", "b"), ("_groups", ["b"])]),
            ("changed vehicle", {"isNull (objectParent _object)": "on_foot", "objectParent _object": "parent"},
             dict(on_foot=False, parent="original", _uav="original"), [("parent", "foreign")]),
        ]
        for reason, replacements, values, mutations in cases:
            self.assertFalse(gate(issue(reason), replacements, values), reason)
            for key, value in mutations:
                self.assertTrue(gate(issue(reason), replacements, dict(values, **{key: value})), (reason, key))

    def test_deferred_null_and_group_settling_do_not_repeat_object_deletion(self):
        model = CleanupModel()
        model.step(0)
        model.step(.05)
        self.assertEqual(model.effects, [(0, "crew"), (0, "uav")])
        model.crew.null = model.uav.null = True
        model.group.members = []
        model.step(.1)
        model.step(.15)
        self.assertEqual(model.effects, [(0, "crew"), (0, "uav"), (.1, "group")])
        self.assertFalse(model.group.null)  # issued deletion is never treated as exact null

    def test_foreign_members_and_locality_change_during_settling_stop_effects(self):
        for contamination in ("foreign", "player", "owner", "local"):
            model = CleanupModel()
            model.step(0)
            model.crew.null = model.uav.null = True
            model.group.members = []
            if contamination == "foreign":
                model.group.members = [Resource()]
            elif contamination == "player":
                model.crew.player = True
                model.group.members = [model.crew]
            elif contamination == "owner":
                model.group.owner = 3
            else:
                model.group.local = False
            model.step(.1)
            self.assertEqual(model.effects, [(0, "crew"), (0, "uav")], contamination)

    def test_deadline_at_equality_and_scheduler_overshoot_prevent_deletion(self):
        for now in (3, 3.0001, 300):
            model = CleanupModel()
            model.group.members = []
            model.step(now)
            self.assertEqual(model.effects, [])
        model = CleanupModel()
        model.group.members = []
        model.step(2.999)
        self.assertEqual(len(model.effects), 3)

    def test_replacement_controller_and_all_exact_null_combinations(self):
        expression = re.search(r'if \((!_matches.*?)\) then \{_issues pushBack', NEW, re.S)[1]
        replacements = {
            '(scriptDone (_uav getVariable ["A3UE_FPV_controllerHandle", scriptNull]))': 'done',
            '_uav getVariable ["A3UE_FPV_cleanupPending", false]': 'pending',
            '_uav getVariable ["A3UE_FPV_detonating", false]': 'detonating',
        }
        for matches in (False, True):
            for done in (False, True):
                for pending in (False, True):
                    for detonating in (False, True):
                        self.assertEqual(gate(expression, replacements, dict(
                            _matches=matches, done=done, pending=pending, detonating=detonating)),
                            not matches or not done or pending or detonating)
        expression = NEW.split('params ["_state"];', 1)[1].split('        };', 1)[0]
        replacements = {
            '((_state get "objects") findIf {!isNull (_x # 0)})': 'object_index',
            '((_state get "groups") findIf {!isNull (_x # 0)})': 'group_index',
        }
        for uav_null in (False, True):
            for crew_null in (False, True):
                for group_null in (False, True):
                    object_index = next((i for i, null in enumerate([uav_null, crew_null]) if not null), -1)
                    self.assertEqual(gate(expression, replacements, dict(
                        object_index=object_index, group_index=-1 if group_null else 0)),
                        uav_null and crew_null and group_null)

    def test_stale_recovery_cannot_acquire_or_release_replacement_state(self):
        expression = re.search(r'if \((_state isEqualRef .*?&& \{scriptDone .*?)\) then', RECOVERY, re.S)[1]
        replacements = {
            '_state isEqualRef (missionNamespace getVariable ["A3UE_POLICY_contractCleanup", createHashMap])': 'same_state',
            'scriptDone (_state get "worker")': 'done',
        }
        for same_state in (False, True):
            for done in (False, True):
                self.assertEqual(gate(expression, replacements, dict(same_state=same_state, done=done)), same_state and done)
        for source in (NEW, RECOVERY):
            release = source.split('private _released = false;', 1)[1]
            self.assertLess(release.index('if (_state isEqualRef'), release.index('A3UE_POLICY_contractCleanup = nil;'))

    def test_worker_handoff_and_recovery_are_fenced_without_second_contract_result(self):
        # These integration checks couple the mock gates to the delivered scheduled/atomic route.
        self.assertNotIn("_thisScript", NEW + RECOVERY)
        self.assertIn('_workerRef set ["handle", _workerRef spawn {', NEW)
        self.assertIn('["worker", (_workerRef get "handle")]', NEW)
        self.assertIn('&& {scriptDone (_state get "worker")}) then {', RECOVERY)
        self.assertIn('_state isEqualRef (missionNamespace getVariable ["A3UE_POLICY_contractCleanup", createHashMap])', RECOVERY)
        self.assertIn('_state set ["worker", (_workerRef get "handle")];', RECOVERY)
        self.assertIn('isNil {call _step;};', NEW)
        self.assertNotIn("A3UE_FPV_POLICY_CONTRACT_END", RECOVERY)
        self.assertNotIn('A3UE_POLICY_contractActive = nil;', NEW.split("if (_complete) then {")[0])


if __name__ == "__main__":
    unittest.main()
