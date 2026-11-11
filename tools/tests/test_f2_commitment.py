"""Executed F2 correction contracts; VM engine substitutions are explicit in harness."""
import unittest,subprocess
from pathlib import Path
from f2_commitment_vm import VM,FPV,ROOT,execute,engine_substitutes,adapt_helper

@unittest.skipUnless(VM and Path(VM).is_file(),'FPV_SQFVM offline interpreter not configured')
class CommitmentSQF(unittest.TestCase):
    def original(self,name):
        return subprocess.check_output(['git','show','caf6f8c0e53025305e04483ce3a93ae6ca403894:addons/drones/functions/fpv/fn_fpv_'+name+'.sqf'],cwd=ROOT,text=True)

    def test_object_terrain_and_clearance_negative_controls_and_continuing_writer(self):
        baseline=self.original('runController')
        abort=baseline.split('private _abortTrajectory = ',1)[1].split('private _attemptIngress',1)[0]
        extra='FPV_originalPrepare={'+adapt_helper('prepareTrajectory',self.original('prepareTrajectory'))+'};\n'
        extra+='private _restoreTerminalVectorControl={true};private _setSafetyReason={};private _abortTrajectory='+engine_substitutes(abort)
        self.sqf('''
{FPV_collision=_x;
 _uav setVariable ["A3UE_FPV_terminalImpactMode","DIRECT_HULL"];
 _uav setVariable ["A3UE_FPV_lastImpactValid",true];_uav setVariable ["A3UE_FPV_lastImpactTargetNetId","target"];
 _uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];_uav setVariable ["A3UE_FPV_lastImpactPointASL",[250,0,2.4]];
 _uav setVariable ["A3UE_FPV_lastImpactSurfaceType","vehicle"];_uav setVariable ["A3UE_FPV_impactAnchorObject",_target];
 _uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];_uav setVariable ["A3UE_FPV_trajectory",[]];
 private _old=[_uav,_target,_profile,1,_identity] call FPV_originalPrepare;
 [(_old # 1)=="CORRIDOR_BLOCKED",_x+" negative plan"] call _assert;
 [_target,"TERMINAL_VECTOR",_old # 2,_old # 1,_old # 3,_old # 4] call _abortTrajectory;
 [_uav getVariable ["A3UE_FPV_engagementAborted",false],_x+" original permanent abort"] call _assert;
 _uav setVariable ["A3UE_FPV_engagementAborted",false];_uav setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];
 _uav setVariable ["A3UE_FPV_targetNetId","target"];_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt",FPV_time];
 _uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];FPV_queries=0;
 private _new=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
 [_new # 0==1,_x+" committed plan"] call _assert;
 private _n=count FPV_moves;
 {FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
  [[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"continuing writer"] call _assert;
 } forEach [0,1];
 [count FPV_moves==_n+1 && {FPV_queries==0},"continuation without corridor probes"] call _assert;
 [_uav getVariable ["A3UE_FPV_targetNetId",""]=="target" && {!(_uav getVariable ["A3UE_FPV_engagementAborted",false])}
  && {_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==-1},"lock no abort or timer"] call _assert;
} forEach ["OBJECT","TERRAIN","CLEARANCE"];
''',extra)

    def test_clear_feasible_plan_and_commands_equal_original_f2(self):
        extra='FPV_originalPrepare={'+adapt_helper('prepareTrajectory',self.original('prepareTrajectory'))+'};\n'
        extra+='FPV_originalWriter={'+adapt_helper('runTerminalVector',self.original('runTerminalVector'))+'};\n'
        self.sqf('''
_uav setVariable ["A3UE_FPV_terminalImpactMode","DIRECT_HULL"];
_uav setVariable ["A3UE_FPV_lastImpactValid",true];_uav setVariable ["A3UE_FPV_lastImpactTargetNetId","target"];
_uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];_uav setVariable ["A3UE_FPV_lastImpactPointASL",[250,0,2.4]];
_uav setVariable ["A3UE_FPV_lastImpactSurfaceType","vehicle"];_uav setVariable ["A3UE_FPV_impactAnchorObject",_target];
private _old=[_uav,_target,_profile,1,_identity] call FPV_originalPrepare;
{FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
 [[_uav,_target,_profile,1,_identity] call FPV_originalWriter,"original writes"] call _assert;
} forEach [0,1,2,3];
private _oldMoves=+FPV_moves;FPV_moves=[];
FPV_time=10;FPV_observed=20;
_uav setVariable ["A3UE_FPV_trajectory",[]];_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
_uav setVariable ["A3UE_FPV_terminalSteeringState",[]];_uav setVariable ["A3UE_FPV_terminalPoseContext",[]];
private _new=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
[(_old # 2 # 6) isEqualTo (_new # 2 # 6),"exact feasible path"] call _assert;
{FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
 [[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"current writes"] call _assert;
} forEach [0,1,2,3];
[FPV_moves isEqualTo _oldMoves,"exact feasible commanded motion"] call _assert;
''',extra)
    def sqf(self,body,extra=None):
        r=execute(body,extra)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn('COMMITMENT_TEST_OK',r.stdout,r.stdout+r.stderr)
        self.assertNotIn('[ERR]',r.stdout,r.stdout)
        return r.stdout

    def test_feasible_plan_and_two_writer_steps(self):
        self.sqf('''
private _p=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
[_p # 0 == 1,"feasible"] call _assert;
{FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;FPV_frame=FPV_frame+1;
 [[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"writer admitted"] call _assert;
} forEach [0,1,2];
[count FPV_moves==2,"first zero dt then movement"] call _assert;
''')

    def test_navigation_identity_survives_payload_surface_changes(self):
        self.sqf('''
private _keys=[];private _references=[];
{_uav setVariable ["A3UE_FPV_terminalImpactMode",_x];
 _uav setVariable ["A3UE_FPV_lastImpactValid",true];
 _uav setVariable ["A3UE_FPV_lastImpactTargetNetId","target"];
 _uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];
 _uav setVariable ["A3UE_FPV_lastImpactPointASL",[40,0,0]];
 private _n=[_uav,_target,_identity] call A3UE_fnc_fpv_targetNavigation;
 _keys pushBack (_n # 0);_references pushBack (_n # 5);
 if (_x!="DIRECT_HULL") then {[(_n # 3) isEqualTo (_n # 5),"obstruction excluded"] call _assert;};
 [_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
 FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;FPV_frame=FPV_frame+1;
} forEach ["DIRECT_HULL","OBSTRUCTION_SURFACE","GROUND_NEAR_TARGET","NONE"];
[{_x isEqualTo (_keys # 0)} count _keys==4,"stable steering identity"] call _assert;
[{_x isEqualTo (_references # 0)} count _references==4,"stable missed-pass reference"] call _assert;
[_uav getVariable ["A3UE_FPV_terminalSteeringSerial",0]==1,"no surface reconstruction"] call _assert;
[_uav getVariable ["A3UE_FPV_terminalVectorEnteredAt",-1]==9,"pass age"] call _assert;
[count FPV_moves==3,"continuous writer"] call _assert;
''')

    def test_curve_refusals_deferral_and_cross_track_continue(self):
        self.sqf('''
{_x params ["_reason","_direction","_speed","_position"];
 _uav setVariable ["direction",_direction];_uav setVariable ["velocity",_direction vectorMultiply _speed];
 _uav setVariable ["position",_position];_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
 _uav setVariable ["A3UE_FPV_terminalSteeringState",[]];_uav setVariable ["A3UE_FPV_trajectory",[]];
 private _p=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
 [(_p # 1)==_reason,"expected mathematical refusal"] call _assert;
 private _deferred=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
 [_deferred # 0 == 0,"plan due"] call _assert;
 private _before=count FPV_moves;
 {FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
  [[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"fallback writer"] call _assert;
 } forEach [0,1,2];
 [count FPV_moves==_before+2,"continuation updates"] call _assert;
 [!(_uav getVariable ["A3UE_FPV_engagementAborted",false]),"no abort"] call _assert;
} forEach [["SETUP_HEADING",[-1,0,0],20,[0,0,50]],
 ["ENTRY_SPEED",[0,0,-1],40,[250,0,100]],
 ["AT_SURFACE",[1,0,0],10,[250,0,2.4]],
 ["CURVATURE_OR_DESCENT",[1,0,0],20,[248,-5,2.4]]];
_uav setVariable ["position",[0,0,50]];_uav setVariable ["velocity",[10,0,0]];
_uav setVariable ["A3UE_FPV_terminalSteeringState",[]];_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
private _p=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
[_p # 0==1,"cross-track seed"] call _assert;
_uav setVariable ["position",[0,20,50]];
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"cross-track fallback"] call _assert;
[_uav getVariable ["A3UE_FPV_navigationContinuation",false],"cross-track disposition"] call _assert;
''')

    def test_stale_target_authority_control_and_link_never_write(self):
        self.sqf('''
{_x params ["_key","_bad","_good"];
 _uav setVariable [_key,_bad];
 [!([_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector),_key] call _assert;
 _uav setVariable [_key,_good];
} forEach [["controlled",true,false],["local",false,true],["siteActive",false,true],
 ["lifecycle",false,true],["A3UE_FPV_targetNetId","replacement","target"],
 ["A3UE_FPV_controllerGeneration",2,1],["A3UE_FPV_detonating",true,false],
 ["A3UE_FPV_linkState","EW_DENIED","OK"]];
[FPV_moves isEqualTo [],"zero obsolete effects"] call _assert;
''')

    def test_actual_filter_occupancy_and_canonical_normalization(self):
        self.sqf('''
private _other=["VMMan","other"] call _make;_other setVariable ["side",west];
_target setVariable ["crew",[_person,_other]];
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target,"occupied"] call _assert;
_target setVariable ["crew",[_other]];_target setVariable ["commander",objNull];
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target,"one remaining living crew"] call _assert;
_other setVariable ["alive",false];
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"dead-only"] call _assert;
_other setVariable ["alive",true];_other setVariable ["captive",true];
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"captive"] call _assert;
_other setVariable ["captive",false];_other setVariable ["side",east];
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"friendly takeover"] call _assert;
_target setVariable ["crew",[]];
[isNull ([_uav] call A3UE_fnc_fpv_resolveTarget),"empty"] call _assert;
_target setVariable ["crew",[_person]];_person setVariable ["parent",_target];
_uav setVariable ["A3UE_FPV_targetNetId","person"];
[([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target,"boarding normalization"] call _assert;
[([_uav,_person,_identity] call A3UE_fnc_fpv_targetNavigation) isEqualTo [],"old man intent denied"] call _assert;
''')

    def test_empty_target_refuses_actuator_and_owner_proposal(self):
        self.sqf('''
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
[!([_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector),"empty movement"] call _assert;
[!([_uav,_target,"PREDICTED_IMPACT","NONE"] call A3UE_fnc_fpv_detonateCompat),"empty proposal"] call _assert;
[FPV_moves isEqualTo [] && {FPV_sent==0},"no effects"] call _assert;
''')

    def test_server_delayed_empty_and_old_target_proposals_do_not_spend_or_disable(self):
        self.sqf('''
private _record=createHashMapFromArray [["phase","live"],["object",_uav],["owner",2],["support",""]];
missionNamespace setVariable ["A3UE_FPV_lifecycles",createHashMapFromArray [["1",_record]]];
private _strike=createHashMapFromArray [["uavNetId","uav"],["targetNetId","target"],["targetRevision",0],
 ["deliveryPosASL",[250,0,2]],["deliveryDir",[1,0,0]],["deliveryUp",[0,0,1]],
 ["detonationReason","PREDICTED_IMPACT"],["fallbackReason","NONE"]];
[_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation;
[FPV_creates==1,"legal ambient reaches payload creation boundary"] call _assert;FPV_creates=0;
 _target setVariable ["crew",[]];_target setVariable ["commander",objNull];
[!([_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation),"queued empty"] call _assert;
_uav setVariable ["A3UE_FPV_targetNetId","person"];
_target setVariable ["crew",[_person]];
[!([_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation),"queued replaced"] call _assert;
[FPV_creates==0 && {!(_uav getVariable ["A3UE_FPV_detonating",false])},"not spent"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="TERMINAL_VECTOR","replacement not disabled"] call _assert;
[_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==-1,"no collateral timer"] call _assert;
[_uav] call A3UE_fnc_fpv_clearTarget;_uav setVariable ["A3UE_FPV_targetNetId","target"];
[!([_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation),"old A after A B A"] call _assert;
[FPV_creates==0,"revision rejects old A"] call _assert;
[!([_uav,_target,"PREDICTED_IMPACT","NONE",0] call A3UE_fnc_fpv_detonateCompat),"owner stale evaluated fuse"] call _assert;
[FPV_sent==0,"no stale owner proposal"] call _assert;
''')

    def test_populated_membership_caches_filter_empty_vehicle_live(self):
        self.sqf('''
_uav setVariable ["A3UE_FPV_targetNetId",""];
_uav setVariable ["A3UE_FPV_siteCandidateCache",[100,[0,0,50],350,[_target,_person]]];
_uav setVariable ["A3UE_FPV_localCandidateCache",[100,[0,0,50],250,[_target,_person]]];
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
[([_uav,_profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _person,"live filtered cache replacement"] call _assert;
''')

    def test_scheduled_planning_changes_cannot_commit_obsolete_plan(self):
        self.sqf('''
private _originalPlan=A3UE_fnc_fpv_planTrajectory;
{_x params ["_mutationName","_bad","_good"];
 _uav setVariable ["A3UE_FPV_trajectory",[]];_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
 A3UE_fnc_fpv_planTrajectory={private _p=_this call _originalPlan;_uav setVariable [_mutationName,_bad];_p};
 private _p=[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
 [_p # 0 == -2,"stale planning refuses"] call _assert;
 [(_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo [],"obsolete plan not stored"] call _assert;
 _uav setVariable [_mutationName,_good];
} forEach [["A3UE_FPV_targetNetId","person","target"],["A3UE_FPV_siteEpoch","new",""],
 ["A3UE_FPV_targetRevision",1,0],["A3UE_FPV_controllerGeneration",2,1],["controlled",true,false]];
''')

    def test_controller_ingress_continuation_and_atomic_target_replacement(self):
        source=(FPV/'fn_fpv_runController.sqf').read_text()
        def closure(name,next_name):
            return source.split('private '+name+' = ',1)[1].split('private '+next_name,1)[0]
        extra='private _nextGuidanceTick=100;private _nextTargetScanTick=100;private _mode="TERMINAL_VECTOR";private _now=10;private _terminalAIRecoveryPending=false;private _impactCacheReady=true;\n'
        extra+='private _clearTerminalPoseContext={_uav setVariable ["A3UE_FPV_terminalSteeringState",[]];};private _refreshTrajectoryImpact={};\n'
        restore=closure('_restoreTerminalVectorControl','_impactSolutionFromCache').replace('_uav forceSpeed (_native # 2);','FPV_hold=FPV_hold+1;')
        extra+='private _restoreTerminalVectorControl='+engine_substitutes(restore)+'\n'
        extra+='private _revalidateTarget='+engine_substitutes(closure('_revalidateTarget','_adoptTarget'))+'\n'
        extra+='private _adoptTarget='+engine_substitutes(closure('_adoptTarget','_loseTarget'))+'\n'
        extra+='private _attemptIngress='+engine_substitutes(closure('_attemptIngress','_restoreInvalidNavigation'))+'\n'
        self.sqf('''
_uav setVariable ["A3UE_FPV_mode","TRACKING"];
_uav setVariable ["velocity",[-30,0,0]];
[[_target] call _attemptIngress,"infeasible entry continues"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="TERMINAL_VECTOR","managed mode"] call _assert;
[FPV_moves isEqualTo [],"managed entry zero dt"] call _assert;
FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"post entry writer"] call _assert;
_target setVariable ["crew",[]];_target setVariable ["commander",objNull];
call _revalidateTarget;
[_uav getVariable ["A3UE_FPV_mode",""]=="SEARCHING","invalid goes directly to ordinary search"] call _assert;
[_nextTargetScanTick==FPV_time,"prompt selector"] call _assert;
[(_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo [] && {(_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]) isEqualTo []},"old intent revoked"] call _assert;
[[_person,"SEARCHING"] call _adoptTarget,"ordinary replacement"] call _assert;
_target setVariable ["crew",[_person]];_person setVariable ["parent",_target];
call _revalidateTarget;
[_uav getVariable ["A3UE_FPV_targetNetId",""]=="target","canonical vehicle adopted"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="TRACKING" && {_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==-1},"normalization no safety episode"] call _assert;
''',extra)

    def test_support_visibility_declines_payload_only_and_real_collateral_holds(self):
        actual='A3UE_fnc_fpv_supportEngagementReason={'+engine_substitutes((FPV/'fn_fpv_supportEngagementReason.sqf').read_text())+'};'
        self.sqf('''
_uav setVariable ["A3UE_FPV_supportSafetyRadius",40];FPV_blocked=true;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"occluded navigation"] call _assert;
[!([_uav,_target,"PREDICTED_IMPACT","NONE"] call A3UE_fnc_fpv_detonateCompat),"occluded payload refused"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="TERMINAL_VECTOR","visibility retains movement mode"] call _assert;
[_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==-1,"visibility no timer"] call _assert;
FPV_deliverySafe=false;
[!([_uav,_target,"PREDICTED_IMPACT","NONE"] call A3UE_fnc_fpv_detonateCompat),"delivery collateral refused"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="SAFETY_HOLD","real collateral hold despite visibility"] call _assert;
''',actual)

    def test_server_support_visibility_rejection_and_delivery_ring_precedence(self):
        actual='A3UE_fnc_fpv_supportEngagementReason={'+engine_substitutes((FPV/'fn_fpv_supportEngagementReason.sqf').read_text())+'};'
        self.sqf('''
private _record=createHashMapFromArray [["phase","live"],["object",_uav],["owner",2],["support","qa"]];
missionNamespace setVariable ["A3UE_FPV_lifecycles",createHashMapFromArray [["1",_record]]];
private _entry=createHashMapFromArray [["drones",[_uav]],["droneNetIds",["uav"]],["safetyRadius",40],["side",east]];
missionNamespace setVariable ["A3UE_FPV_supportRegistry",createHashMapFromArray [["qa",_entry]]];
private _strike=createHashMapFromArray [["uavNetId","uav"],["targetNetId","target"],["targetRevision",0],
 ["deliveryPosASL",[250,0,2]],["deliveryDir",[1,0,0]],["deliveryUp",[0,0,1]],
 ["detonationReason","PREDICTED_IMPACT"],["fallbackReason","NONE"]];
FPV_blocked=true;
[!([_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation),"server visibility refusal"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="TERMINAL_VECTOR" && {_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==-1},"server visibility does not disable guidance"] call _assert;
FPV_deliverySafe=false;
[!([_uav,1,_strike,[],20] call A3UE_fnc_fpv_commitDetonation),"server collateral refusal"] call _assert;
[_uav getVariable ["A3UE_FPV_mode",""]=="SAFETY_HOLD" && {_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]==FPV_time},"server retains real hold"] call _assert;
[FPV_creates==0,"no disallowed payload"] call _assert;
''',actual)

    def test_inherited_speed_descent_and_reverse_heading_converge_bounded(self):
        self.sqf('''
{_x params ["_dir","_speed"];
 private _up=if (abs (_dir # 2)>0.9) then {[0,1,0]} else {[0,0,1]};
 _up=vectorNormalized (_up vectorDiff (_dir vectorMultiply (_up vectorDotProduct _dir)));
 private _s=[[],0,0,_dir,_up,_speed,[0,0,0],1,"INIT",0,_dir,_dir vectorMultiply _speed];
 private _dt=0.02;
 for "_i" from 0 to 600 do {
  private _old=+_s;
  private _result=[_s,[],[0,0,100],[300,0,0],[0,0,0],_s # 5,_limits,_dt] call A3UE_fnc_fpv_trajectorySteering;
  private _step=_result # 0;
  [count _step==6,"finite continuing step"] call _assert;
  [abs ((_step # 2)-(_s # 5))<=(_limits # 2)*_dt+0.001,"bounded speed"] call _assert;
  [(_step # 3) vectorDistance (_s # 6)<=3*_dt+0.001,"bounded rate slew"] call _assert;
  [vectorMagnitude (_step # 3)*((_step # 2) max (_s # 5))<=(_limits # 3)+0.001,"adjacent speed lateral budget"] call _assert;
  _s set [3,_step # 0];_s set [4,_step # 1];_s set [5,_step # 2];_s set [6,_step # 3];
 };
 [(_s # 5)<=(_limits # 0)+0.01,"cruise convergence"] call _assert;
 [abs ((_s # 3 # 2)*(_s # 5))<=(_limits # 4)+0.1,"descent convergence"] call _assert;
 [(_s # 3) vectorDotProduct (vectorNormalized [300,0,-100])>0.98,"heading convergence"] call _assert;
} forEach [[[0,0,-1],45],[[-1,0,0],40],[vectorNormalized [1,0,-2],35]];
''')

    def test_zero_dt_and_control_release_reconstruct_real_state(self):
        self.sqf('''
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
_uav setVariable ["controlled",true];
[!([_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector),"real control substitute"] call _assert;
_uav setVariable ["controlled",false];_uav setVariable ["velocity",[0,30,-20]];
FPV_time=FPV_time+2;FPV_observed=FPV_observed+2;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"release admission"] call _assert;
private _s=_uav getVariable ["A3UE_FPV_terminalSteeringState",[]];
[(_s # 9)==0 && {(_s # 11) isEqualTo [0,30,-20]},"real-state zero dt seed"] call _assert;
[FPV_moves isEqualTo [],"no reconstruction effect"] call _assert;
FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"release continuation"] call _assert;
[count FPV_moves==1,"release progress command"] call _assert;
''')

if __name__=='__main__':unittest.main()
