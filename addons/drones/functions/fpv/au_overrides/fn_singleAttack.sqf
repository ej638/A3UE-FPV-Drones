
/*  Sends a combined attack force to capture the given marker

    Environment: Server or HC, scheduled

    Params:
        _mrkDest: MARKER : The target position where the attack will be send to
        _side: SIDE : The side to send the attack
        _vehCount: NUMBER : Number of vehicles to use in the attack
        _reveal: NUMBER : Amount of info to reveal to rebels, 0 low, 1 high

    Returns:
        Nothing
*/
#include "\x\A3A\addons\core\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_mrkDest", "_side", "_vehCount", "_reveal"];

// Validate before any scheduled fallback can discard remote provenance.
if (isRemoteExecutedJIP) exitWith {};
if (!isServer && {hasInterface}) exitWith {_this remoteExec ["A3A_fnc_singleAttack", 2];};
if (isServer && {!([true] call A3UE_fnc_fpv_isTrustedSupportCaller)}) exitWith {};
private _A3UE_FPV_contextAuthorized = true;
// AU's scheduler dispatches conventional work to HCs from the server.
if (!isServer && {isRemoteExecuted} && {remoteExecutedOwner != 2}) exitWith {};
if (!canSuspend) exitWith {_this spawn A3A_fnc_singleAttack;};
// AU-04: no eligible pack uses the loaded stock body, including its RNG/locality.
if (count (missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap]) == 0) exitWith {
    _this call (["singleAttack"] call A3UE_fnc_fpv_getStockAUFunction)
};
// FPV creation and its synchronous budget substitution retain AU's server lock.
if (!isServer) exitWith {_this remoteExec ["A3A_fnc_singleAttack", 2];};



if ((_side == Occupants && areOccupantsDefeated) || {(_side == Invaders && areInvadersDefeated)}) exitWith {
    ServerInfo_1("%1 faction was defeated earlier, aborting single attack.", str _side);
};

private _targPos = markerPos _mrkDest;

ServerInfo_1("Starting attack with parameters %1", _this);

private _airbase = [_side, markerPos _mrkDest] call A3A_fnc_availableBasesAir;

private _effectiveVehCount = _vehCount max 0;
private _fpvPreferredOrigin = "";

if (_airbase isEqualType "") then {
    private _airbaseLower = toLower _airbase;
    if ((markerShape _airbase) isNotEqualTo "" && {(_airbaseLower find "carrier") < 0}) then {
        _fpvPreferredOrigin = _airbase;
    };
};

// A3UE FPV integration: try a budget-neutral counterattack FPV support before the mixed force.
private _vehicleCostBaseline = missionNamespace getVariable ["A3A_balanceVehicleCost", 100];
if !(_vehicleCostBaseline isEqualType 0) then {
    _vehicleCostBaseline = 100;
};

private _maxFpReduction = 0;
private _minimumConventionalVehCount = 1;
private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
if (count _doctrine == 0) then {
    _doctrine = call A3UE_fnc_fpv_buildDoctrine;
};

private _counterSupportEntry = _doctrine getOrDefault ["CounterAttackSupport", createHashMap];
if (count _counterSupportEntry > 0) then {
    private _supportData = _counterSupportEntry getOrDefault ["support", createHashMap];
    private _roleWeights = _counterSupportEntry getOrDefault ["roleWeights", createHashMap];
    private _familyWeights = _counterSupportEntry getOrDefault ["familyWeights", createHashMap];
    private _vehicleResourceCosts = missionNamespace getVariable ["A3A_vehicleResourceCosts", createHashMap];
    private _costOverhead = _supportData getOrDefault ["costOverhead", 25];
    private _fallbackClassCosts = createHashMapFromArray [
        ["armafpv", 75],
        ["fpv_ua", 65],
        ["kvn", 95]
    ];
    private _maxFpCost = -1;

    if !(_vehicleResourceCosts isEqualType createHashMap) then {
        _vehicleResourceCosts = createHashMap;
    };

    {
        private _roleId = _x;
        if ((_roleWeights getOrDefault [_roleId, 0]) <= 0) then {
            continue;
        };

        {
            private _familyId = _x;
            if ((_familyWeights getOrDefault [_familyId, 0]) <= 0) then {
                continue;
            };

            private _uavClass = [_familyId, _roleId, _side, "CounterAttackSupport"] call A3UE_fnc_fpv_selectClassForRole;
            if (_uavClass isEqualTo "") then {
                continue;
            };

            private _uavCost = _vehicleResourceCosts getOrDefault [_uavClass, -1];
            if !(_uavCost isEqualType 0) then {
                _uavCost = -1;
            };
            if (_uavCost < 0) then {
                _uavCost = _fallbackClassCosts getOrDefault [_familyId, 80];
            };

            _maxFpCost = _maxFpCost max (_uavCost + _costOverhead);
        } forEach ["armafpv", "fpv_ua", "kvn"];
    } forEach ["AT", "AP", "RECON"];

    if (_maxFpCost > 0) then {
        _maxFpReduction = ceil (_maxFpCost / _vehicleCostBaseline);
    };
};

