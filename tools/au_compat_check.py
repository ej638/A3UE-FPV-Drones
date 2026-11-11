"""Quick offline check of an Antistasi Ultimate (AU) release against this addon.

    python tools/au_compat_check.py <AU source>                     report; exit 0 OK, 1 REVIEW/WARN, 2 FAIL
    python tools/au_compat_check.py <AU source> --baseline <AU src>  also print diffs of changed files
    python tools/au_compat_check.py <AU source> --record <version>   store fingerprints, ONLY after review
    python tools/au_compat_check.py --find <version>                 print a located AU source folder

<AU source> is the GitHub source of A3-Antistasi-Ultimate (the folder that holds A3A/addons), e.g.
external/A3-Antistasi-Ultimate-12.4.1 in the original checkout.

Sections:
  pins     the six overridden AU bodies and pinned contracts (tools/verify_au_adapter.py)
  deps     every AU file this addon depends on, fingerprinted against reviewed AU versions
           (compat/au_dependency_review.json). The list is derived from the addon source each run.
  events   which AU event route the addon will take (mirrors fn_addFPVEventListeners.sqf), that the
           CBA names exist, and that AU still raises the site event synchronously at every site type
  sites    AU still schedules the site functions through A3A_fnc_scheduler (our site hook)
  gates    no feature may switch off by AU version: rejects version gates in the addon. Reports
           whether the AU version is in our reviewed list (fn_fpv_auReviewedVersion.sqf), which
           is informational only (the startup report logs a NOTICE on an off-list AU).
  extender AU 12.4+ extender rule against our CfgPatches A3A_compatibility
  globals  AU globals and template keys the addon reads still exist

Static source evidence only. It never qualifies Arma runtime behaviour, CBA's event core or the
installed Workshop build; a short engine smoke on the new AU does that.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons/drones"
REVIEW_FILE = ROOT / "compat/au_dependency_review.json"
sys.path.insert(0, str(ROOT / "tools"))
import verify_au_adapter as adapter  # noqa: E402

RANK = {"OK": 0, "INFO": 0, "REVIEW": 1, "WARN": 1, "FAIL": 2}

# Integration files read on every run, whether or not a symbol scan finds them.
FIXED = [
    "A3A/addons/core/CfgFunctions.hpp",
    "A3A/addons/core/Includes/script_version.hpp",
    "A3A/addons/core/Includes/script_mod.hpp",
    "A3A/addons/core/Includes/script_macros_defines.hpp",
    "A3A/addons/core/Includes/cba_events.hpp",
    "A3A/addons/core/functions/Base/fn_distance.sqf",
    "A3A/addons/core/functions/Base/fn_markerChange.sqf",
    "A3A/addons/core/functions/CREATE/fn_AIVEHinit.sqf",
    "A3A/addons/core/functions/Events/fn_addEventHandler.sqf",
    "A3A/addons/core/functions/Events/fn_triggerLocalEvent.sqf",
    "A3A/addons/core/functions/Events/fn_triggerServerEvent.sqf",
    "A3A/addons/core/functions/init/fn_initExtenderDetection.sqf",
    "A3A/addons/core/functions/init/fn_validateExtenderCompat.sqf",
    "A3A/addons/events/Events.hpp",
    "A3A/addons/events/functions/fn_addEventListener.sqf",
    "A3A/addons/events/functions/fn_triggerEvent.sqf",
    # Inbound: AU code that calls our SUP_FPV callbacks or reads our support-registry entries.
    "A3A/addons/core/functions/Supports/fn_initSupports.sqf",
    "A3A/addons/core/functions/Supports/fn_requestSupport.sqf",
    "A3A/addons/core/functions/Supports/fn_createSupport.sqf",
    "A3A/addons/zeus/functions/init/fn_initModule.sqf",
]
REVIEWED_LIST = "functions/fpv/fn_fpv_auReviewedVersion.sqf"
# The only addon file allowed to call the reviewed-list helper: it logs, never disables.
REVIEWED_LIST_READER = "functions/fpv/fn_fpv_reportAUAdapter.sqf"
# Functions the addon feature-detects with isNil; absence is a route choice, not a break.
OPTIONAL_FUNCTIONS = {"a3a_fnc_addeventhandler", "a3a_events_fnc_addeventlistener"}
# AU globals and faction keys read by string or name; checked only if the addon still uses them.
GLOBALS = [
    "serverInitDone", "sidesX", "teamPlayer", "Occupants", "Invaders", "spawner", "forcedSpawn",
    "tierWar", "theBoss", "petros", "airportsX", "outposts", "resourcesX", "seaports", "milbases",
    "factories", "garrison", "citiesX", "areOccupantsDefeated", "hcArray", "gameMode",
    "A3A_activeSupports", "A3A_supportStrikes", "A3A_supportMarkerCount", "A3A_supportCount",
    "A3A_supportCallInProgress", "A3A_supportTypesOcc", "A3A_supportTypesInv", "A3A_resPool",
    "A3A_taskCount", "A3A_vehicleResourceCosts", "A3A_balancePlayerScale", "A3A_balanceVehicleCost",
    "A3A_saveTarget", "A3A_faction_occ", "A3A_faction_inv", "A3A_faction_riv", "A3A_faction_civ",
    "vehiclesRivalsUavs", "uavsAttack", "uavsPortable", "minefieldAPERS", "attributeLowAir", "unitUnarmed",
]
SITE_EVENT = "locationSpawned"


@dataclass
class Finding:
    verdict: str
    section: str
    message: str
    path: str = ""


def text(path):
    return path.read_text(encoding="utf-8-sig", errors="replace").replace("\r\n", "\n")


def fingerprint(path):
    return adapter.digest(adapter.normalized(path)) if path.is_file() else None


def addon_sources(addon):
    return {p: text(p) for p in sorted(addon.rglob("*")) if p.suffix in (".sqf", ".cpp", ".hpp", ".inc")}


def main_checkout(root=ROOT):
    """A worktree's .git file names <main>/.git/worktrees/<name>; external/ lives in <main>."""
    git = root / ".git"
    if git.is_file():
        line = git.read_text().strip()
        if line.startswith("gitdir:"):
            gitdir = Path(line.split(":", 1)[1].strip())
            if gitdir.parent.name == "worktrees":
                return gitdir.parent.parent.parent
    return None


