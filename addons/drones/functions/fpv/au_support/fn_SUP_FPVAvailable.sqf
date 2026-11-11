params ["_target", "_side", "_maxSpend", "_availTypes"];

_availTypes;

private _targetObject = objNull;
if (_target isEqualType objNull) then {
	_targetObject = _target;
};

if (isNull _targetObject) exitWith {0};
if (!alive _targetObject) exitWith {0};
if (_targetObject isKindOf "Air") exitWith {0};

private _targPos = getPosATL _targetObject;
private _contextMap = ["defence", createHashMap] call A3UE_fnc_fpv_getSupportContext;
private _query = [_side, _targetObject, _maxSpend, _contextMap, "defence", _targPos, true] call A3UE_fnc_fpv_resolveSupportPackage;

if !(_query getOrDefault ["ok", false]) exitWith {0};

_query getOrDefault ["selectorWeight", 0.35]
