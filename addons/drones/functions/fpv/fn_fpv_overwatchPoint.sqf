// Pure LT-2 overwatch geometry. A waiting drone watches its target from a ring: it is ordered to
// the ring point 45 degrees ahead of where it is now, so it never arrives and keeps flying
// (about 7 s of flight ahead, which a late controller pass cannot use up). Each drone has a
// fixed place from its own number: one of three rings 15 m apart (the middle one flown the other
// way round) and one of four heights 6 m apart, so drones on a ring follow each other and never
// meet head on. From far outside the ring the lead shrinks and the drone flies in.
// The ring is centred 2 s ahead of a moving target. Metres, m/s, degrees.
// [uavPosASL, targetPosASL, targetVelocity, baseRadius, drone number]
//   -> [x, y, extra height m, ring speed m/s, on the ring (bool)]
params ["_uavPos", "_targetPos", "_targetVelocity", "_baseRadius", "_index"];
_index = (floor _index) max 0;
private _radius = _baseRadius + 15 * (_index mod 3);
private _turn = [1, -1] select ((_index mod 3) mod 2);
private _centre = [(_targetPos # 0) + 2 * (_targetVelocity # 0), (_targetPos # 1) + 2 * (_targetVelocity # 1), 0];
private _relative = [(_uavPos # 0) - (_centre # 0), (_uavPos # 1) - (_centre # 1), 0];
private _range = vectorMagnitude _relative;
private _bearing = if (_range > 1) then {(_relative # 0) atan2 (_relative # 1)} else {(120 * _index) mod 360};
private _lead = 45 * (((1.5 * _radius) / (_range max _radius)) min 1);
private _aim = _bearing + _turn * _lead;
private _targetSpeed = vectorMagnitude [_targetVelocity # 0, _targetVelocity # 1, 0];
[(_centre # 0) + _radius * (sin _aim), (_centre # 1) + _radius * (cos _aim), 6 * (_index mod 4),
	((_targetSpeed + 8) max 14) min 40, _range <= _radius + 80]
