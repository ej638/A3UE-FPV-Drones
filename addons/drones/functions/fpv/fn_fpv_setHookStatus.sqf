// Server-local transition diagnostics; never broadcast provider code or maps.
params ["_hook", "_state", "_reason", ["_provider", ""], ["_capability", ""]];
if (!isServer || {isRemoteExecuted}) exitWith {false};
private _rows = missionNamespace getVariable ["A3UE_FPV_hookStatus", createHashMap];
private _row = createHashMapFromArray [
	["state", _state], ["reason", _reason], ["provider", _provider], ["capability", _capability],
	["registered", missionNamespace getVariable ["A3UE_FPV_registrationComplete", false]],
	["ready", missionNamespace getVariable ["serverInitDone", false]],
	["auVersion", getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr")],
	["mode", missionNamespace getVariable ["gameMode", -1]]
];
if (_row isNotEqualTo (_rows getOrDefault [_hook, createHashMap])) then {
	diag_log ["A3UE FPV hook", _hook, _row];
};
_rows set [_hook, _row];
missionNamespace setVariable ["A3UE_FPV_hookStatus", _rows];
true
