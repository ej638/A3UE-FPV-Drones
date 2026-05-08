if !(isClass (missionConfigFile / "A3A")) exitWith {};
if (missionNamespace getVariable ["A3UE_FPV_registrationComplete", false]) exitWith {};
if (isNil "A3A_Events_fnc_addEventListener") exitWith {
    if (missionNamespace getVariable ["A3UE_FPV_registrationPending", false]) exitWith {};

    missionNamespace setVariable ["A3UE_FPV_registrationPending", true];

    [] spawn {
        waitUntil {
            sleep 0.1;
            !isNil "A3A_Events_fnc_addEventListener"
        };

        missionNamespace setVariable ["A3UE_FPV_registrationPending", false];
        call A3UE_fnc_addFPVEventListeners;
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

if (isNil "A3UE_FPV_debug") then {
    missionNamespace setVariable ["A3UE_FPV_debug", false];
};

call A3UE_fnc_fpv_buildCompatCatalog;
call A3UE_fnc_fpv_buildDoctrine;

["locationSpawned", "A3UE_FPV_locationSpawned", A3UE_fnc_fpv_onLocationSpawned] call A3A_Events_fnc_addEventListener;
["AIVehInit", "A3UE_FPV_aivehInit", A3UE_fnc_fpv_onAIVehInit] call A3A_Events_fnc_addEventListener;

call A3UE_fnc_fpv_refreshManagedDrones;

missionNamespace setVariable ["A3UE_FPV_registrationComplete", true];
missionNamespace setVariable ["A3UE_FPV_registrationPending", false];