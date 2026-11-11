if (!hasInterface) exitWith {false};

// Bind the three connected APIs together; native code retains HUD/PFH/FX lifetime.
// Retry at registration/bootstrap without a waiter or another render loop.
isNil {
	if (!(missionNamespace getVariable ["A3UE_FPV_crocusSignalAdapterInstalled", false])
		&& {!isNil "DB_fnc_fpv_getSignal"} && {DB_fnc_fpv_getSignal isEqualType {}}
		&& {!isNil "DB_fnc_fpv_ppfx_setInput"} && {DB_fnc_fpv_ppfx_setInput isEqualType {}}
		&& {!isNil "DB_fnc_fpv_onSignalLost"} && {DB_fnc_fpv_onSignalLost isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_crocusNativeGetSignal", DB_fnc_fpv_getSignal];
		missionNamespace setVariable ["A3UE_FPV_crocusNativePpfxSetInput", DB_fnc_fpv_ppfx_setInput];
		missionNamespace setVariable ["A3UE_FPV_crocusNativeOnSignalLost", DB_fnc_fpv_onSignalLost];
		DB_fnc_fpv_getSignal = {
			params ["_player", "_uav"];
			private _input = [_uav] call A3UE_fnc_fpv_getCrocusSignalContext;
			if (_input isEqualTo []) exitWith {_this call (missionNamespace getVariable "A3UE_FPV_crocusNativeGetSignal")};
			private _context = _input # 1;
			// Current supported fields, client-local only; no owner/native writer race.
			{
				_x params ["_key", "_index"];
				_uav setVariable [_key, _context # _index];
			} forEach [["DB_fpv_signalMaxDistance", 5], ["DB_fpv_inJammer", 7],
				["DB_fpv_jammerFactor", 9], ["DB_fpv_signalObstacles", 11], ["DB_fpv_signalTerrainMask", 13]];
			// Direct takeover starts native exposure at its first native sample.
			_uav setVariable ["DB_fpv_lastSignalUpdate", nil];
			_uav setVariable ["DB_fpv_timeInJammerZone", 0];
			_uav setVariable ["DB_fpv_jammerLowTime", 0];
			_input # 0
		};
		DB_fnc_fpv_ppfx_setInput = {
			private _player = missionNamespace getVariable ["bis_fnc_moduleRemoteControl_unit", player];
			private _uav = getConnectedUAV _player;
			private _input = [_uav] call A3UE_fnc_fpv_getCrocusSignalContext;
			if (_input isEqualTo []) exitWith {_this call (missionNamespace getVariable "A3UE_FPV_crocusNativePpfxSetInput")};
			// Native handleSignal constructs operator distance even after getSignal.
			// Replace the entire context so PPFX uses the same site/relay source.
			_input call (missionNamespace getVariable "A3UE_FPV_crocusNativePpfxSetInput")
		};
		DB_fnc_fpv_onSignalLost = {
			params ["_player", "_uav"];
			// Passive HUD must not stop the managed engine or kill its virtual pilot.
			if (([_uav] call A3UE_fnc_fpv_getCrocusSignalContext) isNotEqualTo []) exitWith {};
			_this call (missionNamespace getVariable "A3UE_FPV_crocusNativeOnSignalLost")
		};
		missionNamespace setVariable ["A3UE_FPV_crocusSignalAdapterInstalled", true];
	};
};

missionNamespace getVariable ["A3UE_FPV_crocusSignalAdapterInstalled", false]
