// AU releases whose overrides, support registry, Rivals and event bindings were reviewed
// (docs/FPV_AU_12_4_1_Impact_Analysis_20261110.md). The only place this list lives;
// tools/au_compat_check.py reads it. Informational only: the startup adapter report logs it,
// and no feature switches off on an AU release that is not on the list.
// Returns [loaded A3A_core versionStr, reviewed versions, loaded version is reviewed].
private _version = getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr");
private _reviewed = ["12.0.3", "12.4.1"];
[_version, _reviewed, _version in _reviewed]
