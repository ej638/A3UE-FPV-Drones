private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _doctrine = createHashMap;
private _familyIds = ["armafpv", "fpv_ua", "kvn"];
private _sideKeys = ["east", "west", "independent"];
private _fallbackFamilyMaxSpeeds = createHashMapFromArray [
	["armafpv", 190],
	["fpv_ua", 120],
	["kvn", 145]
];
private _trackingCapFactors = createHashMapFromArray [
	["armafpv", 0.84],
	["fpv_ua", 0.89],
	["kvn", 0.89]
];
private _terminalCapFactors = createHashMapFromArray [
	["armafpv", 0.96],
	["fpv_ua", 0.97],
	["kvn", 0.97]
];

private _buildWeightedRoleEntries = {
	params ["_familyId", "_siteType", "_roleId", "_classes"];

	private _entries = [];

	{
		private _className = _x;
		private _weight = 1;

		switch (_familyId) do {
			case "armafpv": {
				if (_roleId == "RECON") then {
					_weight = 3;
				} else {
					if (_siteType == "Airport" && {_className find "_TI" > -1}) then {
						_weight = _weight + 2;
					};

					if (_siteType == "Outpost" && {_roleId == "AP"} && {_className find "_TI" > -1}) then {
						_weight = _weight + 1;
					};

					if (_siteType == "Resource" && {_roleId == "AP"} && {_className find "_TI" > -1}) then {
						_weight = _weight + 1;
					};
				};
			};

			case "fpv_ua": {
				if (_roleId == "AT") then {
					_weight = 3;
				};

				if (_roleId == "AP") then {
					if (_className find "RKG" > -1) then {
						_weight = 3;
					};

					if (_className find "OG7V" > -1) then {
						_weight = 3;
					};

					if (_className find "IED" > -1) then {
						_weight = if (_siteType == "Resource") then {2} else {1};
					};
				};

				if (_roleId == "RECON") then {
					_weight = if (_className find "OG7V" > -1) then {3} else {2};
				};
			};

			case "kvn": {
				private _is20 = _className find "_20KM" > -1;
				private _is25 = _className find "_25KM" > -1;
				private _isTI = _className find "_TI" > -1;

				switch (_siteType) do {
					case "Airport": {
						if (_is25) then {
							_weight = _weight + 4;
						};

						if (_is20) then {
							_weight = _weight + 2;
						};

						if (_roleId == "RECON" && {_isTI}) then {
							_weight = _weight + 2;
						};
					};

					case "Outpost": {
						if (_is20) then {
							_weight = _weight + 4;
						};

						if (_is25) then {
							_weight = _weight + 1;
						};

						if (!_is20 && !_is25) then {
							_weight = _weight + 2;
						};

						if (_roleId == "RECON" && {_isTI}) then {
							_weight = _weight + 2;
						};
					};

					default {
						if (!_is20 && !_is25) then {
							_weight = _weight + 4;
						};

						if (_is20) then {
							_weight = _weight + 1;
						};

						if (_roleId == "RECON" && {_isTI}) then {
							_weight = _weight + 2;
						};
					};
				};
			};
		};

		if (_weight > 0) then {
			_entries pushBack [_className, _weight];
		};
	} forEach _classes;

	_entries
};

private _buildSiteClassPools = {
	params ["_siteType"];

	private _siteClassPools = createHashMap;

	{
		private _sideKey = _x;
		private _sidePools = createHashMap;

		{
			private _familyId = _x;
			private _familyData = _catalog getOrDefault [_familyId, createHashMap];

			if (count _familyData > 0) then {
				private _classesBySide = _familyData getOrDefault ["classesBySide", createHashMap];
				private _roleMap = _classesBySide getOrDefault [_sideKey, createHashMap];

				if (count _roleMap > 0) then {
					private _familyRolePools = createHashMap;

					{
						private _roleId = _x;
						private _classes = _roleMap getOrDefault [_roleId, []];
						private _entries = [_familyId, _siteType, _roleId, _classes] call _buildWeightedRoleEntries;

						if (_entries isNotEqualTo []) then {
							_familyRolePools set [_roleId, _entries];
						};
					} forEach ["AT", "AP", "RECON"];

					if (count _familyRolePools > 0) then {
						_sidePools set [_familyId, _familyRolePools];
					};
				};
			};
		} forEach _familyIds;

		if (count _sidePools > 0) then {
			_siteClassPools set [_sideKey, _sidePools];
		};
	} forEach _sideKeys;

	_siteClassPools
};

