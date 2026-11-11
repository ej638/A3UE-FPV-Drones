params [["_uav", objNull]];
if (isNull _uav || {!alive _uav} || {!(_uav getVariable ["A3UE_FPV_managed", false])}
    || {(_uav getVariable ["A3UE_FPV_vendorId", ""]) != "armafpv"}
    || {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) != "RADIO"}) exitWith {[]};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {
    _uav setVariable ["A3UE_FPV_signalViewControlled", true];
    []
};
if (_uav getVariable ["A3UE_FPV_signalViewControlled", false]) then {
    _uav setVariable ["A3UE_FPV_signalViewControlled", false];
    _uav setVariable ["A3UE_FPV_signalViewSince", serverTime];
};
private _snapshot = _uav getVariable ["A3UE_FPV_crocusSignalSnapshot", []];
private _controller = _uav getVariable ["A3UE_FPV_controllerIdentity", []];
if !(_controller isEqualType []) then {_controller = [];};
// Never combine a new controller with an old separately delivered control epoch.
private _identity = _uav getVariable ["A3UE_FPV_signalIdentity", []];
if !(_identity isEqualType []) then {_identity = [];};
private _water = _uav getVariable ["A3UE_FPV_signalViewWatermark", [-1, -1, -1]];
private _packet = _snapshot isEqualType [] && {count _snapshot == 6}
    && {(_snapshot # 0) isEqualTo netId _uav} && {(_snapshot # 1) isEqualType []}
    && {count (_snapshot # 1) == 5} && {(_snapshot # 2) isEqualType 0} && {finite (_snapshot # 2)};
// Both packet-first and state-first delivery advance the fence. Delayed state
// or a delayed packet cannot revalidate an older episode/control transition.
{
    if (count _x == 5 && {_x findIf {!(_x isEqualType 0) || {!finite _x}} < 0}) then {
        if ((_x # 2) > (_water # 0) || {(_x # 2) == (_water # 0) && {(_x # 4) > (_water # 1)}}) then {
            _water = [_x # 2, _x # 4, -1];
        };
    };
} forEach ([_controller + [-1], _identity] + (if (_packet) then {[_snapshot # 1]} else {[]}));
_uav setVariable ["A3UE_FPV_signalViewWatermark", _water];
if (_packet && {count _controller == 4} && {(_identity select [0, 4]) isEqualTo _controller}
    && {(_snapshot # 1) isEqualTo _identity}
    && {(_identity # 2) == (_water # 0)} && {(_identity # 4) == (_water # 1)}
    && {(_snapshot # 2) >= (_water # 2)} && {(_snapshot # 2) >= 1}
    && {(_snapshot # 3) isEqualType 0} && {finite (_snapshot # 3)}
    && {(_snapshot # 3) >= (_uav getVariable ["A3UE_FPV_signalViewSince", -1])}
    && {serverTime - (_snapshot # 3) >= 0} && {serverTime - (_snapshot # 3) <= 2}
    && {(_snapshot # 4) isEqualType 0} && {finite (_snapshot # 4)} && {(_snapshot # 4) >= 0} && {(_snapshot # 4) <= 1}
    && {(_snapshot # 5) isEqualType []} && {count (_snapshot # 5) == 14}) exitWith {
    _uav setVariable ["A3UE_FPV_signalViewWatermark", [_identity # 2, _identity # 4, _snapshot # 2]];
    [_snapshot # 4, +(_snapshot # 5)]
};
[1, ["altAGL", 40, "distance", 0, "maxDistance", 4000,
    "inJammer", false, "jammerFactor", 0, "obstacleCount", 0, "terrainMask", 0]]
