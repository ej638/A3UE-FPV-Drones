// Historical expression ONLY for an opt-in engine semantics probe; never called by runtime.
params ["_strike"];
private _snapshotValid = (values _strike) findIf {
	private _value = _x;
	if (_value isEqualType "") exitWith {count _value > 128};
	if (_value isEqualType 0) exitWith {!finite _value};
	if (_value isEqualType true) exitWith {false};
	if (_value isEqualType []) exitWith {
		count _value > 3 || {_value findIf {!(_x isEqualType 0) || {!finite _x}} >= 0}
	};
	true
} < 0;
_snapshotValid