private _copyMap = {
	params [["_source", createHashMap]];

	private _copy = createHashMap;
	{
		_copy set [_x, _y];
	} forEach _source;

	_copy
};

private _mergeInto = {
	params ["_target", ["_source", createHashMap]];

	{
		_target set [_x, _y];
	} forEach _source;

	_target
};

private _resolveFamilyMaxSpeed = {
	params ["_familyId"];

	private _familyData = _catalog getOrDefault [_familyId, createHashMap];
	private _maxSpeed = 0;

	if (count _familyData > 0) then {
		private _classesBySide = _familyData getOrDefault ["classesBySide", createHashMap];

		{
			private _roleMap = _y;
			{
				private _classes = _y;
				{
					private _cfg = configFile >> "CfgVehicles" >> _x;
					if (isClass _cfg) then {
						_maxSpeed = _maxSpeed max getNumber (_cfg >> "maxSpeed");
					};
				} forEach _classes;
			} forEach _roleMap;
		} forEach _classesBySide;
	};

	if (_maxSpeed <= 0) then {
		_maxSpeed = _fallbackFamilyMaxSpeeds getOrDefault [_familyId, 100];
	};

	_maxSpeed
};

private _familyMaxSpeeds = createHashMap;
{
	_familyMaxSpeeds set [_x, [_x] call _resolveFamilyMaxSpeed];
} forEach _familyIds;

private _siteSearchProfiles = createHashMapFromArray [
	["Airport", createHashMapFromArray [
		["searchRadius", 900],
		["localSearchRadius", 320],
		["searchHeightAGL", 45]
	]],
	["Outpost", createHashMapFromArray [
		["searchRadius", 650],
		["localSearchRadius", 260],
		["searchHeightAGL", 35]
	]],
	["Resource", createHashMapFromArray [
		["searchRadius", 500],
		["localSearchRadius", 220],
		["searchHeightAGL", 25]
	]]
];

private _siteLostTargetProfiles = createHashMapFromArray [
	["Airport", createHashMapFromArray [
		["lostTargetRadius", 220],
		["lostTargetTTL", 5],
		["lostTargetConeHalfAngle", 35],
		["lostTargetClimbAGL", 18]
	]],
	["Outpost", createHashMapFromArray [
		["lostTargetRadius", 180],
		["lostTargetTTL", 4],
		["lostTargetConeHalfAngle", 30],
		["lostTargetClimbAGL", 14]
	]],
	["Resource", createHashMapFromArray [
		["lostTargetRadius", 140],
		["lostTargetTTL", 3],
		["lostTargetConeHalfAngle", 25],
		["lostTargetClimbAGL", 10]
	]]
];

private _siteTrackBreakOffsets = createHashMapFromArray [
	["Airport", 700],
	["Outpost", 550],
	["Resource", 450]
];

private _siteLeadDistanceCaps = createHashMapFromArray [
	["Airport", 650],
	["Outpost", 575],
	["Resource", 500]
];

private _siteLeadTimeOffsets = createHashMapFromArray [
	["Airport", 0.00],
	["Outpost", -0.20],
	["Resource", -0.35]
];

private _terminalSteeringDistances = createHashMapFromArray [
	["Airport", createHashMapFromArray [
		["armafpv", 92],
		["kvn", 88],
		["fpv_ua", 84]
	]],
	["Outpost", createHashMapFromArray [
		["armafpv", 84],
		["kvn", 80],
		["fpv_ua", 76]
	]],
	["Resource", createHashMapFromArray [
		["armafpv", 76],
		["kvn", 72],
		["fpv_ua", 68]
	]]
];

