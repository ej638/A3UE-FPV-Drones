// Thin AU 12.0.3 scheduler adapter; never copy or relocate the AU site bodies.
if (!isServer || {isRemoteExecuted && {remoteExecutedOwner != 2}} || {isRemoteExecutedJIP}) exitWith {false};
if (missionNamespace getVariable ["A3UE_FPV_siteHooksInstalled", false]) exitWith {
	private _matches = A3A_fnc_scheduler isEqualTo A3UE_fnc_fpv_scheduleSite;
	if (!_matches) then {diag_log "[A3UE_FPV] siteHooks conflict: scheduler replaced; not overwriting provider";};
	_matches
};
if (isNil "A3A_fnc_scheduler") exitWith {
	if (missionNamespace getVariable ["A3UE_FPV_siteHooksPending", false]) exitWith {false};
	missionNamespace setVariable ["A3UE_FPV_siteHooksPending", true];
	[] spawn {
		waitUntil {sleep 0.25; !isNil "A3A_fnc_scheduler"};
		missionNamespace setVariable ["A3UE_FPV_siteHooksPending", false];
		call A3UE_fnc_fpv_installSiteHooks;
	};
	false
};

private _installed = false;
isNil {
	if (missionNamespace getVariable ["A3UE_FPV_siteHooksInstalled", false]) exitWith {};
	if (isNil "A3UE_FPV_siteEpoch") exitWith {};
	if !(A3A_fnc_scheduler isEqualType {}) exitWith {};
	missionNamespace setVariable ["A3UE_FPV_originalScheduler", A3A_fnc_scheduler];
	A3A_fnc_scheduler = A3UE_fnc_fpv_scheduleSite;
	if !(A3A_fnc_scheduler isEqualTo A3UE_fnc_fpv_scheduleSite) exitWith {};
	missionNamespace setVariable ["A3UE_FPV_siteHooksInstalled", true];
	// This script is created at server registration, never by a remote intent.
	// F5-1b diagnostics: the worker is named and keeps its handle, a heartbeat at the start of
	// each pass and the pass result. Server-local variables only; queue behaviour is unchanged.
	missionNamespace setVariable ["A3UE_FPV_siteWorker", [] spawn {
		scriptName "A3UE_FPV_siteWorker";
		private _passes = 0;
		while {true} do {
			_passes = _passes + 1;
			missionNamespace setVariable ["A3UE_FPV_siteBeat", [diag_tickTime, _passes]];
			missionNamespace setVariable ["A3UE_FPV_siteStage", ["pass", "", diag_tickTime]];
			private _result = [call A3UE_fnc_fpv_processSiteQueue] param [0, "nil"];
			missionNamespace setVariable ["A3UE_FPV_siteLastResult", [_result, diag_tickTime]];
			sleep 1;
		};
	}];
	// F5-1b site monitor: reports, never restarts. One line when the worker's heartbeat goes
	// stale (STALE) or a queued site waits with no transaction (QUEUE_IDLE), one when that
	// clears (CLEAR); with debug, one summary line a minute. 5 s wake, a few reads per wake.
	[] spawn {
		scriptName "A3UE_FPV_siteMonitor";
		private _started = diag_tickTime;
		private _fault = "";
		private _summaryAt = 0;
		while {true} do {
			sleep 5;
			private _beat = missionNamespace getVariable ["A3UE_FPV_siteBeat", []];
			private _beatAge = diag_tickTime - (_beat param [0, _started]);
			private _queue = missionNamespace getVariable ["A3UE_FPV_siteQueue", createHashMap];
			private _queued = _queue isEqualType createHashMap && {count _queue > 0};
			private _txnAge = diag_tickTime - ((missionNamespace getVariable ["A3UE_FPV_siteLastTxn", []]) param [2, _started]);
			private _now = switch (true) do {
				case (_beatAge > 15): {"STALE"};
				case (_queued && {_txnAge > 15}): {"QUEUE_IDLE"};
				default {""};
			};
			if (_now != _fault) then {
				diag_log format ["[A3UE_FPV] siteMonitor %1 was=%2 probe=%3", ["CLEAR", _now] select (_now != ""), _fault, call A3UE_fnc_fpv_siteQueueProbe];
				_fault = _now;
			};
			if (missionNamespace getVariable ["A3UE_FPV_debug", false] && {diag_tickTime >= _summaryAt}) then {
				_summaryAt = diag_tickTime + 60;
				diag_log format ["[A3UE_FPV] siteMonitor beat probe=%1", call A3UE_fnc_fpv_siteQueueProbe];
			};
		};
	};
	_installed = true;
};
diag_log format ["[A3UE_FPV] siteHooks installed=%1: AU scheduler selection retained; server queue requires mutable scheduler", _installed];
_installed
