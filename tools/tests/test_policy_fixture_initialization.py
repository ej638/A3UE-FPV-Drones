"""Source-driven readiness transitions with mocked engine observations; not engine execution."""
from dataclasses import dataclass
import re
import unittest

from test_policy_fixture_cleanup import NEW, RECOVERY, gate, issue


@dataclass
class Original:
    owner: int = 0
    local: bool = False
    saved_owner: int = 0
    saved_id: str = "0:0"
    live_id: str = "0:0"
    original_class: str = "O_UAV_AI"
    live_class: str = "O_UAV_AI"


def owner_rejected(resource, initializing, group=False):
    return gate(issue("locality/owner", int(group)), {
        "local _object": "local", "owner _object": "owner",
        "local _group": "local", "groupOwner _group": "owner",
        '(_state get "owner")': "expected",
    }, dict(local=resource.local, owner=resource.owner, _owner=resource.saved_owner,
            expected=2, _initializing=initializing))


def identity_rejected(resource, initializing):
    return gate(issue("identity"), {
        "netId _object": "live_id", "typeOf _object": "live_class",
    }, dict(live_id=resource.live_id, _id=resource.saved_id,
            live_class=resource.live_class, _class=resource.original_class, _initializing=initializing))


class ReadinessModel:
    """Mock scheduling/roster facts; execute the delivered owner/identity/deadline predicates."""
    def __init__(self):
        self.resources = [Original() for _ in range(4)]  # UAV, two crew, original group
        self.original_refs = tuple(self.resources)
        self.creation_owners = tuple(r.owner for r in self.resources)
        self.confirmed = self.stamped = False
        self.lock = True
        self.phase = "waiting"
        self.finalizations = 0

    def settle(self, *indices):
        for i in indices:
            r = self.resources[i]
            r.owner = 2
            r.local = True
            r.live_id = f"2:{2000+i}"

    def pending(self, **facts):
        for i, resource in enumerate(self.resources):
            if owner_rejected(resource, True, group=i == 3):
                return True
            if i < 3 and identity_rejected(resource, True):
                return True
        # Roster facts stand in for native crew/units/objectParent/null commands.
        expression = NEW.split('if (count _objects != 3', 1)[1].split(') then {', 1)[0]
        if gate('count _objects != 3' + expression, {
            'count _objects': 'object_count', 'count _groups': 'group_count',
            '(_objects findIf {isNull (_x # 0)})': 'null_object_index',
            '(_groups findIf {isNull _x})': 'null_group_index',
            'count (_crew arrayIntersect _crew)': 'unique_crew',
        }, dict(object_count=3, group_count=1, null_object_index=-1,
                null_group_index=-1, unique_crew=2) | facts):
            return True
        return False

    def finalize(self, now, **facts):
        expression = re.search(r'if \((diag_tickTime < _until && \{_pending isEqualTo \[\]\})\) then', NEW)[1]
        admitted = gate(expression, {'_pending isEqualTo []': 'empty'},
                        dict(diag_tickTime=now, _until=8, empty=not self.pending(**facts)))
        if admitted and not self.confirmed:
            for resource in self.resources:
                resource.saved_owner = 2
                resource.saved_id = resource.live_id
            self.confirmed = self.stamped = True
            self.finalizations += 1
            self.phase = "confirmed"
        elif not admitted:
            self.phase = "timeout" if now >= 8 else "refused"
        return admitted


