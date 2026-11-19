// 1.0.9 friendly FPV swarm: the lean dive takes the airframe from Arma's AI and gives it back. Same
// record as the 1.0.x dive (A3UE_FPV_nativeControl: identity, crew AI features, forced speed), so the
// controller's own stop path restores it too. Never while a player or Zeus flies the drone
// (canActuate): the tick retries the restore once control is released.
// [uav, identity, "TAKE" | "RESTORE"] -> Boolean (done)
params [["_uav", objNull], ["_identity", []], ["_action", ""]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if !([_uav, _identity] call A3UE_fnc_fpv_canActuate) exitWith {false};
private _native = _uav getVariable ["A3UE_FPV_nativeControl", []];
if (_action == "TAKE") exitWith {
	if (_native isEqualTo []) then {
		private _crew = (crew _uav) apply {[_x, _x checkAIFeature "PATH", _x checkAIFeature "FSM", _x checkAIFeature "AUTOCOMBAT"]};
		_uav setVariable ["A3UE_FPV_nativeControl", [+_identity, _crew, getForcedSpeed _uav]];
		{
			(_x # 0) disableAI "PATH";
			(_x # 0) disableAI "FSM";
			(_x # 0) disableAI "AUTOCOMBAT";
		} forEach _crew;
		_uav forceSpeed -1;
	};
	_uav setVariable ["A3UE_FPV_terminalSteeringActive", true, true];
	true
};
if (_action != "RESTORE") exitWith {false};
private _saved = count _native == 3 && {(_native # 0) isEqualTo _identity};
{
	private _unit = _x;
	if (!isNull _unit && {local _unit} && {alive _unit}) then {
		private _flags = if (_saved) then {((_native # 1) select {(_x # 0) isEqualTo _unit}) param [0, []]} else {[]};
		if (count _flags == 4) then {
			if (_flags # 1) then {_unit enableAI "PATH";} else {_unit disableAI "PATH";};
			if (_flags # 2) then {_unit enableAI "FSM";} else {_unit disableAI "FSM";};
			if (_flags # 3) then {_unit enableAI "AUTOCOMBAT";} else {_unit disableAI "AUTOCOMBAT";};
		} else {
			_unit enableAI "PATH";
			_unit enableAI "FSM";
			_unit enableAI "AUTOCOMBAT";
		};
	};
} forEach (crew _uav);
if (_saved) then {_uav forceSpeed (_native # 2);};
_uav setVariable ["A3UE_FPV_nativeControl", []];
_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];
true
