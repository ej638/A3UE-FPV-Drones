params [
    "_uavInstance",
    "_unitKinds",
    "_targetSource",
    "_attackDistance",
    "_attackDistance2D",
    "_attackHeight",
    "_allowObjectParent",
    "_customAmmo",
    "_targetDetectionRange",
    "_heightAdjustmentDelay",
    "_stuckCheckInterval",
    "_stuckThreshold",
    "_moveAdjustmentDelay",
    "_initialSearchHeight"
];


isUnitOfKind = {
    params ["_unit", "_unitKinds"];
    private _result = false;
    {      
        private _is_kind_of = _unit isKindOf _x;
        if (_unit isKindOf _x) then { 
            _result = true;
            //systemChat format ["%1 isKindOf (%2) and breaking", _unit, _x, _is_kind_of];
            break;
        };
    } forEach _unitKinds;
    _result
};

// Function to find the nearest enemy of a specific type
findNearestEnemyOfType = {
    params ["_uavInstance", "_unitKinds", "_targetSource", "_allowObjectParent", "_targetDetectionRange"];
    //systemChat format ["findNearestEnemyOfType: %1", _uavInstance];

    private _enemy_side = switch (side _uavInstance) do {
        case east: { west };
        case west: { east };
        default { civilian }; 
    };
    private _targets = switch (_targetSource) do {
        case "allUnits": { allUnits };
        case "vehicles": { vehicles };
    };

    private _enemies = _targets select {
        side _x == _enemy_side && { [_x, _unitKinds] call isUnitOfKind }
    };
    //systemChat format ["Enemies: %1", count _enemies];
    private _nearestEnemy = objNull;
    private _minDistance = _targetDetectionRange;
    private _uniqueTypes = [];

    {
        private _hasObjectParent = !(isNull objectParent _x);
        private _isValidEnemy = _allowObjectParent || !_hasObjectParent;
        private _distance = _uavInstance distance _x;
        //systemChat format ["_distance(: %1 to %2) = %3", _unit, _x, _distance];
        if (_isValidEnemy && (_distance < _minDistance)) then {
            _minDistance = _distance;
            _nearestEnemy = _x;
        };

        
    } forEach _enemies;
    
    /*
    if (!isNull _nearestEnemy) then {
        systemChat format ["Nearest Enemy: %1(%3) for drone: %2, parent %4", _nearestEnemy, _uavInstance, typeOf _nearestEnemy, objectParent _nearestEnemy];
    };*/

    _nearestEnemy
};


is_dead = {
    params ["_object"];
    (isNull _object) || !(alive _object)
};


isExternallyControlled = {
    params ["_unit"];
    
    // Check UAV Terminal connection
    private _isUAVConnected = isUAVConnected _unit;
    if (_isUAVConnected) then {
        true
    } else {
        // Check if unit is being directly controlled by Zeus
        private _zeusController = _unit getVariable ["bis_fnc_moduleRemoteControl_owner", objNull];
        if (!isNull _zeusController) then {
            true
        } else {
            false
        };
    };
};

private _initialized = _uavInstance getVariable ["initialized", false];

if (_initialized) exitWith {}; 

_uavInstance setBehaviour "CARELESS";
_uavInstance setSkill 1;
_uavInstance enableAI "ALL";
_uavInstance setSpeedMode "FULL";
_uavInstance setVariable ["initialized", true];
_uavInstance flyInHeight _initialSearchHeight;
_uavInstance forceSpeed 150;
_uavInstance setVariable ["jac_bonusStealth", 1.0];
systemChat format ["Initialized drone: %1", _uavInstance];

//"LandVehicle", "Car", "Tank"
private _nearestEnemy = objNull;
private _noTargetHintShown = false;
while {isNull _nearestEnemy && (!isNull _uavInstance)} do {
	if ([_uavInstance] call is_dead) then {
		break;
	};
	_nearestEnemy = [_uavInstance, _unitKinds, _targetSource, _allowObjectParent, _targetDetectionRange] call findNearestEnemyOfType;
    if ((isNull _nearestEnemy) && {!_noTargetHintShown}) then {
        _noTargetHintShown = true;
        systemChat format [
            "FPV drone %1 found no valid targets. Check side, Target Source (%2), Unit Types (%3), and whether the enemy is on foot or in a vehicle.",
            _uavInstance,
            _targetSource,
            _unitKinds joinString ","
        ];
    };
	sleep (1);
};

if (isNull _nearestEnemy) then {
	//systemChat format ['Drone %1 has no target!', _uavInstance];
	continue;
};

//systemChat format ["Target aquired for drone: %1 -> %2 (%3)", _uavInstance, _nearestEnemy, typeOf _nearestEnemy];