def find_au_source(version, root=ROOT):
    bases = [Path(os.environ["FPV_AU_SOURCES"])] if os.environ.get("FPV_AU_SOURCES") else []
    bases.append(root / "external")
    if main_checkout(root):
        bases.append(main_checkout(root) / "external")
    for base in bases:
        candidate = base / f"A3-Antistasi-Ultimate-{version}"
        if (candidate / "A3A/addons").is_dir():
            return candidate
    return None


def function_index(au):
    index = {}
    for f in (au / "A3A/addons").rglob("fn_*.sqf"):
        rel = f.relative_to(au).as_posix()
        index.setdefault(f.stem[3:].lower(), []).append(rel)
    return index


def resolve(symbol, index):
    """A3A_Events_fnc_x -> events addon, SCRT_fnc_x -> scrt, A3A_fnc_x -> any other addon."""
    prefix, name = symbol.lower().split("_fnc_", 1)
    rows = index.get(name, [])
    if prefix == "a3a_events":
        return [r for r in rows if "/addons/events/" in r]
    if prefix == "scrt":
        return [r for r in rows if "/addons/scrt/" in r]
    return [r for r in rows if "/addons/events/" not in r and "/addons/scrt/" not in r]


def our_declarations(config):
    """A3A-namespace functions declared by our config (own SUP_FPV or reviewed overrides)."""
    block = adapter.config_block(adapter.config_block(config, "CfgFunctions"), "A3A")
    return {f"a3a_fnc_{n.lower()}" for n in re.findall(r"class\s+(\w+)\s*\{\s*file\s*=", block)}


def dependency_paths(au, addon=ADDON):
    sources = addon_sources(addon)
    corpus = "\n".join(sources.values())
    symbols = sorted({m.group(0).lower() for m in re.finditer(r"(?i)\b(?:a3a_events|a3a|scrt|a3u)_fnc_\w+", corpus)
                      if not m.group(0).lower().endswith("_fnc_")})
    ours = our_declarations(text(addon / "config.cpp"))
    index = function_index(au)
    deps, missing = set(FIXED), []
    for symbol in symbols:
        rows = resolve(symbol, index)
        if rows:
            deps.update(rows)
        elif symbol not in ours and symbol not in OPTIONAL_FUNCTIONS:
            missing.append(symbol)
    return sorted(deps), symbols, ours, missing


