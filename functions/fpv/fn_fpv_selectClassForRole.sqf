params ["_familyId", "_role", ["_side", sideUnknown], ["_locationType", ""]];

private _candidateSideKeys = switch (_side) do {
	case east: { ["east"] };
	case west: { ["west"] };
	case independent: { ["independent"] };
	default { ["east", "west", "independent"] };
};

private _pickWeightedClass = {
	params ["_entries"];

	if (_entries isEqualTo []) exitWith {""};

	private _totalWeight = 0;
	{
		_totalWeight = _totalWeight + ((_x param [1, 0]) max 0);
	} forEach _entries;

	if (_totalWeight <= 0) exitWith {(_entries select 0) param [0, ""]};

	private _roll = random _totalWeight;
	private _selectedClass = "";
	{
		_roll = _roll - ((_x param [1, 0]) max 0);
		if (_roll <= 0) exitWith {
			_selectedClass = _x param [0, ""];
		};
	} forEach _entries;

	if (_selectedClass isEqualTo "") then {
		_selectedClass = (_entries select ((count _entries) - 1)) param [0, ""];
	};

	_selectedClass
};

if (_locationType isNotEqualTo "") then {
	private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
	if (count _doctrine == 0) then {
		_doctrine = call A3UE_fnc_fpv_buildDoctrine;
	};

	private _profile = _doctrine getOrDefault [_locationType, createHashMap];
	if (count _profile > 0) then {
		private _classPools = _profile getOrDefault ["classPools", createHashMap];
		private _weightedClasses = [];

		{
			private _sidePools = _classPools getOrDefault [_x, createHashMap];
			private _familyPools = _sidePools getOrDefault [_familyId, createHashMap];
			private _roleEntries = _familyPools getOrDefault [_role, []];

			{
				_weightedClasses pushBack _x;
			} forEach _roleEntries;
		} forEach _candidateSideKeys;

		if (_weightedClasses isNotEqualTo []) exitWith {
			[_weightedClasses] call _pickWeightedClass
		};
	};
};

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _familyData = _catalog getOrDefault [_familyId, createHashMap];
if (count _familyData == 0) exitWith {""};

private _classesBySide = _familyData getOrDefault ["classesBySide", createHashMap];
private _fallbackClasses = [];

{
	private _roleMap = _classesBySide getOrDefault [_x, createHashMap];
	private _classes = _roleMap getOrDefault [_role, []];

	{
		_fallbackClasses pushBack [_x, 1];
	} forEach _classes;
} forEach _candidateSideKeys;

[_fallbackClasses] call _pickWeightedClass