private _target = _nearestEnemy;
private _currentDistance2d = _uavInstance distance2D _target;
private _currentDistance = (getPosASL _uavInstance) vectorDistance (getPosASL _target);

private _initialDistance2d = _currentDistance2d;
//private _initialHeight = ((getPosATL _uavInstance) select 2);

private _lastSetHeight = _initialSearchHeight;
private _lastSetHeightTime = diag_tickTime;
private _uavCanHitTarget = false;
private _predictedDistance = _currentDistance;

private _lastMoveTime = diag_tickTime;
private _lastLookForNewEnemyTime = diag_tickTime;
private _sleepInterval = 0.05; 
private _ascendTimeout = 10;

// Add this new function at the top with other functions
isStuck = {
    params ["_uav", "_target", "_lastDistance"];
    private _currentDistance = _uav distance _target;
    private _relativeChange = abs(_currentDistance - _lastDistance) / _lastDistance;
    if (_relativeChange < _stuckThreshold) then {
        //systemChat format ["Drone %1 is stuck circling! No approach progress (dist: %2m)", _uav, _currentDistance];
        true
    } else {
        false
    };
};


handleStuckPos = {
    params ["_uav"];
    //systemChat format ["Moving stuck drone %1 to new position", _uav];
    
    // Get current position and height
    private _currentPos = getPosATL _uav;
    private _currentHeight = _currentPos select 2;
    
    // Calculate new position while maintaining height
    private _randomOffset = [
        (random 100) - 50,  // -20 to +20 meters X
        (random 100) - 50,  // -20 to +20 meters Y
        (random 100) - 50
    ];
    private _newPos = _currentPos vectorAdd _randomOffset;
    
    // Force immediate stop, then move to new position
    _uav forceSpeed 0;
    sleep 2;
    _uav flyInHeight _currentHeight + (_randomOffset select 2);  // Maintain current flyInHeight
    _uav move _newPos;
    _uav forceSpeed 150;
    sleep 5;
};


// ... in the main loop, add these variables before the while loop ...
private _lastPos = getPosASL _uavInstance;
private _lastPosTime = diag_tickTime;

// Add these variables before the main while loop
private _lastStuckCheckDistance = _currentDistance;
private _lastStuckCheckTime = diag_tickTime;

