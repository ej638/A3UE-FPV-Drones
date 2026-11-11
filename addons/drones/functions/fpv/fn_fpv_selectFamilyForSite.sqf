params ["_markerX", "_locationType", ["_side", sideUnknown]];

_markerX;

private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
if (count _doctrine == 0) then {
	_doctrine = call A3UE_fnc_fpv_buildDoctrine;
};

private _profile = _doctrine getOrDefault [_locationType, createHashMap];
if (count _profile == 0) exitWith {""};

private _familyWeights = _profile getOrDefault ["familyWeights", createHashMap];
private _classPools = _profile getOrDefault ["classPools", createHashMap];
private _candidateSideKeys = switch (_side) do {
	case east: { ["east"] };
	case west: { ["west"] };
	case independent: { ["independent"] };
	default { ["east", "west", "independent"] };
};

private _weightedFamilies = [];
{
	private _familyId = _x;
	private _baseWeight = _familyWeights getOrDefault [_familyId, 0];

	if (_baseWeight > 0) then {
		private _hasClassPool = false;
		{
			private _sidePools = _classPools getOrDefault [_x, createHashMap];
			private _familyPools = _sidePools getOrDefault [_familyId, createHashMap];

			if (count _familyPools > 0) exitWith {
				_hasClassPool = true;
			};
		} forEach _candidateSideKeys;

		if (_hasClassPool) then {
			_weightedFamilies pushBack [_familyId, _baseWeight];
		};
	};
} forEach ["armafpv", "fpv_ua", "kvn"];

if (_weightedFamilies isEqualTo []) exitWith {""};

private _totalWeight = 0;
{
	_totalWeight = _totalWeight + ((_x param [1, 0]) max 0);
} forEach _weightedFamilies;

if (_totalWeight <= 0) exitWith {(_weightedFamilies select 0) param [0, ""]};

private _roll = random _totalWeight;
private _selectedFamilyId = "";
{
	_roll = _roll - ((_x param [1, 0]) max 0);
	if (_roll <= 0) exitWith {
		_selectedFamilyId = _x param [0, ""];
	};
} forEach _weightedFamilies;

if (_selectedFamilyId isEqualTo "") then {
	_selectedFamilyId = (_weightedFamilies select ((count _weightedFamilies) - 1)) param [0, ""];
};

_selectedFamilyId