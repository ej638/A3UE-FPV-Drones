params [["_uav", objNull]];

if (isNull _uav) exitWith {createHashMap};

private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
if (count _doctrine == 0) then {
	_doctrine = call A3UE_fnc_fpv_buildDoctrine;
};

private _mergeInto = {
	params ["_target", ["_source", createHashMap]];

	{
		_target set [_x, _y];
	} forEach _source;

	_target
};

private _resolveBehaviorProfile = {
	params ["_siteEntry", "_siteType", "_familyId", "_payloadRole"];

	if (count _siteEntry == 0) exitWith {createHashMap};

	private _behavior = _siteEntry getOrDefault ["behavior", createHashMap];
	if (count _behavior == 0) exitWith {createHashMap};

	private _resolved = createHashMap;
	[_resolved, _behavior getOrDefault ["search", createHashMap]] call _mergeInto;
	[_resolved, _behavior getOrDefault ["lostTarget", createHashMap]] call _mergeInto;

	if (_familyId isNotEqualTo "") then {
		private _familyProfiles = (_behavior getOrDefault ["profiles", createHashMap]) getOrDefault [_familyId, createHashMap];
		if (count _familyProfiles > 0 && {_payloadRole isNotEqualTo ""}) then {
			[_resolved, _familyProfiles getOrDefault [_payloadRole, createHashMap]] call _mergeInto;
		};
	};

	if (count _resolved > 0) then {
		_resolved set ["profileId", _siteEntry getOrDefault ["profileId", format ["site_%1_default", toLower _siteType]]];
		_resolved set ["siteType", _siteType];
		_resolved set ["familyId", _familyId];
		_resolved set ["roleId", _payloadRole];
	};

	_resolved
};

private _siteType = _uav getVariable ["A3UE_FPV_siteType", ""];
private _familyId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", ""];
if (_siteType isNotEqualTo "") then {
	private _siteProfile = _doctrine getOrDefault [_siteType, createHashMap];
	private _resolvedSiteProfile = [_siteProfile, _siteType, _familyId, _payloadRole] call _resolveBehaviorProfile;
	if (count _resolvedSiteProfile > 0) exitWith {_resolvedSiteProfile};
	if (count _siteProfile > 0) exitWith {_siteProfile};
};

private _profileId = _uav getVariable ["A3UE_FPV_profileId", ""];
if (_profileId isEqualTo "") exitWith {createHashMap};

private _profile = createHashMap;
{
	private _candidate = _doctrine getOrDefault [_x, createHashMap];
	if ((_candidate getOrDefault ["profileId", ""]) isEqualTo _profileId) exitWith {
		private _resolvedProfile = [_candidate, _x, _familyId, _payloadRole] call _resolveBehaviorProfile;
		_profile = if (count _resolvedProfile > 0) then {
			_resolvedProfile
		} else {
			_candidate
		};
	};
} forEach ["Airport", "Outpost", "Resource"];

_profile