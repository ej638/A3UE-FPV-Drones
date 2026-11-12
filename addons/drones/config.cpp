class CfgPatches {
    class fpv_ai_drones {
        name = "[A3UE] AI FPV Drones";
        author = "EJ";
        url = "https://github.com/ej638/A3UE-FPV-Drones";
        units[] = {};
        weapons[] = {};
        magazines[] = {};
        requiredVersion = 2.14;
        requiredAddons[] = {"A3A_core", "A3_Weapons_F_Tank"};
        A3A_compatibility[] = {12, 4};
    };
};

class CfgAmmo {
    class M_Vorona_HEAT;
    class A3UE_FPV_AT: M_Vorona_HEAT {
        explosive = 0.8;
        hit = 150;
        htMax = 1800;
        htMin = 60;
        indirectHit = 25;
        indirectHitRange = 3.5;
        warheadName = "TandemHEAT";
        submunitionAmmo = "A3UE_FPV_AT_Penetrator";
        submunitionDirectionType = "SubmunitionModelDirection";
        submunitionInitSpeed = 1000;
        submunitionParentSpeedCoef = 0;
        submunitionInitialOffset[] = {0, 0, -0.1};
        submunitionConeType[] = {"random", 1};
        submunitionConeAngle = 0;
        submunitionConeAngleHorizontal = 0;
        triggerTime = -1;
        triggerDistance = -1;
        triggerOnImpact = 1;
        fuseDistance = 0;
        deleteParentWhenTriggered = 0;
        timeToLive = 5;
    };
    class ammo_Penetrator_Vorona;
    class A3UE_FPV_AT_Penetrator: ammo_Penetrator_Vorona {
        hit = 480;
        indirectHit = 0;
        indirectHitRange = 0;
        warheadName = "TandemHEAT";
        timeToLive = 1;
    };
};

class Extended_PreInit_EventHandlers {
    class A3UE_FPV_settings {
        init = "call compileScript ['\fpv_ai_drones\functions\fpv\fn_fpv_registerSettings.sqf']";
    };
};

