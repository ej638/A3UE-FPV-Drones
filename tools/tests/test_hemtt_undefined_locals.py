"""Gate on HEMTT's undefined-variable lint (L-S13).

HEMTT reports L-S13 only as "help", so a real undefined local hides among the
documented warnings. 1.0.7 shipped one (`_minWarTier` in resolveSupportPackage),
which logged a script error per candidate on every successful FPV strike.

The allowed findings are deliberate caller-scope reads: SQF lets a called function
read its caller's locals. Each is pinned to its file, so a new undefined local, or
an allowed name used in a new file, fails this test.
"""
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ALLOWED = {
    # Controller tick and identity, set by the drone controller loop.
    ("fn_fpv_trajectoryLimits.sqf", "_fpvTick"),
    ("fn_fpv_attackSettings.sqf", "_fpvTick"),
    ("fn_fpv_wingSettings.sqf", "_fpvTick"),
    ("fn_fpv_canActuate.sqf", "_fpvTick"),
    ("fn_fpv_resolveTarget.sqf", "_fpvTick"),
    ("fn_fpv_holdPattern.sqf", "_controllerIdentity"),
    ("fn_fpv_applyGuidance.sqf", "_controllerIdentity"),
    ("fn_fpv_overwatch.sqf", "_controllerIdentity"),
    ("fn_fpv_detonateCompat.sqf", "_controllerIdentity"),
    ("fn_fpv_runLostTarget.sqf", "_controllerIdentity"),
    ("fn_fpv_runTerminal.sqf", "_controllerIdentity"),
    # Authorization and context tokens, set by the trusted caller.
    ("fn_fpv_withSupportContext.sqf", "_A3UE_FPV_contextAuthorized"),
    ("fn_fpv_getSupportContext.sqf", "_A3UE_FPV_callContext"),
    ("fn_fpv_cleanupDrone.sqf", "_A3UE_FPV_strikeAuthorized"),
    ("fn_fpv_supportLaunch.sqf", "_A3UE_FPV_spawnAuthorized"),
    ("fn_fpv_lifecycleAccess.sqf", "_A3UE_FPV_lifecycleAuthorized"),
    ("fn_fpv_lifecycleAccess.sqf", "_A3UE_FPV_spawnAuthorized"),
    ("fn_fpv_spawnManagedDrone.sqf", "_A3UE_FPV_spawnAuthorized"),
    ("fn_fpv_onLocationSpawned.sqf", "_A3UE_FPV_siteWorkerContext"),
    # AU's A3A_fnc_createSupport scope.
    ("fn_SUP_FPV.sqf", "_type"),
    ("fn_SUP_FPV.sqf", "_createFunc"),
}

ANSI = re.compile(r"\x1b\[[0-9;]*m")
FINDING = re.compile(r"L-S13\]: Undefined variable `([^`]+)`\s*\n\s*\S+\s+(\S+?):\d+:\d+")


class HemttUndefinedLocalsTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("hemtt"), "hemtt not on PATH")
    def test_only_known_caller_scope_reads(self):
        result = subprocess.run(["hemtt", "check"], cwd=ROOT, capture_output=True,
                                text=True, encoding="utf-8", errors="replace")
        text = ANSI.sub("", result.stdout + result.stderr)
        self.assertEqual(result.returncode, 0, text[-2000:])
        found = {(Path(path).name, var) for var, path in FINDING.findall(text)}
        self.assertTrue(found, "no L-S13 findings parsed; check the HEMTT output format")
        unexpected = sorted(found - ALLOWED)
        self.assertEqual(unexpected, [], f"new undefined locals: {unexpected}")


if __name__ == "__main__":
    unittest.main()