def required_paths(au, addon=ADDON):
    """Every AU path this checker may read (lets tests build a small synthetic AU tree)."""
    deps, *_ = dependency_paths(au, addon)
    manifest = json.loads((ROOT / adapter.PIN / "manifest.json").read_text())
    core = "A3A/addons/core/"
    pins = [core + r["upstream"] for r in manifest["overrides"]] + [core + r["path"] for r in manifest["contracts"]]
    return sorted(set(deps) | set(pins))


# ---------------------------------------------------------------------------- sections
def check_pins(au):
    try:
        result = adapter.verify(ROOT, upstream=au / "A3A/addons/core")
        return [Finding("OK", "pins", f"6 override bodies and contracts match reviewed AU {result['upstream_matches']}")]
    except (ValueError, OSError, KeyError, IndexError) as error:
        message = str(error)
        if "Changed candidate upstream body" in message:
            return [Finding("FAIL", "pins", message + " (our override would hide this AU change; re-port the patch)")]
        if "Changed AU contract" in message:
            return [Finding("REVIEW", "pins", message + " (pinned contract differs from every reviewed AU)")]
        return [Finding("FAIL", "pins", message)]


def check_dependencies(au, addon, review, baseline, verbose):
    deps, symbols, ours, missing = dependency_paths(au, addon)
    findings = [Finding("FAIL", "deps", f"AU no longer defines {s}, which the addon calls") for s in missing]
    index = function_index(au)
    manifest = json.loads((ROOT / adapter.PIN / "manifest.json").read_text())
    reviewed_overrides = {r["name"].lower() for r in manifest["overrides"]}
    for symbol in sorted(ours):
        name = symbol.split("_fnc_", 1)[1]
        clash = resolve(symbol, index)
        if clash and name not in reviewed_overrides:
            findings.append(Finding("FAIL", "deps", f"AU now defines {symbol} itself; our declaration would replace it", clash[0]))
    versions = review.get("versions", {})
    matched = {}
    for rel in deps:
        actual = fingerprint(au / rel)
        known = {v: data["files"][rel] for v, data in versions.items() if rel in data.get("files", {})}
        hits = [v for v, sha in known.items() if sha == actual]
        if hits:
            for v in hits:
                matched[v] = matched.get(v, 0) + 1
            if verbose:
                findings.append(Finding("OK", "deps", f"matches reviewed {', '.join(hits)}", rel))
            continue
        if not known:
            state = "absent" if actual is None else "present"
            findings.append(Finding("REVIEW", "deps", f"unreviewed dependency ({state}); read it, then --record", rel))
            continue
        if actual is None:
            findings.append(Finding("REVIEW", "deps", "file removed since reviewed AU " + ", ".join(known), rel))
            continue
        if all(sha is None for sha in known.values()):
            message = "added since reviewed AU " + ", ".join(known)
        else:
            message = "changed since reviewed AU " + ", ".join(v for v, sha in known.items() if sha is not None)
        if baseline is not None and (baseline / rel).is_file():
            diff = list(difflib.unified_diff(adapter.normalized(baseline / rel).splitlines(),
                                             adapter.normalized(au / rel).splitlines(), "baseline", "candidate", n=1, lineterm=""))
            message += f"  ({rel})\n      " + "\n      ".join(diff[2:42]) + ("\n      ..." if len(diff) > 42 else "")
            rel = ""
        findings.append(Finding("REVIEW", "deps", message, rel))
    summary = ", ".join(f"{v}: {n}" for v, n in sorted(matched.items())) or "none"
    findings.insert(0, Finding("INFO", "deps", f"{len(deps)} AU files from {len(symbols)} referenced AU functions; reviewed matches {summary}"))
    return findings


