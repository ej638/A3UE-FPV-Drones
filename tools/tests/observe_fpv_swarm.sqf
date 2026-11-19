/*
    Hosted Antistasi QA session. Paste into the debug console and use Local Exec
    before calling a swarm. Open the map for numbered tracks and Zeus for unit
    icons. Run again to stop recording and clear the local tracks.
*/
if (!hasInterface || {!isServer}) exitWith {};

private _observer = missionNamespace getVariable ["A3UE_FPV_QA_observer", []];
if (_observer isNotEqualTo []) exitWith {
    _observer params ["_handle", "_markers"];
    terminate _handle;
    { deleteMarkerLocal _x; } forEach _markers;
    missionNamespace setVariable ["A3UE_FPV_QA_observer", nil];
    systemChat "FPV observer stopped and trails cleared.";
};

private _curator = getAssignedCuratorLogic player;
if (isNull _curator) exitWith { systemChat "FPV observer needs the host's assigned Zeus slot."; };

private _markers = [];
private _handle = [_curator, _markers] spawn {
    params ["_curator", "_markers"];
    private _colors = ["ColorYellow", "ColorOrange", "ColorPink", "ColorCIV", "ColorBlue", "ColorGreen", "ColorRed"];
    private _tracks = createHashMap;
    private _swarm = "";
    private _nextCuratorUpdate = 0;

    while { true } do {
        if (diag_tickTime >= _nextCuratorUpdate) then {
            private _units = (allUnits + vehicles) select { alive _x };
            private _new = _units - (curatorEditableObjects _curator);
            if (_new isNotEqualTo []) then { _curator addCuratorEditableObjects [_new, false]; };
            _nextCuratorUpdate = diag_tickTime + 2;
        };

        {
            private _drone = _x;
            private _swarmId = _drone getVariable ["A3UE_FPV_swarmId", ""];
            if (alive _drone && {_swarmId isNotEqualTo ""} && {_swarm in ["", _swarmId]}) then {
                _swarm = _swarmId;
                private _position = getPosATL _drone;
                private _id = netId _drone;
                private _track = _tracks getOrDefault [_id, []];
                if (_track isEqualTo []) then {
                    private _number = count _tracks + 1;
                    private _label = format ["FPV %1", _number];
                    private _name = format ["A3UE_FPV_QA_%1_%2", _swarm, _number];
                    private _dot = createMarkerLocal [_name, _position];
                    private _line = createMarkerLocal [_name + "_path", _position];
                    private _color = _colors select ((_number - 1) mod (count _colors));
                    _dot setMarkerTypeLocal "mil_triangle";
                    _dot setMarkerColorLocal _color;
                    _line setMarkerShapeLocal "POLYLINE";
                    _line setMarkerColorLocal _color;
                    _markers append [_dot, _line];
                    _track = [_dot, _line, _label, [], _drone, false];
                    _tracks set [_id, _track];
                };
                _track params ["_dot", "_line", "_label", "_path"];
                _path append [_position # 0, _position # 1];
                if (count _path >= 4) then { _line setMarkerPolylineLocal _path; };
                _dot setMarkerPosLocal _position;
                _dot setMarkerDirLocal (getDir _drone);
                _dot setMarkerTextLocal format ["%1 · %2 m AGL", _label, round (_position # 2)];
            };
        } forEach vehicles;

        {
            _y params ["_dot", "", "_label", "", "_drone", "_ended"];
            if (!_ended && {!alive _drone}) then {
                _dot setMarkerTextLocal (_label + " (last seen)");
                _dot setMarkerAlphaLocal 0.65;
                _y set [5, true];
            };
        } forEach _tracks;

        uiSleep 0.5;
    };
};

missionNamespace setVariable ["A3UE_FPV_QA_observer", [_handle, _markers]];
systemChat "FPV observer ready. Open the map to see the next swarm's tracks.";
