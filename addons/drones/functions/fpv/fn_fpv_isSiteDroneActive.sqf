params [["_uav", objNull]];

// Support/rival/unmanaged assets retain their existing contracts.
if ((_uav getVariable ["A3UE_FPV_siteEpoch", ""]) == "") exitWith {true};
if (_uav getVariable ["A3UE_FPV_siteRetired", false]) exitWith {false};
private _pilot = driver _uav;
// Bare captivity is a native UAV setting, not capture of the remote pilot (V01).
if (isNull _pilot || {!alive _pilot} || {_pilot getVariable ["surrendered", false]}) exitWith {false};
private _siteSide = _uav getVariable ["A3UE_FPV_siteSide", sideUnknown];
if (side group _pilot != _siteSide) exitWith {false};
// Server fuse uses authoritative ownership; owner guidance sees replicated sides.
isNil "sidesX" || {sidesX getVariable [_uav getVariable ["A3UE_FPV_siteMarker", ""], sideUnknown] == _siteSide}