def cba_names(au):
    events = au / "A3A/addons/core/Includes/cba_events.hpp"
    if not events.is_file():
        return {}
    prefixes = {"PREFIX": "A3A", "PREFIX_CONST": "A3A"}
    for rel in ["A3A/addons/core/Includes/script_mod.hpp", "A3A/addons/core/Includes/script_macros_defines.hpp"]:
        if (au / rel).is_file():
            for key, value in re.findall(r"#define\s+(PREFIX(?:_CONST)?)\s+(\w+)", text(au / rel)):
                prefixes[key] = value
    return {macro: f"{prefixes[prefix]}_event_{name}" for macro, prefix, name in re.findall(
        r"#define\s+(CBA_EVENT_\w+)\s+QUOTE\(TRIPLES\((PREFIX(?:_CONST)?),\s*event,\s*(\w+)\)\)", text(events))}


def legacy_mapping(au):
    path = au / "A3A/addons/events/Events.hpp"
    return dict(re.findall(r"REPLACE_EVENT\(\s*(\w+)\s*,\s*(CBA_EVENT_\w+)\s*\)", text(path))) if path.is_file() else {}


def our_subscriptions(addon):
    source = text(addon / "functions/fpv/fn_addFPVEventListeners.sqf")
    return re.findall(r'\[\s*"(\w+)"\s*,\s*"(A3A_event_\w+)"\s*,\s*"(\w+)"\s*,\s*(A3UE_fnc_\w+)\s*,\s*(true|isServer)\s*\]', source)


TRIGGER = re.compile(r"\[\s*(?P<event>\"\w+\"|CBA_EVENT_\w+)\s*,\s*(?P<args>\[[^\]]*\])\s*\]\s*(?P<how>call|spawn)\s+"
                     r"(?:EFUNC\(\s*Events\s*,\s*triggerEvent\s*\)|A3A_Events_fnc_triggerEvent|FUNCMAIN\(\s*trigger(?P<kind1>\w+)Event\s*\)|A3A_fnc_trigger(?P<kind2>\w+)Event)")


def trigger_name(kind):
    return "legacy A3A_Events_fnc_triggerEvent" if kind == "Legacy" else f"A3A_fnc_trigger{kind}Event"


def triggers(path, event_tokens):
    rows = []
    for m in TRIGGER.finditer(text(path)):
        if m.group("event").strip('"') in event_tokens:
            kind = m.group("kind1") or m.group("kind2") or "Legacy"
            rows.append((kind, m.group("how"), m.group("args")))
    return rows


def site_functions(addon):
    source = text(addon / "functions/fpv/fn_fpv_scheduleSite.sqf")
    return re.findall(r'case\s+"(A3A_fnc_createAI\w+)"\s*:\s*\{\s*"(\w+)"\s*\}', source)


