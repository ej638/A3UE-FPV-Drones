if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {false};
private _records = missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap];
private _closed = [];
{
    private _y = _records get _x;
    private _previous = _y getOrDefault ["previous", []];
    if (count _previous == 4 && {serverTime > (_previous # 3)}) then {_y deleteAt "previous"; _y deleteAt "previousSequences";};
    private _challenge = _y getOrDefault ["challenge", []];
    if (count _challenge == 4 && {serverTime > (_challenge # 3)}) then {_y deleteAt "challenge";};
    if ((_y get "phase") == "closed") then {
        if (serverTime > (_y get "lateUntil")) then {_y deleteAt "retiredGeometry"; _y set ["object", objNull];};
        if (serverTime >= (_y get "closedAt") + 600) then {_records deleteAt _x;} else {_closed pushBack [_y get "closedAt", _x];};
    } else {
        if (serverTime > (_y getOrDefault ["pendingUntil", -1])) then {_y deleteAt "pendingGeometry";};
    };
} forEach keys _records;
_closed sort true;
while {count _closed > 256} do {_records deleteAt ((_closed deleteAt 0) # 1);};
// Source slots are never evicted inside their rate window (no source churn bypass).
private _rates = missionNamespace getVariable ["A3UE_FPV_archiveRates", createHashMap];
{if (serverTime >= ((_rates get _x) # 0) + 10) then {_rates deleteAt _x;};} forEach keys _rates;
true
