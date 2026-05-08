class CfgPatches {
    class fpv_ai_drones {
        units[] = {};
        weapons[] = {};
        magazines[] = {};
        requiredVersion = 1.0;
        requiredAddons[] = {};
    };
};

class CfgFunctions {
    class A3UE {
        class FPV {
            file = "\fpv_ai_drones\functions\fpv";
            class addFPVEventListeners { postInit = 1; };
            class fpv_buildCompatCatalog {};
            class fpv_buildDoctrine {};
            class fpv_getProfile {};
            class fpv_profileValue {};
            class fpv_onLocationSpawned {};
            class fpv_onAIVehInit {};
            class fpv_selectFamilyForSite {};
            class fpv_selectClassForRole {};
            class fpv_managerEvaluateSite {};
            class fpv_managerSpawnDrone {};
            class fpv_cleanupDrone {};
            class fpv_unregisterDrone {};
            class fpv_refreshManagedDrones {};
            class fpv_debugSnapshot {};
            class fpv_applyCompatInit {};
            class fpv_bootstrapLocal {};
            class fpv_runController {};
            class fpv_cacheLinkState {};
            class fpv_isExternallyControlled {};
            class fpv_clearTarget {};
            class fpv_holdPattern {};
            class fpv_runLostTarget {};
            class fpv_isTargetObstructed {};
            class fpv_selectTarget {};
            class fpv_resolveTarget {};
            class fpv_computeIntercept {};
            class fpv_applyGuidance {};
            class fpv_shouldEnterTerminal {};
            class fpv_runTerminal {};
            class fpv_runTerminalVector {};
            class fpv_shouldDetonateNow {};
            class fpv_detonateCompat {};
            class fpv_evaluateLinkState {};
            class fpv_startFiberTrailCompat {};
            class fpv_updateFiberTrailCompat {};
        };
    };
};