def check_events(au, addon):
    findings = []
    subs = our_subscriptions(addon)
    if len(subs) != 3:
        return [Finding("FAIL", "events", f"could not read the subscription table in fn_addFPVEventListeners.sqf ({len(subs)} rows)")]
    has_legacy = (au / "A3A/addons/events/functions/fn_addEventListener.sqf").is_file()
    has_cba = (au / "A3A/addons/core/functions/Events/fn_addEventHandler.sqf").is_file()
    names, mapping = cba_names(au), legacy_mapping(au)
    routes = {}
    for legacy, builtin, _, _, _ in subs:
        if legacy in mapping:
            route, event = "CBA", names.get(mapping[legacy], "")
            if not event:
                findings.append(Finding("FAIL", "events", f"AU maps {legacy} to {mapping[legacy]}, which cba_events.hpp does not define"))
                continue
            if event != builtin:
                findings.append(Finding("WARN", "events", f"AU maps {legacy} to {event}; our built-in fallback {builtin} is stale (works while AU keeps the mapping)"))
        elif has_legacy:
            route, event = "LEGACY", legacy
            if not re.search(r"class\s+" + legacy + r"\b", text(au / "A3A/addons/events/Events.hpp")):
                findings.append(Finding("FAIL", "events", f"legacy event {legacy} is no longer declared in Events.hpp"))
        elif has_cba:
            route, event = "CBA", builtin
            if builtin not in names.values():
                findings.append(Finding("FAIL", "events", f"no legacy API or mapping, and {builtin} is not a defined AU CBA event"))
        else:
            findings.append(Finding("FAIL", "events", "AU has neither the legacy listener API nor A3A_fnc_addEventHandler"))
            continue
        routes[legacy] = (route, event)
        tokens = {legacy, event} | {m for m, n in names.items() if n == event}
        findings.append(Finding("OK", "events", f"{legacy} -> {route} {event}"))
        if legacy == SITE_EVENT:
            for function, site_type in site_functions(addon):
                rel = resolve(function, function_index(au))
                if not rel:
                    findings.append(Finding("FAIL", "events", f"site function {function} not found"))
                    continue
                rows = triggers(au / rel[0], tokens)
                for spawning in ("true", "false"):
                    hit = [r for r in rows if re.search(r'"' + site_type + r'"\s*,\s*' + spawning + r"\b", r[2])]
                    if not hit:
                        findings.append(Finding("FAIL", "events", f"{site_type} no longer raises {event} (spawning={spawning})", rel[0]))
                        continue
                    kind, how, _ = hit[0]
                    if how != "call" or kind not in ("Legacy", "Local", "Server"):
                        findings.append(Finding("FAIL", "events", f"{site_type} raises the site event via {how} {trigger_name(kind)}; "
                                                "onLocationSpawned needs a synchronous call inside the site worker", rel[0]))
                    elif kind == "Server":
                        findings.append(Finding("WARN", "events", f"{site_type} uses triggerServerEvent: synchronous only when raised on the server", rel[0]))
            findings.append(Finding("INFO", "events", f"site event checked for {', '.join(t for _, t in site_functions(addon))} spawn+despawn"))
        else:
            source = {"AIVehInit": "A3A/addons/core/functions/CREATE/fn_AIVEHinit.sqf",
                      "markerChange": "A3A/addons/core/functions/Base/fn_markerChange.sqf"}.get(legacy)
            if source:
                rows = triggers(au / source, tokens) if (au / source).is_file() else []
                if not rows:
                    findings.append(Finding("FAIL", "events", f"{event} is no longer raised in {Path(source).name}", source))
                else:
                    kind, how, args = rows[0]
                    verdict = "OK" if how == "call" and kind in ("Legacy", "Local", "Server") else "WARN"
                    findings.append(Finding(verdict, "events", f"{legacy} raised via {how} {trigger_name(kind)} {args}", source))
    if any(route == "CBA" for route, _ in routes.values()):
        local = au / "A3A/addons/core/functions/Events/fn_triggerLocalEvent.sqf"
        body = text(local) if local.is_file() else ""
        if "call CBA_fnc_localEvent" in body and "spawn" not in body:
            findings.append(Finding("OK", "events", "A3A_fnc_triggerLocalEvent calls CBA_fnc_localEvent synchronously"))
        else:
            findings.append(Finding("FAIL", "events", "A3A_fnc_triggerLocalEvent no longer a plain call into CBA_fnc_localEvent", local.relative_to(au).as_posix()))
        findings.append(Finding("INFO", "events", "CBA's own dispatch (CALL_EVENT: `args call _x`) was read for CBA 3.19.0; re-read it if CBA changes its event core"))
    return findings


def check_sites(au, addon):
    distance = au / "A3A/addons/core/functions/Base/fn_distance.sqf"
    body = text(distance) if distance.is_file() else ""
    findings = []
    for function, site_type in site_functions(addon):
        exact = len(re.findall(r'"' + function + r'"\s*\]\s*call\s+A3A_fnc_scheduler', body))
        loose = len(re.findall(r'(?i)"' + function + r'"\s*\]\s*call\s+A3A_fnc_scheduler', body))
        if exact:
            findings.append(Finding("OK", "sites", f"{site_type}: {function} scheduled via A3A_fnc_scheduler ({exact} call sites)"))
        elif loose:
            findings.append(Finding("WARN", "sites", f"{site_type}: {function} scheduled with different letter case; check fn_fpv_scheduleSite matching", "A3A/addons/core/functions/Base/fn_distance.sqf"))
        else:
            findings.append(Finding("FAIL", "sites", f"{site_type}: {function} is no longer scheduled through A3A_fnc_scheduler; site drones would not deploy", "A3A/addons/core/functions/Base/fn_distance.sqf"))
    return findings


