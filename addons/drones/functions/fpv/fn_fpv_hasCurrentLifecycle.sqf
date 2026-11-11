params [["_uav", objNull, [objNull]], ["_generation", -1, [0]]];
if (isNull _uav || {!local _uav}) exitWith {false};
private _ticket = _uav getVariable ["A3UE_FPV_lifecycleTicket", []];
private _accepted = _uav getVariable ["A3UE_FPV_lifecycleTicketIdentity", []];
private _identity = _uav getVariable ["A3UE_FPV_controllerIdentity", []];
if (count _ticket != 3 || {count _accepted != 4} || {count _identity != 4}) exitWith {false};
if (_generation < 0) then {
    _generation = _uav getVariable [["A3UE_FPV_nativeGeneration", "A3UE_FPV_controllerGeneration"] select (_uav getVariable ["A3UE_FPV_managed", false]), -1];
};
// The replicated identity can arrive before ready. Only ready binds the private
// ticket to an owner/generation; retry and public object state cannot do that.
_accepted isEqualTo [_uav getVariable ["A3UE_FPV_lifecycleId", -1], clientOwner,
    _uav getVariable ["A3UE_FPV_lifecycleEpisode", -1], _generation]
    && {_identity isEqualTo _accepted}
    && {(_ticket # 0) == (_accepted # 0)} && {(_ticket # 1) == (_accepted # 2)}
    && {(_ticket # 2) != ""}
