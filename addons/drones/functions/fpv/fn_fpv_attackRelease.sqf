// LT-2: leave the attack board (the drone dropped or changed its target). A cleared drone that
// leaves has ended its attack: the next one is cleared after the follow-up delay.
// Called from clearTarget, so every path that drops a target releases its slot. Constant work.
// [uav, reason] -> true when the drone was on the board
params [["_uav", objNull], ["_reason", "RELEASE"]];
// F5 / PB-01: an RPC from a client never mutates this machine's board (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav) exitWith {false};
private _key = _uav getVariable ["A3UE_FPV_wingTarget", ""];
if (_key isEqualTo "") exitWith {false};
_uav setVariable ["A3UE_FPV_wingTarget", ""];
private _record = (missionNamespace getVariable ["A3UE_FPV_attackBoard", createHashMap]) getOrDefault [_key, createHashMap];
if (count _record == 0) exitWith {false};
private _holders = _record get "holders";
private _index = _holders findIf {(_x # 0) isEqualTo _uav};
_record set ["queue", (_record get "queue") - [_uav]];
if (_index >= 0) then {
	_holders deleteAt _index;
	private _delay = ((call A3UE_fnc_fpv_wingSettings) # 3) + 0.5 * ((_record get "grants") mod 3);
	_record set ["nextGrantAt", (_record get "nextGrantAt") max (time + _delay)];
	diag_log format ["[A3UE_FPV] wing target=%1 event=%2 id=%3 attackers=%4 waiting=%5 nextInS=%6", _key, _reason, netId _uav,
		count _holders, count (_record get "queue"), (round (_delay * 10)) / 10];
};
true
