if !(isClass (missionConfigFile / "A3A")) exitWith {};
// Functions Library supplies ["postInit", didJIP]; helpers have separate contracts.
if (isNil "A3UE_FPV_auAdapterReport") then {[true] call A3UE_fnc_fpv_reportAUAdapter;};
[] call A3UE_fnc_fpv_installTargetabilityAdapters;
[] call A3UE_fnc_fpv_installCrocusSignalAdapter;
[] call A3UE_fnc_fpv_installUaPayloadAdapter;
[] call A3UE_fnc_fpv_installKvnPathAdapter;
[] call A3UE_fnc_fpv_installKvnArchiveAdapter;
// One transient epoch per mission/campaign load, independent of process uptime.
// AU loads campaigns through mission startup; repeated registration is a repair.
if (isServer && {!isRemoteExecuted} && {isNil "A3UE_FPV_siteEpoch"}) then {
    missionNamespace setVariable ["A3UE_FPV_siteEpoch", format ["%1:%2:%3", worldName, clientOwner, diag_tickTime]];
    missionNamespace setVariable ["A3UE_FPV_siteLifecycle", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_siteTracked", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_siteQueue", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_registry", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_siteReady", false];
    private _staleSupportMarkers = missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []];
    if !(_staleSupportMarkers isEqualType []) then {
        _staleSupportMarkers = [];
    };

    private _persistedSupportRegistry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
    if (_persistedSupportRegistry isEqualType createHashMap) then {
        {
            private _searchMarker = _y getOrDefault ["searchMarker", ""];
            if (_searchMarker isEqualType "" && {_searchMarker isNotEqualTo ""}) then {
                _staleSupportMarkers pushBackUnique _searchMarker;
            };
        } forEach _persistedSupportRegistry;
    };

    {
        if (_x isEqualType "" && {_x isNotEqualTo ""} && {(markerShape _x) isNotEqualTo ""}) then {
            deleteMarker _x;
        };
    } forEach _staleSupportMarkers;

    missionNamespace setVariable ["A3UE_FPV_supportTransientMarkers", []];
    missionNamespace setVariable ["A3UE_FPV_supportRegistry", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", ""];
    missionNamespace setVariable ["A3UE_FPV_lastSupportPlan", createHashMap];
    missionNamespace setVariable ["A3UE_FPV_lastSupportContext", createHashMap];
};

// Capture scheduler identities before waiting for event registration/readiness.
if (isServer && {!isRemoteExecuted}) then {[] call A3UE_fnc_fpv_installSiteHooks;};