def check_extender(au, addon):
    rule = au / "A3A/addons/core/functions/init/fn_validateExtenderCompat.sqf"
    if not rule.is_file():
        return [Finding("INFO", "extender", "this AU has no extender compatibility check (pre-12.4)")]
    version = text(au / "A3A/addons/core/Includes/script_version.hpp")
    major, minor = (int(re.search(r"#define\s+" + k + r"\s+(\d+)", version).group(1)) for k in ("MAJOR", "MINOR"))
    patches = adapter.config_block(text(addon / "config.cpp"), "CfgPatches")
    required = re.search(r"requiredAddons\[\]\s*=\s*\{([^}]*)\}", patches)
    if not required or not re.search(r'(?i)"A3A_', required.group(1)):
        return [Finding("INFO", "extender", "CfgPatches does not require an A3A addon; AU will not treat this mod as an extender")]
    declared = re.search(r"A3A_compatibility\[\]\s*=\s*\{\s*(\d+)\s*,\s*(\d+)\s*\}", patches)
    dialog = " -> AU shows its blocking extender warning dialog at every game setup"
    if not declared:
        return [Finding("WARN", "extender", f"no A3A_compatibility[] in CfgPatches; AU {major}.{minor} reports 'missing A3A_compatibility information'" + dialog, "addons/drones/config.cpp")]
    a, b = int(declared.group(1)), int(declared.group(2))
    # Same order and rules as AU fn_validateExtenderCompat.sqf (12.4.1).
    reason = None
    if a > major:
        reason = "can't declare compatibility for a higher major version"
    elif b > minor:
        reason = "can't declare compatibility for a higher minor version"
    elif minor > 0 and b == 0:
        reason = "only declared compatibility for major versions"
    elif float(f"{a}.{b}") < float(f"{major}.{minor}"):
        reason = "compatibility version is lower than our version"
    if "compatibility version is lower than our version" not in text(rule):
        return [Finding("REVIEW", "extender", "AU changed its extender rule text; re-read fn_validateExtenderCompat.sqf", rule.relative_to(au).as_posix())]
    if reason:
        return [Finding("WARN", "extender", f"declares {{{a}, {b}}} on AU {major}.{minor}: '{reason}'" + dialog, "addons/drones/config.cpp")]
    return [Finding("OK", "extender", f"declares {{{a}, {b}}}; AU {major}.{minor} accepts it (patch releases exempt)")]


def au_version_str(au):
    """A3A_core versionStr = QUOTE(VERSION): MAJOR.MINOR.PATCHLVL, or MAJOR.MINOR when PATCHLVL is 0."""
    version = text(au / "A3A/addons/core/Includes/script_version.hpp")
    major, minor, patch = (re.search(r"#define\s+" + k + r"\s+(\d+)", version).group(1) for k in ("MAJOR", "MINOR", "PATCHLVL"))
    return f"{major}.{minor}.{patch}" if int(patch) > 0 else f"{major}.{minor}"


def check_gates(au, addon, review):
    """No feature switches off by AU version; the reviewed list only feeds the startup report."""
    findings = []
    helper = addon / REVIEWED_LIST
    match = re.search(r"_reviewed\s*=\s*\[([^\]]*)\]", text(helper)) if helper.is_file() else None
    if not match:
        return [Finding("FAIL", "gates", f"cannot read the reviewed AU list in {REVIEWED_LIST}")]
    reviewed = re.findall(r'"([^"]+)"', match.group(1))
    for path, source in addon_sources(addon).items():
        if path == helper:
            continue
        rel = path.relative_to(addon).as_posix()
        if (re.search(r'versionStr"\s*\)\s*(?:!=|==|isEqualTo|isNotEqualTo|in\b)', source)
                or "UNREVIEWED_AU_VERSION" in source):
            findings.append(Finding("FAIL", "gates", "AU version gate: features must not switch off by AU version", rel))
        elif rel != REVIEWED_LIST_READER and "A3UE_fnc_fpv_auReviewedVersion" in source:
            findings.append(Finding("FAIL", "gates", "reviewed-AU list read outside the startup report; it must stay "
                                    "informational, not gate a feature", rel))
    loaded = au_version_str(au)
    if loaded in reviewed:
        findings.append(Finding("OK", "gates", f"AU {loaded} is in the reviewed list {reviewed}"))
    else:
        findings.append(Finding("REVIEW", "gates", f"AU {loaded} is not in the reviewed list {reviewed}. Nothing switches "
                                "off for players (the startup report logs a NOTICE). After review, add it there and "
                                "--record it", "addons/drones/" + REVIEWED_LIST))
    unrecorded = [v for v in reviewed if v not in review.get("versions", {})]
    if unrecorded:
        findings.append(Finding("REVIEW", "gates", f"listed as reviewed but no dependency fingerprints recorded: {unrecorded}"))
    return findings


