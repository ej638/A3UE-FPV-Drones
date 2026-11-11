"""Offline policy decision model and data renderer, NOT an SQF/Arma interpreter.

Inputs describe observed dispatch applicability, source qualification and specimen
conditions. Python PASS validates this review policy, never engine execution.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).parent


def load_policy():
    return json.loads((ROOT / "motion_policy.json").read_text(encoding="utf-8"))


def render_policy(policy):
    def sqf(value):
        if isinstance(value, str):
            return '"' + value.replace('"', '""') + '"'
        if isinstance(value, list):
            return '[' + ','.join(sqf(x) for x in value) + ']'
        return str(value)

    callbacks = [[c[k] for k in ("id", "path", "body", "conditions", "pins")]
                 for c in policy["callbacks"]]
    pins = [[p[k] for k in ("id", "path", "fingerprint", "function", "span", "dependencies", "source_lf", "pbo_sha256", "source_sha256")]
            for p in policy["pins"]]
    for pin in pins:
        pin[6] = pin[6].split('\n')  # no preprocessor directives inside multiline literals
    dynamic = [[d[k] for k in ("id", "class", "event", "path", "marker", "function", "pins", "conditions")]
               for d in policy["dynamic_callbacks"]]
    identity = hashlib.sha256(json.dumps(policy, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
    return ('// Reviewed policy data; generated from motion_policy.json. No vendor code is executed.\n[\n'
            + sqf(policy["version"]) + ',\n' + sqf(policy["dispatch_pins"]) + ',\n[\n'
            + ',\n'.join(sqf(c) for c in callbacks) + '\n],\n[\n'
            + ',\n'.join(sqf(p) for p in pins) + '\n],\n[\n'
            + ',\n'.join(sqf(d) for d in dynamic) + '\n],\n' + sqf(identity)
            + ',\n' + sqf(policy.get('cargo_profiles', [])) + '\n]\n')


def fingerprint(text):
    a, b, n = 1, 0, 0
    for byte in text.encode("utf-8"):
        if byte != 13:
            n += 1
            a = (a + byte) % 65521
            b = (b + a) % 65521
    return [n, a, b]


def canonical(text):
    """Lexical policy specification; not compilation or code execution."""
    out, i, gap = [], 0, False
    identifier = lambda c: c.isascii() and (c.isalnum() or c == "_")
    while i < len(text):
        ch = text[i]
        if text.startswith("#line", i) or text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
            gap = True
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            gap = True
            continue
        if ch in ("'", '"'):
            quote, value = ch, []
            i += 1
            while i < len(text):
                ch = text[i]
                if ch == quote:
                    if i + 1 < len(text) and text[i + 1] == quote:
                        value.append(ch)
                        i += 2
                        continue
                    i += 1
                    break
                value.append(ch)
                i += 1
            out.extend('"' + ''.join(value).replace('"', '""') + '"')
            gap = False
            continue
        if ch.isspace():
            gap = True
        else:
            if gap and identifier(ch) and out and identifier(out[-1]):
                out.append(" ")
            out.append(ch.lower())
            gap = False
        i += 1
    return ''.join(out)


def canonical_spans(text):
    """Offline lexical specification of the engine-regex path, not SQF execution.

    Compare this with the older character scanner on reviewed text and generated
    adversarial cases. Engine regex/compile behavior still requires qualification.
    """
    lexemes = re.compile(r'"(?:""|[^"])*"|\'(?:\'\'|[^\'])*\'|#line[^\n]*|//[^\n]*|/\*[\s\S]*?\*/')
    def plain(code):
        if '\x01' in code:
            raise ValueError('CODE_SEPARATOR_COLLISION')
        code = re.sub(r'([a-z0-9_])[\x00-\x20]+(?=[a-z0-9_])', lambda m: m[1]+'\x01', code.lower())
        return re.sub(r'[\x00\x02-\x20]', '', code).replace('\x01', ' ')
    out, parts, at = [], [], 0
    for match in lexemes.finditer(text):
        token = match.group()
        parts.append(text[at:match.start()])
        if token[0] in ('"', "'"):
            out.append(plain(''.join(parts)))
            parts = []
            if token[0] == "'":
                token = '"' + token[1:-1].replace("''", "'").replace('"', '""') + '"'
            out.append(token)
        else:
            parts.append(' ')
        at = match.end()
    parts.append(text[at:])
    out.append(plain(''.join(parts)))
    return ''.join(out)


class PreparationModel:
    """Transactional audit/state contract using supplied synthetic engine facts.

    Costs are synthetic scheduled time, not predictions of Arma performance.
    Bodies here are strings; compile/preprocessor/registry dispatch are not run.
    """
    def __init__(self):
        self.identity, self.cache = None, {}
        self.active, self.ready, self.phase = False, False, 'IDLE'
        self.reason, self.snapshot = None, None

    def prepare(self, identity, reviewed, observed, bindings, registry, *, busy=False,
                deadline=30, costs=None, interrupt=None, final_bindings=None,
                final_registry=None, unknown=False, mounted_immutable=True):
        if self.active or busy:
            return 'BUSY', (0, 0)
        self.active, self.ready, self.phase = True, False, 'ACKNOWLEDGED'
        transaction = dict(self.cache) if self.identity == identity else {}
        verified, reused, elapsed = 0, 0, 0
        try:
            for ident, expected in reviewed.items():
                self.phase = 'SOURCE_BODY:' + ident
                if interrupt == ident:
                    raise ValueError('CANCELLED')
                elapsed += (costs or {}).get(ident, 0)
                if elapsed >= deadline:
                    raise ValueError('DEADLINE')
                # Only mounted sources are immutable; each body binding is read.
                saved = transaction.get(ident)
                if (not saved or not mounted_immutable) and observed.get(ident, '').replace('\r', '') != expected['source']:
                    raise ValueError('SOURCE_UNQUALIFIED')
                if saved and saved[1] == bindings.get(ident):
                    reused += 1
                    continue
                if canonical_spans(bindings.get(ident, '')) not in [canonical_spans(f) for f in expected['forms']]:
                    raise ValueError('BODY_UNQUALIFIED')
                transaction[ident] = (expected['source'], bindings[ident])
                verified += 1
            if unknown:
                raise ValueError('UNKNOWN_CALLBACK')
            self.phase = 'FINAL_BINDINGS_REGISTRIES'
            if final_bindings is not None and final_bindings != bindings:
                raise ValueError('FUNCTION_CHANGED')
            if final_registry is not None and final_registry != registry:
                raise ValueError('REGISTRY_CHANGED')
            self.identity, self.cache = identity, transaction
            self.snapshot = (dict(bindings), list(registry))
            self.ready, self.phase, self.reason = True, 'PREPARED_ONLY', None
            return 'PREPARED_ONLY', (verified, reused)
        except ValueError as error:
            self.phase, self.reason = 'NOT_RUN', str(error)
            return self.reason, (verified, reused)
        finally:
            self.active = False

    def revalidate(self, bindings, registry, object_callbacks=None, wanted=None, conditions=True):
        if not self.ready:
            return 'PREPARATION_REQUIRED'
        if bindings != self.snapshot[0]:
            return 'FUNCTION_CHANGED'
        if registry != self.snapshot[1]:
            return 'REGISTRY_CHANGED'
        if object_callbacks is not None and object_callbacks != wanted:
            return 'OBJECT_CALLBACKS_CHANGED'
        if not conditions:
            return 'COMPATIBILITY_CONDITION'
        return 'POLICY_ONLY'


def applicable(row, *, is_server, is_dedicated):
    """CBA role selection uses !isDedicated, NOT hasInterface.

    class_match/overridden are observations supplied by the snapshot producer;
    this model does not pretend to evaluate engine isKindOf/config merge.
    """
    if row.get("metadata") or not row.get("class_match", True) or row.get("overridden", False):
        return False
    if not row.get("inherit", True) and not row.get("exact_class", False):
        return False
    if row.get("excluded", False):
        return False
    role = row.get("role", "all")
    return role == "all" or (role == "server" and is_server) or (role == "client" and not is_dedicated)


def decide(snapshot, policy=None):
    """Return a first refusal and required conditions for a synthetic inventory.

    Registry rows are authoritative applicable callbacks, including additions
    from addClassEventHandler. Unmatched dynamic rows fail closed.
    """
    policy = policy or load_policy()
    by_path = {c["path"]: c for c in policy["callbacks"]}
    conditions = set()
    if snapshot.get("cba", False) and not snapshot.get("dispatch_qualified", False):
        return "CBA_FORWARDER_UNQUALIFIED", conditions
    for row in snapshot.get("native", []):
        body = row["body"]
        if not body:
            continue
        if body in ("call cba_xeh_fnc_init", "call cba_xeh_fnc_local"):
            if not snapshot.get("cba", False):
                return "UNKNOWN_NATIVE_CALLBACK", conditions
            continue
        match = by_path.get(row["path"])
        if not match or body != match["body"]:
            return "UNKNOWN_NATIVE_CALLBACK", conditions
        conditions.update(match["conditions"])
    if snapshot.get("cba", False):
        rows = [r for r in snapshot.get("config", [])
                if applicable(r, is_server=snapshot.get("is_server", True),
                              is_dedicated=snapshot.get("is_dedicated", False))]
        for registered in snapshot.get("registered", []):
            match = next((r for r in rows if r["code_id"] == registered["code_id"]), None)
            if match is None:
                dynamic = next((d for d in policy["dynamic_callbacks"]
                                if d["id"] == registered.get("reviewed_dynamic_id")), None)
                if dynamic and registered.get("source_qualified", False) and registered.get("function_qualified", False):
                    conditions.update(dynamic["conditions"])
                    continue
                return "UNKNOWN_DYNAMIC_CALLBACK", conditions
            reviewed = by_path.get(match["path"])
            if not reviewed or match["body"] != reviewed["body"]:
                return "UNKNOWN_CALLBACK", conditions
            if not match.get("source_qualified", True) or not match.get("function_qualified", True):
                return "IMPLEMENTATION_UNQUALIFIED", conditions
            conditions.update(reviewed["conditions"])
    failed = conditions - set(snapshot.get("verified_conditions", []))
    if failed:
        return "COMPATIBILITY_CONDITION:" + sorted(failed)[0], conditions
    return "ADMITTED_POLICY_ONLY", conditions


def specimen_conditions(*, crew, effects=(), fcs=False, radio=False, laser=False,
                        rallypoint=False, captive=False, mute=False):
    """Illustrative measured fields, separate from dispatch/pin qualification."""
    result = {"UA_PG7VL", "KVN_EXACT_VARIANT"}
    if crew and all(not any(c.get(k, "") for k in ("primary", "handgun", "secondary", "current"))
                    and not c.get("bayonet_control", False) for c in crew):
        result.add("UNARMED_CREW")
    if crew and all(not c.get("unconscious", False) for c in crew):
        result.add("CONSCIOUS_CREW")
    for name in ("CBA_EFFECTS_UNDEFINED", "ACE_EFFECTS_UNDEFINED"):
        if not effects:
            result.add(name)
    for name, active in (("FCS_DISABLED", fcs), ("RADIO_OFF", radio), ("LASER_OFF", laser),
                         ("NO_RALLYPOINT", rallypoint), ("NO_CAPTIVE_STATE", captive),
                         ("MUTE_UNDEFINED", mute)):
        if not active:
            result.add(name)
    return result


def cargo_condition(class_name, config, actual, *, policy=None, baseline_mass=None,
                    initialized=False, retained_resources=()):
    """Measured Cargo facts; never calls a vendor API or modifies resources.

    Engine command/variable collection and native initialization remain pending.
    An agreeing Boolean override is supported; a path switch is not.
    """
    policy = policy or load_policy()
    profile = next((p for p in policy['cargo_profiles'] if p[0] == class_name), None)
    if not profile or config != dict(has_cargo=profile[2], space=profile[3], configured=[]):
        return 'CARGO_CONFIG_UNQUALIFIED'
    _, path, has, space = profile
    override = actual.get('has_cargo')
    if override is not None and (type(override) is not bool or override != bool(has)):
        return 'HAS_CARGO_OVERRIDE'
    if type(actual.get('space', space)) not in (int, float) or actual.get('space', space) != space:
        return 'SPACE_OVERRIDE'
    init = actual.get('init', False)
    if type(init) is not bool or (not has and init):
        return 'INIT_STATE'
    if initialized and has and not init:
        return 'NATIVE_INIT_PENDING'
    if any(k in actual for k in ('can_load', 'size')) or actual.get('setspace_jip', False) is not False:
        return 'LOADABILITY_OR_SETSPACE_OVERRIDE'
    if baseline_mass is not None and actual.get('mass') != baseline_mass:
        return 'MASS_CHANGED'
    resources = [actual] + list(retained_resources)
    if len(resources) > 32:
        return 'CONTAINER_BOUND'
    if any(r.get('loaded', []) != [] or r.get('attached', []) != [] or r.get('attached_to')
           or r.get('vehicle_cargo', []) != [] or r.get('cargo_parent') for r in resources):
        return 'LOADED_OR_ATTACHED_RESOURCE'
    if actual.get('interaction') or actual.get('preview') or actual.get('deploy_pfh', -1) != -1:
        return 'CARGO_INTERACTION_OR_DEPLOYMENT'
    return path


def cargo_cleanup_allowed(result, *, previously_unsafe=False):
    return not previously_unsafe and result in ('DISABLED', 'ENABLED_EMPTY')


def unmatched_identity(code, policy=None):
    """Bounded diagnostic source label only; never an admission predicate."""
    for pin in (policy or load_policy())['pins']:
        if '"' + pin['path'] + '"' in code:
            return ['SOURCE_LABEL_ONLY', pin['path'][:160], pin['function'][:80]]
    return ['UNIDENTIFIED']


if __name__ == "__main__":
    expected = render_policy(load_policy())
    if expected != (ROOT / "motion_policy_data.sqf").read_text(encoding="utf-8"):
        raise SystemExit("FAIL: reviewed JSON / SQF data differ")
    print("PASS: reviewed policy data agree; engine semantics NOT RUN")
