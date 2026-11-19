// 1.0.9 friendly FPV swarm (SW-2): the commander's paid call from AU's Supports menu, on the server.
// The commander's machine only asks (SCRT_fnc_ui_launchSupport, our wrapper); the server checks and
// charges here (design §4.4; AU itself charges on the commander's machine with no server check):
// - the sender is the machine of the current commander (theBoss), a live player;
// - the swarm is switched on (setting), AU's support cooldown is free;
// - AU's support points and the rebels' money cover the cost ("costPoints", "costMoney"; EJ, 17
//   November: 1 support point + 500, no airport), and the commander has a radio (as AU checks);
// - then swarmRequest (one swarm at a time, the position, the drone packs), with the commander as
//   the caller, so the drones fly in over the commander (SW-1j).
// The cost is taken only once the swarm is called. The answer goes back to the sender only.
// [position, requester, token] (remoteExecCall to the server) -> nothing
params [["_pos", []], ["_requester", objNull], ["_token", 0]];
if (!isServer || {isRemoteExecutedJIP}) exitWith {};
private _sender = [clientOwner, remoteExecutedOwner] select isRemoteExecuted;
if !(_token isEqualType 0 && {finite _token}) then {_token = 0;};
private _settings = call A3UE_fnc_fpv_swarmSettings;
private _points = _settings get "costPoints";
private _money = _settings get "costMoney";
private _reply = {
	params ["_ok", "_why"];
	diag_log format ["[A3UE_FPV] swarm event=MENU_CALL ok=%1 why=%2 sender=%3 commander=%4 points=%5 money=%6",
		_ok, _why, _sender, if (isNil "theBoss" || {isNull theBoss}) then {-1} else {owner theBoss},
		if (isNil "supportPoints") then {-1} else {supportPoints}, server getVariable ["resourcesFIA", -1]];
	[_ok, _why, _token] remoteExecCall ["A3UE_fnc_fpv_swarmCallReply", _sender];
};
private _why = switch (true) do {
	case (!(["swarmEnabled"] call A3UE_fnc_fpv_userSetting)): {"DISABLED"};
	case (isNil "theBoss" || {!(_requester isEqualType objNull)} || {isNull _requester} || {_requester isNotEqualTo theBoss}
		|| {!alive _requester} || {!isPlayer _requester} || {(owner _requester) != _sender}): {"NOT_COMMANDER"};
	case (!isNil "supportCooldown" && {supportCooldown isEqualTo true}): {"COOLDOWN"};
	case (isNil "supportPoints" || {!(supportPoints isEqualType 0)} || {supportPoints < _points}): {"NO_POINTS"};
	case ((server getVariable ["resourcesFIA", 0]) < _money): {"NO_MONEY"};
	case (!isNil "A3A_fnc_hasRadio" && {!([_requester] call A3A_fnc_hasRadio)}): {"NO_RADIO"};
	default {""};
};
if (_why != "") exitWith {[false, _why] call _reply;};
// swarmRequest refuses remote callers other than the host; this checked call is let through.
localNamespace setVariable ["A3UE_FPV_swarmCallTrusted", true];
private _result = [_pos, -1, _requester] call A3UE_fnc_fpv_swarmRequest;
localNamespace setVariable ["A3UE_FPV_swarmCallTrusted", false];
if !(_result isEqualType [] && {count _result == 2}) then {_result = [false, "FAILED"];};
if ((_result # 0) isNotEqualTo true) exitWith {
	[false, [_result # 1, "FAILED"] select !((_result # 1) isEqualType "")] call _reply;
};
// AU's own accounting: points broadcast as AU does; money through AU's resource function (scheduled).
supportPoints = supportPoints - _points;
publicVariable "supportPoints";
[0, -_money] spawn A3A_fnc_resourcesFIA;
[true, _result # 1] call _reply;
