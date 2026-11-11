# Reviewed Antistasi boundary

AU-04 pins **AU 12.0.3**, not every future Ultimate version. The six executable adapters retain their existing `functions/fpv/au_overrides/` PBO paths. Notification adapters own only FPV formatting/delivery; all other types delegate to loaded AU source. No-pack attacks also delegate to loaded AU source. The four FPV-capable attack copies remain necessary until explicit upstream selection/context hooks exist.

[manifest.json](manifest.json) records original categories, reviewed upstream hashes, each adapter's purpose, four supporting AU contracts and eight build header hashes. `changes/*.patch` records the complete deliberate delta from upstream. The gate reverses each patch against current addon source and verifies the reconstructed original hash, so an unrecorded edit both inside and outside a hunk fails. This stores no second executable copy of the attack bodies. UTF-8/BOM, CRLF/LF and terminal newlines are normalized; all other text participates in the hash. Exact original byte hashes are retained as provenance.

Run from the repository root:

```powershell
python tools/verify_au_adapter.py
python tools/verify_au_adapter.py --upstream 'external/A3-Antistasi-Ultimate-12.0.3/A3A/addons/core'
python -m unittest discover -s tools/tests -p test_au_adapter.py -v
```

The default checks the ignored supplied reference if present. With no reference, it reports **NOT SUPPLIED** and checks the pinned source/patch/header/config contract only. An explicitly supplied missing candidate fails. Both `verify_hemtt.py build` and `release` run this gate and record its evidence scope. Bare HEMTT compilation does not run the Python gate. Release qualification requires the source for the actual deployed AU version, not just the old local reference.

For an AU update, pass its read-only core directory explicitly; do not overwrite the old references or accept drift automatically. Review all six upstream bodies, original categories, `createSupport` lock/cost/debit and scheduler routes, plus macro snapshots. Port only needed FPV deltas, record new hashes/intentional patches as an explicitly reviewed version, and rerun the build/artifact gates and [AU-04 engine card](../../docs/bugs/AU04_Maintained_Extension_Boundary.md). No automatic pin-refresh command is provided. A source hash match does not establish engine binding or runtime compatibility.

AU retains tasks, troop composition, support serialization, resource debit, capture/retreat and ordinary cleanup. FPV retains planning, launch and its own autonomous lifecycle. Do not infer attack-private variables through a long-running wrapper or move AU's support maps/lock to an HC. Future upstream hooks should accept explicit side/target/origin/pool/spend/delay/type and return synchronous success/cost. They remain proposals, not capabilities of 12.0.3.

This boundary does not install over runtime foreign providers. The local startup/on-demand `A3UE_fnc_fpv_reportAUAdapter` reports loaded/reviewed versions, exact category/config path, library metadata, effective packaged-body match, source-addon provenance and duplicate declarations for each public binding. It never assigns `A3A_fnc_*`. A config-layer conflict still depends on mod order; inspect the merged engine config and run the card in both orders. Registry and Rivals provider ownership remain AU-06 work.
