// Pure F4-1 correction program (the pilot's fine-tuning). Degrees and seconds.
// [segmentEnds, yawFractions, pitchFractions, blendSeconds, elapsed, timeToGo, weaveScale,
//  envelopeEnd, envelopeStart] -> [yawDeg, pitchDeg, envelope]
// Each segment holds one aim error; the change between segments is a smoothstep over
// blendSeconds. The error is at most 8 deg far out and 3 deg in the last second, and the
// envelope fades it to zero between envelopeStart and envelopeEnd seconds to go
// (envelope 1 = full weave, 0 = converged on the pass intent point).
params ["_ends", "_yaw", "_pitch", "_blend", "_elapsed", "_timeToGo", "_scale", "_tEnd", "_tStart"];
private _count = count _ends;
if (_count == 0 || {count _yaw != _count} || {count _pitch != _count}) exitWith {[0, 0, 0]};
private _now = _elapsed max 0;
private _index = _ends findIf {_now < _x};
if (_index < 0) then {_index = _count - 1;};
private _segmentStart = if (_index == 0) then {0} else {_ends # (_index - 1)};
private _fromYaw = if (_index == 0) then {0} else {_yaw # (_index - 1)};
private _fromPitch = if (_index == 0) then {0} else {_pitch # (_index - 1)};
private _u = (((_now - _segmentStart) / (_blend max 0.05)) max 0) min 1;
_u = _u * _u * (3 - 2 * _u);
private _yawFraction = _fromYaw + ((_yaw # _index) - _fromYaw) * _u;
private _pitchFraction = _fromPitch + ((_pitch # _index) - _fromPitch) * _u;
private _yawMax = (3 + 5 * ((((_timeToGo - 1) / 4) max 0) min 1)) * _scale;
private _envelope = (((_timeToGo - _tEnd) / ((_tStart - _tEnd) max 0.05)) max 0) min 1;
_envelope = _envelope * _envelope * (3 - 2 * _envelope);
[_yawFraction * _yawMax * _envelope, _pitchFraction * 2 * _scale * _envelope, _envelope]
