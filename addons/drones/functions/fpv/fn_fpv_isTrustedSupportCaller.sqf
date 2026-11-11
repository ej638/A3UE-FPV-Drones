// Request-time role check only; this does not authorize lifecycle reports or callbacks.
params [["_allowAdmin", false]];

if (!isServer) exitWith {false};
// Support/attack requests are transient, never persistent JIP work.
if (isRemoteExecutedJIP) exitWith {false};
if (!isRemoteExecuted) exitWith {true};

private _sender = remoteExecutedOwner;
if (_sender == 2) exitWith {true};

// AU registers HC IDs in hcArray. Cross-check live engine HC objects so stale
// registrations (or a human ID inserted in hcArray) cannot grant the HC role.
private _registeredHCs = missionNamespace getVariable ["hcArray", []];
if !(_registeredHCs isEqualType []) then {_registeredHCs = [];};
private _hasTrustedHC = (entities "HeadlessClient_F") findIf {
	private _hcOwner = owner _x;
	_hcOwner > 2 && {_hcOwner in _registeredHCs} && {_sender == 0 || {_sender == _hcOwner}}
} > -1;
// The engine reports HC-origin remote execution as zero. Zero alone is not
// sufficient: require a connected, AU-registered HC and the AU dispatch check
// at SUP_FPV. HCs are trusted AU coordinators, not untrusted human clients.
if (_hasTrustedHC) exitWith {true};

_allowAdmin && {_sender > 2} && {admin _sender == 2}
