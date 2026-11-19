// 1.0.9 friendly FPV swarm (SW-1e): the attitude writer shared by the swarm's cruise and its dive, so
// the airframe never jumps between them (SW1d, EJ: the dive "almost snaps to the dive position").
// - At the D1 cadence only: at least 3 frames and 0.05 s since the last write.
// - The nose along the path, tilted down with speed as a quad's is (0.8 degree per m/s, at most 20).
//   The tilt fades as the path steepens (cos squared of its angle), so a steep dive looks along its
//   path.
// - Level horizon and a bounded coordinated-turn bank (terminalPresentationUp).
// - SW-1f: at most "bank" degrees of it (the dive: EJ after SW1e, "a crazy twist together when they
//   started diving"; leading a walking man, SW-1e rolled 26 degrees and back in 0.75 s while its nose
//   went over). The sideways acceleration handed to the helper is scaled down to what that bank
//   shows; the helper's own limits (30 degrees, 90 deg/s) are the enemy drones' and stay as they are.
// [uav, path before (unit), path now (unit), speed m/s, step s, [poseAt, poseFrame, attitude], bank deg]
//   -> [poseAt, poseFrame, attitude] (unchanged when nothing was written)
params [["_uav", objNull], ["_path", []], ["_newPath", []], ["_speed", 0], ["_dt", 0], ["_pose", []], ["_bankMax", 30]];
_pose params [["_poseAt", -1], ["_poseFrame", -10], ["_attitude", []]];
private _now = time;
if (_dt <= 0 || {(_now - _poseAt) < 0.05} || {(diag_frameNo - _poseFrame) < 3}) exitWith {[_poseAt, _poseFrame, _attitude]};
if !(_path isEqualType [] && {count _path == 3} && {_newPath isEqualType []} && {count _newPath == 3}) exitWith {[_poseAt, _poseFrame, _attitude]};
private _rate = (_path vectorCrossProduct _newPath) vectorMultiply (1 / _dt);
private _flat = sqrt (((_newPath # 0) ^ 2) + ((_newPath # 1) ^ 2));
private _nose = +_newPath;
if (_flat > 0.05) then {
	private _elevation = asin (((_newPath # 2) max -1) min 1);
	private _tilt = ((_speed * 0.8) min 20) * ((cos _elevation) ^ 2);
	private _noseElevation = (_elevation - _tilt) max -89.5;
	_nose = [((_newPath # 0) / _flat) * (cos _noseElevation), ((_newPath # 1) / _flat) * (cos _noseElevation), sin _noseElevation];
};
if (_bankMax isEqualType 0 && {finite _bankMax} && {_bankMax >= 0} && {_bankMax < 30} && {_flat > 0.05}) then {
	private _right = vectorNormalized [_nose # 1, -(_nose # 0), 0];
	private _lateral = _speed * ((_rate vectorCrossProduct _nose) vectorDotProduct _right);
	private _most = 9.81 * (tan _bankMax);
	if ((abs _lateral) > _most) then {_rate = _rate vectorMultiply (_most / (abs _lateral));};
};
private _up = [_nose, _rate, _speed, _attitude, _now - _poseAt] call A3UE_fnc_fpv_terminalPresentationUp;
if (_up isEqualTo []) exitWith {[_poseAt, _poseFrame, _attitude]};
_uav setVectorDirAndUp [_nose, _up # 0];
[_now, diag_frameNo, _up # 1]
