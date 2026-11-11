"""Execute shipped SQF with explicit engine-property/effect substitutes.

No alternate controller/eligibility/geometry implementation: only unavailable VM
engine primitives are substituted. Objects/arrays/hashmaps/control flow are VM SQF.
This does not emulate physics, replication, authentication or scheduler races.
"""
from pathlib import Path
import os,re,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
FPV=ROOT/'addons/drones/functions/fpv'
VM=os.environ.get('FPV_SQFVM')
TOKEN=re.compile(r'//[^\n]*|/\*.*?\*/|"(?:""|[^"])*"|[A-Za-z_]\w*|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|!=|>=|<=|==|&&|\|\||>>|\s+|.',re.S)
UNARY=set('finite local alive captive velocity vectorDir vectorUp getPosASL getPosATL getPosWorld crew driver effectiveCommander objectParent netId objectFromNetId owner getForcedSpeed side group values ASLToATL ASLToAGL getTerrainHeightASL terrainIntersectASL lineIntersectsSurfaces'.split())
NULAR={'time':'FPV_time','diag_tickTime':'FPV_observed','diag_frameNo':'FPV_frame','serverTime':'FPV_time',
       'canSuspend':'false','clientOwner':'2','remoteExecutedOwner':'FPV_sender','isRemoteExecutedJIP':'FPV_jip','isRemoteExecuted':'FPV_remote'}

def engine_substitutes(source):
    tokens=[m.group() for m in TOKEN.finditer(source) if not m.group().isspace() and not m.group().startswith(('//','/*'))]
    def sequence(i,close=None):
        parts=[]
        while i<len(tokens) and tokens[i]!=close:
            if tokens[i] in ('getOrDefault','isKindOf','setVariable'):
                op=tokens[i]
                left=parts.pop();right,i=atom(i+1)
                parts.append(f'([{left},{right}] call FPV_{op})')
            else:
                p,i=atom(i);parts.append(p)
        return ' '.join(parts),i
    def atom(i):
        t=tokens[i]
        if t=='isNil' and tokens[i+1]=='{':
            body,j=sequence(i+2,'}')
            return '(call {'+body+';false})',j+1
        if t in UNARY:
            arg,j=atom(i+1)
            return f'({arg} call FPV_{t})',j
        if t in ('(','[','{'):
            close={'(':')','[':']','{':'}'}[t]
            body,j=sequence(i+1,close)
            return t+' '+body+' '+close,j+1
        return NULAR.get(t,t),i+1
    return sequence(0)[0]

