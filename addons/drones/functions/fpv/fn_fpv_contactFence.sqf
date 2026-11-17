// Exactly one warhead between our fuse and the drone packs' own explode handlers (EN-02 design
// section 7.3), owner-local, never broadcast. UA, KVN and Crocus detonate on the engine's hit event
// (seen on 9 November), whatever damage they filter. Whichever fires first wins:
//  "NATIVE"  true when the pack has already fired (its own flag is set, and not by us): our fuse
//            must not add a warhead.
//  "SET"     our fuse approved: set the pack's own "already exploded" flag on this machine, so
//            its handler cannot add a warhead before the server commits.
//  "RELEASE" the commit was refused (or never sent): lift our fence so the native backstop works
//            again. Only a flag this function set is ever cleared.
//  "TICK"    lift a fence older than 0.75 s whose commit never arrived (a remote owner).
// [uav, action] -> Boolean
params [["_uav", objNull], ["_action", ""]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav || {!local _uav}) exitWith {false};
private _flag = switch (_uav getVariable ["A3UE_FPV_vendorId", ""]) do {
	case "fpv_ua": {"UA_FPV_Detonated"};
	case "kvn": {"kvn_detonated"};
	case "armafpv": {"DB_fpv_isDetonating"};
	default {""};
};
if (_flag == "") exitWith {false};
private _fence = _uav getVariable ["A3UE_FPV_contactFence", []];
private _ours = _fence isEqualType [] && {count _fence == 2};
private _result = false;
switch (_action) do {
	case "NATIVE": {
		_result = !_ours && {(_uav getVariable [_flag, false]) isEqualTo true};
	};
	case "SET": {
		if (_ours) then {
			_fence set [1, time + 0.75];
			_result = true;
		} else {
			if ((_uav getVariable [_flag, false]) isNotEqualTo true) then {
				_uav setVariable [_flag, true];
				_uav setVariable ["A3UE_FPV_contactFence", [_flag, time + 0.75]];
				_result = true;
			};
		};
	};
	case "RELEASE": {
		if (_ours && {!(_uav getVariable ["A3UE_FPV_detonating", false])}) then {
			_uav setVariable [_fence # 0, false];
			_uav setVariable ["A3UE_FPV_contactFence", []];
			_result = true;
		};
	};
	case "TICK": {
		if (_ours && {time > (_fence # 1) || {time < (_fence # 1) - 1}} && {!(_uav getVariable ["A3UE_FPV_detonating", false])}) then {
			_uav setVariable [_fence # 0, false];
			_uav setVariable ["A3UE_FPV_contactFence", []];
			_result = true;
		};
	};
};
_result