def check_globals(au, addon):
    corpus = "\n".join(addon_sources(addon).values())
    au_text = "\n".join(text(p) for p in (au / "A3A/addons").rglob("*") if p.suffix in (".sqf", ".hpp", ".inc", ".cpp"))
    findings, checked = [], 0
    for name in GLOBALS:
        if not re.search(r"\b" + re.escape(name) + r"\b", corpus):
            continue
        checked += 1
        if not re.search(r"\b" + re.escape(name) + r"\b", au_text):
            findings.append(Finding("REVIEW", "globals", f"{name} is read by the addon but no longer appears in AU"))
    findings.insert(0, Finding("OK" if not findings else "INFO", "globals", f"{checked} AU globals/template keys read by the addon checked"))
    return findings


def run_checks(au, addon=ADDON, review_file=REVIEW_FILE, baseline=None, verbose=False):
    au = Path(au)
    if not (au / "A3A/addons").is_dir():
        return [Finding("FAIL", "input", f"{au} is not an AU source folder (no A3A/addons)")]
    review = json.loads(review_file.read_text()) if review_file.is_file() else {"versions": {}}
    findings = check_pins(au)
    findings += check_dependencies(au, addon, review, baseline, verbose)
    findings += check_events(au, addon)
    findings += check_sites(au, addon)
    findings += check_gates(au, addon, review)
    findings += check_extender(au, addon)
    findings += check_globals(au, addon)
    return findings


def record(au, version, addon=ADDON, review_file=REVIEW_FILE):
    review = json.loads(review_file.read_text()) if review_file.is_file() else {"schema": 1, "versions": {}}
    review.setdefault("note", "Fingerprints of AU files this addon depends on, per AU version a human reviewed. "
                              "Written only by `au_compat_check.py --record` after review; never edited by hand.")
    deps, *_ = dependency_paths(au, addon)
    files = review["versions"].get(version, {}).get("files", {})
    files.update({rel: fingerprint(au / rel) for rel in deps})
    review["versions"][version] = {"recorded": date.today().isoformat(), "files": dict(sorted(files.items()))}
    review_file.write_text(json.dumps(review, indent=2) + "\n")
    return len(deps)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("au", nargs="?", type=Path, help="AU source folder (holds A3A/addons)")
    parser.add_argument("--baseline", type=Path, help="reviewed AU source folder, for diffs of changed files")
    parser.add_argument("--record", metavar="VERSION", help="store dependency fingerprints for VERSION (after review)")
    parser.add_argument("--find", metavar="VERSION", help="print the located external/A3-Antistasi-Ultimate-VERSION")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--verbose", action="store_true", help="also list dependency files that match")
    args = parser.parse_args(argv)
    if args.find:
        found = find_au_source(args.find)
        print(found or f"NOT FOUND: A3-Antistasi-Ultimate-{args.find}")
        return 0 if found else 2
    if args.au is None:
        parser.error("AU source folder required")
    findings = run_checks(args.au, baseline=args.baseline, verbose=args.verbose)
    worst = max(RANK[f.verdict] for f in findings)
    if args.record:
        if worst == 2:
            print("REFUSED: FAIL findings present; fix or accept them before recording a reviewed version")
            return 2
        print(f"Recorded {record(args.au, args.record)} dependency fingerprints for AU {args.record} in {REVIEW_FILE.relative_to(ROOT)}")
        return 0
    if args.json:
        print(json.dumps([asdict(f) for f in findings], indent=2))
    else:
        for f in findings:
            print(f"[{f.verdict:6}] {f.section:8} {f.message}" + (f"  ({f.path})" if f.path else ""))
        counts = {v: sum(f.verdict == v for f in findings) for v in ("FAIL", "WARN", "REVIEW")}
        label = {0: "PASS", 1: "NEEDS REVIEW", 2: "FAIL"}[worst]
        print(f"\n{label}: {counts['FAIL']} FAIL, {counts['WARN']} WARN, {counts['REVIEW']} REVIEW  (AU source: {args.au})")
    return worst


if __name__ == "__main__":
    sys.exit(main())
