// Server-only structural regression. Copy to the disposable mission's scripts/
// folder and execute [] execVM "scripts\f02_support_outcomes.sqf" on the server.
// This deliberately bypasses detonation/transport and cannot certify that path.
if (!isServer) exitWith {false};

isNil {
	private _oldFailureReason = missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", nil];
	private _scenarios = [
		[[[0, "finished", "FIXTURE_STRIKE"], [1, "failed", "mpkilled"]], "failed", "PARTIAL_LOSS", false],
		[[[1, "failed", "deleted"], [0, "finished", "FIXTURE_STRIKE"]], "failed", "PARTIAL_LOSS", false],
		[[[0, "finished", "cleanup"], [1, "failed", "deleted"]], "failed", "PARTIAL_LOSS", false],
		[[[1, "failed", "mpkilled"], [0, "finished", "cleanup"]], "failed", "PARTIAL_LOSS", false],
		[[[0, "failed", "deleted"], [1, "failed", "mpkilled"]], "failed", "DRONE_LOST", true],
		[[[1, "finished", "cleanup"], [0, "finished", "cleanup"]], "finished", "cleanup", false]
	];
	private _failures = 0;
	{
		_x params ["_events", "_expectedStatus", "_expectedReason", "_deleteBoth"];
		private _name = format ["QA_F02_%1_%2", diag_tickTime, _forEachIndex];
		private _vehicles = [
			createVehicle ["B_UAV_01_F", [50, 50, 1000], [], 0, "CAN_COLLIDE"],
			createVehicle ["B_UAV_01_F", [60, 50, 1000], [], 0, "CAN_COLLIDE"]
		];
		private _ids = _vehicles apply {netId _x};
		private _marker = createMarker [_name, [50, 50, 0]];
		_marker setMarkerShape "ELLIPSE";
		private _entry = createHashMapFromArray [
			["status", "active"], ["drones", +_vehicles], ["droneNetIds", +_ids], ["searchMarker", _marker]
		];
		A3UE_FPV_supportRegistry set [_name, _entry];
		A3UE_FPV_supportTransientMarkers pushBack _marker;
		A3A_activeSupports pushBack [_name, east, "FPV", [50, 50, 0], 350, [], 0];
		if (_deleteBoth) then {
			{deleteVehicle _x;} forEach _vehicles;
			// Actual deletion is next-frame work. Manufacture null registry refs
			// here to isolate the cached-ID contract without claiming delivery.
			_entry set ["drones", [objNull, objNull]];
		};
		private _ok = true;
		{
			_x params ["_index", "_status", "_reason"];
			private _accepted = [_name, _status, _reason, _ids # _index] call A3UE_fnc_fpv_supportFinalize;
			_ok = _ok && {_accepted};
			if (_forEachIndex == 0) then {
				_ok = _ok && {count (_entry get "droneNetIds") == 1} && {!("finishedAt" in _entry)} && {markerShape _marker != ""};
				private _outcomesBefore = str (_entry get "droneOutcomes");
				private _duplicate = [_name, "failed", "LATE_DUPLICATE", _ids # _index] call A3UE_fnc_fpv_supportFinalize;
				_ok = _ok && {!_duplicate} && {_outcomesBefore == str (_entry get "droneOutcomes")};
			};
		} forEach _events;
		private _before = ["status", "finishedAt", "lastCleanupReason", "lastFailureReason", "droneOutcomes"] apply {str (_entry getOrDefault [_x, "ABSENT"])};
		private _late = [_name, "failed", "LATE_FORCE", "", true] call A3UE_fnc_fpv_supportFinalize;
		private _after = ["status", "finishedAt", "lastCleanupReason", "lastFailureReason", "droneOutcomes"] apply {str (_entry getOrDefault [_x, "ABSENT"])};
		private _active = A3A_activeSupports select {(_x # 0) == _name};
		_ok = _ok && {!_late} && {_before isEqualTo _after}
			&& {(_entry get "status") == _expectedStatus} && {(_entry get "lastCleanupReason") == _expectedReason}
			&& {count (_entry get "droneOutcomes") == 2} && {(_entry get "droneNetIds") isEqualTo []}
			&& {markerShape _marker == ""} && {!(_marker in A3UE_FPV_supportTransientMarkers)}
			&& {count _active == 1 && {((_active # 0) # 4) == 0}};
		if (!_ok) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST F02] STRUCTURAL case=%1 pass=%2 entry=%3", _forEachIndex, _ok, _entry];
		{if (!isNull _x) then {deleteVehicle _x;};} forEach _vehicles;
		deleteMarker _marker;
		A3UE_FPV_supportTransientMarkers = A3UE_FPV_supportTransientMarkers select {_x != _marker};
		private _retention = _entry getOrDefault ["retentionHandle", scriptNull];
        if !(scriptDone _retention) then {terminate _retention;};
		A3UE_FPV_supportRegistry deleteAt _name;
		A3A_activeSupports = A3A_activeSupports select {(_x # 0) != _name};
	} forEach _scenarios;
	diag_log format ["[A3UE FPV TEST F02] STRUCTURAL complete=6 failures=%1 (not detonation evidence)", _failures];
	missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", if (isNil "_oldFailureReason") then {nil} else {_oldFailureReason}];
};
true
