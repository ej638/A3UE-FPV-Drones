// 1.0.9 friendly FPV swarm (SW-2): wraps AU's SCRT_fnc_ui_launchSupport (the Supports tab's Launch
// button; AU spawns it). Every AU type runs AU's own copy, unchanged. For the swarm:
// - the same checks AU makes, with AU's own messages: cooldown, support points, money, radio, target;
// - then the commander's machine only asks: the server checks again, calls the swarm and charges
//   (swarmCall) and answers this machine (swarmCallReply);
// - on success, AU's cooldown as AU's planes hold it: no other support until the swarm is on station
//   (swarmNotify) or 2 minutes; then AU clears the markers (SCRT_fnc_ui_clearSupport).
// Messages through SCRT_fnc_ui_showMessage; the menu's counters through SCRT_fnc_ui_updateSupportMenu.
// [] -> nothing (scheduled; AU's function returns nothing)
if (isNil "supportType" || {supportType isNotEqualTo "A3UE_FPV_SWARM"}) exitWith {
	_this call (["ui_launchSupport"] call A3UE_fnc_fpv_getStockAUFunction)
};
private _message = {
	params ["_type", "_text"];
	[localize _type, localize "STR_notifiers_support_header", parseText _text, 30] spawn SCRT_fnc_ui_showMessage;
};
private _settings = call A3UE_fnc_fpv_swarmSettings;
private _points = _settings get "costPoints";
private _money = _settings get "costMoney";
private _rebels = if (isNil "A3A_faction_reb") then {""} else {A3A_faction_reb getOrDefault ["name", ""]};
private _currency = if (isNil "A3A_faction_civ") then {""} else {A3A_faction_civ getOrDefault ["currencySymbol", ""]};
private _why = switch (true) do {
	case (!isNil "supportCooldown" && {supportCooldown isEqualTo true}): {localize "STR_notifiers_support_overwhelmed"};
	case (isNil "supportPoints" || {!(supportPoints isEqualType 0)} || {supportPoints < _points}): {localize "STR_notifiers_support_not_enough_support"};
	case ((server getVariable ["resourcesFIA", 0]) < _money): {format [localize "STR_notifiers_support_need_money", _rebels, _money, _currency]};
	case (!([player] call A3A_fnc_hasRadio)): {localize "STR_notifiers_support_need_radio"};
	case (isNil "supportMarkerOrigin" || {(getMarkerColor supportMarkerOrigin) isEqualTo ""}): {localize "STR_notifiers_support_specify_origin"};
	default {""};
};
if (_why != "") exitWith {["STR_notifiers_fail_type", _why] call _message;};

// Ask the server and wait for its answer (at most 10 s).
private _token = floor (random 1e6);
private _answer = {
	private _got = missionNamespace getVariable ["A3UE_FPV_swarmCallReply", []];
	[[], _got] select (_got isEqualType [] && {count _got == 3} && {(_got # 2) isEqualTo _token})
};
missionNamespace setVariable ["A3UE_FPV_swarmCallReply", []];
[getMarkerPos supportMarkerOrigin, player, _token] remoteExecCall ["A3UE_fnc_fpv_swarmCall", 2];
private _until = diag_tickTime + 10;
waitUntil {sleep 0.1; ((call _answer) isNotEqualTo []) || {diag_tickTime > _until}};
private _reply = call _answer;
if (_reply isEqualTo []) then {_reply = [false, "NO_REPLY", _token];};
if !(_reply # 0) exitWith {
	private _reason = _reply # 1;
	["STR_notifiers_fail_type", switch (_reason) do {
		case "COOLDOWN": {localize "STR_notifiers_support_overwhelmed"};
		case "NO_POINTS": {localize "STR_notifiers_support_not_enough_support"};
		case "NO_MONEY": {format [localize "STR_notifiers_support_need_money", _rebels, _money, _currency]};
		case "NO_RADIO": {localize "STR_notifiers_support_need_radio"};
		case "SWARM_ACTIVE": {localize "STR_A3UE_FPV_SWARM_REFUSED_ACTIVE"};
		case "NO_DRONE_PACK": {localize "STR_A3UE_FPV_SWARM_REFUSED_NO_PACK"};
		case "DISABLED": {localize "STR_A3UE_FPV_SWARM_REFUSED_DISABLED"};
		default {format [localize "STR_A3UE_FPV_SWARM_REFUSED_OTHER", _reason]};
	}] call _message;
};

[] spawn A3A_fnc_statistics;
[] call SCRT_fnc_ui_updateSupportMenu;
supportCooldown = true;
publicVariable "supportCooldown";
isSupportMarkerPlacingLocked = true;
publicVariable "isSupportMarkerPlacingLocked";
["STR_notifiers_success_type", localize "STR_notifiers_support_success"] call _message;

private _since = time;
private _timeOut = time + 120;
waitUntil {sleep 1; (missionNamespace getVariable ["A3UE_FPV_swarmArrivedAt", -1]) >= _since || {time > _timeOut}};
isSupportMarkerPlacingLocked = false;
publicVariable "isSupportMarkerPlacingLocked";
supportCooldown = false;
publicVariable "supportCooldown";
[] spawn SCRT_fnc_ui_clearSupport;
