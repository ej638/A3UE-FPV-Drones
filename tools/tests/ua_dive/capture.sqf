// Owner/server/observer LOCAL call. One bounded capture per process; no remoteExec.
// ["start", runId, [uav1,uav2], durationSeconds] call compileScript [...];
// ["mark", "visible stop"] / ["stop"] call compileScript [...];
// stop detaches immediately; export yields in a finite worker. See schema in runbook.
params [["_action", "start"], ["_id", ""], ["_drones", []], ["_duration", 60], ["_stopReason", "manual"]];
if (isRemoteExecuted) exitWith {diag_log "A3UE_FPV_QA capture BLOCKED: use Local Exec on each process"; false};
// Atomic start/stop claim/detach: scheduled cleanup cannot race automatic EachFrame stop.
if (canSuspend) exitWith {
	private _result = false;
	isNil {_result = _this call compileScript ["scripts\ua_dive\capture.sqf"];};
	_result
};
if (_action == "mark") exitWith {
	if (!isNil "A3UE_FPV_QA_sink") then {
		private _note = toString ((toArray (_id select [0,128])) select {_x != 10 && {_x != 13}});
		[objNull, "MARK", [_note]] call A3UE_FPV_QA_sink;
	}; true
};
if (_action == "stop") exitWith {
	private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
	if (count _cap == 0 || {!(_cap get "active")}) exitWith {false};
	if (!(_stopReason in ["manual", "cleanup", "duration"])) then {_stopReason = "manual";};
	[ objNull, "END", [_cap get "dropped", count (_cap get "rows"), _cap get "maxSampleGap",
		_cap get "sampleMisses", diag_tickTime - (_cap get "started"), _stopReason] ] call A3UE_FPV_QA_sink;
	_cap set ["active", false];
    private _cue = _cap getOrDefault ["phaseCueControl",controlNull];
    if (!isNull _cue) then {ctrlDelete _cue;};
	removeMissionEventHandler ["EachFrame", _cap get "eh"];
	{
		_x params ["_u", "_event", "_eh"];
		if (!isNull _u) then {_u removeEventHandler [_event, _eh];};
	} forEach (_cap get "hooks");
	{if (!isNull _x) then {_x setVariable ["A3UE_FPV_QA_capture", nil];};} forEach (_cap get "drones");
	missionNamespace setVariable ["A3UE_FPV_QA_sink", nil];
	private _worker = [_cap] spawn {
		params ["_cap"];
		private _rows = _cap get "rows";
		// Explicit formatting is local to export; never change global toFixed policy.
		private _serialize = {
			params ["_value"];
			if (_value isEqualType 0) exitWith {_value toFixed 6};
			if (_value isEqualType []) exitWith {"[" + ((_value apply {[_x] call _serialize}) joinString ",") + "]"};
			str _value
		};
		private _bases = _cap get "bases";
		{
			private _row = +_x;
			private _data = +(_row # 12);
			// Only absolute clocks; durations, steering dt, vectors and sentinels stay untouched.
			private _clockFields = switch (_row # 5) do {
				case "MOVE": {[[0,0,false],[1,0,false]]};
				case "POSE": {[[1,0,false],[2,0,false]]};
				case "STEERING": {[[2,2,false],[3,0,false]]};
				case "AI_INTENT": {[[0,0,false]]};
				case "DO_MOVE": {[[0,0,false]]};
				case "LOOP": {[[0,0,false],[2,2,false],[3,2,true],[4,2,true],[5,2,true],[7,0,true]]};
				case "FUSE": {[[2,0,true]]};
				case "STATE": {[[15,0,true]]};
				case "STRIKE": {
					if ((_data # 0) == "THROTTLED") then {[[1,0,true]]} else {
						if ((_data # 0) == "PROPOSED") then {[[3,0,true]]} else {[]}
					}
				};
				default {[]};
			};
			{
				_x params ["_field", "_domain", "_deadline"];
				private _value = _data # _field;
				if (!_deadline || {_value > 0}) then {
					_data set [_field, [["@diag","@server","@mission"] # _domain, _value - (_bases # _domain)]];
				};
			} forEach _clockFields;
			if ((_row # 5) == "POSE") then {
				{_data set [_x, ["@frame", (_data # _x) - (_bases # 3)]];} forEach [3,4];
			};
			_row set [12, _data];
			private _line = [["A3UE_FPV_QA|", _row]] call _serialize;
			if (count _line <= 900) then {diag_log text _line;} else {
				// Lossless fragments retain one logical sequence, with bounded physical RPT lines.
				private _wire = [_row] call _serialize;
				private _parts = ceil (count _wire / 256);
				for "_part" from 0 to (_parts - 1) do {
					diag_log text ([["A3UE_FPV_QA_PART", 2, _cap get "id", clientOwner, _cap get "nonce",
						_row # 4, _part, _parts, _wire select [_part * 256,256]]] call _serialize);
				};
			};
			if (_forEachIndex mod 100 == 99) then {sleep 0.01;};
		} forEach _rows;
		diag_log text ([["A3UE_FPV_QA_EXPORT_DONE", 2, _cap get "id", clientOwner, _cap get "nonce",
			count _rows, _cap get "seq", _cap get "dropped"]] call _serialize);
		_cap set ["exported", true];
	};
	_cap set ["exportHandle", _worker];
	true
};
if (_action != "start" || {_id == ""} || {count _id > 128} || {count _drones > 3}
	|| {((toArray _id) findIf {_x < 32}) >= 0} || {_duration < 5} || {_duration > 180}) exitWith {diag_log "A3UE_FPV_QA capture BLOCKED: id, <=3 drones, duration 5..180 required"; false};
private _motion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]) exitWith {diag_log ["A3UE_FPV_QA_BLOCKED","MOTION_PREPARATION_BUSY"]; false};
if (count _motion > 0 && {!(_motion getOrDefault ["finished",false])}) exitWith {diag_log ["A3UE_FPV_QA_BLOCKED","MOTION_FIXTURE_BUSY"]; false};
private _old = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if (!isNil "A3UE_FPV_QA_sink" || {count _old > 0 && {!(_old getOrDefault ["exported", false])}}) exitWith {
	diag_log "A3UE_FPV_QA capture BLOCKED: stop old capture and wait for EXPORT_DONE"; false
};
private _bases = [diag_tickTime, serverTime, time, diag_frameNo];
private _serial = 1 + (missionNamespace getVariable ["A3UE_FPV_QA_captureSerial", 0]);
missionNamespace setVariable ["A3UE_FPV_QA_captureSerial", _serial];
private _cap = createHashMapFromArray [["id", _id], ["nonce", format ["%1:%2:%3:%4", (systemTimeUTC apply {_x toFixed 0}) joinString "-", (_bases # 3) toFixed 0, (_bases # 0) toFixed 6, _serial toFixed 0]],
	["bases", _bases],
	["drones", _drones], ["rows", []], ["seq", 0], ["dropped", 0], ["limit", 60000], ["active", true],
	["started", _bases # 0], ["until", (_bases # 0) + _duration], ["nextSample", 0], ["nextSlow", 0],
	["nextSteering", 0], ["lastSample", -1], ["maxSampleGap", 0], ["sampleMisses", 0], ["hooks", []], ["hooked", []], ["exported", false]];
// At most two explicitly retained fixture targets; never scan the world for evidence.
private _targets = (missionNamespace getVariable ["A3UE_FPV_QA_observedTargets",[]]) select [0,2];
_cap set ["observedTargets",(_targets select {_x isEqualType objNull && {!isNull _x}}) apply {[_x,netId _x,+crew _x]}];
private _captureReserved = false;
isNil {
	if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]
		|| {private _latestMotion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap]; count _latestMotion > 0 && {!(_latestMotion getOrDefault ["finished",false])}}) exitWith {};
	missionNamespace setVariable ["A3UE_FPV_QA_captureState", _cap];
	_captureReserved = true;
};
if (!_captureReserved) exitWith {diag_log ["A3UE_FPV_QA_BLOCKED","MOTION_PREPARATION_OR_FIXTURE_RACE"]; false};
A3UE_FPV_QA_sink = {
	params ["_u", "_kind", "_data"];
	private _c = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
	if (count _c == 0 || {!(_c get "active")} || {!isNull _u && {!(_u in (_c get "drones"))}}) exitWith {};
	// Atomic append only; no scans, movement, debug snapshot or network writes.
	isNil {
		if (!(_c get "active")) exitWith {};
		private _seq = 1 + (_c get "seq"); _c set ["seq", _seq];
		private _rows = _c get "rows";
		if (count _rows >= (_c get "limit") && {_kind != "END"}) then {
			_c set ["dropped", 1 + (_c get "dropped")];
		} else {
			_rows pushBack [2, _c get "id", clientOwner, _c get "nonce", _seq, _kind, diag_tickTime - ((_c get "bases") # 0), serverTime - ((_c get "bases") # 1),
				diag_frameNo - ((_c get "bases") # 3), if (isNull _u) then {""} else {_u getVariable ["A3UE_FPV_netId", netId _u]},
				if (isNull _u) then {-1} else {_u getVariable ["A3UE_FPV_controllerGeneration", -1]},
				if (isNull _u) then {""} else {_u getVariable ["A3UE_FPV_mode", ""]}, _data];
		};
	};
};
[objNull, "START", ["ua-dive-v2", isServer, hasInterface, productVersion, worldName, missionName,
	_duration, 0.02, 0.5, 60000, missionNamespace getVariable ["A3UE_FPV_debug", false], count _drones,
	[(_bases # 0) toFixed 6, (_bases # 1) toFixed 6, (_bases # 2) toFixed 6, (_bases # 3) toFixed 0]]] call A3UE_FPV_QA_sink;
private _eh = addMissionEventHandler ["EachFrame", {
	private _c = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
	if (count _c == 0 || {!(_c get "active")}) exitWith {};
	private _now = diag_tickTime;
	if (_now >= (_c get "until")) exitWith {["stop", "", [], 60, "duration"] call compileScript ["scripts\ua_dive\capture.sqf"];};
	if (_now < (_c get "nextSample")) exitWith {};
	private _last = _c get "lastSample";
	private _gap = if (_last < 0) then {0} else {_now - _last};
	_c set ["maxSampleGap", (_c get "maxSampleGap") max _gap];
	_c set ["sampleMisses", (_c get "sampleMisses") + ((floor (_gap / 0.02) - 1) max 0)];
	_c set ["lastSample", _now]; _c set ["nextSample", _now + 0.02];
	private _steeringDue = _now >= (_c get "nextSteering");
	if (_steeringDue) then {_c set ["nextSteering", _now + 0.1];};
    private _trajectoryDue = _now >= (_c getOrDefault ["nextTrajectory",0]);
    if (_trajectoryDue) then {_c set ["nextTrajectory",_now + 0.2];};
	private _slow = _now >= (_c get "nextSlow");
	if (_slow) then {
        _c set ["nextSlow", _now + 0.5];
        {
            _x params ["_target","_id","_crew"];
            [objNull,"HUNT_TARGET",[_id,getPosASL _target,velocity _target,alive _target,damage _target,
                (_crew select [0,2]) apply {[netId _x,alive _x,damage _x]}]] call A3UE_FPV_QA_sink;
        } forEach (_c getOrDefault ["observedTargets",[]]);
    };
	{
		private _u = _x;
		if (isNull _u) then {continue;};
		_u setVariable ["A3UE_FPV_QA_capture", true];
		if (!(_u in (_c get "hooked"))) then {
			(_c get "hooked") pushBack _u;
			[_u, "IDENTITY", [typeOf _u, _u getVariable ["A3UE_FPV_lifecycleId", -1],
				_u getVariable ["A3UE_FPV_lifecycleEpisode", -1], _u getVariable ["A3UE_FPV_vendorId", ""],
				_u getVariable ["A3UE_FPV_payloadRole", ""], _u getVariable ["A3UE_FPV_ammoClass", ""],
				_u getVariable ["A3UE_FPV_siteMarker", ""], _u getVariable ["A3UE_FPV_rivalEventId", ""]]] call A3UE_FPV_QA_sink;
			{
				private _event = _x;
				private _code = switch (_event) do {
					case "EpeContactStart": {{params ["_u", "_other"]; [_u, "CONTACT", [netId _other, typeOf _other]] call A3UE_FPV_QA_sink;}};
					case "Local": {{params ["_u", "_local"]; [_u, "LOCALITY", [_local, owner _u]] call A3UE_FPV_QA_sink;}};
					case "Killed": {{params ["_u"]; [_u, "KILLED", []] call A3UE_FPV_QA_sink;}};
					default {{params ["_u"]; [_u, "DELETED", []] call A3UE_FPV_QA_sink;}};
				};
				private _id = _u addEventHandler [_event, _code];
				(_c get "hooks") pushBack [_u, _event, _id];
			} forEach ["EpeContactStart", "Local", "Killed", "Deleted"];
		};
		[_u, "SAMPLE", [getPosASL _u, velocity _u, diag_fps, diag_deltaTime, _gap, local _u, owner _u,
			_u getVariable ["A3UE_FPV_targetNetId", ""], _u getVariable ["A3UE_FPV_linkState", ""],
			_u getVariable ["A3UE_FPV_signalStrength", -1]]] call A3UE_FPV_QA_sink;
        if (_trajectoryDue) then {
            private _trajectory = _u getVariable ["A3UE_FPV_trajectory",[]];
            private _summary = [-1,[],0,0,0];
            if (count _trajectory == 7 && {count (_trajectory # 6) == 8}) then {
                private _plan = _trajectory # 6;
                _summary = [time - (_trajectory # 1),+(_plan # 4),_plan # 5,_plan # 6,_plan # 2 # 0];
            };
            // Last reconstruction is latched once at reset, not a sampled claim about the held state.
            private _seed = +(_u getVariable ["A3UE_FPV_steeringReconstruction",[]]);
            if (count _seed == 8) then {_seed set [1,time - (_seed # 1)]; _seed set [2,_now - (_seed # 2)];};
            [_u,"TRAJECTORY",[1,_summary,_u getVariable ["A3UE_FPV_trajectoryReason","NONE"],_seed]] call A3UE_FPV_QA_sink;
            // Opt-in read-only phase cue on the same 5-Hz capture tick; no new worker.
            // Display only; transition evidence stays in the bounded deferred buffer.
            if (hasInterface && {missionNamespace getVariable ["A3UE_FPV_QA_phaseCue",false]} && {_forEachIndex == 0}) then {
                private _display = findDisplay 312;
                if (isNull _display) then {_display = findDisplay 46;};
                private _control = _c getOrDefault ["phaseCueControl",controlNull];
                if (!isNull _display && {isNull _control || {ctrlParent _control isNotEqualTo _display}}) then {
                    if (!isNull _control) then {ctrlDelete _control;};
                    _control = _display ctrlCreate ["RscStructuredText",-1];
                    _control ctrlSetPosition [safeZoneX + 0.02,safeZoneY + 0.05,0.75,0.13];
                    _control ctrlSetBackgroundColor [0,0,0,0.8];
                    _control ctrlCommit 0;
                    _c set ["phaseCueControl",_control];
                };
                private _mode = _u getVariable ["A3UE_FPV_mode",""];
                private _controlled = [_u] call A3UE_fnc_fpv_isExternallyControlled;
                private _target = objectFromNetId (_u getVariable ["A3UE_FPV_targetNetId",""]);
                private _managed = _mode == "TERMINAL_VECTOR" && {count (_u getVariable ["A3UE_FPV_terminalSteeringState",[]]) == 12}
                    // This F2 candidate has one managed purpose: acquired-target attack.
                    && {_u getVariable ["A3UE_FPV_terminalSteeringActive",false]}
                    && {time >= (_u getVariable ["A3UE_FPV_terminalVectorLastUpdateAt",-1])}
                    && {time - (_u getVariable ["A3UE_FPV_terminalVectorLastUpdateAt",-1]) <= 0.15}
                    && {[_u,+(_u getVariable ["A3UE_FPV_controllerIdentity",[]])] call A3UE_fnc_fpv_canActuate};
                private _phase = "WAIT: ordinary search / recovery";
                if (_managed) then {_phase = "MANAGED ATTACK ACTIVE";};
                if (_controlled) then {_phase = "CONTROL ACTIVE: release promptly with *"; _c set ["cueControlSeen",true];};
                if (!_controlled && {_c getOrDefault ["cueControlSeen",false]}) then {_phase = "RELEASED: observe reconstruction / recovery";};
                if (_u getVariable ["A3UE_FPV_detonationCommitted",false] || {!alive _u}) then {_phase = "SPENT / DEAD: no subsequent attack test";};
                if (_phase != (_c getOrDefault ["cuePhase",""])) then {
                    [_u,"PHASE_CUE",[_phase,netId _target]] call A3UE_FPV_QA_sink;
                    _c set ["cuePhase",_phase];
                };
                if (!isNull _control) then {
                    _control ctrlSetStructuredText parseText format ["<t size='1.1' color='#ffe080'>F2R %1</t><br/>UAV %2 | target %3 | range %4 m | serial %5",_phase,netId _u,netId _target,
                        if (isNull _target) then {-1} else {round (_u distance _target)},_u getVariable ["A3UE_FPV_terminalSteeringSerial",0]];
                };
            };

        };
        if (_steeringDue) then {
            private _state = _u getVariable ["A3UE_FPV_terminalSteeringState", []];
            private _logical = [];
            if (_state isEqualType [] && {count _state == 12}
                && {(_state # 0) isEqualType []} && {count (_state # 0) == 9}
                && {((_state # 0) # 1) isEqualType objNull}
                && {((_state # 0) # 4) isEqualType []} && {count ((_state # 0) # 4) == 3}
                && {((_state # 0) # 6) isEqualType []} && {count ((_state # 0) # 6) == 3}
                && {(((_state # 0) # 6) # 1) isEqualType objNull}) then {
                private _key = +(_state # 0);
                _key set [1, netId (_key # 1)];
                private _intent = +(_key # 6);
                _intent set [1, netId (_intent # 1)];
                _key set [6, _intent];
                private _site = +(_key # 4);
                _site set [2, str (_site # 2)];
                _key set [4, _site];
                // Durations only inside nested state; absolute clocks are top-level tagged fields.
                _logical = [_key, _state # 3, _state # 4, _state # 5, _state # 6,
                    _state # 7, _state # 8, _state # 9, _state # 10, _state # 11,
                    time - (_state # 1), _now - (_state # 2)];
            };
            [_u, "STEERING", [1, _logical, time, _now, getPosASL _u, velocity _u,
                vectorDir _u, vectorUp _u, local _u, [_u] call A3UE_fnc_fpv_isExternallyControlled,
                _u getVariable ["A3UE_FPV_controllerIdentity", []], _u getVariable ["A3UE_FPV_targetNetId", ""]]] call A3UE_FPV_QA_sink;
        };

		if (_slow) then {
			private _crew = crew _u;
			private _target = objectFromNetId (_u getVariable ["A3UE_FPV_targetNetId", ""]);
			[_u, "STATE", [isEngineOn _u, damage _u, simulationEnabled _u, alive _u,
				_u getVariable ["A3UE_FPV_lifecycleId", -1], _u getVariable ["A3UE_FPV_lifecycleEpisode", -1],
				_u getVariable ["A3UE_FPV_controllerIdentity", []],
				_crew apply {[netId _x, local _x, owner _x, alive _x, _x checkAIFeature "PATH", _x checkAIFeature "FSM", _x checkAIFeature "AUTOCOMBAT", _x checkAIFeature "MOVE"]},
				[_u] call A3UE_fnc_fpv_isExternallyControlled, (UAVControl _u) apply {if (_x isEqualType objNull) then {netId _x} else {_x}},
				_u getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""], _u getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
				_u getVariable ["A3UE_FPV_terminalImpactMode", ""], _u getVariable ["A3UE_FPV_detonating", false],
				_u getVariable ["A3UE_FPV_engagementFailureReason", ""], _u getVariable ["A3UE_FPV_nextDetonationRequestAt", 0],
				getPosASL _target, velocity _target, _crew apply {if (local _x) then {netId (remoteControlled _x)} else {"NONLOCAL"}},
				behaviour driver _u, speedMode group driver _u, combatMode group driver _u,
				count (_u getVariable ["A3UE_FPV_lifecycleTicket", []]) == 3,
				_u getVariable ["A3UE_FPV_lifecycleClaimFailure", ""], _u getVariable ["A3UE_FPV_controllerRunning", false],
				scriptDone (_u getVariable ["A3UE_FPV_controllerHandle", scriptNull]), _u getVariable ["A3UE_FPV_startedGeneration", -1]]] call A3UE_FPV_QA_sink;
		};
	} forEach (_c get "drones");
}];
_cap set ["eh", _eh];
true