private _familyBehaviorDefaults = createHashMapFromArray [
	["armafpv", createHashMapFromArray [
		["maxLeadTimeNear", 0.20],
		["maxLeadTimeFar", 2.80],
		["nearLeadDistance", 60],
		["trackingMoveDelta", 8],
		["terminalMoveDelta", 4],
		["trackingHeightASL", 10],
		["attackHeightASL", 8],
		["terminalTurnBlend", 0.40],
		["terminalVerticalGain", 0.70]
	]],
	["kvn", createHashMapFromArray [
		["maxLeadTimeNear", 0.24],
		["maxLeadTimeFar", 2.50],
		["nearLeadDistance", 60],
		["trackingMoveDelta", 9],
		["terminalMoveDelta", 4],
		["trackingHeightASL", 9],
		["attackHeightASL", 8],
		["terminalTurnBlend", 0.35],
		["terminalVerticalGain", 0.65]
	]],
	["fpv_ua", createHashMapFromArray [
		["maxLeadTimeNear", 0.28],
		["maxLeadTimeFar", 2.25],
		["nearLeadDistance", 60],
		["trackingMoveDelta", 10],
		["terminalMoveDelta", 5],
		["trackingHeightASL", 8],
		["attackHeightASL", 8],
		["terminalTurnBlend", 0.32],
		["terminalVerticalGain", 0.60]
	]]
];

private _roleBehaviorDefaults = createHashMapFromArray [
	["AT", createHashMapFromArray [
		["targetStickyBonus", 1600],
		["targetStickyWindow", 4],
		["targetSwitchMargin", 900],
		["losBlockedPenalty", 2000],
		["obstructionPenaltyStep", 300],
		["detonationVerticalWindow", 12]
	]],
	["AP", createHashMapFromArray [
		["targetStickyBonus", 1800],
		["targetStickyWindow", 4],
		["targetSwitchMargin", 900],
		["losBlockedPenalty", 2200],
		["obstructionPenaltyStep", 350],
		["detonationVerticalWindow", 12]
	]],
	["RECON", createHashMapFromArray [
		["targetStickyBonus", 1700],
		["targetStickyWindow", 4],
		["targetSwitchMargin", 900],
		["losBlockedPenalty", 2200],
		["obstructionPenaltyStep", 350],
		["detonationVerticalWindow", 10]
	]]
];