// Modify the main while loop to include stuck detection
while {(_predictedDistance > _attackDistance) || (_currentDistance2d > _attackDistance2D)} do {
	sleep _sleepInterval;
	_uavCanHitTarget = false;

	if ([_uavInstance] call isExternallyControlled) then {
        break;
    };

	// is_dead(_uavInstance)
	if ([_uavInstance] call is_dead) then {
		//systemChat format ["Drone is dead!"];
		break;
	};

	// Current target check
	if ([_target] call is_dead || (_currentDistance > 200)) then {
		//systemChat format ["Drone %1 lost the target!", _uavInstance];
		break;
	};
	
	private _currentHeight = ((getPosATL _uavInstance) select 2);
	private _distanceRatio = _currentDistance2d / _initialDistance2d min 1.0;
	private _desiredHeight = _attackHeight + (_initialSearchHeight - _attackHeight) * _distanceRatio;
	private _currentTime = diag_tickTime;
	
	//if ((_currentHeight < _desiredHeight && (_currentTime > _lastSetHeightTime + _ascendTimeout)) || (_currentHeight > _desiredHeight)) then {
	
	//_currentHeight
	private _setHeightFrequency = 1;
	if ((_currentHeight + 1 >= _attackHeight) && (_currentHeight > _desiredHeight + 1) && (_currentTime > _lastSetHeightTime + _setHeightFrequency)) then {
		
		private _canChangeHeight = true;
		if ((_desiredHeight > _lastSetHeight) && (_currentTime <= _lastSetHeightTime + _ascendTimeout)) then {
			_canChangeHeight = false;
		};
		if (_canChangeHeight) then {
			_lastSetHeight = _desiredHeight;
			_lastSetHeightTime = _currentTime;
			_uavInstance flyInHeight _lastSetHeight;
			private _sleepTime = ((_currentHeight / _desiredHeight) * _heightAdjustmentDelay) max 0.1;
			//systemChat format ["Drone %1 setting flyInHeight = %2, currentHeight = %3, sleep: %4",
			//	_uavInstance, _lastSetHeight, _currentHeight, _sleepTime];
			sleep _sleepTime;
		};
	};
					
	// Predictive targeting: adjust path based on target's velocity
	private _targetPos = getPosASL _target;
	private _targetVel = velocity _target;
	private _uavPos = getPosASL _uavInstance;
	private _uavVel = velocity _uavInstance;
	

	// Enhanced prediction considering acceleration
	/*private _predictedTargetPos = _targetPos vectorAdd (_targetVel vectorMultiply _sleepInterval) vectorAdd (_targetAcc vectorMultiply (0.5 * _sleepInterval * _sleepInterval));
	private _predictedUavPos = _uavPos vectorAdd (_uavVel vectorMultiply _sleepInterval);
	_predictedDistance = _predictedUavPos vectorDistance _predictedTargetPos;
	*/

	// Simple prediction assuming constant velocity and linear motion
	private _predictedTargetPos = _targetPos vectorAdd (_targetVel vectorMultiply _sleepInterval);
	private _predictedUavPos = _uavPos vectorAdd (_uavVel vectorMultiply _sleepInterval);
	_predictedDistance = _predictedUavPos vectorDistance _predictedTargetPos;


	private _movePos = getPosATL _target;
	//private _moveTimeout = 5;
	if (_predictedDistance < _attackDistance * 2) then {
		private _uavPosATL = getPosATL _uavInstance;
		private _targetPosATL = getPosATL _target;
		private _moveVector = (_targetPosATL vectorDiff _uavPosATL);
		_moveVector = vectorNormalized _moveVector;
		_moveVector = _moveVector vectorMultiply (_predictedDistance + 1.5*_attackDistance2D);
		
		_movePos = _uavPosATL vectorAdd _moveVector;
		_movePos = [_movePos select 0, _movePos select 1, _attackHeight];
		// systemChat format ["Drone %1 distance to |move vector| = %2", _uavInstance, vectorMagnitude _moveVector];
		//_moveTimeout = 0.2;
	} else {	
		if (_currentTime - _lastStuckCheckTime > _stuckCheckInterval) then {
			if ([_uavInstance, _target, _lastStuckCheckDistance] call isStuck) then {
        		[_uavInstance] call handleStuckPos;
				break;
			};
			_lastStuckCheckDistance = _currentDistance;
			_lastStuckCheckTime = _currentTime;
		};
	};


	//if (_currentTime > _lastMoveTime + _moveTimeout) then {
	_uavInstance DoMove _movePos;
	// Scale sleep based on how far we are from both min and max distances
	private _distanceRange = _targetDetectionRange - _attackDistance;
	private _distanceFromMax = (_predictedDistance - _attackDistance) max 0;
	private _distanceRatio = (_distanceFromMax / _distanceRange) min 1.0;
	private _moveSleepTime = ((_distanceRatio * _distanceRatio) * _moveAdjustmentDelay) max 0.01;

	//systemChat format ["Move - Distance: %1, Ratio: %2, Sleep: %3", _predictedDistance, _distanceRatio, _moveSleepTime];
	sleep _moveSleepTime;

	_uavInstance forceSpeed 150;
	_lastMoveTime = _currentTime;
	//};


	// occasionally look for new enemy
	private _lastLookForNewEnemyFreq = 4;                     
	if (_currentTime > _lastLookForNewEnemyTime + _lastLookForNewEnemyFreq) then {
		private _newNearestEnemy = [_uavInstance, _unitKinds, _targetSource, _allowObjectParent, _targetDetectionRange] call findNearestEnemyOfType;
		if (!(isNull _newNearestEnemy) && (_newNearestEnemy != _target)) then {
			//systemChat format ["New target aquired for drone: %1 -> %2 (%3)", _uavInstance, _newNearestEnemy, typeOf _newNearestEnemy];
			_target = _newNearestEnemy;
		};
		_lastLookForNewEnemyTime = _currentTime;
	};



	_currentDistance2d = _uavInstance distance2D _target;
	_currentDistance = (getPosASL _uavInstance) vectorDistance (getPosASL _target);
	_uavCanHitTarget = true;
	
	// if (_currentDistance < 30 ) then {
	// 	systemChat format ["Drone %1 distance to target = %2, distance2d = %3. _predictedDistance = %4", _uavInstance, _currentDistance, _currentDistance2d, _predictedDistance];
	// };


};

// final approach and explosion
if (_uavCanHitTarget) then {
    _uavInstance doMove (position _target);
    sleep 0.5;

    // Split the ammo string and create multiple explosives
    private _ammoTypes = _customAmmo splitString ",";
    private _explosives = [];
    
    {
        private _explosive = _x createVehicle (position _uavInstance);
        _explosive attachTo [_uavInstance, [0, 0, 0]];
        _explosives pushBack _explosive;
    } forEach _ammoTypes;

    _uavInstance deleteVehicleCrew driver _uavInstance;
    sleep 3;
    
    // Detach and detonate all explosives
    {
        detach _x;
        _x setDamage 1;
    } forEach _explosives;
    
    _uavInstance setDamage 1;
};

// At the end of the script, ensure cleanup
if (!isNull _uavInstance) then {
	_uavInstance setVariable ["initialized", false];
};