if (missionNamespace getVariable ["A3UE_FPV_registrationComplete", false]) exitWith {
    if (isServer) then {
        [] call A3UE_fnc_fpv_installSiteHooks;
        ["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
        [] call A3UE_fnc_fpv_installOccupierInvaderSupportHooks;
    };
};
// AU 12.4+ raises CBA events through A3A_fnc_addEventHandler and keeps the old
// A3A_Events listener API only as a deprecated shim; earlier AU has only the old API.
if (isNil "A3A_fnc_addEventHandler" && {isNil "A3A_Events_fnc_addEventListener"}) exitWith {
    if (missionNamespace getVariable ["A3UE_FPV_registrationPending", false]) exitWith {};

    missionNamespace setVariable ["A3UE_FPV_registrationPending", true];

    [] spawn {
        waitUntil {
            sleep 0.1;
            !isNil "A3A_fnc_addEventHandler" || {!isNil "A3A_Events_fnc_addEventListener"}
        };

        missionNamespace setVariable ["A3UE_FPV_registrationPending", false];
        [] call A3UE_fnc_addFPVEventListeners;
    };
};

if (isNil "A3UE_FPV_loadedMods") then {
    missionNamespace setVariable ["A3UE_FPV_loadedMods", createHashMap];
};

if (isNil "A3UE_FPV_catalog") then {
    missionNamespace setVariable ["A3UE_FPV_catalog", createHashMap];
};

if (isNil "A3UE_FPV_doctrine") then {
    missionNamespace setVariable ["A3UE_FPV_doctrine", createHashMap];
};

if (isNil "A3UE_FPV_registry") then {
    missionNamespace setVariable ["A3UE_FPV_registry", createHashMap];
};

if (isNil "A3UE_FPV_supportRegistry") then {
    missionNamespace setVariable ["A3UE_FPV_supportRegistry", createHashMap];
};

if (isNil "A3UE_FPV_supportTransientMarkers") then {
	missionNamespace setVariable ["A3UE_FPV_supportTransientMarkers", []];
};

if (isNil "A3UE_FPV_debug") then {
    missionNamespace setVariable ["A3UE_FPV_debug", false];
};

if (isNil "A3UE_FPV_supportHooksInstalled") then {
    missionNamespace setVariable ["A3UE_FPV_supportHooksInstalled", false];
};

if (isNil "A3UE_FPV_supportRegistryPatched") then {
    missionNamespace setVariable ["A3UE_FPV_supportRegistryPatched", false];
};

if (isNil "A3UE_FPV_supportInstallFailedReason") then {
    missionNamespace setVariable ["A3UE_FPV_supportInstallFailedReason", ""];
};

if (isNil "A3UE_FPV_supportPatchPending") then {
    missionNamespace setVariable ["A3UE_FPV_supportPatchPending", false];
};

if (isNil "A3UE_FPV_occSupportPatchEligible") then {
    missionNamespace setVariable ["A3UE_FPV_occSupportPatchEligible", false];
};

if (isNil "A3UE_FPV_invSupportPatchEligible") then {
    missionNamespace setVariable ["A3UE_FPV_invSupportPatchEligible", false];
};

if (isNil "A3UE_FPV_occSupportRegistryPatched") then {
    missionNamespace setVariable ["A3UE_FPV_occSupportRegistryPatched", false];
};

if (isNil "A3UE_FPV_invSupportRegistryPatched") then {
    missionNamespace setVariable ["A3UE_FPV_invSupportRegistryPatched", false];
};

[] call A3UE_fnc_fpv_buildCompatCatalog;
[] call A3UE_fnc_fpv_buildDoctrine;

// Per event: AU 12.4+ maps each legacy event to the CBA event it now raises
// (configFile >> "A3A" >> "Events" >> <event> >> "CBA_Event"). AU 12.0-12.3 already has
// A3A_fnc_addEventHandler but still raises these three through the legacy registry, so the
// wrapper alone is not a route signal. With neither mapping nor legacy API left, use the
// built-in CBA name. AU raises all three synchronously on the server (CBA local/server
// event = call), so onLocationSpawned still sees the site worker's private context.
// CBA has no listener ids, so each id subscribes once.
private _eventIds = missionNamespace getVariable ["A3UE_FPV_auEventIds", createHashMap];
private _subscribed = [];
private _routes = [];
{
    _x params ["_legacyEvent", "_cbaEvent", "_listenerId", "_handler", "_wanted"];
    if (_wanted) then {
        private _mapped = getText (configFile >> "A3A" >> "Events" >> _legacyEvent >> "CBA_Event");
        private _useCba = _mapped != "" || {isNil "A3A_Events_fnc_addEventListener" && {!isNil "A3A_fnc_addEventHandler"}};
        if (_useCba) then {
            if (_mapped != "") then {_cbaEvent = _mapped;};
            if !(_listenerId in _eventIds) then {
                _eventIds set [_listenerId, [_cbaEvent, [_cbaEvent, _handler] call A3A_fnc_addEventHandler]];
            };
            _subscribed pushBack _cbaEvent;
            _routes pushBackUnique "CBA";
        } else {
            [_legacyEvent, _listenerId, _handler] call A3A_Events_fnc_addEventListener;
            _subscribed pushBack _legacyEvent;
            _routes pushBackUnique "LEGACY";
        };
    };
} forEach [
    ["locationSpawned", "A3A_event_serverSpawnLocation", "A3UE_FPV_locationSpawned", A3UE_fnc_fpv_onLocationSpawned, true],
    ["AIVehInit", "A3A_event_serverInitAiVehicle", "A3UE_FPV_aivehInit", A3UE_fnc_fpv_onAIVehInit, true],
    ["markerChange", "A3A_event_serverMarkerChange", "A3UE_FPV_markerChange", A3UE_fnc_fpv_onMarkerChange, isServer]
];
private _route = if (count _routes == 1) then {_routes # 0} else {"MIXED"};
missionNamespace setVariable ["A3UE_FPV_auEventIds", _eventIds];
missionNamespace setVariable ["A3UE_FPV_auEventRoute", _route];
diag_log format ["[A3UE_FPV] auEvents route=%1 events=%2", _route, _subscribed];

[] call A3UE_fnc_fpv_refreshManagedDrones;

missionNamespace setVariable ["A3UE_FPV_registrationComplete", true];
missionNamespace setVariable ["A3UE_FPV_registrationPending", false];

if (isServer) then {
	[] call A3UE_fnc_fpv_installSiteHooks;
	["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
    [] call A3UE_fnc_fpv_installOccupierInvaderSupportHooks;
};