class InitializationTests(unittest.TestCase):
    def test_creation_zero_to_expected_host_confirms_original_resources_once(self):
        model = ReadinessModel()
        self.assertTrue(model.pending())
        model.settle(0, 1, 2, 3)
        self.assertTrue(model.finalize(.1))
        self.assertIs(model.resources[0], model.original_refs[0])
        self.assertEqual(model.creation_owners, (0, 0, 0, 0))
        self.assertTrue(all(r.saved_owner == 2 for r in model.resources))
        self.assertEqual(model.finalizations, 1)

    def test_delayed_each_crew_and_group_prevents_early_confirmation(self):
        model = ReadinessModel()
        for index in range(3):
            model.settle(index)
            self.assertFalse(model.finalize(.1 * (index + 1)))
            self.assertFalse(model.stamped)
            self.assertTrue(all(r.saved_owner == 0 for r in model.resources))
        model.settle(3)
        self.assertTrue(model.finalize(7.9))

    def test_partial_readiness_timeout_preserves_provisional_roster_and_lock(self):
        for missing in (0, 1, 2, 3):
            model = ReadinessModel()
            model.settle(*(i for i in range(4) if i != missing))
            self.assertFalse(model.finalize(8))
            self.assertFalse(model.confirmed or model.stamped)
            self.assertEqual(model.phase, "timeout")
            self.assertTrue(model.lock)
            self.assertEqual(tuple(model.resources), model.original_refs)
            self.assertTrue(all(r.saved_owner == 0 for r in model.resources))
        for now in (8, 8.001, 90):
            model = ReadinessModel()
            model.settle(0, 1, 2, 3)
            self.assertFalse(model.finalize(now))  # even if ready after scheduler overshoot

    def test_wrong_owner_and_nonlocal_expected_owner_never_confirm(self):
        for index in range(4):
            for owner, local in ((0, True), (3, True), (2, False)):
                model = ReadinessModel()
                model.settle(0, 1, 2, 3)
                model.resources[index].owner = owner
                model.resources[index].local = local
                self.assertFalse(model.finalize(.2), (index, owner, local))
                self.assertFalse(model.stamped)

    def test_null_partial_or_duplicate_roster_cannot_stamp(self):
        for facts in (dict(object_count=2), dict(group_count=0), dict(group_count=2),
                      dict(null_object_index=1), dict(null_group_index=0), dict(unique_crew=1)):
            model = ReadinessModel()
            model.settle(0, 1, 2, 3)
            self.assertFalse(model.finalize(.2, **facts), facts)

    def test_provisional_ids_can_settle_but_valid_original_id_and_class_cannot_change(self):
        model = ReadinessModel()
        model.settle(0, 1, 2, 3)
        self.assertTrue(model.finalize(.2))
        for field, value in (("saved_id", "2:other"), ("live_id", "0:0"),
                             ("live_id", ""), ("live_class", "foreign")):
            model = ReadinessModel()
            model.settle(0, 1, 2, 3)
            setattr(model.resources[1], field, value)
            self.assertFalse(model.finalize(.2), (field, value))

    def test_change_between_poll_and_atomic_finalization_rejected(self):
        model = ReadinessModel()
        model.settle(0, 1, 2, 3)
        self.assertFalse(model.pending())
        model.resources[3].owner = 3
        self.assertFalse(model.finalize(.2))
        self.assertFalse(model.stamped)

    def test_genuine_change_after_confirmation_rejects_without_refreshing_baseline(self):
        for index in range(4):
            model = ReadinessModel()
            model.settle(0, 1, 2, 3)
            self.assertTrue(model.finalize(.2))
            resource = model.resources[index]
            resource.owner = 3
            self.assertTrue(owner_rejected(resource, False, group=index == 3))
            self.assertEqual(resource.saved_owner, 2)
            if index < 3:
                resource.live_id = "3:replacement"
                self.assertTrue(identity_rejected(resource, False))

    def test_initial_classes_seated_crew_and_complete_group_are_required(self):
        for index in range(3):
            expected = 'O_UAV_01_F' if index == 0 else 'O_UAV_AI'
            for initializing in (False, True):
                for actual in (expected, 'foreign'):
                    rejected = gate(issue('unexpected class'), {
                        'typeOf _object': 'actual',
                        '(["O_UAV_01_F", "O_UAV_AI"] select (_forEachIndex > 0))': 'expected',
                    }, dict(actual=actual, expected=expected, _initializing=initializing))
                    self.assertEqual(rejected, initializing and actual != expected)
        expression = NEW.split('if (count crew _uav != 2', 1)[1].split(') then {', 1)[0]
        for count, missing, displaced in ((2, -1, -1), (1, 1, -1), (2, 0, -1), (2, -1, 1)):
            rejected = gate('count crew _uav != 2' + expression, {
                'count crew _uav': 'count', '(_crew findIf {!(_x in crew _uav)})': 'missing',
                '(_crew findIf {objectParent _x != _uav})': 'displaced',
            }, dict(count=count, missing=missing, displaced=displaced))
            self.assertEqual(rejected, (count, missing, displaced) != (2, -1, -1))
        for count, missing in ((2, -1), (1, 0), (3, -1), (2, 0)):
            rejected = gate(issue('incomplete group roster'), {
                'count units _group': 'count', '(_crew findIf {!(_x in units _group)})': 'missing',
            }, dict(_initializing=True, count=count, missing=missing))
            self.assertEqual(rejected, (count, missing) != (2, -1))

    def test_unconfirmed_recovery_cannot_delete_or_finalize_a_late_settled_roster(self):
        expression = re.search(r'if \((!_initializing && \{!\(_state get "confirmed"\)\})\)', NEW)[1]
        for initializing, confirmed, rejected in ((False, False, True), (False, True, False), (True, False, False)):
            self.assertEqual(gate(expression, {'(_state get "confirmed")': 'confirmed'},
                                  dict(_initializing=initializing, confirmed=confirmed)), rejected)
        step = NEW.split('private _step = {', 1)[1].split('isNil {call _step;};', 1)[0]
        self.assertLess(step.index('[_state] call (_state get "issues")'), step.index('deleteVehicle'))
        self.assertIn('if (_issues isNotEqualTo []) exitWith {_blocked = true;};', step)
        self.assertNotIn('_state set ["confirmed"', RECOVERY)

    def test_atomic_route_full_roster_control_lifecycle_and_unconfirmed_recovery_fences(self):
        creation = NEW.split('// Retain the exact original roster', 1)[1].split('private _start =', 1)[0]
        self.assertIn('isNil {', creation)
        self.assertNotIn('sleep ', creation)
        self.assertIn('_state set ["creation",', creation)
        final = NEW.split('// Validate and finalize once', 1)[1].split('["current local admission"', 1)[0]
        self.assertLess(final.index('_pending = [_state, true] call _issues;'), final.index('_state set ["confirmed", true]'))
        self.assertLess(final.index('_state set ["confirmed", true]'), final.index('_uav setVariable [_key, _value]'))
        self.assertIn('_x set [3, _state get "owner"];', final)
        self.assertIn('_x set [2, _state get "owner"];', final)
        self.assertNotIn('owner (_x # 0)', final)
        self.assertEqual(NEW.count('_state set ["confirmed", true]'), 1)
        self.assertIn('["owner", 2]', NEW)
        self.assertIn('clientOwner != 2', NEW)
        # Shared _issues runs before stamping and in cleanup; no competing control/lifecycle bypass.
        for reason in ('connected/control', 'replacement lifecycle/controller', 'Zeus/control marker',
                       'foreign crew', 'foreign/player member', 'incomplete group roster', 'original crew not seated'):
            self.assertIn('"' + reason + '"', NEW)
        self.assertIn('if (!_initializing && {!(_state get "confirmed")})', NEW)
        self.assertIn('ownership baseline unconfirmed', NEW)
        self.assertNotIn('"confirmed", true', RECOVERY)
        self.assertIn('[_state] call (_state get "cleanup")', RECOVERY)
        self.assertEqual(NEW.count('sleep 0.1;'), 1)
        self.assertIn('private _until = _start + 8;', NEW)
        self.assertIn('private _until = _start + 3;', NEW)
        self.assertIn('sleep 0.05;', NEW)


if __name__ == '__main__':
    unittest.main()