class CfgFunctions {
    class A3UE {
        class FPV {
            file = "\fpv_ai_drones\functions\fpv";
            class addFPVEventListeners { postInit = 1; };
            class fpv_installOccupierInvaderSupportHooks {};
            class fpv_getStockAUFunction {};
            class fpv_reportAUAdapter {};
            class fpv_auReviewedVersion {};
            class fpv_setHookStatus {};
            class fpv_hookBindingMatches {};
            class fpv_bindingRepresentations {};
            class fpv_reportIntegrationHooks {};
            class fpv_buildCompatCatalog {};
            class fpv_getClassDescriptor {};
            class fpv_buildDoctrine {};
            class fpv_patchSupportRegistries {};
            class fpv_withSupportContext {};
            class fpv_getSupportContext {};
            class fpv_isTrustedSupportCaller {};
            class fpv_resolveSupportPackage {};
            class fpv_supportResolveOrigin {};
            class fpv_supportCheckReach {};
            class fpv_sampleRadioLink {};
            class fpv_supportPassesSafetyRing {};
            class fpv_supportEngagementReason {};
            class fpv_supportCreateMarker {};
            class fpv_supportFinalize {};
            class fpv_supportLaunch {};
            class fpv_supportShutdown {};
            class fpv_resolveSiteType {};
            class fpv_emptyImpactSolution {};
            class fpv_evaluateImpactWindow {};
            class fpv_getProfile {};
            class fpv_profileValue {};
            class fpv_onLocationSpawned {};
            class fpv_installSiteHooks {};
            class fpv_scheduleSite {};
            class fpv_runSiteWorker {};
            class fpv_receiveSiteIntent {};
            class fpv_processSiteQueue {};
            class fpv_siteQueueProbe {};
            class fpv_reconcileSites {};
            class fpv_onMarkerChange {};
            class fpv_isSiteDroneActive {};
            class fpv_onAIVehInit {};
            class fpv_selectFamilyForSite {};
            class fpv_selectClassForRole {};
            class fpv_managerEvaluateSite {};
            class fpv_managerSpawnDrone {};
            class fpv_managerDeployStock {};
            class fpv_siteStock {};
            class fpv_userSetting {};
            class fpv_registerSettings {};
            class fpv_supportAllowed {};
            class fpv_standoffThreats {};
            class fpv_launchStandoff {};
            class fpv_spawnManagedDrone {};
            class fpv_cleanupDrone {};
            class fpv_deleteLocal {};
            class fpv_unregisterDrone {};
            class fpv_refreshManagedDrones {};
            class fpv_debugSnapshot {};
            class fpv_applyCompatInit {};
            class fpv_applyTargetability {};
            class fpv_installTargetabilityAdapters {};
            class fpv_installCrocusSignalAdapter {};
            class fpv_getCrocusSignalContext {};
            class fpv_installUaPayloadAdapter {};
            class fpv_installKvnPathAdapter {};
            class fpv_installKvnArchiveAdapter {};
            class fpv_bootstrapLocal {};
            class fpv_runController {};
            class fpv_controllerSleep {};
            class fpv_controllerState {};
            class fpv_directorFrame {};
            class fpv_perfReport {};
            class fpv_wingSettings {};
            class fpv_attackSlot {};
            class fpv_attackRelease {};
            class fpv_attackCrowd {};
            class fpv_overwatch {};
            class fpv_overwatchPoint {};
            class fpv_scanTargets {};
            class fpv_publishTelemetry {};
            class fpv_helperAccess {};
            class fpv_canActuate {};
            class fpv_cacheLinkState {};
            class fpv_isExternallyControlled {};
            class fpv_clearTarget {};
            class fpv_holdPattern {};
            class fpv_runLostTarget {};
            class fpv_isTargetObstructed {};
            class fpv_isAlliedAttacker {};
            class fpv_traceAttackRay {};
            class fpv_selectTarget {};
            class fpv_resolveTarget {};
            class fpv_getHostileSides {};
            class fpv_filterTarget {};
            class fpv_resolveImpactPoint {};
            class fpv_computeIntercept {};
            class fpv_applyGuidance {};
            class fpv_shouldEnterTerminal {};
            class fpv_runTerminal {};
            class fpv_runTerminalVector {};
            class fpv_terminalSteeringStatus {};
            class fpv_stepTerminalSteering {};
            class fpv_terminalPresentationUp {};
            class fpv_trajectoryLimits {};
            class fpv_attackSettings {};
            class fpv_attackEngagement {};
            class fpv_attackApproach {};
            class fpv_attackPass {};
            class fpv_attackAimOffset {};
            class fpv_attackNavigation {};
            class fpv_attackPassSummary {};
            class fpv_attackReversal {};
            class fpv_attackLimits {};
            class fpv_obstacleProbe {};
            class fpv_transitHeight {};
            class fpv_attackClearLine {};
            class fpv_logDroneLoss {};
            class fpv_launchSlot {};
            class fpv_createUavCrew {};
            class fpv_sweepCrew {};
            class fpv_consumePool {};
            class fpv_targetNavigation {};
            class fpv_trajectorySteering {};
            class fpv_planTrajectory {};
            class fpv_followTrajectory {};
            class fpv_prepareTrajectory {};
            class fpv_shouldDetonateNow {};
            class fpv_detonateCompat {};
            class fpv_commitDetonation {};
            class fpv_lifecycleAccess {};
            class fpv_rejectLifecycle {};
            class fpv_validFiberPath {};
            class fpv_pruneLifecycle {};
            class fpv_registerLifecycle {};
            class fpv_claimLifecycle {};
            class fpv_acceptLifecycle {};
            class fpv_hasCurrentLifecycle {};
            class fpv_sendLifecycle {};
            class fpv_endLifecycle {};
            class fpv_reportLifecycle {};
            class fpv_adoptFiberPath {};
            class fpv_trackKvnLifecycle {};
            class fpv_archiveFiber {};
            class fpv_evaluateLinkState {};
            class fpv_startFiberTrailCompat {};
            class fpv_updateFiberTrailCompat {};
            class fpv_installRivalsHooks {};
            class fpv_rivalsEventAvailable {};
            class fpv_rivalsSelectAndExecuteEvent {};
            class fpv_rivalsUavFlyby {};
            class fpv_rivalsEventExecute {};
        };
    };

    class A3A {
        class A3UEFPVSupport {
            class SUP_FPV {
                file = "\fpv_ai_drones\functions\fpv\au_support\fn_SUP_FPV.sqf";
            };

            class SUP_FPVAvailable {
                file = "\fpv_ai_drones\functions\fpv\au_support\fn_SUP_FPVAvailable.sqf";
            };
        };

        class CREATE {
            class singleAttack {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_singleAttack.sqf";
            };

            class wavedAttack {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_wavedAttack.sqf";
            };

            class attackHQ {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_attackHQ.sqf";
            };

            class invaderPunish {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_invaderPunish.sqf";
            };
        };

        class Supports {
            class showInterceptedSetupCall {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_showInterceptedSetupCall.sqf";
            };

            class showInterceptedSupportCall {
                file = "\fpv_ai_drones\functions\fpv\au_overrides\fn_showInterceptedSupportCall.sqf";
            };
        };
    };
};