if (_maxFpReduction > 0 && {(_effectiveVehCount - _maxFpReduction) >= _minimumConventionalVehCount}) then {
    private _fpvContext = createHashMapFromArray [
        ["context", "CounterAttackSupport"],
        ["targetSide", sidesX getVariable [_mrkDest, sideEmpty]],
        ["resourcePool", "defence"]
    ];
    if (_fpvPreferredOrigin isNotEqualTo "") then {
        _fpvContext set ["originMarker", _fpvPreferredOrigin];
    };

    private _fpvMaxSpend = (_effectiveVehCount max 1) * _vehicleCostBaseline;
    private _fpvSupportName = [_fpvContext, {
        ["FPV", _side, "defence", _fpvMaxSpend, objNull, _targPos, 0, 0] call A3A_fnc_createSupport
    }] call A3UE_fnc_fpv_withSupportContext;

    if (_fpvSupportName isNotEqualTo "") then {
        private _supportRegistry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
        private _supportEntry = _supportRegistry getOrDefault [_fpvSupportName, createHashMap];
        private _fpvSupportCost = _supportEntry getOrDefault ["resourceCost", -1];

        if !(_fpvSupportCost isEqualType 0) then {
            _fpvSupportCost = -1;
        };

        private _vehReduction = if (_fpvSupportCost > 0) then {
            ceil (_fpvSupportCost / _vehicleCostBaseline)
        } else {
            _maxFpReduction max 1
        };

        _effectiveVehCount = 0 max (_effectiveVehCount - _vehReduction);
    } else {
        if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
            diag_log format [
                "[A3UE_FPV] singleAttack: FPV counterattack support not created for %1. PreferredOrigin=%2 AirbaseChoice=%3 Failure=%4",
                _mrkDest,
                _fpvPreferredOrigin,
                _airbase,
                missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", ""]
            ];
        };
    };
};

//params ["_side", "_airbase", "_target", "_resPool", "_vehCount", "_delay", "_modifiers", "_attackType", "_reveal"];
private _data = [_side, _airbase, _mrkDest, "defence", _effectiveVehCount, 0, [], "CounterAttack", _reveal] call A3A_fnc_createAttackForceMixed;
_data params ["", "_vehicles", "_crewGroups", "_cargoGroups"];

// Prepare despawn conditions
private _endTime = time + 2700;
private _victory = false;
private _soldiers = [];
{ _soldiers append units _x } forEach _cargoGroups;

while {true} do
{
    private _markerSide = sidesX getVariable _mrkDest;
    if(_markerSide == _side) exitWith {
        ServerInfo_1("Small attack to %1 captured the marker, starting despawn routines", _mrkDest);
        _victory = true;
    };

    private _curSoldiers = { !fleeing _x and _x call A3A_fnc_canFight } count _soldiers;
    if (_curSoldiers < count _soldiers * 0.25) exitWith {
        ServerInfo_1("Small attack to %1 has been defeated, starting despawn routines", _mrkDest);
    };
    if(_endTime < time) exitWith {
        ServerInfo_1("Small attack to %1 timed out, starting despawn routines", _mrkDest);
    };

    // Attempt to flip marker
    [_mrkDest, _markerSide] remoteExec ["A3A_fnc_zoneCheck", 2];
    sleep 30;
};

{ [_x] spawn A3A_fnc_VEHDespawner } forEach _vehicles;
{ [_x] spawn A3A_fnc_enemyReturnToBase } forEach _crewGroups;
{
    [_x, [nil, _mrkDest] select _victory] spawn A3A_fnc_enemyReturnToBase;
    sleep 10;
} forEach _cargoGroups;