SETUP='''
FPV_time=10; FPV_observed=20; FPV_frame=100; FPV_sender=2; FPV_jip=false; FPV_remote=false;
FPV_objects=[]; FPV_moves=[]; FPV_poses=[]; FPV_hold=0; FPV_sent=0; FPV_creates=0;
FPV_scans=0;
FPV_nearEntities={params ["_c","_r"];FPV_scans=FPV_scans+1;FPV_objects select {((_x getVariable ["position",[0,0,50]]) distance2D _c) <= _r}};
FPV_dist={params ["_a","_b"];(_a getVariable ["position",[0,0,50]]) vectorDistance (_b getVariable ["position",[0,0,50]])};
FPV_finite={_this isEqualType 0 && {abs _this < 1e38}};
FPV_getOrDefault={params ["_map","_args"];if ((_args # 0) in _map) then {_map get (_args # 0)} else {_args # 1}};
FPV_values={private _map=_this;(keys _map) apply {_map get _x}};
FPV_ASLToATL={_this};FPV_ASLToAGL={_this};
FPV_queries=0;FPV_collision="";
FPV_getTerrainHeightASL={FPV_queries=FPV_queries+1;if (FPV_collision=="CLEARANCE") then {200} else {-100}};
FPV_terrainIntersectASL={FPV_queries=FPV_queries+1;FPV_collision=="TERRAIN"};
FPV_lineIntersectsSurfaces={FPV_queries=FPV_queries+1;if (FPV_collision=="OBJECT") then {[[[50,0,30],[0,0,1],objNull,objNull]]} else {[]}};
FPV_isKindOf={params ["_o","_kind"];_kind in (_o getVariable ["kinds",[]])};
FPV_setVariable={params ["_o","_args"];_o setVariable [_args # 0,_args # 1];};
FPV_local={_this getVariable ["local",true]};
FPV_alive={!isNull _this && {_this getVariable ["alive",true]}};
FPV_captive={_this getVariable ["captive",false]};
FPV_velocity={_this getVariable ["velocity",[10,0,0]]};
FPV_vectorDir={_this getVariable ["direction",[1,0,0]]};
FPV_vectorUp={_this getVariable ["up",[0,0,1]]};
FPV_getPosASL={_this getVariable ["position",[0,0,50]]};
FPV_getPosATL=FPV_getPosASL; FPV_getPosWorld=FPV_getPosASL;
FPV_crew={_this getVariable ["crew",[]]};
FPV_driver={_this getVariable ["driver",objNull]};
FPV_effectiveCommander={_this getVariable ["commander",objNull]};
FPV_objectParent={_this getVariable ["parent",objNull]};
FPV_netId={if (isNull _this) then {""} else {_this getVariable ["netId",""]}};
FPV_objectFromNetId={private _id=_this; (FPV_objects select {(_x call FPV_netId)==_id}) param [0,objNull]};
FPV_owner={_this getVariable ["owner",2]}; FPV_getForcedSpeed={-1};
FPV_group={_this}; FPV_side={if (isNull _this) then {sideUnknown} else {_this getVariable ["side",east]}};
A3UE_fnc_fpv_helperAccess={true}; A3UE_fnc_fpv_lifecycleAccess={true};
A3UE_fnc_fpv_getHostileSides={[west]};
A3UE_fnc_fpv_isExternallyControlled={(_this # 0) getVariable ["controlled",false]};
A3UE_fnc_fpv_isSiteDroneActive={(_this # 0) getVariable ["siteActive",true]};
A3UE_fnc_fpv_hasCurrentLifecycle={(_this # 0) getVariable ["lifecycle",true]};
A3UE_fnc_fpv_publishTelemetry={params ["_o","_k","_v"];_o setVariable [_k,_v];};
A3UE_fnc_fpv_supportEngagementReason={FPV_permission}; FPV_permission="";
A3UE_fnc_fpv_isTargetObstructed={createHashMapFromArray [["blocked",FPV_blocked]]}; FPV_blocked=false;
A3UE_fnc_fpv_supportPassesSafetyRing={if (isNull (_this # 1)) then {FPV_deliverySafe} else {FPV_targetSafe}};
FPV_deliverySafe=true;FPV_targetSafe=true;
A3UE_fnc_fpv_getClassDescriptor={createHashMapFromArray [["canDetonate",true],["ammoClass","VMAmmo"]]};
A3UE_fnc_fpv_sendLifecycle={FPV_sent=FPV_sent+1;true};
private _make={params ["_class","_id"];private _o=_class createVehicle [0,0,0];_o setVariable ["netId",_id];
 _o setVariable ["kinds",switch (_class) do {case "VMMan": {["Man","AllVehicles"]};case "VMVehicle": {["LandVehicle","Car","AllVehicles"]};default {["Air","AllVehicles"]};}];
 if (_class=="VMMan") then {_o setVariable ["crew",[_o]];};
 FPV_objects pushBack _o;_o};
private _assert={params ["_ok","_label"];if (!_ok) then {throw _label;};};
private _uav=["VMUAV","uav"] call _make;
private _target=["VMVehicle","target"] call _make;
private _person=["VMMan","person"] call _make;_person setVariable ["side",west];
_target setVariable ["crew",[_person]];_target setVariable ["commander",_person];_target setVariable ["position",[250,0,1.2]];
private _identity=[1,2,1,1]; private _generation=1; private _controllerIdentity=+_identity;
{
 _uav setVariable [_x # 0,_x # 1];
} forEach [["A3UE_FPV_targetNetId","target"],["A3UE_FPV_controllerIdentity",_identity],
 ["A3UE_FPV_lifecycleId",1],["A3UE_FPV_lifecycleEpisode",1],["A3UE_FPV_controllerGeneration",1],
 ["A3UE_FPV_managed",true],["A3UE_FPV_controllerRunning",true],["A3UE_FPV_netId","uav"],
 ["A3UE_FPV_mode","TERMINAL_VECTOR"],["A3UE_FPV_terminalVectorEnteredAt",9],
 ["A3UE_FPV_payloadRole","AP"],["A3UE_FPV_lifecycleIdServer",1]];
private _profile=createHashMapFromArray [["familyId","armafpv"]];
// F2/F2C/F2C-L contract scenarios run with the F4-1 attack run off (its regression
// boundary); F4-1 tests switch it on explicitly.
missionNamespace setVariable ["A3UE_FPV_attackRun",false];
private _limits=[_profile] call A3UE_fnc_fpv_trajectoryLimits;
'''