private _behaviorAuthoring = createHashMapFromArray [
	["Airport", [
		["armafpv", [
			["AT", [["trackingSpeed", 150], ["terminalSpeed", 180], ["terminalGateDistance", 100], ["detonationDistance", 18]]],
			["AP", [["trackingSpeed", 160], ["terminalSpeed", 182], ["terminalGateDistance", 92], ["detonationDistance", 14]]],
			["RECON", [["trackingSpeed", 155], ["terminalSpeed", 175], ["terminalGateDistance", 96], ["detonationDistance", 13]]]
		]],
		["kvn", [
			["AT", [["trackingSpeed", 124], ["terminalSpeed", 138], ["terminalGateDistance", 96], ["detonationDistance", 17]]],
			["AP", [["trackingSpeed", 128], ["terminalSpeed", 140], ["terminalGateDistance", 88], ["detonationDistance", 13]]],
			["RECON", [["trackingSpeed", 126], ["terminalSpeed", 136], ["terminalGateDistance", 92], ["detonationDistance", 12]]]
		]],
		["fpv_ua", [
			["AT", [["trackingSpeed", 102], ["terminalSpeed", 114], ["terminalGateDistance", 92], ["detonationDistance", 16]]],
			["AP", [["trackingSpeed", 106], ["terminalSpeed", 116], ["terminalGateDistance", 84], ["detonationDistance", 12]]],
			["RECON", [["trackingSpeed", 104], ["terminalSpeed", 112], ["terminalGateDistance", 88], ["detonationDistance", 11]]]
		]]
	]],
	["Outpost", [
		["armafpv", [
			["AT", [["trackingSpeed", 145], ["terminalSpeed", 172], ["terminalGateDistance", 90], ["detonationDistance", 17]]],
			["AP", [["trackingSpeed", 155], ["terminalSpeed", 176], ["terminalGateDistance", 84], ["detonationDistance", 13]]],
			["RECON", [["trackingSpeed", 150], ["terminalSpeed", 168], ["terminalGateDistance", 88], ["detonationDistance", 12]]]
		]],
		["kvn", [
			["AT", [["trackingSpeed", 120], ["terminalSpeed", 134], ["terminalGateDistance", 86], ["detonationDistance", 16]]],
			["AP", [["trackingSpeed", 124], ["terminalSpeed", 138], ["terminalGateDistance", 80], ["detonationDistance", 12]]],
			["RECON", [["trackingSpeed", 122], ["terminalSpeed", 132], ["terminalGateDistance", 84], ["detonationDistance", 11]]]
		]],
		["fpv_ua", [
			["AT", [["trackingSpeed", 98], ["terminalSpeed", 110], ["terminalGateDistance", 82], ["detonationDistance", 15]]],
			["AP", [["trackingSpeed", 102], ["terminalSpeed", 114], ["terminalGateDistance", 76], ["detonationDistance", 11]]],
			["RECON", [["trackingSpeed", 100], ["terminalSpeed", 108], ["terminalGateDistance", 80], ["detonationDistance", 10]]]
		]]
	]],
	["Resource", [
		["armafpv", [
			["AT", [["trackingSpeed", 138], ["terminalSpeed", 165], ["terminalGateDistance", 82], ["detonationDistance", 16]]],
			["AP", [["trackingSpeed", 148], ["terminalSpeed", 170], ["terminalGateDistance", 76], ["detonationDistance", 12]]],
			["RECON", [["trackingSpeed", 143], ["terminalSpeed", 162], ["terminalGateDistance", 80], ["detonationDistance", 11]]]
		]],
		["kvn", [
			["AT", [["trackingSpeed", 114], ["terminalSpeed", 128], ["terminalGateDistance", 78], ["detonationDistance", 15]]],
			["AP", [["trackingSpeed", 118], ["terminalSpeed", 132], ["terminalGateDistance", 72], ["detonationDistance", 11]]],
			["RECON", [["trackingSpeed", 116], ["terminalSpeed", 126], ["terminalGateDistance", 76], ["detonationDistance", 10]]]
		]],
		["fpv_ua", [
			["AT", [["trackingSpeed", 94], ["terminalSpeed", 104], ["terminalGateDistance", 74], ["detonationDistance", 14]]],
			["AP", [["trackingSpeed", 98], ["terminalSpeed", 108], ["terminalGateDistance", 68], ["detonationDistance", 10]]],
			["RECON", [["trackingSpeed", 96], ["terminalSpeed", 102], ["terminalGateDistance", 72], ["detonationDistance", 9]]]
		]]
	]]
];

private _buildBehaviorProfile = {
	params ["_siteType", "_familyId", "_roleId", ["_authoredSpecs", []]];

	private _profile = createHashMapFromArray [
		["siteType", _siteType],
		["familyId", _familyId],
		["roleId", _roleId],
		["familyMaxSpeed", _familyMaxSpeeds getOrDefault [_familyId, 100]]
	];

	[_profile, [_siteSearchProfiles getOrDefault [_siteType, createHashMap]] call _copyMap] call _mergeInto;
	[_profile, [_siteLostTargetProfiles getOrDefault [_siteType, createHashMap]] call _copyMap] call _mergeInto;
	[_profile, [_familyBehaviorDefaults getOrDefault [_familyId, createHashMap]] call _copyMap] call _mergeInto;
	[_profile, [_roleBehaviorDefaults getOrDefault [_roleId, createHashMap]] call _copyMap] call _mergeInto;
	[_profile, createHashMapFromArray _authoredSpecs] call _mergeInto;

	private _familyMaxSpeed = _profile getOrDefault ["familyMaxSpeed", 100];
	private _trackingCap = round (_familyMaxSpeed * (_trackingCapFactors getOrDefault [_familyId, 0.84]));
	private _terminalCap = round (_familyMaxSpeed * (_terminalCapFactors getOrDefault [_familyId, 0.96]));
	private _trackingSpeed = (_profile getOrDefault ["trackingSpeed", 0]) min _trackingCap;
	private _terminalSpeed = (_profile getOrDefault ["terminalSpeed", 0]) min _terminalCap;
	private _terminalGateDistance = _profile getOrDefault ["terminalGateDistance", 90];
	private _detonationDistance = _profile getOrDefault ["detonationDistance", 14];
	private _leadNear = _profile getOrDefault ["maxLeadTimeNear", 0.25];
	private _leadFar = ((_profile getOrDefault ["maxLeadTimeFar", 2.4]) + (_siteLeadTimeOffsets getOrDefault [_siteType, 0])) max (_leadNear + 0.6);
	private _trackBreakDistance = _terminalGateDistance + (_siteTrackBreakOffsets getOrDefault [_siteType, 500]);
	private _steeringMap = _terminalSteeringDistances getOrDefault [_siteType, createHashMap];

	_profile set ["trackingSpeed", _trackingSpeed];
	_profile set ["terminalSpeed", _terminalSpeed];
	_profile set ["terminalGateDistance2D", round (_terminalGateDistance * 0.55)];
	_profile set ["detonationDistance2D", round (_detonationDistance * 0.50)];
	_profile set ["trackBreakDistance", _trackBreakDistance];
	_profile set ["dropTargetDistance", _trackBreakDistance + 150];
	_profile set ["terminalSteeringDistance", _steeringMap getOrDefault [_familyId, 72]];
	_profile set ["maxLeadTimeNear", _leadNear];
	_profile set ["maxLeadTimeFar", _leadFar];
	_profile set ["maxLeadDistance", _siteLeadDistanceCaps getOrDefault [_siteType, 550]];

	_profile
};

