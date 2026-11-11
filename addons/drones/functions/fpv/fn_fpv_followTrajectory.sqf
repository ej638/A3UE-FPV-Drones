// Pure, bounded actual-position feedback against eight cached corridor segments.
params ["_plan", "_position", "_speed", "_limits"];
if (count _plan != 8 || {!(_plan # 0)}) exitWith {[]};
private _points = _plan # 1;
private _caps = _plan # 2;
private _bestDistance = 1e12;
private _progress = 0;
private _walked = 0;
private _cap = _caps # 0;
for "_i" from 0 to 7 do {
    private _start = _points # _i;
    private _delta = (_points # (_i + 1)) vectorDiff _start;
    private _length = vectorMagnitude _delta;
    if (_length > 1e-6) then {
        private _fraction = (((_position vectorDiff _start) vectorDotProduct _delta) / (_length * _length) max 0) min 1;
        private _onPath = _start vectorAdd (_delta vectorMultiply _fraction);
        private _error = _onPath vectorDistance _position;
        if (_error < _bestDistance) then {
            _bestDistance = _error;
            _progress = _walked + _fraction * _length;
            // Use the stricter endpoint cap; never interpolate above an interval bound.
            _cap = (_caps # _i) min (_caps # (_i + 1));
        };
    };
    _walked = _walked + _length;
};
private _lookahead = ((_speed * (_limits # 7)) max 4) min 18;
private _wanted = (_progress + _lookahead) min (_plan # 3);
private _aim = +(_points # 8);
_walked = 0;
for "_i" from 0 to 7 do {
    private _length = (_points # _i) vectorDistance (_points # (_i + 1));
    if (_wanted >= _walked && {_wanted <= _walked + _length} && {_length > 1e-6}) then {
        _aim = (_points # _i) vectorAdd (((_points # (_i + 1)) vectorDiff (_points # _i)) vectorMultiply ((_wanted - _walked) / _length));
    };
    _walked = _walked + _length;
};
private _delta = _aim vectorDiff _position;
if (vectorMagnitude _delta < 0.01 || {_bestDistance > 6}) exitWith {[]};
[vectorNormalized _delta, _cap, _progress, _bestDistance, _aim]