HELPERS=['profileValue','trajectoryLimits','planTrajectory','followTrajectory','stepTerminalSteering','terminalPresentationUp',
 'terminalSteeringStatus','trajectorySteering','filterTarget','resolveTarget','canActuate',
 'attackSettings','attackEngagement','attackApproach','attackPass','attackAimOffset','attackNavigation','attackPassSummary',
 'attackReversal','attackLimits','obstacleProbe','attackClearLine','transitHeight',
 'targetNavigation','prepareTrajectory','runTerminalVector','clearTarget','detonateCompat','commitDetonation','selectTarget',
 # LT-2: clearTarget and selectTarget call these.
 'wingSettings','attackSlot','attackRelease','attackCrowd','overwatchPoint','scanTargets']

def adapt_helper(name,s):
        if name=='runTerminalVector':
            s=s.replace('_uav setVelocity _desiredVelocity;', 'FPV_moves pushBack +_desiredVelocity;')
            # Published F2C (3ebedea and earlier) and F2C-L presentation setter forms.
            s=s.replace('_uav setVectorDirAndUp [_blendedDir, vectorNormalized _up];','FPV_poses pushBack [_blendedDir,vectorNormalized _up];')
            s=s.replace('_uav setVectorDirAndUp [_blendedDir, _poseUp];','FPV_poses pushBack [_blendedDir,_poseUp];')
            s=s.replace('_x checkAIFeature "PATH"','true').replace('_x checkAIFeature "FSM"','true').replace('_x checkAIFeature "AUTOCOMBAT"','true')
            s=re.sub(r'\(_x # 0\) disableAI "(?:PATH|FSM|AUTOCOMBAT)";', '',s)
            s=s.replace('_uav forceSpeed -1;', '')
        if name=='scanTargets':
            # The VM has no entity lists: the scan returns the test objects inside the circle.
            s=s.replace('_center nearEntities [["Man", "LandVehicle", "Air", "Ship", "StaticWeapon"], _radius]','([_center,_radius] call FPV_nearEntities)')
        if name=='attackSlot':
            # Object ranges come from the tests' "position" variables.
            s=re.sub(r'(_\w+) distance _target', r'([\1,_target] call FPV_dist)', s)
        if name=='commitDetonation':
            s=s.replace('private _missile = createVehicle [_missileType, ASLToAGL _deliveryPos, [], 0, "CAN_COLLIDE"];','FPV_creates=FPV_creates+1; private _missile=objNull;')
        return engine_substitutes(s)

def script(body,extra=None):
    helpers=''
    for name in HELPERS:
        helpers+='A3UE_fnc_fpv_'+name+'={'+adapt_helper(name,(FPV/f'fn_fpv_{name}.sqf').read_text())+'};\n'
    return helpers+SETUP+(extra or '')+body+'\ndiag_log "COMMITMENT_TEST_OK";'

def execute(body,extra=None):
    with tempfile.TemporaryDirectory(prefix='fpv-commitment-') as d:
        p=Path(d)/'test.sqf';p.write_text(script(body,extra))
        cfg=Path(d)/'config.cpp';cfg.write_text('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')
        return subprocess.run([VM,'-a','--suppress-welcome','--no-execute-print','--no-work-print','-m','20000','--input-config',str(cfg),'-i',str(p)],capture_output=True,text=True,timeout=25)
