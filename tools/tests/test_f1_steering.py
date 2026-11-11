"""F1 numerical/specification and source contracts. Does not execute SQF/Arma physics."""
import copy
import math
from pathlib import Path
import random
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT / 'addons/drones/functions/fpv'
STEP = (FPV / 'fn_fpv_stepTerminalSteering.sqf').read_text()
STATUS = (FPV / 'fn_fpv_terminalSteeringStatus.sqf').read_text()
RUNTIME = (FPV / 'fn_fpv_runTerminalVector.sqf').read_text()


def valid_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and abs(v) <= 1e6


def valid_vector(v):
    return isinstance(v, (list, tuple)) and len(v) == 3 and all(map(valid_number, v))


def add(a, b): return [x+y for x,y in zip(a,b)]
def sub(a, b): return [x-y for x,y in zip(a,b)]
def mul(a, k): return [x*k for x in a]
def dot(a, b): return sum(x*y for x,y in zip(a,b))
def mag(a): return math.sqrt(dot(a,a))
def norm(a): return mul(a,1/mag(a))
def cross(a, b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def angle(a, b): return math.acos(max(-1,min(1,dot(norm(a),norm(b)))))


def step(direction, up, speed, angular_rate, aim, target, accel, decel, blend, blend_max, dt):
    """Independent SI equation model, paired with shipped-expression assertions below."""
    if not all(map(valid_vector, [direction,up,angular_rate,aim])) or not all(map(valid_number,[speed,target,accel,decel,blend,blend_max,dt])):
        return None
    if (min(speed,target,accel,decel,dt,blend) < 0 or dt > .25 or blend > blend_max or blend_max > 1
            or min(mag(direction),mag(up),mag(aim)) < 1e-6): return None
    direction,aim=norm(direction),norm(aim)
    up=sub(up,mul(direction,dot(up,direction)))
    if mag(up)<1e-6:return None
    up=norm(up)
    if dt==0:return [direction,up,speed,list(angular_rate),0,0]
    alignment=max(-1,min(1,dot(direction,aim)))
    theta=math.acos(alignment)
    maximum=math.pi*(-math.log(1-min(blend_max,.999999))/.02)
    if mag(angular_rate)>maximum+1e-6:return None
    slew=2*maximum/.02
    fraction=1-(1-min(blend,.999999))**(dt/.02)
    tangent=sub(aim,mul(direction,alignment))
    if mag(tangent)<1e-6:tangent=up
    axis=norm(cross(direction,norm(tangent)))
    requested=mul(axis,min(theta*fraction/dt,maximum))
    delta=sub(requested,angular_rate)
    if mag(delta)>slew*dt and mag(delta)>0:delta=mul(delta,slew*dt/mag(delta))
    rate=add(angular_rate,delta)
    if mag(rate)>maximum and mag(rate)>0:rate=mul(rate,maximum/mag(rate))
    turn=mag(rate)*dt
    if turn>0:
        axis=norm(rate);c,s=math.cos(turn),math.sin(turn)
        def rotate(v):return add(add(mul(v,c),mul(cross(axis,v),s)),mul(axis,dot(axis,v)*(1-c)))
        direction,up=norm(rotate(direction)),rotate(up)
    up=norm(sub(up,mul(direction,dot(up,direction))))
    dv=max(-decel*dt,min(accel*dt,target-speed))
    return [direction,up,speed+dv,rate,dv/dt,turn]


KEY = [[10,2,1,1],'target-object','target-id','TERMINAL_VECTOR',['epoch','marker','EAST'],1,['GROUND','surface','vehicle'],'support','event']


def seed(key=KEY, now=1, observed=10, velocity=(10,0,0), body=(0,1,0), serial=1, reason='INIT'):
    direction=norm(velocity if mag(velocity)>=.01 else (body if mag(body)>=1e-6 else [0,1,0]))
    up=[0,0,1] if abs(direction[2])<.95 else [0,1,0]
    up=norm(sub(up,mul(direction,dot(up,direction))))
    return [copy.deepcopy(key),now,observed,direction,up,mag(velocity),[0,0,0],serial,reason,0,[0,1,0],list(velocity)]


def status(state, key, now, observed, tolerant=True):
    if (not isinstance(now,(int,float)) or isinstance(now,bool) or not math.isfinite(now)
            or not isinstance(observed,(int,float)) or isinstance(observed,bool) or not math.isfinite(observed) or min(now,observed)<0):return 'CLOCK_INVALID',0
    if state==[]:return 'INIT',0
    if not isinstance(state,list) or len(state)!=12:return 'INVALID',0
    if state[0]!=key:return 'KEY',0
    if (not all(valid_number(state[i]) for i in [5,7,9])
            or not all(isinstance(state[i],(int,float)) and not isinstance(state[i],bool) and math.isfinite(state[i]) for i in [1,2]) or not all(valid_vector(state[i]) for i in [3,4,6,10,11])
            or not isinstance(state[8],str)):return 'INVALID',0
    if (min(state[1],state[2],state[5])<0 or state[7]<1 or state[7]!=int(state[7])
            or abs(mag(state[3])-1)>.001 or abs(mag(state[4])-1)>.001 or abs(dot(state[3],state[4]))>.001):return 'INVALID',0
    dt,gap=now-state[1],observed-state[2]
    if min(dt,gap)<0:return 'TIME_REVERSE',0
    if dt>.25:
        # LT-1: a late step integrates a capped 0.25 s; LATE continues a driven state up to 1 s.
        if not tolerant or gap>dt+.5:return 'GAP',0
        return ('LATE' if dt<=1 and state[9]>0 else 'STALL'),.25
    if gap>.5:return 'PAUSE',0
    return ('DUPLICATE',0) if dt==0 else ('STEP',dt)


class SteeringNumericalTests(unittest.TestCase):
    def advance(self, partitions, blend=.35, aim=(0,1,0), aligned_accel=False):
        d,u,s,w=[1,0,0],[0,0,1],10,[0,0,0]
        for dt in partitions:
            b=blend
            a=24/3.6
            if aligned_accel:
                factor=max(0,min(1,(dot(d,aim)-.70)/(.94-.70)))
                a*=factor;b=.22+factor*(blend-.22)
            d,u,s,w,*_=step(d,u,s,w,aim,30,a,30/3.6,b,blend,dt)
        return d,u,s,w

    def test_partition_frozen_response_is_time_composable(self):
        # Constant target/response, ordinary >=20ms scheduled partitions: exact exponential arc.
        fixed=[.02]*25; irregular=[.02,.03,.05,.08,.12,.2]
        a,b=self.advance(fixed),self.advance(irregular)
        self.assertLess(angle(a[0],b[0]),2e-6)
        self.assertAlmostEqual(a[2],b[2],delta=1e-8)

    def test_partition_alignment_feedback_declared_tolerance(self):
        # Alignment-dependent authored gain is sampled, so this is deliberately not exact.
        a=self.advance([.02]*25,aligned_accel=True)
        b=self.advance([.02,.03,.05,.08,.12,.2],aligned_accel=True)
        self.assertLess(angle(a[0],b[0]),.01)  # 0.573 degrees, endpoint after 0.5 simulation seconds
        self.assertAlmostEqual(a[2],b[2],delta=.4)  # m/s; finite sampled planning-feedback difference

    def test_accel_decel_and_overspeed_without_entry_kick(self):
        for dt in [.001,.02,.07,.25]:
            for initial,target,expected in [(0,100,24/3.6),(50,0,-30/3.6)]:
                r=step([1,0,0],[0,0,1],initial,[0,0,0],[1,0,0],target,24/3.6,30/3.6,.35,.35,dt)
                self.assertAlmostEqual(r[4],expected)
                self.assertAlmostEqual(r[2],initial+expected*dt)
        self.assertAlmostEqual(step([1,0,0],[0,0,1],10,[0,0,0],[1,0,0],10.01,8,9,.35,.35,.1)[2],10.01)

    def test_vector_rate_and_acceleration_slew_bounds_changing_planes(self):
        rng=random.Random(117);d,u,s,w=[1,0,0],[0,0,1],10,[0,0,0]
        maximum=math.pi*(-math.log(1-.46)/.02);alpha=2*maximum/.02
        for _ in range(300):
            dt=rng.choice([.0001,.001,.01,.02,.044,.1,.25]);aim=norm([rng.uniform(-1,1) for _ in range(3)])
            old=w;r=step(d,u,s,w,aim,20,44/3.6,54/3.6,.46,.46,dt)
            d,u,s,w,*_=r
            self.assertLessEqual(mag(w),maximum+1e-8)
            self.assertLessEqual(mag(sub(w,old))/dt,alpha+1e-7)
            self.assertAlmostEqual(mag(d),1,delta=1e-12);self.assertAlmostEqual(mag(u),1,delta=1e-12)
            self.assertAlmostEqual(dot(d,u),0,delta=1e-12)

    def test_opposite_vertical_parallel_zero_speed_and_zero_blend(self):
        for d,u,aim in [([1,0,0],[0,0,1],[-1,0,0]),([0,0,1],[0,1,0],[0,0,-1]),([0,0,1],[0,1,0],[0,0,1])]:
            r=step(d,u,0,[0,0,0],aim,10,0,8,.35,.35,.02)
            self.assertEqual(r[2],0);self.assertTrue(all(math.isfinite(x) for v in [r[0],r[1],r[3]] for x in v))
            self.assertAlmostEqual(dot(r[0],r[1]),0,delta=1e-12)
        r=step([1,0,0],[0,0,1],10,[0,0,0],[0,1,0],20,8,9,0,0,.1)
        self.assertEqual(r[0],[1,0,0]);self.assertEqual(r[3],[0,0,0])

    def test_no_integration_at_duplicate_timestamp(self):
        args=[[1,0,0],[0,0,1],0,[0,0,0],[-1,0,0],100,8,9,.35,.35,0]
        r=step(*args);self.assertEqual(r,[[1,0,0],[0,0,1],0,[0,0,0],0,0])

    def test_invalid_nonfinite_malformed_and_extreme_values_suspend(self):
        base=[[1,0,0],[0,0,1],10,[0,0,0],[0,1,0],20,8,9,.35,.35,.02]
        for i in range(len(base)):
            for bad in [True,None,'bad',float('nan'),float('inf'),-float('inf')]:
                a=copy.deepcopy(base);a[i]=bad
                self.assertIsNone(step(*a),(i,bad))
        for i,bad in [(0,[0,0,0]),(0,[1e-8,0,0]),(0,[1e7,0,0]),(0,[1,0]),(1,[1,0,0]),(2,-1),(3,[10000,0,0]),(8,1.1),(10,-1),(10,.251)]:
            a=copy.deepcopy(base);a[i]=bad;self.assertIsNone(step(*a),(i,bad))


class SteeringStateTests(unittest.TestCase):
    def test_initialization_and_reconstruction_from_real_motion(self):
        self.assertEqual(status([],KEY,1,10),('INIT',0))
        old=seed(velocity=[10,0,0]);new=seed(velocity=[0,-12,3],serial=2,reason='INIT')
        self.assertLess(angle(new[3],[0,-12,3]),1e-7)
        self.assertGreater(angle(old[3],new[3]),1)
        self.assertEqual(new[6],[0,0,0]);self.assertEqual(new[9],0)
        self.assertEqual(seed(velocity=[0,0,0],body=[0,0,1])[3],[0,0,1])
        self.assertEqual(seed(velocity=[0,0,0])[5],0)

    def test_every_key_component_invalidates_including_exact_object_and_phase(self):
        for path in [(0,0),(0,1),(0,2),(0,3),(1,),(2,),(3,),(4,0),(4,1),(4,2),(5,),(6,0),(6,1),(6,2),(7,),(8,)]:
            key=copy.deepcopy(KEY);node=key
            for i in path[:-1]:node=node[i]
            node[path[-1]]='replacement'
            self.assertEqual(status(seed(),key,1.02,10.02),('KEY',0),path)

    def test_clock_boundaries_duplicates_gaps_pause_and_reversal(self):
        s=seed()
        for now,observed,result in [(1,10,('DUPLICATE',0)),(1.25,10.5,('STEP',.25)),(1.250001,10.3,('STALL',.25)),
                (1.02,10.50001,('PAUSE',0)),(.99,10.1,('TIME_REVERSE',0)),(1.02,9.99,('TIME_REVERSE',0)),
                (float('nan'),10,('CLOCK_INVALID',0))]:
            self.assertEqual(status(s,KEY,now,observed),result)
        self.assertEqual(status(seed(now=1.25,observed=10.6),KEY,1.27,10.62)[0],'STEP')
        # LT-1: late steps never integrate more than 0.25 s; the legacy switch-off keeps GAP.
        driven=seed();driven[9]=.02
        for now,observed,result in [(1.3,10.3,('LATE',.25)),(2,11,('LATE',.25)),(2.01,11.01,('STALL',.25)),
                (1.6,11.2,('GAP',0))]:
            self.assertEqual(status(driven,KEY,now,observed),result)
        self.assertEqual(status(driven,KEY,1.3,10.3,tolerant=False),('GAP',0))

    def test_corrupt_state_reconstructs_not_normalizes_silently(self):
        for i,bad in [(3,[0,0,0]),(4,[1,0,0]),(5,-1),(6,[float('inf'),0,0]),(7,1.5),(8,False),(9,float('nan'))]:
            s=seed();s[i]=bad;self.assertEqual(status(s,KEY,1.02,10.02),('INVALID',0))

    def test_stale_worker_refuses_and_cannot_erase_newer_state(self):
        # Models the atomic compare of BOTH original key and immutable tuple snapshot.
        before=seed();current=seed(now=1.02,serial=2)
        def admitted(identity,key,snapshot,controlled=False):
            return identity==KEY[0] and key==KEY and snapshot==current and not controlled
        self.assertFalse(admitted(KEY[0],KEY,before))
        saved=copy.deepcopy(current)
        if admitted(KEY[0],KEY,before):current=[]
        self.assertEqual(current,saved)
        self.assertFalse(admitted([10,2,1,0],KEY,current));self.assertFalse(admitted(KEY[0],KEY,current,True))
        self.assertTrue(admitted(KEY[0],KEY,current))

    def test_real_control_release_discards_then_seeds_changed_real_state(self):
        held=seed();held=[]  # existing verified direct-control path clears, no new control semantics
        self.assertEqual(status(held,KEY,3,12),('INIT',0))
        resumed=seed(now=3,observed=12,velocity=[-5,4,-1],serial=2)
        self.assertLess(angle(resumed[3],[-5,4,-1]),1e-7)
        self.assertEqual(resumed[9],0)


class SteeringSourceTests(unittest.TestCase):
    def test_pure_helpers_and_explicit_units_equations(self):
        for s in [STEP,STATUS]:
            self.assertNotRegex(s,r'\b(setVariable|getVariable|remoteExec|spawn|sleep|setVelocity|setPos|vectorDir|vectorUp)\b')
        for fragment in ['(pi / 180)','(180 / pi)','_dt / 0.02','2 * _rateMax / 0.02','_slewMax * _dt','(-_decel * _dt)','(_accel * _dt)']:
            self.assertIn(fragment,STEP)
        # F2 centralizes the unchanged km/h boundary in the pure envelope helper.
        limits=(FPV/'fn_fpv_trajectoryLimits.sqf').read_text()
        self.assertIn('_value / 3.6',limits)
        for v in ['Accel','Decel','SpeedLagTolerance','MaxSpeed']:
            self.assertIn(f'"terminalVector{v}"',limits)

    def test_body_axes_only_in_real_seed_and_no_competing_writer(self):
        self.assertEqual(RUNTIME.count('vectorDir _uav'),1)
        self.assertNotIn('vectorUp _uav',RUNTIME)
        self.assertIn('else {vectorDir _uav}',RUNTIME)
        self.assertIn('private _normalizedCurrentDir = _state # 3;',RUNTIME)
        self.assertIn('private _speedBudgetNow = _state # 5;',RUNTIME)
        self.assertIn('_actualSpeed + (_limits # 9)',(FPV/'fn_fpv_trajectorySteering.sqf').read_text())
        self.assertNotRegex(RUNTIME,r'\b(spawn|sleep|EachFrame|remoteExec|setPos|enableSimulation)\b')

    def test_atomic_identity_intent_state_site_control_link_and_commit_fences(self):
        fence=RUNTIME.split('private _applied = false;\nisNil {',1)[1].split('private _vectorUpdateAt',1)[0]
        for fragment in ['canActuate','hasCurrentLifecycle','controllerIdentity','controllerGeneration','targetNetId',
                'TERMINAL_VECTOR','isExternallyControlled','EW_DENIED','detonating','call _readSteeringKey','isEqualTo _steeringBefore']:
            self.assertIn(fragment,fence)
        for fragment in ['siteEpoch','siteMarker','siteSide','terminalVectorEnteredAt','targetRevision','supportName','rivalEventId']:
            self.assertIn(fragment,RUNTIME)
        clear=RUNTIME.split('private _clearSteeringSnapshot',1)[1].split('private _planningAt',1)[0]
        self.assertIn('isEqualTo _steeringBefore',clear);self.assertIn('isEqualTo _steeringKey',clear)
        self.assertIn('call A3UE_fnc_fpv_helperAccess',RUNTIME)
        access=(FPV/'fn_fpv_helperAccess.sqf').read_text()
        self.assertIn('isRemoteExecutedJIP',access);self.assertIn('remoteExecutedOwner',access)

    def test_reset_paths_and_fuse_survives_zero_dt(self):
        for name,n in [('runController',1),('bootstrapLocal',2),('deleteLocal',1)]:
            self.assertGreaterEqual((FPV/f'fn_fpv_{name}.sqf').read_text().count('["A3UE_FPV_terminalSteeringState", []]'),n)
        c=(FPV/'fn_fpv_runController.sqf').read_text()
        self.assertIn('[_target,_guidanceRevision] call _evaluateFuse',c.split('call A3UE_fnc_fpv_runTerminalVector',1)[1])
        self.assertLess(RUNTIME.index('if (_dt > 0) then {'),RUNTIME.index('disableAI "PATH"'))
        for s in [RUNTIME, (FPV/'fn_fpv_bootstrapLocal.sqf').read_text(),(FPV/'fn_fpv_deleteLocal.sqf').read_text()]:
            for line in s.splitlines():
                if 'setVariable ["A3UE_FPV_terminalSteeringState"' in line:self.assertNotIn(', true]',line)

    def test_status_time_envelope_and_cfgfunctions(self):
        for fragment in ['_dt == 0','_dt < 0','_dt > 0.25','_observedGap > 0.5','["DUPLICATE", 0]',
                         '["_tolerant", true]','_tolerant isEqualTo false || {_observedGap > _dt + 0.5}',
                         '[["STALL", "LATE"] select (_dt <= 1 && {(_state # 9) > 0}), 0.25]']:
            self.assertIn(fragment,STATUS)
        # LT-1: LATE continues the logical state; every other reset re-seeds from the airframe.
        self.assertIn('!(_resetReason in ["STEP", "DUPLICATE", "LATE"])',RUNTIME)
        self.assertIn('if (_dt > 0) then {_state set [9, _dt];};',RUNTIME)
        for s in [RUNTIME,(FPV/'fn_fpv_prepareTrajectory.sqf').read_text()]:
            self.assertIn('(missionNamespace getVariable ["A3UE_FPV_loadTolerantDive", true]) isNotEqualTo false',s)
        config=(ROOT/'addons/drones/config.cpp').read_text()
        self.assertIn('requiredVersion = 2.14',config)
        for name in ['terminalSteeringStatus','stepTerminalSteering']:
            self.assertIn(f'class fpv_{name} {{}};',config)


if __name__=='__main__':unittest.main()
