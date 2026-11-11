// Matched on/off observer: LOCAL scheduled execVM, two FPS reads/second, one final RPT row.
params [["_label", "OFF"], ["_duration", 60]];
if (isRemoteExecuted || {!canSuspend} || {_duration < 5} || {_duration > 180}) exitWith {};
private _fps = [];
private _gaps = [];
private _until = diag_tickTime + _duration;
private _last = diag_tickTime;
while {diag_tickTime < _until} do {
	_fps pushBack diag_fps; _gaps pushBack (diag_tickTime - _last); _last = diag_tickTime;
	sleep 0.5;
};
_fps sort true; _gaps sort true;
diag_log ["UAQA FPS", _label, clientOwner, _duration, count _fps,
	_fps # (floor ((count _fps - 1) * 0.05)), _fps # (floor ((count _fps - 1) * 0.5)),
	selectMin _fps, selectMax _gaps, "P05/P50/min FPS; max sampler gap seconds"];