{
	_x params ["_siteType", "_spawnChance", "_stockRange", "_roleWeightSpecs", "_familyWeightSpecs"];

	private _familyWeights = createHashMap;
	{
		_x params ["_familyId", "_weight"];

		if (count (_catalog getOrDefault [_familyId, createHashMap]) > 0) then {
			_familyWeights set [_familyId, _weight];
		};
	} forEach _familyWeightSpecs;

	private _siteClassPools = [_siteType] call _buildSiteClassPools;
	private _roleWeights = createHashMapFromArray _roleWeightSpecs;
	private _behaviorProfiles = createHashMap;

	{
		_x params ["_familyId", ["_roleSpecs", []]];

		if (count (_catalog getOrDefault [_familyId, createHashMap]) > 0) then {
			private _familyProfileMap = createHashMap;
			{
				_x params ["_roleId", ["_authoredSpecs", []]];
				_familyProfileMap set [_roleId, [_siteType, _familyId, _roleId, _authoredSpecs] call _buildBehaviorProfile];
			} forEach _roleSpecs;

			if (count _familyProfileMap > 0) then {
				_behaviorProfiles set [_familyId, _familyProfileMap];
			};
		};
	} forEach (_behaviorAuthoring getOrDefault [_siteType, []]);

	private _siteBehavior = createHashMapFromArray [
		["search", [_siteSearchProfiles getOrDefault [_siteType, createHashMap]] call _copyMap],
		["lostTarget", [_siteLostTargetProfiles getOrDefault [_siteType, createHashMap]] call _copyMap],
		["profiles", _behaviorProfiles]
	];

	private _siteEntry = createHashMapFromArray [
		["profileId", format ["site_%1_default", toLower _siteType]],
		["spawnChance", _spawnChance],
		["stock", _stockRange],
		["roleWeights", _roleWeights],
		["familyWeights", _familyWeights],
		["classPools", _siteClassPools],
		["spawn", createHashMapFromArray [
			["spawnChance", _spawnChance],
			["stock", _stockRange],
			["roleWeights", _roleWeights],
			["familyWeights", _familyWeights],
			["classPools", _siteClassPools]
		]],
		["behavior", _siteBehavior]
	];

	_doctrine set [_siteType, _siteEntry];
} forEach [
	["Airport", 0.60, [2, 4], [["AT", 60], ["AP", 20], ["RECON", 20]], [["armafpv", 25], ["fpv_ua", 35], ["kvn", 40]]],
	["Outpost", 0.35, [1, 2], [["AT", 30], ["AP", 50], ["RECON", 20]], [["armafpv", 40], ["fpv_ua", 35], ["kvn", 25]]],
	["Resource", 0.25, [1, 1], [["AT", 15], ["AP", 45], ["RECON", 40]], [["armafpv", 35], ["fpv_ua", 35], ["kvn", 30]]]
];

missionNamespace setVariable ["A3UE_FPV_doctrine", _doctrine];

_doctrine